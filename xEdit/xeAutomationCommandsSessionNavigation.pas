{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeAutomationCommandsSessionNavigation;

interface

procedure xeAutomationRegisterSessionNavigationCommands;

implementation

uses
  SysUtils,
  JsonDataObjects,
  VirtualTrees,
  wbInterface,
  xeAutomationDataLookup,
  xeAutomationErrors,
  xeAutomationGuiSnapshot,
  xeAutomationObjectModel,
  xeAutomationRegistry,
  xeMainForm;

function xeAutomationActiveTabName: string;
begin
  Result := 'unknown';
  if not Assigned(frmMain) then
    Exit;

  if frmMain.pgMain.ActivePage = frmMain.tbsView then
    Result := 'view'
  else if frmMain.pgMain.ActivePage = frmMain.tbsReferencedBy then
    Result := 'referencedBy'
  else if frmMain.pgMain.ActivePage = frmMain.tbsMessages then
    Result := 'messages'
  else if frmMain.pgMain.ActivePage = frmMain.tbsInfo then
    Result := 'info'
  else
    Result := frmMain.pgMain.ActivePage.Name;
end;

procedure xeAutomationWriteNavigationRecordReadback(const ATarget: TJsonObject;
  const ARecord: IwbMainRecord; const AMatchesTarget: Boolean);
begin
  ATarget.B['matchesTarget'] := AMatchesTarget;
  if not Assigned(ARecord) then
    Exit;

  ATarget.O['locator'].S['file'] := ARecord._File.FileName;
  ATarget.O['locator'].S['formId'] := ARecord.LoadOrderFormID.ToString(False);
  ATarget.O['locator'].S['path'] := '';
  ATarget.O['object'].S['kind'] := 'record';
  ATarget.O['object'].S['signature'] := ARecord.Signature;
  ATarget.O['object'].S['formId'] := ARecord.LoadOrderFormID.ToString(False);
  if ARecord.CanHaveEditorID and (Trim(ARecord.EditorID) <> '') then
    ATarget.O['object'].S['editorId'] := xeAutomationBoundedText(ARecord.EditorID);
end;

procedure xeAutomationRaiseNavigationPostconditionFailed(const AResult: TJsonObject);
var
  lDetails: TJsonObject;
begin
  lDetails := TJsonObject.Create;
  try
    // A successful navigation response is only safe when native JumpTo left xEdit's
    // observable UI state on the requested record; otherwise return a typed internal
    // error instead of a false-green ok:true envelope.
    lDetails.O['navigationReadback'].Assign(AResult);
    raise xeAutomationNewError(
      xeAutomationErrorInternalError,
      'Automation navigation postcondition failed after JumpTo',
      lDetails
    );
  finally
    lDetails.Free;
  end;
end;

procedure xeAutomationRaiseIfGuiBlocked;
var
  lSnapshot: TJsonObject;
  lDetails: TJsonObject;
begin
  lSnapshot := xeAutomationBuildGuiSnapshot;
  try
    if not lSnapshot.B['hasBlockers'] then
      Exit;

    lDetails := TJsonObject.Create;
    try
      // Navigation drives native UI selection, so visible/modal blockers are a
      // state conflict rather than a best-effort background operation.
      lDetails.O['guiSnapshot'].Assign(lSnapshot);
      raise xeAutomationNewError(
        xeAutomationErrorStateConflict,
        'Automation navigation is blocked by current GUI state',
        lDetails
      );
    finally
      lDetails.Free;
    end;
  finally
    lSnapshot.Free;
  end;
end;

function xeAutomationSessionNavigateToRecord(const AArgs: TJsonObject): TJsonObject;
var
  lLocator: TxeAutomationLocator;
  lTargetRecord: IwbMainRecord;
  lActiveRecord: IwbMainRecord;
  lFocusedRecord: IwbMainRecord;
  lNavNode: PVirtualNode;
begin
  lLocator := xeAutomationParseLocator(AArgs, True, False);
  // V1 is deliberately record-root only. Rejecting non-empty paths at the command
  // boundary keeps element traversal from silently inheriting record navigation UI.
  if lLocator.Path <> '' then
    raise xeAutomationInvalidRequest('Automation session.navigate_to_record path must address the record root');

  xeAutomationRaiseIfGuiBlocked;
  lTargetRecord := xeAutomationRequireMainRecord(lLocator);

  if not Assigned(frmMain) then
    raise xeAutomationStateConflict('Automation navigation requires the main form');

  // Reuse the same native JumpTo seam as history/menu navigation so automation
  // follows xEdit's existing tree expansion, active record, and view-tab behavior.
  frmMain.JumpTo(lTargetRecord, False);
  lActiveRecord := frmMain.AutomationGetActiveRecord;
  lFocusedRecord := frmMain.AutomationGetFocusedRecord;
  lNavNode := frmMain.FindNodeForElement(lTargetRecord);

  Result := TJsonObject.Create;
  try
    Result.S['activeTab'] := xeAutomationActiveTabName;
    xeAutomationWriteNavigationRecordReadback(
      Result.O['targetRecord'],
      lTargetRecord,
      True
    );
    xeAutomationWriteNavigationRecordReadback(
      Result.O['activeRecord'],
      lActiveRecord,
      Assigned(lActiveRecord) and lActiveRecord.Equals(lTargetRecord)
    );
    xeAutomationWriteNavigationRecordReadback(
      Result.O['focusedRecord'],
      lFocusedRecord,
      Assigned(lFocusedRecord) and lFocusedRecord.Equals(lTargetRecord)
    );
    Result.O['treeSelection'].B['found'] := Assigned(lNavNode);
    Result.O['treeSelection'].B['matchesTarget'] := Assigned(lNavNode) and frmMain.vstNav.Selected[lNavNode];
    Result.O['treeSelection'].O['locator'].S['file'] := lTargetRecord._File.FileName;
    Result.O['treeSelection'].O['locator'].S['formId'] := lTargetRecord.LoadOrderFormID.ToString(False);
    Result.O['treeSelection'].O['locator'].S['path'] := '';

    if (Result.S['activeTab'] <> 'view')
      or not Result.O['activeRecord'].B['matchesTarget']
      or not Result.O['focusedRecord'].B['matchesTarget']
      or not Result.O['treeSelection'].B['matchesTarget'] then
      xeAutomationRaiseNavigationPostconditionFailed(Result);
  except
    Result.Free;
    raise;
  end;
end;

procedure xeAutomationRegisterSessionNavigationCommands;
begin
  xeAutomationRegisterCommand('session.navigate_to_record', xeAutomationSessionNavigateToRecord);
end;

end.
