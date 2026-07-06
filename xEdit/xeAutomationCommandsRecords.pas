{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeAutomationCommandsRecords;

interface

uses
  JsonDataObjects,
  wbInterface,
  xeAutomationConflictSnapshot,
  xeAutomationDataLookup,
  xeAutomationObjectModel;

procedure xeAutomationRegisterRecordsCommands;

implementation

uses
  Classes,
  SysUtils,
  wbImplementation,
  xeAutomationErrors,
  xeAutomationMutationPolicy,
  xeAutomationRegistry;

const
  xeAutomationRecordsListLimit = 100;

type
  TxeAutomationCreateParentSpec = record
    HasParent: Boolean;
    FileName: string;
    FormId: Cardinal;
    HasSubGroup: Boolean;
    SubGroup: string;
    HasCoords: Boolean;
    CoordX: SmallInt;
    CoordY: SmallInt;
  end;

function xeAutomationCompareFileLoadOrder(AList: TStringList; AIndex1, AIndex2: Integer): Integer;
var
  lFile1: IwbFile;
  lFile2: IwbFile;
begin
  if AIndex1 = AIndex2 then
    Exit(0);

  lFile1 := IwbFile(Pointer(AList.Objects[AIndex1]));
  lFile2 := IwbFile(Pointer(AList.Objects[AIndex2]));
  if Assigned(lFile1) and Assigned(lFile2) then begin
    Result := lFile1.LoadOrder - lFile2.LoadOrder;
    if Result <> 0 then
      Exit;
  end else if Assigned(lFile1) then
    Exit(-1)
  else if Assigned(lFile2) then
    Exit(1);

  Result := AnsiCompareText(AList[AIndex1], AList[AIndex2]);
end;

function xeAutomationNewMasterReport: TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.A['added'];
  Result.A['alreadyPresent'];
  Result.A['skipped'];
end;

procedure xeAutomationCaptureFileMasters(const AFile: IwbFile; const AMasters: TStrings);
var
  i: Integer;
begin
  AMasters.Clear;
  for i := 0 to Pred(AFile.MasterCount[True]) do
    AMasters.Add(AFile.Masters[i, True].FileName);
end;

function xeAutomationMasterAlreadyPresent(const AMasters: TStrings; const AFileName: string): Boolean;
begin
  Result := AMasters.IndexOf(AFileName) >= 0;
end;

function xeAutomationCollectCopyRequiredMasters(const ASourceRecord: IwbMainRecord; const AAsNew,
  ADeepCopy: Boolean): TStringList;
var
  lMasters: TwbFilesSet;
  lFile: IwbFile;
  lChildGroup: IwbGroupRecord;
begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;
  try
    lMasters := TwbFilesSet.Create;
    try
      // Required-master collection is delegated to xEdit's native walker so copy_into
      // follows the same dependency rules as GUI copy operations for override/new modes.
      ASourceRecord.ReportRequiredMasters(lMasters, AAsNew, True, True);
      // Deep-copying a record with a child group uses the GUI's child-group copy seam,
      // so master preflight must include child-only dependencies before copy/add checks.
      if ADeepCopy and Supports(ASourceRecord.ChildGroup, IwbGroupRecord, lChildGroup) then
        lChildGroup.ReportRequiredMasters(lMasters, AAsNew);
      for lFile in lMasters do
        Result.AddObject(lFile.FileName, Pointer(lFile));
    finally
      lMasters.Free;
    end;
    Result.Sorted := False;
    Result.CustomSort(xeAutomationCompareFileLoadOrder);
  except
    Result.Free;
    raise;
  end;
end;

function xeAutomationApplyCopyRequiredMasters(const ATargetFile: IwbFile; const ARequested: TStrings;
  const AAddRequiredMasters: Boolean): TJsonObject;
var
  lBefore: TStringList;
  lAfter: TStringList;
  lToAdd: TStringList;
  lMasterFile: IwbFile;
  i: Integer;
begin
  Result := xeAutomationNewMasterReport;
  try
    lBefore := nil;
    lAfter := nil;
    lToAdd := nil;
    try
      lBefore := TStringList.Create;
      lAfter := TStringList.Create;
      lToAdd := TStringList.Create;
      lBefore.Sorted := True;
      lBefore.Duplicates := dupIgnore;
      lAfter.Sorted := True;
      lAfter.Duplicates := dupIgnore;
      lToAdd.Sorted := True;
      lToAdd.Duplicates := dupIgnore;

      xeAutomationCaptureFileMasters(ATargetFile, lBefore);

      for i := 0 to Pred(ARequested.Count) do begin
        lMasterFile := IwbFile(Pointer(ARequested.Objects[i]));
        if SameText(ARequested[i], ATargetFile.FileName) then begin
          Result.A['skipped'].Add(ARequested[i]);
          Continue;
        end;

        if xeAutomationMasterAlreadyPresent(lBefore, ARequested[i]) then begin
          Result.A['alreadyPresent'].Add(ARequested[i]);
          Continue;
        end;

        if not AAddRequiredMasters then
          lToAdd.AddObject(ARequested[i], ARequested.Objects[i])
        else begin
          if Assigned(lMasterFile) and (lMasterFile.LoadOrder >= ATargetFile.LoadOrder) then
            raise xeAutomationInvalidTarget(Format(
              'Automation required master "%s" can not be added to "%s" because it does not load before the target',
              [ARequested[i], ATargetFile.FileName]
            ));
          lToAdd.AddObject(ARequested[i], ARequested.Objects[i]);
        end;
      end;

      if (lToAdd.Count > 0) and not AAddRequiredMasters then
        raise xeAutomationMutationNotAllowed(
          'Automation copy requires missing masters and addRequiredMasters is false'
        );

      if lToAdd.Count > 0 then begin
        lToAdd.Sorted := False;
        lToAdd.CustomSort(xeAutomationCompareFileLoadOrder);
        try
          ATargetFile.AddMastersIfMissing(lToAdd, True, True);
        except
          on E: ExeAutomationError do
            raise;
          on E: Exception do
            raise xeAutomationInvalidTarget(Format(
              'Automation required masters could not be added to "%s": %s',
              [ATargetFile.FileName, E.Message]
            ));
        end;
      end;

      xeAutomationCaptureFileMasters(ATargetFile, lAfter);
      for i := 0 to Pred(lToAdd.Count) do
        if not xeAutomationMasterAlreadyPresent(lBefore, lToAdd[i]) and xeAutomationMasterAlreadyPresent(lAfter, lToAdd[i]) then
          Result.A['added'].Add(lToAdd[i])
        else if xeAutomationMasterAlreadyPresent(lAfter, lToAdd[i]) then
          Result.A['alreadyPresent'].Add(lToAdd[i])
        else
          Result.A['skipped'].Add(lToAdd[i]);
    finally
      lToAdd.Free;
      lAfter.Free;
      lBefore.Free;
    end;
  except
    Result.Free;
    raise;
  end;
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

function xeAutomationRequireCreatableRecordSignature(const AArgs: TJsonObject): string;
begin
  Result := UpperCase(xeAutomationRequireStringArg(AArgs, 'signature'));
end;

function xeAutomationInvalidCreateParentRequest(const AMessage, AInvalidField: string): ExeAutomationError;
var
  lDetails: TJsonObject;
begin
  lDetails := TJsonObject.Create;
  try
    if AInvalidField <> '' then
      lDetails.S['invalidField'] := AInvalidField;
    Result := xeAutomationNewError(xeAutomationErrorInvalidRequest, AMessage, lDetails);
  finally
    lDetails.Free;
  end;
end;

function xeAutomationUnsupportedCreateParentRequest(const AParentSignature, AMessage: string): ExeAutomationError;
var
  lDetails: TJsonObject;
begin
  lDetails := TJsonObject.Create;
  try
    lDetails.S['unsupportedParent'] := AParentSignature;
    Result := xeAutomationNewError(xeAutomationErrorInvalidRequest, AMessage, lDetails);
  finally
    lDetails.Free;
  end;
end;

function xeAutomationReadCreateParentSpec(const AArgs: TJsonObject; out AParentSpec: TxeAutomationCreateParentSpec): Boolean;
var
  lParent: TJsonObject;
  lCoords: TJsonArray;
  lFormID: string;
  lCoordValue: Int64;
  i: Integer;
begin
  AParentSpec.HasParent := False;
  AParentSpec.FileName := '';
  AParentSpec.FormId := 0;
  AParentSpec.HasSubGroup := False;
  AParentSpec.SubGroup := '';
  AParentSpec.HasCoords := False;
  AParentSpec.CoordX := 0;
  AParentSpec.CoordY := 0;

  Result := xeAutomationArgPresent(AArgs, 'parent');
  if not Result then
    Exit;

  if AArgs.Types['parent'] <> jdtObject then
    raise xeAutomationInvalidCreateParentRequest('Automation records.create parent must be an object', 'parent');

  lParent := AArgs.O['parent'];
  AParentSpec.HasParent := True;
  AParentSpec.FileName := xeAutomationRequireStringArg(lParent, 'file');
  lFormID := xeAutomationRequireStringArg(lParent, 'formId');
  try
    AParentSpec.FormId := xeAutomationParseFormIdHex(lFormID);
  except
    on E: ExeAutomationError do
      raise xeAutomationInvalidCreateParentRequest(E.Message, 'parent.formId');
  end;
  AParentSpec.HasSubGroup := xeAutomationArgPresent(lParent, 'subGroup');
  if AParentSpec.HasSubGroup then begin
    AParentSpec.SubGroup := xeAutomationReadStringArg(lParent, 'subGroup');
    if AParentSpec.SubGroup = '' then
      raise xeAutomationInvalidCreateParentRequest('Automation records.create parent.subGroup must be a non-empty string', 'parent.subGroup');
  end;
  AParentSpec.HasCoords := xeAutomationArgPresent(lParent, 'coords');
  if AParentSpec.HasCoords then begin
    if lParent.Types['coords'] <> jdtArray then
      raise xeAutomationInvalidCreateParentRequest('Automation records.create parent.coords must be a two-integer array', 'parent.coords');
    lCoords := lParent.A['coords'];
    if lCoords.Count <> 2 then
      raise xeAutomationInvalidCreateParentRequest('Automation records.create parent.coords must contain exactly two integers: [x,y]', 'parent.coords');
    for i := 0 to 1 do begin
      if not (lCoords.Types[i] in [jdtInt, jdtLong]) then
        raise xeAutomationInvalidCreateParentRequest('Automation records.create parent.coords values must be integers', 'parent.coords');
      lCoordValue := lCoords.L[i];
      if (lCoordValue < Low(SmallInt)) or (lCoordValue > High(SmallInt)) then
        raise xeAutomationInvalidCreateParentRequest('Automation records.create parent.coords values must be in signed int16 range', 'parent.coords');
      if i = 0 then
        AParentSpec.CoordX := SmallInt(lCoordValue)
      else
        AParentSpec.CoordY := SmallInt(lCoordValue);
    end;
  end;
end;

procedure xeAutomationValidateWrldCreateParentShape(
  const AParentSpec: TxeAutomationCreateParentSpec;
  const ACreateSignature: TwbSignature);
begin
  // WRLD authoring must choose a CELL-owned worldspace bucket explicitly; other
  // signatures belong under a concrete CELL parent via the Phase 15D route.
  if ACreateSignature <> 'CELL' then
    raise xeAutomationInvalidCreateParentRequest(
      'Automation records.create WRLD parent requires signature CELL; create child records under a CELL parent instead',
      'signature'
    );
  if AParentSpec.HasSubGroup and AParentSpec.HasCoords then
    raise xeAutomationInvalidCreateParentRequest(
      'Automation records.create WRLD parent accepts either parent.subGroup:"Persistent" or parent.coords, not both',
      'parent'
    );
  if not AParentSpec.HasSubGroup and not AParentSpec.HasCoords then
    raise xeAutomationInvalidCreateParentRequest(
      'Automation records.create WRLD parent requires parent.subGroup:"Persistent" or parent.coords:[x,y]',
      'parent'
    );
end;

procedure xeAutomationResolveWrldCreateParentTarget(
  const AParentSpec: TxeAutomationCreateParentSpec;
  const AParent: IwbMainRecord;
  out ATargetGroup: IwbGroupRecord;
  out AExistingRecord: IwbMainRecord;
  out ACreateName: string);
var
  lChildGroup: IwbGroupRecord;
  lGridCell: TwbGridCell;
begin
  ATargetGroup := nil;
  AExistingRecord := nil;
  ACreateName := '';

  xeAutomationValidateWrldCreateParentShape(AParentSpec, 'CELL');

  if AParentSpec.HasSubGroup then begin
    if not SameText(AParentSpec.SubGroup, 'Persistent') then
      raise xeAutomationInvalidCreateParentRequest(
        Format('Automation records.create parent.subGroup "%s" is not supported for WRLD; use "Persistent" or parent.coords:[x,y]', [AParentSpec.SubGroup]),
        'parent.subGroup'
      );

    lChildGroup := AParent.EnsureChildGroup;
    ATargetGroup := lChildGroup;
    AExistingRecord := xeAutomationFindPersistentWorldCell(lChildGroup);
    if not Assigned(AExistingRecord) then
      ACreateName := 'CELL[P]';
    Exit;
  end;

  // Native group Add accepts the same silent world-CELL parameter syntax as the
  // GUI path (CELL[x,y]); that keeps Block/Sub-Block creation inside xEdit core.
  lChildGroup := AParent.EnsureChildGroup;
  ATargetGroup := lChildGroup;
  lGridCell.x := AParentSpec.CoordX;
  lGridCell.y := AParentSpec.CoordY;
  AExistingRecord := AParent.ChildByGridCell[lGridCell];
  if not Assigned(AExistingRecord) then
    ACreateName := Format('CELL[%d,%d]', [AParentSpec.CoordX, AParentSpec.CoordY]);
end;

function xeAutomationDefaultCellChildGroupForSignature(const ACreateSignature: TwbSignature): Integer;
begin
  if (ACreateSignature = 'REFR') or
     (ACreateSignature = 'ACHR') or
     (ACreateSignature = 'PGRD') or
     (ACreateSignature = 'LAND') or
     (ACreateSignature = 'NAVM') then
    Result := 9
  else
    Result := 8;
end;

function xeAutomationCellChildGroupForSubGroup(const ASubGroup: string): Integer;
begin
  if SameText(ASubGroup, 'Persistent') then
    Exit(8);
  if SameText(ASubGroup, 'Temporary') then
    Exit(9);
  if SameText(ASubGroup, 'Visible when Distant') then
    Exit(10);

  raise xeAutomationInvalidCreateParentRequest(
    Format('Automation records.create parent.subGroup "%s" is not supported for CELL', [ASubGroup]),
    'parent.subGroup'
  );
end;

function xeAutomationResolveCreateParentTarget(
  const AParentSpec: TxeAutomationCreateParentSpec;
  const ACreateSignature: TwbSignature;
  out ATargetGroup: IwbGroupRecord;
  out AExistingRecord: IwbMainRecord;
  out ACreateName: string): Boolean;
var
  lLocator: TxeAutomationLocator;
  lParent: IwbMainRecord;
  lChildGroup: IwbGroupRecord;
  lTargetGroupType: Integer;
begin
  ATargetGroup := nil;
  AExistingRecord := nil;
  ACreateName := '';
  Result := AParentSpec.HasParent;
  if not Result then
    Exit;

  lLocator.FileName := AParentSpec.FileName;
  lLocator.FormID := IntToHex(AParentSpec.FormId, 8);
  lLocator.Path := '';
  lParent := xeAutomationRequireMainRecord(lLocator);

  // The parent object is the write-side substitute for synthetic ChildGroup paths:
  // validate the small owner set before native Add sees a malformed target GRUP.
  if lParent.Signature = 'WRLD' then begin
    xeAutomationValidateWrldCreateParentShape(AParentSpec, ACreateSignature);
    xeAutomationResolveWrldCreateParentTarget(AParentSpec, lParent, ATargetGroup, AExistingRecord, ACreateName);
    Exit;
  end;
  if (lParent.Signature <> 'CELL') and (lParent.Signature <> 'DIAL') and (lParent.Signature <> 'QUST') then
    raise xeAutomationInvalidCreateParentRequest('parent record does not own a ChildGroup', 'parent.formId');

  if lParent.Signature = 'CELL' then begin
    if AParentSpec.HasSubGroup then
      lTargetGroupType := xeAutomationCellChildGroupForSubGroup(AParentSpec.SubGroup)
    else
      lTargetGroupType := xeAutomationDefaultCellChildGroupForSignature(ACreateSignature);

    lChildGroup := lParent.EnsureChildGroup;
    ATargetGroup := lChildGroup.FindChildGroup(lTargetGroupType, lParent);
    if not Assigned(ATargetGroup) then begin
      if lTargetGroupType = xeAutomationDefaultCellChildGroupForSignature(ACreateSignature) then
        ATargetGroup := lChildGroup
      else
        raise xeAutomationInvalidTarget(Format('Automation CELL sub-group "%s" is not resolvable for parent %s', [AParentSpec.SubGroup, lParent.LoadOrderFormID.ToString(False)]));
    end;
    Exit;
  end;

  if AParentSpec.HasSubGroup then
    raise xeAutomationInvalidCreateParentRequest(
      Format('Automation records.create parent.subGroup is not supported for %s parents', [string(lParent.Signature)]),
      'parent.subGroup'
    );

  // DIAL and QUST are one-level ChildGroup owners. EnsureChildGroup mirrors native
  // editor behavior for empty parents so the following Add remains the only record
  // creation seam and xEdit still owns signature validity.
  ATargetGroup := lParent.EnsureChildGroup;
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

function xeAutomationNewRecordResponse(const ARecord: IwbMainRecord): TJsonObject;
begin
  Result := xeAutomationNewObjectResponse(
    ARecord._File.FileName,
    ARecord.LoadOrderFormID.ToString(False),
    ''
  );
  xeAutomationWriteRecordSummary(Result.O['object'], ARecord);
  // Record responses stay shallow and point traversal through elements.children so
  // callers do not accidentally trigger an unbounded recursive record dump.
  xeAutomationAddChildrenRelation(Result);
end;

function xeAutomationNewListedRecordSummary(const ARecord: IwbMainRecord): TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.O['locator'].S['file'] := ARecord._File.FileName;
  Result.O['locator'].S['formId'] := ARecord.LoadOrderFormID.ToString(False);
  Result.O['locator'].S['path'] := '';
  // List results stay intentionally shallow so the first enumeration primitive is
  // reviewable and bounded by summaries plus locators, not implicit deep traversal.
  xeAutomationWriteRecordSummary(Result.O['object'], ARecord);
end;

function xeAutomationNewListedRecordSummaryWithParents(const ARecord: IwbMainRecord;
  const AIncludeParents: Boolean): TJsonObject;
begin
  Result := xeAutomationNewListedRecordSummary(ARecord);
  if AIncludeParents then
    xeAutomationAppendParentsRelation(Result, xeAutomationCollectAncestorChain(ARecord, 16));
end;

function xeAutomationNewRecordResponseWithParents(const ARecord: IwbMainRecord;
  const AIncludeParents: Boolean): TJsonObject;
begin
  Result := xeAutomationNewRecordResponse(ARecord);
  if AIncludeParents then
    xeAutomationAppendParentsRelation(Result, xeAutomationCollectAncestorChain(ARecord, 16));
end;

procedure xeAutomationAppendChildGroupConflictSubBlock(const AResult: TJsonObject;
  const ASnapshot: TxeAutomationConflictSnapshot);
var
  lChildGroup: TJsonObject;
  lSignatures: TJsonObject;
  lHits: TJsonArray;
  lHit: TJsonObject;
  i: Integer;
begin
  if not ASnapshot.ChildGroup.Present then
    Exit;

  lChildGroup := AResult.O['childGroup'];
  lChildGroup.I['count'] := ASnapshot.ChildGroup.Count;
  lChildGroup.B['hasConflict'] := ASnapshot.ChildGroup.HasConflict;
  lChildGroup.B['conflictingHitsTruncated'] := ASnapshot.ChildGroup.ConflictingHitsTruncated;

  lSignatures := lChildGroup.O['signatures'];
  for i := Low(ASnapshot.ChildGroup.Signatures) to High(ASnapshot.ChildGroup.Signatures) do begin
    lSignatures.O[ASnapshot.ChildGroup.Signatures[i].Signature].I['total'] := ASnapshot.ChildGroup.Signatures[i].Total;
    lSignatures.O[ASnapshot.ChildGroup.Signatures[i].Signature].I['conflicting'] := ASnapshot.ChildGroup.Signatures[i].Conflicting;
  end;

  lHits := lChildGroup.A['conflictingHits'];
  for i := Low(ASnapshot.ChildGroup.ConflictingHits) to High(ASnapshot.ChildGroup.ConflictingHits) do begin
    lHit := xeAutomationNewListedRecordSummary(ASnapshot.ChildGroup.ConflictingHits[i].RecordRef);
    xeAutomationWriteConflictBlock(
      lHit.O['conflict'],
      ASnapshot.ChildGroup.ConflictingHits[i].ConflictAll,
      ASnapshot.ChildGroup.ConflictingHits[i].ConflictThis,
      nil
    );
    lHits.Add(lHit);
  end;
end;

function xeAutomationNewRecordConflictStatusResponse(const ARecord: IwbMainRecord;
  const ASnapshot: TxeAutomationConflictSnapshot): TJsonObject;
var
  lRecordObject: TJsonObject;
  lChildren: TJsonArray;
  i: Integer;
begin
  Result := TJsonObject.Create;
  lRecordObject := Result.O['record'];
  lRecordObject.O['locator'].S['file'] := ARecord._File.FileName;
  lRecordObject.O['locator'].S['formId'] := ARecord.LoadOrderFormID.ToString(False);
  lRecordObject.O['locator'].S['path'] := '';
  xeAutomationWriteRecordSummary(lRecordObject.O['object'], ARecord);

  xeAutomationWriteConflictBlock(Result.O['conflict'], ASnapshot.ConflictAll, ASnapshot.ConflictThis, ASnapshot.Participants);

  Result.O['children'].I['count'] := Length(ASnapshot.Children);
  Result.O['children'].B['truncated'] := ASnapshot.ChildrenTruncated;
  lChildren := Result.O['children'].A['items'];
  for i := Low(ASnapshot.Children) to High(ASnapshot.Children) do
    xeAutomationWriteConflictChildStub(lChildren.AddObject, ARecord, ASnapshot.Children[i]);

  // ChildGroup conflict signal is an additive read-only block; records without a
  // populated ChildGroup omit it entirely so pre-15C clients keep their old shape.
  xeAutomationAppendChildGroupConflictSubBlock(Result, ASnapshot);
end;

function xeAutomationRequireRootRecord(const AArgs: TJsonObject): IwbMainRecord;
var
  lLocator: TxeAutomationLocator;
begin
  lLocator := xeAutomationParseLocator(AArgs, True, False);

  // These relationship commands stay root-record only. Allowing child paths here
  // would silently widen the contract beyond the approved surface.
  if lLocator.Path <> '' then
    raise xeAutomationInvalidRequest('Automation locator path is not supported for this records command');

  Result := xeAutomationRequireMainRecord(lLocator);
end;

function xeAutomationRequireRootMutationRecord(const AArgs: TJsonObject): IwbMainRecord;
var
  lLocator: TxeAutomationLocator;
begin
  lLocator := xeAutomationParseLocator(AArgs, True, True);

  // Root-level record mutations are intentionally separated from element-path edits:
  // deleting or flagging a child path would cross into native container semantics that
  // are handled by dedicated element commands and different removability rules.
  if Trim(lLocator.Path) <> '' then
    raise xeAutomationInvalidRequest('Automation records mutation path must address the record root');

  // Mutation locators must name a record owned by the addressed file, not a master
  // record merely reachable through that file's load-order dependencies.
  Result := xeAutomationRequireOwnedMainRecord(lLocator);
end;

function xeAutomationNewListedRecordHitsResponse(const ASearch: TxeAutomationBoundedMainRecordSearch): TJsonObject;
var
  lHits: TJsonArray;
  i: Integer;
begin
  Result := TJsonObject.Create;
  Result.B['truncated'] := ASearch.Truncated;
  lHits := Result.A['hits'];
  for i := Low(ASearch.Hits) to High(ASearch.Hits) do
    lHits.Add(xeAutomationNewListedRecordSummary(ASearch.Hits[i]));

  Result.I['count'] := lHits.Count;
end;

function xeAutomationRecordsFindByFormID(const AArgs: TJsonObject): TJsonObject;
var
  lSearch: TxeAutomationMainRecordSearch;
  lHits: TJsonArray;
  lFileName: string;
  lIncludeParents: Boolean;
  i: Integer;
begin
  lIncludeParents := xeAutomationReadIncludeParentsArg(AArgs);
  lFileName := xeAutomationReadStringArg(AArgs, 'file');
  lSearch := xeAutomationFindMainRecordsByLoadOrderFormID(
    xeAutomationRequireStringArg(AArgs, 'formId'),
    lFileName
  );

  Result := TJsonObject.Create;
  Result.B['truncated'] := lSearch.Truncated;
  lHits := Result.A['hits'];
  for i := Low(lSearch.Hits) to High(lSearch.Hits) do
    lHits.Add(xeAutomationNewListedRecordSummaryWithParents(lSearch.Hits[i], lIncludeParents));

  Result.I['count'] := lHits.Count;

  // Keep the identity lookup response shallow: callers get concrete hits plus the
  // two canonical endpoints for the same FormID, without any recursive expansion.
  if Assigned(lSearch.MasterOrSelf) then
    Result.O['masterOrSelf'] := xeAutomationNewListedRecordSummaryWithParents(lSearch.MasterOrSelf, lIncludeParents);
  if Assigned(lSearch.WinningOverride) then
    Result.O['winningOverride'] := xeAutomationNewListedRecordSummaryWithParents(lSearch.WinningOverride, lIncludeParents);
end;

function xeAutomationRecordsFindByEditorID(const AArgs: TJsonObject): TJsonObject;
var
  lSearch: TxeAutomationBoundedMainRecordSearch;
  lHits: TJsonArray;
  lIncludeParents: Boolean;
  i: Integer;
begin
  lIncludeParents := xeAutomationReadIncludeParentsArg(AArgs);
  // Keep request-shape validation at the boundary so malformed signature inputs
  // fail as structured invalid_request responses before any record traversal starts.
  lSearch := xeAutomationFindMainRecordsByEditorID(
    xeAutomationRequireStringArg(AArgs, 'editorId'),
    xeAutomationReadStringArg(AArgs, 'signature')
  );

  Result := TJsonObject.Create;
  Result.B['truncated'] := lSearch.Truncated;
  lHits := Result.A['hits'];
  for i := Low(lSearch.Hits) to High(lSearch.Hits) do
    lHits.Add(xeAutomationNewListedRecordSummaryWithParents(lSearch.Hits[i], lIncludeParents));

  Result.I['count'] := lHits.Count;
end;

function xeAutomationRecordsApplyFilter(const AArgs: TJsonObject): TJsonObject;
var
  lSearch: TxeAutomationBoundedMainRecordSearch;
  lHits: TJsonArray;
  lOffset: Integer;
  lLimit: Integer;
  i: Integer;
begin
  // records.list remains the simple enumerator; the broader Apply Filter contract is
  // isolated here so callers opt into file-scoped glob and status matching explicitly.
  // Phase 16 (contract 0.21): request-boundary pagination is echoed back through
  // offset / limit / (optional) nextOffset so cursor-style drain is trivial for
  // wrappers and total is intentionally NOT emitted -- the underlying scan is
  // early-exit and cannot cheaply produce a full match count without breaking
  // the per-page containment guarantee that keeps context bounded.
  lOffset := xeAutomationReadOffsetArg(AArgs);
  lLimit := xeAutomationReadApplyFilterLimitArg(AArgs);
  lSearch := xeAutomationFilterMainRecords(AArgs);

  Result := TJsonObject.Create;
  Result.B['truncated'] := lSearch.Truncated;
  Result.I['offset'] := lOffset;
  Result.I['limit'] := lLimit;
  lHits := Result.A['hits'];
  for i := Low(lSearch.Hits) to High(lSearch.Hits) do
    lHits.Add(xeAutomationNewListedRecordSummary(lSearch.Hits[i]));

  Result.I['count'] := lHits.Count;
  if lSearch.Truncated then
    // nextOffset is the load-bearing cursor primitive: wrappers can re-issue the
    // same filter with offset=nextOffset until truncated is false without ever
    // materializing a total. Omitting nextOffset when not truncated keeps the
    // "no more pages" terminator unambiguous for pure-JSON clients.
    Result.I['nextOffset'] := lOffset + lHits.Count;
  if lSearch.RegexTimeouts > 0 then
    Result.I['regexTimeouts'] := lSearch.RegexTimeouts;
  if lSearch.RegexSlotsExhausted > 0 then
    Result.I['regexSlotsExhausted'] := lSearch.RegexSlotsExhausted;
end;

function xeAutomationRecordsGet(const AArgs: TJsonObject): TJsonObject;
var
  lRecord: IwbMainRecord;
begin
  lRecord := xeAutomationRequireMainRecord(xeAutomationParseLocator(AArgs, True, False));
  Result := xeAutomationNewRecordResponseWithParents(lRecord, xeAutomationReadIncludeParentsArg(AArgs));
end;

function xeAutomationRecordsBaseRecord(const AArgs: TJsonObject): TJsonObject;
var
  lRecord: IwbMainRecord;
  lBaseRecord: IwbMainRecord;
begin
  lRecord := xeAutomationRequireRootRecord(AArgs);

  Result := TJsonObject.Create;
  Result.O['record'] := xeAutomationNewListedRecordSummary(lRecord);

  if lRecord.CanHaveBaseRecord and Supports(lRecord.BaseRecord, IwbMainRecord, lBaseRecord) then
    Result.O['baseRecord'] := xeAutomationNewListedRecordSummary(lBaseRecord)
  else
    Result['baseRecord'] := nil;
end;

function xeAutomationRecordsReferences(const AArgs: TJsonObject): TJsonObject;
var
  lHasRecursive: Boolean;
  lRecursive: Boolean;
begin
  lRecursive := xeAutomationReadBooleanArg(AArgs, 'recursive', lHasRecursive);
  if not lHasRecursive then
    lRecursive := False;
  Result := xeAutomationNewListedRecordHitsResponse(
    xeAutomationCollectOutgoingReferences(
      xeAutomationRequireRootRecord(AArgs),
      xeAutomationReadSearchLimit(AArgs),
      lRecursive
    )
  );
end;

function xeAutomationRecordsReferencedBy(const AArgs: TJsonObject): TJsonObject;
begin
  Result := xeAutomationNewListedRecordHitsResponse(
    xeAutomationCollectReferencedByRecords(
      xeAutomationRequireRootRecord(AArgs),
      xeAutomationReadSearchLimit(AArgs)
    )
  );
end;

function xeAutomationRecordsConflictStatus(const AArgs: TJsonObject): TJsonObject;
var
  lRecord: IwbMainRecord;
  lSnapshot: TxeAutomationConflictSnapshot;
begin
  lRecord := xeAutomationRequireRootRecord(AArgs);
  lSnapshot := xeAutomationSnapshotRecordConflict(lRecord, xeAutomationReadSearchLimit(AArgs));
  Result := xeAutomationNewRecordConflictStatusResponse(lRecord, lSnapshot);
end;

function xeAutomationRecordsList(const AArgs: TJsonObject): TJsonObject;
var
  lFile: IwbFile;
  lRecordList: TJsonArray;
  lSignature: string;
  lTruncated: Boolean;
  lRecord: IwbMainRecord;
  i: Integer;
begin
  lFile := xeAutomationRequirePluginFile(xeAutomationRequireStringArg(AArgs, 'file'));
  lSignature := xeAutomationReadStringArg(AArgs, 'signature');

  Result := TJsonObject.Create;
  lRecordList := Result.A['records'];
  lTruncated := False;

  // Keep the first list surface bounded and shallow by streaming directly from the
  // file and stopping after a small internal cap instead of materializing matches.
  for i := 0 to Pred(lFile.RecordCount) do
    if Supports(lFile.Records[i], IwbMainRecord, lRecord) then
      if (lSignature = '') or SameText(lRecord.Signature, lSignature) then begin
        // Report truncation only when the hard cap actually clips one more matching
        // record, so bounded list callers can trust count/truncated together.
        if lRecordList.Count >= xeAutomationRecordsListLimit then begin
          lTruncated := True;
          Break;
        end;

        lRecordList.Add(xeAutomationNewListedRecordSummary(lRecord));
      end;

  Result.I['count'] := lRecordList.Count;
  Result.B['truncated'] := lTruncated;
end;

function xeAutomationRecordsCreate(const AArgs: TJsonObject): TJsonObject;
var
  lFile: IwbFile;
  lGroupElement: IwbElement;
  lNewElement: IwbElement;
  lGroup: IwbGroupRecord;
  lParentSpec: TxeAutomationCreateParentSpec;
  lParentTargetGroup: IwbGroupRecord;
  lExistingParentRecord: IwbMainRecord;
  lRecord: IwbMainRecord;
  lSignature: string;
  lCreateSignature: TwbSignature;
  lCreateName: string;
  lEditorID: string;
  lAlreadyExists: Boolean;
  lDeniedReason: string;
begin
  if not xeAutomationMutationPolicyConsentSatisfied(lDeniedReason) then begin
    Result := xeAutomationErrorsBuildConsentRequired('records.create', 'records-mutation', lDeniedReason);
    Exit;
  end;

  lFile := xeAutomationRequirePluginFile(xeAutomationRequireStringArg(AArgs, 'targetFile'));
  lSignature := xeAutomationRequireCreatableRecordSignature(AArgs);
  lCreateSignature := StrToSignature(lSignature);
  lEditorID := xeAutomationReadStringArg(AArgs, 'editorId');
  xeAutomationReadCreateParentSpec(AArgs, lParentSpec);
  xeAutomationRequireWritableTargetFile(lFile);

  try
    lAlreadyExists := False;
    if xeAutomationResolveCreateParentTarget(lParentSpec, lCreateSignature, lParentTargetGroup, lExistingParentRecord, lCreateName) then begin
      if not Assigned(lParentTargetGroup) then
        raise xeAutomationInvalidTarget(Format('Automation parent target group could not be resolved for signature %s', [lSignature]));
      if not SameText(lParentTargetGroup._File.FileName, lFile.FileName) then
        raise xeAutomationInvalidTarget(Format(
          'Automation records.create parent target must be owned by targetFile "%s"; create or copy the parent override first',
          [lFile.FileName]
        ));

      // Parent-spec creation lands in an existing ChildGroup owner chosen by the
      // caller, but still delegates signature support to the same native Add seam.
      if Assigned(lExistingParentRecord) then begin
        lNewElement := lExistingParentRecord;
        lAlreadyExists := True;
      end else begin
        if lCreateName = '' then
          lCreateName := lSignature;
        lNewElement := lParentTargetGroup.Add(lCreateName, True);
      end;
    end else begin
      // Top-level groups are a native file-structure seam. Automation deliberately
      // avoids protocol-side signature allow-lists here and lets xEdit's Add path
      // decide which signatures the active game/file model can actually create.
      lGroupElement := lFile.Add(lSignature, True);
      if not Supports(lGroupElement, IwbGroupRecord, lGroup) then
        raise xeAutomationInvalidTarget(Format('Automation record group could not be created for signature %s', [lSignature]));

      lNewElement := lGroup.Add(lSignature, True);
    end;

    if not Supports(lNewElement, IwbMainRecord, lRecord) then
      raise xeAutomationInvalidTarget(Format('Automation record could not be created for signature %s', [lSignature]));

    if lEditorID <> '' then begin
      if not lRecord.CanHaveEditorID then
        raise xeAutomationMutationNotAllowed(Format('Automation record signature %s cannot have an EditorID', [lSignature]));
      lRecord.EditorID := lEditorID;
    end;
  except
    on E: ExeAutomationError do
      raise;
    on E: Exception do
      raise xeAutomationInvalidTarget(Format('Automation record could not be created: %s', [E.Message]));
  end;

  Result := TJsonObject.Create;
  try
    Result.B['changed'] := not lAlreadyExists;
    Result.B['created'] := lRecord.IsMaster and not lAlreadyExists;
    Result.B['override'] := not lRecord.IsMaster;
    if lAlreadyExists then
      Result.B['alreadyExists'] := True;
    Result.B['dirty'] := lFile.Modified;
    Result.O['file'] := xeAutomationNewFileSummary(lFile);
    Result.O['locator'].S['file'] := lFile.FileName;
    Result.O['locator'].S['formId'] := lRecord.LoadOrderFormID.ToString(False);
    Result.O['locator'].S['path'] := '';
    xeAutomationWriteRecordSummary(Result.O['record'], lRecord);
  except
    Result.Free;
    raise;
  end;
end;

function xeAutomationRecordsDelete(const AArgs: TJsonObject): TJsonObject;
var
  lRecord: IwbMainRecord;
  lChildGroup: IwbGroupRecord;
  lFile: IwbFile;
  lRemovedRecord: TJsonObject;
  lDeniedReason: string;
begin
  if not xeAutomationMutationPolicyConsentSatisfied(lDeniedReason) then begin
    Result := xeAutomationErrorsBuildConsentRequired('records.delete', 'records-mutation', lDeniedReason);
    Exit;
  end;

  lRemovedRecord := nil;
  lRecord := xeAutomationRequireRootMutationRecord(AArgs);
  xeAutomationRequireWritableRootRecordTarget(lRecord);

  lFile := lRecord._File;
  lChildGroup := lRecord.ChildGroup;
  lRemovedRecord := xeAutomationNewListedRecordSummary(lRecord);
  try
    // Physical removal uses xEdit's native structure mutation seam and remains only in
    // daemon memory until session.save; records.mark_deleted covers Deleted-flag edits.
    lRecord.Remove;
    // Mirror native UI physical delete ordering so child GRUP data is removed with
    // records that own one instead of leaving orphaned groups in the patch structure.
    if Assigned(lChildGroup) then
      lChildGroup.Remove;

    Result := TJsonObject.Create;
    try
      Result.B['changed'] := True;
      Result.B['dirty'] := lFile.Modified;
      Result.O['file'] := xeAutomationNewFileSummary(lFile);
      Result.O['removedRecord'] := lRemovedRecord;
      lRemovedRecord := nil;
    except
      Result.Free;
      raise;
    end;
  finally
    lRemovedRecord.Free;
  end;
end;

function xeAutomationRecordsMarkDeleted(const AArgs: TJsonObject): TJsonObject;
var
  lRecord: IwbMainRecord;
  lFile: IwbFile;
  lExpectedDeleted: Boolean;
  lHasExpectedDeleted: Boolean;
  lBeforeDeleted: Boolean;
  lChanged: Boolean;
  lDeniedReason: string;
begin
  if not xeAutomationMutationPolicyConsentSatisfied(lDeniedReason) then begin
    Result := xeAutomationErrorsBuildConsentRequired('records.mark_deleted', 'records-mutation', lDeniedReason);
    Exit;
  end;

  lRecord := xeAutomationRequireRootMutationRecord(AArgs);
  xeAutomationRequireWritableRootRecordTarget(lRecord);

  lExpectedDeleted := xeAutomationReadBooleanArg(AArgs, 'expectedDeleted', lHasExpectedDeleted);
  lBeforeDeleted := lRecord.IsDeleted;

  if lHasExpectedDeleted and (lExpectedDeleted <> lBeforeDeleted) then
    // Expected-state checks fail before touching the native Deleted flag so clients can
    // safely retry optimistic workflows without accidentally changing stale targets.
    raise xeAutomationStateConflict(Format(
      'Automation records.mark_deleted expectedDeleted mismatch for %s:%s',
      [lRecord._File.FileName, lRecord.LoadOrderFormID.ToString(False)]
    ));

  lFile := lRecord._File;
  lChanged := not lBeforeDeleted;
  if lChanged then
    // xEdit exposes record deletion as a flag mutation here, distinct from Remove;
    // automation deliberately offers no undelete path through this surface.
    lRecord.IsDeleted := True;

  Result := TJsonObject.Create;
  try
    Result.B['changed'] := lChanged;
    Result.B['dirty'] := lFile.Modified;
    Result.O['file'] := xeAutomationNewFileSummary(lFile);
    Result.O['locator'].S['file'] := lFile.FileName;
    Result.O['locator'].S['formId'] := lRecord.LoadOrderFormID.ToString(False);
    Result.O['locator'].S['path'] := '';
    Result.O['before'].B['isDeleted'] := lBeforeDeleted;
    Result.O['after'].B['isDeleted'] := lRecord.IsDeleted;
    xeAutomationWriteRecordSummary(Result.O['record'], lRecord);
  except
    Result.Free;
    raise;
  end;
end;

function xeAutomationIdentifyCopiedMainRecord(const ACopiedElement: IwbElement; const ASourceRecord: IwbMainRecord;
  const ATargetFile: IwbFile; const AAsNew: Boolean): IwbMainRecord;
var
  lCopiedGroup: IwbGroupRecord;
begin
  Result := nil;

  if not AAsNew then begin
    // Deep-copying a child group mirrors the GUI seam and may return a group rather
    // than the owning record, so override mode re-resolves the stable source FormID
    // strictly in the target file instead of accepting a master-chain fallback.
    Result := xeAutomationResolveOwnedMainRecordInFile(ATargetFile, ASourceRecord.LoadOrderFormID.ToString(False));
    if Assigned(Result) then
      Exit;
  end;

  if Supports(ACopiedElement, IwbMainRecord, Result) then
    Exit;

  if Supports(ACopiedElement, IwbGroupRecord, lCopiedGroup) then
    Supports(lCopiedGroup.ChildrenOf, IwbMainRecord, Result);

  if not Assigned(Result) then
    raise xeAutomationMutationNotAllowed('Automation records.copy_into could not identify the copied main record');
end;

function xeAutomationRecordsCopyInto(const AArgs: TJsonObject): TJsonObject;
var
  lSourceLocator: TxeAutomationLocator;
  lTargetLocator: TxeAutomationLocator;
  lSourceRecord: IwbMainRecord;
  lTargetFile: IwbFile;
  lExistingTarget: IwbMainRecord;
  lCopySource: IwbElement;
  lCopiedElement: IwbElement;
  lCopiedRecord: IwbMainRecord;
  lRequiredMasters: TStringList;
  lMasterReport: TJsonObject;
  lMode: string;
  lAsNew: Boolean;
  lDeepCopy: Boolean;
  lNativeDeepCopy: Boolean;
  lOverwrite: Boolean;
  lAddRequiredMasters: Boolean;
  lOverwroteExisting: Boolean;
  lEditorIDPrefix: string;
  lEditorIDSuffix: string;
  lDeniedReason: string;
begin
  if not xeAutomationMutationPolicyConsentSatisfied(lDeniedReason) then begin
    Result := xeAutomationErrorsBuildConsentRequired('records.copy_into', 'records-mutation', lDeniedReason);
    Exit;
  end;

  lMasterReport := nil;
  lSourceLocator := xeAutomationParseNestedLocatorArg(AArgs, 'source', True, True);
  lTargetLocator := xeAutomationParseNestedLocatorArg(AArgs, 'target', False, True);

  // copy_into is intentionally record-root only. Reject child paths at the protocol
  // boundary before native copy routines can infer broader element semantics.
  if lSourceLocator.Path <> '' then
    raise xeAutomationInvalidRequest('Automation records.copy_into source path is not supported');
  if lTargetLocator.Path <> '' then
    raise xeAutomationInvalidRequest('Automation records.copy_into target path is not supported');

  lMode := LowerCase(xeAutomationRequireStringArg(AArgs, 'mode'));
  if lMode = 'override' then
    lAsNew := False
  else if lMode = 'new' then
    lAsNew := True
  else
    raise xeAutomationInvalidRequest(Format('Automation records.copy_into mode "%s" is not supported', [lMode]));

  lDeepCopy := xeAutomationReadBooleanArgDefault(AArgs, 'deepCopy', False);
  lOverwrite := xeAutomationReadBooleanArgDefault(AArgs, 'overwrite', False);
  lAddRequiredMasters := xeAutomationReadBooleanArgDefault(AArgs, 'addRequiredMasters', True);
  if lAsNew and lOverwrite then
    raise xeAutomationInvalidRequest('Automation records.copy_into overwrite is only supported for override mode');

  lEditorIDPrefix := xeAutomationReadStringArg(AArgs, 'editorIdPrefix');
  lEditorIDSuffix := xeAutomationReadStringArg(AArgs, 'editorIdSuffix');

  lSourceRecord := xeAutomationRequireMainRecord(lSourceLocator);
  lTargetFile := xeAutomationRequirePluginFile(lTargetLocator.FileName);
  xeAutomationRequireWritableTargetFile(lTargetFile);

  if not lSourceRecord.CanCopy then
    raise xeAutomationMutationNotAllowed('Automation records.copy_into source record cannot be copied');

  lExistingTarget := nil;
  if not lAsNew then begin
    // The existence precheck is about target ownership. A master record reachable
    // through the target's masters is not an existing override in the target file.
    lExistingTarget := xeAutomationResolveOwnedMainRecordInFile(lTargetFile, lSourceRecord.LoadOrderFormID.ToString(False));
    if Assigned(lExistingTarget) then begin
      if not lOverwrite then
        raise xeAutomationStateConflict(Format(
          'Automation records.copy_into target already contains override %s in %s',
          [lSourceRecord.LoadOrderFormID.ToString(False), lTargetFile.FileName]
        ));
      xeAutomationRequireWritableRootRecordTarget(lExistingTarget);
    end;
  end;
  lOverwroteExisting := Assigned(lExistingTarget) and lOverwrite;

  lNativeDeepCopy := lDeepCopy;
  if lOverwroteExisting then
    // wbCopyElementToFile only performs the desired replace/update path for existing
    // overrides when deep copy is forced, but the response still echoes caller intent.
    lNativeDeepCopy := True;

  // Use the same native-deep-copy decision for master preflight and the copy source;
  // otherwise child-group-only dependencies could bypass addRequiredMasters=false.
  lRequiredMasters := xeAutomationCollectCopyRequiredMasters(lSourceRecord, lAsNew, lNativeDeepCopy);
  try
    lMasterReport := xeAutomationApplyCopyRequiredMasters(lTargetFile, lRequiredMasters, lAddRequiredMasters);
  finally
    lRequiredMasters.Free;
  end;

  try
    // Master addition is the intentional pre-copy mutation boundary: native copy needs
    // dependencies present first, so later copy failures may leave audited master-list
    // changes, while addRequiredMasters=false still fails before hidden master edits.
    lCopySource := lSourceRecord;
    if lNativeDeepCopy and Assigned(lSourceRecord.ChildGroup) then
      lCopySource := lSourceRecord.ChildGroup;

    try
      lCopiedElement := wbCopyElementToFile(
        lCopySource,
        lTargetFile,
        lAsNew,
        lNativeDeepCopy,
        '',
        '',
        lEditorIDPrefix,
        lEditorIDSuffix,
        lOverwrite
      );
      lCopiedRecord := xeAutomationIdentifyCopiedMainRecord(lCopiedElement, lSourceRecord, lTargetFile, lAsNew);
    except
      on E: ExeAutomationError do
        raise;
      on E: Exception do
        raise xeAutomationInvalidTarget(Format('Automation record could not be copied: %s', [E.Message]));
    end;

    Result := TJsonObject.Create;
    try
      Result.B['changed'] := True;
      Result.B['dirty'] := lTargetFile.Modified;
      Result.S['mode'] := lMode;
      Result.B['deepCopy'] := lDeepCopy;
      Result.B['overwrite'] := lOverwrite;
      Result.B['overwroteExisting'] := lOverwroteExisting;
      Result.O['source'].S['file'] := lSourceLocator.FileName;
      Result.O['source'].S['formId'] := lSourceLocator.FormID;
      Result.O['source'].S['path'] := lSourceLocator.Path;
      Result.O['target'].S['file'] := lTargetFile.FileName;
      Result.O['target'].S['path'] := lTargetLocator.Path;
      Result.O['locator'].S['file'] := lCopiedRecord._File.FileName;
      Result.O['locator'].S['formId'] := lCopiedRecord.LoadOrderFormID.ToString(False);
      Result.O['locator'].S['path'] := '';
      Result.O['masters'] := lMasterReport;
      lMasterReport := nil;
      xeAutomationWriteRecordSummary(Result.O['record'], lCopiedRecord);
    except
      Result.Free;
      raise;
    end;
  except
    lMasterReport.Free;
    raise;
  end;
end;

function xeAutomationRecordsMasterOrSelf(const AArgs: TJsonObject): TJsonObject;
var
  lRecord: IwbMainRecord;
begin
  lRecord := xeAutomationRequireMainRecord(xeAutomationParseLocator(AArgs, True, False)).MasterOrSelf;
  Result := xeAutomationNewRecordResponseWithParents(lRecord, xeAutomationReadIncludeParentsArg(AArgs));
end;

function xeAutomationRecordsWinningOverride(const AArgs: TJsonObject): TJsonObject;
var
  lRecord: IwbMainRecord;
begin
  lRecord := xeAutomationRequireMainRecord(xeAutomationParseLocator(AArgs, True, False)).WinningOverride;
  Result := xeAutomationNewRecordResponseWithParents(lRecord, xeAutomationReadIncludeParentsArg(AArgs));
end;

procedure xeAutomationRegisterRecordsCommands;
begin
  xeAutomationRegisterCommand('records.list', xeAutomationRecordsList);
  xeAutomationRegisterCommand('records.apply_filter', xeAutomationRecordsApplyFilter);
  xeAutomationRegisterCommand('records.base_record', xeAutomationRecordsBaseRecord);
  xeAutomationRegisterCommand('records.create', xeAutomationRecordsCreate);
  xeAutomationRegisterCommand('records.copy_into', xeAutomationRecordsCopyInto);
  xeAutomationRegisterCommand('records.delete', xeAutomationRecordsDelete);
  xeAutomationRegisterCommand('records.mark_deleted', xeAutomationRecordsMarkDeleted);
  xeAutomationRegisterCommand('records.conflict_status', xeAutomationRecordsConflictStatus);
  xeAutomationRegisterCommand('records.references', xeAutomationRecordsReferences);
  xeAutomationRegisterCommand('records.referenced_by', xeAutomationRecordsReferencedBy);
  xeAutomationRegisterCommand('records.find_by_form_id', xeAutomationRecordsFindByFormID);
  xeAutomationRegisterCommand('records.find_by_editor_id', xeAutomationRecordsFindByEditorID);
  xeAutomationRegisterCommand('records.get', xeAutomationRecordsGet);
  xeAutomationRegisterCommand('records.master_or_self', xeAutomationRecordsMasterOrSelf);
  xeAutomationRegisterCommand('records.winning_override', xeAutomationRecordsWinningOverride);
end;

end.
