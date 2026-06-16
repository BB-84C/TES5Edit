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
  Variants,
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

function xeAutomationReadBooleanArgDefault(const AArgs: TJsonObject; const AName: string;
  const ADefault: Boolean): Boolean;
var
  lHasValue: Boolean;
begin
  Result := xeAutomationReadBooleanArg(AArgs, AName, lHasValue);
  if not lHasValue then
    Result := ADefault;
end;

function xeAutomationReadIncludeParentsArg(const AArgs: TJsonObject): Boolean;
begin
  Result := xeAutomationReadBooleanArgDefault(AArgs, 'includeParents', False);
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

procedure xeAutomationWriteMainRecordSummary(const ATarget: TJsonObject; const ARecord: IwbMainRecord);
begin
  ATarget.S['kind'] := 'record';
  ATarget.S['signature'] := ARecord.Signature;
  ATarget.S['formId'] := ARecord.LoadOrderFormID.ToString(False);
  ATarget.B['isMaster'] := ARecord.IsMaster;
  ATarget.B['isDeleted'] := ARecord.IsDeleted;
  ATarget.B['isWinningOverride'] := ARecord.IsWinningOverride;
  ATarget.I['overrideCount'] := ARecord.OverrideCount;

  if ARecord.CanHaveEditorID and (Trim(ARecord.EditorID) <> '') then
    ATarget.S['editorId'] := xeAutomationBoundedText(ARecord.EditorID);
  if ARecord.CanHaveFullName and (Trim(ARecord.FullName) <> '') then
    ATarget.S['fullName'] := xeAutomationBoundedText(ARecord.FullName);
  if Trim(ARecord.DisplayNameKey) <> '' then
    ATarget.S['displayNameKey'] := xeAutomationBoundedText(ARecord.DisplayNameKey);
end;

function xeAutomationNewMainRecordElementResponse(const ARecord: IwbMainRecord): TJsonObject;
begin
  Result := xeAutomationNewObjectResponse(
    ARecord._File.FileName,
    ARecord.LoadOrderFormID.ToString(False),
    ''
  );
  xeAutomationWriteMainRecordSummary(Result.O['object'], ARecord);
  // Main records reached while walking a ChildGroup re-enter the existing record
  // locator contract so every other records.* / elements.* verb can use them unchanged.
  xeAutomationAddChildrenRelation(Result);
end;

function xeAutomationGroupGridLabel(const AGroup: IwbGroupRecord): string;
begin
  Result := Format('%d, %d', [
    LongRecSmall(AGroup.GroupLabel).Hi,
    LongRecSmall(AGroup.GroupLabel).Lo
  ]);
end;

function xeAutomationChildGroupSynthLabel(
  const AParentGroup, AChildGroup: IwbGroupRecord): string;
begin
  Result := '';
  if not Assigned(AChildGroup) then
    Exit;

  case AChildGroup.GroupType of
    4:
      Result := 'Block ' + xeAutomationGroupGridLabel(AChildGroup);
    5:
      Result := 'Sub-Block ' + xeAutomationGroupGridLabel(AChildGroup);
    8:
      Result := 'Persistent';
    9:
      Result := 'Temporary';
    10:
      if Assigned(AParentGroup) and (AParentGroup.GroupType = 6) then
        Result := 'Visible when Distant'
      else
        Result := AChildGroup.ShortName;
    6:
      if Assigned(AParentGroup) and (AParentGroup.GroupType = 1) then
        Result := 'Persistent'
      else
        Result := AChildGroup.ShortName;
  else
    Result := AChildGroup.ShortName;
  end;
end;

function xeAutomationSuppressContextualChildGroup(
  const AParentGroup, AChildGroup: IwbGroupRecord): Boolean;
begin
  // WRLD ChildGroups can contain both the persistent CELL record and that CELL's
  // own GroupType-6 children GRUP. Emit the CELL by flat FormID only; callers can
  // then follow the CELL's own \Child Group breadcrumb without a colliding
  // WRLD-relative \Child Group\Persistent synthetic path.
  Result := Assigned(AParentGroup) and Assigned(AChildGroup) and
    (AParentGroup.GroupType = 1) and (AChildGroup.GroupType = 6);
end;

function xeAutomationNewChildGroupStub(
  const AOwnerRecord: IwbMainRecord;
  const AGroup: IwbGroupRecord;
  const ASynthPath: string): TJsonObject;
var
  lContainer: IwbContainer;
  lChildElement: IwbElement;
  lChildRecord: IwbMainRecord;
  lSeen: TStringList;
  lSignatures: TJsonArray;
  lSig: string;
  i: Integer;
