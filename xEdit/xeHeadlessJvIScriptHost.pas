{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeHeadlessJvIScriptHost;

interface

uses
  JsonDataObjects,
  Types;

const
  xeHeadlessScriptErrorBusy = 'script_busy';
  xeHeadlessScriptErrorFailed = 'script_failed';
  xeHeadlessScriptErrorTimeout = 'script_timeout';
  xeHeadlessScriptErrorStatementBudgetExceeded = 'script_statement_budget_exceeded';
  xeHeadlessScriptErrorPolicyPreflight = 'script_policy_preflight';
  xeHeadlessScriptErrorException = 'script_exception';

type
  TxeHeadlessScriptRunOptions = record
    // EntryScriptPath is expected to have been canonicalized by the request layer;
    // this host still treats it as untrusted for unit-source sibling resolution.
    EntryScriptPath: string;
    Targets: TJsonArray;
    TimeoutMS: Cardinal;
    StatementBudget: Cardinal;
  end;

  TxeHeadlessScriptRunResult = record
    Success: Boolean;
    ErrorCode: string;
    ErrorMessage: string;
    BusyHolder: string;
    ScriptLastPhase: string;
    ScriptFailed: Boolean;
    ScriptFailureCode: string;
    ScriptFailureMessage: string;
    ExternalDeclarationDenied: Boolean;
    ScriptFailureUnitName: string;
    ScriptFailureLine: Integer;
    PolicyPreflightLine: Integer;
    PolicyPreflightColumn: Integer;
    ProcessedTargetCount: Integer;
    Messages: TStringDynArray;
    MessagesTruncated: Boolean;
    DirtyState: TJsonObject; // caller owns
  end;

function xeHeadlessRunScript(const AOptions: TxeHeadlessScriptRunOptions): TxeHeadlessScriptRunResult;

implementation

uses
  Classes,
  SysUtils,
  StrUtils,
  Variants,
  Windows,
  JvInterpreter,
  wbInterface,
  wbLoadOrder,
  xeAutomationDataLookup,
  xeAutomationErrors,
  xeAutomationObjectModel,
  xeInit,
  xeScriptExecutionGuard,
  xeScriptLint,
  xeScriptRuntimePolicy;

const
  xeHeadlessMessageMaxBytes = 1024 * 1024;
  xeHeadlessMessageMaxLines = 5000;

type
  TxeHeadlessTargetElements = array of IwbElement;

  TxeHeadlessJvIHost = class
  private
    FOptions: TxeHeadlessScriptRunOptions;
    FResult: TxeHeadlessScriptRunResult;
    FProgram: TJvInterpreterProgram;
    FMessages: TStringList;
    FMessageBytes: Integer;
    FStartTick: UInt64;
    FEntryScriptDir: string;
    FAgentScriptsDir: string;
    FEntryScriptUnderAgentRoot: Boolean;
    FTargets: TxeHeadlessTargetElements;
    FFiles: TwbFiles;
    procedure AddCapturedMessage(const AMessage: string);
    procedure CallScriptFunction(const AName: string; const AParams: array of Variant);
    procedure CacheLoadedFiles;
    procedure FailScript(const ACode, AMessage: string);
    procedure JvInterpreterProgramGetValue(Sender: TObject; Identifier: string; var Value: Variant;
      Args: TJvInterpreterArgs; var Done: Boolean);
    procedure JvInterpreterProgramGetUnitSource(UnitName: string; var Source: string; var Done: Boolean);
    procedure JvInterpreterProgramStatement(Sender: TObject);
    procedure ResolveTargets;
    function BuildDirtyState: TJsonObject;
    function LastErrorLocation: string;
    function LoadUnitSourceFrom(const ADirectory, AUnitName: string; out ASource: string): Boolean;
    function Run: TxeHeadlessScriptRunResult;
  public
    constructor Create(const AOptions: TxeHeadlessScriptRunOptions);
    destructor Destroy; override;
  end;

  PUnitInfo = ^TUnitInfo;
  TUnitInfo = record
    UnitName: string;
    Found: PBoolean;
  end;

function xeHeadlessPolicyAllowsCall(const ACalledSymbol: string): Boolean;
begin
  // Script-local declarations are removed by the lint scanner's first pass; this
  // callback supplies the process-wide ledger/host/language side of the decision.
  Result := xeScriptPolicyIsAllowedCall(ACalledSymbol, nil);
end;

function xeUtf8PrefixByByteBudget(const AValue: string; const AMaxBytes: Integer): string;
var
  lBytes: Integer;
  lChar: string;
  lCharBytes: Integer;
  i: Integer;
begin
  Result := '';
  lBytes := 0;
  for i := 1 to Length(AValue) do begin
    lChar := AValue[i];
    lCharBytes := TEncoding.UTF8.GetByteCount(lChar);
    if lBytes + lCharBytes > AMaxBytes then
      Break;
    Result := Result + lChar;
    Inc(lBytes, lCharBytes);
  end;
end;

function xePathIsUnderDirectory(const APath, ADirectory: string): Boolean;
var
  lPath: string;
  lDirectory: string;
begin
  lPath := ExpandFileName(APath);
  lDirectory := IncludeTrailingPathDelimiter(ExpandFileName(ADirectory));
  Result := StartsText(lDirectory, lPath);
end;

function xeIsSafeUnitName(const AUnitName: string): Boolean;
var
  i: Integer;
begin
  Result := AUnitName <> '';
  for i := 1 to Length(AUnitName) do
    if not CharInSet(AUnitName[i], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) then
      Exit(False);
end;

procedure HasUnitProc(const Name: string; NameType: TNameType; Flags: Byte; Param: Pointer);
var
  s: string;
begin
  case NameType of
    ntContainsUnit:
      with PUnitInfo(Param)^ do begin
        s := Name;
        s := StringReplace(s, 'system.', '', [rfReplaceAll, rfIgnoreCase]);
        s := StringReplace(s, 'vcl.', '', [rfReplaceAll, rfIgnoreCase]);
        s := StringReplace(s, 'winapi.', '', [rfReplaceAll, rfIgnoreCase]);
        s := StringReplace(s, 'data.', '', [rfReplaceAll, rfIgnoreCase]);
        s := StringReplace(s, 'web.', '', [rfReplaceAll, rfIgnoreCase]);
        if SameText(s, UnitName) then
          Found^ := True;
      end;
  end;
end;

function IsUnitCompiledIn(Module: HMODULE; const UnitName: string): Boolean;
var
  Info: TUnitInfo;
  Flags: Integer;
begin
  Result := False;
  Info.UnitName := UnitName;
  Info.Found := @Result;
  GetPackageInfo(Module, @Info, Flags, HasUnitProc);
end;

constructor TxeHeadlessJvIHost.Create(const AOptions: TxeHeadlessScriptRunOptions);
begin
  inherited Create;
  FOptions := AOptions;
  FMessages := TStringList.Create;
  FResult.ScriptLastPhase := 'queued';
  FEntryScriptDir := IncludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(FOptions.EntryScriptPath)));
  FAgentScriptsDir := IncludeTrailingPathDelimiter(ExpandFileName(wbScriptsPath + 'Agent'));
  FEntryScriptUnderAgentRoot := xePathIsUnderDirectory(FOptions.EntryScriptPath, FAgentScriptsDir);
