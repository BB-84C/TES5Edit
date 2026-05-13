{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeAutomationJobs;

interface

uses
  JsonDataObjects;

type
  TxeAutomationJobStartValidator = procedure(var ADryRun: Boolean; const ADryRunSpecified: Boolean; const ATarget, AOptions: TJsonObject);
  TxeAutomationJobHandler = procedure(const AJobId: string; const ADryRun, ADryRunSpecified: Boolean; const ATarget, AOptions: TJsonObject;
    const AFindings: TJsonArray; const ASummary, AResult, AFailure: TJsonObject);

procedure xeAutomationRegisterJobKind(const AKind: string; const AHandler: TxeAutomationJobHandler);
procedure xeAutomationRegisterJobKindWithValidator(const AKind: string; const AHandler: TxeAutomationJobHandler;
  const AValidator: TxeAutomationJobStartValidator);
function xeAutomationListJobKinds: TArray<string>;
function xeAutomationStartJob(const AKind: string; const ADryRun, ADryRunSpecified: Boolean; const ATarget, AOptions: TJsonObject): TJsonObject;
function xeAutomationGetJob(const AJobId: string): TJsonObject;
function xeAutomationGetJobFindings(const AJobId: string; const AOffset, ALimit: Integer): TJsonObject;
function xeAutomationCancelJob(const AJobId: string): TJsonObject;
function xeAutomationDiscardJob(const AJobId: string): TJsonObject;

implementation

uses
  System.Generics.Collections,
  SysUtils,
  Classes,
  xeAutomationErrors;

const
  xeAutomationTerminalJobRetention = 16;

type
  TxeAutomationJobKindRegistration = record
    Handler: TxeAutomationJobHandler;
    Validator: TxeAutomationJobStartValidator;
  end;

  TxeAutomationJobState = (xajsQueued, xajsRunning, xajsSucceeded, xajsFailed, xajsCancelRequested, xajsCanceled);

  TxeAutomationJob = class
  public
    Id: string;
    Kind: string;
    State: TxeAutomationJobState;
    Sequence: Int64;
    DryRun: Boolean;
    DryRunSpecified: Boolean;
    Target: TJsonObject;
    Options: TJsonObject;
    SummaryData: TJsonObject;
    ResultData: TJsonObject;
    FailureData: TJsonObject;
    Findings: TJsonArray;
    constructor Create;
    destructor Destroy; override;
    function IsTerminal: Boolean;
    function IsCancelable: Boolean;
  end;

var
  xeAutomationJobKinds: TDictionary<string, TxeAutomationJobKindRegistration>;
  xeAutomationJobList: TObjectList<TxeAutomationJob>;
  xeAutomationNextJobId: Integer;
  xeAutomationNextJobSequence: Int64;
  xeAutomationActiveJob: TxeAutomationJob;

constructor TxeAutomationJob.Create;
begin
  inherited;
  Target := TJsonObject.Create;
  Options := TJsonObject.Create;
  SummaryData := TJsonObject.Create;
  ResultData := TJsonObject.Create;
  FailureData := TJsonObject.Create;
  Findings := TJsonArray.Create;
end;

destructor TxeAutomationJob.Destroy;
begin
  Findings.Free;
  FailureData.Free;
  ResultData.Free;
  SummaryData.Free;
  Options.Free;
  Target.Free;
  inherited;
end;

function TxeAutomationJob.IsTerminal: Boolean;
begin
  Result := State in [xajsSucceeded, xajsFailed, xajsCanceled];
end;

function TxeAutomationJob.IsCancelable: Boolean;
begin
  // Native xEdit operations are advanced only on the main request path. Once a
  // handler is running there is no safe mid-operation interrupt point to expose.
  Result := State in [xajsQueued, xajsCancelRequested];
end;

function xeAutomationNormalizeJobKind(const AKind: string): string;
begin
  Result := LowerCase(Trim(AKind));
end;

function xeAutomationGetJobKinds: TDictionary<string, TxeAutomationJobKindRegistration>;
begin
  if not Assigned(xeAutomationJobKinds) then
    xeAutomationJobKinds := TDictionary<string, TxeAutomationJobKindRegistration>.Create;
  Result := xeAutomationJobKinds;
end;

function xeAutomationGetJobs: TObjectList<TxeAutomationJob>;
begin
  if not Assigned(xeAutomationJobList) then
    xeAutomationJobList := TObjectList<TxeAutomationJob>.Create(True);
  Result := xeAutomationJobList;
end;

function xeAutomationJobStateName(const AState: TxeAutomationJobState): string;
begin
  case AState of
    xajsQueued: Result := 'queued';
    xajsRunning: Result := 'running';
    xajsSucceeded: Result := 'succeeded';
    xajsFailed: Result := 'failed';
    xajsCancelRequested: Result := 'cancel_requested';
    xajsCanceled: Result := 'canceled';
  else
    Result := 'failed';
  end;
end;

procedure xeAutomationRegisterJobKindWithValidator(const AKind: string; const AHandler: TxeAutomationJobHandler;
  const AValidator: TxeAutomationJobStartValidator);
var
  lKind: string;
  lRegistration: TxeAutomationJobKindRegistration;
begin
  if not Assigned(AHandler) then
    raise Exception.Create('Automation job handler is required');

  lKind := xeAutomationNormalizeJobKind(AKind);
  if lKind = '' then
    raise Exception.Create('Automation job kind is required');
  if xeAutomationGetJobKinds.ContainsKey(lKind) then
    raise Exception.CreateFmt('Automation job kind already registered: %s', [AKind]);

  lRegistration.Handler := AHandler;
  lRegistration.Validator := AValidator;
  xeAutomationGetJobKinds.Add(lKind, lRegistration);
end;

procedure xeAutomationRegisterJobKind(const AKind: string; const AHandler: TxeAutomationJobHandler);
begin
  xeAutomationRegisterJobKindWithValidator(AKind, AHandler, nil);
end;

function xeAutomationListJobKinds: TArray<string>;
var
  lKinds: TStringList;
  lPair: TPair<string, TxeAutomationJobKindRegistration>;
  i: Integer;
begin
  lKinds := TStringList.Create;
  try
    for lPair in xeAutomationGetJobKinds do
      lKinds.Add(lPair.Key);
    lKinds.Sort;

    SetLength(Result, lKinds.Count);
    for i := 0 to Pred(lKinds.Count) do
      Result[i] := lKinds[i];
  finally
    lKinds.Free;
  end;
end;

function xeAutomationFindJob(const AJobId: string): TxeAutomationJob;
var
  lJob: TxeAutomationJob;
begin
  Result := nil;
  for lJob in xeAutomationGetJobs do
    if SameText(lJob.Id, Trim(AJobId)) then
      Exit(lJob);
end;

function xeAutomationRequireJob(const AJobId: string): TxeAutomationJob;
begin
  Result := xeAutomationFindJob(AJobId);
  if not Assigned(Result) then
    raise xeAutomationNewError(xeAutomationErrorJobNotFound, Format('Automation job not found: %s', [AJobId]));
end;

procedure xeAutomationCopyJsonObject(const ASource, ADest: TJsonObject);
begin
  ADest.Clear;
  if Assigned(ASource) then
    ADest.Assign(ASource);
end;

function xeAutomationNewJobSnapshot(const AJob: TxeAutomationJob): TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.S['jobId'] := AJob.Id;
  Result.S['kind'] := AJob.Kind;
  Result.S['state'] := xeAutomationJobStateName(AJob.State);
  Result.B['terminal'] := AJob.IsTerminal;
  Result.B['cancelable'] := AJob.IsCancelable;
  Result.B['dryRun'] := AJob.DryRun;
  Result.B['dryRunSpecified'] := AJob.DryRunSpecified;
  Result.L['sequence'] := AJob.Sequence;
  Result.I['findingCount'] := AJob.Findings.Count;
  if AJob.SummaryData.Count > 0 then
    Result.O['summary'].Assign(AJob.SummaryData);
  if AJob.ResultData.Count > 0 then
    Result.O['result'].Assign(AJob.ResultData);
  if AJob.FailureData.Count > 0 then
    Result.O['failure'].Assign(AJob.FailureData);
end;

procedure xeAutomationWriteFindingJobFields(const ATarget: TJsonObject; const AJob: TxeAutomationJob);
begin
  ATarget.S['jobId'] := AJob.Id;
  ATarget.S['kind'] := AJob.Kind;
  ATarget.S['state'] := xeAutomationJobStateName(AJob.State);
  ATarget.B['terminal'] := AJob.IsTerminal;
  ATarget.B['cancelable'] := AJob.IsCancelable;
  ATarget.B['dryRun'] := AJob.DryRun;
end;

procedure xeAutomationAddFindingCopy(const ADest: TJsonArray; const ASource: TJsonArray; const AIndex: Integer);
begin
  case ASource.Types[AIndex] of
    jdtString: ADest.Add(ASource.S[AIndex]);
    jdtInt: ADest.Add(ASource.I[AIndex]);
    jdtLong: ADest.Add(ASource.L[AIndex]);
    jdtULong: ADest.Add(ASource.U[AIndex]);
    jdtFloat: ADest.Add(ASource.F[AIndex]);
    jdtDateTime: ADest.Add(ASource.D[AIndex]);
    jdtUtcDateTime: ADest.AddUtcDateTime(ASource.DUtc[AIndex]);
    jdtBool: ADest.Add(ASource.B[AIndex]);
    jdtArray: ADest.Add(ASource.A[AIndex].Clone);
    jdtObject: ADest.Add(ASource.O[AIndex].Clone);
  else
    ADest.AddObject(nil);
  end;
end;

procedure xeAutomationPruneTerminalJobs;
var
  lTerminalCount: Integer;
  i: Integer;
  lJob: TxeAutomationJob;
begin
  lTerminalCount := 0;
  for lJob in xeAutomationGetJobs do
    if lJob.IsTerminal then
      Inc(lTerminalCount);

  i := 0;
  while (lTerminalCount > xeAutomationTerminalJobRetention) and (i < xeAutomationGetJobs.Count) do begin
    lJob := xeAutomationGetJobs[i];
    if lJob.IsTerminal and (lJob <> xeAutomationActiveJob) then begin
      xeAutomationGetJobs.Delete(i);
      Dec(lTerminalCount);
      Continue;
    end;
    Inc(i);
  end;
end;

procedure xeAutomationFinishActiveJobIfTerminal(const AJob: TxeAutomationJob);
begin
  if (AJob = xeAutomationActiveJob) and AJob.IsTerminal then begin
    xeAutomationActiveJob := nil;
    xeAutomationPruneTerminalJobs;
  end;
end;

procedure xeAutomationAdvanceJob(const AJob: TxeAutomationJob);
var
  lRegistration: TxeAutomationJobKindRegistration;
begin
  if not Assigned(AJob) or AJob.IsTerminal then
    Exit;

  // Jobs are deliberately poll-driven from jobs.get instead of using a worker
  // thread; xEdit's loaded plugin graph is UI/main-thread state and many native
  // operations assume that thread-safety boundary.
  if AJob.State = xajsCancelRequested then begin
    AJob.State := xajsCanceled;
    xeAutomationFinishActiveJobIfTerminal(AJob);
    Exit;
  end;

  if AJob.State <> xajsQueued then
    Exit;

  AJob.State := xajsRunning;
  try
    if not xeAutomationGetJobKinds.TryGetValue(AJob.Kind, lRegistration) then
      raise xeAutomationNewError(xeAutomationErrorUnknownJobKind, Format('Automation job kind not registered: %s', [AJob.Kind]));
    lRegistration.Handler(AJob.Id, AJob.DryRun, AJob.DryRunSpecified, AJob.Target, AJob.Options, AJob.Findings,
      AJob.SummaryData, AJob.ResultData, AJob.FailureData);
    if AJob.State = xajsCancelRequested then
      AJob.State := xajsCanceled
    else if AJob.FailureData.Count > 0 then
      AJob.State := xajsFailed
    else
      AJob.State := xajsSucceeded;
  except
    on E: ExeAutomationError do begin
      // Accepted jobs report execution failures in durable job state instead of
      // turning a later poll into a transport-level error envelope.
      AJob.FailureData.S['code'] := E.Code;
      AJob.FailureData.S['message'] := E.Message;
      AJob.FailureData.S['phase'] := 'execution';
      AJob.FailureData.B['partial'] := False;
      AJob.State := xajsFailed;
    end;
    on E: Exception do begin
      AJob.FailureData.S['code'] := xeAutomationErrorInternalError;
      AJob.FailureData.S['message'] := E.Message;
      AJob.FailureData.S['phase'] := 'execution';
      AJob.FailureData.B['partial'] := False;
      AJob.State := xajsFailed;
    end;
  end;

  xeAutomationFinishActiveJobIfTerminal(AJob);
end;

function xeAutomationStartJob(const AKind: string; const ADryRun, ADryRunSpecified: Boolean; const ATarget, AOptions: TJsonObject): TJsonObject;
var
  lKind: string;
  lJob: TxeAutomationJob;
  lDryRun: Boolean;
  lRegistration: TxeAutomationJobKindRegistration;
begin
  lKind := xeAutomationNormalizeJobKind(AKind);
  if not xeAutomationGetJobKinds.TryGetValue(lKind, lRegistration) then
    // Unknown-kind validation intentionally runs before the active-job check so
    // malformed or unsupported requests get a stable shape even during long work.
    raise xeAutomationNewError(xeAutomationErrorUnknownJobKind, Format('Automation job kind not registered: %s', [AKind]));

  lDryRun := ADryRun;
  // Kind-specific start validators run after known-kind lookup but before active
  // job conflict checks so schema errors remain deterministic during queued work.
  if Assigned(lRegistration.Validator) then
    lRegistration.Validator(lDryRun, ADryRunSpecified, ATarget, AOptions);

  if Assigned(xeAutomationActiveJob) and not xeAutomationActiveJob.IsTerminal then
    raise xeAutomationNewError(xeAutomationErrorJobBusy, Format('Automation job already active: %s', [xeAutomationActiveJob.Id]));

  Inc(xeAutomationNextJobId);
  Inc(xeAutomationNextJobSequence);
  lJob := TxeAutomationJob.Create;
  try
    lJob.Id := Format('job-%.6d', [xeAutomationNextJobId]);
    lJob.Kind := lKind;
    lJob.State := xajsQueued;
    lJob.Sequence := xeAutomationNextJobSequence;
    lJob.DryRun := lDryRun;
    lJob.DryRunSpecified := ADryRunSpecified;
    xeAutomationCopyJsonObject(ATarget, lJob.Target);
    xeAutomationCopyJsonObject(AOptions, lJob.Options);

    xeAutomationGetJobs.Add(lJob);
    xeAutomationActiveJob := lJob;
    lJob := nil;
    Result := xeAutomationNewJobSnapshot(xeAutomationActiveJob);
  finally
    lJob.Free;
  end;
end;

function xeAutomationGetJob(const AJobId: string): TJsonObject;
var
  lJob: TxeAutomationJob;
begin
  lJob := xeAutomationRequireJob(AJobId);
  xeAutomationAdvanceJob(lJob);
  Result := xeAutomationNewJobSnapshot(lJob);
end;

function xeAutomationGetJobFindings(const AJobId: string; const AOffset, ALimit: Integer): TJsonObject;
var
  lJob: TxeAutomationJob;
  i: Integer;
  lEnd: Integer;
begin
  lJob := xeAutomationRequireJob(AJobId);
  Result := TJsonObject.Create;
  xeAutomationWriteFindingJobFields(Result, lJob);
  Result.I['offset'] := AOffset;
  Result.I['limit'] := ALimit;
  Result.I['total'] := lJob.Findings.Count;
  // Initialize before paging so empty result pages still serialize the stable
  // protocol shape with findings: [] instead of omitting the field entirely.
  Result.A['findings'].Clear;
  lEnd := AOffset + ALimit;
  if lEnd > lJob.Findings.Count then
    lEnd := lJob.Findings.Count;
  for i := AOffset to Pred(lEnd) do
    // Findings are copied in stored order so completed jobs keep stable paging
    // even after newer terminal jobs are retained beside them.
    xeAutomationAddFindingCopy(Result.A['findings'], lJob.Findings, i);
end;

function xeAutomationCancelJob(const AJobId: string): TJsonObject;
var
  lJob: TxeAutomationJob;
begin
  lJob := xeAutomationRequireJob(AJobId);
  if lJob.IsTerminal then
    Exit(xeAutomationNewJobSnapshot(lJob));

  if lJob.State = xajsQueued then begin
    lJob.State := xajsCancelRequested;
    xeAutomationAdvanceJob(lJob);
  end else
    raise xeAutomationNewError(xeAutomationErrorOperationNotCancelable, Format('Automation job is not cancelable: %s', [AJobId]));

  Result := xeAutomationNewJobSnapshot(lJob);
end;

function xeAutomationDiscardJob(const AJobId: string): TJsonObject;
var
  lJob: TxeAutomationJob;
begin
  lJob := xeAutomationRequireJob(AJobId);
  if not lJob.IsTerminal then
    raise xeAutomationNewError(xeAutomationErrorJobNotTerminal, Format('Automation job is not terminal: %s', [AJobId]));

  Result := xeAutomationNewJobSnapshot(lJob);
  if lJob = xeAutomationActiveJob then
    xeAutomationActiveJob := nil;
  xeAutomationGetJobs.Remove(lJob);
end;

initialization
finalization
  xeAutomationActiveJob := nil;
  FreeAndNil(xeAutomationJobList);
  FreeAndNil(xeAutomationJobKinds);
end.