begin
  Result := nil;
  if not Assigned(AOwnerRecord) or not Assigned(AGroup) then
    Exit;
  if not Supports(AGroup, IwbContainer, lContainer) then
    Exit;
  // Empty ChildGroups are suppressed so callers never receive dangling
  // navigation affordances that immediately resolve to no visible contents.
  if lContainer.ElementCount = 0 then
    Exit;

  Result := TJsonObject.Create;
  try
    Result.O['locator'].S['file'] := AOwnerRecord._File.FileName;
    Result.O['locator'].S['formId'] := AOwnerRecord.LoadOrderFormID.ToString(False);
    Result.O['locator'].S['path'] := ASynthPath;

    Result.O['object'].S['kind'] := 'child_group';
    Result.O['object'].S['name'] := xeAutomationBoundedText(AGroup.ShortName);
    Result.O['object'].I['groupType'] := AGroup.GroupType;
    Result.O['object'].I['count'] := lContainer.ElementCount;

    lSeen := TStringList.Create;
    try
      lSeen.Sorted := True;
      lSeen.Duplicates := dupIgnore;
      for i := 0 to Pred(lContainer.ElementCount) do begin
        lChildElement := lContainer.Elements[i];
        if not Assigned(lChildElement) then
          Continue;

        if Supports(lChildElement, IwbMainRecord, lChildRecord) and Assigned(lChildRecord) then begin
          lSig := string(lChildRecord.Signature);
          if lSig <> '' then
            lSeen.Add(lSig);
        end;
      end;

      if lSeen.Count > 0 then begin
        lSignatures := Result.O['object'].A['signatures'];
        for i := 0 to Pred(lSeen.Count) do
          lSignatures.Add(lSeen[i]);
      end;
    finally
      lSeen.Free;
    end;

    Result.O['relations'].O['children'].S['command'] := 'elements.children';
    Result.O['relations'].O['children'].O['locator'].S['file'] := AOwnerRecord._File.FileName;
    Result.O['relations'].O['children'].O['locator'].S['formId'] := AOwnerRecord.LoadOrderFormID.ToString(False);
    Result.O['relations'].O['children'].O['locator'].S['path'] := ASynthPath;
  except
    Result.Free;
    raise;
  end;
end;

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
  lMainRecord: IwbMainRecord;
begin
  if Supports(AElement, IwbMainRecord, lMainRecord)
    and (not SameText(lMainRecord._File.FileName, ARecord._File.FileName)
      or (lMainRecord.LoadOrderFormID <> ARecord.LoadOrderFormID)) then
    Exit(xeAutomationNewMainRecordElementResponse(lMainRecord));

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

procedure xeAutomationAppendParentsForElementResponse(const AResponse: TJsonObject;
  const AOwnerRecord: IwbMainRecord; const AElement: IwbElement);
var
  lRecord: IwbMainRecord;
begin
  lRecord := AOwnerRecord;
  if Supports(AElement, IwbMainRecord, lRecord) and Assigned(lRecord) then begin
    xeAutomationAppendParentsRelation(AResponse, xeAutomationCollectAncestorChain(lRecord, 16));
    Exit;
  end;
  xeAutomationAppendParentsRelation(AResponse, xeAutomationCollectAncestorChain(AOwnerRecord, 16));
end;

function xeAutomationElementsBuildBeforeAfterSnapshot(
  const ARecord: IwbMainRecord; const AElement: IwbElement): TJsonObject;
begin
  Result := TJsonObject.Create;
  try
    Result.O['locator'].S['file']   := ARecord._File.FileName;
    Result.O['locator'].S['formId'] := ARecord.LoadOrderFormID.ToString(False);
    Result.O['locator'].S['path']   := xeAutomationElementLocatorPath(AElement);
    Result.S['editValue'] := AElement.EditValue;
    xeAutomationWriteElementSummary(
      Result.O['object'], AElement, xeAutomationElementLocatorPath(AElement));
  except
    Result.Free;
    raise;
  end;
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
  lIncludeParents: Boolean;
begin
  lIncludeParents := xeAutomationReadIncludeParentsArg(AArgs);
  lLocator := xeAutomationParseLocator(AArgs, True, True);
  lElement := xeAutomationRequireElement(lLocator, lRecord);
  Result := xeAutomationNewElementResponse(lRecord, lElement);
  if lIncludeParents then
    xeAutomationAppendParentsForElementResponse(Result, lRecord, lElement);
end;

function xeAutomationElementsChildren(const AArgs: TJsonObject): TJsonObject;
var
  lLocator: TxeAutomationLocator;
  lRecord: IwbMainRecord;
  lElement: IwbElement;
  lContainer: IwbContainer;
  lChildren: TJsonArray;
  lChild: IwbElement;
  lChildGroup: IwbGroupRecord;
  lChildSynthPath: string;
  lMain: IwbMainRecord;
  lParentIsChildGroup: Boolean;
  lParentGroup: IwbGroupRecord;
  lParentSynthPath: string;
  lStub: TJsonObject;
  lLimit: Integer;
  lOffset: Integer;
  lTotal: Integer;
  lEndIndex: Integer;
  lIncludeParents: Boolean;
  lEntry: TJsonObject;
  i: Integer;
