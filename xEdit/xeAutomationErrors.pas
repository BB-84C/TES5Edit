{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeAutomationErrors;

interface

uses
  SysUtils,
  JsonDataObjects;

const
  // These codes are part of the CLI contract, so callers should branch on them
  // instead of depending on Delphi exception class names or message text.
  xeAutomationErrorInvalidRequest   = 'invalid_request';
  xeAutomationErrorUnknownCommand   = 'unknown_command';
  xeAutomationErrorFileNotFound     = 'file_not_found';
  xeAutomationErrorRecordNotFound   = 'record_not_found';
  xeAutomationErrorElementNotFound  = 'element_not_found';
  xeAutomationErrorInvalidTarget    = 'invalid_target';
  xeAutomationErrorConsentRequired  = 'consent_required';
  xeAutomationErrorMutationNotAllowed = 'mutation_not_allowed';
  xeAutomationErrorReadOnlyTarget  = 'read_only_target';
  xeAutomationErrorStateConflict   = 'state_conflict';
  xeAutomationErrorSaveFailed      = 'save_failed';
  xeAutomationErrorUnknownJobKind  = 'unknown_job_kind';
  xeAutomationErrorJobNotFound     = 'job_not_found';
  xeAutomationErrorJobNotTerminal  = 'job_not_terminal';
  xeAutomationErrorJobBusy         = 'job_busy';
  xeAutomationErrorOperationNotCancelable = 'operation_not_cancelable';
  xeAutomationErrorUnsupportedGameMode = 'unsupported_game_mode';
  xeAutomationErrorUnsafeOperation = 'unsafe_operation';
  xeAutomationErrorEligibilityFailed = 'eligibility_failed';
  xeAutomationErrorInternalError   = 'internal_error';

  // ESL analysis finding codes are protocol-facing constants so later compact/apply
  // jobs can reuse the same branchable values without coupling clients to messages.
  xeAutomationFindingRequiresFormIDCompaction = 'requires_formid_compaction';
  xeAutomationFindingTooManyNewRecordsForLight = 'too_many_new_records_for_light';
  xeAutomationFindingNonEditableTarget = 'non_editable_target';
  xeAutomationFindingNonEditableReferrer = 'non_editable_referrer';
  xeAutomationFindingProtectedTarget = 'protected_target';
  xeAutomationFindingUnsupportedGameMode = 'unsupported_game_mode';
  xeAutomationFindingNewCellRecordRisk = 'new_cell_record_risk';

  // Validation finding codes are stable protocol values; messages may preserve
  // native xEdit wording, but clients should branch on these constants.
  xeAutomationFindingValidationCheckError = 'xedit_check_error';
  xeAutomationFindingValidationItmRecord = 'itm_record';
  xeAutomationFindingValidationDeletedReference = 'deleted_reference';
  xeAutomationFindingValidationDeletedNavmesh = 'deleted_navmesh';
  xeAutomationFindingValidationDeletedReferenceSkipped = 'deleted_reference_skipped';
  xeAutomationFindingValidationNoErrorsFound = 'no_errors_found';
  xeAutomationFindingValidationNoItmRecordsFound = 'no_itm_records_found';
  xeAutomationFindingValidationNoDeletedRefsFound = 'no_deleted_refs_found';

  // Cleaning finding codes are stable protocol values emitted through jobs.findings;
  // keeping them beside the other taxonomy constants prevents example/docs drift.
  xeAutomationFindingCleaningItmRecordsPlanned = 'itm_records_planned';
  xeAutomationFindingCleaningItmRecordsRemoved = 'itm_records_removed';
  xeAutomationFindingCleaningItmRecordsSkipped = 'itm_records_skipped';
  xeAutomationFindingCleaningDeletedRefsPlanned = 'deleted_refs_planned';
  xeAutomationFindingCleaningDeletedRefsUndeletedDisabled = 'deleted_refs_undeleted_disabled';
  xeAutomationFindingCleaningDeletedRefsSkipped = 'deleted_refs_skipped';
  xeAutomationFindingCleaningDeletedNavmeshSkipped = 'deleted_navmesh_skipped';
  xeAutomationFindingCleaningMastersSortCleanPlanned = 'masters_sort_clean_planned';
  xeAutomationFindingCleaningMastersSortCleanApplied = 'masters_sort_clean_applied';
  xeAutomationFindingCleaningMastersSortCleanSkipped = 'masters_sort_clean_skipped';

type
  ExeAutomationError = class(Exception)
  private
    FCode: string;
    FDetails: TJsonObject;
  public
    constructor Create(const aCode, aMessage: string); overload;
    // The details overload copies aDetails so callers keep owning their original
    // JSON object while the raised exception remains safe across catch paths.
    constructor Create(const aCode, aMessage: string; const aDetails: TJsonObject); overload;
    destructor Destroy; override;
    property Code: string read FCode;
    property Details: TJsonObject read FDetails;
  end;

function xeAutomationNewError(const aCode, aMessage: string; const aDetails: TJsonObject = nil): ExeAutomationError;
function xeAutomationInvalidRequest(const aMessage: string): ExeAutomationError;
function xeAutomationUnknownCommand(const aCommand: string): ExeAutomationError;
function xeAutomationInvalidTarget(const aMessage: string): ExeAutomationError;
function xeAutomationMutationNotAllowed(const aMessage: string): ExeAutomationError;
function xeAutomationReadOnlyTarget(const aMessage: string): ExeAutomationError;
function xeAutomationStateConflict(const aMessage: string): ExeAutomationError;
function xeAutomationSaveFailed(const aMessage: string): ExeAutomationError;
function xeAutomationRecordNotFound(const AFileName, AFormID: string): ExeAutomationError;
function xeAutomationElementNotFound(const AFileName, AFormID, APath: string): ExeAutomationError;
function xeAutomationErrorsBuildConsentRequired(
  const ACommandName: string;
  const AMutationCategory: string;
  const ADeniedReason: string): TJsonObject;

implementation

constructor ExeAutomationError.Create(const aCode, aMessage: string);
begin
  inherited Create(aMessage);
  FCode := aCode;
  FDetails := nil;
end;

constructor ExeAutomationError.Create(const aCode, aMessage: string; const aDetails: TJsonObject);
begin
  inherited Create(aMessage);
  FCode := aCode;
  FDetails := nil;
  if Assigned(aDetails) then begin
    FDetails := TJsonObject.Create;
    FDetails.Assign(aDetails);
  end;
end;

destructor ExeAutomationError.Destroy;
begin
  FDetails.Free;
  inherited;
end;

function xeAutomationNewError(const aCode, aMessage: string; const aDetails: TJsonObject): ExeAutomationError;
begin
  Result := ExeAutomationError.Create(aCode, aMessage, aDetails);
end;

function xeAutomationInvalidRequest(const aMessage: string): ExeAutomationError;
begin
  Result := xeAutomationNewError(xeAutomationErrorInvalidRequest, aMessage);
end;

function xeAutomationUnknownCommand(const aCommand: string): ExeAutomationError;
begin
  Result := xeAutomationNewError(
    xeAutomationErrorUnknownCommand,
    Format('Automation command not registered: %s', [aCommand])
  );
end;

function xeAutomationInvalidTarget(const aMessage: string): ExeAutomationError;
begin
  Result := xeAutomationNewError(xeAutomationErrorInvalidTarget, aMessage);
end;

function xeAutomationMutationNotAllowed(const aMessage: string): ExeAutomationError;
begin
  Result := xeAutomationNewError(xeAutomationErrorMutationNotAllowed, aMessage);
end;

function xeAutomationReadOnlyTarget(const aMessage: string): ExeAutomationError;
begin
  Result := xeAutomationNewError(xeAutomationErrorReadOnlyTarget, aMessage);
end;

function xeAutomationStateConflict(const aMessage: string): ExeAutomationError;
begin
  Result := xeAutomationNewError(xeAutomationErrorStateConflict, aMessage);
end;

function xeAutomationSaveFailed(const aMessage: string): ExeAutomationError;
begin
  Result := xeAutomationNewError(xeAutomationErrorSaveFailed, aMessage);
end;

function xeAutomationRecordNotFound(const AFileName, AFormID: string): ExeAutomationError;
begin
  Result := xeAutomationNewError(
    xeAutomationErrorRecordNotFound,
    Format('Automation record not found: %s:%s', [AFileName, AFormID])
  );
end;

function xeAutomationElementNotFound(const AFileName, AFormID, APath: string): ExeAutomationError;
begin
  Result := xeAutomationNewError(
    xeAutomationErrorElementNotFound,
    Format('Automation element not found: %s:%s:%s', [AFileName, AFormID, APath])
  );
end;

function xeAutomationErrorsBuildConsentRequired(
  const ACommandName: string;
  const AMutationCategory: string;
  const ADeniedReason: string): TJsonObject;
var
  lDetails: TJsonObject;
begin
  lDetails := TJsonObject.Create;
  try
    // Consent refusal is a request-boundary protocol error, so route it through
    // the same typed-error path as existing command validation failures.
    lDetails.S['deniedReason'] := ADeniedReason;
    lDetails.S['commandName'] := ACommandName;
    lDetails.S['mutationCategory'] := AMutationCategory;
    raise xeAutomationNewError(
      xeAutomationErrorConsentRequired,
      'Automation mutating command requires -IKnowWhatImDoing',
      lDetails
    );
  finally
    lDetails.Free;
  end;
end;

end.