end;

destructor TxeHeadlessJvIHost.Destroy;
begin
  FreeAndNil(FProgram);
  FreeAndNil(FMessages);
  inherited;
end;

procedure TxeHeadlessJvIHost.AddCapturedMessage(const AMessage: string);
var
  lBytes: Integer;
  lRemaining: Integer;
  lStored: string;
begin
  if FResult.MessagesTruncated then
    Exit;

  if FMessages.Count >= xeHeadlessMessageMaxLines then begin
    FResult.MessagesTruncated := True;
    Exit;
  end;

  lBytes := TEncoding.UTF8.GetByteCount(AMessage);
  lRemaining := xeHeadlessMessageMaxBytes - FMessageBytes;
  if lRemaining <= 0 then begin
    FResult.MessagesTruncated := True;
    Exit;
  end;

  if lBytes > lRemaining then begin
    lStored := xeUtf8PrefixByByteBudget(AMessage, lRemaining);
    FResult.MessagesTruncated := True;
  end else
    lStored := AMessage;

  if lStored <> '' then begin
    FMessages.Add(lStored);
    Inc(FMessageBytes, TEncoding.UTF8.GetByteCount(lStored));
  end;
end;

function TxeHeadlessJvIHost.BuildDirtyState: TJsonObject;
var
  lModules: TwbModuleInfos;
  lDirtyFiles: TJsonArray;
  lFile: IwbFile;
  i: Integer;
