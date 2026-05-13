{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeScriptLint;

interface

type
  TxeScriptLintHit = record
    Kind: string;
    Symbol: string;
    Line: Integer;
    Column: Integer;
    SourceUnit: string;
  end;

function xeLintScriptEntrySource(const ASource, ASourceUnit: string): TArray<TxeScriptLintHit>;

implementation

uses
  SysUtils;

type
  TxeScriptLintDenySymbol = record
    Kind: string;
    Symbol: string;
  end;

  TxeScriptLintToken = record
    Text: string;
    Line: Integer;
    Column: Integer;
  end;

const
  xeScriptLintDeniedSymbols: array[0..54] of TxeScriptLintDenySymbol = (
    (Kind: 'BLOCKER_UI'; Symbol: 'ShowModal'),
    (Kind: 'BLOCKER_UI'; Symbol: 'TOpenDialog.Execute'),
    (Kind: 'BLOCKER_UI'; Symbol: 'TSaveDialog.Execute'),
    (Kind: 'BLOCKER_UI'; Symbol: 'MessageDlg'),
    (Kind: 'BLOCKER_UI'; Symbol: 'MessageDlgPos'),
    (Kind: 'BLOCKER_UI'; Symbol: 'MessageDlgPosHelp'),
    (Kind: 'BLOCKER_UI'; Symbol: 'Application.MessageBox'),
    (Kind: 'BLOCKER_UI'; Symbol: 'Windows.MessageBox'),
    (Kind: 'BLOCKER_UI'; Symbol: 'Application.ProcessMessages'),
    (Kind: 'BLOCKER_INPUT'; Symbol: 'InputBox'),
    (Kind: 'BLOCKER_INPUT'; Symbol: 'InputQuery'),
    (Kind: 'BLOCKER_INPUT'; Symbol: 'SelectDirectory'),
    (Kind: 'WRITE_FS'; Symbol: 'TStrings.SaveToFile'),
    (Kind: 'WRITE_FS'; Symbol: 'TMemoryStream.SaveToFile'),
    (Kind: 'WRITE_FS'; Symbol: 'TGraphic.SaveToFile'),
    (Kind: 'WRITE_FS'; Symbol: 'TPicture.SaveToFile'),
    (Kind: 'WRITE_FS'; Symbol: 'TMetafile.SaveToFile'),
    (Kind: 'WRITE_FS'; Symbol: 'DeleteFile'),
    (Kind: 'WRITE_FS'; Symbol: 'RenameFile'),
    (Kind: 'WRITE_FS'; Symbol: 'SetCurrentDir'),
    (Kind: 'WRITE_FS'; Symbol: 'CreateDir'),
    (Kind: 'WRITE_FS'; Symbol: 'RemoveDir'),
    (Kind: 'WRITE_FS'; Symbol: 'ForceDirectories'),
    (Kind: 'WRITE_FS'; Symbol: 'CopyFile'),
    (Kind: 'WRITE_FS'; Symbol: 'TFile.WriteAllText'),
    (Kind: 'WRITE_FS'; Symbol: 'TCustomIniFile.WriteString'),
    (Kind: 'WRITE_FS'; Symbol: 'TCustomIniFile.WriteInteger'),
    (Kind: 'WRITE_FS'; Symbol: 'TCustomIniFile.WriteFloat'),
    (Kind: 'WRITE_FS'; Symbol: 'TCustomIniFile.WriteBool'),
    (Kind: 'WRITE_FS'; Symbol: 'TMemIniFile.SetStrings'),
    (Kind: 'WRITE_FS'; Symbol: 'TdfElement.SaveToFile'),
    (Kind: 'WRITE_FS'; Symbol: 'TdfElement.SaveToJSONFile'),
    (Kind: 'WRITE_FS'; Symbol: 'TFileStream.Create'),
    (Kind: 'SIDE_EFFECT_OS'; Symbol: 'GetClipboardText'),
    (Kind: 'SIDE_EFFECT_OS'; Symbol: 'SetClipboardText'),
    (Kind: 'SIDE_EFFECT_OS'; Symbol: 'ShellExecute'),
    (Kind: 'SIDE_EFFECT_OS'; Symbol: 'ShellExecuteWait'),
    (Kind: 'SIDE_EFFECT_OS'; Symbol: 'CreateProcessWait'),
    (Kind: 'SIDE_EFFECT_OS'; Symbol: 'Sleep'),
    (Kind: 'SIDE_EFFECT_OS'; Symbol: 'GetKeyState'),
    (Kind: 'SIDE_EFFECT_OS'; Symbol: 'TCustomEdit.CopyToClipboard'),
    (Kind: 'SIDE_EFFECT_OS'; Symbol: 'TCustomEdit.CutToClipboard'),
    (Kind: 'SIDE_EFFECT_OS'; Symbol: 'TCustomEdit.PasteFromClipboard'),
    (Kind: 'SIDE_EFFECT_OS'; Symbol: 'ExecuteCaptureConsoleOutput'),
    (Kind: 'HOST_GUI_HOOK'; Symbol: 'frmMain'),
    (Kind: 'HOST_GUI_HOOK'; Symbol: 'frmFileSelect'),
    (Kind: 'HOST_GUI_HOOK'; Symbol: 'JumpTo'),
    (Kind: 'HOST_GUI_HOOK'; Symbol: 'ApplyFilter'),
    (Kind: 'HOST_GUI_HOOK'; Symbol: 'RemoveFilter'),
    (Kind: 'HOST_GUI_HOOK'; Symbol: 'RemoveNode'),
    (Kind: 'HOST_GUI_HOOK'; Symbol: 'ClearMessages'),
    (Kind: 'HOST_GUI_HOOK'; Symbol: 'wbSelectedFilesToFileNames'),
    (Kind: 'HIDDEN_PROMPT'; Symbol: 'AddNewFile'),
    (Kind: 'HIDDEN_PROMPT'; Symbol: 'AddNewFileName'),
    (Kind: 'HIDDEN_PROMPT'; Symbol: 'AddRequiredElementMasters')
  );

function xeIsIdentifierStart(const AChar: Char): Boolean;
begin
  Result := ((AChar >= 'A') and (AChar <= 'Z')) or
    ((AChar >= 'a') and (AChar <= 'z')) or
    (AChar = '_');
end;

function xeIsIdentifierChar(const AChar: Char): Boolean;
begin
  Result := xeIsIdentifierStart(AChar) or
    ((AChar >= '0') and (AChar <= '9'));
end;

procedure xeAdvanceSourceChar(const ASource: string; var AIndex, ALine, AColumn: Integer);
var
  lChar: Char;
begin
  if AIndex > Length(ASource) then
    Exit;

  lChar := ASource[AIndex];
  Inc(AIndex);

  if lChar = #13 then begin
    if (AIndex <= Length(ASource)) and (ASource[AIndex] = #10) then
      Inc(AIndex);
    Inc(ALine);
    AColumn := 1;
  end else if lChar = #10 then begin
    Inc(ALine);
    AColumn := 1;
  end else
    Inc(AColumn);
end;

function xeReadIdentifierAt(const ASource: string; var AIndex: Integer): string;
var
  lStart: Integer;
begin
  lStart := AIndex;
  while (AIndex <= Length(ASource)) and xeIsIdentifierChar(ASource[AIndex]) do
    Inc(AIndex);
  Result := Copy(ASource, lStart, AIndex - lStart);
end;

function xeFindDeniedSymbol(const ASymbol: string; out AKind, ACanonicalSymbol: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := Low(xeScriptLintDeniedSymbols) to High(xeScriptLintDeniedSymbols) do
    if SameText(ASymbol, xeScriptLintDeniedSymbols[i].Symbol) then begin
      AKind := xeScriptLintDeniedSymbols[i].Kind;
      ACanonicalSymbol := xeScriptLintDeniedSymbols[i].Symbol;
      Exit(True);
    end;
end;

procedure xeAppendLintHit(var AHits: TArray<TxeScriptLintHit>; const AKind, ASymbol: string;
  const ALine, AColumn: Integer; const ASourceUnit: string);
var
  lIndex: Integer;
begin
  lIndex := Length(AHits);
  SetLength(AHits, lIndex + 1);
  AHits[lIndex].Kind := AKind;
  AHits[lIndex].Symbol := ASymbol;
  AHits[lIndex].Line := ALine;
  AHits[lIndex].Column := AColumn;
  AHits[lIndex].SourceUnit := ASourceUnit;
end;

procedure xeSkipBraceComment(const ASource: string; var AIndex, ALine, AColumn: Integer);
begin
  xeAdvanceSourceChar(ASource, AIndex, ALine, AColumn);
  while AIndex <= Length(ASource) do begin
    if ASource[AIndex] = '}' then begin
      xeAdvanceSourceChar(ASource, AIndex, ALine, AColumn);
      Exit;
    end;
    xeAdvanceSourceChar(ASource, AIndex, ALine, AColumn);
  end;
end;

procedure xeSkipParenStarComment(const ASource: string; var AIndex, ALine, AColumn: Integer);
begin
  xeAdvanceSourceChar(ASource, AIndex, ALine, AColumn);
  xeAdvanceSourceChar(ASource, AIndex, ALine, AColumn);
  while AIndex <= Length(ASource) do begin
    if (AIndex < Length(ASource)) and (ASource[AIndex] = '*') and (ASource[AIndex + 1] = ')') then begin
      xeAdvanceSourceChar(ASource, AIndex, ALine, AColumn);
      xeAdvanceSourceChar(ASource, AIndex, ALine, AColumn);
      Exit;
    end;
    xeAdvanceSourceChar(ASource, AIndex, ALine, AColumn);
  end;
end;

procedure xeSkipLineComment(const ASource: string; var AIndex, ALine, AColumn: Integer);
begin
  while (AIndex <= Length(ASource)) and not (ASource[AIndex] in [#10, #13]) do
    xeAdvanceSourceChar(ASource, AIndex, ALine, AColumn);
end;

procedure xeSkipStringLiteral(const ASource: string; var AIndex, ALine, AColumn: Integer);
begin
  xeAdvanceSourceChar(ASource, AIndex, ALine, AColumn);
  while AIndex <= Length(ASource) do begin
    if ASource[AIndex] = '''' then begin
      xeAdvanceSourceChar(ASource, AIndex, ALine, AColumn);
      if (AIndex <= Length(ASource)) and (ASource[AIndex] = '''') then begin
        xeAdvanceSourceChar(ASource, AIndex, ALine, AColumn);
        Continue;
      end;
      Exit;
    end;
    xeAdvanceSourceChar(ASource, AIndex, ALine, AColumn);
  end;
end;

function xeReadNextSignificantToken(const ASource: string; var AIndex, ALine, AColumn: Integer;
  out AToken: TxeScriptLintToken): Boolean;
var
  lStartIndex: Integer;
begin
  Result := False;
  AToken.Text := '';
  AToken.Line := 0;
  AToken.Column := 0;

  while AIndex <= Length(ASource) do begin
    if ASource[AIndex] in [#9, #10, #13, ' '] then begin
      xeAdvanceSourceChar(ASource, AIndex, ALine, AColumn);
      Continue;
    end;

    if ASource[AIndex] = '{' then begin
      xeSkipBraceComment(ASource, AIndex, ALine, AColumn);
      Continue;
    end;

    if (AIndex < Length(ASource)) and (ASource[AIndex] = '(') and (ASource[AIndex + 1] = '*') then begin
      xeSkipParenStarComment(ASource, AIndex, ALine, AColumn);
      Continue;
    end;

    if (AIndex < Length(ASource)) and (ASource[AIndex] = '/') and (ASource[AIndex + 1] = '/') then begin
      xeSkipLineComment(ASource, AIndex, ALine, AColumn);
      Continue;
    end;

    Break;
  end;

  if AIndex > Length(ASource) then
    Exit;

  AToken.Line := ALine;
  AToken.Column := AColumn;
  if xeIsIdentifierStart(ASource[AIndex]) then begin
    lStartIndex := AIndex;
    AToken.Text := xeReadIdentifierAt(ASource, AIndex);
    Inc(AColumn, AIndex - lStartIndex);
  end else begin
    AToken.Text := ASource[AIndex];
    xeAdvanceSourceChar(ASource, AIndex, ALine, AColumn);
  end;

  Result := True;
end;

function xeReadDottedSymbolFromTokenStream(const ASource: string; const AIndex, ALine, AColumn: Integer;
  out AFirstToken, ADottedSymbol: string): Boolean;
var
  lIndex: Integer;
  lLine: Integer;
  lColumn: Integer;
  lToken: TxeScriptLintToken;
begin
  Result := False;
  AFirstToken := '';
  ADottedSymbol := '';
  lIndex := AIndex;
  lLine := ALine;
  lColumn := AColumn;

  if not xeReadNextSignificantToken(ASource, lIndex, lLine, lColumn, lToken) or
     (lToken.Text = '') or not xeIsIdentifierStart(lToken.Text[1]) then
    Exit;

  AFirstToken := lToken.Text;
  ADottedSymbol := lToken.Text;

  while xeReadNextSignificantToken(ASource, lIndex, lLine, lColumn, lToken) and
    (lToken.Text = '.') do begin
    if not xeReadNextSignificantToken(ASource, lIndex, lLine, lColumn, lToken) or
       (lToken.Text = '') or not xeIsIdentifierStart(lToken.Text[1]) then
      Break;
    ADottedSymbol := ADottedSymbol + '.' + lToken.Text;
  end;

  Result := True;
end;

function xeMatchDeniedSymbolAtToken(const ASource: string; const AIndex, ALine, AColumn: Integer;
  out AKind, ACanonicalSymbol: string): Boolean;
var
  lFirstToken: string;
  lDottedSymbol: string;
begin
  Result := False;
  if not xeReadDottedSymbolFromTokenStream(ASource, AIndex, ALine, AColumn, lFirstToken, lDottedSymbol) then
    Exit;

  if xeFindDeniedSymbol(lDottedSymbol, AKind, ACanonicalSymbol) then
    Exit(True);

  Result := xeFindDeniedSymbol(lFirstToken, AKind, ACanonicalSymbol);
end;

function xeLintScriptEntrySource(const ASource, ASourceUnit: string): TArray<TxeScriptLintHit>;
var
  lIndex: Integer;
  lLine: Integer;
  lColumn: Integer;
  lStartLine: Integer;
  lStartColumn: Integer;
  lKind: string;
  lCanonicalSymbol: string;
begin
  SetLength(Result, 0);
  lIndex := 1;
  lLine := 1;
  lColumn := 1;

  // Lint only the entry script text. Helper units remain guarded by the runtime
  // auth hook, but are not scanned here so daemon callers get a fast,
  // deterministic preflight warning without include resolution.
  while lIndex <= Length(ASource) do begin
    if ASource[lIndex] = '''' then begin
      xeSkipStringLiteral(ASource, lIndex, lLine, lColumn);
      Continue;
    end;

    if ASource[lIndex] = '{' then begin
      xeSkipBraceComment(ASource, lIndex, lLine, lColumn);
      Continue;
    end;

    if (lIndex < Length(ASource)) and (ASource[lIndex] = '(') and (ASource[lIndex + 1] = '*') then begin
      xeSkipParenStarComment(ASource, lIndex, lLine, lColumn);
      Continue;
    end;

    if (lIndex < Length(ASource)) and (ASource[lIndex] = '/') and (ASource[lIndex + 1] = '/') then begin
      xeSkipLineComment(ASource, lIndex, lLine, lColumn);
      Continue;
    end;

    if xeIsIdentifierStart(ASource[lIndex]) then begin
      lStartLine := lLine;
      lStartColumn := lColumn;

      // This MVP matches exact lexical symbol occurrences in the entry script
      // only. It deliberately avoids type-aware instance-call inference; the
      // runtime auth hook remains authoritative for helper units and semantic
      // cases lint cannot classify before execution.
      if xeMatchDeniedSymbolAtToken(ASource, lIndex, lLine, lColumn, lKind, lCanonicalSymbol) then
        xeAppendLintHit(Result, lKind, lCanonicalSymbol, lStartLine, lStartColumn, ASourceUnit);

      while (lIndex <= Length(ASource)) and xeIsIdentifierChar(ASource[lIndex]) do
        xeAdvanceSourceChar(ASource, lIndex, lLine, lColumn);
      Continue;
    end;

    xeAdvanceSourceChar(ASource, lIndex, lLine, lColumn);
  end;
end;

end.
