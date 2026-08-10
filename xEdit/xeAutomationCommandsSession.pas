{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeAutomationCommandsSession;

interface

procedure xeAutomationRegisterSessionCommands;

implementation

uses
  SysUtils,
  JsonDataObjects,
  wbInterface,
  wbLoadOrder,
  xeAutomationDataLookup,
  xeAutomationErrors,
  xeAutomationGuiSnapshot,
  xeAutomationMutationPolicy,
  xeAutomationObjectModel,
  xeAutomationRegistry,
  xeAutomationServeLoop,
  xeMainForm;

function xeAutomationNewPendingFileSummary(const AFileName: string): TJsonObject;
var
  lFile: IwbFile;
begin
  lFile := xeAutomationTryPluginFile(AFileName);
  if Assigned(lFile) then
    Exit(xeAutomationNewFileSummary(lFile));

  // A pending queue entry is persistence state in its own right. If xEdit's
  // module-name index cannot resolve its FileNameOnDisk key (notably .ghost
  // names), preserve the non-raising readback with the identity still known.
  Result := TJsonObject.Create;
  Result.S['name'] := AFileName;
  Result.S['fileName'] := AFileName;
end;

function xeAutomationBuildDirtyState: TJsonObject;
var
  lModules: TwbModuleInfos;
  lDirtyFiles: TJsonArray;
  lPendingShutdownFiles: TJsonArray;
  lPendingShutdownSnapshot: TxePendingShutdownFiles;
  lPendingEntry: TJsonObject;
  lFile: IwbFile;
  i: Integer;
begin
  Result := TJsonObject.Create;
  lDirtyFiles := Result.A['dirtyFiles'];
  lPendingShutdownFiles := Result.A['pendingShutdownFiles'];

  // Dirty state belongs to the loaded daemon session, not to any single request:
  // each call asks about the same in-memory plugin set until the daemon exits.
  lModules := wbModulesByLoadOrder;
  for i := Low(lModules) to High(lModules) do begin
    lFile := xeAutomationTryPluginFileFromModule(lModules[i]);
    if Assigned(lFile) and lFile.Modified then
      lDirtyFiles.Add(xeAutomationNewFileSummary(lFile));
  end;

  Result.I['unsavedChangeCount'] := lDirtyFiles.Count;
  Result.B['dirty'] := lDirtyFiles.Count > 0;

  xePendingShutdownSnapshot(lPendingShutdownSnapshot);
  for i := Low(lPendingShutdownSnapshot) to High(lPendingShutdownSnapshot) do begin
    lPendingEntry := lPendingShutdownFiles.AddObject;
    lPendingEntry.S['tempFile'] := lPendingShutdownSnapshot[i].TempName;
    lPendingEntry.O['file'] := xeAutomationNewPendingFileSummary(
      lPendingShutdownSnapshot[i].FileName
    );
  end;
  Result.I['pendingShutdownCount'] := lPendingShutdownFiles.Count;
  // Saving clears Modified before a memory-mapped module can be renamed. Thus a
  // pending entry intentionally coexists with dirty=false until shutdown/flush.
end;

function xeAutomationSessionGetDirtyState(const AArgs: TJsonObject): TJsonObject;
begin
  Result := xeAutomationBuildDirtyState;
end;

function xeAutomationSessionGetGuiSnapshot(const AArgs: TJsonObject): TJsonObject;
begin
  // GUI snapshot state belongs to the loaded daemon session because the caller is
  // asking about the current xEdit window environment, not request-local data.
  Result := xeAutomationBuildGuiSnapshot;
end;

function xeAutomationSessionSave(const AArgs: TJsonObject): TJsonObject;
var
  lSaveTargets: TxeAutomationTargetFiles;
  lSavedFilesNow: TJsonArray;
  lSavedFilesPendingShutdown: TJsonArray;
  lSaveError: string;
  lWasDirty: Boolean;
  i: Integer;
  lDeniedReason: string;
begin
  if not xeAutomationMutationPolicyConsentSatisfied(lDeniedReason) then begin
    Result := xeAutomationErrorsBuildConsentRequired('session.save', 'session-mutation', lDeniedReason);
    Exit;
  end;

  lSaveTargets := xeAutomationResolveSaveTargets(AArgs);

  Result := TJsonObject.Create;
  lSavedFilesNow := Result.A['savedFilesNow'];
  lSavedFilesPendingShutdown := Result.A['savedFilesPendingShutdown'];
  for i := Low(lSaveTargets) to High(lSaveTargets) do begin
    lWasDirty := lSaveTargets[i].Modified;
    lSaveError := '';
    xeSavePluginFile(lSaveTargets[i], True, lSaveError);
    if (lSaveError <> '') and not xeSavePluginFilePendingShutdown(lSaveTargets[i]) then
      raise xeAutomationSaveFailed(
        Format('Automation save failed for %s: %s', [lSaveTargets[i].FileName, lSaveError])
      );

    if lWasDirty and not lSaveTargets[i].Modified then begin
      // A queued rename is still a successful save, but the final module filename
      // will not exist on disk until shutdown drains FilesToRename.
      if xeSavePluginFilePendingShutdown(lSaveTargets[i]) then
        lSavedFilesPendingShutdown.Add(xeAutomationNewFileSummary(lSaveTargets[i]))
      else
        lSavedFilesNow.Add(xeAutomationNewFileSummary(lSaveTargets[i]));
    end;
  end;

  Result.I['savedNowCount'] := lSavedFilesNow.Count;
  Result.I['savePendingShutdownCount'] := lSavedFilesPendingShutdown.Count;
  Result.O['dirtyState'] := xeAutomationBuildDirtyState;
end;

function xeAutomationSessionFlush(const AArgs: TJsonObject): TJsonObject;
var
  lPendingBefore: TxePendingShutdownFiles;
  lDrainResults: TxePendingRenameResults;
  lPendingAfter: TxePendingShutdownFiles;
  lDirtyState: TJsonObject;
  lFlushedFiles: TJsonArray;
  lPendingRemaining: TJsonArray;
  lEntry: TJsonObject;
  lDeniedReason: string;
  lForceSpecified: Boolean;
  lForce: Boolean;
  i: Integer;
begin
  if not xeAutomationMutationPolicyConsentSatisfied(lDeniedReason) then begin
    Result := xeAutomationErrorsBuildConsentRequired('session.flush', 'session-mutation', lDeniedReason);
    Exit;
  end;

  lForce := xeAutomationReadBooleanArg(AArgs, 'force', lForceSpecified);
  if not lForceSpecified then
    lForce := False;
  xePendingShutdownSnapshot(lPendingBefore);
  // Force-closing the loaded file graph destroys the session, so preserve its
  // final dirty-state readback before the shared drain releases memory maps.
  lDirtyState := xeAutomationBuildDirtyState;
  try
    // Unsaved Modified files are not represented by the pending-rename queue.
    // Refuse to destroy them unless the caller explicitly accepts that loss.
    if lDirtyState.B['dirty'] and not lForce then
      raise xeAutomationStateConflict(
        'session.flush refuses to discard unsaved changes; call session.save first or pass force:true'
      );

    try
      xeDrainPendingRenames(lDrainResults);
    finally
      // From this point the file graph may already be invalid. Arm exit before
      // JSON construction so any later exception still terminates the daemon.
      xeAutomationServeLoopRequestExit;
    end;
    if Length(lDrainResults) <> Length(lPendingBefore) then
      raise xeAutomationNewError(
        xeAutomationErrorInternalError,
        'session.flush pending queue changed between snapshot and drain'
      );
    xePendingShutdownSnapshot(lPendingAfter);

    Result := TJsonObject.Create;
    lFlushedFiles := Result.A['flushedFiles'];
    for i := Low(lDrainResults) to High(lDrainResults) do begin
      lEntry := lFlushedFiles.AddObject;
      lEntry.S['fileName'] := lDrainResults[i].FileName;
      lEntry.B['renamed'] := lDrainResults[i].Renamed;
      if lDrainResults[i].Error <> '' then
        lEntry.S['error'] := lDrainResults[i].Error;
    end;

    lPendingRemaining := Result.A['pendingRemaining'];
    for i := Low(lPendingAfter) to High(lPendingAfter) do
      lPendingRemaining.Add(lPendingAfter[i].FileName);
    Result.I['pendingRemainingCount'] := lPendingRemaining.Count;
    Result.O['dirtyState'] := lDirtyState;
    lDirtyState := nil;
  finally
    lDirtyState.Free;
  end;
end;

procedure xeAutomationRegisterSessionCommands;
begin
  xeAutomationRegisterCommand('session.get_dirty_state', xeAutomationSessionGetDirtyState);
  xeAutomationRegisterCommand('session.get_gui_snapshot', xeAutomationSessionGetGuiSnapshot);
  xeAutomationRegisterCommand('session.save', xeAutomationSessionSave);
  xeAutomationRegisterCommand('session.flush', xeAutomationSessionFlush);
end;

end.
