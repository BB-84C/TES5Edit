{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeAutomationCommandsCleaning;

interface

procedure xeAutomationRegisterCleaningCommands;

implementation

uses
  SysUtils,
  Generics.Collections,
  JsonDataObjects,
  wbInterface,
  xeAutomationDataLookup,
  xeAutomationErrors,
  xeAutomationJobs,
  xeAutomationMutationPolicy,
  xeMainForm;

const
  xeAutomationCleaningQuickCleanKind = 'cleaning.quick_clean';
  xeAutomationCleaningQuickAutoCleanKind = 'cleaning.quick_auto_clean';
  xeAutomationCleaningSortAndCleanMastersKind = 'cleaning.sort_and_clean_masters';

procedure xeAutomationValidateCleaningStart(var ADryRun: Boolean; const ADryRunSpecified: Boolean;
  const ATarget, AOptions: TJsonObject);
var
  lFiles: TJsonArray;
  i: Integer;
begin
  if not Assigned(ATarget) then
    raise xeAutomationInvalidRequest('Automation cleaning target is required');
  if not ATarget.Contains('files') then
    raise xeAutomationInvalidRequest('Automation cleaning target.files is required');
  if ATarget.Types['files'] <> jdtArray then
    raise xeAutomationInvalidRequest('Automation cleaning target.files must be an array');

  lFiles := ATarget.A['files'];
  if lFiles.Count = 0 then
    raise xeAutomationInvalidRequest('Automation cleaning target.files must not be empty');
  for i := 0 to Pred(lFiles.Count) do
    if lFiles.Types[i] <> jdtString then
      raise xeAutomationInvalidRequest('Automation cleaning target.files entries must be strings');

  // Cleaning is destructive in apply mode, so omitted dryRun must normalize to a
  // planning job at start-time before any active-job or execution state exists.
  if not ADryRunSpecified then
    ADryRun := True;
end;

procedure xeAutomationAddCleaningFinding(const AFindings: TJsonArray; const ASource, ASeverity, ACode, AMessage,
  AFileName, AActionKind, AReason: string; const APlanned, AApplied, ASkipped: Integer);
var
  lFinding: TJsonObject;
begin
  lFinding := TJsonObject.Create;
  try
    lFinding.S['severity'] := ASeverity;
    lFinding.S['code'] := ACode;
    lFinding.S['message'] := AMessage;
    lFinding.S['source'] := ASource;
    lFinding.O['target'].S['file'] := AFileName;
    lFinding.O['action'].S['kind'] := AActionKind;
    if AReason <> '' then
      lFinding.O['action'].S['reason'] := AReason;
    lFinding.O['counts'].I['planned'] := APlanned;
    lFinding.O['counts'].I['applied'] := AApplied;
    lFinding.O['counts'].I['skipped'] := ASkipped;
    AFindings.Add(lFinding);
    lFinding := nil;
  finally
    lFinding.Free;
  end;
end;

procedure xeAutomationAddDirtyFile(const ATarget: TJsonArray; const AFile: IwbFile);
var
  i: Integer;
begin
  if (not Assigned(AFile)) or (not AFile.Modified) then
    Exit;
  for i := 0 to Pred(ATarget.Count) do
    if SameText(ATarget.S[i], AFile.FileName) then
      Exit;
  ATarget.Add(AFile.FileName);
end;

procedure xeAutomationWriteCleaningDefaults(const AKind: string; const ADryRun: Boolean; const AFiles: TJsonArray;
  const ASummary, AResult: TJsonObject);
begin
  ASummary.S['kind'] := AKind;
  ASummary.B['dryRun'] := ADryRun;
  ASummary.I['targets'] := AFiles.Count;
  ASummary.I['planned'] := 0;
  ASummary.I['applied'] := 0;
  ASummary.I['skipped'] := 0;
  ASummary.I['findings'] := 0;
  ASummary.B['changed'] := False;
  ASummary.B['requiresSave'] := False;
  ASummary.A['dirtyFiles'].Clear;
  AResult.A['files'].Clear;
end;

procedure xeAutomationWriteCleaningFileResult(const ATarget: TJsonArray; const AFile: IwbFile; const AOperation: string;
  const APlanned, AApplied, ASkipped: Integer; const ADirtyBefore, ADirtyAfter: Boolean);
var
  lFileResult: TJsonObject;
begin
  lFileResult := TJsonObject.Create;
  try
    lFileResult.S['fileName'] := AFile.FileName;
    lFileResult.S['operation'] := AOperation;
    lFileResult.I['planned'] := APlanned;
    lFileResult.I['applied'] := AApplied;
    lFileResult.I['skipped'] := ASkipped;
    lFileResult.B['dirtyBefore'] := ADirtyBefore;
    lFileResult.B['dirtyAfter'] := ADirtyAfter;
    lFileResult.B['changed'] := ADirtyBefore <> ADirtyAfter;
    ATarget.Add(lFileResult);
    lFileResult := nil;
  finally
    lFileResult.Free;
  end;
end;

procedure xeAutomationWriteMasterCleaningFileResult(const ATarget: TJsonArray; const AFile: IwbFile;
  const ASortPlanned, ASortApplied, ASortSkipped, ACleanPlanned, ACleanApplied, ACleanSkipped: Integer;
  const ADirtyBefore, ADirtyAfter: Boolean);
var
  lFileResult: TJsonObject;
begin
  lFileResult := TJsonObject.Create;
  try
    lFileResult.S['fileName'] := AFile.FileName;
    lFileResult.S['operation'] := 'sort_and_clean_masters';
    lFileResult.I['planned'] := ASortPlanned + ACleanPlanned;
    lFileResult.I['applied'] := ASortApplied + ACleanApplied;
    lFileResult.I['skipped'] := ASortSkipped + ACleanSkipped;
    lFileResult.B['dirtyBefore'] := ADirtyBefore;
    lFileResult.B['dirtyAfter'] := ADirtyAfter;
    lFileResult.B['changed'] := ADirtyBefore <> ADirtyAfter;
    lFileResult.O['operations'].O['sort'].I['planned'] := ASortPlanned;
    lFileResult.O['operations'].O['sort'].I['applied'] := ASortApplied;
    lFileResult.O['operations'].O['sort'].I['skipped'] := ASortSkipped;
    lFileResult.O['operations'].O['cleanMasters'].I['planned'] := ACleanPlanned;
    lFileResult.O['operations'].O['cleanMasters'].I['applied'] := ACleanApplied;
    lFileResult.O['operations'].O['cleanMasters'].I['skipped'] := ACleanSkipped;
    ATarget.Add(lFileResult);
    lFileResult := nil;
  finally
    lFileResult.Free;
  end;
end;

procedure xeAutomationAccumulateCounts(const ASummary: TJsonObject; const APlanned, AApplied, ASkipped: Integer);
begin
  ASummary.I['planned'] := ASummary.I['planned'] + APlanned;
  ASummary.I['applied'] := ASummary.I['applied'] + AApplied;
  ASummary.I['skipped'] := ASummary.I['skipped'] + ASkipped;
end;

procedure xeAutomationRunItmCleaning(const AKind: string; const ADryRun: Boolean; const AFile: IwbFile;
  const AFindings: TJsonArray; const ASummary, AResult: TJsonObject);
var
  lPlanned: Integer;
  lApplied: Integer;
  lSkipped: Integer;
  lDirtyBefore: Boolean;
begin
  lDirtyBefore := AFile.Modified;
  xeAutomationCleanIdenticalToMasterInMemory(AFile, not ADryRun, lPlanned, lApplied, lSkipped);
  if ADryRun then
    xeAutomationAddCleaningFinding(AFindings, AKind, 'info', xeAutomationFindingCleaningItmRecordsPlanned,
      Format('Planned ITM cleaning for %s', [AFile.FileName]), AFile.FileName, 'planned', 'dry_run', lPlanned, 0, lSkipped)
  else if lApplied > 0 then
    xeAutomationAddCleaningFinding(AFindings, AKind, 'info', xeAutomationFindingCleaningItmRecordsRemoved,
      Format('Removed %d ITM records from %s', [lApplied, AFile.FileName]), AFile.FileName, 'applied', '', lPlanned, lApplied, lSkipped)
  else
    xeAutomationAddCleaningFinding(AFindings, AKind, 'info', xeAutomationFindingCleaningItmRecordsSkipped,
      Format('No removable ITM records found in %s', [AFile.FileName]), AFile.FileName, 'skipped', 'no_change', lPlanned, 0, lSkipped);
  xeAutomationAccumulateCounts(ASummary, lPlanned, lApplied, lSkipped);
  xeAutomationWriteCleaningFileResult(AResult.A['files'], AFile, 'remove_itm', lPlanned, lApplied, lSkipped,
    lDirtyBefore, AFile.Modified);
end;

procedure xeAutomationRunDeletedRefCleaning(const AKind: string; const ADryRun: Boolean; const AFile: IwbFile;
  const AFindings: TJsonArray; const ASummary, AResult: TJsonObject);
var
  lPlanned: Integer;
  lApplied: Integer;
  lSkipped: Integer;
  lDeletedNavmesh: Integer;
  lDirtyBefore: Boolean;
begin
  lDirtyBefore := AFile.Modified;
  xeAutomationUndeleteAndDisableRefsInMemory(AFile, not ADryRun, lPlanned, lApplied, lSkipped, lDeletedNavmesh);
  if ADryRun then
    xeAutomationAddCleaningFinding(AFindings, AKind, 'info', xeAutomationFindingCleaningDeletedRefsPlanned,
      Format('Planned deleted-reference cleaning for %s', [AFile.FileName]), AFile.FileName, 'planned', 'dry_run', lPlanned, 0, lSkipped)
  else if lApplied > 0 then
    xeAutomationAddCleaningFinding(AFindings, AKind, 'info', xeAutomationFindingCleaningDeletedRefsUndeletedDisabled,
      Format('Undeleted and disabled %d references in %s', [lApplied, AFile.FileName]), AFile.FileName, 'applied', '', lPlanned, lApplied, lSkipped)
  else
    xeAutomationAddCleaningFinding(AFindings, AKind, 'info', xeAutomationFindingCleaningDeletedRefsSkipped,
      Format('No cleanable deleted references found in %s', [AFile.FileName]), AFile.FileName, 'skipped', 'no_change', lPlanned, 0, lSkipped);
  if lDeletedNavmesh > 0 then
    xeAutomationAddCleaningFinding(AFindings, AKind, 'warning', xeAutomationFindingCleaningDeletedNavmeshSkipped,
      Format('Skipped %d deleted NavMeshes in %s', [lDeletedNavmesh, AFile.FileName]), AFile.FileName, 'skipped', 'unsafe_navmesh', 0, 0, lDeletedNavmesh);
  xeAutomationAccumulateCounts(ASummary, lPlanned, lApplied, lSkipped);
  xeAutomationWriteCleaningFileResult(AResult.A['files'], AFile, 'undelete_and_disable_refs', lPlanned, lApplied, lSkipped,
    lDirtyBefore, AFile.Modified);
end;

procedure xeAutomationRunSortAndCleanMasters(const AKind: string; const ADryRun: Boolean; const AFile: IwbFile;
  const AFindings: TJsonArray; const ASummary, AResult: TJsonObject);
var
  lSortPlanned: Integer;
  lSortApplied: Integer;
  lSortSkipped: Integer;
  lCleanPlanned: Integer;
  lCleanApplied: Integer;
  lCleanSkipped: Integer;
  lPlanned: Integer;
  lApplied: Integer;
  lSkipped: Integer;
  lDirtyBefore: Boolean;
begin
  lDirtyBefore := AFile.Modified;
  xeAutomationSortAndCleanMastersInMemory(AFile, not ADryRun, lSortPlanned, lSortApplied, lSortSkipped,
    lCleanPlanned, lCleanApplied, lCleanSkipped);
  lPlanned := lSortPlanned + lCleanPlanned;
  lApplied := lSortApplied + lCleanApplied;
  lSkipped := lSortSkipped + lCleanSkipped;
  if ADryRun then
    xeAutomationAddCleaningFinding(AFindings, AKind, 'info', xeAutomationFindingCleaningMastersSortCleanPlanned,
      Format('Planned sort and clean masters for %s', [AFile.FileName]), AFile.FileName, 'planned', 'dry_run', lPlanned, 0, lSkipped)
  else if lApplied > 0 then
    xeAutomationAddCleaningFinding(AFindings, AKind, 'info', xeAutomationFindingCleaningMastersSortCleanApplied,
      Format('Applied sort and clean masters for %s', [AFile.FileName]), AFile.FileName, 'applied', '', lPlanned, lApplied, lSkipped)
  else
    xeAutomationAddCleaningFinding(AFindings, AKind, 'info', xeAutomationFindingCleaningMastersSortCleanSkipped,
      Format('No master list changes were needed for %s', [AFile.FileName]), AFile.FileName, 'skipped', 'no_change', lPlanned, 0, lSkipped);
  xeAutomationAccumulateCounts(ASummary, lPlanned, lApplied, lSkipped);
  xeAutomationWriteMasterCleaningFileResult(AResult.A['files'], AFile, lSortPlanned, lSortApplied, lSortSkipped,
    lCleanPlanned, lCleanApplied, lCleanSkipped, lDirtyBefore, AFile.Modified);
end;

procedure xeAutomationRunCleaningJob(const AKind: string; const ADryRun: Boolean; const ATarget: TJsonObject;
  const AFindings: TJsonArray; const ASummary, AResult: TJsonObject);
var
  lFiles: TJsonArray;
  lTargetFiles: TList<IwbFile>;
  lFile: IwbFile;
  i: Integer;
begin
  lFiles := ATarget.A['files'];
  xeAutomationWriteCleaningDefaults(AKind, ADryRun, lFiles, ASummary, AResult);

  lTargetFiles := TList<IwbFile>.Create;
  try
    for i := 0 to Pred(lFiles.Count) do begin
      lFile := xeAutomationRequirePluginFile(Trim(lFiles.S[i]));
      if not ADryRun then
        // Apply-mode cleaning preflights every target before touching the first one;
        // otherwise a later protected file could leave earlier writable files dirty.
        xeAutomationRequireWritableCleaningTarget(lFile);
      lTargetFiles.Add(lFile);
    end;

    for lFile in lTargetFiles do begin

      if SameText(AKind, xeAutomationCleaningSortAndCleanMastersKind) or
        SameText(AKind, xeAutomationCleaningQuickAutoCleanKind) then
        xeAutomationRunSortAndCleanMasters(AKind, ADryRun, lFile, AFindings, ASummary, AResult);
      if SameText(AKind, xeAutomationCleaningQuickCleanKind) or
        SameText(AKind, xeAutomationCleaningQuickAutoCleanKind) then begin
        xeAutomationRunItmCleaning(AKind, ADryRun, lFile, AFindings, ASummary, AResult);
        xeAutomationRunDeletedRefCleaning(AKind, ADryRun, lFile, AFindings, ASummary, AResult);
      end;

      if (not ADryRun) and lFile.Modified then begin
        ASummary.B['changed'] := True;
        ASummary.B['requiresSave'] := True;
        xeAutomationAddDirtyFile(ASummary.A['dirtyFiles'], lFile);
      end;
    end;
  finally
    lTargetFiles.Free;
  end;

  ASummary.I['findings'] := AFindings.Count;
end;

procedure xeAutomationQuickCleanJob(const AJobId: string; const ADryRun, ADryRunSpecified: Boolean;
  const ATarget, AOptions: TJsonObject; const AFindings: TJsonArray; const ASummary, AResult, AFailure: TJsonObject);
begin
  xeAutomationRunCleaningJob(xeAutomationCleaningQuickCleanKind, ADryRun, ATarget, AFindings, ASummary, AResult);
end;

procedure xeAutomationQuickAutoCleanJob(const AJobId: string; const ADryRun, ADryRunSpecified: Boolean;
  const ATarget, AOptions: TJsonObject; const AFindings: TJsonArray; const ASummary, AResult, AFailure: TJsonObject);
begin
  xeAutomationRunCleaningJob(xeAutomationCleaningQuickAutoCleanKind, ADryRun, ATarget, AFindings, ASummary, AResult);
end;

procedure xeAutomationSortAndCleanMastersJob(const AJobId: string; const ADryRun, ADryRunSpecified: Boolean;
  const ATarget, AOptions: TJsonObject; const AFindings: TJsonArray; const ASummary, AResult, AFailure: TJsonObject);
begin
  xeAutomationRunCleaningJob(xeAutomationCleaningSortAndCleanMastersKind, ADryRun, ATarget, AFindings, ASummary, AResult);
end;

procedure xeAutomationRegisterCleaningCommands;
begin
  // Capability advertising is registry-derived; the cleaning kinds become visible
  // only after these in-memory, explicit-save-safe handlers are linked.
  xeAutomationRegisterJobKindWithValidator(xeAutomationCleaningQuickCleanKind, xeAutomationQuickCleanJob,
    xeAutomationValidateCleaningStart);
  xeAutomationRegisterJobKindWithValidator(xeAutomationCleaningQuickAutoCleanKind, xeAutomationQuickAutoCleanJob,
    xeAutomationValidateCleaningStart);
  xeAutomationRegisterJobKindWithValidator(xeAutomationCleaningSortAndCleanMastersKind, xeAutomationSortAndCleanMastersJob,
    xeAutomationValidateCleaningStart);
end;

end.
