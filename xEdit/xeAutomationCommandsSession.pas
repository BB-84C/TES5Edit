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
  xeAutomationRegistry,
  xeMainForm;

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
    lPendingEntry.O['file'] := xeAutomationNewFileSummary(
        xeAutomationRequirePluginFile(lPendingShutdownSnapshot[i].FileName)
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

procedure xeAutomationRegisterSessionCommands;
begin
  xeAutomationRegisterCommand('session.get_dirty_state', xeAutomationSessionGetDirtyState);
  xeAutomationRegisterCommand('session.get_gui_snapshot', xeAutomationSessionGetGuiSnapshot);
  xeAutomationRegisterCommand('session.save', xeAutomationSessionSave);
end;

end.