begin
  Result := TJsonObject.Create;
  lDirtyFiles := Result.A['dirtyFiles'];

  lModules := wbModulesByLoadOrder;
  for i := Low(lModules) to High(lModules) do begin
    lFile := xeAutomationTryPluginFileFromModule(lModules[i]);
    if Assigned(lFile) and lFile.Modified then
      lDirtyFiles.Add(xeAutomationNewFileSummary(lFile));
  end;

  Result.I['unsavedChangeCount'] := lDirtyFiles.Count;
  Result.B['dirty'] := lDirtyFiles.Count > 0;
end;

procedure TxeHeadlessJvIHost.CallScriptFunction(const AName: string; const AParams: array of Variant);
var
  lReturn: Variant;
begin
  FProgram.CallFunction(AName, nil, AParams);
  lReturn := FProgram.VResult;
  if not VarIsEmpty(lReturn) and not VarIsNull(lReturn) and (lReturn <> 0) then
    FailScript(xeHeadlessScriptErrorFailed, Format('%s returned %s', [AName, VarToStr(lReturn)]));
end;

procedure TxeHeadlessJvIHost.CacheLoadedFiles;
var
  lModules: TwbModuleInfos;
  lFile: IwbFile;
  lFileCount: Integer;
  i: Integer;
begin
  // Snapshot loaded plugin files once per run so frequent JvInterpreter identifier
  // lookups do not rescan the global load-order module list.
  lModules := wbModulesByLoadOrder;
  SetLength(FFiles, Length(lModules));

  lFileCount := 0;
  for i := Low(lModules) to High(lModules) do begin
    lFile := xeAutomationTryPluginFileFromModule(lModules[i]);
    if Assigned(lFile) then begin
      FFiles[lFileCount] := lFile;
      Inc(lFileCount);
    end;
  end;

  SetLength(FFiles, lFileCount);
end;

procedure TxeHeadlessJvIHost.FailScript(const ACode, AMessage: string);
begin
  FResult.ScriptFailed := True;
  FResult.ScriptFailureCode := ACode;
  FResult.ScriptFailureMessage := AMessage;
  raise xeAutomationNewError(ACode, AMessage);
end;

procedure TxeHeadlessJvIHost.JvInterpreterProgramGetValue(Sender: TObject; Identifier: string; var Value: Variant;
  Args: TJvInterpreterArgs; var Done: Boolean);
var
  i: Integer;
