{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeAutomationCommandsElements;

interface

procedure xeAutomationRegisterElementsCommands;

implementation

uses
  SysUtils,
  Classes,
  JsonDataObjects,
  wbInterface,
  xeAutomationConflictSnapshot,
  xeAutomationDataLookup,
  xeAutomationErrors,
  xeAutomationMutationPolicy,
  xeAutomationObjectModel,
  xeAutomationRegistry;

function xeAutomationCompareFileLoadOrder(AList: TStringList; AIndex1, AIndex2: Integer): Integer;
begin
  if AIndex1 = AIndex2 then
    Exit(0);

  Result := IwbFile(Pointer(AList.Objects[AIndex1])).LoadOrder
    - IwbFile(Pointer(AList.Objects[AIndex2])).LoadOrder;
end;

function xeAutomationCollectRequiredMasters(const AElement: IwbElement; const ATargetFile: IwbFile): TStringList;
var
  lMasters: TwbFilesSet;
  lFile: IwbFile;
  lFindIndex: Integer;
  i: Integer;
begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;

  lMasters := TwbFilesSet.Create;
  try
    // Required-master analysis should follow xEdit's native container walk so the
    // automation result stays aligned with the existing Add/Report Masters behavior.
    AElement.ReportRequiredMasters(lMasters, False, True, True);
    for lFile in lMasters do
      Result.AddObject(lFile.FileName, Pointer(lFile));
  finally
    lMasters.Free;
  end;

  // The approved protocol reports the addressed scope's required masters in load
  // order, but never echoes the target file itself as one of its own dependencies.
  if Result.Find(ATargetFile.FileName, lFindIndex) then
    Result.Delete(lFindIndex);

  Result.Sorted := False;
  Result.CustomSort(xeAutomationCompareFileLoadOrder);
end;

function xeAutomationNewElementResponse(const ARecord: IwbMainRecord; const AElement: IwbElement): TJsonObject; forward;

function xeAutomationElementsRequiredMasters(const AArgs: TJsonObject): TJsonObject;
var
  lLocator: TxeAutomationLocator;
  lRecord: IwbMainRecord;
  lElement: IwbElement;
  lElementResponse: TJsonObject;
  lRequiredMasters: TStringList;
  lMasters: TJsonArray;
  i: Integer;
begin
  lLocator := xeAutomationParseLocator(AArgs, True, True);
  lElement := xeAutomationRequireElement(lLocator, lRecord);

  Result := TJsonObject.Create;
  lElementResponse := xeAutomationNewElementResponse(lRecord, lElement);
  try
    Result.O['object'].Assign(lElementResponse);
  finally
    lElementResponse.Free;
  end;

  lRequiredMasters := xeAutomationCollectRequiredMasters(lElement, lRecord._File);
  try
    Result.I['count'] := lRequiredMasters.Count;
    lMasters := Result.A['masters'];
    for i := 0 to Pred(lRequiredMasters.Count) do
      // Emit the shared file summary shape so each master entry carries stable
      // identity fields without inventing a one-off required-masters schema.
      lMasters.Add(xeAutomationNewFileSummary(IwbFile(Pointer(lRequiredMasters.Objects[i]))));
  finally
    lRequiredMasters.Free;
  end;
end;

function xeAutomationNewElementResponse(const ARecord: IwbMainRecord; const AElement: IwbElement): TJsonObject;
var
  lLocatorPath: string;
begin
  lLocatorPath := xeAutomationElementLocatorPath(AElement);
  Result := xeAutomationNewObjectResponse(
    ARecord._File.FileName,
    ARecord.LoadOrderFormID.ToString(False),
    lLocatorPath
  );
  xeAutomationWriteElementSummary(Result.O['object'], AElement, lLocatorPath);
  if xeAutomationElementHasChildren(AElement) then
    xeAutomationAddChildrenRelation(Result);
end;

function xeAutomationNewElementConflictStatusResponse(const ARecord: IwbMainRecord;
  const AElement: IwbElement; const ASnapshot: TxeAutomationConflictSnapshot): TJsonObject;
var
  lObject: TJsonObject;
  lChildren: TJsonArray;
  i: Integer;
  lLocatorPath: string;
begin
  Result := TJsonObject.Create;
  lObject := Result.O['object'];
  lLocatorPath := xeAutomationElementLocatorPath(AElement);
  xeAutomationWriteElementSummary(lObject.O['object'], AElement, lLocatorPath);
  Result.O['object'].O['locator'].S['file'] := ARecord._File.FileName;
  Result.O['object'].O['locator'].S['formId'] := ARecord.LoadOrderFormID.ToString(False);
  Result.O['object'].O['locator'].S['path'] := lLocatorPath;

  xeAutomationWriteConflictBlock(Result.O['conflict'], ASnapshot.ConflictAll, ASnapshot.ConflictThis, ASnapshot.Participants);

  Result.O['children'].I['count'] := Length(ASnapshot.Children);
  Result.O['children'].B['truncated'] := ASnapshot.ChildrenTruncated;
  lChildren := Result.O['children'].A['items'];
  for i := Low(ASnapshot.Children) to High(ASnapshot.Children) do
    xeAutomationWriteConflictChildStub(lChildren.AddObject, ARecord, ASnapshot.Children[i]);
end;

function xeAutomationElementsGet(const AArgs: TJsonObject): TJsonObject;
var
  lLocator: TxeAutomationLocator;
  lRecord: IwbMainRecord;
  lElement: IwbElement;
begin
  lLocator := xeAutomationParseLocator(AArgs, True, True);
  lElement := xeAutomationRequireElement(lLocator, lRecord);
  Result := xeAutomationNewElementResponse(lRecord, lElement);
end;

function xeAutomationElementsChildren(const AArgs: TJsonObject): TJsonObject;
var
  lLocator: TxeAutomationLocator;
  lRecord: IwbMainRecord;
  lElement: IwbElement;
  lContainer: IwbContainer;
  lChildren: TJsonArray;
  i: Integer;
begin
  lLocator := xeAutomationParseLocator(AArgs, True, True);
  lElement := xeAutomationRequireElement(lLocator, lRecord);

  Result := TJsonObject.Create;
  lChildren := Result.A['children'];
  if not Supports(lElement, IwbContainer, lContainer) then
    Exit;

  // This command intentionally emits only one generation of child stubs. Callers
  // must opt into deeper traversal by following returned child locators explicitly.
  for i := 0 to Pred(lContainer.ElementCount) do
    lChildren.Add(xeAutomationNewElementResponse(lRecord, lContainer.Elements[i]));
end;

function xeAutomationElementsConflictStatus(const AArgs: TJsonObject): TJsonObject;
var
  lLocator: TxeAutomationLocator;
  lRecord: IwbMainRecord;
  lElement: IwbElement;
begin
  lLocator := xeAutomationParseLocator(AArgs, True, True);
  // elements.conflict_status is the explicit drill-down endpoint. Requiring a
  // non-root path preserves the progressive root-first contract from records.*.
  if Trim(lLocator.Path) = '' then
    raise xeAutomationInvalidRequest('Automation locator path must be non-empty for elements.conflict_status');

  lElement := xeAutomationRequireElement(lLocator, lRecord);
  Result := xeAutomationNewElementConflictStatusResponse(
    lRecord,
    lElement,
    xeAutomationSnapshotElementConflict(lElement, xeAutomationReadSearchLimit(AArgs))
  );
end;

function xeAutomationElementsSetValue(const AArgs: TJsonObject): TJsonObject;
var
  lLocator: TxeAutomationLocator;
  lRecord: IwbMainRecord;
  lElement: IwbElement;
  lAfterValue: string;
  lBeforeValue: string;
  lValue: string;
  lChanged: Boolean;
  lDeniedReason: string;
begin
  if not xeAutomationMutationPolicyConsentSatisfied(lDeniedReason) then begin
    Result := xeAutomationErrorsBuildConsentRequired('elements.set_value', 'elements-mutation', lDeniedReason);
    Exit;
  end;

  lLocator := xeAutomationParseLocator(AArgs, True, True);
  lElement := xeAutomationRequireOwnedElement(lLocator, lRecord);
  xeAutomationRequireWritableElementTarget(lElement);
  lValue := xeAutomationRequireRawStringArg(AArgs, 'value');

  lBeforeValue := lElement.EditValue;
  if lBeforeValue <> lValue then begin
    // This deliberately mutates only the loaded daemon session. Save/commit flows
    // arrive later, so callers can stage edits and inspect dirty state separately.
    lElement.EditValue := lValue;
  end;
  lAfterValue := lElement.EditValue;
  lChanged := lAfterValue <> lBeforeValue;

  Result := xeAutomationNewMutationResult(
    lChanged,
    lRecord._File.Modified,
    lRecord._File.FileName,
    lRecord.LoadOrderFormID.ToString(False),
    xeAutomationElementLocatorPath(lElement)
  );
  Result.O['file'] := xeAutomationNewFileSummary(lRecord._File);
end;

function xeAutomationElementsAddChild(const AArgs: TJsonObject): TJsonObject;
var
  lLocator: TxeAutomationLocator;
  lRecord: IwbMainRecord;
  lElement: IwbElement;
  lNewElement: IwbElement;
  lTargetIndex: Integer;
  lTemplate: IwbTemplateElement;
  lTemplates: TwbTemplateElements;
  lDeniedReason: string;
begin
  if not xeAutomationMutationPolicyConsentSatisfied(lDeniedReason) then begin
    Result := xeAutomationErrorsBuildConsentRequired('elements.add_child', 'elements-mutation', lDeniedReason);
    Exit;
  end;

  lLocator := xeAutomationParseLocator(AArgs, True, True);
  lElement := xeAutomationRequireOwnedElement(lLocator, lRecord);
  xeAutomationRequireAddableElementTarget(lElement);

  // Structural adds stop at the loaded daemon session for now. Persistence stays
  // behind a later explicit save command so add/remove cannot silently touch disk.
  lTargetIndex := wbAssignAdd;
  lTemplate := nil;
  lTemplates := lElement.GetAssignTemplates(lTargetIndex);
  if Length(lTemplates) > 1 then
    raise xeAutomationMutationNotAllowed('Automation mutation target requires explicit template selection');
  if Length(lTemplates) = 1 then
    lTemplate := lTemplates[0];

  lNewElement := lElement.Assign(lTargetIndex, lTemplate, False);
  if not Assigned(lNewElement) then
    raise xeAutomationMutationNotAllowed('Automation mutation target cannot accept a child');
  lNewElement.SetToDefaultIfAsCreatedEmpty;

  Result := xeAutomationNewMutationResult(
    True,
    lRecord._File.Modified,
    lRecord._File.FileName,
    lRecord.LoadOrderFormID.ToString(False),
    xeAutomationElementLocatorPath(lNewElement)
  );
  Result.O['file'] := xeAutomationNewFileSummary(lRecord._File);
end;

function xeAutomationElementsRemoveChild(const AArgs: TJsonObject): TJsonObject;
var
  lLocator: TxeAutomationLocator;
  lRecord: IwbMainRecord;
  lElement: IwbElement;
  lRemovedPath: string;
  lDeniedReason: string;
begin
  if not xeAutomationMutationPolicyConsentSatisfied(lDeniedReason) then begin
    Result := xeAutomationErrorsBuildConsentRequired('elements.remove_child', 'elements-mutation', lDeniedReason);
    Exit;
  end;

  lLocator := xeAutomationParseLocator(AArgs, True, True);
  if Trim(lLocator.Path) = '' then
    raise xeAutomationInvalidTarget('Automation mutation target must address an existing child element');

  lElement := xeAutomationRequireOwnedElement(lLocator, lRecord);
  xeAutomationRequireRemovableElementTarget(lElement);
  lRemovedPath := xeAutomationElementLocatorPath(lElement);

  // Like other element mutations, removal only updates in-memory session state.
  // Save/commit behavior is intentionally deferred to an explicit command.
  lElement.Remove;

  Result := xeAutomationNewMutationResult(
    True,
    lRecord._File.Modified,
    lRecord._File.FileName,
    lRecord.LoadOrderFormID.ToString(False),
    lRemovedPath
  );
  Result.O['file'] := xeAutomationNewFileSummary(lRecord._File);
end;

function xeAutomationElementsCopyChildTo(const AArgs: TJsonObject): TJsonObject;
var
  lSourceLocator: TxeAutomationLocator;
  lTargetLocator: TxeAutomationLocator;
  lSourceRecord: IwbMainRecord;
  lTargetRecord: IwbMainRecord;
  lSourceElement: IwbElement;
  lTargetElement: IwbElement;
  lNewElement: IwbElement;
  lDeniedReason: string;
begin
  if not xeAutomationMutationPolicyConsentSatisfied(lDeniedReason) then begin
    Result := xeAutomationErrorsBuildConsentRequired('elements.copy_child_to', 'elements-mutation', lDeniedReason);
    Exit;
  end;

  // Copy requests carry both locators explicitly so callers never have to reason
  // about hidden clipboard/session state when reviewing or replaying a mutation.
  lSourceLocator := xeAutomationParseNestedLocatorArg(AArgs, 'source', True, True);
  lTargetLocator := xeAutomationParseNestedLocatorArg(AArgs, 'target', True, True);

  if Trim(lSourceLocator.Path) = '' then
    raise xeAutomationInvalidTarget('Automation mutation source must address an existing child element');

  lSourceElement := xeAutomationRequireElement(lSourceLocator, lSourceRecord);
  // Copy targets are writable mutation targets, so they must be records owned by
  // the addressed file instead of master records found through compatibility lookup.
  lTargetElement := xeAutomationRequireOwnedElement(lTargetLocator, lTargetRecord);
  xeAutomationRequireCopyTarget(lTargetElement, lSourceElement);

  // Like other element mutations, copy only mutates loaded session memory. Save
  // behavior stays behind an explicit command instead of piggybacking here.
  lNewElement := lTargetElement.Assign(wbAssignAdd, lSourceElement, False);
  if not Assigned(lNewElement) then
    raise xeAutomationMutationNotAllowed('Automation mutation target cannot accept the addressed source child');

  Result := xeAutomationNewMutationResult(
    True,
    lTargetRecord._File.Modified,
    lTargetRecord._File.FileName,
    lTargetRecord.LoadOrderFormID.ToString(False),
    xeAutomationElementLocatorPath(lNewElement)
  );
  Result.O['file'] := xeAutomationNewFileSummary(lTargetRecord._File);
end;

procedure xeAutomationRegisterElementsCommands;
begin
  xeAutomationRegisterCommand('elements.get', xeAutomationElementsGet);
  xeAutomationRegisterCommand('elements.children', xeAutomationElementsChildren);
  xeAutomationRegisterCommand('elements.conflict_status', xeAutomationElementsConflictStatus);
  xeAutomationRegisterCommand('elements.required_masters', xeAutomationElementsRequiredMasters);
  xeAutomationRegisterCommand('elements.set_value', xeAutomationElementsSetValue);
  xeAutomationRegisterCommand('elements.add_child', xeAutomationElementsAddChild);
  xeAutomationRegisterCommand('elements.remove_child', xeAutomationElementsRemoveChild);
  xeAutomationRegisterCommand('elements.copy_child_to', xeAutomationElementsCopyChildTo);
end;

end.
