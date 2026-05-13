{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeAutomationHostCli;

interface

function xeAutomationTryRunCli(out AExitCode: Integer): Boolean;
function xeAutomationExecuteRequestText(const aRequestText: string): string; overload;
function xeAutomationExecuteRequestText(const aRequestText: string; out aSucceeded: Boolean): string; overload;
function xeAutomationTryRejectInvalidSetup(const aMessage: string; out AExitCode: Integer): Boolean;

implementation

uses
  System.IOUtils,
  SysUtils,
  JsonDataObjects,
  wbInterface,
  // The one-shot host stays linked only to stateless commands. Loaded-data groups
  // are registered later from serve-mode startup once the live session is loaded.
  xeAutomationCommandsSystem,
  xeAutomationErrors,
  xeAutomationRegistry,
  xeAutomationSession,
  xeAutomationTypes,
  xeAutomationTransportPipe;

procedure xeAutomationWriteCliResponseText(const aResponsePath, aResponseText: string);
begin
  TFile.WriteAllText(aResponsePath, aResponseText, TEncoding.UTF8);
end;

procedure xeAutomationCopyRequestCorrelation(const aRequest, aResponse: TJsonObject);
begin
  if not Assigned(aRequest) or not Assigned(aResponse) then
    Exit;

  // Correlation fields are optional protocol metadata. Echo them only when the
  // request parsed cleanly so malformed JSON still returns the stable legacy error
  // envelope instead of depending on a best-effort partial parser.
  if aRequest.Contains('requestId') then
    aResponse.Values['requestId'] := aRequest.Values['requestId'];
  if aRequest.Contains('id') then
    aResponse.Values['id'] := aRequest.Values['id'];
end;

function xeAutomationSanitizeRequestLogValue(const aValue: string): string;
const
  CxeAutomationMaxRequestLogValueLength = 120;
begin
  Result := StringReplace(aValue, #13, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #9, ' ', [rfReplaceAll]);
  Result := Trim(Result);
  if Length(Result) > CxeAutomationMaxRequestLogValueLength then
    Result := Copy(Result, 1, CxeAutomationMaxRequestLogValueLength) + '...';
end;

procedure xeAutomationTryGetRequestCorrelation(const aRequest: TJsonObject;
  out aCorrelationName, aCorrelationValue: string);
begin
  aCorrelationName := '';
  aCorrelationValue := '';

  if not Assigned(aRequest) then
    Exit;

  if aRequest.Contains('requestId') then begin
    aCorrelationName := 'requestId';
    aCorrelationValue := xeAutomationSanitizeRequestLogValue(aRequest.S['requestId']);
  end else if aRequest.Contains('id') then begin
    aCorrelationName := 'id';
    aCorrelationValue := xeAutomationSanitizeRequestLogValue(aRequest.S['id']);
  end;
end;

procedure xeAutomationAppendRequestLogField(var aLine: string; const aKey, aValue: string);
begin
  if (aKey = '') or (aValue = '') then
    Exit;

  aLine := aLine + Format(' %s="%s"', [aKey, xeAutomationSanitizeRequestLogValue(aValue)]);
end;

function xeAutomationTryGetTargetValue(const aTarget: TJsonObject; const aKey: string): string;
begin
  Result := '';
  if not Assigned(aTarget) then
    Exit;

  if aKey = 'file' then begin
    if aTarget.Contains('file') then
      Exit(aTarget.S['file']);
    if aTarget.Contains('name') then
      Exit(aTarget.S['name']);
    if aTarget.Contains('fileName') then
      Exit(aTarget.S['fileName']);
    if aTarget.Contains('targetFile') then
      Exit(aTarget.S['targetFile']);
  end;

  if aTarget.Contains(aKey) then
    Result := aTarget.S[aKey];
end;

procedure xeAutomationAppendRequestLogTargetFields(var aLine: string; const aTarget: TJsonObject);
begin
  xeAutomationAppendRequestLogField(aLine, 'file', xeAutomationTryGetTargetValue(aTarget, 'file'));
  xeAutomationAppendRequestLogField(aLine, 'formId', xeAutomationTryGetTargetValue(aTarget, 'formId'));
  xeAutomationAppendRequestLogField(aLine, 'path', xeAutomationTryGetTargetValue(aTarget, 'path'));
  xeAutomationAppendRequestLogField(aLine, 'editorId', xeAutomationTryGetTargetValue(aTarget, 'editorId'));
end;

function xeAutomationBuildTargetBlockText(const aTarget: TJsonObject): string; overload;
begin
  Result := '';
  xeAutomationAppendRequestLogTargetFields(Result, aTarget);
  Result := Trim(Result);
end;

function xeAutomationBuildTargetBlockText(const aFileName: string): string; overload;
begin
  Result := '';
  xeAutomationAppendRequestLogField(Result, 'file', aFileName);
  Result := Trim(Result);
end;

function xeAutomationTryAppendRequestTargetSummary(var aLine: string; const aArgs: TJsonObject): Boolean;
var
  lBlock: string;
  lBeforeLine: string;
  lTarget: TJsonObject;
  lTargets: TJsonArray;
  lFirstTarget: string;
begin
  Result := False;
  if not Assigned(aArgs) then
    Exit;

  if aArgs.Contains('source') and (aArgs.Types['source'] = jdtObject) then begin
    lBlock := xeAutomationBuildTargetBlockText(aArgs.O['source']);
    if lBlock <> '' then begin
      aLine := aLine + Format(' source={%s}', [lBlock]);
      Result := True;
    end;
  end;

  if aArgs.Contains('target') then begin
    case aArgs.Types['target'] of
      jdtObject: begin
        lTarget := aArgs.O['target'];
        if Assigned(lTarget) and lTarget.Contains('files') and (lTarget.Types['files'] = jdtArray) then begin
          lTargets := lTarget.A['files'];
          if lTargets.Count > 1 then begin
            lFirstTarget := xeAutomationBuildTargetBlockText(lTargets.S[0]);
            if lFirstTarget <> '' then
              aLine := aLine + Format(' targets=%d firstTarget={%s}', [lTargets.Count, lFirstTarget])
            else
              aLine := aLine + Format(' targets=%d', [lTargets.Count]);
            Exit(True);
          end else if lTargets.Count = 1 then begin
            lBlock := xeAutomationBuildTargetBlockText(lTargets.S[0]);
            if lBlock <> '' then begin
              aLine := aLine + Format(' target={%s}', [lBlock]);
              Exit(True);
            end;
          end;
        end;

        lBlock := xeAutomationBuildTargetBlockText(lTarget);
        if lBlock <> '' then begin
          aLine := aLine + Format(' target={%s}', [lBlock]);
          Exit(True);
        end;
      end;
      jdtArray: begin
        lTargets := aArgs.A['target'];
        if lTargets.Count > 1 then begin
          lFirstTarget := xeAutomationBuildTargetBlockText(lTargets.S[0]);
          if lFirstTarget <> '' then
            aLine := aLine + Format(' targets=%d firstTarget={%s}', [lTargets.Count, lFirstTarget])
          else
            aLine := aLine + Format(' targets=%d', [lTargets.Count]);
          Exit(True);
        end else if lTargets.Count = 1 then begin
          lBlock := xeAutomationBuildTargetBlockText(lTargets.S[0]);
          if lBlock <> '' then begin
            aLine := aLine + Format(' target={%s}', [lBlock]);
            Exit(True);
          end;
        end;
      end;
      jdtString: begin
        aLine := aLine + Format(' target="%s"', [xeAutomationSanitizeRequestLogValue(aArgs.S['target'])]);
        Exit(True);
      end;
    end;
  end;

  if aArgs.Contains('targets') and (aArgs.Types['targets'] = jdtArray) then begin
    lTargets := aArgs.A['targets'];
    if lTargets.Count > 1 then begin
      if lTargets.Types[0] = jdtObject then
        lFirstTarget := xeAutomationBuildTargetBlockText(lTargets.O[0])
      else
        lFirstTarget := xeAutomationBuildTargetBlockText(lTargets.S[0]);
      if lFirstTarget <> '' then
        aLine := aLine + Format(' targets=%d firstTarget={%s}', [lTargets.Count, lFirstTarget])
      else
        aLine := aLine + Format(' targets=%d', [lTargets.Count]);
      Exit(True);
    end else if lTargets.Count = 1 then begin
      if lTargets.Types[0] = jdtObject then
        lBlock := xeAutomationBuildTargetBlockText(lTargets.O[0])
      else
        lBlock := xeAutomationBuildTargetBlockText(lTargets.S[0]);
      if lBlock <> '' then begin
        aLine := aLine + Format(' target={%s}', [lBlock]);
        Exit(True);
      end;
    end;
  end;

  lBeforeLine := aLine;
  xeAutomationAppendRequestLogTargetFields(aLine, aArgs);
  Result := aLine <> lBeforeLine;
end;

function xeAutomationBuildRequestLogLine(const aCommand: string; const aRequest, aArgs: TJsonObject): string;
var
  lCorrelationName: string;
  lCorrelationValue: string;
begin
  xeAutomationTryGetRequestCorrelation(aRequest, lCorrelationName, lCorrelationValue);

  Result := Format('Automation request: command="%s"', [
    xeAutomationSanitizeRequestLogValue(aCommand)
  ]);

  xeAutomationTryAppendRequestTargetSummary(Result, aArgs);

  if (lCorrelationName = 'requestId') and (lCorrelationValue <> '') then
    xeAutomationAppendRequestLogField(Result, 'requestId', lCorrelationValue)
  else if (lCorrelationName = 'id') and (lCorrelationValue <> '') then
    xeAutomationAppendRequestLogField(Result, 'id', lCorrelationValue);
end;

function xeAutomationBuildResultLogLine(const aCommand: string; const aRequest: TJsonObject;
  aOk: Boolean; const aErrorCode, aErrorMessage: string): string;
var
  lCorrelationName: string;
  lCorrelationValue: string;
begin
  xeAutomationTryGetRequestCorrelation(aRequest, lCorrelationName, lCorrelationValue);

  Result := Format('Automation result: command="%s"', [
    xeAutomationSanitizeRequestLogValue(aCommand)
  ]);

  if (lCorrelationName = 'requestId') and (lCorrelationValue <> '') then
    xeAutomationAppendRequestLogField(Result, 'requestId', lCorrelationValue)
  else if (lCorrelationName = 'id') and (lCorrelationValue <> '') then
    xeAutomationAppendRequestLogField(Result, 'id', lCorrelationValue);

  if aOk then
    Result := Result + ' ok=true'
  else begin
    Result := Result + ' ok=false';
    xeAutomationAppendRequestLogField(Result, 'code', aErrorCode);
    xeAutomationAppendRequestLogField(Result, 'reason', aErrorMessage);
  end;
end;

procedure xeAutomationLogRequestToMessages(const aCommand: string; const aRequest, aArgs: TJsonObject);
begin
  // This breadcrumb intentionally logs only stable command/correlation/target metadata.
  // Raw args can contain large payloads (scripts, values, paths) and would make
  // the Messages panel noisy for operators while duplicating request-file truth.
  wbProgress(xeAutomationBuildRequestLogLine(aCommand, aRequest, aArgs), True);
end;

procedure xeAutomationLogResultToMessages(const aCommand: string; const aRequest: TJsonObject;
  aOk: Boolean; const aErrorCode, aErrorMessage: string);
begin
  wbProgress(xeAutomationBuildResultLogLine(aCommand, aRequest, aOk, aErrorCode, aErrorMessage), True);
end;

function xeAutomationBuildErrorResponseText(const aCommand, aCode, aMessage: string;
  const aRequest: TJsonObject = nil; const aDetails: TJsonObject = nil): string;
var
  lResponse: TJsonObject;
begin
  lResponse := TJsonObject.Create;
  try
    lResponse.B['ok'] := False;
    xeAutomationCopyRequestCorrelation(aRequest, lResponse);
    lResponse.S['command'] := aCommand;
    lResponse.O['error'].S['code'] := aCode;
    lResponse.O['error'].S['message'] := aMessage;
    // error.details is an optional protocol extension: omit it when absent so
    // legacy clients continue to receive the exact original envelope shape.
    if Assigned(aDetails) then
      lResponse.O['error'].O['details'].Assign(aDetails);
    Result := lResponse.ToJSON(True);
  finally
    lResponse.Free;
  end;
end;

function xeAutomationCanWriteCliResponse(const aResponsePath: string): Boolean;
begin
  Result := aResponsePath <> '';
end;

function xeAutomationPrimaryResponsePath: string;
begin
  if xeAutomationCallResponsePath <> '' then
    Result := xeAutomationCallResponsePath
  else
    Result := xeAutomationCliResponsePath;
end;

procedure xeAutomationWriteCliErrorResponse(const aResponsePath, aCommand, aCode, aMessage: string;
  const aDetails: TJsonObject = nil);
begin
  if not xeAutomationCanWriteCliResponse(aResponsePath) then
    Exit;

  try
    xeAutomationWriteCliResponseText(
      aResponsePath,
      xeAutomationBuildErrorResponseText(aCommand, aCode, aMessage, nil, aDetails)
    );
  except
    // Keep automation invocations fail-fast even when the configured
    // response path itself is invalid or unwritable.
  end;
end;

function xeAutomationTryRejectInvalidSetup(const aMessage: string; out AExitCode: Integer): Boolean;
begin
  AExitCode := 1;
  xeAutomationWriteCliErrorResponse(
    xeAutomationPrimaryResponsePath,
    '',
    xeAutomationErrorInvalidRequest,
    aMessage
  );
  Result := True;
end;

function xeAutomationExecuteRequestText(const aRequestText: string; out aSucceeded: Boolean): string; overload;
var
  lCommand: string;
  lRequestBase: TJsonBaseObject;
  lRequest: TJsonObject;
  lArgs: TJsonObject;
  lResult: TJsonObject;
  lResponse: TJsonObject;
begin
  lCommand := '';
  aSucceeded := False;
  lRequestBase := nil;
  lRequest := nil;
  lArgs := nil;
  lResult := nil;
  lResponse := nil;
  try
    try
      lRequestBase := TJsonBaseObject.ParseUtf8(aRequestText);
      if not (lRequestBase is TJsonObject) then
        raise xeAutomationInvalidRequest('Automation CLI request must be a JSON object');

      lRequest := lRequestBase as TJsonObject;
      lCommand := Trim(lRequest.S['command']);
      if lCommand = '' then
        raise xeAutomationInvalidRequest('Automation CLI request must include a command');

      // Treat malformed args as an invalid request at the transport boundary
      // so callers get a stable protocol error instead of Delphi cast text.
      if lRequest.Contains('args') then begin
        if lRequest.Types['args'] <> jdtObject then
          raise xeAutomationInvalidRequest('Automation CLI request args must be a JSON object');
        lArgs := lRequest.ExtractObject('args');
      end else
        lArgs := TJsonObject.Create;
    except
      on E: ExeAutomationError do
        raise;
      on E: Exception do
        raise xeAutomationInvalidRequest(E.Message);
    end;

    xeAutomationLogRequestToMessages(lCommand, lRequest, lArgs);

    // Request execution is registry-driven so serve mode can deliberately expand
    // the command surface only after xEdit has loaded the in-memory session.
    lResult := xeAutomationExecuteCommand(lCommand, lArgs);

    lResponse := TJsonObject.Create;
    // Success responses always echo the command name so external wrappers can
    // correlate results without inferring state from the request file alone.
    lResponse.B['ok'] := True;
    xeAutomationCopyRequestCorrelation(lRequest, lResponse);
    lResponse.S['command'] := lCommand;
    lResponse.O['result'] := lResult;
    lResult := nil;
    xeAutomationLogResultToMessages(lCommand, lRequest, True, '', '');
    aSucceeded := True;
    Result := lResponse.ToJSON(True);
  except
    on E: ExeAutomationError do begin
      xeAutomationLogResultToMessages(lCommand, lRequest, False, E.Code, E.Message);
      Result := xeAutomationBuildErrorResponseText(lCommand, E.Code, E.Message, lRequest, E.Details);
    end;
    on E: Exception do begin
      xeAutomationLogResultToMessages(lCommand, lRequest, False, xeAutomationErrorInternalError, E.Message);
      Result := xeAutomationBuildErrorResponseText(
        lCommand,
        xeAutomationErrorInternalError,
        E.Message,
        lRequest
      );
    end;
  end;

  lResponse.Free;
  lResult.Free;
  lArgs.Free;
  lRequestBase.Free;
end;

function xeAutomationExecuteRequestText(const aRequestText: string): string; overload;
var
  lSucceeded: Boolean;
begin
  Result := xeAutomationExecuteRequestText(aRequestText, lSucceeded);
end;

function xeAutomationTryRunCliCall(out AExitCode: Integer): Boolean;
var
  lRequestText: string;
  lResponseBytes: TBytes;
begin
  if xeAutomationMode <> xamCall then
    Exit(False);

  Result := True;
  AExitCode := 0;
  try
    try
      if not xeAutomationCallPidIsValid then
        raise xeAutomationInvalidRequest('Automation call pid is required');

      if xeAutomationCallPipeName = '' then
        raise xeAutomationInvalidRequest('Automation call pipe name is required');

      if xeAutomationCallRequestPath = '' then
        raise xeAutomationInvalidRequest('Automation call request path is required');

      if xeAutomationCallResponsePath = '' then
        raise xeAutomationInvalidRequest('Automation call response path is required');

      // Call mode is a thin relay: it forwards one JSON document to the daemon
      // and returns one JSON response without owning any command semantics.
      lRequestText := TFile.ReadAllText(xeAutomationCallRequestPath, TEncoding.UTF8);
      if Trim(lRequestText) = '' then
        raise xeAutomationInvalidRequest('Automation call request file is empty');

      if not xeAutomationTryPipeClientCall(
        xeAutomationCallPipeName,
        TEncoding.UTF8.GetBytes(lRequestText),
        lResponseBytes
      ) then
        raise xeAutomationNewError(
          xeAutomationErrorInternalError,
          Format('Automation daemon pipe is unavailable: %s', [xeAutomationCallPipeName])
        );

      xeAutomationWriteCliResponseText(
        xeAutomationCallResponsePath,
        TEncoding.UTF8.GetString(lResponseBytes)
      );
      AExitCode := 0;
    except
      on E: ExeAutomationError do begin
        AExitCode := 1;
        xeAutomationWriteCliErrorResponse(xeAutomationCallResponsePath, '', E.Code, E.Message, E.Details);
      end;
      on E: Exception do begin
        AExitCode := 1;
        xeAutomationWriteCliErrorResponse(
          xeAutomationCallResponsePath,
          '',
          xeAutomationErrorInternalError,
          E.Message
        );
      end;
    end;
  finally
    SetLength(lResponseBytes, 0);
  end;
end;

function xeAutomationTryRunCli(out AExitCode: Integer): Boolean;
var
  lResponseText: string;
  lSucceeded: Boolean;
begin
  AExitCode := 0;
  if xeAutomationTryRunCliCall(AExitCode) then
    Exit(True);

  if not xeAutomationCliRequested then
    Exit(False);

  // Once CLI mode is active, always consume the invocation here so malformed
  // requests fail headlessly instead of falling through into normal GUI startup.
  Result := True;
  try
    // Validate transport-level prerequisites before reading any files so
    // partial flag combinations fail with stable protocol errors.
    if xeAutomationCliRequestPath = '' then
      raise xeAutomationInvalidRequest('Automation CLI request path is required');

    if xeAutomationCliResponsePath = '' then
      raise xeAutomationInvalidRequest('Automation CLI response path is required');

    lResponseText := xeAutomationExecuteRequestText(
      TFile.ReadAllText(xeAutomationCliRequestPath, TEncoding.UTF8),
      lSucceeded
    );
    xeAutomationWriteCliResponseText(xeAutomationCliResponsePath, lResponseText);
    if lSucceeded then
      AExitCode := 0
    else
      AExitCode := 1;
  except
    on E: ExeAutomationError do begin
      AExitCode := 1;
      xeAutomationWriteCliErrorResponse(xeAutomationCliResponsePath, '', E.Code, E.Message, E.Details);
    end;
    on E: Exception do begin
      AExitCode := 1;
      xeAutomationWriteCliErrorResponse(xeAutomationCliResponsePath, '', xeAutomationErrorInternalError, E.Message);
    end;
  end;
end;

end.
