{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeAutomationCommandsJobs;

interface

procedure xeAutomationRegisterJobsCommands;

implementation

uses
  SysUtils,
  Math,
  JsonDataObjects,
  xeAutomationErrors,
  xeAutomationJobs,
  xeAutomationMutationPolicy,
  xeAutomationObjectModel,
  xeAutomationRegistry;

function xeAutomationJobMutationCategory(const AKind: string; const ADryRun, ADryRunSpecified: Boolean): string;
begin
  Result := '';
  if (not ADryRunSpecified) or ADryRun then
    Exit;

  if SameText(AKind, 'cleaning.quick_clean') or SameText(AKind, 'cleaning.quick_auto_clean') or
     SameText(AKind, 'cleaning.sort_and_clean_masters') then
    Exit('cleaning-mutation');

  if SameText(AKind, 'files.hygiene.batch') then
    Exit('files-mutation');

  if SameText(AKind, 'plugin.formids.compact_for_esl') or SameText(AKind, 'plugin.esl.apply') then
    Exit('plugin-analysis-mutation');
end;

function xeAutomationRequireObjectArg(const AArgs: TJsonObject; const AName: string): TJsonObject;
begin
  if not Assigned(AArgs) then
    raise xeAutomationInvalidRequest('Automation command args are required');
  if not AArgs.Contains(AName) then
    raise xeAutomationInvalidRequest(Format('Automation arg "%s" is required', [AName]));
  if AArgs.Types[AName] <> jdtObject then
    raise xeAutomationInvalidRequest(Format('Automation arg field "%s" must be an object', [AName]));
  Result := AArgs.O[AName];
end;

function xeAutomationReadOptionalObjectArg(const AArgs: TJsonObject; const AName: string): TJsonObject;
begin
  Result := nil;
  if not Assigned(AArgs) or not AArgs.Contains(AName) then
    Exit;
  if AArgs.Types[AName] <> jdtObject then
    raise xeAutomationInvalidRequest(Format('Automation arg field "%s" must be an object', [AName]));
  Result := AArgs.O[AName];
end;

function xeAutomationReadIntegerArg(const AArgs: TJsonObject; const AName: string; const ADefault: Integer): Integer;
begin
  Result := ADefault;
  if not Assigned(AArgs) or not AArgs.Contains(AName) then
    Exit;
  if not (AArgs.Types[AName] in [jdtInt, jdtLong]) then
    raise xeAutomationInvalidRequest(Format('Automation arg field "%s" must be an integer', [AName]));
  Result := AArgs.I[AName];
end;

function xeAutomationJobsStart(const AArgs: TJsonObject): TJsonObject;
var
  lKind: string;
  lTarget: TJsonObject;
  lOptions: TJsonObject;
  lHasDryRun: Boolean;
  lDryRun: Boolean;
  lMutationCategory: string;
  lDeniedReason: string;
begin
  // Validate request shape before job-manager state checks so malformed start
  // requests never get masked by an unrelated active job conflict.
  lKind := xeAutomationRequireStringArg(AArgs, 'kind');
  lTarget := xeAutomationRequireObjectArg(AArgs, 'target');
  lOptions := xeAutomationReadOptionalObjectArg(AArgs, 'options');
  lDryRun := xeAutomationReadBooleanArg(AArgs, 'dryRun', lHasDryRun);
  lMutationCategory := xeAutomationJobMutationCategory(lKind, lDryRun, lHasDryRun);
  if (lMutationCategory <> '') and not xeAutomationMutationPolicyConsentSatisfied(lDeniedReason) then begin
    Result := xeAutomationErrorsBuildConsentRequired(lKind, lMutationCategory, lDeniedReason);
    Exit;
  end;

  Result := xeAutomationStartJob(lKind, lDryRun, lHasDryRun, lTarget, lOptions);
end;

function xeAutomationJobsGet(const AArgs: TJsonObject): TJsonObject;
begin
  Result := xeAutomationGetJob(xeAutomationRequireStringArg(AArgs, 'jobId'));
end;

function xeAutomationJobsFindings(const AArgs: TJsonObject): TJsonObject;
var
  lJobId: string;
  lOffset: Integer;
  lLimit: Integer;
begin
  lJobId := xeAutomationRequireStringArg(AArgs, 'jobId');
  lOffset := xeAutomationReadIntegerArg(AArgs, 'offset', 0);
  lLimit := xeAutomationReadIntegerArg(AArgs, 'limit', 100);
  if lOffset < 0 then
    raise xeAutomationInvalidRequest('Automation arg "offset" must be non-negative');
  if lLimit <= 0 then
    raise xeAutomationInvalidRequest('Automation arg "limit" must be positive');
  lLimit := Min(lLimit, 500);
  Result := xeAutomationGetJobFindings(lJobId, lOffset, lLimit);
end;

function xeAutomationJobsCancel(const AArgs: TJsonObject): TJsonObject;
begin
  Result := xeAutomationCancelJob(xeAutomationRequireStringArg(AArgs, 'jobId'));
end;

function xeAutomationJobsDiscard(const AArgs: TJsonObject): TJsonObject;
begin
  Result := xeAutomationDiscardJob(xeAutomationRequireStringArg(AArgs, 'jobId'));
end;

procedure xeAutomationRegisterJobsCommands;
begin
  xeAutomationRegisterCommand('jobs.start', xeAutomationJobsStart);
  xeAutomationRegisterCommand('jobs.get', xeAutomationJobsGet);
  xeAutomationRegisterCommand('jobs.findings', xeAutomationJobsFindings);
  xeAutomationRegisterCommand('jobs.cancel', xeAutomationJobsCancel);
  xeAutomationRegisterCommand('jobs.discard', xeAutomationJobsDiscard);
end;

end.
