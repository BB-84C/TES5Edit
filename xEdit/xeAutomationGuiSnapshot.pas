{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeAutomationGuiSnapshot;

interface

uses
  JsonDataObjects;

function xeAutomationBuildGuiSnapshot: TJsonObject;

implementation

uses
  Winapi.Windows,
  Forms,
  SysUtils,
  xeMainForm;

type
  TxeAutomationGuiBlocker = record
    Title: string;
    ClassName: string;
    Visible: Boolean;
    Enabled: Boolean;
    Modal: Boolean;
    Kind: string;
    BlocksAutomation: Boolean;
  end;

  TxeAutomationGuiBlockers = array of TxeAutomationGuiBlocker;

  PxeAutomationGuiSnapshotContext = ^TxeAutomationGuiSnapshotContext;
  TxeAutomationGuiSnapshotContext = record
    MainWindowHandle: HWND;
    Blockers: TxeAutomationGuiBlockers;
  end;

function xeAutomationWindowText(const AHandle: HWND): string;
var
  lLength: Integer;
begin
  lLength := GetWindowTextLength(AHandle);
  if lLength <= 0 then
    Exit('');

  SetLength(Result, lLength + 1);
  SetLength(Result, GetWindowText(AHandle, PChar(Result), lLength + 1));
end;

function xeAutomationWindowClassName(const AHandle: HWND): string;
var
  lBuffer: array[0..255] of Char;
  lLength: Integer;
begin
  lLength := GetClassName(AHandle, lBuffer, Length(lBuffer));
  SetString(Result, lBuffer, lLength);
end;

function xeAutomationWindowIsModalLike(const AHandle: HWND; const AClassName: string): Boolean;
var
  lStyle: NativeInt;
  lExStyle: NativeInt;
begin
  lStyle := GetWindowLongPtr(AHandle, GWL_STYLE);
  lExStyle := GetWindowLongPtr(AHandle, GWL_EXSTYLE);
  Result := SameText(AClassName, '#32770')
    or ((lStyle and DS_MODALFRAME) <> 0)
    or ((lExStyle and WS_EX_DLGMODALFRAME) <> 0);
end;

function xeAutomationClassifyBlockerKind(
  const AClassName: string;
  const AVisible, AModal: Boolean
): string;
begin
  // This seam is intentionally coarse for the first GUI snapshot contract.
  // We only separate broad blocker families here so later work can refine
  // dialog-specific handling without changing today's blocker detection policy.
  if AModal then
    Result := 'modal_dialog'
  else if SameText(AClassName, 'TfrmWait') then
    Result := 'progress_window'
  else if AVisible then
    Result := 'window'
  else
    Result := 'background_window';
end;

function xeAutomationWindowLikelyBlocksAutomation(
  const AHandle, AMainWindowHandle: HWND;
  const AVisible, AModal: Boolean
): Boolean;
var
  lOwnerHandle: HWND;
begin
  // Keep the first version blocker-only and reviewable: visible non-main
  // windows are reported directly, while hidden windows are only kept when they
  // look like modal-owned UI that can still disable the main interaction path.
  if AVisible then
    Exit(True);

  if (AMainWindowHandle = 0) or IsWindowEnabled(AMainWindowHandle) then
    Exit(False);

  lOwnerHandle := GetWindow(AHandle, GW_OWNER);
  Result := AModal and ((lOwnerHandle = 0) or (lOwnerHandle = AMainWindowHandle));
end;

procedure xeAutomationAppendGuiBlocker(
  var ABlockers: TxeAutomationGuiBlockers;
  const ABlocker: TxeAutomationGuiBlocker
);
var
  lIndex: Integer;
begin
  lIndex := Length(ABlockers);
  SetLength(ABlockers, lIndex + 1);
  ABlockers[lIndex] := ABlocker;
end;

function xeAutomationCollectGuiBlocker(const AHandle: HWND; const AContext: PxeAutomationGuiSnapshotContext): Boolean;
var
  lClassName: string;
  lBlocker: TxeAutomationGuiBlocker;
begin
  Result := False;
  if not Assigned(AContext) then
    Exit;

  if AHandle = AContext.MainWindowHandle then
    Exit;

  lClassName := xeAutomationWindowClassName(AHandle);
  if (AHandle = Application.Handle) or SameText(lClassName, 'TApplication') then
    Exit;

  lBlocker.Title := Trim(xeAutomationWindowText(AHandle));
  lBlocker.ClassName := lClassName;
  lBlocker.Visible := IsWindowVisible(AHandle);
  lBlocker.Enabled := IsWindowEnabled(AHandle);
  lBlocker.Modal := xeAutomationWindowIsModalLike(AHandle, lClassName);
  lBlocker.BlocksAutomation := xeAutomationWindowLikelyBlocksAutomation(
    AHandle,
    AContext.MainWindowHandle,
    lBlocker.Visible,
    lBlocker.Modal
  );
  if not lBlocker.BlocksAutomation then
    Exit;

  lBlocker.Kind := xeAutomationClassifyBlockerKind(
    lBlocker.ClassName,
    lBlocker.Visible,
    lBlocker.Modal
  );
  xeAutomationAppendGuiBlocker(AContext.Blockers, lBlocker);
  Result := True;
end;

function xeAutomationCollectWindowsProc(AHandle: HWND; AParam: LPARAM): BOOL; stdcall;
var
  lProcessId: DWORD;
begin
  Result := True;
  if GetWindowThreadProcessId(AHandle, lProcessId) = 0 then
    Exit;

  if lProcessId <> GetCurrentProcessId then
    Exit;

  xeAutomationCollectGuiBlocker(AHandle, PxeAutomationGuiSnapshotContext(AParam));
end;

function xeAutomationMainWindowHandle: HWND;
begin
  if Assigned(frmMain) then
    Result := frmMain.Handle
  else if Assigned(Application.MainForm) then
    Result := Application.MainForm.Handle
  else
    Result := 0;
end;

function xeAutomationBuildGuiSnapshot: TJsonObject;
var
  lContext: TxeAutomationGuiSnapshotContext;
  lBlockers: TJsonArray;
  lBlockerJson: TJsonObject;
  i: Integer;
begin
  Result := TJsonObject.Create;
  lBlockers := Result.A['blockers'];

  lContext.MainWindowHandle := xeAutomationMainWindowHandle;
  SetLength(lContext.Blockers, 0);
  EnumWindows(@xeAutomationCollectWindowsProc, LPARAM(@lContext));

  for i := Low(lContext.Blockers) to High(lContext.Blockers) do begin
    lBlockerJson := lBlockers.AddObject;
    lBlockerJson.S['title'] := lContext.Blockers[i].Title;
    lBlockerJson.S['className'] := lContext.Blockers[i].ClassName;
    lBlockerJson.B['visible'] := lContext.Blockers[i].Visible;
    lBlockerJson.B['enabled'] := lContext.Blockers[i].Enabled;
    lBlockerJson.B['modal'] := lContext.Blockers[i].Modal;
    lBlockerJson.S['kind'] := lContext.Blockers[i].Kind;
    lBlockerJson.B['blocksAutomation'] := lContext.Blockers[i].BlocksAutomation;
  end;

  Result.I['blockerCount'] := lBlockers.Count;
  Result.B['hasBlockers'] := lBlockers.Count > 0;
end;

end.
