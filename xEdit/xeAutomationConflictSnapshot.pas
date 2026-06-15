{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeAutomationConflictSnapshot;

interface

uses
  wbInterface;

type
  TxeAutomationConflictParticipant = record
    FileRef: IwbFile;
    Role: string;
    Present: Boolean;
  end;

  TxeAutomationConflictParticipants = array of TxeAutomationConflictParticipant;

  TxeAutomationConflictChildSnapshot = record
    Element: IwbElement;
    LocatorElement: IwbElement;
    ConflictAll: TConflictAll;
    ConflictThis: TConflictThis;
    Participants: TxeAutomationConflictParticipants;
  end;

  TxeAutomationConflictChildSnapshots = array of TxeAutomationConflictChildSnapshot;

  TxeAutomationConflictChildGroupSignature = record
    Signature: string;
    Total: Integer;
    Conflicting: Integer;
  end;

  TxeAutomationConflictChildGroupSignatures = array of TxeAutomationConflictChildGroupSignature;

  TxeAutomationConflictChildGroupHit = record
    RecordRef: IwbMainRecord;
    ConflictAll: TConflictAll;
    ConflictThis: TConflictThis;
  end;

  TxeAutomationConflictChildGroupHits = array of TxeAutomationConflictChildGroupHit;

  TxeAutomationConflictChildGroupSnapshot = record
    Present: Boolean;
    Count: Integer;
    HasConflict: Boolean;
    Signatures: TxeAutomationConflictChildGroupSignatures;
    ConflictingHits: TxeAutomationConflictChildGroupHits;
    ConflictingHitsTruncated: Boolean;
  end;

  TxeAutomationConflictSnapshot = record
    Element: IwbElement;
    ConflictAll: TConflictAll;
    ConflictThis: TConflictThis;
    Participants: TxeAutomationConflictParticipants;
    Children: TxeAutomationConflictChildSnapshots;
    ChildrenTruncated: Boolean;
    ChildGroup: TxeAutomationConflictChildGroupSnapshot;
  end;

function xeAutomationSnapshotRecordConflict(const ARecord: IwbMainRecord; const ALimit: Integer): TxeAutomationConflictSnapshot;
function xeAutomationSnapshotElementConflict(const AElement: IwbElement; const ALimit: Integer): TxeAutomationConflictSnapshot;

implementation

uses
  SysUtils,
  VirtualTrees,
  wbHelpers,
  xeMainForm;

const
  xeAutomationChildGroupConflictSignatures = 'REFR,ACHR,PGRE,PHZD,PARW,PBAR,PBEA,PCON,PFLA,PMIS,LAND,NAVM,PGRD,INFO,DLBR,SCEN,CELL,DIAL,QUST,WRLD';

type
  TxeAutomationParticipantFileRefs = array of IwbFile;

  // The helper needs the same row-alignment/conflict primitives that the GUI uses,
  // but automation keeps that dependency quarantined here instead of widening the
  // public TfrmMain surface for protocol-facing command units.
  TfrmMainAccess = class(TfrmMain)
  public
    function AccessNodeDatasForMainRecord(const AMainRecord: IwbMainRecord): TDynViewNodeDatas;
    function AccessNodeDatasForContainer(const AContainer: IwbDataContainer): TDynViewNodeDatas;
    procedure AccessInitChildren(const ANodeDatas: PViewNodeDatas; ANodeCount: Integer; var AChildCount: Cardinal);
    procedure AccessInitNodes(const ANode: PVirtualNode; const ANodeDatas, AParentDatas: PViewNodeDatas;
      ANodeCount: Integer; AIndex: Cardinal; var AInitialStates: TVirtualNodeInitStates);
  end;

function TfrmMainAccess.AccessNodeDatasForMainRecord(const AMainRecord: IwbMainRecord): TDynViewNodeDatas;
begin
  Result := NodeDatasForMainRecord(AMainRecord);
end;

function TfrmMainAccess.AccessNodeDatasForContainer(const AContainer: IwbDataContainer): TDynViewNodeDatas;
begin
  Result := NodeDatasForContainer(AContainer);
end;

procedure TfrmMainAccess.AccessInitChildren(const ANodeDatas: PViewNodeDatas; ANodeCount: Integer; var AChildCount: Cardinal);
begin
  InitChildren(ANodeDatas, ANodeCount, AChildCount);
end;

procedure TfrmMainAccess.AccessInitNodes(const ANode: PVirtualNode; const ANodeDatas, AParentDatas: PViewNodeDatas;
  ANodeCount: Integer; AIndex: Cardinal; var AInitialStates: TVirtualNodeInitStates);
begin
  InitNodes(ANode, ANodeDatas, AParentDatas, ANodeCount, AIndex, AInitialStates);
end;

function xeAutomationMainFormAccess: TfrmMainAccess;
begin
  if not Assigned(frmMain) then
    raise Exception.Create('Automation conflict snapshot requires the main form');
  Result := TfrmMainAccess(frmMain);
end;

function xeAutomationConflictRole(const AIndex: Integer; const APresent: Boolean): string;
begin
  if not APresent then
    Exit('missing');
  if AIndex = 0 then
    Exit('master');
  Result := 'override';
end;

function xeAutomationConflictUsesInjectedPriority(const ARecord: IwbMainRecord): Boolean;
begin
  Result := ARecord.MasterOrSelf.IsInjected and not ((ARecord.Signature = 'GMST') or (ARecord.Signature = 'DFOB'));
end;

function xeAutomationElementIndexedPath(const AElement: IwbElement): string;
begin
  Result := Trim(AElement.IndexedPath[False]);
end;

function xeAutomationRepresentativeElement(const ANodeDatas: TDynViewNodeDatas; const APreferredIndex: Integer): IwbElement;
var
  i: Integer;
begin
  Result := nil;
  if (APreferredIndex >= Low(ANodeDatas)) and (APreferredIndex <= High(ANodeDatas)) then
    Result := ANodeDatas[APreferredIndex].Element;
  if Assigned(Result) then
    Exit;

  for i := Low(ANodeDatas) to High(ANodeDatas) do
    if Assigned(ANodeDatas[i].Element) then
      Exit(ANodeDatas[i].Element);
end;

function xeAutomationBuildParticipantFileRefs(const ANodeDatas: TDynViewNodeDatas): TxeAutomationParticipantFileRefs;
var
  i: Integer;
begin
  SetLength(Result, Length(ANodeDatas));
  for i := Low(ANodeDatas) to High(ANodeDatas) do
    if Assigned(ANodeDatas[i].Element) then
      Result[i] := ANodeDatas[i].Element._File
    else if Assigned(ANodeDatas[i].Container) then
      Result[i] := ANodeDatas[i].Container._File;
end;

function xeAutomationBuildAlignedParticipants(const ANodeDatas: TDynViewNodeDatas;
  const AParticipantFileRefs: TxeAutomationParticipantFileRefs): TxeAutomationConflictParticipants;
var
  i: Integer;
  lPresent: Boolean;
begin
  SetLength(Result, Length(AParticipantFileRefs));
  for i := Low(AParticipantFileRefs) to High(AParticipantFileRefs) do begin
    lPresent := Assigned(ANodeDatas[i].Element);
    // Participant file identity must come from the snapshot's aligned comparison
    // basis, not from whichever child happens to exist in this row. That keeps
    // file/load-order fields stable even when a deeper child is missing here.
    Result[i].FileRef := AParticipantFileRefs[i];
    Result[i].Present := lPresent;
    Result[i].Role := xeAutomationConflictRole(i, lPresent);
  end;
end;

procedure xeAutomationResetNodeDatas(var ANodeDatas: TDynViewNodeDatas; const ANodeCount: Integer);
begin
  // InitNodes expects a fresh row buffer. Reusing an old TDynViewNodeDatas instance
  // without clearing it can leak stale Element/Container/flag state between rows.
  Finalize(ANodeDatas);
  SetLength(ANodeDatas, ANodeCount);
end;

function xeAutomationTargetIndexForFile(const ANodeDatas: TDynViewNodeDatas; const ATargetFile: IwbFile): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := Low(ANodeDatas) to High(ANodeDatas) do
    if Assigned(ANodeDatas[i].Element) and Assigned(ATargetFile) and ANodeDatas[i].Element._File.Equals(ATargetFile) then
      Exit(i);
end;

function xeAutomationFindAlignedRow(const AParentNodeDatas: TDynViewNodeDatas; const ATargetElement: IwbElement;
  out ANodeDatas: TDynViewNodeDatas; out AInitialStates: TVirtualNodeInitStates): Boolean; forward;

function xeAutomationParentPath(const APath: string): string;
var
  lDelimiter: Integer;
begin
  lDelimiter := LastDelimiter('\', APath);
  if lDelimiter > 0 then
    Result := Copy(APath, 1, Pred(lDelimiter))
  else
    Result := '';
end;

function xeAutomationParentNodeDatasForElement(const AElement: IwbElement): TDynViewNodeDatas;
var
  lAccess: TfrmMainAccess;
  lRecord: IwbMainRecord;
  lParentElement: IwbElement;
  lParentContainer: IwbDataContainer;
  lGrandParentNodeDatas: TDynViewNodeDatas;
  lInitialStates: TVirtualNodeInitStates;
  lParentPath: string;
begin
  lAccess := xeAutomationMainFormAccess;
  lRecord := AElement.ContainingMainRecord;
  lParentPath := xeAutomationParentPath(xeAutomationElementIndexedPath(AElement));
  if lParentPath = '' then
    Exit(lAccess.AccessNodeDatasForMainRecord(lRecord));

  lParentElement := lRecord.ElementByPath[lParentPath];
  if not Assigned(lParentElement) then
    raise Exception.CreateFmt('Automation conflict snapshot could not resolve parent path "%s" for element "%s"', [lParentPath, AElement.Name]);

  if Supports(lParentElement, IwbDataContainer, lParentContainer) then
    Exit(lAccess.AccessNodeDatasForContainer(lParentContainer));

  // Some immediate parents are visible tree nodes without a direct data-container
  // interface. In that case we align the parent from its ancestor row using the
  // stable indexed locator path instead of chasing brittle container interfaces.
  lGrandParentNodeDatas := xeAutomationParentNodeDatasForElement(lParentElement);
  if xeAutomationFindAlignedRow(lGrandParentNodeDatas, lParentElement, Result, lInitialStates) then
    Exit;

  raise Exception.CreateFmt('Automation conflict snapshot could not align parent for element "%s"', [AElement.Name]);
end;

function xeAutomationFindAlignedRow(const AParentNodeDatas: TDynViewNodeDatas; const ATargetElement: IwbElement;
  out ANodeDatas: TDynViewNodeDatas; out AInitialStates: TVirtualNodeInitStates): Boolean;
var
  lAccess: TfrmMainAccess;
  lChildCount: Cardinal;
  lTargetIndex: Integer;
  lChildIndex: Cardinal;
  i: Integer;
begin
  Result := False;
  ANodeDatas := nil;
  AInitialStates := [];
  if Length(AParentNodeDatas) = 0 then
    Exit;

  lTargetIndex := xeAutomationTargetIndexForFile(AParentNodeDatas, ATargetElement._File);
  if lTargetIndex < 0 then
    Exit;

  lAccess := xeAutomationMainFormAccess;
  lChildCount := 0;
  lAccess.AccessInitChildren(@AParentNodeDatas[0], Length(AParentNodeDatas), lChildCount);

  for lChildIndex := 0 to Pred(lChildCount) do begin
    xeAutomationResetNodeDatas(ANodeDatas, Length(AParentNodeDatas));
    AInitialStates := [];
    lAccess.AccessInitNodes(nil, @ANodeDatas[0], @AParentNodeDatas[0], Length(AParentNodeDatas), lChildIndex, AInitialStates);
    if ivsDisabled in AInitialStates then
      Continue;

    for i := Low(ANodeDatas) to High(ANodeDatas) do
      if Assigned(ANodeDatas[i].Element) and ANodeDatas[i].Element.Equals(ATargetElement) then
        Exit(True);
  end;

  ANodeDatas := nil;
  AInitialStates := [];
end;

function xeAutomationBuildConflictedChildren(const AParentNodeDatas: TDynViewNodeDatas; const ATargetIndex: Integer;
  const AParticipantFileRefs: TxeAutomationParticipantFileRefs; const AInjected: Boolean; const ALimit: Integer;
  out ATruncated: Boolean): TxeAutomationConflictChildSnapshots;
var
  lAccess: TfrmMainAccess;
  lChildCount: Cardinal;
  lInitialStates: TVirtualNodeInitStates;
  lNodeDatas: TDynViewNodeDatas;
  lConflictAll: TConflictAll;
  lItem: TxeAutomationConflictChildSnapshot;
  lCount: Integer;
  lChildIndex: Cardinal;
begin
  Result := nil;
  ATruncated := False;
  lCount := 0;
  if Length(AParentNodeDatas) = 0 then
    Exit;

  lAccess := xeAutomationMainFormAccess;
  lChildCount := 0;
  lAccess.AccessInitChildren(@AParentNodeDatas[0], Length(AParentNodeDatas), lChildCount);

  // Automation conflict snapshots intentionally expose only conflicted immediate
  // children so callers can drill down explicitly instead of receiving a full tree.
  for lChildIndex := 0 to Pred(lChildCount) do begin
    xeAutomationResetNodeDatas(lNodeDatas, Length(AParentNodeDatas));
    lInitialStates := [];
    lAccess.AccessInitNodes(nil, @lNodeDatas[0], @AParentNodeDatas[0], Length(AParentNodeDatas), lChildIndex, lInitialStates);
    if ivsDisabled in lInitialStates then
      Continue;

    if ivsHasChildren in lInitialStates then
      lConflictAll := lAccess.ConflictLevelForChildNodeDatas(lNodeDatas, False, AInjected)
    else
      lConflictAll := lAccess.ConflictLevelForNodeDatas(@lNodeDatas[0], Length(lNodeDatas), False, AInjected);

    if lConflictAll <= caNoConflict then
      Continue;

    if (ALimit >= 0) and (lCount >= ALimit) then begin
      ATruncated := True;
      Break;
    end;

    lItem.Element := xeAutomationRepresentativeElement(lNodeDatas, ATargetIndex);
    if (ATargetIndex >= Low(lNodeDatas)) and (ATargetIndex <= High(lNodeDatas)) then
      lItem.LocatorElement := lNodeDatas[ATargetIndex].Element
    else
      lItem.LocatorElement := nil;
    lItem.ConflictAll := lConflictAll;
    if (ATargetIndex >= Low(lNodeDatas)) and (ATargetIndex <= High(lNodeDatas)) then
      lItem.ConflictThis := lNodeDatas[ATargetIndex].ConflictThis
    else
      lItem.ConflictThis := ctUnknown;
    // Child participants reuse the snapshot's aligned comparison basis so missing
    // child slots still carry stable file identity for protocol consumers.
    lItem.Participants := xeAutomationBuildAlignedParticipants(lNodeDatas, AParticipantFileRefs);

    SetLength(Result, Succ(lCount));
    Result[lCount] := lItem;
    Inc(lCount);
  end;
end;

function xeAutomationFindChildGroupSignatureIndex(const ASignatures: TxeAutomationConflictChildGroupSignatures;
  const ASignature: string): Integer;
var
  i: Integer;
begin
  for i := Low(ASignatures) to High(ASignatures) do
    if SameText(ASignatures[i].Signature, ASignature) then
      Exit(i);
  Result := -1;
end;

procedure xeAutomationAddChildGroupSignature(var AChildGroup: TxeAutomationConflictChildGroupSnapshot;
  const ASignature: string; const AConflicting: Boolean);
var
  lIndex: Integer;
begin
  lIndex := xeAutomationFindChildGroupSignatureIndex(AChildGroup.Signatures, ASignature);
  if lIndex < 0 then begin
    SetLength(AChildGroup.Signatures, Length(AChildGroup.Signatures) + 1);
    lIndex := High(AChildGroup.Signatures);
    AChildGroup.Signatures[lIndex].Signature := ASignature;
  end;

  Inc(AChildGroup.Signatures[lIndex].Total);
  if AConflicting then
    Inc(AChildGroup.Signatures[lIndex].Conflicting);
end;

procedure xeAutomationAppendChildGroupConflictHit(var AChildGroup: TxeAutomationConflictChildGroupSnapshot;
  const ARecord: IwbMainRecord; const AConflictAll: TConflictAll; const AConflictThis: TConflictThis;
  const ALimit: Integer);
var
  lIndex: Integer;
begin
  if Length(AChildGroup.ConflictingHits) >= ALimit then begin
    AChildGroup.ConflictingHitsTruncated := True;
    Exit;
  end;

  SetLength(AChildGroup.ConflictingHits, Length(AChildGroup.ConflictingHits) + 1);
  lIndex := High(AChildGroup.ConflictingHits);
  AChildGroup.ConflictingHits[lIndex].RecordRef := ARecord;
  AChildGroup.ConflictingHits[lIndex].ConflictAll := AConflictAll;
  AChildGroup.ConflictingHits[lIndex].ConflictThis := AConflictThis;
end;

function xeAutomationSnapshotChildGroupConflict(const ARecord: IwbMainRecord): TxeAutomationConflictChildGroupSnapshot;
var
  lAccess: TfrmMainAccess;
  lChildren: TDynMainRecords;
  lConflictAll: TConflictAll;
  lConflictThis: TConflictThis;
  lConflicting: Boolean;
  i: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  if not Assigned(ARecord.ChildGroup) or (ARecord.ChildGroup.ElementCount = 0) then
    Exit;

  lChildren := wbGetSiblingRecords(ARecord, wbStringToSignatures(xeAutomationChildGroupConflictSignatures), True);
  if Length(lChildren) = 0 then
    Exit;

  Result.Present := True;
  Result.Count := Length(lChildren);
  lAccess := xeAutomationMainFormAccess;

  for i := Low(lChildren) to High(lChildren) do begin
    lAccess.ConflictLevelForMainRecord(lChildren[i], lConflictAll, lConflictThis);
    lConflicting := lConflictAll > caNoConflict;
    xeAutomationAddChildGroupSignature(Result, lChildren[i].Signature, lConflicting);

    if not lConflicting then
      Continue;

    Result.HasConflict := True;
    xeAutomationAppendChildGroupConflictHit(Result, lChildren[i], lConflictAll, lConflictThis, 20);
  end;
end;

function xeAutomationSnapshotRecordConflict(const ARecord: IwbMainRecord; const ALimit: Integer): TxeAutomationConflictSnapshot;
var
  lAccess: TfrmMainAccess;
  lParentNodeDatas: TDynViewNodeDatas;
  lParticipantFileRefs: TxeAutomationParticipantFileRefs;
  lTargetIndex: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Element := ARecord;

  lAccess := xeAutomationMainFormAccess;
  lAccess.ConflictLevelForMainRecord(ARecord, Result.ConflictAll, Result.ConflictThis);

  lParentNodeDatas := lAccess.AccessNodeDatasForMainRecord(ARecord);
  lParticipantFileRefs := xeAutomationBuildParticipantFileRefs(lParentNodeDatas);
  // Root participants use the same aligned comparison row basis as child snapshots
  // so JSON consumers see one stable participant ordering across the whole snapshot.
  Result.Participants := xeAutomationBuildAlignedParticipants(lParentNodeDatas, lParticipantFileRefs);
  lTargetIndex := xeAutomationTargetIndexForFile(lParentNodeDatas, ARecord._File);
  Result.Children := xeAutomationBuildConflictedChildren(
    lParentNodeDatas,
    lTargetIndex,
    lParticipantFileRefs,
    xeAutomationConflictUsesInjectedPriority(ARecord),
    ALimit,
    Result.ChildrenTruncated
  );
  Result.ChildGroup := xeAutomationSnapshotChildGroupConflict(ARecord);
end;

function xeAutomationSnapshotElementConflict(const AElement: IwbElement; const ALimit: Integer): TxeAutomationConflictSnapshot;
var
  lAccess: TfrmMainAccess;
  lRecord: IwbMainRecord;
  lParticipantFileRefs: TxeAutomationParticipantFileRefs;
  lParentNodeDatas: TDynViewNodeDatas;
  lNodeDatas: TDynViewNodeDatas;
  lInitialStates: TVirtualNodeInitStates;
  lTargetIndex: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Element := AElement;

  if Supports(AElement, IwbMainRecord, lRecord) then
    Exit(xeAutomationSnapshotRecordConflict(lRecord, ALimit));

  lAccess := xeAutomationMainFormAccess;
  lRecord := AElement.ContainingMainRecord;

  // Leaf requests must align the addressed element's own comparison row rather than
  // silently reusing the parent's aggregate row, so elements.conflict_status stays a
  // true child drill-down endpoint for exact locator-based follow-up calls.
  lParentNodeDatas := xeAutomationParentNodeDatasForElement(AElement);

  if not xeAutomationFindAlignedRow(lParentNodeDatas, AElement, lNodeDatas, lInitialStates) then
    raise Exception.CreateFmt('Automation conflict snapshot could not align element "%s"', [AElement.Name]);

  lParticipantFileRefs := xeAutomationBuildParticipantFileRefs(
    lAccess.AccessNodeDatasForMainRecord(lRecord)
  );
  lTargetIndex := xeAutomationTargetIndexForFile(lNodeDatas, AElement._File);
  if ivsHasChildren in lInitialStates then
    Result.ConflictAll := lAccess.ConflictLevelForChildNodeDatas(lNodeDatas, False, xeAutomationConflictUsesInjectedPriority(lRecord))
  else
    Result.ConflictAll := lAccess.ConflictLevelForNodeDatas(@lNodeDatas[0], Length(lNodeDatas), False, xeAutomationConflictUsesInjectedPriority(lRecord));

  if lTargetIndex >= 0 then
    Result.ConflictThis := lNodeDatas[lTargetIndex].ConflictThis
  else
    Result.ConflictThis := ctUnknown;

  Result.Participants := xeAutomationBuildAlignedParticipants(lNodeDatas, lParticipantFileRefs);
  // Use the aligned row's initialized child-state instead of depending on JSON
  // object-model helpers from this lower-level conflict snapshot unit.
  if ivsHasChildren in lInitialStates then
    Result.Children := xeAutomationBuildConflictedChildren(
      lNodeDatas,
      lTargetIndex,
      lParticipantFileRefs,
      xeAutomationConflictUsesInjectedPriority(lRecord),
      ALimit,
      Result.ChildrenTruncated
    );
end;

end.
