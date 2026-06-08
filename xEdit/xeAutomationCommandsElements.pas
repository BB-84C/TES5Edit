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

function xeAutomationElementsAddChildBuildAvailableTemplatesDetails(
  const ATemplates: TwbTemplateElements): TJsonObject;
var
  lArray: TJsonArray;
  lEntry: TJsonObject;
  i: Integer;
begin
  Result := TJsonObject.Create;
  lArray := Result.A['availableTemplates'];
  for i := Low(ATemplates) to High(ATemplates) do begin
    lEntry := lArray.AddObject;
    lEntry.I['index'] := i;
    lEntry.S['name'] := ATemplates[i].Name;
  end;
end;

function xeAutomationElementsAddChildSelectTemplate(
  const ATemplates: TwbTemplateElements; const AArgs: TJsonObject;
  out ASelectedIndex: Integer): IwbTemplateElement;
var
  lHasIndex, lHasName: Boolean;
  lIndex: Integer;
  lName: string;
  lMatch: Integer;
  lFoundCount: Integer;
  lDetails: TJsonObject;
  i: Integer;
begin
  Result := nil;
  ASelectedIndex := -1;

  lHasIndex := xeAutomationArgPresent(AArgs, 'templateIndex');
  lHasName  := xeAutomationArgPresent(AArgs, 'templateName');
  if lHasName and (AArgs.Types['templateName'] <> jdtString) then
    raise xeAutomationInvalidRequest('Automation arg "templateName" must be a string');

  if not lHasIndex and not lHasName then begin
    if Length(ATemplates) > 1 then begin
      lDetails := xeAutomationElementsAddChildBuildAvailableTemplatesDetails(ATemplates);
      try
        // The error factory copies details, so this caller retains/free owns the builder result.
        raise xeAutomationMutationNotAllowedWithDetails(
          'Automation mutation target requires explicit template selection', lDetails);
      finally
        lDetails.Free;
      end;
    end;
    if Length(ATemplates) = 1 then begin
      Result := ATemplates[0];
      ASelectedIndex := 0;
    end;
    Exit;
  end;

  if lHasIndex then begin
    if AArgs.Types['templateIndex'] <> jdtInt then
      raise xeAutomationInvalidRequest('Automation arg "templateIndex" must be an integer');
    lIndex := AArgs.I['templateIndex'];
    if (lIndex < 0) or (lIndex > High(ATemplates)) then
      raise xeAutomationInvalidRequest('Automation arg "templateIndex" out of range');
  end;

  if lHasName then begin
    lName := Trim(AArgs.S['templateName']);
    if lName = '' then
      raise xeAutomationInvalidRequest('Automation arg "templateName" must be a non-empty string');
    lMatch := -1;
    lFoundCount := 0;
    for i := Low(ATemplates) to High(ATemplates) do
      if SameText(ATemplates[i].Name, lName) then begin
        lMatch := i;
        Inc(lFoundCount);
      end;
    if lFoundCount = 0 then
      raise xeAutomationInvalidRequest('Automation arg "templateName" matches no available template');
    if lFoundCount > 1 then
      raise xeAutomationInvalidRequest('Automation arg "templateName" is ambiguous; use "templateIndex"');
    if lHasIndex and (lMatch <> lIndex) then
      raise xeAutomationInvalidRequest('Automation args "templateIndex" and "templateName" disagree');
    ASelectedIndex := lMatch;
  end else begin
    ASelectedIndex := lIndex;
  end;

  Result := ATemplates[ASelectedIndex];
end;

function xeAutomationElementsAddChild(const AArgs: TJsonObject): TJsonObject;
var
  lLocator: TxeAutomationLocator;
  lRecord: IwbMainRecord;
  lElement: IwbElement;
  lNewElement: IwbElement;
  lTargetIndex: Integer;
  lTemplate: IwbTemplateElement;
  lSelectedTemplateIndex: Integer;
  lTemplates: TwbTemplateElements;
  lDeniedReason: string;
  lPlacement: TJsonObject;
