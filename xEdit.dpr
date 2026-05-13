{******************************************************************************


  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

{$I xeDefines.inc}

{$IFDEF EXCEPTION_LOGGING_ENABLED}
// JCL_DEBUG_EXPERT_GENERATEJDBG OFF
// JCL_DEBUG_EXPERT_INSERTJDBG ON
// JCL_DEBUG_EXPERT_DELETEMAPFILE ON
{$ENDIF}

program xEdit;

{$RTTI EXPLICIT METHODS([vcPrivate, vcProtected, vcPublic, vcPublished]) PROPERTIES([vcPrivate, vcProtected, vcPublic, vcPublished]) FIELDS([vcPrivate, vcProtected, vcPublic, vcPublished])}

uses
  {$IFDEF EXCEPTION_LOGGING_ENABLED}
  nxExceptionHook,
  {$ENDIF }
  Winapi.Windows,
  Forms,
  Dialogs,
  SysUtils,
  VirtualTrees,
  VTEditors,
  VirtualEditTree,
  {$IFNDEF LiteVersion}
  cxVTEditors,
  {$ENDIF}
  Vcl.Themes,
  Vcl.Styles,
  Vcl.Styles.Hooks,
  Vcl.Styles.Utils.Menus,
  Vcl.Styles.Utils.Forms,
  Vcl.Styles.Utils.StdCtrls,
  Vcl.Styles.Utils.ScreenTips,
  xeAutomationCommandsCleaning in 'xEdit\xeAutomationCommandsCleaning.pas',
  xeAutomationCommandsElements in 'xEdit\xeAutomationCommandsElements.pas',
  xeAutomationCommandsFileHygiene in 'xEdit\xeAutomationCommandsFileHygiene.pas',
  xeAutomationCommandsFiles in 'xEdit\xeAutomationCommandsFiles.pas',
  xeAutomationCommandsJobs in 'xEdit\xeAutomationCommandsJobs.pas',
  xeAutomationCommandsPluginAnalysis in 'xEdit\xeAutomationCommandsPluginAnalysis.pas',
  xeAutomationCommandsRecords in 'xEdit\xeAutomationCommandsRecords.pas',
  xeAutomationCommandsSession in 'xEdit\xeAutomationCommandsSession.pas',
  xeAutomationCommandsSessionNavigation in 'xEdit\xeAutomationCommandsSessionNavigation.pas',
  xeAutomationCommandsScripts in 'xEdit\xeAutomationCommandsScripts.pas',
  xeAutomationCommandsSystem in 'xEdit\xeAutomationCommandsSystem.pas',
  xeAutomationCommandsValidation in 'xEdit\xeAutomationCommandsValidation.pas',
  xeAutomationConflictSnapshot in 'xEdit\xeAutomationConflictSnapshot.pas',
  xeAutomationDataLookup in 'xEdit\xeAutomationDataLookup.pas',
  xeAutomationErrors in 'xEdit\xeAutomationErrors.pas',
  xeAutomationGuiSnapshot in 'xEdit\xeAutomationGuiSnapshot.pas',
  xeAutomationHostCli in 'xEdit\xeAutomationHostCli.pas',
  xeAutomationJobs in 'xEdit\xeAutomationJobs.pas',
  xeAutomationMutationPolicy in 'xEdit\xeAutomationMutationPolicy.pas',
  xeAutomationObjectModel in 'xEdit\xeAutomationObjectModel.pas',
  xeAutomationRegistry in 'xEdit\xeAutomationRegistry.pas',
  xeAutomationServeLoop in 'xEdit\xeAutomationServeLoop.pas',
  xeAutomationSession in 'xEdit\xeAutomationSession.pas',
  xeAutomationTransportPipe in 'xEdit\xeAutomationTransportPipe.pas',
  xeAutomationTypes in 'xEdit\xeAutomationTypes.pas',
  xeInit in 'xEdit\xeInit.pas',
  wbBetterStringList in 'Core\wbBetterStringList.pas',
  wbBSA in 'Core\wbBSA.pas',
  wbCommandLine in 'Core\wbCommandLine.pas',
  wbDataFormat in 'Core\wbDataFormat.pas',
  wbDataFormatMaterial in 'Core\wbDataFormatMaterial.pas',
  wbDataFormatMisc in 'Core\wbDataFormatMisc.pas',
  wbDataFormatNif in 'Core\wbDataFormatNif.pas',
  wbDataFormatNifTypes in 'Core\wbDataFormatNifTypes.pas',
  wbDefinitionsCommon in 'Core\wbDefinitionsCommon.pas',
  wbDefinitionsFNV in 'Core\wbDefinitionsFNV.pas',
  wbDefinitionsFNVSaves in 'Core\wbDefinitionsFNVSaves.pas',
  wbDefinitionsFO3 in 'Core\wbDefinitionsFO3.pas',
  wbDefinitionsFO3Saves in 'Core\wbDefinitionsFO3Saves.pas',
  wbDefinitionsFO4 in 'Core\wbDefinitionsFO4.pas',
  wbDefinitionsFO4Saves in 'Core\wbDefinitionsFO4Saves.pas',
  wbDefinitionsFO76 in 'Core\wbDefinitionsFO76.pas',
  wbDefinitionsTES3 in 'Core\wbDefinitionsTES3.pas',
  wbDefinitionsTES4 in 'Core\wbDefinitionsTES4.pas',
  wbDefinitionsTES4Saves in 'Core\wbDefinitionsTES4Saves.pas',
  wbDefinitionsTES5 in 'Core\wbDefinitionsTES5.pas',
  wbDefinitionsTES5Saves in 'Core\wbDefinitionsTES5Saves.pas',
  wbHalfFloat in 'Core\wbHalfFloat.pas',
  wbHardcoded in 'Core\wbHardcoded.pas' {wbHardcodedContainer: TDataModule},
  wbHelpers in 'Core\wbHelpers.pas',
  wbImplementation in 'Core\wbImplementation.pas',
  wbInterface in 'Core\wbInterface.pas',
  wbLocalization in 'Core\wbLocalization.pas',
  wbLOD in 'Core\wbLOD.pas',
  wbModGroups in 'Core\wbModGroups.pas',
  wbNifMath in 'Core\wbNifMath.pas',
  wbNifScanner in 'Core\wbNifScanner.pas',
  wbSaveInterface in 'Core\wbSaveInterface.pas',
  wbSort in 'Core\wbSort.pas',
  wbStreams in 'Core\wbStreams.pas',
  xeDeveloperMessageForm in 'xEdit\xeDeveloperMessageForm.pas' {frmDeveloperMessage},
  xeEditWarningForm in 'xEdit\xeEditWarningForm.pas' {frmEditWarning},
  xeFileSelectForm in 'xEdit\xeFileSelectForm.pas' {frmFileSelect},
  xeFilterOptionsForm in 'xEdit\xeFilterOptionsForm.pas' {frmFilterOptions},
  xeLegendForm in 'xEdit\xeLegendForm.pas' {frmLegend},
  xeLocalizationForm in 'xEdit\xeLocalizationForm.pas' {frmLocalization},
  xeLocalizePluginForm in 'xEdit\xeLocalizePluginForm.pas' {frmLocalizePlugin},
  xeLODGenForm in 'xEdit\xeLODGenForm.pas', {frmLODGen}
  xeLogAnalyzerForm in 'xEdit\xeLogAnalyzerForm.pas' {frmLogAnalyzer},
  xeMainForm in 'xEdit\xeMainForm.pas' {frmMain},
  xeModGroupEditForm in 'xEdit\xeModGroupEditForm.pas', {frmModGroupEdit}
  xeModGroupSelectForm in 'xEdit\xeModGroupSelectForm.pas', {frmModGroupSelect}
  xeModuleSelectForm in 'xEdit\xeModuleSelectForm.pas', {frmModuleSelect}
  xeOptionsForm in 'xEdit\xeOptionsForm.pas' {frmOptions},
  xeRichEditForm in 'xEdit\xeRichEditForm.pas' {frmRichEdit},
  xejviScriptAdapter in 'xEdit\JvI\xejviScriptAdapter.pas',
  xejviScriptAdapterDF in 'xEdit\JvI\xejviScriptAdapterDF.pas',
  xejviScriptAdapterMisc in 'xEdit\JvI\xejviScriptAdapterMisc.pas',
  xeScriptExecutionGuard in 'xEdit\xeScriptExecutionGuard.pas',
  xeHeadlessJvIScriptHost in 'xEdit\xeHeadlessJvIScriptHost.pas',
  xeScriptRuntimePolicy in 'xEdit\xeScriptRuntimePolicy.pas',
  xeScriptForm in 'xEdit\xeScriptForm.pas' {frmScript},
  xeTipForm in 'xEdit\xeTipForm.pas', {frmTip}
  xeViewElementsForm in 'xEdit\xeViewElementsForm.pas' {frmViewElements},
  xeWaitForm in 'xEdit\xeWaitForm.pas' {frmWait},
  xeWorldspaceCellDetailsForm in 'xEdit\xeWorldspaceCellDetailsForm.pas' {frmWorldspaceCellDetails},
  xeScriptHost in 'xEdit\xeScriptHost.pas',
  xejviScriptHost in 'xEdit\JvI\xejviScriptHost.pas',
  wbDefinitionsSF1 in 'Core\wbDefinitionsSF1.pas',
  wbDefinitionsSignatures in 'Core\wbDefinitionsSignatures.pas',
  wbLoadOrder in 'Core\wbLoadOrder.pas';

{$R *.res}
{$MAXSTACKSIZE 2097152}

const
  IMAGE_FILE_LARGE_ADDRESS_AWARE = $0020;

var
  lAutomationExitCode: Integer;

{$SetPEFlags IMAGE_FILE_LARGE_ADDRESS_AWARE}

begin
  UseLatestCommonDialogs := True;
  SysUtils.FormatSettings.DecimalSeparator := '.';

  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.UpdateFormatSettings := False;
  Application.HintHidePause := 10000;

  xeInitStyles;

  if not xeDoInit then
    Exit;

  if xeIconResource <> '' then begin
    var lIconHandle := LoadIcon(HInstance, PChar(xeIconResource));
    if lIconHandle <> 0 then
      Application.Icon.Handle := lIconHandle;
  end;

  {$IFDEF EXCEPTION_LOGGING_ENABLED}
  nxEHAppVersion := wbApplicationTitle;
  {$ENDIF}
  Application.Title := wbApplicationTitle;

  // Keep the lightweight one-shot CLI path for existing `system.*` style calls;
  // daemon serve/call mode is being added alongside it for loaded-data sessions.
  if xeAutomationHasConflictingModes then begin
    if xeAutomationTryRejectInvalidSetup('Conflicting automation modes were requested', lAutomationExitCode) then begin
      ExitCode := lAutomationExitCode;
      Exit;
    end;
  end;

  // Run automation requests before the main form exists so scripted
  // callers get a deterministic headless path that is independent of UI lifecycle state.
  if xeAutomationCliRequested or (xeAutomationMode = xamCall) then begin
    if xeAutomationTryRunCli(lAutomationExitCode) then begin
      ExitCode := lAutomationExitCode;
      Exit;
    end;
  end;

  try
    Application.CreateForm(TfrmMain, frmMain);
    Application.Run;
  finally
    DoRename;
  end;
end.
