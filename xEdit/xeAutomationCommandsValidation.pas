{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeAutomationCommandsValidation;

interface

procedure xeAutomationRegisterValidationCommands;

implementation

uses
  Classes,
  SysUtils,
  JsonDataObjects,
  wbInterface,
  xeAutomationDataLookup,
  xeAutomationErrors,
  xeAutomationJobs,
  xeAutomationObjectModel;

const
  xeAutomationValidationCheckForErrorsKind = 'validation.check_for_errors';
  xeAutomationValidationCheckForItmKind = 'validation.check_for_itm';
  xeAutomationValidationCheckForDeletedRefsKind = 'validation.check_for_deleted_refs';

function xeAutomationValidationKindName(const AKind: string): string;
begin
  Result := AKind;
end;

procedure xeAutomationValidateValidationStart(var ADryRun: Boolean; const ADryRunSpecified: Boolean;
  const ATarget, AOptions: TJsonObject);
var
  lFiles: TJsonArray;
  i: Integer;
begin
  if not Assigned(ATarget) then
    raise xeAutomationInvalidRequest('Automation validation target is required');
  if not ATarget.Contains('files') then
    raise xeAutomationInvalidRequest('Automation validation target.files is required');
  if ATarget.Types['files'] <> jdtArray then
    raise xeAutomationInvalidRequest('Automation validation target.files must be an array');

  lFiles := ATarget.A['files'];
  if lFiles.Count = 0 then
    raise xeAutomationInvalidRequest('Automation validation target.files must not be empty');
  for i := 0 to Pred(lFiles.Count) do
    if lFiles.Types[i] <> jdtString then
      raise xeAutomationInvalidRequest('Automation validation target.files entries must be strings');

  // Validation kinds are non-mutating even when legacy clients send dryRun:false.
  // Normalize the stored job snapshot to dryRun=true so the contract is visible.
  ADryRun := True;
end;

procedure xeAutomationWriteValidationTarget(const ATarget: TJsonObject; const AFile: IwbFile;
  const ARecord: IwbMainRecord; const APath: string);
begin
  if Assigned(AFile) then
    ATarget.S['file'] := AFile.FileName;
  if Assigned(ARecord) then begin
    ATarget.S['formId'] := ARecord.LoadOrderFormID.ToString(True);
    ATarget.S['signature'] := ARecord.Signature;
  end;
  ATarget.S['path'] := APath;
end;

procedure xeAutomationAddValidationFinding(const AFindings: TJsonArray; const ASource, ASeverity, ACode,
  AMessage: string; const AFile: IwbFile; const ARecord: IwbMainRecord; const APath: string);
var
  lFinding: TJsonObject;
begin
  lFinding := TJsonObject.Create;
  try
    lFinding.S['severity'] := ASeverity;
    lFinding.S['code'] := ACode;
    lFinding.S['message'] := AMessage;
    xeAutomationWriteValidationTarget(lFinding.O['target'], AFile, ARecord, APath);
    lFinding.S['source'] := ASource;
    lFinding.O['action'].S['kind'] := 'none';
    lFinding.O['action'].S['reason'] := 'validation_only';
    AFindings.Add(lFinding);
    lFinding := nil;
  finally
    lFinding.Free;
  end;
end;

function xeAutomationDeletedRefCanBeSafelyUndeleted(const ARecord: IwbMainRecord): Boolean;
var
  lLinksToRecord: IwbMainRecord;
begin
  Result := False;
  if not Assigned(ARecord) then
    Exit;
  if ARecord.Signature = 'NAVM' then
    Exit;
  lLinksToRecord := ARecord.MasterOrSelf.BaseRecord;
  if ARecord.IsInjected or (not Assigned(lLinksToRecord)) then
    Exit;
  if (wbGameMode in [gmFNV]) and (lLinksToRecord.Signature = 'TREE') and lLinksToRecord.Flags.HasLODtree then
    Exit;
  Result := True;
end;

function xeAutomationIsDeletedRefSignature(const ARecord: IwbMainRecord): Boolean;
begin
  Result := Assigned(ARecord) and (
    (ARecord.Signature = 'REFR') or
    (ARecord.Signature = 'PGRE') or
    (ARecord.Signature = 'PMIS') or
    (ARecord.Signature = 'ACHR') or
    (ARecord.Signature = 'ACRE') or
    (ARecord.Signature = 'NAVM') or
    (ARecord.Signature = 'PARW') or
    (ARecord.Signature = 'PBAR') or
    (ARecord.Signature = 'PBEA') or
    (ARecord.Signature = 'PCON') or
    (ARecord.Signature = 'PFLA') or
    (ARecord.Signature = 'PHZD'));
end;

function xeAutomationRecordBelongsToFile(const AFile: IwbFile; const ARecord: IwbMainRecord): Boolean;
begin
  Result := Assigned(AFile) and Assigned(ARecord) and Assigned(ARecord._File) and SameText(ARecord._File.FileName, AFile.FileName);
end;

function xeAutomationSerializedMainRecordsEqual(const ALeft, ARight: IwbMainRecord): Boolean;
var
  lLeftStream: TMemoryStream;
  lRightStream: TMemoryStream;
begin
  Result := False;
  if (not Assigned(ALeft)) or (not Assigned(ARight)) then
    Exit;

  lLeftStream := TMemoryStream.Create;
  try
    lRightStream := TMemoryStream.Create;
    try
      // ContentEquals deliberately refuses modified records. Validation still has
      // to classify freshly created unsaved overrides, so compare the would-be
      // serialized record bytes without resetting modified state.
      ALeft.WriteToStream(lLeftStream, rmNo);
      ARight.WriteToStream(lRightStream, rmNo);
      Result := (lLeftStream.Size = lRightStream.Size) and
        ((lLeftStream.Size = 0) or CompareMem(lLeftStream.Memory, lRightStream.Memory, lLeftStream.Size));
    finally
      lRightStream.Free;
    end;
  finally
    lLeftStream.Free;
  end;
end;

function xeAutomationElementContentEquals(const ALeft, ARight: IwbElement): Boolean;
var
  lLeftContainer: IwbContainerElementRef;
  lRightContainer: IwbContainerElementRef;
  lLeftStart: Integer;
  lRightStart: Integer;
  lCompareCount: Integer;
  lLeftIsContainer: Boolean;
  lRightIsContainer: Boolean;
  i: Integer;
begin
  Result := False;
  if (not Assigned(ALeft)) or (not Assigned(ARight)) then
    Exit;
  if ALeft.ElementType <> ARight.ElementType then
    Exit;

  lLeftIsContainer := Supports(ALeft, IwbContainerElementRef, lLeftContainer);
  lRightIsContainer := Supports(ARight, IwbContainerElementRef, lRightContainer);
  if lLeftIsContainer or lRightIsContainer then begin
    if (not lLeftIsContainer) or (not lRightIsContainer) then
      Exit;

    // Main-record headers contain file-local metadata such as FormID ownership.
    // ITM semantics care about user data below those additional header elements.
    lLeftStart := lLeftContainer.AdditionalElementCount;
    lRightStart := lRightContainer.AdditionalElementCount;
    lCompareCount := lLeftContainer.ElementCount - lLeftStart;
    if lCompareCount <> (lRightContainer.ElementCount - lRightStart) then
      Exit;

    for i := 0 to Pred(lCompareCount) do
      if not xeAutomationElementContentEquals(lLeftContainer.Elements[lLeftStart + i], lRightContainer.Elements[lRightStart + i]) then
        Exit;

    Result := True;
    Exit;
  end;

  Result := SameText(ALeft.BaseName, ARight.BaseName) and (ALeft.EditValue = ARight.EditValue);
end;

procedure xeAutomationRunCheckForErrors(const ASource: string; const AFile: IwbFile; const AFindings: TJsonArray;
  var ACheckedRecords: Integer);
var
  lLastErrorRecord: IwbMainRecord;
  lFindingsBefore: Integer;

  procedure CheckElement(const AElement: IwbElement);
  var
    lContainer: IwbContainerElementRef;
    lError: string;
    lRecord: IwbMainRecord;
    i: Integer;
  begin
    if not Assigned(AElement) then
      Exit;

    lError := AElement.Check;
    if lError <> '' then begin
      lRecord := AElement.ContainingMainRecord;
      if Assigned(lRecord) and (lRecord <> lLastErrorRecord) then
        lLastErrorRecord := lRecord;
      xeAutomationAddValidationFinding(AFindings, ASource, 'error', xeAutomationFindingValidationCheckError,
        lError, AFile, lRecord, AElement.Path);
    end;
    if AElement.ElementType = etMainRecord then
      Inc(ACheckedRecords);

    if Supports(AElement, IwbContainerElementRef, lContainer) then
      for i := 0 to Pred(lContainer.ElementCount) do
        CheckElement(lContainer.Elements[i]);
  end;
begin
  lLastErrorRecord := nil;
  lFindingsBefore := AFindings.Count;
  // This mirrors the GUI check-for-errors traversal without progress/UI writes;
  // automation needs machine-readable findings and must not depend on selection.
  CheckElement(AFile);
  if AFindings.Count = lFindingsBefore then
    xeAutomationAddValidationFinding(AFindings, ASource, 'info', xeAutomationFindingValidationNoErrorsFound,
      Format('No xEdit check errors found in %s', [AFile.FileName]), AFile, nil, '');
end;

procedure xeAutomationRunCheckForItm(const ASource: string; const AFile: IwbFile; const AFindings: TJsonArray;
  var ACheckedRecords: Integer);
var
  lFindingsBefore: Integer;

  function IsIdenticalToMaster(const ARecord: IwbMainRecord): Boolean;
  var
    lMaster: IwbMainRecord;
  begin
    Result := False;
    if not Assigned(ARecord) then
      Exit;
    lMaster := ARecord.MasterOrSelf;
    if (not Assigned(lMaster)) or lMaster.Equals(ARecord) or lMaster.IsInjected then
      Exit;
    // Fresh automation-created overrides may not have GUI conflict state populated
    // yet. Compare from the master side so modified-state flags on the override do
    // not hide an otherwise identical record from validation-only ITM reporting.
    Result := lMaster.ContentEquals(ARecord) or xeAutomationSerializedMainRecordsEqual(lMaster, ARecord) or
      xeAutomationElementContentEquals(lMaster, ARecord);
  end;

  procedure CheckElement(const AElement: IwbElement);
  var
    lContainer: IwbContainerElementRef;
    lRecord: IwbMainRecord;
    i: Integer;
  begin
    if not Assigned(AElement) then
      Exit;

    if Supports(AElement, IwbMainRecord, lRecord) then begin
      if xeAutomationRecordBelongsToFile(AFile, lRecord) then begin
        Inc(ACheckedRecords);
        if IsIdenticalToMaster(lRecord) or
          ((not lRecord.MasterOrSelf.IsInjected) and ((lRecord.ConflictThis = ctIdenticalToMaster) or
          ((lRecord.ConflictThis = ctConflictBenign) and (lRecord.Signature = 'NAVM')))) then
          xeAutomationAddValidationFinding(AFindings, ASource, 'warning', xeAutomationFindingValidationItmRecord,
            Format('Identical to master record: %s', [lRecord.Name]), AFile, lRecord, '');
      end;
    end;

    if Supports(AElement, IwbContainerElementRef, lContainer) then
      for i := 0 to Pred(lContainer.ElementCount) do
        CheckElement(lContainer.Elements[i]);
  end;
begin
  lFindingsBefore := AFindings.Count;
  // The GUI cleaner uses filtered tree conflict state. This read-only seam uses the
  // same native conflict flags directly, avoiding filter setup and Remove calls.
  CheckElement(AFile);
  if AFindings.Count = lFindingsBefore then
    xeAutomationAddValidationFinding(AFindings, ASource, 'info', xeAutomationFindingValidationNoItmRecordsFound,
      Format('No identical-to-master records found in %s', [AFile.FileName]), AFile, nil, '');
end;

procedure xeAutomationRunCheckForDeletedRefs(const ASource: string; const AFile: IwbFile; const AFindings: TJsonArray;
  var ACheckedRecords: Integer);
var
  lFindingsBefore: Integer;

  procedure CheckElement(const AElement: IwbElement);
  var
    lContainer: IwbContainerElementRef;
    lRecord: IwbMainRecord;
    lCode: string;
    lSeverity: string;
    lMessage: string;
    i: Integer;
  begin
    if not Assigned(AElement) then
      Exit;

    if Supports(AElement, IwbMainRecord, lRecord) then begin
      if xeAutomationRecordBelongsToFile(AFile, lRecord) then begin
        Inc(ACheckedRecords);
        if lRecord.IsEditable and lRecord.IsDeleted and xeAutomationIsDeletedRefSignature(lRecord) then begin
          lCode := xeAutomationFindingValidationDeletedReference;
          lSeverity := 'warning';
          lMessage := Format('Deleted reference: %s', [lRecord.Name]);
          if lRecord.Signature = 'NAVM' then begin
            lCode := xeAutomationFindingValidationDeletedNavmesh;
            lSeverity := 'error';
            lMessage := Format('Deleted NavMesh cannot be safely undeleted by xEdit cleaning: %s', [lRecord.Name]);
          end else if not xeAutomationDeletedRefCanBeSafelyUndeleted(lRecord) then begin
            lCode := xeAutomationFindingValidationDeletedReferenceSkipped;
            lSeverity := 'info';
            lMessage := Format('Deleted reference cannot be safely undeleted by xEdit cleaning: %s', [lRecord.Name]);
          end;
          xeAutomationAddValidationFinding(AFindings, ASource, lSeverity, lCode, lMessage, AFile, lRecord, '');
        end;
      end;
    end;

    if Supports(AElement, IwbContainerElementRef, lContainer) then
      for i := 0 to Pred(lContainer.ElementCount) do
        CheckElement(lContainer.Elements[i]);
  end;
begin
  lFindingsBefore := AFindings.Count;
  // Count/report only: the cleaning counterpart may undelete/disable later, but
  // validation must never toggle flags or remove fields from loaded records.
  CheckElement(AFile);
  if AFindings.Count = lFindingsBefore then
    xeAutomationAddValidationFinding(AFindings, ASource, 'info', xeAutomationFindingValidationNoDeletedRefsFound,
      Format('No deleted references found in %s', [AFile.FileName]), AFile, nil, '');
end;

procedure xeAutomationRunValidationJob(const AKind: string; const ATarget: TJsonObject; const AFindings: TJsonArray;
  const ASummary, AResult: TJsonObject);
var
  lFiles: TJsonArray;
  lFile: IwbFile;
  lFileResult: TJsonObject;
  lBeforeModified: Boolean;
  lAfterModified: Boolean;
  lCheckedRecords: Integer;
  lFindingsBefore: Integer;
  i: Integer;
begin
  lFiles := ATarget.A['files'];
  ASummary.S['kind'] := AKind;
  ASummary.B['validationOnly'] := True;
  ASummary.I['fileCount'] := lFiles.Count;
  AResult.A['files'].Clear;

  for i := 0 to Pred(lFiles.Count) do begin
    lFile := xeAutomationRequirePluginFile(lFiles.S[i]);
    lBeforeModified := lFile.Modified;
    lCheckedRecords := 0;
    lFindingsBefore := AFindings.Count;

    if SameText(AKind, xeAutomationValidationCheckForErrorsKind) then
      xeAutomationRunCheckForErrors(AKind, lFile, AFindings, lCheckedRecords)
    else if SameText(AKind, xeAutomationValidationCheckForItmKind) then
      xeAutomationRunCheckForItm(AKind, lFile, AFindings, lCheckedRecords)
    else if SameText(AKind, xeAutomationValidationCheckForDeletedRefsKind) then
      xeAutomationRunCheckForDeletedRefs(AKind, lFile, AFindings, lCheckedRecords)
    else
      raise xeAutomationNewError(xeAutomationErrorUnknownJobKind, Format('Automation validation kind not registered: %s', [AKind]));

    lAfterModified := lFile.Modified;
    lFileResult := TJsonObject.Create;
    try
      lFileResult.S['fileName'] := lFile.FileName;
      lFileResult.I['checkedRecords'] := lCheckedRecords;
      lFileResult.I['findingCount'] := AFindings.Count - lFindingsBefore;
      lFileResult.B['dirtyBefore'] := lBeforeModified;
      lFileResult.B['dirtyAfter'] := lAfterModified;
      lFileResult.B['dirtyChanged'] := lBeforeModified <> lAfterModified;
      AResult.A['files'].Add(lFileResult);
      lFileResult := nil;
    finally
      lFileResult.Free;
    end;
  end;

  ASummary.I['findingCount'] := AFindings.Count;
  ASummary.B['dirtyChanged'] := False;
  for i := 0 to Pred(AResult.A['files'].Count) do
    if AResult.A['files'].O[i].B['dirtyChanged'] then
      ASummary.B['dirtyChanged'] := True;
end;

procedure xeAutomationValidationJobHandler(const AJobId: string; const ADryRun, ADryRunSpecified: Boolean;
  const ATarget, AOptions: TJsonObject; const AFindings: TJsonArray; const ASummary, AResult, AFailure: TJsonObject);
begin
  xeAutomationRunValidationJob(xeAutomationValidationKindName(AOptions.S['kind']), ATarget, AFindings, ASummary, AResult);
end;

procedure xeAutomationCheckForErrorsJobHandler(const AJobId: string; const ADryRun, ADryRunSpecified: Boolean;
  const ATarget, AOptions: TJsonObject; const AFindings: TJsonArray; const ASummary, AResult, AFailure: TJsonObject);
begin
  xeAutomationRunValidationJob(xeAutomationValidationCheckForErrorsKind, ATarget, AFindings, ASummary, AResult);
end;

procedure xeAutomationCheckForItmJobHandler(const AJobId: string; const ADryRun, ADryRunSpecified: Boolean;
  const ATarget, AOptions: TJsonObject; const AFindings: TJsonArray; const ASummary, AResult, AFailure: TJsonObject);
begin
  xeAutomationRunValidationJob(xeAutomationValidationCheckForItmKind, ATarget, AFindings, ASummary, AResult);
end;

procedure xeAutomationCheckForDeletedRefsJobHandler(const AJobId: string; const ADryRun, ADryRunSpecified: Boolean;
  const ATarget, AOptions: TJsonObject; const AFindings: TJsonArray; const ASummary, AResult, AFailure: TJsonObject);
begin
  xeAutomationRunValidationJob(xeAutomationValidationCheckForDeletedRefsKind, ATarget, AFindings, ASummary, AResult);
end;

procedure xeAutomationRegisterValidationCommands;
begin
  xeAutomationRegisterJobKindWithValidator(xeAutomationValidationCheckForErrorsKind, xeAutomationCheckForErrorsJobHandler,
    xeAutomationValidateValidationStart);
  xeAutomationRegisterJobKindWithValidator(xeAutomationValidationCheckForItmKind, xeAutomationCheckForItmJobHandler,
    xeAutomationValidateValidationStart);
  xeAutomationRegisterJobKindWithValidator(xeAutomationValidationCheckForDeletedRefsKind, xeAutomationCheckForDeletedRefsJobHandler,
    xeAutomationValidateValidationStart);
end;

end.
