{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeAutomationCommandsPluginAnalysis;

interface

procedure xeAutomationRegisterPluginAnalysisCommands;

implementation

uses
  System.Generics.Collections,
  SysUtils,
  JsonDataObjects,
  wbInterface,
  wbLoadOrder,
  xeAutomationDataLookup,
  xeAutomationErrors,
  xeAutomationJobs,
  xeAutomationMutationPolicy,
  xeAutomationObjectModel;

const
  xeAutomationEslAnalyzeKind = 'plugin.esl.analyze';
  xeAutomationFormIdsCompactForEslKind = 'plugin.formids.compact_for_esl';
  xeAutomationEslApplyKind = 'plugin.esl.apply';
  xeAutomationLightObjectIdLimit = $FFF;

type
  TxeAutomationFormIdRemap = record
    RecordRef: IwbMainRecord;
    OldFormID: TwbFormID;
    NewFormID: TwbFormID;
  end;

  TxeAutomationFormIdRemaps = array of TxeAutomationFormIdRemap;

function xeAutomationLightObjectIdLowest(const AFile: IwbFile): Cardinal;
begin
  Result := $800;
  if Assigned(AFile) and AFile.AllowHardcodedRangeUse then
    Result := 1;
end;

function xeAutomationLightObjectIdCapacity(const AFile: IwbFile): Cardinal;
var
  lLowestObjectId: Cardinal;
begin
  lLowestObjectId := xeAutomationLightObjectIdLowest(AFile);
  if lLowestObjectId > xeAutomationLightObjectIdLimit then
    Exit(0);
  Result := Succ(xeAutomationLightObjectIdLimit - lLowestObjectId);
end;

function xeAutomationObjectIdHex(const AObjectId: Cardinal): string;
begin
  Result := IntToHex(AObjectId, 8);
end;

function xeAutomationProtectedAnalysisTargetMessage(const AFile: IwbFile): string;
var
  lModule: PwbModuleInfo;
begin
  Result := '';
  if not Assigned(AFile) then
    Exit('Automation analysis target is required');

  if AFile.IsNotPlugin then
    Exit(Format('Automation analysis target is not a plugin: %s', [AFile.FileName]));

  lModule := PwbModuleInfo(AFile.ModuleInfo);
  if Assigned(lModule) and (mfIsHardcoded in lModule^.miFlags) then
    Exit(Format('Automation analysis target is a hardcoded module: %s', [AFile.FileName]));

  if fsIsHardcoded in AFile.FileStates then
    Exit(Format('Automation analysis target is a hardcoded file: %s', [AFile.FileName]));

  if fsIsGameMaster in AFile.FileStates then
    Exit(Format('Automation analysis target is the game master: %s', [AFile.FileName]));

  if fsIsOfficial in AFile.FileStates then
    Exit(Format('Automation analysis target is an official master: %s', [AFile.FileName]));
end;

procedure xeAutomationAddFindingObject(const AList: TJsonArray; const ACode, ASeverity, AMessage: string);
var
  lFinding: TJsonObject;
begin
  lFinding := TJsonObject.Create;
  try
    lFinding.S['code'] := ACode;
    lFinding.S['severity'] := ASeverity;
    lFinding.S['message'] := AMessage;
    AList.Add(lFinding);
    lFinding := nil;
  finally
    lFinding.Free;
  end;
end;

procedure xeAutomationAddPagedFinding(const AFindings: TJsonArray; const AFileName, ACode, ASeverity, AMessage: string);
var
  lFinding: TJsonObject;
begin
  lFinding := TJsonObject.Create;
  try
    lFinding.S['severity'] := ASeverity;
    lFinding.S['code'] := ACode;
    lFinding.S['message'] := AMessage;
    lFinding.O['target'].S['file'] := AFileName;
    lFinding.S['source'] := xeAutomationEslAnalyzeKind;
    AFindings.Add(lFinding);
    lFinding := nil;
  finally
    lFinding.Free;
  end;
end;

procedure xeAutomationAddUniqueString(const ATarget: TJsonArray; const AValue: string);
var
  i: Integer;
begin
  for i := 0 to Pred(ATarget.Count) do
    if SameText(ATarget.S[i], AValue) then
      Exit;
  ATarget.Add(AValue);
end;

function xeAutomationNewHeaderFlags(const AFile: IwbFile): TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.B['esm'] := AFile.IsESM;
  Result.B['esl'] := AFile.IsLight;
end;

function xeAutomationReadBooleanOption(const AOptions: TJsonObject; const AName: string; const ADefault: Boolean): Boolean;
begin
  Result := ADefault;
  if not Assigned(AOptions) or not AOptions.Contains(AName) then
    Exit;
  if AOptions.Types[AName] <> jdtBool then
    raise xeAutomationInvalidRequest(Format('Automation option "%s" must be a boolean', [AName]));
  Result := AOptions.B[AName];
end;

function xeAutomationAppliedWord(const AApplied: Boolean): string;
begin
  if AApplied then
    Result := 'Applied'
  else
    Result := 'Planned';
end;

procedure xeAutomationAddDirtyFile(const ADirtyFiles: TJsonArray; const AFile: IwbFile);
begin
  if Assigned(AFile) then
    xeAutomationAddUniqueString(ADirtyFiles, AFile.FileName);
end;

procedure xeAutomationValidateEslAnalyzeStart(var ADryRun: Boolean; const ADryRunSpecified: Boolean;
  const ATarget, AOptions: TJsonObject);
var
  lFiles: TJsonArray;
  i: Integer;
begin
  if not Assigned(ATarget) then
    raise xeAutomationInvalidRequest('Automation plugin.esl.analyze target is required');
  if not ATarget.Contains('files') then
    raise xeAutomationInvalidRequest('Automation plugin.esl.analyze target.files is required');
  if ATarget.Types['files'] <> jdtArray then
    raise xeAutomationInvalidRequest('Automation plugin.esl.analyze target.files must be an array');

  lFiles := ATarget.A['files'];
  if lFiles.Count = 0 then
    raise xeAutomationInvalidRequest('Automation plugin.esl.analyze target.files must not be empty');
  for i := 0 to Pred(lFiles.Count) do
    if lFiles.Types[i] <> jdtString then
      raise xeAutomationInvalidRequest('Automation plugin.esl.analyze target.files entries must be strings');

  // This job is a read-only analysis surface. Normalize omitted dryRun to true so
  // clients cannot mistake acceptance of the job for permission to mutate or save.
  if not ADryRunSpecified then
    ADryRun := True;
end;

procedure xeAutomationValidatePluginFilesTarget(const AKind: string; var ADryRun: Boolean; const ADryRunSpecified: Boolean;
  const ATarget: TJsonObject);
var
  lFiles: TJsonArray;
  i: Integer;
begin
  if not Assigned(ATarget) then
    raise xeAutomationInvalidRequest(Format('Automation %s target is required', [AKind]));
  if not ATarget.Contains('files') then
    raise xeAutomationInvalidRequest(Format('Automation %s target.files is required', [AKind]));
  if ATarget.Types['files'] <> jdtArray then
    raise xeAutomationInvalidRequest(Format('Automation %s target.files must be an array', [AKind]));

  lFiles := ATarget.A['files'];
  if lFiles.Count = 0 then
    raise xeAutomationInvalidRequest(Format('Automation %s target.files must not be empty', [AKind]));
  for i := 0 to Pred(lFiles.Count) do
    if lFiles.Types[i] <> jdtString then
      raise xeAutomationInvalidRequest(Format('Automation %s target.files entries must be strings', [AKind]));

  // Mutating 6B jobs are safe-by-default: callers must opt into apply mode with
  // dryRun:false, and persistence still remains a separate session.save call.
  if not ADryRunSpecified then
    ADryRun := True;
end;

procedure xeAutomationValidateCompactForEslStart(var ADryRun: Boolean; const ADryRunSpecified: Boolean;
  const ATarget, AOptions: TJsonObject);
begin
  xeAutomationValidatePluginFilesTarget(xeAutomationFormIdsCompactForEslKind, ADryRun, ADryRunSpecified, ATarget);
end;

procedure xeAutomationValidateEslApplyStart(var ADryRun: Boolean; const ADryRunSpecified: Boolean;
  const ATarget, AOptions: TJsonObject);
begin
  xeAutomationValidatePluginFilesTarget(xeAutomationEslApplyKind, ADryRun, ADryRunSpecified, ATarget);
  xeAutomationReadBooleanOption(AOptions, 'allowAfterCompact', False);
end;

procedure xeAutomationAddEslRecordStats(const AFile: IwbFile; const ARecord: IwbMainRecord;
  const ASeenRecords: TDictionary<Cardinal, Boolean>; var ANewRecordCount: Integer; var AMaxObjectId: Cardinal;
  var AMinObjectId: Cardinal; var AHasCellRisk: Boolean);
var
  lObjectId: Cardinal;
begin
  if not Assigned(ARecord) or (ARecord = AFile.Header) then
    Exit;

  if ARecord.LoadOrderFormID.FileID <> AFile.LoadOrderFileID then
    Exit;

  if ASeenRecords.ContainsKey(ARecord.LoadOrderFormID.ToCardinal) then
    Exit;
  ASeenRecords.Add(ARecord.LoadOrderFormID.ToCardinal, True);

  Inc(ANewRecordCount);
  lObjectId := ARecord.LoadOrderFormID.ObjectID;
  if (AMinObjectId = 0) or (lObjectId < AMinObjectId) then
    AMinObjectId := lObjectId;
  if lObjectId > AMaxObjectId then
    AMaxObjectId := lObjectId;
  if ARecord.Signature = 'CELL' then
    AHasCellRisk := True;
end;

procedure xeAutomationCollectEslRecordStatsFromElement(const AFile: IwbFile; const AElement: IwbElement;
  const ASeenRecords: TDictionary<Cardinal, Boolean>; var ANewRecordCount: Integer; var AMaxObjectId: Cardinal;
  var AMinObjectId: Cardinal; var AHasCellRisk: Boolean);
var
  lRecord: IwbMainRecord;
  lContainer: IwbContainer;
  i: Integer;
begin
  if not Assigned(AElement) then
    Exit;

  if Supports(AElement, IwbMainRecord, lRecord) then
    xeAutomationAddEslRecordStats(AFile, lRecord, ASeenRecords, ANewRecordCount, AMaxObjectId, AMinObjectId, AHasCellRisk);

  // New records created through automation live under signature GRUP containers.
  // Walk the file tree instead of trusting the shallow Records[] view so analysis
  // remains read-only but still sees freshly-created grouped records before save.
  if Supports(AElement, IwbContainer, lContainer) then
    for i := 0 to Pred(lContainer.ElementCount) do
      xeAutomationCollectEslRecordStatsFromElement(AFile, lContainer.Elements[i], ASeenRecords, ANewRecordCount, AMaxObjectId,
        AMinObjectId, AHasCellRisk);
end;

procedure xeAutomationCollectEslRecordStatsFromGroup(const AFile: IwbFile; const ASignature: TwbSignature;
  const ASeenRecords: TDictionary<Cardinal, Boolean>; var ANewRecordCount: Integer; var AMaxObjectId: Cardinal;
  var AMinObjectId: Cardinal; var AHasCellRisk: Boolean);
var
  lGroup: IwbGroupRecord;
  lObjectId: Cardinal;
  lFormId: TwbFormID;
  lRecord: IwbMainRecord;
begin
  lGroup := AFile.GroupBySignature[ASignature];
  if not Assigned(lGroup) then
    Exit;

  xeAutomationCollectEslRecordStatsFromElement(AFile, lGroup, ASeenRecords, ANewRecordCount, AMaxObjectId, AMinObjectId, AHasCellRisk);
  for lObjectId := 1 to $FFFF do begin
    lFormId := TwbFormID.FromCardinal(lObjectId).ChangeFileID(AFile.LoadOrderFileID);
    lRecord := lGroup.MainRecordByFormID[lFormId];
    if Assigned(lRecord) then
      xeAutomationAddEslRecordStats(AFile, lRecord, ASeenRecords, ANewRecordCount, AMaxObjectId, AMinObjectId, AHasCellRisk);
  end;
end;

procedure xeAutomationCollectEslRecordStatsByObjectIdScan(const AFile: IwbFile;
  const ASeenRecords: TDictionary<Cardinal, Boolean>; var ANewRecordCount: Integer; var AMaxObjectId: Cardinal;
  var AMinObjectId: Cardinal; var AHasCellRisk: Boolean);
var
  lObjectId: Cardinal;
  lFormId: TwbFormID;
  lRecord: IwbMainRecord;
begin
  if AFile.HighObjectID > $FFFF then
    Exit;

  for lObjectId := 1 to AFile.HighObjectID do begin
    lFormId := TwbFormID.FromCardinal(lObjectId).ChangeFileID(AFile.LoadOrderFileID);
    lRecord := AFile.RecordByFormID[lFormId, True, True];
    if Assigned(lRecord) then
      xeAutomationAddEslRecordStats(AFile, lRecord, ASeenRecords, ANewRecordCount, AMaxObjectId, AMinObjectId, AHasCellRisk);
  end;
end;

function xeAutomationAnalyzePluginForEsl(const AFile: IwbFile; const AFindings: TJsonArray): TJsonObject;
var
  lNewRecordCount: Integer;
  lMaxObjectId: Cardinal;
  lMinObjectId: Cardinal;
  lHasCellRisk: Boolean;
  lProtectedMessage: string;
  lRiskMessage: string;
  lBlockerMessage: string;
  lSeenRecords: TDictionary<Cardinal, Boolean>;
  lNextObjectId: Cardinal;
  lLowestObjectId: Cardinal;
  lLightObjectIdCapacity: Cardinal;
begin
  Result := TJsonObject.Create;
  try
    Result.S['fileName'] := AFile.FileName;
    Result.B['eligible'] := True;
    Result.B['canSetLightFlagWithoutCompact'] := True;
    Result.B['requiresCompact'] := False;
    Result.S['lightObjectIdLowest'] := xeAutomationObjectIdHex(xeAutomationLightObjectIdLowest(AFile));
    Result.S['lightObjectIdLimit'] := xeAutomationObjectIdHex(xeAutomationLightObjectIdLimit);
    Result.I['lightObjectIdCapacity'] := xeAutomationLightObjectIdCapacity(AFile);
    Result.A['risks'].Clear;
    Result.A['blockers'].Clear;

    lNewRecordCount := 0;
    lMaxObjectId := 0;
    lMinObjectId := 0;
    lHasCellRisk := False;
    lSeenRecords := TDictionary<Cardinal, Boolean>.Create;
    try
      xeAutomationCollectEslRecordStatsFromElement(AFile, AFile, lSeenRecords, lNewRecordCount, lMaxObjectId, lMinObjectId, lHasCellRisk);
      // The current automation creation surface can leave fresh KYWD/MISC records in
      // signature groups before the file's shallow record view catches up. Probe those
      // groups explicitly so read-only analysis reflects the live unsaved session.
      xeAutomationCollectEslRecordStatsFromGroup(AFile, 'KYWD', lSeenRecords, lNewRecordCount, lMaxObjectId, lMinObjectId, lHasCellRisk);
      xeAutomationCollectEslRecordStatsFromGroup(AFile, 'MISC', lSeenRecords, lNewRecordCount, lMaxObjectId, lMinObjectId, lHasCellRisk);
      // Unsaved new-file groups can also be visible through FormID lookup before
      // shallow record enumeration reflects them, so bounded ObjectID probing keeps
      // fresh automation fixtures and small plugins honest without scanning DLC scale.
      xeAutomationCollectEslRecordStatsByObjectIdScan(AFile, lSeenRecords, lNewRecordCount, lMaxObjectId, lMinObjectId, lHasCellRisk);
    finally
      lSeenRecords.Free;
    end;
    lNextObjectId := AFile.NextObjectID and $FFFFFF;
    if (lNextObjectId > 0) and (Pred(lNextObjectId) > lMaxObjectId) then
      lMaxObjectId := Pred(lNextObjectId);

    Result.I['newRecordCount'] := lNewRecordCount;
    Result.S['minObjectId'] := xeAutomationObjectIdHex(lMinObjectId);
    Result.S['maxObjectId'] := xeAutomationObjectIdHex(lMaxObjectId);
    lLowestObjectId := xeAutomationLightObjectIdLowest(AFile);
    lLightObjectIdCapacity := xeAutomationLightObjectIdCapacity(AFile);

    if not wbIsLightSupported then begin
      lBlockerMessage := 'Current game mode does not support light plugins';
      xeAutomationAddFindingObject(Result.A['blockers'], xeAutomationFindingUnsupportedGameMode, 'error', lBlockerMessage);
      xeAutomationAddPagedFinding(AFindings, AFile.FileName, xeAutomationFindingUnsupportedGameMode, 'error', lBlockerMessage);
    end;

    lProtectedMessage := xeAutomationProtectedAnalysisTargetMessage(AFile);
    if lProtectedMessage <> '' then begin
      xeAutomationAddFindingObject(Result.A['blockers'], xeAutomationFindingProtectedTarget, 'error', lProtectedMessage);
      xeAutomationAddPagedFinding(AFindings, AFile.FileName, xeAutomationFindingProtectedTarget, 'error', lProtectedMessage);
    end;

    if not AFile.IsEditable then begin
      lBlockerMessage := Format('Automation analysis target is read-only: %s', [AFile.FileName]);
      xeAutomationAddFindingObject(Result.A['blockers'], xeAutomationFindingNonEditableTarget, 'error', lBlockerMessage);
      xeAutomationAddPagedFinding(AFindings, AFile.FileName, xeAutomationFindingNonEditableTarget, 'error', lBlockerMessage);
    end;

    if Cardinal(lNewRecordCount) > lLightObjectIdCapacity then begin
      lBlockerMessage := Format('%s has %d new records, exceeding the light plugin ObjectID capacity of %d',
        [AFile.FileName, lNewRecordCount, lLightObjectIdCapacity]);
      xeAutomationAddFindingObject(Result.A['blockers'], xeAutomationFindingTooManyNewRecordsForLight, 'error', lBlockerMessage);
      xeAutomationAddPagedFinding(AFindings, AFile.FileName, xeAutomationFindingTooManyNewRecordsForLight, 'error', lBlockerMessage);
    end;

    // Analysis and compaction must share the same usable ObjectID range. For games
    // that reserve the hardcoded range, records below $800 also require compaction.
    if (lNewRecordCount > 0) and ((lMaxObjectId > xeAutomationLightObjectIdLimit) or (lMinObjectId < lLowestObjectId)) then begin
      Result.B['canSetLightFlagWithoutCompact'] := False;
      Result.B['requiresCompact'] := True;
      lRiskMessage := Format('%s contains new records above the light ObjectID limit and requires FormID compaction before setting ESL',
        [AFile.FileName]);
      xeAutomationAddFindingObject(Result.A['risks'], xeAutomationFindingRequiresFormIDCompaction, 'warning', lRiskMessage);
      xeAutomationAddPagedFinding(AFindings, AFile.FileName, xeAutomationFindingRequiresFormIDCompaction, 'warning', lRiskMessage);
    end;

    if lHasCellRisk then begin
      lRiskMessage := Format('%s contains new CELL records; compacting FormIDs can invalidate external references to placed content',
        [AFile.FileName]);
      xeAutomationAddFindingObject(Result.A['risks'], xeAutomationFindingNewCellRecordRisk, 'warning', lRiskMessage);
      xeAutomationAddPagedFinding(AFindings, AFile.FileName, xeAutomationFindingNewCellRecordRisk, 'warning', lRiskMessage);
    end;

    Result.B['eligible'] := (Result.A['blockers'].Count = 0) and not Result.B['requiresCompact'];
  except
    Result.Free;
    raise;
  end;
end;

procedure xeAutomationSortMainRecordsByObjectId(var ARecords: TxeAutomationMainRecords);
var
  i: Integer;
  j: Integer;
  lTemp: IwbMainRecord;
begin
  for i := Low(ARecords) to High(ARecords) do
    for j := Succ(i) to High(ARecords) do
      if ARecords[j].LoadOrderFormID.ObjectID < ARecords[i].LoadOrderFormID.ObjectID then begin
        lTemp := ARecords[i];
        ARecords[i] := ARecords[j];
        ARecords[j] := lTemp;
      end;
end;

function xeAutomationPlanCompactForEsl(const AFile: IwbFile): TxeAutomationFormIdRemaps;
var
  lRecords: TxeAutomationMainRecords;
  lTakenObjectIds: array of Boolean;
  lLowestObjectId: Cardinal;
  lNextObjectId: Cardinal;
  lObjectId: Cardinal;
  lRecord: IwbMainRecord;
  i: Integer;
begin
  SetLength(Result, 0);
  lLowestObjectId := xeAutomationLightObjectIdLowest(AFile);

  SetLength(lTakenObjectIds, Succ(xeAutomationLightObjectIdLimit));
  lRecords := xeAutomationCollectNewMainRecordsInFile(AFile);
  xeAutomationSortMainRecordsByObjectId(lRecords);

  for lRecord in lRecords do begin
    lObjectId := lRecord.LoadOrderFormID.ObjectID;
    if (lObjectId >= lLowestObjectId) and (lObjectId <= xeAutomationLightObjectIdLimit) then
      lTakenObjectIds[lObjectId] := True;
  end;

  lNextObjectId := lLowestObjectId;
  for i := Low(lRecords) to High(lRecords) do begin
    lRecord := lRecords[i];
    lObjectId := lRecord.LoadOrderFormID.ObjectID;
    if (lObjectId >= lLowestObjectId) and (lObjectId <= xeAutomationLightObjectIdLimit) then
      Continue;

    while (lNextObjectId <= xeAutomationLightObjectIdLimit) and lTakenObjectIds[lNextObjectId] do
      Inc(lNextObjectId);
    if lNextObjectId > xeAutomationLightObjectIdLimit then
      raise xeAutomationNewError(xeAutomationErrorEligibilityFailed,
        Format('%s has too many new records to compact into the light ObjectID range', [AFile.FileName]));

    SetLength(Result, Succ(Length(Result)));
    Result[High(Result)].RecordRef := lRecord;
    Result[High(Result)].OldFormID := lRecord.LoadOrderFormID;
    Result[High(Result)].NewFormID := TwbFormID.FromCardinal(lNextObjectId).ChangeFileID(AFile.LoadOrderFileID);
    lTakenObjectIds[lNextObjectId] := True;
    Inc(lNextObjectId);
  end;
end;

procedure xeAutomationAddRemapFinding(const AFindings: TJsonArray; const AKind: string; const AFile: IwbFile;
  const ARemap: TxeAutomationFormIdRemap; const AApplied: Boolean);
var
  lFinding: TJsonObject;
begin
  lFinding := TJsonObject.Create;
  try
    lFinding.S['severity'] := 'info';
    if AApplied then
      lFinding.S['code'] := 'formid_remap_applied'
    else
      lFinding.S['code'] := 'formid_remap_planned';
    lFinding.S['message'] := Format('%s FormID remap in %s: %s -> %s',
      [xeAutomationAppliedWord(AApplied), AFile.FileName, ARemap.OldFormID.ToString(True), ARemap.NewFormID.ToString(True)]);
    lFinding.O['target'].S['file'] := AFile.FileName;
    lFinding.O['target'].S['formId'] := ARemap.OldFormID.ToString(True);
    lFinding.O['target'].S['signature'] := ARemap.RecordRef.Signature;
    lFinding.S['source'] := AKind;
    if AApplied then
      lFinding.O['action'].S['kind'] := 'applied'
    else
      lFinding.O['action'].S['kind'] := 'planned';
    lFinding.O['action'].S['oldFormId'] := ARemap.OldFormID.ToString(True);
    lFinding.O['action'].S['newFormId'] := ARemap.NewFormID.ToString(True);
    AFindings.Add(lFinding);
    lFinding := nil;
  finally
    lFinding.Free;
  end;
end;

function xeAutomationAddNonEditableReferrerFindings(const AFindings: TJsonArray; const AKind: string; const AFile: IwbFile;
  const ARemap: TxeAutomationFormIdRemap): Integer;
var
  lFinding: TJsonObject;
  lMaster: IwbMainRecord;
  lReferrer: IwbMainRecord;
  i: Integer;
begin
  Result := 0;
  lMaster := ARemap.RecordRef.MasterOrSelf;
  for i := 0 to Pred(lMaster.ReferencedByCount) do begin
    lReferrer := lMaster.ReferencedBy[i];
    // External editable referrers are safe: the apply sweep rewrites them and
    // reports their files dirty. Only records/files xEdit cannot edit would keep
    // stale links after the target FormID is compacted.
    if Assigned(lReferrer) and ((not lReferrer.IsEditable) or (not lReferrer._File.IsEditable)) then begin
      Inc(Result);
      lFinding := TJsonObject.Create;
      try
        lFinding.S['severity'] := 'error';
        lFinding.S['code'] := xeAutomationFindingNonEditableReferrer;
        lFinding.S['message'] := Format('%s cannot compact %s because non-editable referrer %s:%s would retain %s',
          [AKind, ARemap.OldFormID.ToString(True), lReferrer._File.FileName, lReferrer.LoadOrderFormID.ToString(True),
           ARemap.OldFormID.ToString(True)]);
        lFinding.O['target'].S['file'] := AFile.FileName;
        lFinding.O['target'].S['formId'] := ARemap.OldFormID.ToString(True);
        lFinding.O['target'].S['newFormId'] := ARemap.NewFormID.ToString(True);
        lFinding.O['target'].S['signature'] := ARemap.RecordRef.Signature;
        lFinding.O['referrer'].S['file'] := lReferrer._File.FileName;
        lFinding.O['referrer'].S['formId'] := lReferrer.LoadOrderFormID.ToString(True);
        lFinding.O['referrer'].S['signature'] := lReferrer.Signature;
        lFinding.S['source'] := AKind;
        AFindings.Add(lFinding);
        lFinding := nil;
      finally
        lFinding.Free;
      end;
    end;
  end;
end;

function xeAutomationAddNonEditableReferrerFindingsForBatch(const AFindings: TJsonArray; const AKind: string;
  const AFile: IwbFile; const ARemaps: TxeAutomationFormIdRemaps): Integer;
var
  lRemap: TxeAutomationFormIdRemap;
begin
  Result := 0;
  // Reference metadata is built immediately before this scan by the caller. Keeping
  // the policy as findings lets dry-run report stale-reference risk while apply mode
  // can fail before any FormID/header mutation is attempted.
  for lRemap in ARemaps do
    Inc(Result, xeAutomationAddNonEditableReferrerFindings(AFindings, AKind, AFile, lRemap));
end;

procedure xeAutomationBuildLoadedReferenceGraph;
var
  lModules: TwbModuleInfos;
  lFile: IwbFile;
  i: Integer;
begin
  // Referrers can live outside the compact target. Build references for every
  // loaded plugin so automation can fail on stale non-editable callers instead of
  // seeing only the target file's outgoing links.
  lModules := wbModulesByLoadOrder;
  for i := Low(lModules) to High(lModules) do begin
    lFile := xeAutomationTryPluginFileFromModule(lModules[i]);
    if Assigned(lFile) then
      lFile.BuildOrLoadRef(False);
  end;
end;

procedure xeAutomationRequireWritableFormIdRemapTargets(const ARemap: TxeAutomationFormIdRemap);
var
  lMaster: IwbMainRecord;
  lRecord: IwbMainRecord;
  i: Integer;
begin
  xeAutomationRequireWritableEslMutationTarget(ARemap.RecordRef._File);

  for i := 0 to Pred(ARemap.RecordRef.OverrideCount) do begin
    lRecord := ARemap.RecordRef.Overrides[i];
    if Assigned(lRecord) then
      xeAutomationRequireWritableEslMutationTarget(lRecord._File);
  end;

  lMaster := ARemap.RecordRef.MasterOrSelf;
  for i := 0 to Pred(lMaster.ReferencedByCount) do begin
    lRecord := lMaster.ReferencedBy[i];
    if Assigned(lRecord) and lRecord.IsEditable then
      xeAutomationRequireWritableEslMutationTarget(lRecord._File);
  end;
end;

procedure xeAutomationRequireWritableFormIdRemapBatch(const ARemaps: TxeAutomationFormIdRemaps);
var
  lRemap: TxeAutomationFormIdRemap;
begin
  // Preflight every editable override/referrer before the first FormID assignment so
  // automation never partially compacts a target then discovers a non-target file is protected.
  for lRemap in ARemaps do
    xeAutomationRequireWritableFormIdRemapTargets(lRemap);
end;

procedure xeAutomationApplyFormIdRemap(const ARemap: TxeAutomationFormIdRemap; const ADirtyFiles: TJsonArray);
var
  lMaster: IwbMainRecord;
  lReferencedBy: TDynMainRecords;
  lOverrides: TDynMainRecords;
  i: Integer;
begin
  lMaster := ARemap.RecordRef.MasterOrSelf;
  SetLength(lReferencedBy, lMaster.ReferencedByCount);
  for i := 0 to Pred(lMaster.ReferencedByCount) do
    lReferencedBy[i] := lMaster.ReferencedBy[i];

  SetLength(lOverrides, ARemap.RecordRef.OverrideCount);
  for i := 0 to Pred(ARemap.RecordRef.OverrideCount) do
    lOverrides[i] := ARemap.RecordRef.Overrides[i];

  ARemap.RecordRef.LoadOrderFormID := ARemap.NewFormID;
  xeAutomationAddDirtyFile(ADirtyFiles, ARemap.RecordRef._File);
  for i := Low(lOverrides) to High(lOverrides) do
    if Assigned(lOverrides[i]) then begin
      lOverrides[i].LoadOrderFormID := ARemap.NewFormID;
      xeAutomationAddDirtyFile(ADirtyFiles, lOverrides[i]._File);
    end;

  // The GUI path prompts before touching referrers; automation has no dialog, so
  // it applies the same native CompareExchange sweep deterministically in memory
  // and reports every file where that sweep actually changed a reference.
  for i := Low(lReferencedBy) to High(lReferencedBy) do
    if Assigned(lReferencedBy[i]) and lReferencedBy[i].IsEditable then
      if lReferencedBy[i].CompareExchangeFormID(ARemap.OldFormID, ARemap.NewFormID) then
        xeAutomationAddDirtyFile(ADirtyFiles, lReferencedBy[i]._File);
end;

procedure xeAutomationUpdateNextObjectIdAfterCompact(const AFile: IwbFile);
var
  lRecords: TxeAutomationMainRecords;
  lRecord: IwbMainRecord;
  lMaxObjectId: Cardinal;
begin
  lMaxObjectId := 0;
  lRecords := xeAutomationCollectNewMainRecordsInFile(AFile);
  for lRecord in lRecords do
    if lRecord.LoadOrderFormID.ObjectID > lMaxObjectId then
      lMaxObjectId := lRecord.LoadOrderFormID.ObjectID;
  if lMaxObjectId < xeAutomationLightObjectIdLimit then
    AFile.NextObjectID := Succ(lMaxObjectId)
  else
    AFile.NextObjectID := xeAutomationLightObjectIdLimit;
end;

procedure xeAutomationWriteCompactResultFile(const ATarget: TJsonArray; const AFile: IwbFile;
  const ARemaps: TxeAutomationFormIdRemaps; const AApplied: Boolean);
var
  lFileResult: TJsonObject;
  lRemapObject: TJsonObject;
  lRemap: TxeAutomationFormIdRemap;
begin
  lFileResult := TJsonObject.Create;
  try
    lFileResult.S['fileName'] := AFile.FileName;
    lFileResult.B['changed'] := AApplied and (Length(ARemaps) > 0);
    lFileResult.I['remapCount'] := Length(ARemaps);
    lFileResult.B['eslFlagChanged'] := False;
    lFileResult.B['isLight'] := AFile.IsLight;
    for lRemap in ARemaps do begin
      lRemapObject := TJsonObject.Create;
      try
        lRemapObject.S['file'] := AFile.FileName;
        lRemapObject.S['signature'] := lRemap.RecordRef.Signature;
        lRemapObject.S['oldFormId'] := lRemap.OldFormID.ToString(True);
        lRemapObject.S['newFormId'] := lRemap.NewFormID.ToString(True);
        lFileResult.A['remaps'].Add(lRemapObject);
        lRemapObject := nil;
      finally
        lRemapObject.Free;
      end;
    end;
    ATarget.Add(lFileResult);
    lFileResult := nil;
  finally
    lFileResult.Free;
  end;
end;

procedure xeAutomationPluginFormIdsCompactForEslJob(const AJobId: string; const ADryRun, ADryRunSpecified: Boolean;
  const ATarget, AOptions: TJsonObject; const AFindings: TJsonArray; const ASummary, AResult, AFailure: TJsonObject);
var
  lFiles: TJsonArray;
  lFile: IwbFile;
  lRemaps: TxeAutomationFormIdRemaps;
  lFileName: string;
  i: Integer;
  lRemap: TxeAutomationFormIdRemap;
begin
  lFiles := ATarget.A['files'];
  ASummary.I['targets'] := lFiles.Count;
  ASummary.I['planned'] := 0;
  ASummary.I['applied'] := 0;
  ASummary.I['findings'] := 0;
  ASummary.B['changed'] := False;
  ASummary.B['requiresSave'] := False;
  ASummary.A['dirtyFiles'].Clear;
  AResult.A['files'].Clear;

  for i := 0 to Pred(lFiles.Count) do begin
    lFileName := Trim(lFiles.S[i]);
    lFile := xeAutomationRequirePluginFile(lFileName);
    if not ADryRun then
      // Apply mode mutates FormIDs only in the loaded xEdit session. The explicit
      // save boundary is preserved by not calling any disk-writing file routines.
      xeAutomationRequireWritableEslMutationTarget(lFile);
    lRemaps := xeAutomationPlanCompactForEsl(lFile);
    if Length(lRemaps) > 0 then begin
      xeAutomationBuildLoadedReferenceGraph;
      if xeAutomationAddNonEditableReferrerFindingsForBatch(AFindings, xeAutomationFormIdsCompactForEslKind, lFile, lRemaps) > 0 then
        if not ADryRun then
          raise xeAutomationNewError(xeAutomationFindingNonEditableReferrer,
            Format('%s has non-editable referrers that would remain stale after FormID compaction', [lFile.FileName]));
    end;
    if not ADryRun then
      xeAutomationRequireWritableFormIdRemapBatch(lRemaps);

    for lRemap in lRemaps do begin
      xeAutomationAddRemapFinding(AFindings, xeAutomationFormIdsCompactForEslKind, lFile, lRemap, not ADryRun);
      if ADryRun then
        ASummary.I['planned'] := ASummary.I['planned'] + 1
      else begin
        lFile.BuildOrLoadRef(False);
        xeAutomationApplyFormIdRemap(lRemap, ASummary.A['dirtyFiles']);
        ASummary.I['applied'] := ASummary.I['applied'] + 1;
      end;
    end;

    if not ADryRun and (Length(lRemaps) > 0) then begin
      xeAutomationUpdateNextObjectIdAfterCompact(lFile);
      ASummary.B['changed'] := True;
      ASummary.B['requiresSave'] := True;
      xeAutomationAddDirtyFile(ASummary.A['dirtyFiles'], lFile);
    end;
    xeAutomationWriteCompactResultFile(AResult.A['files'], lFile, lRemaps, not ADryRun);
  end;

  ASummary.I['findings'] := AFindings.Count;
end;

procedure xeAutomationAddEslApplyFinding(const AFindings: TJsonArray; const AFile: IwbFile; const AOldESL, ANewESL: Boolean;
  const AApplied: Boolean);
var
  lFinding: TJsonObject;
begin
  lFinding := TJsonObject.Create;
  try
    lFinding.S['severity'] := 'info';
    if AApplied then
      lFinding.S['code'] := 'esl_flag_applied'
    else
      lFinding.S['code'] := 'esl_flag_planned';
    lFinding.S['message'] := Format('%s ESL header flag for %s: %s -> %s',
      [xeAutomationAppliedWord(AApplied), AFile.FileName, BoolToStr(AOldESL, True), BoolToStr(ANewESL, True)]);
    lFinding.O['target'].S['file'] := AFile.FileName;
    lFinding.S['source'] := xeAutomationEslApplyKind;
    if AApplied then
      lFinding.O['action'].S['kind'] := 'applied'
    else
      lFinding.O['action'].S['kind'] := 'planned';
    lFinding.O['action'].B['oldEsl'] := AOldESL;
    lFinding.O['action'].B['newEsl'] := ANewESL;
    AFindings.Add(lFinding);
    lFinding := nil;
  finally
    lFinding.Free;
  end;
end;

function xeAutomationEnsureEslApplyEligibility(const AFile: IwbFile; const AAllowAfterCompact: Boolean; const AFindings: TJsonArray): Boolean;
var
  lAnalysis: TJsonObject;
  lBlockerCount: Integer;
begin
  Result := False;
  lAnalysis := xeAutomationAnalyzePluginForEsl(AFile, AFindings);
  try
    lBlockerCount := lAnalysis.A['blockers'].Count;
    if lAnalysis.B['eligible'] then
      Exit;
    if AAllowAfterCompact and (lBlockerCount = 0) and lAnalysis.B['requiresCompact'] then begin
      Result := True;
      Exit;
    end;
    raise xeAutomationNewError(xeAutomationErrorEligibilityFailed,
      Format('%s is not currently eligible for ESL flag application', [AFile.FileName]));
  finally
    lAnalysis.Free;
  end;
end;

procedure xeAutomationWriteEslApplyResultFile(const ATarget: TJsonArray; const AFile: IwbFile;
  const AOldFlags, ANewFlags: TJsonObject; const ARemaps: TxeAutomationFormIdRemaps; const ACompacted: Boolean; const AChanged: Boolean);
var
  lFileResult: TJsonObject;
  lRemapObject: TJsonObject;
  lRemap: TxeAutomationFormIdRemap;
begin
  lFileResult := TJsonObject.Create;
  try
    lFileResult.S['fileName'] := AFile.FileName;
    lFileResult.O['oldFlags'].Assign(AOldFlags);
    lFileResult.O['newFlags'].Assign(ANewFlags);
    lFileResult.B['compacted'] := ACompacted;
    lFileResult.I['remapCount'] := Length(ARemaps);
    for lRemap in ARemaps do begin
      lRemapObject := TJsonObject.Create;
      try
        lRemapObject.S['file'] := AFile.FileName;
        lRemapObject.S['signature'] := lRemap.RecordRef.Signature;
        lRemapObject.S['oldFormId'] := lRemap.OldFormID.ToString(True);
        lRemapObject.S['newFormId'] := lRemap.NewFormID.ToString(True);
        lFileResult.A['remaps'].Add(lRemapObject);
        lRemapObject := nil;
      finally
        lRemapObject.Free;
      end;
    end;
    lFileResult.B['changed'] := AChanged;
    ATarget.Add(lFileResult);
    lFileResult := nil;
  finally
    lFileResult.Free;
  end;
end;

procedure xeAutomationPluginEslApplyJob(const AJobId: string; const ADryRun, ADryRunSpecified: Boolean;
  const ATarget, AOptions: TJsonObject; const AFindings: TJsonArray; const ASummary, AResult, AFailure: TJsonObject);
var
  lFiles: TJsonArray;
  lFile: IwbFile;
  lAllowAfterCompact: Boolean;
  lOldFlags: TJsonObject;
  lNewFlags: TJsonObject;
  lRemaps: TxeAutomationFormIdRemaps;
  lRemap: TxeAutomationFormIdRemap;
  lRequiresCompact: Boolean;
  lChanged: Boolean;
  i: Integer;
begin
  lFiles := ATarget.A['files'];
  lAllowAfterCompact := xeAutomationReadBooleanOption(AOptions, 'allowAfterCompact', False);
  ASummary.I['targets'] := lFiles.Count;
  ASummary.I['planned'] := 0;
  ASummary.I['applied'] := 0;
  ASummary.I['findings'] := 0;
  ASummary.B['changed'] := False;
  ASummary.B['requiresSave'] := False;
  ASummary.A['dirtyFiles'].Clear;
  AResult.A['files'].Clear;

  for i := 0 to Pred(lFiles.Count) do begin
    lFile := xeAutomationRequirePluginFile(Trim(lFiles.S[i]));
    if not ADryRun then
      // ESL apply may optionally compact first, but both mutations still stay in
      // daemon memory; session.save remains the only disk persistence boundary.
      xeAutomationRequireWritableEslMutationTarget(lFile);
    lRequiresCompact := xeAutomationEnsureEslApplyEligibility(lFile, lAllowAfterCompact, AFindings);
    SetLength(lRemaps, 0);
    if lRequiresCompact then begin
      lRemaps := xeAutomationPlanCompactForEsl(lFile);
      if Length(lRemaps) > 0 then begin
        xeAutomationBuildLoadedReferenceGraph;
        if xeAutomationAddNonEditableReferrerFindingsForBatch(AFindings, xeAutomationEslApplyKind, lFile, lRemaps) > 0 then
          if not ADryRun then
            raise xeAutomationNewError(xeAutomationFindingNonEditableReferrer,
              Format('%s has non-editable referrers that would remain stale after FormID compaction', [lFile.FileName]));
      end;
      if not ADryRun then begin
        xeAutomationRequireWritableFormIdRemapBatch(lRemaps);
        for lRemap in lRemaps do begin
          xeAutomationApplyFormIdRemap(lRemap, ASummary.A['dirtyFiles']);
          xeAutomationAddRemapFinding(AFindings, xeAutomationEslApplyKind, lFile, lRemap, True);
        end;
        if Length(lRemaps) > 0 then begin
          xeAutomationUpdateNextObjectIdAfterCompact(lFile);
          ASummary.B['changed'] := True;
          ASummary.B['requiresSave'] := True;
          xeAutomationAddDirtyFile(ASummary.A['dirtyFiles'], lFile);
        end;
      end else
        for lRemap in lRemaps do
          xeAutomationAddRemapFinding(AFindings, xeAutomationEslApplyKind, lFile, lRemap, False);
    end;

    lOldFlags := xeAutomationNewHeaderFlags(lFile);
    try
      if not ADryRun and not lFile.IsLight then
        lFile.IsLight := True;
      lNewFlags := xeAutomationNewHeaderFlags(lFile);
      try
        if ADryRun then
          lNewFlags.B['esl'] := True;
        lChanged := lOldFlags.B['esl'] <> lNewFlags.B['esl'];
        xeAutomationAddEslApplyFinding(AFindings, lFile, lOldFlags.B['esl'], lNewFlags.B['esl'], not ADryRun);
        if ADryRun then
          ASummary.I['planned'] := ASummary.I['planned'] + 1
        else if lChanged then begin
          ASummary.I['applied'] := ASummary.I['applied'] + 1;
          ASummary.B['changed'] := True;
          ASummary.B['requiresSave'] := True;
          xeAutomationAddDirtyFile(ASummary.A['dirtyFiles'], lFile);
        end;
        xeAutomationWriteEslApplyResultFile(AResult.A['files'], lFile, lOldFlags, lNewFlags, lRemaps, lRequiresCompact and not ADryRun,
          lChanged or (not ADryRun and (Length(lRemaps) > 0)));
      finally
        lNewFlags.Free;
      end;
    finally
      lOldFlags.Free;
    end;
  end;

  ASummary.I['findings'] := AFindings.Count;
end;

procedure xeAutomationPluginEslAnalyzeJob(const AJobId: string; const ADryRun, ADryRunSpecified: Boolean;
  const ATarget, AOptions: TJsonObject; const AFindings: TJsonArray; const ASummary, AResult, AFailure: TJsonObject);
var
  lFiles: TJsonArray;
  lFile: IwbFile;
  lAnalysis: TJsonObject;
  i: Integer;
begin
  lFiles := ATarget.A['files'];
  ASummary.I['targets'] := lFiles.Count;
  ASummary.I['eligible'] := 0;
  ASummary.I['ineligible'] := 0;
  ASummary.I['findings'] := 0;
  ASummary.B['changed'] := False;
  ASummary.B['requiresSave'] := False;
  ASummary.A['dirtyFiles'].Clear;
  AResult.A['files'].Clear;

  for i := 0 to Pred(lFiles.Count) do begin
    // File lookup is the execution boundary: malformed target shape was rejected at
    // jobs.start, while absent loaded files remain normal job execution failures.
    lFile := xeAutomationRequirePluginFile(Trim(lFiles.S[i]));
    lAnalysis := xeAutomationAnalyzePluginForEsl(lFile, AFindings);
    try
      if lAnalysis.B['eligible'] then
        ASummary.I['eligible'] := ASummary.I['eligible'] + 1
      else
        ASummary.I['ineligible'] := ASummary.I['ineligible'] + 1;
      AResult.A['files'].Add(lAnalysis);
      lAnalysis := nil;
    finally
      lAnalysis.Free;
    end;
  end;

  ASummary.I['findings'] := AFindings.Count;
end;

procedure xeAutomationRegisterPluginAnalysisCommands;
begin
  // Capability advertising is registry-derived; registering these kinds here is
  // the single point that makes Task 3 compact/apply visible to clients.
  xeAutomationRegisterJobKindWithValidator(xeAutomationEslAnalyzeKind, xeAutomationPluginEslAnalyzeJob,
    xeAutomationValidateEslAnalyzeStart);
  xeAutomationRegisterJobKindWithValidator(xeAutomationFormIdsCompactForEslKind, xeAutomationPluginFormIdsCompactForEslJob,
    xeAutomationValidateCompactForEslStart);
  xeAutomationRegisterJobKindWithValidator(xeAutomationEslApplyKind, xeAutomationPluginEslApplyJob,
    xeAutomationValidateEslApplyStart);
end;

end.
