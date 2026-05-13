{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeAutomationSession;

interface

uses
  xeAutomationTypes;

var
  xeAutomationMode: TxeAutomationMode = xamNone;
  xeAutomationCliRequestedRaw: Boolean;
  xeAutomationServeRequestedRaw: Boolean;
  xeAutomationCallRequestedRaw: Boolean;
  xeAutomationCliRequestPath: string;
  xeAutomationCliResponsePath: string;
  xeAutomationCallPid: Cardinal;
  xeAutomationCallPipeName: string;
  xeAutomationCallRequestPath: string;
  xeAutomationCallResponsePath: string;

procedure xeAutomationResetSession;
procedure xeAutomationUpdateMode(
  aCliRequestSpecified,
  aCliResponseSpecified,
  aServeSpecified,
  aCallPidSpecified,
  aCallRequestSpecified,
  aCallResponseSpecified: Boolean
);
function xeAutomationCallPidIsValid: Boolean;
function xeAutomationCliRequested: Boolean;
function xeAutomationDaemonRequested: Boolean;
function xeAutomationHasConflictingModes: Boolean;

implementation

procedure xeAutomationResetSession;
begin
  xeAutomationMode := xamNone;
  xeAutomationCliRequestedRaw := False;
  xeAutomationServeRequestedRaw := False;
  xeAutomationCallRequestedRaw := False;
  xeAutomationCliRequestPath := '';
  xeAutomationCliResponsePath := '';
  xeAutomationCallPid := 0;
  xeAutomationCallPipeName := '';
  xeAutomationCallRequestPath := '';
  xeAutomationCallResponsePath := '';
end;

procedure xeAutomationUpdateMode(
  aCliRequestSpecified,
  aCliResponseSpecified,
  aServeSpecified,
  aCallPidSpecified,
  aCallRequestSpecified,
  aCallResponseSpecified: Boolean
);
begin
  // Preserve the raw requested mode family separately from the resolved mode so
  // later validation can diagnose conflicting combinations without changing the
  // branch-routing enum used by the current startup path.
  xeAutomationCliRequestedRaw := aCliRequestSpecified or aCliResponseSpecified;
  xeAutomationServeRequestedRaw := aServeSpecified;
  xeAutomationCallRequestedRaw := aCallPidSpecified or aCallRequestSpecified or aCallResponseSpecified;

  // Keep partial automation invocations on a headless path so malformed serve or
  // call mode arguments do not silently fall back into the normal GUI startup.
  if xeAutomationCallRequestedRaw then
    xeAutomationMode := xamCall
  else if xeAutomationServeRequestedRaw then
    xeAutomationMode := xamServe
  else if xeAutomationCliRequestedRaw then
    xeAutomationMode := xamCli
  else
    xeAutomationMode := xamNone;
end;

function xeAutomationCallPidIsValid: Boolean;
begin
  Result := xeAutomationCallPid <> 0;
end;

function xeAutomationCliRequested: Boolean;
begin
  Result := xeAutomationMode = xamCli;
end;

function xeAutomationDaemonRequested: Boolean;
begin
  Result := xeAutomationMode in [xamServe, xamCall];
end;

function xeAutomationHasConflictingModes: Boolean;
var
  lRequestedCount: Integer;
begin
  lRequestedCount := 0;
  if xeAutomationCliRequestedRaw then
    Inc(lRequestedCount);
  if xeAutomationServeRequestedRaw then
    Inc(lRequestedCount);
  if xeAutomationCallRequestedRaw then
    Inc(lRequestedCount);
  Result := lRequestedCount > 1;
end;

end.