begin
  lIncludeParents := xeAutomationReadIncludeParentsArg(AArgs);
  lLocator := xeAutomationParseLocator(AArgs, True, True);
  lElement := xeAutomationRequireElement(lLocator, lRecord);
  lLimit := xeAutomationReadChildrenLimitArg(AArgs);
  lOffset := xeAutomationReadOffsetArg(AArgs);
  if xeAutomationPathStartsWithChildGroupPrefix(lLocator.Path) then
    lParentSynthPath := lLocator.Path
  else
    lParentSynthPath := '';

  Result := TJsonObject.Create;
  lChildren := Result.A['children'];
  if not Supports(lElement, IwbContainer, lContainer) then begin
    Result.I['count'] := 0;
    Result.I['total'] := 0;
    Result.I['offset'] := lOffset;
    Result.B['truncated'] := False;
    Exit;
  end;

  lTotal := lContainer.ElementCount;
  if lOffset >= lTotal then begin
    Result.I['count'] := 0;
    Result.I['total'] := lTotal;
    Result.I['offset'] := lOffset;
    Result.B['truncated'] := False;
    Exit;
  end;

  if lLimit > (lTotal - lOffset) then
    lEndIndex := lTotal
  else
    lEndIndex := lOffset + lLimit;

  lParentIsChildGroup := (lParentSynthPath <> '') and Supports(lElement, IwbGroupRecord, lParentGroup);

  // Pagination is applied before per-child response materialization so dense
  // ChildGroups cannot overflow the named-pipe transport buffer. The total field
  // remains the native immediate-child count, not the synthetic ChildGroup stub.
  for i := lOffset to Pred(lEndIndex) do begin
    lChild := lContainer.Elements[i];
    if not Assigned(lChild) then
      Continue;

    // Some main records exposed from terminal GRUPs also satisfy group-flavored
    // interfaces. Prefer the flat MainRecord locator first so terminal ChildGroup
    // walks never reinterpret real records as synthetic nested GRUP breadcrumbs.
    if Supports(lChild, IwbMainRecord, lMain) and Assigned(lMain) then begin
      lEntry := xeAutomationNewMainRecordElementResponse(lMain);
      if lIncludeParents then
        xeAutomationAppendParentsRelation(lEntry, xeAutomationCollectAncestorChain(lMain, 16));
      lChildren.Add(lEntry);
    end
    else if lParentIsChildGroup and Supports(lChild, IwbGroupRecord, lChildGroup) and Assigned(lChildGroup) then begin
      if xeAutomationSuppressContextualChildGroup(lParentGroup, lChildGroup) then
        Continue;
      lChildSynthPath := lParentSynthPath + '\' + xeAutomationChildGroupSynthLabel(lParentGroup, lChildGroup);
      if lChildSynthPath = lParentSynthPath + '\' then
        Continue;
      lStub := xeAutomationNewChildGroupStub(lRecord, lChildGroup, lChildSynthPath);
      if Assigned(lStub) then begin
        if lIncludeParents then
          xeAutomationAppendParentsRelation(lStub, xeAutomationCollectAncestorChain(lRecord, 16));
        lChildren.Add(lStub);
      end;
    end else begin
      lEntry := xeAutomationNewElementResponse(lRecord, lChild);
      if lIncludeParents then
        xeAutomationAppendParentsForElementResponse(lEntry, lRecord, lChild);
      lChildren.Add(lEntry);
    end;
  end;

  // Phase 15H keeps the Phase 15A virtual ChildGroup affordance only on the
  // first page. It counts as a returned entry, but never as part of total, so
  // clients can page native children by offset without seeing duplicate stubs.
  if (lOffset = 0) and Supports(lElement, IwbMainRecord, lMain) and Assigned(lMain.ChildGroup) then begin
    lStub := xeAutomationNewChildGroupStub(lMain, lMain.ChildGroup, '\Child Group');
    if Assigned(lStub) then begin
      if lIncludeParents then
        xeAutomationAppendParentsRelation(lStub, xeAutomationCollectAncestorChain(lMain, 16));
      lChildren.Add(lStub);
    end;
  end;

  Result.I['count'] := lChildren.Count;
  Result.I['total'] := lTotal;
  Result.I['offset'] := lOffset;
  Result.B['truncated'] := lEndIndex < lTotal;
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

function xeAutomationElementsSetToDefault(const AArgs: TJsonObject): TJsonObject;
var
  lLocator: TxeAutomationLocator;
  lRecord: IwbMainRecord;
  lElement: IwbElement;
  lBefore: TJsonObject;
  lDeniedReason: string;
begin
  if not xeAutomationMutationPolicyConsentSatisfied(lDeniedReason) then begin
    Result := xeAutomationErrorsBuildConsentRequired(
      'elements.set_to_default', 'elements-mutation', lDeniedReason);
    Exit;
  end;

  lLocator := xeAutomationParseLocator(AArgs, True, True);
  lElement := xeAutomationRequireOwnedElement(lLocator, lRecord);
  xeAutomationRequireSetToDefaultTarget(lElement);

  lBefore := xeAutomationElementsBuildBeforeAfterSnapshot(lRecord, lElement);
  try
    // SetToDefault is intentionally in-memory only; callers persist later with session.save.
    lElement.SetToDefault;

    Result := xeAutomationNewMutationResult(
      lBefore.S['editValue'] <> lElement.EditValue,
      lRecord._File.Modified,
      lRecord._File.FileName,
      lRecord.LoadOrderFormID.ToString(False),
      xeAutomationElementLocatorPath(lElement)
    );
    Result.O['file'] := xeAutomationNewFileSummary(lRecord._File);
    Result.O['before'].Assign(lBefore);
    Result.O['after'] := xeAutomationElementsBuildBeforeAfterSnapshot(lRecord, lElement);
  finally
    lBefore.Free;
  end;
