{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeAutomationCommandsFiles;

interface

procedure xeAutomationRegisterFilesCommands;

implementation

uses
  Classes,
  SysUtils,
  Types,
  JsonDataObjects,
  wbImplementation,
  wbInterface,
  wbLoadOrder,
  xeAutomationDataLookup,
  xeAutomationErrors,
  xeMainForm,
  xeAutomationMutationPolicy,
  xeAutomationObjectModel,
  xeAutomationRegistry;

const
  xeAutomationFilesCreateTemplateEmpty = 'empty';

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

procedure xeAutomationCaptureFileMasters(const AFile: IwbFile; const AMasters: TStrings);
var
  i: Integer;
begin
  AMasters.Clear;
  for i := 0 to Pred(AFile.MasterCount[True]) do
    AMasters.Add(AFile.Masters[i, True].FileName);
end;

function xeAutomationNewMasterReport: TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.A['added'];
  Result.A['alreadyPresent'];
  Result.A['skipped'];
end;

function xeAutomationMasterAlreadyPresent(const AMasters: TStrings; const AFileName: string): Boolean;
begin
  Result := AMasters.IndexOf(AFileName) >= 0;
end;

function xeAutomationApplyMasterRequests(const AFile: IwbFile; const ARequested: TStrings): TJsonObject;
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

      xeAutomationCaptureFileMasters(AFile, lBefore);

      for i := 0 to Pred(ARequested.Count) do begin
        lMasterFile := IwbFile(Pointer(ARequested.Objects[i]));
        // Master mutation is a native xEdit seam. Pre-filter self-dependencies here so
        // callers receive a stable protocol report instead of a low-level add failure.
        if SameText(ARequested[i], AFile.FileName) then begin
          Result.A['skipped'].Add(ARequested[i]);
          Continue;
        end;

        if xeAutomationMasterAlreadyPresent(lBefore, ARequested[i]) then begin
          Result.A['alreadyPresent'].Add(ARequested[i]);
          Continue;
        end;

        if Assigned(lMasterFile) and (lMasterFile.LoadOrder >= AFile.LoadOrder) then
          raise xeAutomationInvalidTarget(Format(
            'Automation required master "%s" can not be added to "%s" because it does not load before the target',
            [ARequested[i], AFile.FileName]
          ));

        lToAdd.AddObject(ARequested[i], ARequested.Objects[i]);
      end;

      if lToAdd.Count > 0 then begin
        lToAdd.Sorted := False;
        lToAdd.CustomSort(xeAutomationCompareFileLoadOrder);
        try
          AFile.AddMastersIfMissing(lToAdd, True, True);
        except
          on E: ExeAutomationError do
            raise;
          on E: Exception do
            raise xeAutomationInvalidTarget(Format(
              'Automation required masters could not be added to "%s": %s',
              [AFile.FileName, E.Message]
            ));
        end;
      end;

      xeAutomationCaptureFileMasters(AFile, lAfter);
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

function xeAutomationRequestedMastersFromNames(const ATargetFileName: string; const ANames: TStringDynArray): TStringList;
var
  lMaster: IwbFile;
  lName: string;
begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;
  try
    for lName in ANames do begin
      // A just-created file cannot be resolved by name yet. Preserve the request so
      // the shared add helper can report self-dependencies as skipped, not missing.
      if SameText(lName, ATargetFileName) then begin
        Result.AddObject(ATargetFileName, nil);
        Continue;
      end;

      lMaster := xeAutomationRequirePluginFile(lName);
      Result.AddObject(lMaster.FileName, Pointer(lMaster));
    end;
    Result.Sorted := False;
    Result.CustomSort(xeAutomationCompareFileLoadOrder);
  except
    Result.Free;
    raise;
  end;
end;

function xeAutomationRequestedMastersFromElement(const AElement: IwbElement): TStringList;
var
  lMasters: TwbFilesSet;
  lFile: IwbFile;
begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;
  try
    lMasters := TwbFilesSet.Create;
    try
      // Use xEdit's own required-master walker so automation stays aligned with the
      // GUI add-masters logic for root records and nested element scopes.
      AElement.ReportRequiredMasters(lMasters, False, True, True);
      for lFile in lMasters do
        Result.AddObject(lFile.FileName, Pointer(lFile));
      Result.Sorted := False;
      Result.CustomSort(xeAutomationCompareFileLoadOrder);
    finally
      lMasters.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function xeAutomationValidateNewFileName(const AArgs: TJsonObject): string;
var
  lExt: string;
begin
  Result := xeAutomationRequireStringArg(AArgs, 'fileName');
  // New files must be named plugins inside the active data path. Rejecting path-like
  // values here avoids accidentally turning automation into a filesystem write API.
  if ExtractFileName(Result) <> Result then
    raise xeAutomationInvalidRequest('Automation arg "fileName" must be a bare plugin file name');

  lExt := LowerCase(ExtractFileExt(Result));
  if (lExt <> '.esp') and (lExt <> '.esm') and (lExt <> '.esl') then
    raise xeAutomationInvalidRequest('Automation arg "fileName" must end with .esp, .esm, or .esl');
end;

procedure xeAutomationReadCreateFlags(const AArgs: TJsonObject; out AIsESM, AIsLight, AIsMedium, AIsLocalized: Boolean);
var
  lFlags: TJsonObject;
  lName: string;
  lHasESL: Boolean;
  lHasSmall: Boolean;
  lESL: Boolean;
  lSmall: Boolean;
  i: Integer;
begin
  AIsESM := False;
  AIsLight := False;
  AIsMedium := False;
  AIsLocalized := False;
  lHasESL := False;
  lHasSmall := False;
  lESL := False;
  lSmall := False;
  if not Assigned(AArgs) or not AArgs.Contains('flags') then
    Exit;

  if AArgs.Types['flags'] <> jdtObject then
    raise xeAutomationInvalidRequest('Automation arg field "flags" must be an object');

  lFlags := AArgs.O['flags'];
  for i := 0 to Pred(lFlags.Count) do begin
    lName := lFlags.Names[i];
    // Flags are intentionally named at the protocol boundary so automation exposes
    // Bethesda plugin header bits deliberately while still rejecting typos.
    // Phase 16 (contract 0.21): `small` is a Starfield-native alias of `esl` /
    // light-slot, and `localized` maps directly to IwbFile.IsLocalized. Both stay
    // valid outside Starfield too (a Skyrim ESL flagged file is still small in the
    // engine's vocabulary, and Localized is a game-agnostic header bit), so the
    // parser is game-mode-agnostic. Aliases are resolved after full parse.
    if not SameText(lName, 'esm') and not SameText(lName, 'esl') and
       not SameText(lName, 'small') and not SameText(lName, 'medium') and
       not SameText(lName, 'localized') then
      raise xeAutomationInvalidRequest(Format('Automation files.create flag "%s" is not supported', [lName]));
    if lFlags.Types[lName] <> jdtBool then
      raise xeAutomationInvalidRequest(Format('Automation files.create flag "%s" must be a boolean', [lName]));
  end;

  if lFlags.Contains('esm') then
    AIsESM := lFlags.B['esm'];
  if lFlags.Contains('esl') then begin
    lHasESL := True;
    lESL := lFlags.B['esl'];
  end;
  if lFlags.Contains('small') then begin
    lHasSmall := True;
    lSmall := lFlags.B['small'];
  end;
  // small/esl target the same light-slot bit; only reject when the caller
  // explicitly disagrees on the two aliases. Silent OR would let contradictory
  // requests appear to succeed with whichever alias was parsed last.
  if lHasESL and lHasSmall and (lESL <> lSmall) then
    raise xeAutomationInvalidRequest('Automation files.create flags "small" and "esl" are aliases and must not disagree; set only one, or the same boolean on both');
  if lHasESL then
    AIsLight := lESL
  else if lHasSmall then
    AIsLight := lSmall;
  if lFlags.Contains('medium') then
    AIsMedium := lFlags.B['medium'];
  if lFlags.Contains('localized') then
    AIsLocalized := lFlags.B['localized'];
end;

procedure xeAutomationValidateCreateShape(const AFileName: string; const AIsESM, AIsLight, AIsMedium: Boolean);
var
  lExt: string;
begin
  lExt := LowerCase(ExtractFileExt(AFileName));
  if SameText(lExt, '.esp') and AIsESM then
    raise xeAutomationInvalidRequest('Automation .esp files must not set flags.esm true');
  if SameText(lExt, '.esm') and not AIsESM then
    raise xeAutomationInvalidRequest('Automation .esm files must set flags.esm true');
  // Phase 16 (contract 0.21) Starfield unlock: xEdit's core header-flag mask lets
  // a .esm carry the small/light bit and Bethesda ships several small .esm files
  // in Starfield. Refusing the combination at the automation surface prevented
  // authoring small .esm patches through the CLI even though the SF1 engine
  // accepts them, so the pre-0.21 rejection is dropped for .esm here. medium
  // stays orthogonal to esl (mutually exclusive light-vs-medium slot handled
  // natively by IwbMainRecordStructFlags setters).
  if SameText(lExt, '.esl') and (not AIsESM or not AIsLight) then
    raise xeAutomationInvalidRequest('Automation .esl files must set flags.esm and flags.esl true');
  if AIsLight and AIsMedium then
    raise xeAutomationInvalidRequest('Automation files.create must not set flags.esl and flags.medium true together');
end;

procedure xeAutomationRequireNoExistingNewFile(const AFileName: string);
var
  lModules: TwbModuleInfos;
  lFile: IwbFile;
  i: Integer;
begin
  lModules := wbModulesByLoadOrder;
  for i := Low(lModules) to High(lModules) do begin
    lFile := xeAutomationTryPluginFileFromModule(lModules[i]);
    if Assigned(lFile) and SameText(lFile.FileName, AFileName) then
      raise xeAutomationStateConflict(Format('Automation file is already loaded: %s', [AFileName]));
  end;

  if FileExists(wbDataPath + AFileName) then
    raise xeAutomationStateConflict(Format('Automation file already exists on disk: %s', [AFileName]));
end;

function xeAutomationNextNewFileLoadOrder: Integer;
var
  lModules: TwbModuleInfos;
  lFile: IwbFile;
  i: Integer;
begin
  Result := 0;
  lModules := wbModulesByLoadOrder;
  for i := Low(lModules) to High(lModules) do begin
    lFile := xeAutomationTryPluginFileFromModule(lModules[i]);
    if Assigned(lFile) and (lFile.LoadOrder >= Result) then
      Result := Succ(lFile.LoadOrder);
  end;
end;

function xeAutomationFilesList(const AArgs: TJsonObject): TJsonObject;
var
  lModules: TwbModuleInfos;
  lFiles: TJsonArray;
  lFile: IwbFile;
  i: Integer;
begin
  Result := TJsonObject.Create;
  lFiles := Result.A['files'];
  lModules := wbModulesByLoadOrder;
  for i := Low(lModules) to High(lModules) do begin
    lFile := xeAutomationTryPluginFileFromModule(lModules[i]);
    if Assigned(lFile) then
      lFiles.Add(xeAutomationNewFileSummary(lFile));
  end;
end;

function xeAutomationFilesGet(const AArgs: TJsonObject): TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.O['file'] := xeAutomationNewFileSummary(
    xeAutomationRequirePluginFile(xeAutomationRequireStringArg(AArgs, 'name'))
  );
end;

function xeAutomationFilesCreate(const AArgs: TJsonObject): TJsonObject;
var
  lFileName: string;
  lTemplate: string;
  lIsESM: Boolean;
  lIsLight: Boolean;
  lIsMedium: Boolean;
  lIsLocalized: Boolean;
  lInitialMasters: TStringDynArray;
  lRequestedMasters: TStringList;
  lMasterReport: TJsonObject;
  lFile: IwbFile;
  lDeniedReason: string;
begin
  if not xeAutomationMutationPolicyConsentSatisfied(lDeniedReason) then begin
    Result := xeAutomationErrorsBuildConsentRequired('files.create', 'files-mutation', lDeniedReason);
    Exit;
  end;

  lMasterReport := nil;
  if not Assigned(AArgs) then
    raise xeAutomationInvalidRequest('Automation command args are required');

  lFileName := xeAutomationValidateNewFileName(AArgs);
  lTemplate := xeAutomationReadStringArg(AArgs, 'template');
  if (lTemplate <> '') and not SameText(lTemplate, xeAutomationFilesCreateTemplateEmpty) then
    raise xeAutomationInvalidRequest(Format('Automation files.create template "%s" is not supported', [lTemplate]));

  xeAutomationReadCreateFlags(AArgs, lIsESM, lIsLight, lIsMedium, lIsLocalized);
  xeAutomationValidateCreateShape(lFileName, lIsESM, lIsLight, lIsMedium);
  xeAutomationRequireNoExistingNewFile(lFileName);
  if not wbEditAllowed then
    raise xeAutomationReadOnlyTarget('Automation mutation requires edit mode');

  lInitialMasters := xeAutomationReadStringArrayArg(AArgs, 'initialMasters');
  lRequestedMasters := xeAutomationRequestedMastersFromNames(lFileName, lInitialMasters);
  try
    try
      lFile := wbNewFile(wbDataPath + lFileName, xeAutomationNextNewFileLoadOrder, lIsLight, lIsMedium);
      // wbNewFile handles light/medium allocation, but ESM header intent remains a
      // post-create file flag so .esm/.esl and explicit ESM plugins match xEdit state.
      if lIsESM or SameText(ExtractFileExt(lFileName), '.esm') or SameText(ExtractFileExt(lFileName), '.esl') then
        lFile.IsESM := True;
      // Phase 16 (contract 0.21): Localized is orthogonal to esm/esl/medium and
      // maps directly to the IwbFile.IsLocalized native seam. Apply post-create
      // so wbNewFile's template selection isn't perturbed. IsLocalized is only
      // set True when explicitly requested; defaulting to False preserves
      // existing files.create semantics for pre-0.21 clients.
      if lIsLocalized then
        lFile.IsLocalized := True;

      lMasterReport := xeAutomationApplyMasterRequests(lFile, lRequestedMasters);

      if Assigned(frmMain) then
        // Automation files.create already mutates xEdit's live file model through wbNewFile.
        // Mirror the existing GUI AddNewFile registration seam so the new patch file
        // appears immediately in the left navigation tree and can show dirty styling.
        frmMain.AddFile(lFile);

      Result := TJsonObject.Create;
      try
        Result.B['changed'] := True;
        Result.B['dirty'] := lFile.Modified;
        Result.O['file'] := xeAutomationNewFileSummary(lFile);
        Result.O['masters'] := lMasterReport;
        lMasterReport := nil;
      except
        Result.Free;
        lMasterReport.Free;
        raise;
      end;
    except
      on E: ExeAutomationError do
        raise;
      on E: Exception do
        raise xeAutomationInvalidTarget(Format('Automation file could not be created: %s', [E.Message]));
    end;
  finally
    lRequestedMasters.Free;
  end;
end;

function xeAutomationFilesAddRequiredMasters(const AArgs: TJsonObject): TJsonObject;
var
  lTargetFileName: string;
  lSourceLocator: TxeAutomationLocator;
  lRecord: IwbMainRecord;
  lSourceElement: IwbElement;
  lTargetFile: IwbFile;
  lRequestedMasters: TStringList;
  lMasterReport: TJsonObject;
  lChanged: Boolean;
  lDeniedReason: string;
begin
  if not xeAutomationMutationPolicyConsentSatisfied(lDeniedReason) then begin
    Result := xeAutomationErrorsBuildConsentRequired('files.add_required_masters', 'files-mutation', lDeniedReason);
    Exit;
  end;

  lMasterReport := nil;
  lTargetFileName := xeAutomationRequireStringArg(AArgs, 'targetFile');
  lSourceLocator := xeAutomationParseNestedLocatorArg(AArgs, 'source', True, True);
  lTargetFile := xeAutomationRequirePluginFile(lTargetFileName);
  xeAutomationRequireWritableTargetFile(lTargetFile);
  lSourceElement := xeAutomationRequireElement(lSourceLocator, lRecord);

  lRequestedMasters := xeAutomationRequestedMastersFromElement(lSourceElement);
  try
    lMasterReport := xeAutomationApplyMasterRequests(lTargetFile, lRequestedMasters);
  finally
    lRequestedMasters.Free;
  end;

  Result := TJsonObject.Create;
  try
    lChanged := lMasterReport.A['added'].Count > 0;
    Result.B['changed'] := lChanged;
    Result.B['dirty'] := lTargetFile.Modified;
    Result.S['targetFile'] := lTargetFile.FileName;
    // Echo the parsed source locator so clients can correlate idempotent master-add
    // responses without depending on implicit command arguments outside the result.
    Result.O['source'].S['file'] := lSourceLocator.FileName;
    Result.O['source'].S['formId'] := lSourceLocator.FormID;
    Result.O['source'].S['path'] := lSourceLocator.Path;
    Result.O['masters'] := lMasterReport;
    lMasterReport := nil;
  except
    Result.Free;
    lMasterReport.Free;
    raise;
  end;
end;

procedure xeAutomationRegisterFilesCommands;
begin
  xeAutomationRegisterCommand('files.list', xeAutomationFilesList);
  xeAutomationRegisterCommand('files.get', xeAutomationFilesGet);
  xeAutomationRegisterCommand('files.create', xeAutomationFilesCreate);
  xeAutomationRegisterCommand('files.add_required_masters', xeAutomationFilesAddRequiredMasters);
end;

end.