begin
  if not xeAutomationMutationPolicyConsentSatisfied(lDeniedReason) then begin
    Result := xeAutomationErrorsBuildConsentRequired('elements.add_child', 'elements-mutation', lDeniedReason);
    Exit;
  end;

  lLocator := xeAutomationParseLocator(AArgs, True, True);
  lElement := xeAutomationRequireOwnedElement(lLocator, lRecord);

  if xeAutomationArgPresent(AArgs, 'targetIndex') then begin
    if AArgs.Types['targetIndex'] <> jdtInt then
      raise xeAutomationInvalidRequest('Automation arg "targetIndex" must be an integer');
    lTargetIndex := AArgs.I['targetIndex'];
  end else begin
    lTargetIndex := wbAssignAdd;
  end;

  xeAutomationRequireAddableElementTargetAt(lElement, lTargetIndex);

  lTemplates := lElement.GetAssignTemplates(lTargetIndex);
  lTemplate := xeAutomationElementsAddChildSelectTemplate(lTemplates, AArgs, lSelectedTemplateIndex);

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

  Result.O['target'].O['locator'].S['file']   := lRecord._File.FileName;
  Result.O['target'].O['locator'].S['formId'] := lRecord.LoadOrderFormID.ToString(False);
  Result.O['target'].O['locator'].S['path']   := lLocator.Path;

  lPlacement := Result.O['placement'];
  if lTargetIndex = wbAssignAdd then
    lPlacement.S['mode'] := 'append'
  else begin
    lPlacement.S['mode']  := 'index';
    lPlacement.I['value'] := lTargetIndex;
  end;

  if Assigned(lTemplate) then begin
    Result.O['selectedTemplate'].I['index'] := lSelectedTemplateIndex;
    Result.O['selectedTemplate'].S['name']  := lTemplate.Name;
  end;
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

function xeAutomationCopyChildAddMastersIfRequested(
  const ASourceElement: IwbElement; const ATargetFile: IwbFile;
  const AAddRequiredMasters: Boolean): TJsonObject;
var
  lRequired: TStringList;
  lAdded, lAlreadyPresent, lSkipped: TJsonArray;
  lMaster: IwbFile;
  i: Integer;
begin
  Result := TJsonObject.Create;
  try
    lAdded          := Result.A['added'];
    lAlreadyPresent := Result.A['alreadyPresent'];
    lSkipped        := Result.A['skipped'];

    lRequired := xeAutomationCollectRequiredMasters(ASourceElement, ATargetFile);
    try
      for i := 0 to Pred(lRequired.Count) do begin
        lMaster := IwbFile(Pointer(lRequired.Objects[i]));
        if ATargetFile.HasMaster(lMaster.FileName) then begin
          lAlreadyPresent.Add(lMaster.FileName);
          Continue;
        end;
        if not AAddRequiredMasters then begin
          // Track missing masters as skipped; we'll raise mutation_not_allowed
          // after the walk so the report still contains the full diagnostic set.
          lSkipped.Add(lMaster.FileName);
          Continue;
        end;
        ATargetFile.AddMasterIfMissing(lMaster.FileName);
        lAdded.Add(lMaster.FileName);
      end;
    finally
      lRequired.Free;
    end;

    if not AAddRequiredMasters and (lSkipped.Count > 0) then
      raise xeAutomationMutationNotAllowed(
        'Automation mutation target is missing required masters; pass addRequiredMasters:true to add them');
  except
    Result.Free;
    raise;
  end;
end;

procedure xeAutomationCopyChildApplySortOrderFixup(
  const ANewElement: IwbElement; const ATargetIndex: Integer;
  const APlacement: TJsonObject);
var
  lContainer: IwbContainerElementRef;
begin
  // Per design §15.2: only fix up sort order when targetIndex is a concrete
  // non-wbAssignAdd integer and the copied child lives in a container reference
  // that xEdit can reorder by SortOrder. Otherwise native Assign's placement is
  // the only mutation and the response reports no explicit sort-order pass.
  APlacement.B['sortOrderApplied'] := False;
  if ATargetIndex = wbAssignAdd then
    Exit;
  if not Assigned(ANewElement) then
    Exit;
  if not Supports(ANewElement.Container, IwbContainerElementRef, lContainer) then
    Exit;

  // Mirror xEdit/xeMainForm.pas drag/drop sort fix: set SortOrder on the new
  // element to the requested position, then ask the container to re-sort and
  // refresh memory order. IwbContainerBase exposes SortBySortOrder as the native
  // operation rather than a separate boolean predicate, so support for the
  // container-ref seam is the precise automation gate available here.
  ANewElement.SortOrder := ATargetIndex;
  lContainer.SortBySortOrder;
  lContainer.ResetMemoryOrder;
  APlacement.B['sortOrderApplied'] := True;
end;