end;

function xeAutomationElementsClear(const AArgs: TJsonObject): TJsonObject;
var
  lLocator: TxeAutomationLocator;
  lRecord: IwbMainRecord;
  lElement: IwbElement;
  lContainer: IwbContainer;
  lBefore: TJsonObject;
  lBeforeCount: Integer;
  lDeniedReason: string;
begin
  if not xeAutomationMutationPolicyConsentSatisfied(lDeniedReason) then begin
    Result := xeAutomationErrorsBuildConsentRequired(
      'elements.clear', 'elements-mutation', lDeniedReason);
    Exit;
  end;

  lLocator := xeAutomationParseLocator(AArgs, True, True);
  lElement := xeAutomationRequireOwnedElement(lLocator, lRecord);
  xeAutomationRequireClearableElementTarget(lElement);

  lBeforeCount := 0;
  if Supports(lElement, IwbContainer, lContainer) then
    lBeforeCount := lContainer.ElementCount;

  lBefore := xeAutomationElementsBuildBeforeAfterSnapshot(lRecord, lElement);
  try
    // Clear follows xEdit's native IsClearable policy and leaves persistence explicit.
    lElement.Clear;

    Result := xeAutomationNewMutationResult(
      lBeforeCount > 0,
      lRecord._File.Modified,
      lRecord._File.FileName,
      lRecord.LoadOrderFormID.ToString(False),
      xeAutomationElementLocatorPath(lElement)
    );
    Result.O['file'] := xeAutomationNewFileSummary(lRecord._File);
    Result.O['before'].Assign(lBefore);
    Result.O['after'] := xeAutomationElementsBuildBeforeAfterSnapshot(lRecord, lElement);
    Result.I['removedCount'] := lBeforeCount;
  finally
    lBefore.Free;
  end;
end;

function xeAutomationElementsSetNativeValueParseValue(
  const AArgs: TJsonObject; const AKind: string): Variant;
var
  lValueType: TJsonDataType;
  lRawString: string;
  lInt64Value: Int64;
  lParsedFormId: Cardinal;
  lArray: TJsonArray;
  lVarArray: Variant;
  i: Integer;
begin
  lValueType := AArgs.Types['value'];

  // Explicit kind assertions intentionally validate the JSON shape before xEdit
  // sees the Variant, so malformed requests fail with stable protocol errors.
  if AKind <> '' then begin
    if SameText(AKind, 'int') then begin
      if lValueType = jdtString then begin
        if not TryStrToInt64(Trim(AArgs.S['value']), lInt64Value) then
          raise xeAutomationInvalidRequest('Automation arg "value" with kind:"int" must be a parsable integer string');
        Exit(lInt64Value);
      end;
      if lValueType in [jdtInt, jdtLong] then
        Exit(AArgs.L['value']);
      raise xeAutomationInvalidRequest('Automation arg "value" with kind:"int" must be a number or decimal string');
    end;
    if SameText(AKind, 'float') then begin
      if lValueType in [jdtFloat, jdtInt, jdtLong] then
        Exit(Double(AArgs.F['value']));
      raise xeAutomationInvalidRequest('Automation arg "value" with kind:"float" must be a number');
    end;
    if SameText(AKind, 'string') then begin
      if lValueType <> jdtString then
        raise xeAutomationInvalidRequest('Automation arg "value" with kind:"string" must be a string');
      Exit(AArgs.S['value']);
    end;
    if SameText(AKind, 'bool') then begin
      if lValueType <> jdtBool then
        raise xeAutomationInvalidRequest('Automation arg "value" with kind:"bool" must be a boolean');
      Exit(AArgs.B['value']);
    end;
    if SameText(AKind, 'formId') then begin
      if lValueType <> jdtString then
        raise xeAutomationInvalidRequest('Automation arg "value" with kind:"formId" must be a hex string');
      lRawString := Trim(AArgs.S['value']);
      lParsedFormId := xeAutomationParseFormIdHex(lRawString);
      Exit(lParsedFormId);
    end;
    if SameText(AKind, 'formIdArray') then begin
      if lValueType <> jdtArray then
        raise xeAutomationInvalidRequest('Automation arg "value" with kind:"formIdArray" must be a JSON array of hex strings');
      lArray := AArgs.A['value'];
      // varLongWord matches Cardinal's unsigned 32-bit range; FormIDs can exceed
      // signed varInteger and would otherwise overflow into negative values.
      lVarArray := VarArrayCreate([0, Pred(lArray.Count)], varLongWord);
      for i := 0 to Pred(lArray.Count) do begin
        if lArray.Types[i] <> jdtString then
          raise xeAutomationInvalidRequest('Automation arg "value[i]" with kind:"formIdArray" must be a hex string');
        lVarArray[i] := xeAutomationParseFormIdHex(lArray.S[i]);
      end;
      Exit(lVarArray);
    end;
    raise xeAutomationInvalidRequest(
      Format('Automation arg "kind" must be one of int/float/string/bool/formId/formIdArray, got "%s"', [AKind]));
  end;

  // With no kind hint, keep the automation surface close to JSON semantics and let
  // native xEdit schema conversion decide whether the resulting Variant is valid.
  case lValueType of
    jdtString: Exit(AArgs.S['value']);
    jdtBool:   Exit(AArgs.B['value']);
    jdtInt:    Exit(AArgs.I['value']);
    jdtLong:   Exit(AArgs.L['value']);
    jdtFloat:  Exit(Double(AArgs.F['value']));
    jdtNone:   Exit(Variants.Null);
  else
    raise xeAutomationInvalidRequest('Automation arg "value" is unsupported JSON type');
  end;
