{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeAutomationRegistry;

interface

uses
  System.Classes,
  System.Generics.Collections,
  JsonDataObjects;

type
  TxeAutomationCommandHandler = function(const aArgs: TJsonObject): TJsonObject;

procedure xeAutomationRegisterCommand(const aName: string; const aHandler: TxeAutomationCommandHandler);
function xeAutomationHasCommand(const aName: string): Boolean;
function xeAutomationExecuteCommand(const aName: string; const aArgs: TJsonObject): TJsonObject;
function xeAutomationListCommands: TArray<string>;

implementation

uses
  SysUtils,
  xeAutomationErrors;

var
  xeAutomationCommands: TDictionary<string, TxeAutomationCommandHandler>;

function xeAutomationNormalizeCommandName(const aName: string): string;
begin
  // Keep lookup case-insensitive and whitespace-stable so later command groups
  // do not accidentally create transport-visible aliases.
  Result := LowerCase(Trim(aName));
end;

function xeAutomationGetCommands: TDictionary<string, TxeAutomationCommandHandler>;
begin
  if not Assigned(xeAutomationCommands) then
    xeAutomationCommands := TDictionary<string, TxeAutomationCommandHandler>.Create;
  Result := xeAutomationCommands;
end;

function xeAutomationGetCommandHandler(const aName: string): TxeAutomationCommandHandler;
begin
  Result := nil;
  xeAutomationGetCommands.TryGetValue(xeAutomationNormalizeCommandName(aName), Result);
end;

procedure xeAutomationRegisterCommand(const aName: string; const aHandler: TxeAutomationCommandHandler);
var
  lNormalizedName: string;
begin
  if not Assigned(aHandler) then
    raise Exception.Create('Automation command handler is required');

  lNormalizedName := xeAutomationNormalizeCommandName(aName);
  if lNormalizedName = '' then
    raise Exception.Create('Automation command name is required');

  if xeAutomationHasCommand(lNormalizedName) then
    raise Exception.CreateFmt('Automation command already registered: %s', [aName]);

  xeAutomationGetCommands.Add(lNormalizedName, aHandler);
end;

function xeAutomationHasCommand(const aName: string): Boolean;
begin
  Result := Assigned(xeAutomationGetCommandHandler(aName));
end;

function xeAutomationExecuteCommand(const aName: string; const aArgs: TJsonObject): TJsonObject;
var
  lHandler: TxeAutomationCommandHandler;
begin
  lHandler := xeAutomationGetCommandHandler(aName);
  if not Assigned(lHandler) then
    // The registry owns "command exists" decisions so the host can stay focused
    // on transport concerns and just translate typed failures into CLI responses.
    raise xeAutomationUnknownCommand(aName);

  Result := lHandler(aArgs);
end;

function xeAutomationListCommands: TArray<string>;
var
  lCommandNames: TStringList;
  lPair: TPair<string, TxeAutomationCommandHandler>;
  i: Integer;
begin
  lCommandNames := TStringList.Create;
  try
    // Capability reporting must stay stable across runs, so callers get an
    // explicitly sorted name list instead of dictionary iteration order.
    for lPair in xeAutomationGetCommands do
      lCommandNames.Add(lPair.Key);
    lCommandNames.Sort;

    SetLength(Result, lCommandNames.Count);
    for i := 0 to Pred(lCommandNames.Count) do
      Result[i] := lCommandNames[i];
  finally
    lCommandNames.Free;
  end;
end;

initialization
finalization
  FreeAndNil(xeAutomationCommands);
end.
