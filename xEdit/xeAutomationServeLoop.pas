{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeAutomationServeLoop;

interface

function xeAutomationServeLoopPipeName: string;
procedure xeAutomationServeLoopStart;
procedure xeAutomationServeLoopStop;
procedure xeAutomationServeLoopPoll;

implementation

uses
  xeAutomationCommandsCleaning,
  xeAutomationCommandsFileHygiene,
  xeAutomationCommandsJobs,
  xeAutomationCommandsPluginAnalysis,
  xeAutomationCommandsValidation,
  xeAutomationCommandsSession,
  xeAutomationCommandsSessionNavigation,
  Windows,
  Classes,
  SysUtils,
  xeAutomationCommandsElements,
  xeAutomationCommandsFiles,
  xeAutomationCommandsRecords,
  xeAutomationCommandsScripts,
  xeAutomationHostCli,
  xeAutomationTransportPipe;

const
  // ChildGroup element walks can legitimately return hundreds of flat record
  // stubs. Keep the message-pipe buffer above those response sizes so large
  // read-only enumerations do not get misreported as broken-pipe daemon failures.
  xeAutomationServeBufferSize = 4 * 1024 * 1024;

var
  xeAutomationServeActive: Boolean;
  xeAutomationServeCommandsRegistered: Boolean;
  xeAutomationServePipeNameValue: string;
  xeAutomationServePipeHandle: THandle = INVALID_HANDLE_VALUE;

function xeAutomationServeLoopPipeName: string;
begin
  Result := xeAutomationServePipeNameValue;
end;

procedure xeAutomationServeLoopResetPipe;
begin
  if xeAutomationPipeHandleIsOpen(xeAutomationServePipeHandle) then
    DisconnectNamedPipe(xeAutomationServePipeHandle);
  xeAutomationResetPipeHandle(xeAutomationServePipeHandle);
end;

procedure xeAutomationServeLoopEnsurePipe;
begin
  if xeAutomationPipeHandleIsOpen(xeAutomationServePipeHandle) then
    Exit;

  xeAutomationServePipeHandle := CreateNamedPipe(
    PChar(xeAutomationServePipeNameValue),
    PIPE_ACCESS_DUPLEX,
    PIPE_TYPE_MESSAGE or PIPE_READMODE_MESSAGE or PIPE_NOWAIT,
    1,
    xeAutomationServeBufferSize,
    xeAutomationServeBufferSize,
    0,
    nil
  );
  if not xeAutomationPipeHandleIsOpen(xeAutomationServePipeHandle) then
    RaiseLastOSError;
end;

function xeAutomationServeLoopTryConnectClient: Boolean;
var
  lError: Cardinal;
begin
  Result := ConnectNamedPipe(xeAutomationServePipeHandle, nil);
  if Result then
    Exit;

  lError := GetLastError;
  case lError of
    ERROR_PIPE_CONNECTED:
      Result := True;
    ERROR_PIPE_LISTENING:
      Result := False;
    ERROR_NO_DATA:
      begin
        // A previous client dropped its end before the server disconnected this
        // pipe instance. Reset now so the next poll can create a fresh listener.
        xeAutomationServeLoopResetPipe;
        Result := False;
      end;
  else
    RaiseLastOSError(lError);
  end;
end;

procedure xeAutomationServeLoopReadPipeBytes(out aBytes: TBytes);
var
  lBuffer: TBytes;
  lBytesRead: Cardinal;
  lError: Cardinal;
  lStream: TBytesStream;
begin
  SetLength(lBuffer, 4096);
  lStream := TBytesStream.Create;
  try
    repeat
      if ReadFile(xeAutomationServePipeHandle, lBuffer[0], Length(lBuffer), lBytesRead, nil) then begin
        if lBytesRead > 0 then
          lStream.WriteBuffer(lBuffer[0], lBytesRead);
        Break;
      end;

      lError := GetLastError;
      if lError <> ERROR_MORE_DATA then
        RaiseLastOSError(lError);

      if lBytesRead > 0 then
        lStream.WriteBuffer(lBuffer[0], lBytesRead);
    until False;

    aBytes := Copy(lStream.Bytes, 0, lStream.Size);
  finally
    lStream.Free;
  end;
end;

procedure xeAutomationServeLoopWritePipeBytes(const aBytes: TBytes);
var
  lError: Cardinal;
  lWritten: Cardinal;
begin
  if Length(aBytes) = 0 then
    Exit;

  if not WriteFile(xeAutomationServePipeHandle, aBytes[0], Length(aBytes), lWritten, nil) then begin
    lError := GetLastError;
    if lError in [ERROR_BROKEN_PIPE, ERROR_PIPE_NOT_CONNECTED, ERROR_NO_DATA] then begin
      // A client can disconnect after sending its request but before reading the
      // response. That should drop only this exchange, not terminate the daemon.
      xeAutomationServeLoopResetPipe;
      Exit;
    end;
    RaiseLastOSError(lError);
  end;

  if lWritten <> Cardinal(Length(aBytes)) then begin
    // External pipe clients can race close/read timing on the nonblocking
    // message pipe; treat peer loss as connection-local, not daemon-fatal.
    xeAutomationServeLoopResetPipe;
    Exit;
  end;
end;

function xeAutomationServeLoopTryReadRequest(out aRequestBytes: TBytes): Boolean;
var
  lBytesAvailable: Cardinal;
  lError: Cardinal;
begin
  Result := False;
  SetLength(aRequestBytes, 0);

  if not PeekNamedPipe(xeAutomationServePipeHandle, nil, 0, nil, @lBytesAvailable, nil) then begin
    lError := GetLastError;
    if lError in [ERROR_BROKEN_PIPE, ERROR_PIPE_NOT_CONNECTED] then begin
      xeAutomationServeLoopResetPipe;
      Exit(False);
    end;
    RaiseLastOSError(lError);
  end;

  if lBytesAvailable = 0 then
    Exit(False);

  xeAutomationServeLoopReadPipeBytes(aRequestBytes);
  Result := True;
end;

procedure xeAutomationServeLoopStart;
begin
  xeAutomationServeLoopStop;
  // Serve mode owns the loaded-data command surface. Register it exactly once
  // here, after xEdit finishes loading the real session, so one-shot CLI stays
  // stateless and duplicate registration mistakes still fail loudly.
  if not xeAutomationServeCommandsRegistered then begin
    xeAutomationRegisterSessionCommands;
    // Navigation is loaded-session-only because it drives the live main form
    // through xEdit's native JumpTo seam instead of a headless data lookup.
    xeAutomationRegisterSessionNavigationCommands;
    xeAutomationRegisterFilesCommands;
    // Loaded-data daemon sessions must expose file hygiene before any capabilities
    // probe, because direct callers may invoke these commands immediately by PID.
    xeAutomationRegisterFileHygieneCommands;
    // Plugin analysis is read-only but depends on loaded files, so daemon startup
    // wires it beside file hygiene before job commands/capabilities are queried.
    xeAutomationRegisterPluginAnalysisCommands;
    // Validation jobs are loaded-data read-only checks. Register them before the
    // job command facade so daemon capabilities and jobs.start agree immediately.
    xeAutomationRegisterValidationCommands;
    // 6D cleaning jobs share loaded xEdit state and must be registered before the
    // job facade so jobs.start and capabilities observe the same implemented set.
    xeAutomationRegisterCleaningCommands;
    xeAutomationRegisterRecordsCommands;
    xeAutomationRegisterElementsCommands;
    // Scripts run against loaded data and locator resolution, so expose them only
    // after the session/files/records/elements command surface has been wired.
    xeAutomationRegisterScriptsCommands;
    // Job commands are registered after file hygiene so the batch job kind is
    // visible to both lifecycle commands and the capabilities response.
    xeAutomationRegisterJobsCommands;
    xeAutomationServeCommandsRegistered := True;
  end;
  xeAutomationServeActive := True;
  xeAutomationServePipeNameValue := xeAutomationPipeNameForPid(GetCurrentProcessId);
  xeAutomationServeLoopEnsurePipe;
end;

procedure xeAutomationServeLoopStop;
begin
  xeAutomationServeActive := False;
  xeAutomationServeLoopResetPipe;
  xeAutomationServePipeNameValue := '';
end;

procedure xeAutomationServeLoopPoll;
var
  lRequestBytes: TBytes;
  lResponseText: string;
begin
  if not xeAutomationServeActive then
    Exit;

  xeAutomationServeLoopEnsurePipe;
  if not xeAutomationServeLoopTryConnectClient then
    Exit;

  if not xeAutomationServeLoopTryReadRequest(lRequestBytes) then
    Exit;

  try
    // Serve mode reuses the host request executor so CLI, call, and daemon paths
    // all share one request/response and error-envelope implementation.
    lResponseText := xeAutomationExecuteRequestText(TEncoding.UTF8.GetString(lRequestBytes));
    xeAutomationServeLoopWritePipeBytes(TEncoding.UTF8.GetBytes(lResponseText));
    FlushFileBuffers(xeAutomationServePipeHandle);
  finally
    xeAutomationServeLoopResetPipe;
  end;
end;

initialization
  xeAutomationServePipeHandle := INVALID_HANDLE_VALUE;

finalization
  xeAutomationServeLoopStop;
end.
