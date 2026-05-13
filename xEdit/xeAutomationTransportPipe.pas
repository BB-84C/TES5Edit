{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeAutomationTransportPipe;

interface

uses
  Windows,
  SysUtils;

function xeAutomationPipeNameForPid(const aPid: Cardinal): string;
function xeAutomationPipeHandleIsOpen(const aPipeHandle: THandle): Boolean;
procedure xeAutomationResetPipeHandle(var aPipeHandle: THandle);
function xeAutomationTryPipeClientCall(const aPipeName: string; const aRequestBytes: TBytes; out aResponseBytes: TBytes): Boolean;

implementation

uses
  Classes;

const
  xeAutomationPipeNamePrefix = '\\.\pipe\xedit-';
  xeAutomationPipeClientRetryDelayMs = 50;
  xeAutomationPipeClientRetryTimeoutMs = 5000;

function xeAutomationPipeNameForPid(const aPid: Cardinal): string;
begin
  // A PID only identifies which daemon instance owns the conversation; callers
  // still need a concrete OS transport endpoint. Deriving the pipe name from the
  // PID gives both sides a stable rendezvous name without a separate registry.
  Result := xeAutomationPipeNamePrefix + UIntToStr(aPid);
end;

function xeAutomationPipeHandleIsOpen(const aPipeHandle: THandle): Boolean;
begin
  Result := (aPipeHandle <> 0) and (aPipeHandle <> INVALID_HANDLE_VALUE);
end;

procedure xeAutomationResetPipeHandle(var aPipeHandle: THandle);
begin
  if xeAutomationPipeHandleIsOpen(aPipeHandle) then
    CloseHandle(aPipeHandle);
  aPipeHandle := INVALID_HANDLE_VALUE;
end;

function xeAutomationPipeClientCanRetryOpenError(const aError: Cardinal): Boolean;
begin
  Result := aError in [ERROR_FILE_NOT_FOUND, ERROR_PIPE_BUSY, ERROR_SEM_TIMEOUT];
end;

procedure xeAutomationWritePipeBytes(const aPipeHandle: THandle; const aBytes: TBytes);
var
  lWritten: Cardinal;
begin
  if Length(aBytes) = 0 then
    Exit;

  if not WriteFile(aPipeHandle, aBytes[0], Length(aBytes), lWritten, nil) then
    RaiseLastOSError;

  if lWritten <> Cardinal(Length(aBytes)) then
    raise Exception.Create('Automation daemon pipe write was incomplete');
end;

procedure xeAutomationReadPipeBytes(const aPipeHandle: THandle; out aBytes: TBytes);
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
      if ReadFile(aPipeHandle, lBuffer[0], Length(lBuffer), lBytesRead, nil) then begin
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

function xeAutomationTryPipeClientCall(const aPipeName: string; const aRequestBytes: TBytes; out aResponseBytes: TBytes): Boolean;
var
  lPipeHandle: THandle;
  lReadMode: DWORD;
  lOpenError: Cardinal;
  lStartedTick: Cardinal;
begin
  Result := False;
  SetLength(aResponseBytes, 0);
  lStartedTick := GetTickCount;
  repeat
    lPipeHandle := CreateFile(PChar(aPipeName), GENERIC_READ or GENERIC_WRITE, 0, nil, OPEN_EXISTING, 0, 0);
    if xeAutomationPipeHandleIsOpen(lPipeHandle) then
      Break;

    lOpenError := GetLastError;
    if not xeAutomationPipeClientCanRetryOpenError(lOpenError) then
      RaiseLastOSError(lOpenError);

    if (GetTickCount - lStartedTick) >= xeAutomationPipeClientRetryTimeoutMs then
      Exit(False);

    if lOpenError = ERROR_PIPE_BUSY then
      WaitNamedPipe(PChar(aPipeName), xeAutomationPipeClientRetryDelayMs)
    else
      Sleep(xeAutomationPipeClientRetryDelayMs);
  until False;

  try
    lReadMode := PIPE_READMODE_MESSAGE;
    if not SetNamedPipeHandleState(lPipeHandle, lReadMode, nil, nil) then
      RaiseLastOSError;

    xeAutomationWritePipeBytes(lPipeHandle, aRequestBytes);
    xeAutomationReadPipeBytes(lPipeHandle, aResponseBytes);
    Result := True;
  finally
    xeAutomationResetPipeHandle(lPipeHandle);
  end;
end;

end.