end;

function xeAutomationElementsSetNativeValueBuildBeforeAfter(
  const AElement: IwbElement): TJsonObject;
var
  lObject: TJsonObject;
begin
  Result := TJsonObject.Create;
  try
    Result.S['editValue'] := AElement.EditValue;
    lObject := Result.O['object'];
    xeAutomationWriteElementSummary(
      lObject, AElement, xeAutomationElementLocatorPath(AElement));
    // NativeValue can expose schema-specific Variant shapes that JSON cannot echo
    // faithfully. Emit a native block only for unambiguous scalar round-trips; the
    // canonical proof remains editValue plus the full element summary envelope.
    try
      case VarType(AElement.NativeValue) and varTypeMask of
        varEmpty, varNull:
          Result.O['nativeValue'].B['null'] := True;
        varInteger, varSmallint, varShortInt, varByte, varWord:
          Result.O['nativeValue'].I['intValue'] := AElement.NativeValue;
        varLongWord, varInt64, varUInt64:
          Result.O['nativeValue'].L['longValue'] := AElement.NativeValue;
        varSingle, varDouble:
          Result.O['nativeValue'].F['floatValue'] := AElement.NativeValue;
        varBoolean:
          Result.O['nativeValue'].B['boolValue'] := AElement.NativeValue;
        varOleStr, varString, varUString:
          Result.O['nativeValue'].S['stringValue'] := AElement.NativeValue;
      end;
    except
      // Swallow best-effort native echo failures; editValue is canonical proof.
    end;
  except
    Result.Free;
    raise;
  end;
end;

function xeAutomationElementsSetNativeValue(const AArgs: TJsonObject): TJsonObject;
var
  lLocator: TxeAutomationLocator;
  lRecord: IwbMainRecord;
  lElement: IwbElement;
  lKind: string;
  lParsedValue: Variant;
  lBefore: TJsonObject;
  lDeniedReason: string;
begin
  if not xeAutomationMutationPolicyConsentSatisfied(lDeniedReason) then begin
    Result := xeAutomationErrorsBuildConsentRequired(
      'elements.set_native_value', 'elements-mutation', lDeniedReason);
    Exit;
  end;

  lLocator := xeAutomationParseLocator(AArgs, True, True);
  lElement := xeAutomationRequireOwnedElement(lLocator, lRecord);
  xeAutomationRequireWritableElementTarget(lElement);

  if not AArgs.Contains('value') then
    raise xeAutomationInvalidRequest('Automation arg "value" is required');

  lKind := '';
  if xeAutomationArgPresent(AArgs, 'kind') then begin
    if AArgs.Types['kind'] <> jdtString then
      raise xeAutomationInvalidRequest('Automation arg "kind" must be a string');
    lKind := AArgs.S['kind'];
  end;

  lParsedValue := xeAutomationElementsSetNativeValueParseValue(AArgs, lKind);

  lBefore := xeAutomationElementsSetNativeValueBuildBeforeAfter(lElement);
  try
    try
      // NativeValue writes are schema-sensitive; wrap native conversion failures
      // as mutation denials so callers can distinguish policy/schema rejection
      // from malformed automation request parsing.
      lElement.NativeValue := lParsedValue;
    except
      on E: ExeAutomationError do
        raise;
      on E: Exception do
        raise xeAutomationMutationNotAllowed(
          Format('Native value rejected by xEdit schema: %s', [E.Message]));
    end;

    Result := xeAutomationNewMutationResult(
      lBefore.S['editValue'] <> lElement.EditValue,
      lRecord._File.Modified,
      lRecord._File.FileName,
      lRecord.LoadOrderFormID.ToString(False),
      xeAutomationElementLocatorPath(lElement)
    );
    Result.O['file'] := xeAutomationNewFileSummary(lRecord._File);
    Result.O['before'].Assign(lBefore);
    Result.O['after'] := xeAutomationElementsSetNativeValueBuildBeforeAfter(lElement);
  finally
    lBefore.Free;
  end;