begin
  // The headless host intentionally exposes only daemon-safe callbacks. GUI-only
  // objects such as frmMain/frmFileSelect are explicitly denied below so runtime
  // denial semantics are preserved without exposing real GUI host objects.
  if SameText(Identifier, 'AddMessage') then begin
    if (Args.Count = 1) and VarIsStr(Args.Values[0]) then begin
      AddCapturedMessage(Args.Values[0]);
      Done := True;
    end else
      JvInterpreterError(ieDirectInvalidArgument, 0);
  end else if SameText(Identifier, 'ScriptLastPhase') and (Args.Count = 0) then begin
    Value := FResult.ScriptLastPhase;
    Done := True;
  end else if SameText(Identifier, 'ScriptFailed') and (Args.Count = 0) then begin
    Value := FResult.ScriptFailed;
    Done := True;
  end else if SameText(Identifier, 'ScriptFailureCode') and (Args.Count = 0) then begin
    Value := FResult.ScriptFailureCode;
    Done := True;
  end else if SameText(Identifier, 'ScriptFailureMessage') and (Args.Count = 0) then begin
    Value := FResult.ScriptFailureMessage;
    Done := True;
  end else if (SameText(Identifier, 'ProgramPath') or SameText(Identifier, 'wbProgramPath')) and (Args.Count = 0) then begin
    Value := wbProgramPath;
    Done := True;
  end else if (SameText(Identifier, 'ScriptsPath') or SameText(Identifier, 'wbScriptsPath')) and (Args.Count = 0) then begin
    Value := wbScriptsPath;
    Done := True;
  end else if (SameText(Identifier, 'DataPath') or SameText(Identifier, 'wbDataPath')) and (Args.Count = 0) then begin
    Value := wbDataPath;
    Done := True;
  end else if (SameText(Identifier, 'TempPath') or SameText(Identifier, 'wbTempPath')) and (Args.Count = 0) then begin
    Value := wbTempPath;
    Done := True;
  end else if SameText(Identifier, 'FileCount') and (Args.Count = 0) then begin
    // Loaded-file globals are daemon-safe object-model entry points, not GUI hooks:
    // they let common xEdit scripts reach IwbFile objects without exposing frmMain.
    Value := Length(FFiles);
    Done := True;
  end else if SameText(Identifier, 'FileByIndex') then begin
    if (Args.Count = 1) and VarIsNumeric(Args.Values[0]) and
      (Integer(Args.Values[0]) >= 0) and (Integer(Args.Values[0]) < Length(FFiles)) then begin
      Value := FFiles[Integer(Args.Values[0])];
      Done := True;
    end else
      JvInterpreterError(ieDirectInvalidArgument, 0);
  end else if SameText(Identifier, 'FileByLoadOrderFileID') then begin
    if (Args.Count = 1) and VarIsStr(Args.Values[0]) then begin
      for i := Low(FFiles) to High(FFiles) do
        if FFiles[i].LoadOrderFileID.ToString = Args.Values[0] then begin
          Value := FFiles[i];
          Break;
        end;
      Done := True;
    end else
      JvInterpreterError(ieDirectInvalidArgument, 0);
  end else if SameText(Identifier, 'FileByLoadOrder') then begin
    // Keep the GUI host bounds check: common scripts see the same rejection shape
    // for negative or beyond-file-count numeric load-order arguments.
    if (Args.Count = 1) and VarIsNumeric(Args.Values[0]) and
      (Integer(Args.Values[0]) >= 0) and (Integer(Args.Values[0]) < Length(FFiles)) then begin
      for i := Low(FFiles) to High(FFiles) do
        if FFiles[i].LoadOrder = Integer(Args.Values[0]) then begin
          Value := FFiles[i];
          Break;
        end;
      Done := True;
    end else
      JvInterpreterError(ieDirectInvalidArgument, 0);
  end else if SameText(Identifier, 'FileByName') then begin
    if (Args.Count = 1) and VarIsStr(Args.Values[0]) then begin
      for i := Low(FFiles) to High(FFiles) do
        if SameText(Args.Values[0], FFiles[i].FileName) then begin
          Value := FFiles[i];
          Break;
        end;
      Done := True;
    end else
      JvInterpreterError(ieDirectInvalidArgument, 0);
  end else if SameText(Identifier, 'frmMain') and (Args.Count = 0) then
    JvInterpreterErrorN(ieAccessDenied, 0,
      'frmMain: runtime policy denied by ledger classification deny_host_gui_hook')
  else if SameText(Identifier, 'frmFileSelect') and (Args.Count = 0) then
    JvInterpreterErrorN(ieAccessDenied, 0,
      'frmFileSelect: runtime policy denied by ledger classification deny_host_gui_hook');
end;

function TxeHeadlessJvIHost.LastErrorLocation: string;
begin
  if Assigned(FProgram) and Assigned(FProgram.LastError) then
    Result := Format('unit %s line %d', [FProgram.LastError.ErrUnitName, FProgram.LastError.ErrLine])
  else
    Result := '';
end;

function TxeHeadlessJvIHost.LoadUnitSourceFrom(const ADirectory, AUnitName: string; out ASource: string): Boolean;
var
  lUnitFile: string;
  lSource: TStringList;
begin
  Result := False;
  if not xeIsSafeUnitName(AUnitName) then
    Exit;

  lUnitFile := ExpandFileName(IncludeTrailingPathDelimiter(ADirectory) + AUnitName + '.pas');
  if not xePathIsUnderDirectory(lUnitFile, ADirectory) or not FileExists(lUnitFile) then
    Exit;

  lSource := TStringList.Create;
  try
    lSource.LoadFromFile(lUnitFile);
    ASource := lSource.Text;
    Result := True;
  finally
    lSource.Free;
  end;
end;

procedure TxeHeadlessJvIHost.JvInterpreterProgramGetUnitSource(UnitName: string; var Source: string; var Done: Boolean);
begin
  if SameText(UnitName, 'xEditAPI') or SameText(UnitName, 'UITypes') or IsUnitCompiledIn(HInstance, UnitName) then begin
    Source := 'unit ' + UnitName + '; end.';
    Done := True;
    Exit;
  end;

  // Unit loading uses explicit sibling/Agent roots instead of the legacy GUI host's
  // raw ScriptsPath LoadFromFile path, preventing a daemon script from importing an
  // arbitrary file by shaping UnitName or relying on the process current directory.
  if LoadUnitSourceFrom(FEntryScriptDir, UnitName, Source) then begin
    Done := True;
    Exit;
  end;

  if FEntryScriptUnderAgentRoot and LoadUnitSourceFrom(FAgentScriptsDir, UnitName, Source) then
    Done := True;
