{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeAutomationDataLookup;

interface

uses
  System.RegularExpressions,
  wbInterface,
  wbLoadOrder,
  JsonDataObjects,
  xeAutomationObjectModel;

type
  TxeAutomationMainRecords = array of IwbMainRecord;
  TxeAutomationFiles = array of IwbFile;

  TxeAutomationMainRecordSearch = record
    Hits: TxeAutomationMainRecords;
    Truncated: Boolean;
    MasterOrSelf: IwbMainRecord;
    WinningOverride: IwbMainRecord;
  end;

  TxeAutomationBoundedMainRecordSearch = record
    Hits: TxeAutomationMainRecords;
    Truncated: Boolean;
    RegexTimeouts: Integer;
    RegexSlotsExhausted: Integer;
  end;

  TxeAutomationRecordFilter = record
    Files: TxeAutomationFiles;
    Signatures: TwbSignatures;
    BaseSignatures: TwbSignatures;
    EditorIDPattern: string;
    DisplayNamePattern: string;
    FullNamePattern: string;
    BaseEditorIDPattern: string;
    BaseDisplayNamePattern: string;
    ParentFormID: Cardinal;
    HasParentFormID: Boolean;
    EditorIDRegex: TRegEx;
    HasEditorIDRegex: Boolean;
    DisplayNameRegex: TRegEx;
    HasDisplayNameRegex: Boolean;
    FullNameRegex: TRegEx;
    HasFullNameRegex: Boolean;
    BaseEditorIDRegex: TRegEx;
    HasBaseEditorIDRegex: Boolean;
    BaseDisplayNameRegex: TRegEx;
    HasBaseDisplayNameRegex: Boolean;
    RegexTimeouts: Integer;
    RegexSlotsExhausted: Integer;
    BaseFormID: TwbFormID;
    HasBaseFormID: Boolean;
    HasIsMaster: Boolean;
    IsMaster: Boolean;
    HasIsWinningOverride: Boolean;
    IsWinningOverride: Boolean;
    HasIsDeleted: Boolean;
    IsDeleted: Boolean;
    HasIsInjected: Boolean;
    IsInjected: Boolean;
    ConflictAll: TConflictAllSet;
    UseConflictAll: Boolean;
    ConflictThis: TConflictThisSet;
    UseConflictThis: Boolean;
    Limit: Integer;
  end;

function xeAutomationTryPluginFileFromModule(const AModule: PwbModuleInfo): IwbFile;
function xeAutomationRequirePluginFile(const AName: string): IwbFile;
function xeAutomationNewFileSummary(const AFile: IwbFile): TJsonObject;
function xeAutomationArgPresent(const AArgs: TJsonObject; const AKey: string): Boolean;
function xeAutomationParseFormIdHex(const AHex: string): Cardinal;
function xeAutomationRequireFormID(const AFormID: string): TwbFormID;
function xeAutomationGlobMatchesCI(const AValue, APattern: string): Boolean;
function xeAutomationFindMainRecordsByLoadOrderFormID(const AFormID: string; const AFileName: string = ''): TxeAutomationMainRecordSearch;
function xeAutomationFindMainRecordsByEditorID(const AEditorID: string; const ASignature: string = ''): TxeAutomationBoundedMainRecordSearch;
function xeAutomationFilterMainRecords(const AArgs: TJsonObject): TxeAutomationBoundedMainRecordSearch;
function xeAutomationReadSearchLimit(const AArgs: TJsonObject; const AName: string = 'limit'; const ADefault: Integer = 100): Integer;
function xeAutomationReadChildrenLimitArg(const AArgs: TJsonObject; const AName: string = 'limit'; const ADefault: Integer = 200): Integer;
function xeAutomationReadOffsetArg(const AArgs: TJsonObject; const AName: string = 'offset'; const ADefault: Integer = 0): Integer;
function xeAutomationCollectOutgoingReferences(const ARecord: IwbMainRecord; const ALimit: Integer;
  const ARecursive: Boolean): TxeAutomationBoundedMainRecordSearch;
function xeAutomationCollectReferencedByRecords(const ARecord: IwbMainRecord; const ALimit: Integer): TxeAutomationBoundedMainRecordSearch;
function xeAutomationCollectNewMainRecordsInFile(const AFile: IwbFile): TxeAutomationMainRecords;
function xeAutomationResolveMainRecordInFile(const AFile: IwbFile; const AFormID: string): IwbMainRecord;
function xeAutomationResolveOwnedMainRecordInFile(const AFile: IwbFile; const AFormID: string): IwbMainRecord;
function xeAutomationRequireMainRecord(const ALocator: TxeAutomationLocator): IwbMainRecord;
function xeAutomationRequireOwnedMainRecord(const ALocator: TxeAutomationLocator): IwbMainRecord;
function xeAutomationPathStartsWithChildGroupPrefix(const APath: string): Boolean;
function xeAutomationRequireElement(const ALocator: TxeAutomationLocator; out ARecord: IwbMainRecord): IwbElement;
function xeAutomationRequireOwnedElement(const ALocator: TxeAutomationLocator; out ARecord: IwbMainRecord): IwbElement;

implementation

uses
  System.Generics.Collections,
  System.Threading,
  SysUtils,
  StrUtils,
  Types,
  JclStrings,
  wbHelpers,
  xeAutomationErrors;

const
  xeAutomationRecordSearchLimit = 100;
  xeAutomationElementsChildrenMaxLimit = 1000;
  xeAutomationChildGroupPathPrefix = '\Child Group';
  xeAutomationRegexTimeoutMs = 100;
  xeAutomationMaxRegexTasksInFlight = 4;
  xeAutomationChildGroupReferenceSignatures = 'REFR,ACHR,PGRE,PHZD,PARW,PBAR,PBEA,PCON,PFLA,PMIS,LAND,NAVM,PGRD,INFO,DLBR,SCEN,CELL,DIAL,QUST,WRLD';

var
  xeAutomationRegexTasksInFlight: Integer = 0;
  xeAutomationRegexTaskLock: TObject;

type
  IxeAutomationRegexMatchState = interface
    ['{8F47082E-5451-46E8-82B0-6536788595D8}']
    procedure Execute;
    function GetMatched: Boolean;
    property Matched: Boolean read GetMatched;
  end;

  TxeAutomationRegexMatchState = class(TInterfacedObject, IxeAutomationRegexMatchState)
  private
    FRegex: TRegEx;
    FInput: string;
    FMatched: Boolean;
  public
    constructor Create(const ARegex: TRegEx; const AInput: string);
    procedure Execute;
    function GetMatched: Boolean;
  end;

constructor TxeAutomationRegexMatchState.Create(const ARegex: TRegEx; const AInput: string);
begin
  inherited Create;
  FRegex := ARegex;
  FInput := AInput;
  FMatched := False;
end;

procedure TxeAutomationRegexMatchState.Execute;
begin
  FMatched := FRegex.IsMatch(FInput);
end;

function TxeAutomationRegexMatchState.GetMatched: Boolean;
begin
  Result := FMatched;
end;

function xeAutomationTryPluginFileFromModule(const AModule: PwbModuleInfo): IwbFile;
begin
  Result := nil;
  if not Assigned(AModule) or not AModule^.IsValid then
    Exit;

  // Automation-created files can be registered as new/loaded modules before xEdit
  // assigns a normal load-order index. Keep them visible to files.list, save target
  // resolution, and duplicate checks as long as they are real plugin files.
  Result := AModule^._File;
  if Assigned(Result) and ((mfIsHardcoded in AModule^.miFlags) or (AModule^.miExtension = meUnknown) or Result.IsNotPlugin) then
    Result := nil;
end;

function xeAutomationNewFileSummary(const AFile: IwbFile): TJsonObject;
var
  lMasters: TJsonArray;
  i: Integer;
begin
  Result := TJsonObject.Create;
  Result.S['name'] := AFile.FileName;
  Result.I['loadOrder'] := AFile.LoadOrder;
  Result.S['loadOrderFileId'] := AFile.LoadOrderFileID.ToString;
  Result.S['fileName'] := AFile.FileName;
  Result.B['isEditable'] := AFile.IsEditable;
  Result.B['isESM'] := AFile.IsESM;
  Result.B['isLight'] := AFile.IsLight;
  Result.B['isMedium'] := AFile.IsMedium;
  Result.B['modified'] := AFile.Modified;
  // Master-list readback is part of the file-state contract: mutation commands
  // may report requested master handling, but callers still need the actual xEdit
  // file state to prove no hidden self/required-master mutation occurred.
  lMasters := Result.A['masters'];
  for i := 0 to Pred(AFile.MasterCount[True]) do
    lMasters.Add(AFile.Masters[i, True].FileName);
end;

function xeAutomationArgPresent(const AArgs: TJsonObject; const AKey: string): Boolean;
begin
  // Treat explicit JSON null and absent keys both as "not present"; any other
  // JSON type is present so the per-arg validators can reject malformed input.
  Result := Assigned(AArgs) and AArgs.Contains(AKey) and not AArgs.IsNull(AKey);
end;

function xeAutomationParseFormIdHex(const AHex: string): Cardinal;
var
  lTrimmed: string;
  lParsed: Int64;
begin
  lTrimmed := Trim(AHex);
  if lTrimmed = '' then
    raise xeAutomationInvalidRequest('FormID hex string is empty');

  // Use an Int64 intermediate so malformed/overflowing public FormID strings are
  // rejected at the request boundary before native xEdit mutation code runs.
  if not TryStrToInt64('$' + lTrimmed, lParsed) then
    raise xeAutomationInvalidRequest(Format('FormID hex string is not parsable: %s', [AHex]));
  if (lParsed < 0) or (lParsed > Cardinal(-1)) then
    raise xeAutomationInvalidRequest(Format('FormID hex string is out of Cardinal range: %s', [AHex]));
  Result := Cardinal(lParsed);
end;

function xeAutomationRequirePluginFile(const AName: string): IwbFile;
var
  lModule: PwbModuleInfo;
begin
  lModule := wbModuleByName(AName);
  Result := nil;
  if lModule^.IsValid then
    Result := xeAutomationTryPluginFileFromModule(lModule);

  if not Assigned(Result) then
    raise xeAutomationNewError(
      xeAutomationErrorFileNotFound,
      Format('Automation file not found: %s', [AName])
    );
end;

function xeAutomationRequireFormID(const AFormID: string): TwbFormID;
begin
  if AFormID = '' then
    raise xeAutomationInvalidRequest('Automation locator must include formId');

  try
    Result := TwbFormID.FromStr(AFormID);
  except
    on E: Exception do
      raise xeAutomationInvalidRequest(
        Format('Automation locator formId must be a valid FormID: %s', [AFormID])
      );
  end;
end;

function xeAutomationGlobMatchesCI(const AValue, APattern: string): Boolean;
begin
  if APattern = '' then
    Exit(True);

  // JCL globbing is case-sensitive, so normalize both sides once here and keep the
  // later filter commands on one shared case-insensitive wildcard contract.
  Result := StrMatches(UpperCase(APattern), UpperCase(AValue));
end;

function xeAutomationTryAcquireRegexTaskSlot: Boolean;
begin
  TMonitor.Enter(xeAutomationRegexTaskLock);
  try
    Result := xeAutomationRegexTasksInFlight < xeAutomationMaxRegexTasksInFlight;
    if Result then
      Inc(xeAutomationRegexTasksInFlight);
  finally
    TMonitor.Exit(xeAutomationRegexTaskLock);
  end;
end;

procedure xeAutomationReleaseRegexTaskSlot;
begin
  TMonitor.Enter(xeAutomationRegexTaskLock);
  try
    if xeAutomationRegexTasksInFlight > 0 then
      Dec(xeAutomationRegexTasksInFlight);
  finally
    TMonitor.Exit(xeAutomationRegexTaskLock);
  end;
end;

function xeAutomationRegexMatchTimeBounded(const ARegex: TRegEx; const AInput: string;
  ATimeoutMs: Cardinal; var ATimedOut: Boolean; var ASlotExhausted: Boolean): Boolean;
var
  lTask: ITask;
  lState: IxeAutomationRegexMatchState;
begin
  ATimedOut := False;
  ASlotExhausted := False;
  Result := False;

  if not xeAutomationTryAcquireRegexTaskSlot then begin
    ASlotExhausted := True;
    Exit;
  end;

  lState := TxeAutomationRegexMatchState.Create(ARegex, AInput);
  lTask := TTask.Run(
    procedure
    begin
      try
        lState.Execute;
      finally
        xeAutomationReleaseRegexTaskSlot;
      end;
    end);

  // CONTRACT: System.RegularExpressions.TRegEx has no interruptible match API in
  // this RTL. The daemon wait only bounds how long the main apply_filter loop waits
  // on each record; it does not terminate the worker, which may finish later using
  // the reference-counted match state captured above.
  //
  // Bound class                    | Reported as
  // ------------------------------ | ------------------------------------------
  // Worker finishes within 100 ms  | matched/non-matched record result
  // Worker exceeds 100 ms wait     | non-match and result.regexTimeouts++
  // All 4 worker slots in use      | non-match and result.regexSlotsExhausted++
  //
  // Clients should avoid catastrophic-backtracking patterns. This Tier 1 guard is
  // honest observability, not real worker cancellation; subprocess isolation is the
  // future Tier 2 design required for hard wall-time termination.
  if lTask.Wait(ATimeoutMs) then
    Result := lState.Matched
  else
    ATimedOut := True;
end;

function xeAutomationRegexFieldMatches(const ARegex: TRegEx; const AValue: string;
  var AFilter: TxeAutomationRecordFilter): Boolean;
var
  lTimedOut: Boolean;
  lSlotExhausted: Boolean;
begin
  Result := xeAutomationRegexMatchTimeBounded(ARegex, AValue, xeAutomationRegexTimeoutMs, lTimedOut, lSlotExhausted);
  if lTimedOut then begin
    Inc(AFilter.RegexTimeouts);
    Result := False;
  end else if lSlotExhausted then begin
    Inc(AFilter.RegexSlotsExhausted);
    Result := False;
  end;
end;

function xeAutomationInvalidFieldRequest(const AMessage, AInvalidField: string): ExeAutomationError;
var
  lDetails: TJsonObject;
begin
  lDetails := TJsonObject.Create;
  try
    lDetails.S['invalidField'] := AInvalidField;
    Result := xeAutomationNewError(xeAutomationErrorInvalidRequest, AMessage, lDetails);
  finally
    lDetails.Free;
  end;
end;

procedure xeAutomationRejectPatternRegexConflict(const APatternField, ARegexField: string);
begin
  raise xeAutomationInvalidFieldRequest(
    Format('Automation records.apply_filter must specify only one of %s or %s per identifier', [APatternField, ARegexField]),
    ARegexField
  );
end;

function xeAutomationReadRegexFilterArg(const AArgs: TJsonObject; const AName: string; out AHasRegex: Boolean): TRegEx;
var
  lPattern: string;
begin
  AHasRegex := False;
  lPattern := xeAutomationReadStringArg(AArgs, AName);
  if lPattern = '' then
    Exit;

  try
    Result := TRegEx.Create(lPattern, [roIgnoreCase, roCompiled]);
    AHasRegex := True;
  except
    on E: Exception do
      // Regex syntax errors are request-boundary failures. Preserve the offending
      // field name in details so clients can highlight the exact input that failed.
      raise xeAutomationInvalidFieldRequest(
        Format('Automation arg "%s" is not a valid regular expression: %s', [AName, E.Message]),
        AName
      );
  end;
end;

procedure xeAutomationValidatePatternRegexPair(const AArgs: TJsonObject; const APatternField, ARegexField: string);
begin
  if (xeAutomationReadStringArg(AArgs, APatternField) <> '') and (xeAutomationReadStringArg(AArgs, ARegexField) <> '') then
    xeAutomationRejectPatternRegexConflict(APatternField, ARegexField);
end;

function xeAutomationRecordHasAncestor(const ARecord: IwbMainRecord; const AParentFormID: Cardinal): Boolean;
var
  lContainer: IwbContainer;
  lAncestor: IwbMainRecord;
  lGroup: IwbGroupRecord;
begin
  Result := False;
  if not Assigned(ARecord) then
    Exit;

  // ChildGroup-contained records are already in the flat file index; the parent
  // predicate must therefore walk the real xEdit container chain rather than rely
  // on record-list ordering or synthetic ChildGroup path text.
  lContainer := ARecord.Container;
  while Assigned(lContainer) do begin
    if Supports(lContainer, IwbMainRecord, lAncestor) then
      if lAncestor.LoadOrderFormID.ToCardinal = AParentFormID then
        Exit(True);
    if Supports(lContainer, IwbGroupRecord, lGroup) then begin
      lAncestor := lGroup.ChildrenOf;
      if Assigned(lAncestor) and (lAncestor.LoadOrderFormID.ToCardinal = AParentFormID) then
        Exit(True);
    end;
    lContainer := lContainer.Container;
  end;
end;

function xeAutomationFindMainRecordsByLoadOrderFormID(const AFormID: string; const AFileName: string): TxeAutomationMainRecordSearch;
var
  lParsedFormID: TwbFormID;
  lModules: TwbModuleInfos;
  lFile: IwbFile;
  lRecord: IwbMainRecord;
  i: Integer;
begin
  Result.Hits := nil;
  Result.Truncated := False;
  Result.MasterOrSelf := nil;
  Result.WinningOverride := nil;
  lParsedFormID := xeAutomationRequireFormID(AFormID);

  if AFileName <> '' then begin
    lFile := xeAutomationRequirePluginFile(AFileName);
    // Compact/apply workflows can return a pre-save load-order locator and then
    // reload the same plugin as light, where xEdit may expose a different public
    // load-order file slot. Reuse the locator recovery seam so file-scoped identity
    // probes stay valid across the explicit save/reload boundary.
    lRecord := xeAutomationResolveMainRecordInFile(lFile, lParsedFormID.ToString(True));
    if Assigned(lRecord) then begin
      SetLength(Result.Hits, 1);
      Result.Hits[0] := lRecord;
      Result.MasterOrSelf := lRecord.MasterOrSelf;
      Result.WinningOverride := lRecord.WinningOverride;
    end;
    Exit;
  end;

  lModules := wbModulesByLoadOrder;
  for i := Low(lModules) to High(lModules) do begin
    lFile := xeAutomationTryPluginFileFromModule(lModules[i]);
    if not Assigned(lFile) then
      Continue;

    // This search is intentionally exact and shallow: we probe each loaded plugin
    // for one concrete record with the caller's public load-order identity.
    lRecord := lFile.ContainedRecordByLoadOrderFormID[lParsedFormID, True];
    if not Assigned(lRecord) then
      Continue;

    if not Assigned(Result.MasterOrSelf) then begin
      // Any concrete hit can derive the shared record identity endpoints because
      // overrides all resolve back to the same master/winning record chain.
      Result.MasterOrSelf := lRecord.MasterOrSelf;
      Result.WinningOverride := lRecord.WinningOverride;
    end;

    // Keep FormID identity search on the same first-cut bounded surface as the
    // other record enumeration/search commands instead of returning every override.
    if Length(Result.Hits) >= xeAutomationRecordSearchLimit then begin
      Result.Truncated := True;
      Break;
    end;

    SetLength(Result.Hits, Length(Result.Hits) + 1);
    Result.Hits[High(Result.Hits)] := lRecord;
  end;
end;

function xeAutomationRequireSignature(const ASignature: string): TwbSignature;
begin
  if ASignature = '' then
    raise xeAutomationInvalidRequest('Automation arg "signature" is required');

  if Length(ASignature) <> 4 then
    raise xeAutomationInvalidRequest('Automation arg "signature" must be a 4-character record signature');

  // Signature grouping is exact-only, but automation callers commonly send the
  // same four-letter record code in mixed case. Normalize case before converting
  // so signature narrowing matches the SameText tolerance used by records.list.
  Result := StrToSignature(UpperCase(ASignature));
end;

function xeAutomationReadLimitArg(const AArgs: TJsonObject; const AName: string; const ADefault: Integer): Integer;
var
  lValue: Int64;
begin
  Result := ADefault;
  if not Assigned(AArgs) or not AArgs.Contains(AName) then
    Exit;

  case AArgs.Types[AName] of
    jdtInt,
    jdtLong,
    jdtULong:
      lValue := AArgs.L[AName];
  else
    raise xeAutomationInvalidRequest(Format('Automation arg field "%s" must be an integer', [AName]));
  end;

  if lValue < 1 then
    raise xeAutomationInvalidRequest(Format('Automation arg "%s" must be greater than zero', [AName]));

  if lValue > xeAutomationRecordSearchLimit then
    Result := xeAutomationRecordSearchLimit
  else
    Result := lValue;
end;

function xeAutomationReadSearchLimit(const AArgs: TJsonObject; const AName: string; const ADefault: Integer): Integer;
begin
  Result := xeAutomationReadLimitArg(AArgs, AName, ADefault);
end;

function xeAutomationReadChildrenLimitArg(const AArgs: TJsonObject; const AName: string; const ADefault: Integer): Integer;
var
  lValue: Int64;
begin
  Result := ADefault;
  if not Assigned(AArgs) or not AArgs.Contains(AName) then
    Exit;

  case AArgs.Types[AName] of
    jdtInt,
    jdtLong,
    jdtULong:
      lValue := AArgs.L[AName];
  else
    raise xeAutomationInvalidRequest(Format('Automation arg field "%s" must be an integer', [AName]));
  end;

  // elements.children is the only currently unbounded element-response surface.
  // Reject out-of-range page sizes instead of silently clamping so wrappers can
  // distinguish caller bugs from a valid but truncated page.
  if (lValue < 1) or (lValue > xeAutomationElementsChildrenMaxLimit) then
    raise xeAutomationInvalidRequest(Format(
      'Automation arg "%s" must be between 1 and %d for elements.children pagination',
      [AName, xeAutomationElementsChildrenMaxLimit]
    ));

  Result := Integer(lValue);
end;

function xeAutomationReadOffsetArg(const AArgs: TJsonObject; const AName: string; const ADefault: Integer): Integer;
var
  lValue: Int64;
begin
  Result := ADefault;
  if not Assigned(AArgs) or not AArgs.Contains(AName) then
    Exit;

  case AArgs.Types[AName] of
    jdtInt,
    jdtLong,
    jdtULong:
      lValue := AArgs.L[AName];
  else
    raise xeAutomationInvalidRequest(Format('Automation arg field "%s" must be an integer', [AName]));
  end;

  if lValue < 0 then
    raise xeAutomationInvalidRequest(Format('Automation arg "%s" must be greater than or equal to zero', [AName]));
  if lValue > High(Integer) then
    raise xeAutomationInvalidRequest(Format('Automation arg "%s" is out of supported integer range', [AName]));

  Result := Integer(lValue);
end;

function xeAutomationConflictAllFromName(const AName: string): TConflictAll;
begin
  if SameText(AName, 'caUnknown') then
    Exit(caUnknown);
  if SameText(AName, 'caOnlyOne') then
    Exit(caOnlyOne);
  if SameText(AName, 'caNoConflict') then
    Exit(caNoConflict);
  if SameText(AName, 'caConflictBenign') then
    Exit(caConflictBenign);
  if SameText(AName, 'caOverride') then
    Exit(caOverride);
  if SameText(AName, 'caConflict') then
    Exit(caConflict);
  if SameText(AName, 'caConflictCritical') then
    Exit(caConflictCritical);

  raise xeAutomationInvalidRequest(Format('Automation arg "conflictAll" contains an unknown conflict level: %s', [AName]));
end;

function xeAutomationConflictThisFromName(const AName: string): TConflictThis;
begin
  if SameText(AName, 'ctUnknown') then
    Exit(ctUnknown);
  if SameText(AName, 'ctIgnored') then
    Exit(ctIgnored);
  if SameText(AName, 'ctNotDefined') then
    Exit(ctNotDefined);
  if SameText(AName, 'ctIdenticalToMaster') then
    Exit(ctIdenticalToMaster);
  if SameText(AName, 'ctOnlyOne') then
    Exit(ctOnlyOne);
  if SameText(AName, 'ctHiddenByModGroup') then
    Exit(ctHiddenByModGroup);
  if SameText(AName, 'ctMaster') then
    Exit(ctMaster);
  if SameText(AName, 'ctConflictBenign') then
    Exit(ctConflictBenign);
  if SameText(AName, 'ctOverride') then
    Exit(ctOverride);
  if SameText(AName, 'ctIdenticalToMasterWinsConflict') then
    Exit(ctIdenticalToMasterWinsConflict);
  if SameText(AName, 'ctConflictWins') then
    Exit(ctConflictWins);
  if SameText(AName, 'ctConflictLoses') then
    Exit(ctConflictLoses);

  raise xeAutomationInvalidRequest(Format('Automation arg "conflictThis" contains an unknown conflict level: %s', [AName]));
end;

function xeAutomationRequirePluginFiles(const AFileNames: TStringDynArray): TxeAutomationFiles;
var
  i, j: Integer;
  lFile: IwbFile;
  lExists: Boolean;
begin
  if Length(AFileNames) = 0 then
    raise xeAutomationInvalidRequest('Automation arg "files" must contain at least one plugin name');

  Result := nil;
  for i := Low(AFileNames) to High(AFileNames) do begin
    if AFileNames[i] = '' then
      raise xeAutomationInvalidRequest('Automation arg "files" entries must be non-empty strings');

    lFile := xeAutomationRequirePluginFile(AFileNames[i]);
    lExists := False;
    for j := Low(Result) to High(Result) do
      if SameText(Result[j].FileName, lFile.FileName) then begin
        lExists := True;
        Break;
      end;

    if lExists then
      Continue;

    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := lFile;
  end;
end;

function xeAutomationReadSignatureArrayArg(const AArgs: TJsonObject; const AName: string): TwbSignatures;
var
  lValues: TStringDynArray;
  i: Integer;
begin
  lValues := xeAutomationReadStringArrayArg(AArgs, AName);
  SetLength(Result, Length(lValues));
  for i := Low(lValues) to High(lValues) do
    Result[i] := xeAutomationRequireSignature(lValues[i]);
end;

function xeAutomationReadConflictAllSetArg(const AArgs: TJsonObject; const AName: string; out AHasValue: Boolean): TConflictAllSet;
var
  lValues: TStringDynArray;
  i: Integer;
begin
  Result := [];
  AHasValue := Assigned(AArgs) and AArgs.Contains(AName);
  if not AHasValue then
    Exit;

  lValues := xeAutomationReadStringArrayArg(AArgs, AName);
  AHasValue := Length(lValues) > 0;
  for i := Low(lValues) to High(lValues) do
    Include(Result, xeAutomationConflictAllFromName(lValues[i]));
end;

function xeAutomationReadConflictThisSetArg(const AArgs: TJsonObject; const AName: string; out AHasValue: Boolean): TConflictThisSet;
var
  lValues: TStringDynArray;
  i: Integer;
begin
  Result := [];
  AHasValue := Assigned(AArgs) and AArgs.Contains(AName);
  if not AHasValue then
    Exit;

  lValues := xeAutomationReadStringArrayArg(AArgs, AName);
  AHasValue := Length(lValues) > 0;
  for i := Low(lValues) to High(lValues) do
    Include(Result, xeAutomationConflictThisFromName(lValues[i]));
end;

function xeAutomationSignatureInSet(const ASignature: TwbSignature; const ASet: TwbSignatures): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := Low(ASet) to High(ASet) do
    if SameText(ASignature, ASet[i]) then
      Exit(True);
end;

function xeAutomationReadRecordFilter(const AArgs: TJsonObject): TxeAutomationRecordFilter;
begin
  if not Assigned(AArgs) then
    raise xeAutomationInvalidRequest('Automation command args are required');

  Result.Files := xeAutomationRequirePluginFiles(xeAutomationReadStringArrayArg(AArgs, 'files'));
  Result.Signatures := xeAutomationReadSignatureArrayArg(AArgs, 'signatures');
  Result.BaseSignatures := xeAutomationReadSignatureArrayArg(AArgs, 'baseSignatures');
  Result.EditorIDPattern := xeAutomationReadStringArg(AArgs, 'editorIdPattern');
  Result.DisplayNamePattern := xeAutomationReadStringArg(AArgs, 'displayNamePattern');
  Result.FullNamePattern := xeAutomationReadStringArg(AArgs, 'fullNamePattern');
  Result.BaseEditorIDPattern := xeAutomationReadStringArg(AArgs, 'baseEditorIdPattern');
  Result.BaseDisplayNamePattern := xeAutomationReadStringArg(AArgs, 'baseDisplayNamePattern');

  xeAutomationValidatePatternRegexPair(AArgs, 'editorIdPattern', 'editorIdRegex');
  xeAutomationValidatePatternRegexPair(AArgs, 'displayNamePattern', 'displayNameRegex');
  xeAutomationValidatePatternRegexPair(AArgs, 'fullNamePattern', 'fullNameRegex');
  xeAutomationValidatePatternRegexPair(AArgs, 'baseEditorIdPattern', 'baseEditorIdRegex');
  xeAutomationValidatePatternRegexPair(AArgs, 'baseDisplayNamePattern', 'baseDisplayNameRegex');

  Result.EditorIDRegex := xeAutomationReadRegexFilterArg(AArgs, 'editorIdRegex', Result.HasEditorIDRegex);
  Result.DisplayNameRegex := xeAutomationReadRegexFilterArg(AArgs, 'displayNameRegex', Result.HasDisplayNameRegex);
  Result.FullNameRegex := xeAutomationReadRegexFilterArg(AArgs, 'fullNameRegex', Result.HasFullNameRegex);
  Result.BaseEditorIDRegex := xeAutomationReadRegexFilterArg(AArgs, 'baseEditorIdRegex', Result.HasBaseEditorIDRegex);
  Result.BaseDisplayNameRegex := xeAutomationReadRegexFilterArg(AArgs, 'baseDisplayNameRegex', Result.HasBaseDisplayNameRegex);
  Result.RegexTimeouts := 0;
  Result.RegexSlotsExhausted := 0;

  Result.HasParentFormID := xeAutomationArgPresent(AArgs, 'parentFormId');
  if Result.HasParentFormID then
    Result.ParentFormID := xeAutomationParseFormIdHex(xeAutomationRequireStringArg(AArgs, 'parentFormId'));

  // Parse the public filter contract once at the request boundary so record scans can
  // stay focused on matching real record state instead of repeating validation logic.
  Result.HasBaseFormID := Assigned(AArgs) and AArgs.Contains('baseFormId');
  if Result.HasBaseFormID then
    Result.BaseFormID := xeAutomationRequireFormID(xeAutomationRequireStringArg(AArgs, 'baseFormId'));

  Result.IsMaster := xeAutomationReadBooleanArg(AArgs, 'isMaster', Result.HasIsMaster);
  Result.IsWinningOverride := xeAutomationReadBooleanArg(AArgs, 'isWinningOverride', Result.HasIsWinningOverride);
  Result.IsDeleted := xeAutomationReadBooleanArg(AArgs, 'isDeleted', Result.HasIsDeleted);
  Result.IsInjected := xeAutomationReadBooleanArg(AArgs, 'isInjected', Result.HasIsInjected);
  Result.ConflictAll := xeAutomationReadConflictAllSetArg(AArgs, 'conflictAll', Result.UseConflictAll);
  Result.ConflictThis := xeAutomationReadConflictThisSetArg(AArgs, 'conflictThis', Result.UseConflictThis);
  Result.Limit := xeAutomationReadLimitArg(AArgs, 'limit', xeAutomationRecordSearchLimit);
end;

function xeAutomationRecordMatchesFilter(const ARecord: IwbMainRecord; var AFilter: TxeAutomationRecordFilter): Boolean;
var
  lBaseRecord: IwbMainRecord;
begin
  Result := False;
  if not Assigned(ARecord) then
    Exit;

  if (Length(AFilter.Signatures) > 0) and not xeAutomationSignatureInSet(ARecord.Signature, AFilter.Signatures) then
    Exit;
  if AFilter.HasParentFormID and not xeAutomationRecordHasAncestor(ARecord, AFilter.ParentFormID) then
    Exit;
  if (AFilter.EditorIDPattern <> '') and ((not ARecord.CanHaveEditorID) or not xeAutomationGlobMatchesCI(ARecord.EditorID, AFilter.EditorIDPattern)) then
    Exit;
  if (AFilter.DisplayNamePattern <> '') and not xeAutomationGlobMatchesCI(ARecord.DisplayName[True], AFilter.DisplayNamePattern) then
    Exit;
  if (AFilter.FullNamePattern <> '') and ((not ARecord.CanHaveFullName) or not xeAutomationGlobMatchesCI(ARecord.FullName, AFilter.FullNamePattern)) then
    Exit;
  if AFilter.HasIsMaster and (ARecord.IsMaster <> AFilter.IsMaster) then
    Exit;
  if AFilter.HasIsWinningOverride and (ARecord.IsWinningOverride <> AFilter.IsWinningOverride) then
    Exit;
  if AFilter.HasIsDeleted and (ARecord.IsDeleted <> AFilter.IsDeleted) then
    Exit;
  if AFilter.HasIsInjected and (ARecord.IsInjected <> AFilter.IsInjected) then
    Exit;
  if AFilter.UseConflictAll and not (ARecord.ConflictAll in AFilter.ConflictAll) then
    Exit;
  if AFilter.UseConflictThis and not (ARecord.ConflictThis in AFilter.ConflictThis) then
    Exit;
  if AFilter.HasEditorIDRegex and ((not ARecord.CanHaveEditorID) or not xeAutomationRegexFieldMatches(AFilter.EditorIDRegex, ARecord.EditorID, AFilter)) then
    Exit;
  if AFilter.HasDisplayNameRegex and not xeAutomationRegexFieldMatches(AFilter.DisplayNameRegex, ARecord.DisplayName[True], AFilter) then
    Exit;
  if AFilter.HasFullNameRegex and ((not ARecord.CanHaveFullName) or not xeAutomationRegexFieldMatches(AFilter.FullNameRegex, ARecord.FullName, AFilter)) then
    Exit;

  if (Length(AFilter.BaseSignatures) > 0) or AFilter.HasBaseFormID or (AFilter.BaseEditorIDPattern <> '') or (AFilter.BaseDisplayNamePattern <> '') or AFilter.HasBaseEditorIDRegex or AFilter.HasBaseDisplayNameRegex then begin
    // Base-record predicates must resolve the real linked base record; matching the
    // summarized output text would silently diverge from xEdit's actual filter logic.
    if not ARecord.CanHaveBaseRecord or not Supports(ARecord.BaseRecord, IwbMainRecord, lBaseRecord) then
      Exit;

    if (Length(AFilter.BaseSignatures) > 0) and not xeAutomationSignatureInSet(lBaseRecord.Signature, AFilter.BaseSignatures) then
      Exit;
    if AFilter.HasBaseFormID and (lBaseRecord.LoadOrderFormID <> AFilter.BaseFormID) then
      Exit;
    if (AFilter.BaseEditorIDPattern <> '') and ((not lBaseRecord.CanHaveEditorID) or not xeAutomationGlobMatchesCI(lBaseRecord.EditorID, AFilter.BaseEditorIDPattern)) then
      Exit;
    if (AFilter.BaseDisplayNamePattern <> '') and not xeAutomationGlobMatchesCI(lBaseRecord.DisplayName[True], AFilter.BaseDisplayNamePattern) then
      Exit;
    if AFilter.HasBaseEditorIDRegex and ((not lBaseRecord.CanHaveEditorID) or not xeAutomationRegexFieldMatches(AFilter.BaseEditorIDRegex, lBaseRecord.EditorID, AFilter)) then
      Exit;
    if AFilter.HasBaseDisplayNameRegex and not xeAutomationRegexFieldMatches(AFilter.BaseDisplayNameRegex, lBaseRecord.DisplayName[True], AFilter) then
      Exit;
  end;

  Result := True;
end;

procedure xeAutomationAddBoundedRecordHit(var ASearch: TxeAutomationBoundedMainRecordSearch; const ARecord: IwbMainRecord);
var
  lHitCount: Integer;
begin
  lHitCount := Length(ASearch.Hits);
  if lHitCount >= xeAutomationRecordSearchLimit then begin
    ASearch.Truncated := True;
    Exit;
  end;

  SetLength(ASearch.Hits, lHitCount + 1);
  ASearch.Hits[lHitCount] := ARecord;
end;

function xeAutomationSameRecordLocator(const ALeft, ARight: IwbMainRecord): Boolean;
begin
  Result := Assigned(ALeft) and Assigned(ARight)
    and SameText(ALeft._File.FileName, ARight._File.FileName)
    and (ALeft.LoadOrderFormID = ARight.LoadOrderFormID);
end;

procedure xeAutomationAddUniqueRecordHit(var ASearch: TxeAutomationBoundedMainRecordSearch; const ARecord: IwbMainRecord; const ALimit: Integer);
var
  i: Integer;
begin
  if not Assigned(ARecord) then
    Exit;

  for i := Low(ASearch.Hits) to High(ASearch.Hits) do
    if xeAutomationSameRecordLocator(ASearch.Hits[i], ARecord) then
      Exit;

  // Relationship commands promise unique root-record hits, so dedupe on the public
  // locator shape before enforcing the caller's limit/truncated contract.
  if Length(ASearch.Hits) >= ALimit then begin
    ASearch.Truncated := True;
    Exit;
  end;

  SetLength(ASearch.Hits, Length(ASearch.Hits) + 1);
  ASearch.Hits[High(ASearch.Hits)] := ARecord;
end;

procedure xeAutomationCollectOutgoingReferencesRecursive(const AElement: IwbElement; var ASearch: TxeAutomationBoundedMainRecordSearch; const ALimit: Integer);
var
  lLinkedElement: IwbElement;
  lContainer: IwbContainer;
  i: Integer;
begin
  if not Assigned(AElement) or ASearch.Truncated or not AElement.CanContainFormIDs then
    Exit;

  lLinkedElement := AElement.LinksTo;
  if Assigned(lLinkedElement) then
    xeAutomationAddUniqueRecordHit(ASearch, lLinkedElement.ContainingMainRecord, ALimit);
  if ASearch.Truncated then
    Exit;

  // Walk the full container subtree, not only multi-element views, so outgoing
  // references are collected from the same record-root tree that xEdit exposes.
  if Supports(AElement, IwbContainer, lContainer) then
    for i := 0 to Pred(lContainer.ElementCount) do begin
      xeAutomationCollectOutgoingReferencesRecursive(lContainer.Elements[i], ASearch, ALimit);
      if ASearch.Truncated then
        Exit;
    end;
end;

function xeAutomationCollectOutgoingReferences(const ARecord: IwbMainRecord; const ALimit: Integer;
  const ARecursive: Boolean): TxeAutomationBoundedMainRecordSearch;
var
  lChildren: TDynMainRecords;
  i: Integer;
begin
  Result.Hits := nil;
  Result.Truncated := False;
  Result.RegexTimeouts := 0;
  Result.RegexSlotsExhausted := 0;
  xeAutomationCollectOutgoingReferencesRecursive(ARecord, Result, ALimit);

  if not ARecursive or Result.Truncated or not Assigned(ARecord.ChildGroup) or (ARecord.ChildGroup.ElementCount = 0) then
    Exit;

  // ChildGroup-owned records are not part of the parent record's element subtree.
  // Reuse xEdit's canonical sibling walker, then collect each child record shallowly
  // so recursive:true expands the same semantic children that the GUI tree exposes.
  lChildren := wbGetSiblingRecords(ARecord, wbStringToSignatures(xeAutomationChildGroupReferenceSignatures), True);
  for i := Low(lChildren) to High(lChildren) do begin
    xeAutomationCollectOutgoingReferencesRecursive(lChildren[i], Result, ALimit);
    if Result.Truncated then
      Exit;
  end;
end;

function xeAutomationCollectReferencedByRecords(const ARecord: IwbMainRecord; const ALimit: Integer): TxeAutomationBoundedMainRecordSearch;
var
  i: Integer;
begin
  Result.Hits := nil;
  Result.Truncated := False;
  Result.RegexTimeouts := 0;
  Result.RegexSlotsExhausted := 0;

  for i := 0 to Pred(ARecord.ReferencedByCount) do begin
    xeAutomationAddUniqueRecordHit(Result, ARecord.ReferencedBy[i], ALimit);
    if Result.Truncated then
      Exit;
  end;
end;

function xeAutomationFilterMainRecords(const AArgs: TJsonObject): TxeAutomationBoundedMainRecordSearch;
var
  lFilter: TxeAutomationRecordFilter;
  lFile: IwbFile;
  lRecord: IwbMainRecord;
  i, j: Integer;
begin
  Result.Hits := nil;
  Result.Truncated := False;
  Result.RegexTimeouts := 0;
  Result.RegexSlotsExhausted := 0;
  lFilter := xeAutomationReadRecordFilter(AArgs);

  for i := Low(lFilter.Files) to High(lFilter.Files) do begin
    lFile := lFilter.Files[i];
    for j := 0 to Pred(lFile.RecordCount) do begin
      if not Supports(lFile.Records[j], IwbMainRecord, lRecord) then
        Continue;
      if not xeAutomationRecordMatchesFilter(lRecord, lFilter) then
        Continue;

      // Apply Filter is intentionally file-scoped and shallow: it streams matching
      // root records and reports truncation instead of materializing a deeper tree.
      if Length(Result.Hits) >= lFilter.Limit then begin
        Result.Truncated := True;
        Result.RegexTimeouts := lFilter.RegexTimeouts;
        Result.RegexSlotsExhausted := lFilter.RegexSlotsExhausted;
        Exit;
      end;

      xeAutomationAddBoundedRecordHit(Result, lRecord);
      if Result.Truncated then
      begin
        Result.RegexTimeouts := lFilter.RegexTimeouts;
        Result.RegexSlotsExhausted := lFilter.RegexSlotsExhausted;
        Exit;
      end;
    end;
  end;
  Result.RegexTimeouts := lFilter.RegexTimeouts;
  Result.RegexSlotsExhausted := lFilter.RegexSlotsExhausted;
end;

function xeAutomationFindMainRecordsByEditorID(const AEditorID: string; const ASignature: string): TxeAutomationBoundedMainRecordSearch;
var
  lModules: TwbModuleInfos;
  lFile: IwbFile;
  lGroup: IwbGroupRecord;
  lRecord: IwbMainRecord;
  lSignature: TwbSignature;
  lUseSignature: Boolean;
  i, j: Integer;
begin
  Result.Hits := nil;
  Result.Truncated := False;
  Result.RegexTimeouts := 0;
  Result.RegexSlotsExhausted := 0;

  if AEditorID = '' then
    raise xeAutomationInvalidRequest('Automation arg "editorId" is required');

  lUseSignature := ASignature <> '';
  if lUseSignature then
    lSignature := xeAutomationRequireSignature(ASignature);

  lModules := wbModulesByLoadOrder;
  for i := Low(lModules) to High(lModules) do begin
    lFile := xeAutomationTryPluginFileFromModule(lModules[i]);
    if not Assigned(lFile) then
      Continue;

    if lUseSignature then begin
      // When the caller gives a concrete signature, keep the search exact and cheap
      // by using the file's signature group plus exact EditorID lookup only.
      lGroup := lFile.GroupBySignature[lSignature];
      if not Assigned(lGroup) then
        Continue;

      lRecord := lGroup.MainRecordByEditorID[AEditorID];
      if Assigned(lRecord) and SameText(lRecord.EditorID, AEditorID) then
        xeAutomationAddBoundedRecordHit(Result, lRecord);
    end else begin
      // Signature-free lookup is still exact-only, but it must scan loaded records
      // because we are intentionally not broadening this into a generalized query API.
      for j := 0 to Pred(lFile.RecordCount) do begin
        if not Supports(lFile.Records[j], IwbMainRecord, lRecord) then
          Continue;
        if not lRecord.CanHaveEditorID then
          Continue;
        if not SameText(lRecord.EditorID, AEditorID) then
          Continue;

        xeAutomationAddBoundedRecordHit(Result, lRecord);
        if Result.Truncated then
          Break;
      end;
    end;

    if Result.Truncated then
      Break;
  end;
end;

procedure xeAutomationAddNewMainRecordInFile(const AFile: IwbFile; const ARecord: IwbMainRecord;
  const ASeenRecords: TDictionary<Cardinal, Boolean>; var ARecords: TxeAutomationMainRecords);
begin
  if not Assigned(AFile) or not Assigned(ARecord) or (ARecord = AFile.Header) then
    Exit;

  if ARecord.LoadOrderFormID.FileID <> AFile.LoadOrderFileID then
    Exit;

  if ASeenRecords.ContainsKey(ARecord.LoadOrderFormID.ToCardinal) then
    Exit;
  ASeenRecords.Add(ARecord.LoadOrderFormID.ToCardinal, True);

  SetLength(ARecords, Succ(Length(ARecords)));
  ARecords[High(ARecords)] := ARecord;
end;

procedure xeAutomationCollectNewMainRecordsFromElement(const AFile: IwbFile; const AElement: IwbElement;
  const ASeenRecords: TDictionary<Cardinal, Boolean>; var ARecords: TxeAutomationMainRecords);
var
  lRecord: IwbMainRecord;
  lContainer: IwbContainer;
  i: Integer;
begin
  if not Assigned(AElement) then
    Exit;

  if Supports(AElement, IwbMainRecord, lRecord) then
    xeAutomationAddNewMainRecordInFile(AFile, lRecord, ASeenRecords, ARecords);

  if Supports(AElement, IwbContainer, lContainer) then
    for i := 0 to Pred(lContainer.ElementCount) do
      xeAutomationCollectNewMainRecordsFromElement(AFile, lContainer.Elements[i], ASeenRecords, ARecords);
end;

function xeAutomationCollectNewMainRecordsInFile(const AFile: IwbFile): TxeAutomationMainRecords;
var
  lSeenRecords: TDictionary<Cardinal, Boolean>;
  i: Integer;
begin
  SetLength(Result, 0);
  if not Assigned(AFile) then
    Exit;

  lSeenRecords := TDictionary<Cardinal, Boolean>.Create;
  try
    // Compact/apply jobs need the same live in-memory record view used by analysis:
    // newly-created automation records can sit under GRUP containers before save.
    xeAutomationCollectNewMainRecordsFromElement(AFile, AFile, lSeenRecords, Result);
    for i := 0 to Pred(AFile.RecordCount) do
      xeAutomationAddNewMainRecordInFile(AFile, AFile.Records[i], lSeenRecords, Result);
  finally
    lSeenRecords.Free;
  end;
end;

function xeAutomationResolveMainRecordInFile(const AFile: IwbFile; const AFormID: string): IwbMainRecord;
var
  lParsedFormID: TwbFormID;
begin
  if not Assigned(AFile) then
    Exit(nil);

  lParsedFormID := xeAutomationRequireFormID(AFormID);

  // Automation responses now round-trip public load-order FormIDs, so read-side
  // lookup must prefer the file-level load-order seam before any compatibility path.
  Result := AFile.ContainedRecordByLoadOrderFormID[lParsedFormID, True];
  if Assigned(Result) then
    Exit;

  // Keep temporary compatibility for callers that still send the older file-local
  // FormID shape until the addressing migration removes that legacy locator input.
  Result := AFile.RecordByFormID[lParsedFormID, True, True];
end;

function xeAutomationMainRecordBelongsToFile(const ARecord: IwbMainRecord; const AFile: IwbFile): Boolean;
begin
  Result := Assigned(ARecord) and Assigned(AFile) and Assigned(ARecord._File)
    and SameText(ARecord._File.FileName, AFile.FileName);
end;

function xeAutomationResolveOwnedMainRecordInFile(const AFile: IwbFile; const AFormID: string): IwbMainRecord;
var
  lParsedFormID: TwbFormID;
begin
  if not Assigned(AFile) then
    Exit(nil);

  lParsedFormID := xeAutomationRequireFormID(AFormID);

  // Mutation/existence checks must answer "does this addressed file itself own the
  // record?" Master-walking compatibility lookup is allowed only after rejecting
  // any result that xEdit resolved from a required master instead of the target file.
  Result := AFile.ContainedRecordByLoadOrderFormID[lParsedFormID, True];
  if xeAutomationMainRecordBelongsToFile(Result, AFile) then
    Exit;

  Result := AFile.RecordByFormID[lParsedFormID, True, True];
  if not xeAutomationMainRecordBelongsToFile(Result, AFile) then
    Result := nil;
end;

function xeAutomationRequireMainRecord(const ALocator: TxeAutomationLocator): IwbMainRecord;
var
  lFile: IwbFile;
begin
  lFile := xeAutomationRequirePluginFile(ALocator.FileName);
  Result := xeAutomationResolveMainRecordInFile(lFile, ALocator.FormID);
  if not Assigned(Result) then
    raise xeAutomationRecordNotFound(ALocator.FileName, ALocator.FormID);
end;

function xeAutomationRequireOwnedMainRecord(const ALocator: TxeAutomationLocator): IwbMainRecord;
var
  lFile: IwbFile;
begin
  lFile := xeAutomationRequirePluginFile(ALocator.FileName);
  Result := xeAutomationResolveOwnedMainRecordInFile(lFile, ALocator.FormID);
  if not Assigned(Result) then
    raise xeAutomationRecordNotFound(ALocator.FileName, ALocator.FormID);
end;

function xeAutomationPathStartsWithChildGroupPrefix(const APath: string): Boolean;
var
  L: Integer;
begin
  Result := False;
  L := Length(xeAutomationChildGroupPathPrefix);
  if Length(APath) < L then
    Exit;
  if not StartsText(xeAutomationChildGroupPathPrefix, APath) then
    Exit;
  if Length(APath) = L then begin
    Result := True;
    Exit;
  end;
  Result := (APath[L + 1] = '\');
end;

function xeAutomationEncodeGridLabel(const AX, AY: SmallInt): Cardinal;
var
  lLabel: LongRecSmall;
begin
  lLabel.Lo := AY;
  lLabel.Hi := AX;
  Move(lLabel, Result, SizeOf(Result));
end;

function xeAutomationTryParseGridLabel(const ALabel: string; out AX, AY: SmallInt): Boolean;
var
  lCommaPos: Integer;
  lXValue: Integer;
  lYValue: Integer;
begin
  Result := False;
  AX := 0;
  AY := 0;

  lCommaPos := Pos(',', ALabel);
  if lCommaPos < 1 then
    Exit;

  if not TryStrToInt(Trim(Copy(ALabel, 1, lCommaPos - 1)), lXValue) then
    Exit;
  if not TryStrToInt(Trim(Copy(ALabel, lCommaPos + 1, MaxInt)), lYValue) then
    Exit;
  if (lXValue < Low(SmallInt)) or (lXValue > High(SmallInt)) or
     (lYValue < Low(SmallInt)) or (lYValue > High(SmallInt)) then
    Exit;

  AX := SmallInt(lXValue);
  AY := SmallInt(lYValue);
  Result := True;
end;

function xeAutomationFindGroupByTypeAndLabel(
  const AParentGroup: IwbGroupRecord;
  const AGroupType: Integer;
  const AGroupLabel: Cardinal): IwbGroupRecord;
var
  lContainer: IwbContainerElementRef;
  lGroup: IwbGroupRecord;
  i: Integer;
begin
  Result := nil;
  if not Assigned(AParentGroup) then
    Exit;
  if not Supports(AParentGroup, IwbContainerElementRef, lContainer) then
    Exit;

  for i := 0 to Pred(lContainer.ElementCount) do
    if Supports(lContainer.Elements[i], IwbGroupRecord, lGroup) and
       (lGroup.GroupType = AGroupType) and
       (lGroup.GroupLabel = AGroupLabel) then
      Exit(lGroup);
end;

function xeAutomationFindBlockGroup(
  const AParentGroup: IwbGroupRecord;
  const AX, AY: SmallInt): IwbGroupRecord;
begin
  Result := xeAutomationFindGroupByTypeAndLabel(AParentGroup, 4, xeAutomationEncodeGridLabel(AX, AY));
end;

function xeAutomationFindBlockGroupByLabel(
  const AParentGroup: IwbGroupRecord;
  const ALabel: string): IwbGroupRecord;
var
  lX: SmallInt;
  lY: SmallInt;
begin
  Result := nil;
  if xeAutomationTryParseGridLabel(ALabel, lX, lY) then
    Result := xeAutomationFindBlockGroup(AParentGroup, lX, lY);
end;

function xeAutomationFindPersistentWorldCell(const AWorldChildGroup: IwbGroupRecord): IwbMainRecord;
var
  lContainer: IwbContainerElementRef;
  lRecord: IwbMainRecord;
  i: Integer;
begin
  Result := nil;
  if not Assigned(AWorldChildGroup) then
    Exit;
  if not Supports(AWorldChildGroup, IwbContainerElementRef, lContainer) then
    Exit;

  // A WRLD persistent cell is a direct CELL main record in the world ChildGroup;
  // it is not contained by the exterior Block/Sub-Block GRUP hierarchy.
  for i := 0 to Pred(lContainer.ElementCount) do
    if Supports(lContainer.Elements[i], IwbMainRecord, lRecord) and
       SameText(lRecord.Signature, 'CELL') and lRecord.IsPersistent then
      Exit(lRecord);
end;

function xeAutomationFindSubBlockByLabel(
  const AParentGroup: IwbGroupRecord;
  const ALabel: string): IwbGroupRecord;
var
  lX: SmallInt;
  lY: SmallInt;
begin
  Result := nil;
  if xeAutomationTryParseGridLabel(ALabel, lX, lY) then
    Result := xeAutomationFindGroupByTypeAndLabel(AParentGroup, 5, xeAutomationEncodeGridLabel(lX, lY));
end;

function xeAutomationResolveChildGroupRemainder(
  const ASubGroup: IwbGroupRecord;
  const ARemainder: string): IwbElement;
var
  lContainer: IwbContainerElementRef;
  lFirstSegment: string;
  lRest: string;
  lSeparatorPos: Integer;
  lSubBlock: IwbGroupRecord;
begin
  Result := nil;
  if not Assigned(ASubGroup) or (ARemainder = '') then
    Exit;

  lSeparatorPos := Pos('\', ARemainder);
  if lSeparatorPos = 0 then begin
    lFirstSegment := ARemainder;
    lRest := '';
  end else begin
    lFirstSegment := Copy(ARemainder, 1, lSeparatorPos - 1);
    lRest := Copy(ARemainder, lSeparatorPos + 1, MaxInt);
  end;

  if SameText(Copy(lFirstSegment, 1, Length('Sub-Block ')), 'Sub-Block ') then begin
    lSubBlock := xeAutomationFindSubBlockByLabel(ASubGroup, Copy(lFirstSegment, Length('Sub-Block ') + 1, MaxInt));
    if not Assigned(lSubBlock) then
      Exit;
    if lRest = '' then
      Exit(lSubBlock);
    if Supports(lSubBlock, IwbContainerElementRef, lContainer) then
      Result := lContainer.ElementByPath[lRest];
    Exit;
  end;

  if Supports(ASubGroup, IwbContainerElementRef, lContainer) then
    Result := lContainer.ElementByPath[ARemainder];
end;

function xeAutomationFindLabeledSubGroup(
  const AParentGroup: IwbGroupRecord;
  const AOwnerRecord: IwbMainRecord;
  const ALabel: string): IwbElement;
begin
  Result := nil;
  if not Assigned(AParentGroup) or not Assigned(AOwnerRecord) then
    Exit;

  if SameText(AOwnerRecord.Signature, 'CELL') then begin
    if SameText(ALabel, 'Persistent') then
      Exit(AParentGroup.FindChildGroup(8, AOwnerRecord));
    if SameText(ALabel, 'Temporary') then
      Exit(AParentGroup.FindChildGroup(9, AOwnerRecord));
    if SameText(ALabel, 'Visible when Distant') then
      Exit(AParentGroup.FindChildGroup(10, AOwnerRecord));
    Exit;
  end;

  if SameText(AOwnerRecord.Signature, 'WRLD') then begin
    if SameText(ALabel, 'Persistent') then
      Exit(xeAutomationFindPersistentWorldCell(AParentGroup));
    if SameText(Copy(ALabel, 1, Length('Block ')), 'Block ') then
      Exit(xeAutomationFindBlockGroupByLabel(AParentGroup, Copy(ALabel, Length('Block ') + 1, MaxInt)));
  end;
end;

function xeAutomationResolveChildGroupPath(const ARecord: IwbMainRecord; const APath: string): IwbElement;
var
  lChildGroup: IwbGroupRecord;
  lContainer: IwbContainerElementRef;
  lFirstSegment: string;
  lRemainder: string;
  lResolvedElement: IwbElement;
  lSeparatorPos: Integer;
  lSubGroup: IwbGroupRecord;
  lTrimmedPath: string;
begin
  Result := nil;
  if not Assigned(ARecord) then
    Exit;

  lChildGroup := ARecord.ChildGroup;
  if not Assigned(lChildGroup) then
    Exit;

  lTrimmedPath := APath;
  if (lTrimmedPath <> '') and (lTrimmedPath[1] = '\') then
    Delete(lTrimmedPath, 1, 1);
  if lTrimmedPath = '' then
    Exit(lChildGroup);

  lSeparatorPos := Pos('\', lTrimmedPath);
  if lSeparatorPos = 0 then begin
    lFirstSegment := lTrimmedPath;
    lRemainder := '';
  end else begin
    lFirstSegment := Copy(lTrimmedPath, 1, lSeparatorPos - 1);
    lRemainder := Copy(lTrimmedPath, lSeparatorPos + 1, MaxInt);
  end;

  lResolvedElement := xeAutomationFindLabeledSubGroup(lChildGroup, ARecord, lFirstSegment);
  if Assigned(lResolvedElement) then begin
    if lRemainder = '' then
      Exit(lResolvedElement);
    if Supports(lResolvedElement, IwbGroupRecord, lSubGroup) then
      Exit(xeAutomationResolveChildGroupRemainder(lSubGroup, lRemainder));
    if Supports(lResolvedElement, IwbContainerElementRef, lContainer) then
      Exit(lContainer.ElementByPath[lRemainder]);
    Exit;
  end;

  if Supports(lChildGroup, IwbContainerElementRef, lContainer) then
    Result := lContainer.ElementByPath[lTrimmedPath];
end;

function xeAutomationRequireElement(const ALocator: TxeAutomationLocator; out ARecord: IwbMainRecord): IwbElement;
var
  lAfterPrefix: string;
begin
  ARecord := xeAutomationRequireMainRecord(ALocator);

  // Elements are addressed relative to the located main record. An empty path means
  // "the record root", which keeps record-root traversal on the same locator shape.
  if ALocator.Path = '' then
    Exit(ARecord);

  // Phase 15A: ChildGroup path-prefix dispatch handles a sibling GRUP, not a
  // normal record element; all other paths preserve existing ElementByPath behavior.
  if xeAutomationPathStartsWithChildGroupPrefix(ALocator.Path) then begin
    lAfterPrefix := Copy(ALocator.Path, Length(xeAutomationChildGroupPathPrefix) + 1, MaxInt);
    Result := xeAutomationResolveChildGroupPath(ARecord, lAfterPrefix);
    if not Assigned(Result) then
      raise xeAutomationElementNotFound(ALocator.FileName, ALocator.FormID, ALocator.Path);
    Exit;
  end;

  Result := ARecord.ElementByPath[ALocator.Path];
  if not Assigned(Result) then
    raise xeAutomationElementNotFound(ALocator.FileName, ALocator.FormID, ALocator.Path);
end;

function xeAutomationRequireOwnedElement(const ALocator: TxeAutomationLocator; out ARecord: IwbMainRecord): IwbElement;
begin
  ARecord := xeAutomationRequireOwnedMainRecord(ALocator);

  // Strict owned lookup is for mutation targets: callers may still use the legacy
  // file-local FormID compatibility shape, but not a master record reached through it.
  if ALocator.Path = '' then
    Exit(ARecord);

  // Synthetic ChildGroup locators are navigation breadcrumbs only. Mutation verbs
  // must re-enter through the flat FormID locator emitted for the resolved record,
  // otherwise response envelopes can imply the original parent record was mutated.
  if xeAutomationPathStartsWithChildGroupPrefix(ALocator.Path) then
    raise xeAutomationInvalidTarget(
      'Synthetic ChildGroup paths are read-only; mutate through the resolved record''s FormID locator');

  Result := ARecord.ElementByPath[ALocator.Path];
  if not Assigned(Result) then
    raise xeAutomationElementNotFound(ALocator.FileName, ALocator.FormID, ALocator.Path);
end;

initialization
  // Regex timeout workers may outlive the request that spawned them; keep this
  // tiny coordination object process-lifetime so late slot releases stay safe.
  xeAutomationRegexTaskLock := TObject.Create;

end.