end;

procedure xeAutomationElementsWriteTemplateList(
  const ATarget: TJsonArray; const ATemplates: TwbTemplateElements);
var
  lEntry: TJsonObject;
  i: Integer;
begin
  for i := Low(ATemplates) to High(ATemplates) do begin
    lEntry := ATarget.AddObject;
    lEntry.I['index'] := i;
    lEntry.S['name']  := ATemplates[i].Name;
  end;
end;

function xeAutomationElementsResolveTargetIndexArg(
  const AArgs: TJsonObject; out ATargetIndex: Integer): string;
begin
  // Optional targetIndex defaults to xEdit's append sentinel. A present-but-wrong
  // JSON type is a malformed automation request, not an implicit append.
  if xeAutomationArgPresent(AArgs, 'targetIndex') then begin
    if AArgs.Types['targetIndex'] <> jdtInt then
      raise xeAutomationInvalidRequest('Automation arg "targetIndex" must be an integer');
    ATargetIndex := AArgs.I['targetIndex'];
    Result := IntToStr(ATargetIndex);
  end else begin
    ATargetIndex := wbAssignAdd;
    Result := 'append';
  end;
end;

function xeAutomationElementsEditCapabilities(const AArgs: TJsonObject): TJsonObject;
var
  lLocator: TxeAutomationLocator;
  lRecord: IwbMainRecord;
  lElement: IwbElement;
  lTargetIndex: Integer;
  lTargetIndexLabel: string;
  lSourceLocator: TxeAutomationLocator;
  lSourceRecord: IwbMainRecord;
  lSourceElement: IwbElement;
  lHasSource: Boolean;
  lCanAssign: Boolean;
  lTemplates: TwbTemplateElements;
  lWritableTargetFile: Boolean;
begin
  // This is a read-only discovery command: it reports native predicates plus the
  // narrower automation write policy without requiring mutation consent.
  lLocator := xeAutomationParseLocator(AArgs, True, True);
  lElement := xeAutomationRequireElement(lLocator, lRecord);

  lTargetIndexLabel := xeAutomationElementsResolveTargetIndexArg(AArgs, lTargetIndex);

  lHasSource := AArgs.Contains('source') and (AArgs.Types['source'] = jdtObject);
  lSourceElement := nil;
  if lHasSource then begin
    lSourceLocator := xeAutomationParseNestedLocatorArg(AArgs, 'source', True, True);
    lSourceElement := xeAutomationRequireElement(lSourceLocator, lSourceRecord);
  end;

  Result := TJsonObject.Create;
  try
    Result.O['locator'].S['file']   := lRecord._File.FileName;
    Result.O['locator'].S['formId'] := lRecord.LoadOrderFormID.ToString(False);
    Result.O['locator'].S['path']   := xeAutomationElementLocatorPath(lElement);
    xeAutomationWriteElementSummary(
      Result.O['object'], lElement, xeAutomationElementLocatorPath(lElement));

    Result.O['predicates'].B['isEditable']      := lElement.IsEditable;
    Result.O['predicates'].B['isRemovable']     := lElement.IsRemovable;
    Result.O['predicates'].B['isClearable']     := lElement.IsClearable;
    Result.O['predicates'].B['canMoveUp']       := lElement.CanMoveUp;
    Result.O['predicates'].B['canMoveDown']     := lElement.CanMoveDown;
    Result.O['predicates'].B['canChangeMember'] := lElement.CanChangeMember;

    lWritableTargetFile := False;
    try
      xeAutomationRequireWritableTargetFile(lElement._File);
      lWritableTargetFile := True;
    except
      // Capability probes must stay read-only on protected files; policy denials
      // simply collapse operation booleans to False instead of failing discovery.
    end;

    lCanAssign := lWritableTargetFile and
      xeAutomationElementCanAssignAt(lElement, lSourceElement, lTargetIndex);

    Result.O['operations'].B['setValue']       := lWritableTargetFile and lElement.IsEditable and Assigned(lElement.ValueDef);
    Result.O['operations'].B['setNativeValue'] := lWritableTargetFile and lElement.IsEditable and Assigned(lElement.ValueDef);
    Result.O['operations'].B['setToDefault']   := lWritableTargetFile and xeAutomationElementCanSetToDefault(lElement);
    Result.O['operations'].B['clear']          := lWritableTargetFile and lElement.IsClearable;
    Result.O['operations'].B['moveUp']         := lWritableTargetFile and lElement.CanMoveUp;
    Result.O['operations'].B['moveDown']       := lWritableTargetFile and lElement.CanMoveDown;
    Result.O['operations'].B['nextMember']     := lWritableTargetFile and lElement.CanChangeMember;
    Result.O['operations'].B['previousMember'] := lWritableTargetFile and lElement.CanChangeMember;
    Result.O['operations'].B['addChild']       := lWritableTargetFile and
      (not (esNotSuitableToAddTo in lElement.ElementStates)) and
      lElement.CanAssign(lTargetIndex, nil, True);
    Result.O['operations'].B['copyChildTo']    := lWritableTargetFile and
      (not (esNotSuitableToAddTo in lElement.ElementStates)) and
      lElement.CanAssign(lTargetIndex, lSourceElement, True);

    Result.O['assign'].S['targetIndex']               := lTargetIndexLabel;
    Result.O['assign'].B['sourceProvided']            := lHasSource;
    Result.O['assign'].B['canAssign']                 := lCanAssign;
    lTemplates := lElement.GetAssignTemplates(lTargetIndex);
    Result.O['assign'].I['templateCount']             := Length(lTemplates);
    Result.O['assign'].B['requiresTemplateSelection'] := Length(lTemplates) > 1;
    xeAutomationElementsWriteTemplateList(Result.O['assign'].A['templates'], lTemplates);
  except
    Result.Free;
    raise;
  end;