end;

procedure TxeHeadlessJvIHost.JvInterpreterProgramStatement(Sender: TObject);
begin
  wbTick;

  if (FOptions.TimeoutMS > 0) and (GetTickCount64 - FStartTick > FOptions.TimeoutMS) then
    FailScript(xeHeadlessScriptErrorTimeout, 'Headless script execution timed out');

  if FOptions.StatementBudget > 0 then begin
    Dec(FOptions.StatementBudget);
    if FOptions.StatementBudget = 0 then
      FailScript(xeHeadlessScriptErrorStatementBudgetExceeded, 'Headless script statement budget exhausted');
  end;
end;

procedure TxeHeadlessJvIHost.ResolveTargets;
var
  lLocator: TxeAutomationLocator;
  lRecord: IwbMainRecord;
  i: Integer;
begin
  SetLength(FTargets, 0);
  if not Assigned(FOptions.Targets) then
    Exit;

  SetLength(FTargets, FOptions.Targets.Count);
  for i := 0 to Pred(FOptions.Targets.Count) do begin
    if FOptions.Targets.Types[i] <> jdtObject then
      raise xeAutomationInvalidRequest('Headless script target entries must be locator objects');

    lLocator := xeAutomationParseLocator(FOptions.Targets.O[i], True, True);
    FTargets[i] := xeAutomationRequireElement(lLocator, lRecord);
  end;
end;

function TxeHeadlessJvIHost.Run: TxeHeadlessScriptRunResult;
var
  lSource: TStringList;
  lPreflightHits: TArray<TxeScriptLintHit>;
  i: Integer;
  lLocation: string;
begin
  try
    try
      FResult.ScriptLastPhase := 'load';
      lSource := TStringList.Create;
      try
        lSource.LoadFromFile(FOptions.EntryScriptPath);

        FResult.ScriptLastPhase := 'resolve_targets';
        ResolveTargets;

        CacheLoadedFiles;

        FProgram := TJvInterpreterProgram.Create(nil);
        FProgram.OnGetValue := JvInterpreterProgramGetValue;
        FProgram.OnGetUnitSource := JvInterpreterProgramGetUnitSource;
        FProgram.OnStatement := JvInterpreterProgramStatement;
        FProgram.Pas.Text := lSource.Text;

        FStartTick := GetTickCount64;
        FResult.ScriptLastPhase := 'compile';
        FProgram.Compile;

        // JVCL resolves adapter calls lazily and exposes no post-compile call table.
        // Scan only entry-script call shapes before lifecycle dispatch; helper-unit
        // and local-instance calls remain guarded by the authoritative runtime hook.
        FResult.ScriptLastPhase := 'preflight';
        lPreflightHits := xeScriptPolicyPreflightCalls(lSource.Text,
          ExtractFileName(FOptions.EntryScriptPath), xeHeadlessPolicyAllowsCall);
        if Length(lPreflightHits) > 0 then begin
          FResult.PolicyPreflightLine := lPreflightHits[0].Line;
          FResult.PolicyPreflightColumn := lPreflightHits[0].Column;
          raise xeAutomationNewError(xeHeadlessScriptErrorPolicyPreflight,
            Format('Access denied to ''%s: policy preflight: symbol is not in the JvI ledger or host-global allowlist''',
              [lPreflightHits[0].Symbol]));
        end;

        try
          FResult.ScriptLastPhase := 'initialize';
          if FProgram.FunctionExists('', 'Initialize') then
            CallScriptFunction('Initialize', []);

          FResult.ScriptLastPhase := 'process';
          if FProgram.FunctionExists('', 'Process') then
            for i := Low(FTargets) to High(FTargets) do begin
              CallScriptFunction('Process', [FTargets[i]]);
              Inc(FResult.ProcessedTargetCount);
            end;
        finally
          FResult.ScriptLastPhase := 'finalize';
          if FProgram.FunctionExists('', 'Finalize') then
            CallScriptFunction('Finalize', []);
        end;

        FResult.ScriptLastPhase := 'complete';
        FResult.Success := True;
      finally
        lSource.Free;
      end;
    except
      on E: ExeAutomationError do begin
        FResult.Success := False;
        if SameText(FResult.ScriptLastPhase, 'resolve_targets') then
          // Target resolution is a request-boundary validation step for headless
          // runs, so all locator/lookup failures are reported as malformed run
          // input and execution is skipped before any script code is compiled.
          FResult.ErrorCode := xeAutomationErrorInvalidRequest
        else
          FResult.ErrorCode := E.Code;
        FResult.ErrorMessage := E.Message;
        if not FResult.ScriptFailed and not SameText(FResult.ErrorCode, xeAutomationErrorInvalidRequest) then begin
          FResult.ScriptFailed := True;
          FResult.ScriptFailureCode := FResult.ErrorCode;
          FResult.ScriptFailureMessage := E.Message;
        end;
      end;
      on E: EJvInterpreterExternalDeclarationDenied do begin
        // Distinguishable external-declaration rejection: the host surfaces
        // explicit fields on the result so the daemon facade can emit
        // script_external_declaration_not_allowed without string-matching the
        // generic compile-error message. Class is declared at JvInterpreter.pas:1125.
        FResult.Success := False;
        FResult.ErrorCode := xeHeadlessScriptErrorException;
        FResult.ExternalDeclarationDenied := True;
        FResult.ScriptFailureUnitName := E.ErrUnitName;
        FResult.ScriptFailureLine := E.ErrLine;
        lLocation := LastErrorLocation;
        if lLocation <> '' then
          FResult.ErrorMessage := Format('Exception in %s: [%s] %s', [lLocation, E.ClassName, E.Message])
        else
          FResult.ErrorMessage := Format('Exception: [%s] %s', [E.ClassName, E.Message]);
        FResult.ScriptFailed := True;
        FResult.ScriptFailureCode := FResult.ErrorCode;
        FResult.ScriptFailureMessage := FResult.ErrorMessage;
      end;
      on E: Exception do begin
        FResult.Success := False;
        if SameText(FResult.ScriptLastPhase, 'resolve_targets') then
          FResult.ErrorCode := xeAutomationErrorInvalidRequest
        else
          FResult.ErrorCode := xeHeadlessScriptErrorException;
        lLocation := LastErrorLocation;
        if lLocation <> '' then
          FResult.ErrorMessage := Format('Exception in %s: [%s] %s', [lLocation, E.ClassName, E.Message])
        else
          FResult.ErrorMessage := Format('Exception: [%s] %s', [E.ClassName, E.Message]);
        FResult.ScriptFailed := not SameText(FResult.ErrorCode, xeAutomationErrorInvalidRequest);
        FResult.ScriptFailureCode := FResult.ErrorCode;
        FResult.ScriptFailureMessage := FResult.ErrorMessage;
      end;
    end;
  finally
    SetLength(FResult.Messages, FMessages.Count);
    for i := 0 to Pred(FMessages.Count) do
      FResult.Messages[i] := FMessages[i];
    FResult.DirtyState := BuildDirtyState;
  end;

  Result := FResult;
