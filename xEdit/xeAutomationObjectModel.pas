{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeAutomationObjectModel;

interface

uses
  JsonDataObjects,
  Types,
  wbInterface,
  xeAutomationConflictSnapshot;

type
  TxeAutomationLocator = record
    FileName: string;
    FormID: string;
    Path: string;
  end;

  function xeAutomationReadStringArg(const AArgs: TJsonObject; const AName: string): string;
  function xeAutomationReadBooleanArg(const AArgs: TJsonObject; const AName: string; out AHasValue: Boolean): Boolean;
  function xeAutomationReadStringArrayArg(const AArgs: TJsonObject; const AName: string): TStringDynArray;
  function xeAutomationRequireStringArg(const AArgs: TJsonObject; const AName: string): string;
  function xeAutomationRequireRawStringArg(const AArgs: TJsonObject; const AName: string): string;
  function xeAutomationParseLocator(const AArgs: TJsonObject; const ARequireFormID, ARequirePath: Boolean): TxeAutomationLocator; overload;
  function xeAutomationParseLocator(const AArgs: TJsonObject; const ARequirePath: Boolean): TxeAutomationLocator; overload;
  function xeAutomationParseNestedLocatorArg(const AArgs: TJsonObject; const AName: string; const ARequireFormID, ARequirePath: Boolean): TxeAutomationLocator;
  function xeAutomationNewObjectResponse(const AFileName, AFormID, APath: string): TJsonObject;
  function xeAutomationNewMutationResult(const AChanged, ADirty: Boolean; const AFileName, AFormID, APath: string): TJsonObject;
  function xeAutomationAddChildrenRelation(const AResponse: TJsonObject): TJsonObject;
  procedure xeAutomationAppendParentsRelation(AOutResponse: TJsonObject; const AParents: TArray<IwbMainRecord>);
  function xeAutomationBoundedText(const AValue: string; const AMaxLength: Integer = 160): string;
  function xeAutomationElementHasChildren(const AElement: IwbElement): Boolean;
  function xeAutomationElementLocatorPath(const AElement: IwbElement): string;
  procedure xeAutomationWriteElementSummary(const ATarget: TJsonObject; const AElement: IwbElement; const ALocatorPath: string);
  procedure xeAutomationWriteConflictParticipant(const ATarget: TJsonObject; const AParticipant: TxeAutomationConflictParticipant);
  procedure xeAutomationWriteConflictBlock(const ATarget: TJsonObject; const AConflictAll: TConflictAll;
    const AConflictThis: TConflictThis; const AParticipants: TxeAutomationConflictParticipants);
  procedure xeAutomationWriteConflictChildStub(const ATarget: TJsonObject; const ARecord: IwbMainRecord;
    const AChild: TxeAutomationConflictChildSnapshot);

implementation

uses
  TypInfo,
  SysUtils,
  xeAutomationErrors;

function xeAutomationReadStringValue(const AArgs: TJsonObject; const AName, AFieldKind: string): string;
begin
  Result := '';
  if not Assigned(AArgs) or not AArgs.Contains(AName) then
    Exit;

  if AArgs.Types[AName] <> jdtString then
    raise xeAutomationInvalidRequest(Format('Automation %s "%s" must be a string', [AFieldKind, AName]));

  Result := Trim(AArgs.S[AName]);
end;

function xeAutomationReadStringArg(const AArgs: TJsonObject; const AName: string): string;
begin
  Result := xeAutomationReadStringValue(AArgs, AName, 'arg field');
end;

function xeAutomationReadBooleanArg(const AArgs: TJsonObject; const AName: string; out AHasValue: Boolean): Boolean;
begin
  AHasValue := Assigned(AArgs) and AArgs.Contains(AName);
  if not AHasValue then
    Exit(False);

  if AArgs.Types[AName] <> jdtBool then
    raise xeAutomationInvalidRequest(Format('Automation arg field "%s" must be a boolean', [AName]));

  Result := AArgs.B[AName];
end;

function xeAutomationReadStringArrayArg(const AArgs: TJsonObject; const AName: string): TStringDynArray;
var
  lValues: TJsonArray;
  i: Integer;
begin
  Result := nil;
  if not Assigned(AArgs) or not AArgs.Contains(AName) then
    Exit;

  if AArgs.Types[AName] <> jdtArray then
    raise xeAutomationInvalidRequest(Format('Automation arg field "%s" must be an array', [AName]));

  lValues := AArgs.A[AName];
  SetLength(Result, lValues.Count);
  for i := 0 to Pred(lValues.Count) do begin
    if lValues.Types[i] <> jdtString then
      raise xeAutomationInvalidRequest(Format('Automation arg "%s" entries must be strings', [AName]));

    // Filter helpers share the trimmed string contract used by the scalar readers so
    // later commands can combine single-value and list-valued args predictably.
    Result[i] := Trim(lValues.S[i]);
  end;
end;

function xeAutomationRequireStringArg(const AArgs: TJsonObject; const AName: string): string;
begin
  if not Assigned(AArgs) then
    raise xeAutomationInvalidRequest('Automation command args are required');

  Result := xeAutomationReadStringArg(AArgs, AName);
  if Result = '' then
    raise xeAutomationInvalidRequest(Format('Automation arg "%s" is required', [AName]));
end;

function xeAutomationRequireRawStringArg(const AArgs: TJsonObject; const AName: string): string;
begin
  if not Assigned(AArgs) then
    raise xeAutomationInvalidRequest('Automation command args are required');

  if not AArgs.Contains(AName) then
    raise xeAutomationInvalidRequest(Format('Automation arg "%s" is required', [AName]));

  if AArgs.Types[AName] <> jdtString then
    raise xeAutomationInvalidRequest(Format('Automation arg field "%s" must be a string', [AName]));

  // Mutation payloads must preserve caller-provided whitespace exactly, so they
  // cannot reuse the trimmed string readers used for locator and command fields.
  Result := AArgs.S[AName];
end;

procedure xeAutomationWriteLocator(const ATarget: TJsonObject; const AFileName, AFormID, APath: string);
begin
  if AFileName <> '' then
    ATarget.S['file'] := AFileName;
  if AFormID <> '' then
    ATarget.S['formId'] := AFormID;
  // Preserve the full locator shape even at the record root so callers never have
  // to infer whether a missing path means "root" or "field omitted by writer".
  ATarget.S['path'] := APath;
end;

function xeAutomationParseLocator(const AArgs: TJsonObject; const ARequireFormID, ARequirePath: Boolean): TxeAutomationLocator;
begin
  if not Assigned(AArgs) then
    raise xeAutomationInvalidRequest('Automation command args are required');

  // Keep locator validation at the request boundary so later command units can
  // share one stable malformed-input contract instead of open-coding field checks.
  Result.FileName := xeAutomationReadStringValue(AArgs, 'file', 'locator field');
  Result.FormID := xeAutomationReadStringValue(AArgs, 'formId', 'locator field');
  Result.Path := xeAutomationReadStringValue(AArgs, 'path', 'locator field');

  if Result.FileName = '' then
    raise xeAutomationInvalidRequest('Automation locator must include file');

  if ARequireFormID and (Result.FormID = '') then
    raise xeAutomationInvalidRequest('Automation locator must include formId');

  // For daemon object traversal, an empty string is a valid record-root path. The
  // contract requirement here is field presence, not non-empty content.
  if ARequirePath and not AArgs.Contains('path') then
    raise xeAutomationInvalidRequest('Automation locator must include path');
end;

function xeAutomationParseLocator(const AArgs: TJsonObject; const ARequirePath: Boolean): TxeAutomationLocator; overload;
begin
  Result := xeAutomationParseLocator(AArgs, False, ARequirePath);
end;

function xeAutomationParseNestedLocatorArg(const AArgs: TJsonObject; const AName: string;
  const ARequireFormID, ARequirePath: Boolean): TxeAutomationLocator;
begin
  if not Assigned(AArgs) then
    raise xeAutomationInvalidRequest('Automation command args are required');

  if not AArgs.Contains(AName) then
    raise xeAutomationInvalidRequest(Format('Automation arg "%s" is required', [AName]));

  if AArgs.Types[AName] <> jdtObject then
    raise xeAutomationInvalidRequest(Format('Automation arg field "%s" must be an object', [AName]));

  // Nested locator args share the same malformed-input contract as top-level
  // locators, keeping command units from drifting into one-off validation shapes.
  Result := xeAutomationParseLocator(AArgs.O[AName], ARequireFormID, ARequirePath);
end;

function xeAutomationNewObjectResponse(const AFileName, AFormID, APath: string): TJsonObject;
begin
  Result := TJsonObject.Create;
  // Reserve the object payload up front so later command units can fill fields
  // into one stable envelope shape instead of changing the response schema.
  Result.O['object'];
  xeAutomationWriteLocator(Result.O['locator'], AFileName, AFormID, APath);
  Result.O['relations'];
end;

function xeAutomationNewMutationResult(const AChanged, ADirty: Boolean; const AFileName, AFormID, APath: string): TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.B['changed'] := AChanged;
  Result.B['dirty'] := ADirty;
  xeAutomationWriteLocator(Result.O['locator'], AFileName, AFormID, APath);
end;

function xeAutomationAddChildrenRelation(const AResponse: TJsonObject): TJsonObject;
var
  lLocator: TJsonObject;
begin
  // Children stay behind an explicit relation stub so later read-only commands can
  // expose traversal affordances without eagerly embedding deep descendant payloads.
  Result := AResponse.O['relations'].O['children'];
  Result.S['command'] := 'elements.children';
  lLocator := AResponse.O['locator'];
  xeAutomationWriteLocator(
    Result.O['locator'],
    Trim(lLocator.S['file']),
    Trim(lLocator.S['formId']),
    Trim(lLocator.S['path'])
  );
end;

procedure xeAutomationWriteRecordSummary(const ATarget: TJsonObject; const ARecord: IwbMainRecord);
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

procedure xeAutomationAppendParentsRelation(AOutResponse: TJsonObject; const AParents: TArray<IwbMainRecord>);
var
  lParents: TJsonArray;
  lEntry: TJsonObject;
  lParent: IwbMainRecord;
begin
  if not Assigned(AOutResponse) then
    Exit;

  // The parents relation is opt-in at each command boundary. When requested, emit
  // an array even for top-level records so callers can distinguish "asked and empty"
  // from legacy responses where the relation was not requested.
  lParents := AOutResponse.O['relations'].A['parents'];
  for lParent in AParents do begin
    if not Assigned(lParent) then
      Continue;
    lEntry := lParents.AddObject;
    xeAutomationWriteLocator(
      lEntry.O['locator'],
      lParent._File.FileName,
      lParent.LoadOrderFormID.ToString(False),
      ''
    );
    xeAutomationWriteRecordSummary(lEntry.O['object'], lParent);
  end;
end;

function xeAutomationBoundedText(const AValue: string; const AMaxLength: Integer): string;
begin
  Result := Trim(AValue);
  if (AMaxLength > 3) and (Length(Result) > AMaxLength) then
    Result := Copy(Result, 1, AMaxLength - 3) + '...';
end;

function xeAutomationElementHasChildren(const AElement: IwbElement): Boolean;
var
  lContainer: IwbContainer;
begin
  Result := Supports(AElement, IwbContainer, lContainer) and (lContainer.ElementCount > 0);
end;

function xeAutomationElementLocatorPath(const AElement: IwbElement): string;
begin
  // IndexedPath[False] yields a record-relative path, which is stable enough for
  // round-tripping child locators without leaking file/group indexing details.
  Result := Trim(AElement.IndexedPath[False]);
end;

procedure xeAutomationWriteElementSummary(const ATarget: TJsonObject; const AElement: IwbElement; const ALocatorPath: string);
var
  lValue: string;
  lSummary: string;
  lEditValue: string;
begin
  ATarget.S['kind'] := 'element';
  ATarget.S['elementType'] := GetEnumName(TypeInfo(TwbElementType), Ord(AElement.ElementType));
  ATarget.S['name'] := xeAutomationBoundedText(AElement.Name);

  if Trim(AElement.ShortName) <> '' then
    ATarget.S['shortName'] := xeAutomationBoundedText(AElement.ShortName);
  // The object payload surfaces the same record-relative path that appears in the
  // locator so clients can copy one actionable path without translating formats.
  ATarget.S['path'] := ALocatorPath;

  lValue := xeAutomationBoundedText(AElement.Value);
  if lValue <> '' then
    ATarget.S['value'] := lValue;

  lSummary := xeAutomationBoundedText(AElement.Summary);
  if (lSummary <> '') and not SameText(lSummary, lValue) then
    ATarget.S['summary'] := lSummary;

  lEditValue := xeAutomationBoundedText(AElement.EditValue);
  if (lEditValue <> '') and not SameText(lEditValue, lValue) then
    ATarget.S['editValue'] := lEditValue;
end;

procedure xeAutomationWriteConflictParticipant(const ATarget: TJsonObject; const AParticipant: TxeAutomationConflictParticipant);
begin
  // The protocol keeps participant identity fields structurally stable on every
  // entry. Snapshot generation should already supply FileRef for each slot, but
  // the writer still emits fixed fields here as a defensive contract boundary.
  ATarget.S['file'] := '';
  ATarget.I['loadOrder'] := -1;
  ATarget.S['loadOrderFileId'] := '';
  if Assigned(AParticipant.FileRef) then begin
    ATarget.S['file'] := AParticipant.FileRef.FileName;
    ATarget.I['loadOrder'] := AParticipant.FileRef.LoadOrder;
    ATarget.S['loadOrderFileId'] := AParticipant.FileRef.LoadOrderFileID.ToString;
  end;
  ATarget.S['role'] := AParticipant.Role;
  ATarget.B['present'] := AParticipant.Present;
end;

procedure xeAutomationWriteConflictBlock(const ATarget: TJsonObject; const AConflictAll: TConflictAll;
  const AConflictThis: TConflictThis; const AParticipants: TxeAutomationConflictParticipants);
var
  lParticipants: TJsonArray;
  i: Integer;
begin
  ATarget.S['all'] := GetEnumName(TypeInfo(TConflictAll), Ord(AConflictAll));
  ATarget.S['this'] := GetEnumName(TypeInfo(TConflictThis), Ord(AConflictThis));
  lParticipants := ATarget.A['participants'];
  for i := Low(AParticipants) to High(AParticipants) do
    xeAutomationWriteConflictParticipant(lParticipants.AddObject, AParticipants[i]);
end;

function xeAutomationElementValueSummary(const AElement: IwbElement): string;
begin
  Result := xeAutomationBoundedText(AElement.Summary);
  if Result = '' then
    Result := xeAutomationBoundedText(AElement.Value);
  if Result = '' then
    Result := xeAutomationBoundedText(AElement.EditValue);
end;

procedure xeAutomationWriteConflictChildStub(const ATarget: TJsonObject; const ARecord: IwbMainRecord;
  const AChild: TxeAutomationConflictChildSnapshot);
var
  lPath: string;
begin
  lPath := xeAutomationElementLocatorPath(AChild.Element);
  ATarget.S['name'] := xeAutomationBoundedText(AChild.Element.Name);
  ATarget.S['path'] := lPath;
  ATarget.B['hasChildren'] := xeAutomationElementHasChildren(AChild.Element);
  ATarget.S['valueSummary'] := xeAutomationElementValueSummary(AChild.Element);
  // Child stubs stay shallow. When the requested file actually owns this aligned
  // child row we expose a drill-down locator; when that side is missing we omit
  // locator rather than advertising a follow-up path that cannot resolve.
  xeAutomationWriteConflictBlock(ATarget.O['conflict'], AChild.ConflictAll, AChild.ConflictThis, AChild.Participants);
  if Assigned(AChild.LocatorElement) then
    xeAutomationWriteLocator(
      ATarget.O['locator'],
      ARecord._File.FileName,
      ARecord.LoadOrderFormID.ToString(False),
      xeAutomationElementLocatorPath(AChild.LocatorElement)
    );
end;

end.