end;

function xeAutomationElementsAssignTemplates(const AArgs: TJsonObject): TJsonObject;
var
  lLocator: TxeAutomationLocator;
  lRecord: IwbMainRecord;
  lElement: IwbElement;
  lTargetIndex: Integer;
  lTargetIndexLabel: string;
  lTemplates: TwbTemplateElements;
begin
  // Native template discovery is read-only and intentionally separate from
  // source-sensitive CanAssign, which belongs to elements.edit_capabilities.
  lLocator := xeAutomationParseLocator(AArgs, True, True);
  lElement := xeAutomationRequireElement(lLocator, lRecord);

  lTargetIndexLabel := xeAutomationElementsResolveTargetIndexArg(AArgs, lTargetIndex);
  lTemplates := lElement.GetAssignTemplates(lTargetIndex);

  Result := TJsonObject.Create;
  try
    Result.O['locator'].S['file']   := lRecord._File.FileName;
    Result.O['locator'].S['formId'] := lRecord.LoadOrderFormID.ToString(False);
    Result.O['locator'].S['path']   := xeAutomationElementLocatorPath(lElement);
    Result.S['targetIndex'] := lTargetIndexLabel;
    Result.I['count']       := Length(lTemplates);
    xeAutomationElementsWriteTemplateList(Result.A['templates'], lTemplates);
  except
    Result.Free;
    raise;
  end;
end;

function xeAutomationElementsAddChildBuildAvailableTemplatesDetails(
  const ATemplates: TwbTemplateElements): TJsonObject;
begin
  Result := TJsonObject.Create;
  xeAutomationElementsWriteTemplateList(Result.A['availableTemplates'], ATemplates);
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
        if Assigned(lMaster) and (lMaster.LoadOrder >= ATargetFile.LoadOrder) then
          raise xeAutomationInvalidTarget(Format(
            'Automation required master "%s" can not be added to "%s" because it does not load before the target',
            [lMaster.FileName, ATargetFile.FileName]
          ));
        try
          ATargetFile.AddMasterIfMissing(lMaster.FileName, True, True);
        except
          on E: ExeAutomationError do
            raise;
          on E: Exception do
            raise xeAutomationInvalidTarget(Format(
              'Automation required masters could not be added to "%s": %s',
              [ATargetFile.FileName, E.Message]
            ));
        end;
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
  lSortableContainer: IwbSortableContainer;
begin
  // Mirror GUI predicate at xEdit/xeMainForm.pas:15339-15348:
  //   * targetIndex within the writable range [0, High(Integer)) — wbAssignAdd is High(Integer)
  //   * Supports(targetElement, IwbContainerElementRef, ...)
  //   * View-state vnfIsAligned, which we approximate by "container is NOT content-sorted"
  //     because vnfIsAligned cannot be read outside the GUI tree.
  // Conservative on miss: report sortOrderApplied:false rather than silently fire on
  // a container where SortBySortOrder is a no-op or misleading.
  APlacement.B['sortOrderApplied'] := False;
  if not Assigned(ANewElement) then
    Exit;
  if (ATargetIndex < 0) or (ATargetIndex >= High(Integer)) then
    Exit;
  if not Supports(ANewElement.Container, IwbContainerElementRef, lContainer) then
    Exit;

  // IwbContainerElementRef does not expose Sorted directly; IwbSortableContainer
  // is the reachable interface that reports content-sorted containers.
  if not Supports(lContainer, IwbSortableContainer, lSortableContainer) then
    Exit;
  if lSortableContainer.Sorted then
    Exit;

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

  // Build the masters report before Assign so addRequiredMasters:false fails
  // before any structural mutation. On failure the surrounding except clause
  // frees the report before the raise propagates, so callers never see a
  // partial masters block on errors.
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

type
  TxeAutomationElementMoveOrMemberOp = (emoMoveUp, emoMoveDown, emoNextMember, emoPrevMember);

function xeAutomationElementsMoveOrMemberCore(
  const AArgs: TJsonObject; const AOp: TxeAutomationElementMoveOrMemberOp;
  const ACommandName: string): TJsonObject;
