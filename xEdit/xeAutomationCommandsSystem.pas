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
begin
  Result := TJsonObject.Create;
  Result.S['contractVersion'] := '0.11';

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
end;

initialization
  // System commands self-register because they are safe before data loading.
  // Loaded-data command groups are linked here but registered through explicit
  // startup/capability seams so duplicate registration remains avoidable.
  xeAutomationRegisterCommand('system.ping', xeAutomationSystemPing);
  xeAutomationRegisterCommand('system.describe', xeAutomationSystemDescribe);
  xeAutomationRegisterCommand('system.capabilities', xeAutomationSystemCapabilities);

end.
