{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeAutomationMutationPolicy;

interface

uses
  JsonDataObjects,
  wbInterface;

type
  TxeAutomationTargetFiles = array of IwbFile;

procedure xeAutomationRequireWritableTargetFile(const AFile: IwbFile);
procedure xeAutomationRequireWritableEslMutationTarget(const AFile: IwbFile);
procedure xeAutomationRequireWritableCleaningTarget(const AFile: IwbFile);
procedure xeAutomationRequireWritableRootRecordTarget(const ARecord: IwbMainRecord);
procedure xeAutomationRequireWritableElementTarget(const AElement: IwbElement);
procedure xeAutomationRequireAddableElementTarget(const AElement: IwbElement);
procedure xeAutomationRequireCopyTarget(const ATarget, ASource: IwbElement);
procedure xeAutomationRequireRemovableElementTarget(const AElement: IwbElement);

// NEW Phase 13 element-mutation gates
procedure xeAutomationRequireSetToDefaultTarget(const AElement: IwbElement);
procedure xeAutomationRequireClearableElementTarget(const AElement: IwbElement);
procedure xeAutomationRequireMoveUpElementTarget(const AElement: IwbElement);
procedure xeAutomationRequireMoveDownElementTarget(const AElement: IwbElement);
procedure xeAutomationRequireMemberChangeElementTarget(const AElement: IwbElement);
procedure xeAutomationRequireAddableElementTargetAt(
  const AElement: IwbElement; const ATargetIndex: Integer);
procedure xeAutomationRequireCopyTargetAt(
  const ATarget, ASource: IwbElement; const ATargetIndex: Integer);

// NEW Phase 13 pure boolean discovery helpers (no exceptions, for edit_capabilities)
function xeAutomationElementCanSetToDefault(const AElement: IwbElement): Boolean;
function xeAutomationElementCanAssignAt(
  const ATarget, ASource: IwbElement; const ATargetIndex: Integer): Boolean;
function xeAutomationResolveSaveTargets(const AArgs: TJsonObject): TxeAutomationTargetFiles;
function xeAutomationMutationPolicyConsentSatisfied(out ADeniedReason: string): Boolean;

implementation

uses
  SysUtils,
  wbLoadOrder,
  xeAutomationDataLookup,
  xeAutomationErrors;

procedure xeAutomationAddTargetFile(var AFiles: TxeAutomationTargetFiles; const AFile: IwbFile);
var
  i: Integer;
begin
  xeAutomationRequireWritableTargetFile(AFile);
  for i := Low(AFiles) to High(AFiles) do
    if SameText(AFiles[i].FileName, AFile.FileName) then
      Exit;

  SetLength(AFiles, Succ(Length(AFiles)));
  AFiles[High(AFiles)] := AFile;
end;

function xeAutomationMutationPolicyConsentSatisfied(out ADeniedReason: string): Boolean;
begin
  if wbIKnowWhatImDoing then begin
    Result := True;
    ADeniedReason := '';
  end else begin
    Result := False;
    ADeniedReason := 'iknowwhatimdoing-required';
  end;
end;

function xeAutomationResolveSaveTargets(const AArgs: TJsonObject): TxeAutomationTargetFiles;
var
  lAll: Boolean;
  lModules: TwbModuleInfos;
  lFiles: TJsonArray;
  lFile: IwbFile;
  lName: string;
  i: Integer;
begin
  SetLength(Result, 0);

  if not Assigned(AArgs) then
    raise xeAutomationInvalidRequest('Automation command args are required');

  if AArgs.Contains('all') = AArgs.Contains('files') then
    raise xeAutomationInvalidRequest('Automation save args must include exactly one of "all" or "files"');

  if AArgs.Contains('all') then begin
    if AArgs.Types['all'] <> jdtBool then
      raise xeAutomationInvalidRequest('Automation arg field "all" must be a boolean');

    lAll := AArgs.B['all'];
    if not lAll then
      raise xeAutomationInvalidRequest('Automation arg "all" must be true');

    // Save remains the first persistence boundary. Earlier mutation commands stop in
    // daemon memory on purpose, so "save all" only walks the current dirty session.
    lModules := wbModulesByLoadOrder;
    for i := Low(lModules) to High(lModules) do begin
      lFile := xeAutomationTryPluginFileFromModule(lModules[i]);
      if Assigned(lFile) and lFile.Modified then
        xeAutomationAddTargetFile(Result, lFile);
    end;
    Exit;
  end;

  if AArgs.Types['files'] <> jdtArray then
    raise xeAutomationInvalidRequest('Automation arg field "files" must be an array');

  lFiles := AArgs.A['files'];
  if lFiles.Count = 0 then
    raise xeAutomationInvalidRequest('Automation arg "files" must include at least one file name');

  for i := 0 to Pred(lFiles.Count) do begin
    if lFiles.Types[i] <> jdtString then
      raise xeAutomationInvalidRequest('Automation arg "files" entries must be strings');

    lName := Trim(lFiles.S[i]);
    if lName = '' then
      raise xeAutomationInvalidRequest('Automation arg "files" entries must be non-empty strings');

    xeAutomationAddTargetFile(Result, xeAutomationRequirePluginFile(lName));
  end;
end;

function xeAutomationProtectedTargetMessage(const AFile: IwbFile): string;
var
  lModule: PwbModuleInfo;
begin
  Result := '';
  if not Assigned(AFile) then
    Exit('Automation mutation target is required');

  if AFile.IsNotPlugin then
    Exit(Format('Automation mutation target is not a plugin: %s', [AFile.FileName]));

  // Keep write-target policy in one unit so future mutation commands can reuse the
  // same guardrail instead of open-coding official/master/hardcoded checks.
  lModule := PwbModuleInfo(AFile.ModuleInfo);
  if Assigned(lModule) and (mfIsHardcoded in lModule^.miFlags) then
    Exit(Format('Automation mutation target is a hardcoded module: %s', [AFile.FileName]));

  if fsIsHardcoded in AFile.FileStates then
    Exit(Format('Automation mutation target is a hardcoded file: %s', [AFile.FileName]));

  if fsIsGameMaster in AFile.FileStates then
    Exit(Format('Automation mutation target is the game master: %s', [AFile.FileName]));

  if fsIsOfficial in AFile.FileStates then
    Exit(Format('Automation mutation target is an official master: %s', [AFile.FileName]));
end;

procedure xeAutomationRequireWritableTargetFile(const AFile: IwbFile);
var
  lMessage: string;
begin
  // Mutation commands stay in-memory until session.save so persistence remains an
  // explicit, reviewable step instead of a side effect hidden behind edits.
  if not Assigned(AFile) then
    raise xeAutomationInvalidTarget('Automation mutation target is required');

  if not wbEditAllowed then
    raise xeAutomationReadOnlyTarget('Automation mutation requires edit mode');

  lMessage := xeAutomationProtectedTargetMessage(AFile);
  if lMessage <> '' then
    raise xeAutomationMutationNotAllowed(lMessage);

  if not AFile.IsEditable then
    raise xeAutomationReadOnlyTarget(
      Format('Automation mutation target is read-only: %s', [AFile.FileName])
    );
end;

procedure xeAutomationRequireWritableEslMutationTarget(const AFile: IwbFile);
begin
  // ESL/compact jobs share the normal write guard, then add the light-plugin mode
  // gate here so unsupported games fail before any FormID/header state can change.
  xeAutomationRequireWritableTargetFile(AFile);
  if not wbIsLightSupported then
    raise xeAutomationNewError(xeAutomationErrorUnsupportedGameMode, 'Current game mode does not support light plugins');
end;

procedure xeAutomationRequireWritableCleaningTarget(const AFile: IwbFile);
begin
  // Cleaning jobs remove records or rewrite headers in memory only, but they can
  // still destroy user data if pointed at protected/read-only files; keep their
  // apply-mode gate explicit and shared with save-target policy.
  xeAutomationRequireWritableTargetFile(AFile);
end;

procedure xeAutomationRequireWritableRootRecordTarget(const ARecord: IwbMainRecord);
begin
  if not Assigned(ARecord) then
    raise xeAutomationInvalidTarget('Automation mutation target record is required');

  xeAutomationRequireWritableTargetFile(ARecord._File);

  // Root-record mutations have a second native writability gate: an editable file can
  // still contain an individual override that xEdit will not let automation replace.
  if not ARecord.IsEditable then
    raise xeAutomationReadOnlyTarget('Automation mutation target record is not editable');
end;

procedure xeAutomationRequireWritableElementTarget(const AElement: IwbElement);
begin
  if not Assigned(AElement) then
    raise xeAutomationInvalidTarget('Automation mutation target is required');

  xeAutomationRequireWritableTargetFile(AElement._File);

  // EditValue is the same leaf-value seam the GUI uses; containers and record roots
  // need dedicated structural commands instead of being coerced through value edits.
  if not Assigned(AElement.ValueDef) then
    raise xeAutomationInvalidTarget('Automation mutation target must be a value-bearing element');

  if not AElement.IsEditable then
    raise xeAutomationReadOnlyTarget('Automation mutation target is not editable');
end;

procedure xeAutomationRequireAddableElementTarget(const AElement: IwbElement);
begin
  if not Assigned(AElement) then
    raise xeAutomationInvalidTarget('Automation mutation target is required');

  xeAutomationRequireWritableTargetFile(AElement._File);

  // Whether a container can grow is definition-driven in xEdit, so automation must
  // defer to the same schema-bound Add predicates the GUI uses instead of guessing.
  if (esNotSuitableToAddTo in AElement.ElementStates) or not AElement.CanAssign(wbAssignAdd, nil, True) then
    raise xeAutomationMutationNotAllowed('Automation mutation target cannot accept a child');
end;

procedure xeAutomationRequireCopyTarget(const ATarget, ASource: IwbElement);
begin
  if not Assigned(ATarget) then
    raise xeAutomationInvalidTarget('Automation mutation target is required');

  if not Assigned(ASource) then
    raise xeAutomationInvalidTarget('Automation mutation source is required');

  xeAutomationRequireWritableTargetFile(ATarget._File);

  // Copy reuses the same schema-bound container rules as add-child, but the
  // admissibility check must also account for the concrete source element.
  if (esNotSuitableToAddTo in ATarget.ElementStates) or not ATarget.CanAssign(wbAssignAdd, ASource, True) then
    raise xeAutomationMutationNotAllowed('Automation mutation target cannot accept the addressed source child');
end;

procedure xeAutomationRequireRemovableElementTarget(const AElement: IwbElement);
begin
  if not Assigned(AElement) then
    raise xeAutomationInvalidTarget('Automation mutation target is required');

  xeAutomationRequireWritableTargetFile(AElement._File);

  // Removability is also schema-bound. Some visible elements are structural or
  // required, so the automation path must honor xEdit''s own removability check.
  if not AElement.IsRemovable then
    raise xeAutomationMutationNotAllowed('Automation mutation target cannot remove the addressed child');
end;

procedure xeAutomationRequireSetToDefaultTarget(const AElement: IwbElement);
begin
  if not Assigned(AElement) then
    raise xeAutomationInvalidTarget('Automation mutation target is required');

  xeAutomationRequireWritableTargetFile(AElement._File);

  // SetToDefault availability mirrors the GUI rule at xEdit/xeMainForm.pas:16015-16016.
  // Both must remain in sync; if GUI behavior shifts, update here.
  if not xeAutomationElementCanSetToDefault(AElement) then
    raise xeAutomationMutationNotAllowed(
      'Automation mutation target cannot be reset to default');
end;

procedure xeAutomationRequireClearableElementTarget(const AElement: IwbElement);
begin
  if not Assigned(AElement) then
    raise xeAutomationInvalidTarget('Automation mutation target is required');

  xeAutomationRequireWritableTargetFile(AElement._File);

  // Clear admissibility is definition-driven (variable-length, all children removable).
  if not AElement.IsClearable then
    raise xeAutomationMutationNotAllowed(
      'Automation mutation target is not clearable');
end;

procedure xeAutomationRequireMoveUpElementTarget(const AElement: IwbElement);
begin
  if not Assigned(AElement) then
    raise xeAutomationInvalidTarget('Automation mutation target is required');

  xeAutomationRequireWritableTargetFile(AElement._File);

  // CanMoveUp encodes "has a previous sibling in a reorderable container."
  if not AElement.CanMoveUp then
    raise xeAutomationMutationNotAllowed(
      'Automation mutation target cannot move up');
end;

procedure xeAutomationRequireMoveDownElementTarget(const AElement: IwbElement);
begin
  if not Assigned(AElement) then
    raise xeAutomationInvalidTarget('Automation mutation target is required');

  xeAutomationRequireWritableTargetFile(AElement._File);

  if not AElement.CanMoveDown then
    raise xeAutomationMutationNotAllowed(
      'Automation mutation target cannot move down');
end;

procedure xeAutomationRequireMemberChangeElementTarget(const AElement: IwbElement);
begin
  if not Assigned(AElement) then
    raise xeAutomationInvalidTarget('Automation mutation target is required');

  xeAutomationRequireWritableTargetFile(AElement._File);

  // Member change replaces the element in its slot; CanChangeMember encodes union shape.
  if not AElement.CanChangeMember then
    raise xeAutomationMutationNotAllowed(
      'Automation mutation target cannot change member');
end;

procedure xeAutomationRequireAddableElementTargetAt(
  const AElement: IwbElement; const ATargetIndex: Integer);
begin
  if not Assigned(AElement) then
    raise xeAutomationInvalidTarget('Automation mutation target is required');

  xeAutomationRequireWritableTargetFile(AElement._File);

  // Schema-bound add admissibility, parametrized over placement index. Defers to native
  // CanAssign so multi-template containers stay consistent with the GUI Add menu.
  if (esNotSuitableToAddTo in AElement.ElementStates)
    or not AElement.CanAssign(ATargetIndex, nil, True) then
    raise xeAutomationMutationNotAllowed(
      'Automation mutation target cannot accept a child at the requested index');
end;

procedure xeAutomationRequireCopyTargetAt(
  const ATarget, ASource: IwbElement; const ATargetIndex: Integer);
begin
  if not Assigned(ATarget) then
    raise xeAutomationInvalidTarget('Automation mutation target is required');

  if not Assigned(ASource) then
    raise xeAutomationInvalidTarget('Automation mutation source is required');

  xeAutomationRequireWritableTargetFile(ATarget._File);

  // Copy admissibility considers both placement index and concrete source. Defers to
  // CanAssign with source so the schema decides, not the CLI.
  if (esNotSuitableToAddTo in ATarget.ElementStates)
    or not ATarget.CanAssign(ATargetIndex, ASource, True) then
    raise xeAutomationMutationNotAllowed(
      'Automation mutation target cannot accept the addressed source child at the requested index');
end;

function xeAutomationElementCanSetToDefault(const AElement: IwbElement): Boolean;
var
  lValueDef: IwbValueDef;
begin
  // Mirror of GUI predicate at xEdit/xeMainForm.pas:16015-16016. SetToDefault is meaningful
  // when the element has a definition-driven default. The GUI gates the menu item by
  // checking IsEditable plus the presence of a ValueDef or container shape. Replicate that.
  Result := False;
  if not Assigned(AElement) then
    Exit;

  if not AElement.IsEditable then
    Exit;

  // Allow on value-bearing leaves (have a ValueDef with a default) AND on optional
  // structural containers. Native SetToDefault is a no-op when no default exists, so
  // erring on the side of "yes if writable + has shape" is consistent with GUI behavior.
  lValueDef := AElement.ValueDef;
  if Assigned(lValueDef) then begin
    Result := True;
    Exit;
  end;

  // Containers: native SetToDefault resets the substructure where defaults are declared.
  if Supports(AElement, IwbContainer) then
    Result := True;
end;

function xeAutomationElementCanAssignAt(
  const ATarget, ASource: IwbElement; const ATargetIndex: Integer): Boolean;
begin
  // Pure boolean variant for elements.edit_capabilities — reports rather than raises.
  Result := False;
  if not Assigned(ATarget) then
    Exit;

  if esNotSuitableToAddTo in ATarget.ElementStates then
    Exit;

  Result := ATarget.CanAssign(ATargetIndex, ASource, True);
end;

end.