end;

function xeHeadlessRunScript(const AOptions: TxeHeadlessScriptRunOptions): TxeHeadlessScriptRunResult;
var
  lHost: TxeHeadlessJvIHost;
  lPreviousRejectExternalDeclarations: Boolean;
begin
  Result := Default(TxeHeadlessScriptRunResult);
  Result.ScriptLastPhase := 'queued';

  // The execution guard is acquired at the outermost seam so policy install,
  // callback wiring, and script teardown cannot interleave with GUI script runs.
  // A busy refusal still unwinds through daemon error handling while another
  // script may own the GUI host, so the returned record must be fully zeroed
  // before this early exit can expose ownership-bearing fields to cleanup code.
  if not xeScriptGuardTryAcquire('daemon') then begin
    Result.Success := False;
    Result.ErrorCode := xeHeadlessScriptErrorBusy;
    Result.ErrorMessage := 'Script execution is already running';
    Result.BusyHolder := xeScriptGuardCurrentHolder;
    Exit;
  end;

  lPreviousRejectExternalDeclarations := JvInterpreterRejectExternalDeclarations;
  lHost := nil;
  try
    // The parser-level external-declaration kill switch is toggled by this host,
    // not by policy install, because GUI script compatibility still depends on the
    // legacy default while daemon/headless executions require the stricter seam.
    xeInstallScriptRuntimePolicy;
    JvInterpreterRejectExternalDeclarations := True;
    lHost := TxeHeadlessJvIHost.Create(AOptions);
    Result := lHost.Run;
  finally
    // Per-program deny sentinels are owned by lHost.FProgram and die here.
    FreeAndNil(lHost);
    JvInterpreterRejectExternalDeclarations := lPreviousRejectExternalDeclarations;
    xeUninstallScriptRuntimePolicy;
    xeScriptGuardRelease;
  end;
end;

end.
