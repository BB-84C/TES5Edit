{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeAutomationCommandsSystem;

interface

implementation

uses
  SysUtils,
  TypInfo,
  JsonDataObjects,
  wbInterface,
  xeAutomationCommandsCleaning,
  xeAutomationCommandsElements,
  xeAutomationCommandsFileHygiene,
  xeAutomationCommandsFiles,
  xeAutomationCommandsJobs,
  xeAutomationCommandsPluginAnalysis,
  xeAutomationCommandsValidation,
  xeAutomationCommandsRecords,
  xeAutomationCommandsScripts,
  xeAutomationCommandsSession,
  xeAutomationCommandsSessionNavigation,
  xeAutomationJobs,
  xeAutomationRegistry;

const
  xeAutomationFinalJobKinds: array[0..9] of string = (
    'files.hygiene.batch',
    'plugin.esl.analyze',
    'plugin.esl.apply',
    'plugin.formids.compact_for_esl',
    'validation.check_for_errors',
    'validation.check_for_itm',
    'validation.check_for_deleted_refs',
    'cleaning.quick_clean',
    'cleaning.quick_auto_clean',
    'cleaning.sort_and_clean_masters'
  );

procedure xeAutomationEnsureCapabilityCommandSurface;
var
  lJobKind: string;
  lPluginAnalyzeRegistered: Boolean;
  lValidationErrorsRegistered: Boolean;
  lValidationItmRegistered: Boolean;
  lValidationDeletedRefsRegistered: Boolean;
  lCleaningQuickRegistered: Boolean;
  lCleaningQuickAutoRegistered: Boolean;
  lCleaningMastersRegistered: Boolean;
begin
  // Capabilities advertises the full protocol surface even for one-shot probes;
  // register groups lazily here so the registry remains the single source of names.
  if not xeAutomationHasCommand('session.get_dirty_state') then
    xeAutomationRegisterSessionCommands;
  if not xeAutomationHasCommand('session.navigate_to_record') then
    xeAutomationRegisterSessionNavigationCommands;
  if not xeAutomationHasCommand('files.list') then
    xeAutomationRegisterFilesCommands;
  if not xeAutomationHasCommand('files.get_header') then
    xeAutomationRegisterFileHygieneCommands;
  // Capability probes are allowed before daemon serve registration; load the
  // accepted ESL/compact job group here so the complete job surface is present.
  lPluginAnalyzeRegistered := False;
  lValidationErrorsRegistered := False;
  lValidationItmRegistered := False;
  lValidationDeletedRefsRegistered := False;
  lCleaningQuickRegistered := False;
  lCleaningQuickAutoRegistered := False;
  lCleaningMastersRegistered := False;
  for lJobKind in xeAutomationListJobKinds do
    if SameText(lJobKind, 'plugin.esl.analyze') then begin
      lPluginAnalyzeRegistered := True;
    end else if SameText(lJobKind, 'validation.check_for_errors') then begin
      lValidationErrorsRegistered := True;
    end else if SameText(lJobKind, 'validation.check_for_itm') then begin
      lValidationItmRegistered := True;
    end else if SameText(lJobKind, 'validation.check_for_deleted_refs') then begin
      lValidationDeletedRefsRegistered := True;
    end else if SameText(lJobKind, 'cleaning.quick_clean') then begin
      lCleaningQuickRegistered := True;
    end else if SameText(lJobKind, 'cleaning.quick_auto_clean') then begin
      lCleaningQuickAutoRegistered := True;
    end else if SameText(lJobKind, 'cleaning.sort_and_clean_masters') then begin
      lCleaningMastersRegistered := True;
    end;
  if not lPluginAnalyzeRegistered then
    xeAutomationRegisterPluginAnalysisCommands;
  // Keep validation capability advertising registry-derived: these kinds are
  // registered lazily only after their implementation unit is linked here.
  if not (lValidationErrorsRegistered and lValidationItmRegistered and lValidationDeletedRefsRegistered) then
    xeAutomationRegisterValidationCommands;
  // Cleaning capability advertising remains truthful because these kinds are
  // registered only after the 6D in-memory/apply-safe implementation is linked.
  if not (lCleaningQuickRegistered and lCleaningQuickAutoRegistered and lCleaningMastersRegistered) then
    xeAutomationRegisterCleaningCommands;
  if not xeAutomationHasCommand('jobs.start') then
    xeAutomationRegisterJobsCommands;
  if not xeAutomationHasCommand('records.list') then
    xeAutomationRegisterRecordsCommands;
  if not xeAutomationHasCommand('elements.get') then
    xeAutomationRegisterElementsCommands;
  // One-shot capabilities probes do not pass through serve-loop startup, so the
  // public scripts.* names are registered here before the registry is listed.
  if not xeAutomationHasCommand('scripts.list') then
    xeAutomationRegisterScriptsCommands;
end;

function xeAutomationSystemPing(const aArgs: TJsonObject): TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.S['status'] := 'ok';
end;

function xeAutomationSystemDescribe(const aArgs: TJsonObject): TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.S['appName'] := wbAppName;
  Result.S['gameName'] := wbGameName;
  Result.S['gameMode'] := GetEnumName(TypeInfo(TwbGameMode), Ord(wbGameMode));
  Result.S['subMode'] := wbSubMode;
  Result.S['dataPath'] := wbDataPath;
end;

function xeAutomationSystemCapabilities(const aArgs: TJsonObject): TJsonObject;
var
  lCommands: TJsonArray;
  lCommandNames: TArray<string>;
  lCommandName: string;
  lJobKind: string;
  lScripts: TJsonObject;
  lChildGroupNavigation: TJsonObject;
  lElementsChildrenPagination: TJsonObject;
  lApplyFilterExtensions: TJsonObject;
  lApplyFilterRegex: TJsonObject;
  lReferencesRecursive: TJsonObject;
  lConflictStatusChildGroup: TJsonObject;
  lCreateParentSpec: TJsonObject;
begin
  Result := TJsonObject.Create;
  // Phase 15H (0.16 -> 0.17): additive pagination for elements.children.
  // Earlier supports blocks remain stable for older clients that ignore new keys.
  Result.S['contractVersion'] := '0.17';

  xeAutomationEnsureCapabilityCommandSurface;

  // This contract is intentionally small and mode-agnostic so automation
  // clients can cheaply detect command names and transport support.
  lCommands := Result.A['commands'];
  lCommandNames := xeAutomationListCommands;
  for lCommandName in lCommandNames do
    lCommands.Add(lCommandName);

  Result.O['supports'].B['oneShot'] := True;
  Result.O['supports'].B['daemon'] := True;
  // Supports fields are explicit protocol metadata rather than inferred from
  // command names so clients can choose safe patch-building flows up front.
  Result.O['supports'].O['filesCreate'].A['extensions'].Add('.esp');
  Result.O['supports'].O['filesCreate'].A['extensions'].Add('.esm');
  Result.O['supports'].O['filesCreate'].A['extensions'].Add('.esl');
  Result.O['supports'].O['filesCreate'].A['flags'].Add('esm');
  Result.O['supports'].O['filesCreate'].A['flags'].Add('esl');
  Result.O['supports'].O['filesCreate'].A['flags'].Add('medium');
  // Local fork: surface that Starfield .esp creation/editing/master-add is
  // enabled natively in this build, even though upstream xEdit blocks it.
  // The "plain-only" mode means we only open the unflagged .esp shape
  // (no Light/Medium/Update/ESL flag); flagged-.esp combinations remain
  // blocked because the SF1 engine handles them unstably. The
  // "full-only" master policy means master-add still requires every
  // master to be a Full module - matching xEdit core's existing SF1
  // safety gate at TwbFile.AddMaster.
  if wbIsStarfield then begin
    Result.O['supports'].O['filesCreate'].O['starfieldEspWrite'].S['mode'] := 'plain-only';
    Result.O['supports'].O['filesCreate'].O['starfieldEspWrite'].S['masterPolicy'] := 'full-only';
    Result.O['supports'].O['filesCreate'].O['starfieldEspWrite'].B['allowMasterAdd'] := True;
  end;
  // records.create intentionally has no protocol-side signature allow-list; xEdit's
  // native group/record Add path owns support decisions for the active game mode.
  Result.O['supports'].O['recordsCreate'].S['signaturePolicy'] := 'native-xedit-add';
  Result.O['supports'].O['scripts'].O['namespaces'].A['runnable'].Add('');
  Result.O['supports'].O['scripts'].O['namespaces'].A['runnable'].Add('Agent');
  Result.O['supports'].O['scripts'].O['namespaces'].A['writable'].Add('Agent');
  Result.O['supports'].O['scripts'].S['fsReadRoot'] := 'scripts';
  Result.O['supports'].O['scripts'].B['runtimeFsRead'] := True;
  Result.O['supports'].O['scripts'].B['runtimeFsWrite'] := False;
  Result.O['supports'].O['scripts'].B['runtimeUi'] := False;
  Result.O['supports'].O['scripts'].B['runtimeShell'] := False;
  Result.O['supports'].O['scripts'].B['runtimeClipboard'] := False;
  Result.O['supports'].O['scripts'].B['runtimeProcessSpawn'] := False;
  Result.O['supports'].O['scripts'].A['targetModel'].Add('explicitLocators');
  Result.O['supports'].O['scripts'].A['targetModel'].Add('none');
  Result.O['supports'].O['scripts'].S['lintPolicy'] := 'hard-gate-with-override';
  Result.O['supports'].O['scripts'].S['lintScope'] := 'entry-script-only';
  Result.O['supports'].O['scripts'].O['execution'].B['synchronous'] := True;
  Result.O['supports'].O['scripts'].O['execution'].B['cancelable'] := False;
  Result.O['supports'].O['scripts'].O['execution'].I['defaultTimeoutMs'] := 30000;
  Result.O['supports'].O['scripts'].O['execution'].I['defaultMaxStatements'] := 1000000;
  // The existing shared GUI/daemon runner semantics are exposed as explicit
  // client metadata without moving scripts.run into jobs.*.
  Result.O['supports'].O['scripts'].O['execution'].S['overlapPolicy'] := 'single-process-single-runner';
  Result.O['supports'].O['scripts'].O['execution'].A['busyHolders'].Add('daemon');
  Result.O['supports'].O['scripts'].O['execution'].A['busyHolders'].Add('gui');
  Result.O['supports'].O['scripts'].O['execution'].B['failureMessagesOnError'] := True;
  Result.O['supports'].O['scripts'].O['execution'].B['iKnowWhatImDoing'] := wbIKnowWhatImDoing;
  lScripts := Result.O['supports'].O['scripts'];
  // Additive script-policy fields remain part of the frozen capability surface.
  with lScripts.A['additionalAllowedReads'] do
  begin
    Add('TFile.ReadAllText');
    Add('TStrings.LoadFromFile');
    Add('TMemoryStream.LoadFromFile');
    Add('TDirectory.GetFiles');
    Add('TDirectory.GetDirectories');
  end;
  with lScripts.A['errorLifecycleFields'] do
  begin
    Add('ranInitialize');
    Add('ranFinalize');
    Add('processed');
  end;
  with lScripts.A['additionalDenyCodes'] do
  begin
    Add('script_external_declaration_not_allowed');
  end;
  Result.O['supports'].O['jobs'].A['states'].Add('queued');
  Result.O['supports'].O['jobs'].A['states'].Add('running');
  Result.O['supports'].O['jobs'].A['states'].Add('succeeded');
  Result.O['supports'].O['jobs'].A['states'].Add('failed');
  Result.O['supports'].O['jobs'].A['states'].Add('cancel_requested');
  Result.O['supports'].O['jobs'].A['states'].Add('canceled');
  Result.O['supports'].O['jobs'].A['commands'].Add('jobs.start');
  Result.O['supports'].O['jobs'].A['commands'].Add('jobs.get');
  Result.O['supports'].O['jobs'].A['commands'].Add('jobs.findings');
  Result.O['supports'].O['jobs'].A['commands'].Add('jobs.cancel');
  Result.O['supports'].O['jobs'].A['commands'].Add('jobs.discard');
  // Keep the public job-kind order and membership stable so clients receive a
  // deterministic contract instead of dictionary sort order.
  for lJobKind in xeAutomationFinalJobKinds do
    Result.O['supports'].O['jobs'].A['kinds'].Add(lJobKind);
  Result.O['supports'].O['fileHygiene'].A['commands'].Add('files.get_header');
  Result.O['supports'].O['fileHygiene'].A['commands'].Add('files.get_masters');
  Result.O['supports'].O['fileHygiene'].A['commands'].Add('files.set_header_flags');
  Result.O['supports'].O['fileHygiene'].A['commands'].Add('files.sort_masters');
  Result.O['supports'].O['fileHygiene'].A['commands'].Add('files.clean_masters');
  Result.O['supports'].O['fileHygiene'].A['headerFlags'].Add('esm');
  Result.O['supports'].O['fileHygiene'].A['headerFlags'].Add('esl');
  Result.O['supports'].O['fileHygiene'].A['headerFlags'].Add('medium');
  Result.O['supports'].O['fileHygiene'].S['saveBoundary'] := 'explicit_session_save';

  // Phase 13 element-mutation expansion. See docs/plans/2026-06-07-xedit-phase13-*.md.
  Result.O['supports'].O['elementsMutation'].A['commands'].Add('elements.set_native_value');
  Result.O['supports'].O['elementsMutation'].A['commands'].Add('elements.set_to_default');
  Result.O['supports'].O['elementsMutation'].A['commands'].Add('elements.clear');
  Result.O['supports'].O['elementsMutation'].A['commands'].Add('elements.move_up');
  Result.O['supports'].O['elementsMutation'].A['commands'].Add('elements.move_down');
  Result.O['supports'].O['elementsMutation'].A['commands'].Add('elements.next_member');
  Result.O['supports'].O['elementsMutation'].A['commands'].Add('elements.previous_member');
  Result.O['supports'].O['elementsMutation'].A['commands'].Add('elements.edit_capabilities');
  Result.O['supports'].O['elementsMutation'].A['commands'].Add('elements.assign_templates');

  Result.O['supports'].O['elementsMutation'].O['discovery'].S['capabilitiesCommand'] := 'elements.edit_capabilities';
  Result.O['supports'].O['elementsMutation'].O['discovery'].S['templatesCommand']    := 'elements.assign_templates';
  Result.O['supports'].O['elementsMutation'].O['discovery'].B['templatesEmbedded']   := True;
  Result.O['supports'].O['elementsMutation'].O['discovery'].B['sourceSensitiveCopyCheck'] := True;

  Result.O['supports'].O['elementsMutation'].O['valueWrites'].B['editValue'] := True;
  Result.O['supports'].O['elementsMutation'].O['valueWrites'].O['nativeValue'].B['supported']    := True;
  Result.O['supports'].O['elementsMutation'].O['valueWrites'].O['nativeValue'].S['requestShape'] := 'json-typed-with-optional-kind-hint';
  Result.O['supports'].O['elementsMutation'].O['valueWrites'].O['nativeValue'].A['kinds'].Add('int');
  Result.O['supports'].O['elementsMutation'].O['valueWrites'].O['nativeValue'].A['kinds'].Add('float');
  Result.O['supports'].O['elementsMutation'].O['valueWrites'].O['nativeValue'].A['kinds'].Add('string');
  Result.O['supports'].O['elementsMutation'].O['valueWrites'].O['nativeValue'].A['kinds'].Add('bool');
  Result.O['supports'].O['elementsMutation'].O['valueWrites'].O['nativeValue'].A['kinds'].Add('formId');
  Result.O['supports'].O['elementsMutation'].O['valueWrites'].O['nativeValue'].A['kinds'].Add('formIdArray');
  Result.O['supports'].O['elementsMutation'].O['valueWrites'].O['nativeValue'].B['losslessJsonRoundTrip'] := False;

  Result.O['supports'].O['elementsMutation'].O['addChild'].B['targetIndex'] := True;
  Result.O['supports'].O['elementsMutation'].O['addChild'].O['templateSelection'].B['byIndex'] := True;
  Result.O['supports'].O['elementsMutation'].O['addChild'].O['templateSelection'].B['byName']  := True;
  Result.O['supports'].O['elementsMutation'].O['addChild'].O['templateSelection'].B['autoSelectSingleTemplate'] := True;

  Result.O['supports'].O['elementsMutation'].O['copyChildTo'].B['targetIndex'] := True;
  Result.O['supports'].O['elementsMutation'].O['copyChildTo'].O['addRequiredMasters'].B['supported'] := True;
  Result.O['supports'].O['elementsMutation'].O['copyChildTo'].O['addRequiredMasters'].B['default']   := False;
  Result.O['supports'].O['elementsMutation'].O['copyChildTo'].B['sortOrderExposed'] := False;
  Result.O['supports'].O['elementsMutation'].O['copyChildTo'].S['placementMode']    := 'targetIndex';

  Result.O['supports'].O['elementsMutation'].O['operations'].B['setToDefault']     := True;
  Result.O['supports'].O['elementsMutation'].O['operations'].B['clear']            := True;
  Result.O['supports'].O['elementsMutation'].O['operations'].B['moveUp']           := True;
  Result.O['supports'].O['elementsMutation'].O['operations'].B['moveDown']         := True;
  Result.O['supports'].O['elementsMutation'].O['operations'].B['nextMember']       := True;
  Result.O['supports'].O['elementsMutation'].O['operations'].B['previousMember']   := True;

  Result.O['supports'].O['elementsMutation'].S['saveBoundary']    := 'explicit_session_save';
  Result.O['supports'].O['elementsMutation'].S['mutationPolicy']  := 'native-xedit-predicates';
  Result.O['supports'].O['elementsMutation'].B['consentRequired'] := True;
  Result.O['supports'].O['elementsMutation'].B['iKnowWhatImDoing'] := wbIKnowWhatImDoing;

  // Phase 15A exposes ChildGroup traversal as read-only locator metadata; no
  // mutation verbs are implied by this capability block.
  lChildGroupNavigation := Result.O['supports'].O['childGroupNavigation'];
  lChildGroupNavigation.S['prefix'] := '\Child Group';
  lChildGroupNavigation.B['recordLocatorReentry'] := True;
  with lChildGroupNavigation.A['parents'] do begin
    Add('CELL');
    Add('WRLD');
    Add('DIAL');
    Add('QUST');
  end;
  lChildGroupNavigation.S['questAvailableWhen'] := 'wbVWDAsQuestChildren';
  with lChildGroupNavigation.O['subLabels'].A['CELL'] do begin
    Add('Persistent');
    Add('Temporary');
    Add('Visible when Distant');
  end;
  with lChildGroupNavigation.O['subLabels'].A['WRLD'] do begin
    Add('Persistent');
    Add('Block <N>,<N>');
    Add('Block <N>,<N>\Sub-Block <M>,<M>');
  end;
  with lChildGroupNavigation.O['groupTypes'] do begin
    I['WRLD-ChildGroup'] := 1;
    I['Block'] := 4;
    I['Sub-Block'] := 5;
    I['CELL-ChildGroup'] := 6;
    I['DIAL-ChildGroup'] := 7;
    I['CELL-Persistent'] := 8;
    I['CELL-Temporary'] := 9;
    I['CELL-VWD'] := 10;
    I['QUST-ChildGroup'] := 10;
  end;
  lChildGroupNavigation.S['objectKind'] := 'child_group';

  // elements.children is now bounded at the verb layer so dense ChildGroups stay
  // safely below the named-pipe buffer limit without changing the transport.
  lElementsChildrenPagination := Result.O['supports'].O['elementsChildrenPagination'];
  lElementsChildrenPagination.I['defaultLimit'] := 200;
  lElementsChildrenPagination.I['maxLimit'] := 1000;
  with lElementsChildrenPagination.A['responseFields'] do begin
    Add('count');
    Add('total');
    Add('offset');
    Add('truncated');
  end;

  // Phase 15B keeps records.apply_filter as the discovery surface: parentFormId
  // scopes by MainRecord ancestry, while regex fields are explicit alternatives
  // to the existing glob patterns and report timeout skips through result metadata.
  lApplyFilterExtensions := Result.O['supports'].O['applyFilterExtensions'];
  lApplyFilterExtensions.B['parentFormId'] := True;
  lApplyFilterRegex := lApplyFilterExtensions.O['regex'];
  lApplyFilterRegex.S['engine'] := 'System.RegularExpressions.TRegEx';
  lApplyFilterRegex.I['perRecordTimeoutMs'] := 100;
  with lApplyFilterRegex.A['fields'] do begin
    Add('editorIdRegex');
    Add('displayNameRegex');
    Add('fullNameRegex');
    Add('baseEditorIdRegex');
    Add('baseDisplayNameRegex');
  end;
  lApplyFilterRegex.S['anchoring'] := 'partial';
  lApplyFilterRegex.B['caseSensitive'] := False;
  lApplyFilterRegex.S['combinedWithPattern'] := 'rejected';
  lApplyFilterExtensions.S['regexTimeoutsField'] := 'result.regexTimeouts';

  // records.references recursion is opt-in so legacy relationship lookups stay
  // shallow unless a caller explicitly asks to union ChildGroup-owned records.
  lReferencesRecursive := Result.O['supports'].O['referencesRecursive'];
  lReferencesRecursive.B['defaultRecursive'] := False;
  with lReferencesRecursive.A['appliesTo'] do begin
    Add('CELL');
    Add('WRLD');
    Add('DIAL');
    Add('QUST');
  end;
  lReferencesRecursive.S['dedupBy'] := 'loadOrderFormId';
  lReferencesRecursive.S['limitSemantics'] := 'post-union-post-dedup';

  // records.conflict_status now surfaces aggregate conflict signal from the
  // existing ChildGroup seam without changing the main record conflict block.
  lConflictStatusChildGroup := Result.O['supports'].O['conflictStatusChildGroup'];
  lConflictStatusChildGroup.S['subBlockKey'] := 'childGroup';
  with lConflictStatusChildGroup.A['fields'] do begin
    Add('count');
    Add('hasConflict');
    Add('signatures');
    Add('conflictingHits');
    Add('conflictingHitsTruncated');
  end;
  lConflictStatusChildGroup.I['conflictingHitsMax'] := 20;
  lConflictStatusChildGroup.S['omittedWhen'] := 'no-child-group-or-empty-child-group';

  // records.create parent-spec is an opt-in write-side route into existing
  // ChildGroup owners; native xEdit Add still owns per-signature validity.
  lCreateParentSpec := Result.O['supports'].O['createParentSpec'];
  with lCreateParentSpec.A['supportedParents'] do begin
    Add('CELL');
    Add('DIAL');
    Add('QUST');
  end;
  with lCreateParentSpec.O['subGroupVocabulary'].A['CELL'] do begin
    Add('Persistent');
    Add('Temporary');
    Add('Visible when Distant');
  end;
  with lCreateParentSpec.O['defaultSubGroup'].O['CELL'] do begin
    S['REFR'] := 'Temporary';
    S['ACHR'] := 'Temporary';
    S['PGRD'] := 'Temporary';
    S['LAND'] := 'Temporary';
    S['NAVM'] := 'Temporary';
    S['_other_'] := 'Persistent';
  end;
  lCreateParentSpec.A['unsupportedParents'].Add('WRLD');
  lCreateParentSpec.S['wrldDeferralReason'] := 'Block/Sub-Block parent resolution deferred to a future phase';

  // r5 (contract 0.12): expose the inline string-decoding policy so MCP
  // clients can detect that this fork autodetects UTF-8 for translatable
  // fields and so callers know which startup flags switch the global default.
  Result.O['supports'].O['stringDecoding'].B['translatableInlineUtf8Autodetect'] := True;
  // defaultFallbackEncoding names the encoding the autodetect falls through to
  // when no per-def / per-file / CLI override applies. activeFallbackEncoding
  // reports the encoding currently in effect for the running daemon - it
  // changes when -cp:<...> / -cp-trans:<...> are passed at startup or when
  // the game language sets a non-1252 default through wbEncodingForLanguage.
  Result.O['supports'].O['stringDecoding'].S['defaultFallbackEncoding'] := 'cp1252';
  if Assigned(wbEncodingTrans) then
    Result.O['supports'].O['stringDecoding'].S['activeFallbackEncoding'] := wbEncodingTrans.EncodingName
  else
    Result.O['supports'].O['stringDecoding'].S['activeFallbackEncoding'] := 'cp1252';
  Result.O['supports'].O['stringDecoding'].S['asciiBehavior']       := 'cp1252-path-preserved';
  Result.O['supports'].O['stringDecoding'].A['autodetectScope'].Add('dfTranslatable');
  // Defense layers (RFC 3629 strict + heuristics) - clients can audit
  // expected behavior against these named layers when filing regressions.
  with Result.O['supports'].O['stringDecoding'].A['defenseLayers'] do begin
    Add('rfc3629-strict');
    Add('overlong-tightening');
    Add('surrogate-rejection');
    Add('noncharacter-rejection');
    Add('c1-control-rejection');
    Add('ascii-bypass');
    Add('bom-strip-leading');
  end;
  // Explicit per-file/per-def overrides always win. Latched-boolean check on
  // IwbFile, so explicit cp1252 still suppresses autodetect.
  with Result.O['supports'].O['stringDecoding'].A['overrideWins'] do begin
    Add('cpoverride-sidecar');
    Add('snam-cp-marker');
    Add('per-def-encoding-override');
  end;
  // Startup-only CLI flags that switch the global default encoding before any
  // plugin load. Already-shipped flags - documented here as supported.
  with Result.O['supports'].O['stringDecoding'].O['cliFlags'] do begin
    A['translatableDefault'].Add('-cp:<encoding>');
    A['translatableDefault'].Add('-cp-trans:<encoding>');
    A['nonTranslatableDefault'].Add('-cp-general:<encoding>');
    A['acceptedValues'].Add('utf-8');
    A['acceptedValues'].Add('utf8');
    A['acceptedValues'].Add('65001');
    A['acceptedValues'].Add('1252');
    A['acceptedValues'].Add('936');
    A['acceptedValues'].Add('932');
    A['acceptedValues'].Add('1251');
    A['acceptedValues'].Add('<any-windows-codepage-number>');
    S['scope'] := 'startup-only';
  end;
  // Known limitation: autodetect runs on read; the GUI write path still uses
  // the bsdGetEncoding chain (CP-1252 default unless override or CLI flag is
  // set). Saving an autodetected UTF-8 string through xEdit will round-trip
  // through CP-1252 encode and mojibake on disk. Use -cp:utf-8 / cpoverride
  // for read+write symmetric UTF-8.
  Result.O['supports'].O['stringDecoding'].S['readWriteAsymmetry'] :=
    'read-autodetects-write-uses-bsdGetEncoding';
end;

initialization
  // System commands self-register because they are safe before data loading.
  // Loaded-data command groups are linked here but registered through explicit
  // startup/capability seams so duplicate registration remains avoidable.
  xeAutomationRegisterCommand('system.ping', xeAutomationSystemPing);
  xeAutomationRegisterCommand('system.describe', xeAutomationSystemDescribe);
  xeAutomationRegisterCommand('system.capabilities', xeAutomationSystemCapabilities);

end.