function xeAutomationElementsCopyChildTo(const AArgs: TJsonObject): TJsonObject;
var
  lSourceLocator, lTargetLocator: TxeAutomationLocator;
  lSourceRecord, lTargetRecord:   IwbMainRecord;
  lSourceElement: IwbElement;
  lTargetElement: IwbElement;
  lNewElement: IwbElement;
  lTargetIndex: Integer;
  lAddRequiredMasters: Boolean;
  lDeniedReason: string;
  lPlacement: TJsonObject;
  lMasters: TJsonObject;
begin
  if not xeAutomationMutationPolicyConsentSatisfied(lDeniedReason) then begin
    Result := xeAutomationErrorsBuildConsentRequired(
      'elements.copy_child_to', 'elements-mutation', lDeniedReason);
    Exit;
  end;

  lSourceLocator := xeAutomationParseNestedLocatorArg(AArgs, 'source', True, True);
  lTargetLocator := xeAutomationParseNestedLocatorArg(AArgs, 'target', True, True);

  if Trim(lSourceLocator.Path) = '' then
    raise xeAutomationInvalidTarget(
      'Automation mutation source must address an existing child element');

  if xeAutomationArgPresent(AArgs, 'targetIndex') then begin
    if AArgs.Types['targetIndex'] <> jdtInt then
      raise xeAutomationInvalidRequest('Automation arg "targetIndex" must be an integer');
    lTargetIndex := AArgs.I['targetIndex'];
  end else begin
    lTargetIndex := wbAssignAdd;
  end;

  // Per design §3.G Overseer override: default FALSE to preserve backward
  // compatibility of an already-shipped verb. Callers opt into GUI parity
  // explicitly by passing addRequiredMasters:true.
  lAddRequiredMasters := False;
  if xeAutomationArgPresent(AArgs, 'addRequiredMasters') then begin
    if AArgs.Types['addRequiredMasters'] <> jdtBool then
      raise xeAutomationInvalidRequest('Automation arg "addRequiredMasters" must be a boolean');
    lAddRequiredMasters := AArgs.B['addRequiredMasters'];
  end;

  lSourceElement := xeAutomationRequireElement(lSourceLocator, lSourceRecord);
  lTargetElement := xeAutomationRequireOwnedElement(lTargetLocator, lTargetRecord);
  xeAutomationRequireCopyTargetAt(lTargetElement, lSourceElement, lTargetIndex);

  // Preflight masters first so addRequiredMasters:false fails before any
  // structural mutation. The helper handles both branches and produces the
  // masters block whether we succeed or raise.
  lMasters := xeAutomationCopyChildAddMastersIfRequested(
    lSourceElement, lTargetRecord._File, lAddRequiredMasters);
  try
    lNewElement := lTargetElement.Assign(lTargetIndex, lSourceElement, False);
    if not Assigned(lNewElement) then
      raise xeAutomationMutationNotAllowed(
        'Automation mutation target cannot accept the addressed source child');

    Result := xeAutomationNewMutationResult(
      True,
      lTargetRecord._File.Modified,
      lTargetRecord._File.FileName,
      lTargetRecord.LoadOrderFormID.ToString(False),
      xeAutomationElementLocatorPath(lNewElement)
    );
    Result.O['file'] := xeAutomationNewFileSummary(lTargetRecord._File);

    // Echo both locators so callers can re-resolve target/source post-mutation
    // without re-parsing their original request.
    Result.O['source'].O['locator'].S['file']   := lSourceRecord._File.FileName;
    Result.O['source'].O['locator'].S['formId'] := lSourceRecord.LoadOrderFormID.ToString(False);
    Result.O['source'].O['locator'].S['path']   := lSourceLocator.Path;
    Result.O['target'].O['locator'].S['file']   := lTargetRecord._File.FileName;
    Result.O['target'].O['locator'].S['formId'] := lTargetRecord.LoadOrderFormID.ToString(False);
    Result.O['target'].O['locator'].S['path']   := lTargetLocator.Path;

    lPlacement := Result.O['placement'];
    if lTargetIndex = wbAssignAdd then
      lPlacement.S['mode'] := 'append'
    else begin
      lPlacement.S['mode']  := 'index';
      lPlacement.I['value'] := lTargetIndex;
    end;
    xeAutomationCopyChildApplySortOrderFixup(lNewElement, lTargetIndex, lPlacement);

    Result.O['masters'] := lMasters;
    lMasters := nil;
  except
    lMasters.Free;
    raise;
  end;
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
