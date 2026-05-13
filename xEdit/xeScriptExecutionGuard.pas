{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeScriptExecutionGuard;

interface

function xeScriptGuardTryAcquire(const aHolder: string): Boolean;
procedure xeScriptGuardRelease;
function xeScriptGuardCurrentHolder: string;
function xeScriptGuardIsHeld: Boolean;

implementation

uses
  SyncObjs,
  SysUtils;

var
  xeScriptGuardLock: TCriticalSection;
  xeScriptGuardHeld: Boolean;
  xeScriptGuardHolder: string;

function xeScriptGuardTryAcquire(const aHolder: string): Boolean;
begin
  xeScriptGuardLock.Enter;
  try
    Result := not xeScriptGuardHeld;
    if Result then begin
      // This unit is the single authority for script execution mutual exclusion:
      // both daemon and GUI paths must acquire here instead of keeping separate flags.
      xeScriptGuardHeld := True;
      xeScriptGuardHolder := aHolder;
    end;
  finally
    xeScriptGuardLock.Leave;
  end;
end;

procedure xeScriptGuardRelease;
begin
  xeScriptGuardLock.Enter;
  try
    xeScriptGuardHeld := False;
    xeScriptGuardHolder := '';
  finally
    xeScriptGuardLock.Leave;
  end;
end;

function xeScriptGuardCurrentHolder: string;
begin
  xeScriptGuardLock.Enter;
  try
    Result := xeScriptGuardHolder;
  finally
    xeScriptGuardLock.Leave;
  end;
end;

function xeScriptGuardIsHeld: Boolean;
begin
  xeScriptGuardLock.Enter;
  try
    Result := xeScriptGuardHeld;
  finally
    xeScriptGuardLock.Leave;
  end;
end;

initialization
  xeScriptGuardLock := TCriticalSection.Create;
finalization
  FreeAndNil(xeScriptGuardLock);
end.
