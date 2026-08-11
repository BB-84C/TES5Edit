{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeAutomationCommandsScripts;

interface

procedure xeAutomationRegisterScriptsCommands;

implementation

uses
  StrUtils,
  SysUtils,
  Windows,
  JsonDataObjects,
  JvInterpreter,
  wbInterface,
  wbLoadOrder,
  xeAutomationDataLookup,
  xeAutomationErrors,
  xeMainForm,
  xeHeadlessJvIScriptHost,
  xeAutomationMutationPolicy,
  xeAutomationObjectModel,
  xeAutomationRegistry,
  xeScriptExecutionGuard,
  xeScriptLint,
  xeScriptStorage;

const
  xeAutomationScriptsDefaultListLimit = 200;
  xeAutomationScriptsMaxListLimit = 1000;
  xeAutomationScriptsDefaultTimeoutMS = 30000;
  xeAutomationScriptsDefaultMaxStatements = 1000000;
  xeAutomationScriptsErrorBlockerLint = 'script_blocker_lint';
  xeAutomationScriptsErrorCompile = 'script_compile_error';
  xeAutomationScriptsErrorRuntime = 'script_runtime_error';

function xeScriptsRunEntryUnitNameFor(const AOptions: TxeHeadlessScriptRunOptions): string;
var
  lFileName: string;
begin
  lFileName := ExtractFileName(AOptions.EntryScriptPath);
  Result := ChangeFileExt(lFileName, '');
end;

function xeAutomationScriptsReadIntegerArg(const AArgs: TJsonObject; const AName: string;
  const ADefault: Integer): Integer;
var
  lValue: Int64;
begin
  Result := ADefault;
  if not Assigned(AArgs) or not AArgs.Contains(AName) then
    Exit;

  if not (AArgs.Types[AName] in [jdtInt, jdtLong]) then
    raise xeAutomationInvalidRequest(Format('Automation arg field "%s" must be an integer', [AName]));

  // JSON may carry a value wider than Delphi Integer. Validate in Int64 before
  // casting so extreme limits are clamped predictably instead of overflowing.
  lValue := AArgs.L[AName];
  if lValue < 0 then
    raise xeAutomationInvalidRequest(Format('Automation arg field "%s" must be non-negative', [AName]));
  if lValue > High(Integer) then
    Exit(High(Integer));

  Result := Integer(lValue);
end;

function xeAutomationScriptsReadCardinalArg(const AArgs: TJsonObject; const AName: string;
  const ADefault: Cardinal): Cardinal;
var
  lValue: Int64;
begin
  Result := ADefault;
  if not Assigned(AArgs) or not AArgs.Contains(AName) then
    Exit;

  if not (AArgs.Types[AName] in [jdtInt, jdtLong]) then
    raise xeAutomationInvalidRequest(Format('Automation arg field "%s" must be an integer', [AName]));

  // budgets are parsed through Int64 first so hostile JSON cannot wrap the
  // Cardinal fields consumed by the headless runner.
  lValue := AArgs.L[AName];
  if lValue < 0 then
    raise xeAutomationInvalidRequest(Format('Automation arg field "%s" must be non-negative', [AName]));
  if lValue = 0 then
    raise xeAutomationInvalidRequest(Format('Automation arg field "%s" must be greater than zero', [AName]));
  if lValue > High(Cardinal) then
    Exit(High(Cardinal));

  Result := Cardinal(lValue);
end;

procedure xeAutomationScriptsRaiseStorageError(const ARejectionKind, AId: string);
var
  lCode: string;
  lMessage: string;
begin
  lCode := ARejectionKind;
  if lCode = '' then
    lCode := xeScriptStorageIoError;

  // xeScriptStorage owns filesystem canonicalization and reports stable rejection
  // kinds; this facade only maps those kinds into the daemon error envelope.
  if SameText(lCode, xeScriptStorageInvalidRequest) then
    raise xeAutomationInvalidRequest(Format('Script id "%s" is invalid', [AId]));

  if SameText(lCode, xeScriptStoragePathOutsideNamespace) then
    lMessage := Format('Script id "%s" is outside the allowed scripts namespace', [AId])
  else if SameText(lCode, xeScriptStorageScriptNotFound) then
    lMessage := Format('Script "%s" was not found', [AId])
  else if SameText(lCode, xeScriptStorageAlreadyExists) then
    lMessage := Format('Script "%s" already exists', [AId])
  else if SameText(lCode, xeScriptStorageIoError) then
    lMessage := Format('Script "%s" could not be accessed', [AId])
  else
    lMessage := Format('Script "%s" was rejected: %s', [AId, lCode]);

  raise xeAutomationNewError(lCode, lMessage);
end;

procedure xeAutomationScriptsRequireCanonicalId(const AId: string; const ARequireAgentWrite: Boolean;
  out ANormalizedId: string);
var
  lAbsolutePath: string;
  lRejectionKind: string;
begin
  // The storage helper is the single source of truth for ID normalization and
  // Agent/ write boundaries; command handlers must not rebuild paths themselves.
  if not xeCanonicalizeScriptId(AId, ARequireAgentWrite, ANormalizedId, lAbsolutePath, lRejectionKind) then
    xeAutomationScriptsRaiseStorageError(lRejectionKind, AId);
end;

procedure xeAutomationScriptsWriteMeta(const ATarget: TJsonObject; const AMeta: TxeScriptMeta);
begin
  ATarget.S['id'] := AMeta.Id;
  ATarget.L['sizeBytes'] := AMeta.SizeBytes;
  ATarget.S['modifiedTime'] := AMeta.ModifiedTimeUtc;
end;

function xeAutomationScriptsList(const AArgs: TJsonObject): TJsonObject;
var
  lPrefix: string;
  lLimit: Integer;
  lScripts: TArray<TxeScriptMeta>;
  lTotal: Integer;
  lTruncated: Boolean;
  lScript: TxeScriptMeta;
  lScriptJson: TJsonObject;
begin
  lPrefix := xeAutomationReadStringArg(AArgs, 'prefix');
  lLimit := xeAutomationScriptsReadIntegerArg(AArgs, 'limit', xeAutomationScriptsDefaultListLimit);
  if lLimit > xeAutomationScriptsMaxListLimit then
    lLimit := xeAutomationScriptsMaxListLimit;

  if not xeListScripts(lPrefix, lLimit, lScripts, lTotal, lTruncated) then
    xeAutomationScriptsRaiseStorageError(xeScriptStorageInvalidRequest, lPrefix);

  Result := TJsonObject.Create;
  try
    Result.A['scripts'];
    for lScript in lScripts do begin
      lScriptJson := TJsonObject.Create;
      xeAutomationScriptsWriteMeta(lScriptJson, lScript);
      Result.A['scripts'].Add(lScriptJson);
    end;
    Result.I['total'] := lTotal;
    Result.B['truncated'] := lTruncated;
  except
    Result.Free;
    raise;
  end;
end;

function xeAutomationScriptsRead(const AArgs: TJsonObject): TJsonObject;
var
  lId: string;
  lNormalizedId: string;
  lSource: string;
  lRejectionKind: string;
begin
  lId := xeAutomationRequireStringArg(AArgs, 'id');
  xeAutomationScriptsRequireCanonicalId(lId, False, lNormalizedId);

  if not xeReadScript(lId, lSource, lRejectionKind) then
    xeAutomationScriptsRaiseStorageError(lRejectionKind, lId);

  Result := TJsonObject.Create;
  Result.S['id'] := lNormalizedId;
  Result.S['source'] := lSource;
end;

function xeAutomationScriptsWrite(const AArgs: TJsonObject): TJsonObject;
var
  lId: string;
  lSource: string;
  lOverwriteSpecified: Boolean;
  lOverwrite: Boolean;
  lMeta: TxeScriptMeta;
  lCreated: Boolean;
  lAlreadyExists: Boolean;
  lRejectionKind: string;
  lDeniedReason: string;
begin
  if not xeAutomationMutationPolicyConsentSatisfied(lDeniedReason) then begin
    Result := xeAutomationErrorsBuildConsentRequired('scripts.write', 'scripts-mutation', lDeniedReason);
    Exit;
  end;

  lId := xeAutomationRequireStringArg(AArgs, 'id');
  lSource := xeAutomationRequireRawStringArg(AArgs, 'source');
  lOverwrite := xeAutomationReadBooleanArg(AArgs, 'overwrite', lOverwriteSpecified);
  if not lOverwriteSpecified then
    lOverwrite := False;

  if not xeWriteScript(lId, lSource, lOverwrite, lMeta, lCreated, lRejectionKind, lAlreadyExists) then
    xeAutomationScriptsRaiseStorageError(lRejectionKind, lId);

  Result := TJsonObject.Create;
  xeAutomationScriptsWriteMeta(Result, lMeta);
  Result.B['created'] := lCreated;
end;

function xeAutomationScriptsDelete(const AArgs: TJsonObject): TJsonObject;
var
  lId: string;
  lNormalizedId: string;
  lAbsolutePath: string;
  lRejectionKind: string;
  lDeniedReason: string;
begin
  if not xeAutomationMutationPolicyConsentSatisfied(lDeniedReason) then begin
    Result := xeAutomationErrorsBuildConsentRequired('scripts.delete', 'scripts-mutation', lDeniedReason);
    Exit;
  end;

  lId := xeAutomationRequireStringArg(AArgs, 'id');
  lNormalizedId := lId;
  // Let xeDeleteScript own missing-vs-namespace decisions; pre-rejecting here can
  // mask a missing Agent script as path_outside_namespace before storage sees it.
  xeCanonicalizeScriptId(lId, False, lNormalizedId, lAbsolutePath, lRejectionKind);

  if not xeDeleteScript(lId, lRejectionKind) then
    xeAutomationScriptsRaiseStorageError(lRejectionKind, lId);

  Result := TJsonObject.Create;
  Result.S['id'] := lNormalizedId;
  Result.B['deleted'] := True;
end;

function xeAutomationScriptsIsAgentId(const ANormalizedId: string): Boolean;
begin
  Result := StartsText('Agent/', ANormalizedId);
end;

procedure xeAutomationScriptsAddLintWarnings(const ATarget: TJsonObject; const AName: string;
  const AHits: TArray<TxeScriptLintHit>);
var
  lHit: TxeScriptLintHit;
  lHitJson: TJsonObject;
begin
  ATarget.A[AName];
  for lHit in AHits do begin
    lHitJson := TJsonObject.Create;
    lHitJson.S['kind'] := lHit.Kind;
    lHitJson.S['symbol'] := lHit.Symbol;
    lHitJson.I['line'] := lHit.Line;
    lHitJson.I['column'] := lHit.Column;
    lHitJson.S['sourceUnit'] := lHit.SourceUnit;
    ATarget.A[AName].Add(lHitJson);
  end;
end;

procedure xeAutomationScriptsRaiseLintBlocker(const ANormalizedId: string;
  const AHits: TArray<TxeScriptLintHit>);
var
  lDetails: TJsonObject;
begin
  lDetails := TJsonObject.Create;
  try
    xeAutomationScriptsAddLintWarnings(lDetails, 'lintWarnings', AHits);
    lDetails.S['lintScope'] := 'entry-script-only';
    raise xeAutomationNewError(
      xeAutomationScriptsErrorBlockerLint,
      Format('Script "%s" contains blocker lint warnings', [ANormalizedId]),
      lDetails
    );
  finally
    lDetails.Free;
  end;
end;

procedure xeAutomationScriptsRaiseCurrentBusyHolder;
var
  lDetails: TJsonObject;
begin
  lDetails := TJsonObject.Create;
  try
    lDetails.S['holder'] := xeScriptGuardCurrentHolder;
    raise xeAutomationNewError(
      xeHeadlessScriptErrorBusy,
      'Script execution is already running',
      lDetails
    );
  finally
    lDetails.Free;
  end;
end;

function xeAutomationScriptsLooksLikeFormId(const AValue: string): Boolean;
var
  i: Integer;
  lStart: Integer;
begin
  Result := False;
  if AValue = '' then
    Exit;

  lStart := 1;
  if (Length(AValue) > 2) and (AValue[1] = '0') and (UpCase(AValue[2]) = 'X') then
    lStart := 3;
  if lStart > Length(AValue) then
    Exit;

  for i := lStart to Length(AValue) do
    if not CharInSet(AValue[i], ['0'..'9', 'A'..'F', 'a'..'f']) then
      Exit;
  Result := True;
end;

function xeAutomationScriptsReadTargetsArg(const AArgs: TJsonObject): TJsonArray;
var
  i: Integer;
  lLocator: TxeAutomationLocator;
begin
  Result := nil;
  if not Assigned(AArgs) or not AArgs.Contains('targets') then
    Exit;

  if AArgs.Types['targets'] <> jdtArray then
    raise xeAutomationInvalidRequest('Automation arg field "targets" must be an array');

  Result := AArgs.A['targets'];
  for i := 0 to Pred(Result.Count) do begin
    if Result.Types[i] <> jdtObject then
      raise xeAutomationInvalidRequest('Automation arg field "targets" target entries must be locator objects');
    lLocator := xeAutomationParseLocator(Result.O[i], True, True);
    if not xeAutomationScriptsLooksLikeFormId(lLocator.FormID) then
      raise xeAutomationInvalidRequest('Automation target locator formId must be hexadecimal');
  end;
end;

function xeAutomationScriptsTryParseSoftTermination(const AMessage: string;
  out ATerminationCode: Int64): Boolean;
var
  lFunctionName: string;
  lPrefix: string;
  lDigits: string;
  lOffset: Integer;
  lCode64: Int64;
begin
  Result := False;
  ATerminationCode := 0;
  lFunctionName := '';

  if Copy(AMessage, 1, Length('Initialize returned ')) = 'Initialize returned ' then
    lFunctionName := 'Initialize'
  else if Copy(AMessage, 1, Length('Process returned ')) = 'Process returned ' then
    lFunctionName := 'Process'
  else if Copy(AMessage, 1, Length('Finalize returned ')) = 'Finalize returned ' then
    lFunctionName := 'Finalize'
  else
    Exit;

  lPrefix := lFunctionName + ' returned ';
  lDigits := Copy(AMessage, Length(lPrefix) + 1, MaxInt);
  if lDigits = '' then
    Exit;

  lOffset := 1;
  if CharInSet(lDigits[lOffset], ['-', '+']) then begin
    Inc(lOffset);
    if lOffset > Length(lDigits) then
      Exit;
  end;

  while lOffset <= Length(lDigits) do begin
    if not CharInSet(lDigits[lOffset], ['0'..'9']) then
      Exit;
    Inc(lOffset);
  end;

  if not TryStrToInt64(lDigits, lCode64) then
    Exit;

  ATerminationCode := lCode64;
  Result := True;
end;

function xeAutomationScriptsTryExtractRuntimeDenial(const AMessage: string;
  out ADeniedIdentifier: string): Boolean;
const
  lAccessDeniedPrefix = 'Access denied to ''';
var
  lStart: Integer;
  lStop: Integer;
  lPayload: string;
  lSeparator: Integer;
begin
  Result := False;
  ADeniedIdentifier := '';

  lStart := Pos(lAccessDeniedPrefix, AMessage);
  if lStart = 0 then
    Exit;

  Inc(lStart, Length(lAccessDeniedPrefix));
  lStop := Pos('''', Copy(AMessage, lStart, MaxInt));
  if lStop = 0 then
    Exit;

  lPayload := Copy(AMessage, lStart, lStop - 1);
  // JVCL's auth hook formats denials as "Access denied to '<identifier>: <reason>'";
  // use that single parse point so runtimeDenied and deniedIdentifier cannot drift.
  lSeparator := Pos(': ', lPayload);
  if lSeparator = 0 then
    Exit;

  ADeniedIdentifier := Copy(lPayload, 1, lSeparator - 1);
  Result := ADeniedIdentifier <> '';
end;

function xeAutomationScriptsPhaseRank(const APhase: string): Integer;
begin
  if SameText(APhase, 'queued') then
    Result := 0
  else if SameText(APhase, 'load') then
    Result := 1
  else if SameText(APhase, 'resolve_targets') then
    Result := 2
  else if SameText(APhase, 'compile') then
    Result := 3
  else if SameText(APhase, 'preflight') then
    Result := 4
  else if SameText(APhase, 'initialize') then
    Result := 5
  else if SameText(APhase, 'process') then
    Result := 6
  else if SameText(APhase, 'finalize') then
    Result := 7
  else if SameText(APhase, 'complete') then
    Result := 8
  else
    Result := -1;
end;

function xeAutomationScriptsRanPhase(const ARunResult: TxeHeadlessScriptRunResult;
  const APhase: string): Boolean;
var
  lLastRank: Integer;
  lTargetRank: Integer;
begin
  lLastRank := xeAutomationScriptsPhaseRank(ARunResult.ScriptLastPhase);
  lTargetRank := xeAutomationScriptsPhaseRank(APhase);
  Result := (lTargetRank >= 0) and (lLastRank >= lTargetRank);
end;

procedure xeAutomationScriptsAttachLifecycleDetails(const ADetails: TJsonObject;
  const ARunResult: TxeHeadlessScriptRunResult);
begin
  if not Assigned(ADetails) then
    Exit;

  // Phase-progression heuristic for lifecycle reporting:
  // ranInitialize:true means the run reached or passed the 'initialize' phase,
  // not that an Initialize routine actually existed. Same shape for ranFinalize.
  ADetails.B['ranInitialize'] := xeAutomationScriptsRanPhase(ARunResult, 'initialize');
  ADetails.B['ranFinalize'] := xeAutomationScriptsRanPhase(ARunResult, 'finalize');
  ADetails.I['processed'] := ARunResult.ProcessedTargetCount;
end;

procedure xeAutomationScriptsAttachFailureMessages(const ADetails: TJsonObject;
  const ARunResult: TxeHeadlessScriptRunResult);
var
  i: Integer;
begin
  if not Assigned(ADetails) then
    Exit;

  // Lifecycle-failure messages live on error.details while request/lint/storage
  // rejections stay message-free because they never run scripts.
  ADetails.A['messages'];
  for i := Low(ARunResult.Messages) to High(ARunResult.Messages) do
    ADetails.A['messages'].Add(ARunResult.Messages[i]);
  ADetails.B['messagesTruncated'] := ARunResult.MessagesTruncated;
end;

function xeAutomationScriptsErrorLocationFromMessage(const AMessage: string): string;
var
  lStart: Integer;
  lStop: Integer;
begin
  Result := '';
  lStart := Pos('in unit ', AMessage);
  if lStart = 0 then
    Exit;

  Inc(lStart, Length('in '));

  lStop := Pos(':', Copy(AMessage, lStart, MaxInt));
  if lStop = 0 then
    Result := Copy(AMessage, lStart, MaxInt)
  else
    Result := Copy(AMessage, lStart, lStop - 1);
end;

procedure xeAutomationScriptsAddFailureLocation(const ADetails: TJsonObject; const AMessage: string);
var
  lLocation: string;
begin
  lLocation := xeAutomationScriptsErrorLocationFromMessage(AMessage);
  if lLocation <> '' then
    ADetails.S['errorLocation'] := lLocation;
end;

function xeAutomationScriptsFailureMessage(const ARunResult: TxeHeadlessScriptRunResult): string;
begin
  Result := ARunResult.ScriptFailureMessage;
  if Result = '' then
    Result := ARunResult.ErrorMessage;
end;

function xeAutomationScriptsStringArrayContains(const AValues: TArray<string>;
  const AValue: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := Low(AValues) to High(AValues) do
    if SameText(AValues[i], AValue) then
      Exit(True);
end;

procedure xeAutomationScriptsAppendUniqueString(var AValues: TArray<string>;
  const AValue: string);
var
  lIndex: Integer;
begin
  if (AValue = '') or xeAutomationScriptsStringArrayContains(AValues, AValue) then
    Exit;
  lIndex := Length(AValues);
  SetLength(AValues, lIndex + 1);
  AValues[lIndex] := AValue;
end;

function xeAutomationScriptsCurrentDirtyFiles: TArray<string>;
var
  lModules: TwbModuleInfos;
  lFile: IwbFile;
  i: Integer;
begin
  SetLength(Result, 0);
  lModules := wbModulesByLoadOrder;
  for i := Low(lModules) to High(lModules) do begin
    lFile := xeAutomationTryPluginFileFromModule(lModules[i]);
    if Assigned(lFile) and lFile.Modified then
      xeAutomationScriptsAppendUniqueString(Result, lFile.FileName);
  end;
end;

function xeAutomationScriptsDirtyFilesFromState(const ADirtyState: TJsonObject): TArray<string>;
var
  lDirtyFiles: TJsonArray;
  lDirtyFile: TJsonObject;
  i: Integer;
begin
  SetLength(Result, 0);
  if not Assigned(ADirtyState) or not ADirtyState.Contains('dirtyFiles') or
    (ADirtyState.Types['dirtyFiles'] <> jdtArray) then
    Exit;

  lDirtyFiles := ADirtyState.A['dirtyFiles'];
  for i := 0 to Pred(lDirtyFiles.Count) do begin
    if lDirtyFiles.Types[i] <> jdtObject then
      Continue;
    lDirtyFile := lDirtyFiles.O[i];
    if lDirtyFile.Contains('name') then
      xeAutomationScriptsAppendUniqueString(Result, lDirtyFile.S['name']);
  end;
end;

function xeAutomationScriptsStringSetsEqual(const ALeft, ARight: TArray<string>): Boolean;
var
  i: Integer;
begin
  if Length(ALeft) <> Length(ARight) then
    Exit(False);
  for i := Low(ALeft) to High(ALeft) do
    if not xeAutomationScriptsStringArrayContains(ARight, ALeft[i]) then
      Exit(False);
  Result := True;
end;

procedure xeAutomationScriptsAttachFailureMutationDetails(const ADetails: TJsonObject;
  const ADirtyFilesBefore: TArray<string>; const ARunResult: TxeHeadlessScriptRunResult);
var
  lDirtyFilesAfter: TArray<string>;
  lMutationsApplied: Boolean;
  i: Integer;
begin
  lDirtyFilesAfter := xeAutomationScriptsDirtyFilesFromState(ARunResult.DirtyState);
  lMutationsApplied := not xeAutomationScriptsStringSetsEqual(ADirtyFilesBefore, lDirtyFilesAfter);
  ADetails.B['mutationsAppliedBeforeFailure'] := lMutationsApplied;
  if not lMutationsApplied then
    Exit;

  // Report only files newly dirtied by this run, excluding pre-existing session
  // dirtiness that the failed script did not introduce.
  ADetails.A['modifiedFilesBeforeFailure'];
  for i := Low(lDirtyFilesAfter) to High(lDirtyFilesAfter) do
    if not xeAutomationScriptsStringArrayContains(ADirtyFilesBefore, lDirtyFilesAfter[i]) then
      ADetails.A['modifiedFilesBeforeFailure'].Add(lDirtyFilesAfter[i]);
end;

procedure xeAutomationScriptsRaiseRunError(const ACode, AMessage: string; const ADetails: TJsonObject);
begin
  raise xeAutomationNewError(ACode, AMessage, ADetails);
end;

function xeAutomationScriptsRunFailedInProcessPhase(const ARunResult: TxeHeadlessScriptRunResult;
  const AOptions: TxeHeadlessScriptRunOptions): Boolean;
var
  lMessage: string;
  lTargetCount: Integer;
begin
  lMessage := xeAutomationScriptsFailureMessage(ARunResult);
  // The host phase-tags non-zero returns as "<Name> returned <int>" and exposes
  // targetIndex for generic Process exceptions when the target count and processed
  // count make the current target unambiguous.
  if Copy(lMessage, 1, Length('Process returned ')) = 'Process returned ' then
    Exit(True);

  if SameText(ARunResult.ScriptLastPhase, 'process') then
    Exit(True);

  lTargetCount := 0;
  if Assigned(AOptions.Targets) then
    lTargetCount := AOptions.Targets.Count;

  // Generic Process exceptions run the host's finally block, which advances the
  // visible phase to finalize. If targets remain unprocessed after the runner has
  // reached Process-or-later, expose the current target index instead of hiding it.
  if (lTargetCount > 0) and (ARunResult.ProcessedTargetCount < lTargetCount) and
    (xeAutomationScriptsPhaseRank(ARunResult.ScriptLastPhase) >= xeAutomationScriptsPhaseRank('process')) then
    Exit(True);

  Result := False;
end;

procedure xeAutomationScriptsTriageFailedRun(const ARunResult: TxeHeadlessScriptRunResult;
  const AOptions: TxeHeadlessScriptRunOptions; const ATimeoutMS, AMaxStatements: Cardinal;
  const ADirtyFilesBefore: TArray<string>;
  out ATerminatedEarly: Boolean; out ATerminationCode: Int64);
var
  lDetails: TJsonObject;
  lMessage: string;
  lRuntimeDenied: Boolean;
  lPolicyPreflight: Boolean;
  lDeniedIdentifier: string;
begin
  ATerminatedEarly := False;
  ATerminationCode := 0;
  lMessage := xeAutomationScriptsFailureMessage(ARunResult);

  if SameText(ARunResult.ErrorCode, xeHeadlessScriptErrorBusy) then begin
    lDetails := TJsonObject.Create;
    try
      lDetails.S['holder'] := ARunResult.BusyHolder;
      xeAutomationScriptsRaiseRunError(xeHeadlessScriptErrorBusy, ARunResult.ErrorMessage, lDetails);
    finally
      lDetails.Free;
    end;
  end;

  if SameText(ARunResult.ErrorCode, xeAutomationErrorInvalidRequest) then
    raise xeAutomationInvalidRequest(ARunResult.ErrorMessage);

  if SameText(ARunResult.ScriptFailureCode, xeHeadlessScriptErrorFailed) and
    xeAutomationScriptsTryParseSoftTermination(lMessage, ATerminationCode) then begin
    ATerminatedEarly := True;
    Exit;
  end;

  if SameText(ARunResult.ScriptLastPhase, 'compile') then begin
    if ARunResult.ExternalDeclarationDenied then begin
      lDetails := TJsonObject.Create;
      try
        // Dedicated daemon-surface mapping for JvI external-decl rejection.
        // Source/line come from the host surrogate fields populated in
        // xeHeadlessJvIScriptHost.pas. JvI raises with position 0 at
        // JvInterpreter.pas:8228 so ScriptFailureLine may legitimately be 0; the
        // public spec treats 0 as "unknown" rather than line one. declarationText
        // is intentionally not emitted (rev 2 simplification).
        if ARunResult.ScriptFailureUnitName <> '' then
          lDetails.S['sourceUnit'] := ARunResult.ScriptFailureUnitName
        else
          lDetails.S['sourceUnit'] := xeScriptsRunEntryUnitNameFor(AOptions);
        lDetails.I['line'] := ARunResult.ScriptFailureLine;
        xeAutomationScriptsAttachLifecycleDetails(lDetails, ARunResult);
        xeAutomationScriptsAttachFailureMessages(lDetails, ARunResult);
        xeAutomationScriptsRaiseRunError('script_external_declaration_not_allowed',
          ARunResult.ErrorMessage, lDetails);
      finally
        lDetails.Free;
      end;
    end;

    lDetails := TJsonObject.Create;
    try
      xeAutomationScriptsAddFailureLocation(lDetails, ARunResult.ErrorMessage);
      xeAutomationScriptsAttachLifecycleDetails(lDetails, ARunResult);
      xeAutomationScriptsAttachFailureMessages(lDetails, ARunResult);
      // Non-external compile failures keep the generic compile-error contract;
      // only the host's explicit external-declaration surrogate gets remapped above.
      xeAutomationScriptsRaiseRunError(xeAutomationScriptsErrorCompile, ARunResult.ErrorMessage, lDetails);
    finally
      lDetails.Free;
    end;
  end;

  if SameText(ARunResult.ErrorCode, xeHeadlessScriptErrorTimeout) then begin
    lDetails := TJsonObject.Create;
    try
      lDetails.L['timeoutMs'] := ATimeoutMS;
      // The runner does not expose elapsed wall time; echo timeoutMs as a
      // conservative upper-bound estimate rather than fabricating precision.
      lDetails.L['elapsedMs'] := ATimeoutMS;
      xeAutomationScriptsAttachLifecycleDetails(lDetails, ARunResult);
      xeAutomationScriptsAttachFailureMessages(lDetails, ARunResult);
      xeAutomationScriptsAttachFailureMutationDetails(lDetails, ADirtyFilesBefore, ARunResult);
      xeAutomationScriptsRaiseRunError(xeHeadlessScriptErrorTimeout, ARunResult.ErrorMessage, lDetails);
    finally
      lDetails.Free;
    end;
  end;

  if SameText(ARunResult.ErrorCode, xeHeadlessScriptErrorStatementBudgetExceeded) then begin
    lDetails := TJsonObject.Create;
    try
      lDetails.L['maxStatements'] := AMaxStatements;
      // Per C4 statements is omitted because the host does not expose a true
      // consumed statement count; emitting 0 would mislead callers.
      xeAutomationScriptsAttachLifecycleDetails(lDetails, ARunResult);
      xeAutomationScriptsAttachFailureMessages(lDetails, ARunResult);
      xeAutomationScriptsAttachFailureMutationDetails(lDetails, ADirtyFilesBefore, ARunResult);
      xeAutomationScriptsRaiseRunError(xeHeadlessScriptErrorStatementBudgetExceeded, ARunResult.ErrorMessage, lDetails);
    finally
      lDetails.Free;
    end;
  end;

  lDetails := TJsonObject.Create;
  try
    xeAutomationScriptsAddFailureLocation(lDetails, ARunResult.ErrorMessage);
    lRuntimeDenied := xeAutomationScriptsTryExtractRuntimeDenial(ARunResult.ErrorMessage, lDeniedIdentifier);
    lPolicyPreflight := SameText(ARunResult.ErrorCode, xeHeadlessScriptErrorPolicyPreflight);
    lDetails.B['policyPreflight'] := lPolicyPreflight;
    if lPolicyPreflight then begin
      lDetails.I['preflightLine'] := ARunResult.PolicyPreflightLine;
      lDetails.I['preflightColumn'] := ARunResult.PolicyPreflightColumn;
    end;
    lDetails.B['runtimeDenied'] := False;
    if lRuntimeDenied then begin
      lDetails.B['runtimeDenied'] := True;
      lDetails.S['deniedIdentifier'] := lDeniedIdentifier;
    end;
    if xeAutomationScriptsRunFailedInProcessPhase(ARunResult, AOptions) then
      lDetails.I['targetIndex'] := ARunResult.ProcessedTargetCount;
    xeAutomationScriptsAttachLifecycleDetails(lDetails, ARunResult);
    xeAutomationScriptsAttachFailureMessages(lDetails, ARunResult);
    xeAutomationScriptsAttachFailureMutationDetails(lDetails, ADirtyFilesBefore, ARunResult);
    xeAutomationScriptsRaiseRunError(xeAutomationScriptsErrorRuntime, ARunResult.ErrorMessage, lDetails);
  finally
    lDetails.Free;
  end;
end;

procedure xeAutomationScriptsAddMessages(const ATarget: TJsonObject; const ARunResult: TxeHeadlessScriptRunResult);
var
  i: Integer;
begin
  ATarget.A['messages'];
  for i := Low(ARunResult.Messages) to High(ARunResult.Messages) do
    ATarget.A['messages'].Add(ARunResult.Messages[i]);
end;

procedure xeAutomationScriptsAddDirtyFiles(const ATarget: TJsonObject; const ARunResult: TxeHeadlessScriptRunResult);
var
  lDirtyFiles: TJsonArray;
  lDirtyFile: TJsonObject;
  i: Integer;
begin
  ATarget.A['dirtyFiles'];
  if not Assigned(ARunResult.DirtyState) or not ARunResult.DirtyState.Contains('dirtyFiles') or
    (ARunResult.DirtyState.Types['dirtyFiles'] <> jdtArray) then
    Exit;

  lDirtyFiles := ARunResult.DirtyState.A['dirtyFiles'];
  for i := 0 to Pred(lDirtyFiles.Count) do begin
    if lDirtyFiles.Types[i] <> jdtObject then
      Continue;
    lDirtyFile := lDirtyFiles.O[i];
    // The headless host reuses xeAutomationNewFileSummary; expose only its display
    // plugin name so public scripts.run dirtyFiles stays a flat string array.
    if lDirtyFile.Contains('name') then
      ATarget.A['dirtyFiles'].Add(lDirtyFile.S['name']);
  end;
end;

function xeAutomationScriptsSuccessResult(const ANormalizedId: string;
  const ALintHits: TArray<TxeScriptLintHit>; const ALintBypassed: Boolean;
  const ARunResult: TxeHeadlessScriptRunResult; const ATerminatedEarly: Boolean;
  const ATerminationCode: Int64): TJsonObject;
begin
  Result := TJsonObject.Create;
  try
    Result.S['id'] := ANormalizedId;
    Result.O['compile'].B['ok'] := True;
    Result.B['lintBypassed'] := ALintBypassed;
    xeAutomationScriptsAddLintWarnings(Result, 'lintWarnings', ALintHits);
    // The host exposes only phase progression. A missing Initialize/Finalize routine
    // is therefore indistinguishable from a defined no-op routine in this facade.
    Result.B['ranInitialize'] := xeAutomationScriptsRanPhase(ARunResult, 'initialize');
    Result.B['ranFinalize'] := xeAutomationScriptsRanPhase(ARunResult, 'finalize');
    Result.I['processed'] := ARunResult.ProcessedTargetCount;
    Result.B['terminatedEarly'] := ATerminatedEarly;
    if ATerminatedEarly then
      Result.L['terminationCode'] := ATerminationCode
    else
      Result.O['terminationCode'] := nil;
    Result.B['timedOut'] := False;
    Result.B['statementBudgetExceeded'] := False;
    xeAutomationScriptsAddMessages(Result, ARunResult);
    Result.B['messagesTruncated'] := ARunResult.MessagesTruncated;
    xeAutomationScriptsAddDirtyFiles(Result, ARunResult);
  except
    Result.Free;
    raise;
  end;
end;

function xeAutomationScriptsRun(const AArgs: TJsonObject): TJsonObject;
var
  lId: string;
  lNormalizedId: string;
  lAbsolutePath: string;
  lRejectionKind: string;
  lIsAgent: Boolean;
  lSource: string;
  lAcceptKnownBlockersSpecified: Boolean;
  lAcceptKnownBlockers: Boolean;
  lLintHits: TArray<TxeScriptLintHit>;
  lLintBypassed: Boolean;
  lOptions: TxeHeadlessScriptRunOptions;
  lResult: TxeHeadlessScriptRunResult;
  lStarted: UInt64;
  lPrevPnlClientEnabled: Boolean;
  lTerminatedEarly: Boolean;
  lTerminationCode: Int64;
  lDeniedReason: string;
  lDirtyFilesBefore: TArray<string>;
begin
  if not xeAutomationMutationPolicyConsentSatisfied(lDeniedReason) then begin
    Result := xeAutomationErrorsBuildConsentRequired('scripts.run', 'scripts-mutation', lDeniedReason);
    Exit;
  end;

  // Parse and validate every request argument before storage, lint, or execution so
  // malformed run inputs cannot be masked by script_not_found or blocker lint.
  lId := xeAutomationRequireStringArg(AArgs, 'id');
  lOptions.Targets := xeAutomationScriptsReadTargetsArg(AArgs);
  lAcceptKnownBlockers := xeAutomationReadBooleanArg(AArgs, 'acceptKnownBlockers', lAcceptKnownBlockersSpecified);
  if not lAcceptKnownBlockersSpecified then
    lAcceptKnownBlockers := False;
  lOptions.TimeoutMS := xeAutomationScriptsReadCardinalArg(AArgs, 'timeoutMs', xeAutomationScriptsDefaultTimeoutMS);
  lOptions.StatementBudget := xeAutomationScriptsReadCardinalArg(AArgs, 'maxStatements', xeAutomationScriptsDefaultMaxStatements);

  // GUI Apply Script pumps messages while it owns the shared JvI execution token.
  // Refuse daemon scripts.run at the request boundary so reentrant timers cannot
  // descend into storage, lint, or headless-runner setup on that same GUI thread.
  if xeScriptGuardIsHeld and SameText(xeScriptGuardCurrentHolder, 'gui') then
    xeAutomationScriptsRaiseCurrentBusyHolder;

  if not xeCanonicalizeScriptId(lId, False, lNormalizedId, lAbsolutePath, lRejectionKind) then
    xeAutomationScriptsRaiseStorageError(lRejectionKind, lId);

  lIsAgent := xeAutomationScriptsIsAgentId(lNormalizedId);

  if not xeReadScript(lId, lSource, lRejectionKind) then
    xeAutomationScriptsRaiseStorageError(lRejectionKind, lId);

  SetLength(lLintHits, 0);
  if not lIsAgent then
    lLintHits := xeLintScriptEntrySource(lSource, lNormalizedId);
  lLintBypassed := (Length(lLintHits) > 0) and lAcceptKnownBlockers;
  if (Length(lLintHits) > 0) and not lAcceptKnownBlockers then
    xeAutomationScriptsRaiseLintBlocker(lNormalizedId, lLintHits);

  lOptions.EntryScriptPath := lAbsolutePath;
  // Targets remains owned by the request JSON object; the headless host borrows the
  // array reference for synchronous resolution and this facade must not free it.

  // Keep the cleanup owner record explicit before the call so overlap/refusal
  // result paths never depend on Delphi's implicit local-record contents.
  lResult := Default(TxeHeadlessScriptRunResult);
  // Snapshot the session before lifecycle dispatch so failure reporting can
  // distinguish this run's partial mutations from dirtiness that already existed.
  lDirtyFilesBefore := xeAutomationScriptsCurrentDirtyFiles;
  lPrevPnlClientEnabled := False;
  lStarted := GetTickCount64;
  if Assigned(frmMain) then
    lPrevPnlClientEnabled := frmMain.BeginDaemonScriptIndicator(lNormalizedId);
  try
    try
      // The daemon timer runs on the GUI thread, so this remains synchronous; the
      // main-form facade only makes that blocked interval visible and auditable.
      lResult := xeHeadlessRunScript(lOptions);
    finally
      if Assigned(frmMain) then
        frmMain.EndDaemonScriptIndicator(lNormalizedId, GetTickCount64 - lStarted, Length(lResult.Messages), lPrevPnlClientEnabled);
    end;

    lTerminatedEarly := False;
    lTerminationCode := 0;
    if not lResult.Success then
      xeAutomationScriptsTriageFailedRun(lResult, lOptions, lOptions.TimeoutMS, lOptions.StatementBudget,
        lDirtyFilesBefore, lTerminatedEarly, lTerminationCode);

    Result := xeAutomationScriptsSuccessResult(lNormalizedId, lLintHits, lLintBypassed, lResult,
      lTerminatedEarly, lTerminationCode);
  finally
    if Assigned(lResult.DirtyState) then
      lResult.DirtyState.Free;
  end;
end;

procedure xeAutomationRegisterScriptsCommands;
begin
  xeAutomationRegisterCommand('scripts.list', xeAutomationScriptsList);
  xeAutomationRegisterCommand('scripts.read', xeAutomationScriptsRead);
  xeAutomationRegisterCommand('scripts.write', xeAutomationScriptsWrite);
  xeAutomationRegisterCommand('scripts.delete', xeAutomationScriptsDelete);
  xeAutomationRegisterCommand('scripts.run', xeAutomationScriptsRun);
end;

end.