var
  lLocator: TxeAutomationLocator;
  lRecord: IwbMainRecord;
  lElement, lAfterElement: IwbElement;
  lBefore: TJsonObject;
  lBeforePath, lAfterPath: string;
  lDeniedReason: string;
begin
  if not xeAutomationMutationPolicyConsentSatisfied(lDeniedReason) then begin
    Result := xeAutomationErrorsBuildConsentRequired(
      ACommandName, 'elements-mutation', lDeniedReason);
    Exit;
  end;

  lLocator := xeAutomationParseLocator(AArgs, True, True);
  lElement := xeAutomationRequireOwnedElement(lLocator, lRecord);

  case AOp of
    emoMoveUp:     xeAutomationRequireMoveUpElementTarget(lElement);
    emoMoveDown:   xeAutomationRequireMoveDownElementTarget(lElement);
    emoNextMember,
    emoPrevMember: xeAutomationRequireMemberChangeElementTarget(lElement);
  end;

  lBefore := xeAutomationElementsBuildBeforeAfterSnapshot(lRecord, lElement);
  lBeforePath := xeAutomationElementLocatorPath(lElement);
  try
    case AOp of
      emoMoveUp:     begin lElement.MoveUp;     lAfterElement := lElement; end;
      emoMoveDown:   begin lElement.MoveDown;   lAfterElement := lElement; end;
      emoNextMember:     lAfterElement := lElement.NextMember;
      emoPrevMember:     lAfterElement := lElement.PreviousMember;
    end;
    if not Assigned(lAfterElement) then
      lAfterElement := lElement;

    lAfterPath := xeAutomationElementLocatorPath(lAfterElement);

    Result := xeAutomationNewMutationResult(
      lBeforePath <> lAfterPath,
      lRecord._File.Modified,
      lRecord._File.FileName,
      lRecord.LoadOrderFormID.ToString(False),
      lAfterPath
    );
    Result.O['file']        := xeAutomationNewFileSummary(lRecord._File);
    // The original path can drift after native move/member operations, so the
    // post-mutation top-level locator is the caller's authoritative continuation point.
    Result.B['pathChanged'] := lBeforePath <> lAfterPath;
    Result.O['before'].Assign(lBefore);
    Result.O['after']       := xeAutomationElementsBuildBeforeAfterSnapshot(lRecord, lAfterElement);
  finally
    lBefore.Free;
  end;
end;

function xeAutomationElementsMoveUp(const AArgs: TJsonObject): TJsonObject;
begin
  Result := xeAutomationElementsMoveOrMemberCore(AArgs, emoMoveUp, 'elements.move_up');
end;

function xeAutomationElementsMoveDown(const AArgs: TJsonObject): TJsonObject;
begin
  Result := xeAutomationElementsMoveOrMemberCore(AArgs, emoMoveDown, 'elements.move_down');
end;

function xeAutomationElementsNextMember(const AArgs: TJsonObject): TJsonObject;
begin
  Result := xeAutomationElementsMoveOrMemberCore(AArgs, emoNextMember, 'elements.next_member');
end;

function xeAutomationElementsPreviousMember(const AArgs: TJsonObject): TJsonObject;
begin
  Result := xeAutomationElementsMoveOrMemberCore(AArgs, emoPrevMember, 'elements.previous_member');
end;

procedure xeAutomationRegisterElementsCommands;
begin
  xeAutomationRegisterCommand('elements.get', xeAutomationElementsGet);
  xeAutomationRegisterCommand('elements.children', xeAutomationElementsChildren);
  xeAutomationRegisterCommand('elements.conflict_status', xeAutomationElementsConflictStatus);
  xeAutomationRegisterCommand('elements.required_masters', xeAutomationElementsRequiredMasters);
  xeAutomationRegisterCommand('elements.edit_capabilities', xeAutomationElementsEditCapabilities);
  xeAutomationRegisterCommand('elements.assign_templates', xeAutomationElementsAssignTemplates);
  xeAutomationRegisterCommand('elements.set_value', xeAutomationElementsSetValue);
  xeAutomationRegisterCommand('elements.set_to_default', xeAutomationElementsSetToDefault);
  xeAutomationRegisterCommand('elements.clear', xeAutomationElementsClear);
  xeAutomationRegisterCommand('elements.set_native_value', xeAutomationElementsSetNativeValue);
  xeAutomationRegisterCommand('elements.add_child', xeAutomationElementsAddChild);
  xeAutomationRegisterCommand('elements.remove_child', xeAutomationElementsRemoveChild);
  xeAutomationRegisterCommand('elements.copy_child_to', xeAutomationElementsCopyChildTo);
  xeAutomationRegisterCommand('elements.move_up', xeAutomationElementsMoveUp);
  xeAutomationRegisterCommand('elements.move_down', xeAutomationElementsMoveDown);
  xeAutomationRegisterCommand('elements.next_member', xeAutomationElementsNextMember);
  xeAutomationRegisterCommand('elements.previous_member', xeAutomationElementsPreviousMember);
end;

end.
