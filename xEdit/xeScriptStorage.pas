{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeScriptStorage;

interface

const
  xeScriptStorageInvalidRequest = 'invalid_request';
  xeScriptStoragePathOutsideNamespace = 'path_outside_namespace';
  xeScriptStorageScriptNotFound = 'script_not_found';
  xeScriptStorageAlreadyExists = 'already_exists';
  xeScriptStorageIoError = 'io_error';

type
  TxeScriptMeta = record
    Id: string;
    AbsolutePath: string;
    SizeBytes: Int64;
    ModifiedTimeUtc: string;
  end;

function xeCanonicalizeScriptId(const AId: string; const ARequireAgentWrite: Boolean;
  out ANormalizedId, AAbsolutePath: string; out ARejectionKind: string): Boolean;
function xeListScripts(const APrefix: string; const ALimit: Integer;
  out AScripts: TArray<TxeScriptMeta>; out ATotal: Integer; out ATruncated: Boolean): Boolean;
function xeReadScript(const AId: string; out ASource: string): Boolean; overload;
function xeReadScript(const AId: string; out ASource: string; out ARejectionKind: string): Boolean; overload;
function xeWriteScript(const AId, ASource: string; const AOverwrite: Boolean;
  out AMeta: TxeScriptMeta; out ACreated: Boolean): Boolean; overload;
function xeWriteScript(const AId, ASource: string; const AOverwrite: Boolean;
  out AMeta: TxeScriptMeta; out ACreated: Boolean; out ARejectionKind: string;
  out AAlreadyExists: Boolean): Boolean; overload;
function xeDeleteScript(const AId: string): Boolean; overload;
function xeDeleteScript(const AId: string; out ARejectionKind: string): Boolean; overload;

implementation

uses
  Classes,
  Generics.Collections,
  IOUtils,
  StrUtils,
  SysUtils,
  Windows,
  wbInterface;

const
  xeScriptStorageDefaultLimit = 200;
  xeScriptStorageMaxLimit = 1000;
  xeScriptStorageAgentSegment = 'Agent';
  xePathPrefixWin32Device = '\\?\';
  xePathPrefixDosDevice = '\\.\';
  xePathPrefixNativeDosDevice = '\??\';

function xeStartsWithText(const AValue, APrefix: string): Boolean;
begin
  Result := (Length(AValue) >= Length(APrefix)) and
    SameText(Copy(AValue, 1, Length(APrefix)), APrefix);
end;

function xeNormalizeFinalPathPrefix(const APath: string): string;
begin
  Result := StringReplace(APath, '/', '\', [rfReplaceAll]);
  if xeStartsWithText(Result, '\\?\UNC\') then
    Result := '\\' + Copy(Result, 9, MaxInt)
  else if xeStartsWithText(Result, xePathPrefixWin32Device) then
    Result := Copy(Result, 5, MaxInt);
end;

function xeFinalPathForExistingPath(const APath: string): string;
var
  lHandle: THandle;
  lLength: DWORD;
begin
  Result := '';
  lHandle := CreateFile(PChar(APath), 0,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil, OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL or FILE_FLAG_BACKUP_SEMANTICS, 0);
  if lHandle = INVALID_HANDLE_VALUE then
    Exit;
  try
    SetLength(Result, 32768);
    {$WARN SYMBOL_PLATFORM OFF}
    lLength := GetFinalPathNameByHandle(lHandle, PChar(Result), Length(Result), FILE_NAME_NORMALIZED);
    {$WARN SYMBOL_PLATFORM ON}
    if (lLength = 0) or (lLength >= DWORD(Length(Result))) then begin
      Result := '';
      Exit;
    end;
    SetLength(Result, lLength);
    Result := xeNormalizeFinalPathPrefix(Result);
  finally
    CloseHandle(lHandle);
  end;
end;

function xeScriptsRootPath: string;
begin
  Result := ExpandFileName(IncludeTrailingPathDelimiter(wbScriptsPath));
end;

function xeAgentRootPath: string;
begin
  Result := ExpandFileName(IncludeTrailingPathDelimiter(xeScriptsRootPath + xeScriptStorageAgentSegment));
end;

function xeScriptsRootFinalPath: string;
begin
  if Trim(wbScriptsPath) = '' then
    Exit('');
  Result := xeFinalPathForExistingPath(xeScriptsRootPath);
end;

function xeSameOrDescendantOf(const AChild, ARoot: string): Boolean;
var
  lChild: string;
  lRoot: string;
begin
  lChild := ExcludeTrailingPathDelimiter(AChild);
  lRoot := ExcludeTrailingPathDelimiter(ARoot);
  Result := SameText(lChild, lRoot) or
    ((Length(lChild) > Length(lRoot) + 1) and
     SameText(Copy(lChild, 1, Length(lRoot)), lRoot) and
     (lChild[Length(lRoot) + 1] = '\'));
end;

function xeNearestExistingDirectory(const ADirectory: string): string;
var
  lCandidate: string;
  lParent: string;
begin
  lCandidate := ExpandFileName(ADirectory);
  while (lCandidate <> '') and not DirectoryExists(lCandidate) do begin
    lParent := ExcludeTrailingPathDelimiter(ExtractFilePath(ExcludeTrailingPathDelimiter(lCandidate)));
    if SameText(lParent, lCandidate) then
      Exit('');
    lCandidate := lParent;
  end;
  Result := lCandidate;
end;

function xeExistingPathIsUnderScriptsRoot(const APath: string): Boolean;
var
  lRootFinalPath: string;
  lFinalPath: string;
begin
  Result := False;
  lRootFinalPath := xeScriptsRootFinalPath;
  if lRootFinalPath = '' then
    Exit;

  lFinalPath := xeFinalPathForExistingPath(APath);
  Result := (lFinalPath <> '') and xeSameOrDescendantOf(lFinalPath, lRootFinalPath);
end;

function xeExistingPathIsUnderFinalRoot(const APath, ARootFinalPath: string): Boolean;
var
  lFinalPath: string;
begin
  Result := False;
  if ARootFinalPath = '' then
    Exit;

  lFinalPath := xeFinalPathForExistingPath(APath);
  Result := (lFinalPath <> '') and xeSameOrDescendantOf(lFinalPath, ARootFinalPath);
end;

function xeCandidatePathIsUnderFinalRoot(const APath, ARootFinalPath: string): Boolean;
var
  lFinalPath: string;
  lExistingParent: string;
begin
  Result := False;
  if ARootFinalPath = '' then
    Exit;

  if FileExists(APath) or DirectoryExists(APath) then begin
    lFinalPath := xeFinalPathForExistingPath(APath);
    Result := (lFinalPath <> '') and xeSameOrDescendantOf(lFinalPath, ARootFinalPath);
    Exit;
  end;

  // Missing writes are accepted only after the nearest existing parent is resolved
  // through Win32 final paths, so Agent/ junctions cannot redirect a future create
  // outside wbScriptsPath before the command facade maps the rejection to protocol.
  lExistingParent := xeNearestExistingDirectory(ExtractFilePath(APath));
  lFinalPath := xeFinalPathForExistingPath(lExistingParent);
  Result := (lFinalPath <> '') and xeSameOrDescendantOf(lFinalPath, ARootFinalPath);
end;

function xeCandidatePathIsUnderScriptsRoot(const APath: string): Boolean;
begin
  Result := xeCandidatePathIsUnderFinalRoot(APath, xeScriptsRootFinalPath);
end;

function xeAgentRootFinalPath(const ACreateIfMissing: Boolean): string;
var
  lRootFinalPath: string;
begin
  Result := '';
  if Trim(wbScriptsPath) = '' then
    Exit;

  if ACreateIfMissing then begin
    // Only the write path may create Agent/. Read/delete validation must not mutate
    // the scripts tree merely to answer a namespace question.
    if not ForceDirectories(xeAgentRootPath) then
      Exit;
  end else if not DirectoryExists(xeAgentRootPath) then
    Exit;

  lRootFinalPath := xeScriptsRootFinalPath;
  Result := xeFinalPathForExistingPath(xeAgentRootPath);
  if (Result = '') or (lRootFinalPath = '') or not xeSameOrDescendantOf(Result, lRootFinalPath) then
    Result := '';
end;

function xeExistingPathIsUnderAgentRoot(const APath: string; const ACreateAgentRoot: Boolean = False): Boolean;
begin
  Result := xeExistingPathIsUnderFinalRoot(APath, xeAgentRootFinalPath(ACreateAgentRoot));
end;

function xeCandidatePathIsUnderAgentRoot(const APath: string; const ACreateAgentRoot: Boolean = False): Boolean;
begin
  Result := xeCandidatePathIsUnderFinalRoot(APath, xeAgentRootFinalPath(ACreateAgentRoot));
end;

function xeHasInvalidScriptIdShape(const AId: string; const AAllowTrailingSlash: Boolean): Boolean;
var
  i: Integer;
  lId: string;
  lPart: string;
  lPath: string;
begin
  lId := AId;
  Result := (lId = '') or
    (Pos(#0, lId) > 0) or
    (Pos('..', lId) > 0) or
    (Pos(':', lId) > 0) or
    xeStartsWithText(lId, xePathPrefixWin32Device) or
    xeStartsWithText(lId, xePathPrefixDosDevice) or
    xeStartsWithText(lId, xePathPrefixNativeDosDevice) or
    ((Length(lId) > 0) and (lId[1] in ['\', '/'])) or
    SameText(ExtractFileExt(lId), '.pas');
  if Result then
    Exit;

  lPath := StringReplace(lId, '/', '\', [rfReplaceAll]);
  for i := 1 to Length(lId) do
    if lPath[i] = '\' then begin
      if lPart = '' then
        Exit(True);
      if (lPart = '.') or (lPart = '..') then
        Exit(True);
      lPart := '';
    end else
      lPart := lPart + lPath[i];

  Result := ((lPart = '') and not AAllowTrailingSlash) or (lPart = '.') or (lPart = '..');
end;

function xeNormalizeScriptIdShape(const AId: string; const AAllowTrailingSlash: Boolean;
  out ANormalizedId: string): Boolean;
var
  lId: string;
  lSlashPos: Integer;
  lFirstSegment: string;
begin
  ANormalizedId := '';
  lId := Trim(AId);
  if xeHasInvalidScriptIdShape(lId, AAllowTrailingSlash) then
    Exit(False);

  ANormalizedId := StringReplace(lId, '\', '/', [rfReplaceAll]);
  lSlashPos := Pos('/', ANormalizedId);
  if lSlashPos = 0 then
    lFirstSegment := ANormalizedId
  else
    lFirstSegment := Copy(ANormalizedId, 1, lSlashPos - 1);

  if SameText(lFirstSegment, xeScriptStorageAgentSegment) then
    ANormalizedId := xeScriptStorageAgentSegment + Copy(ANormalizedId, Length(lFirstSegment) + 1, MaxInt);

  Result := True;
end;

function xeIdIsUnderAgentRoot(const AId: string): Boolean;
begin
  Result := xeStartsWithText(AId, xeScriptStorageAgentSegment + '/');
end;

function xeNormalizedIdToAbsolutePath(const ANormalizedId: string): string;
begin
  Result := ExpandFileName(xeScriptsRootPath + StringReplace(ANormalizedId, '/', '\', [rfReplaceAll]) + '.pas');
end;

function xeFormatUtcDateTime(const AValue: TDateTime): string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"Z"', AValue);
end;

function xeBuildScriptMeta(const ANormalizedId, AAbsolutePath: string; out AMeta: TxeScriptMeta): Boolean;
begin
  Result := False;
  AMeta.Id := ANormalizedId;
  AMeta.AbsolutePath := AAbsolutePath;
  AMeta.SizeBytes := 0;
  AMeta.ModifiedTimeUtc := '';
  if not FileExists(AAbsolutePath) then
    Exit;

  try
    // Listing is best-effort: files can disappear or become temporarily locked
    // between FindFirst and metadata reads, so skip that row instead of surfacing a
    // raw filesystem exception to scripts.list callers.
    AMeta.SizeBytes := TFile.GetSize(AAbsolutePath);
    AMeta.ModifiedTimeUtc := xeFormatUtcDateTime(TFile.GetLastWriteTimeUtc(AAbsolutePath));
    Result := True;
  except
    Result := False;
  end;
end;

function xeLoadScriptSource(const APath: string; out ASource: string): Boolean;
var
  lSource: TStringList;
begin
  Result := False;
  ASource := '';
  lSource := TStringList.Create;
  try
    // Match xeHeadlessJvIScriptHost's TStringList.LoadFromFile path so scripts.read
    // previews the same decoded text that scripts.run will compile.
    lSource.LoadFromFile(APath);
    ASource := lSource.Text;
    Result := True;
  finally
    lSource.Free;
  end;
end;

procedure xeSaveScriptSource(const APath, ASource: string);
var
  lSource: TStringList;
begin
  lSource := TStringList.Create;
  try
    // Save through TStringList as well so stored scripts keep matching the runner's
    // current default-load behavior until that encoding contract is tightened.
    lSource.Text := ASource;
    lSource.SaveToFile(APath);
  finally
    lSource.Free;
  end;
end;

function xeCanonicalizeScriptId(const AId: string; const ARequireAgentWrite: Boolean;
  out ANormalizedId, AAbsolutePath: string; out ARejectionKind: string): Boolean;
begin
  Result := False;
  ANormalizedId := '';
  AAbsolutePath := '';
  ARejectionKind := xeScriptStorageInvalidRequest;

  // This is the stable request-boundary split for daemon errors: syntactically
  // hostile IDs are invalid_request; valid IDs that escape wbScriptsPath or the
  // writable Agent/ namespace are path_outside_namespace.
  if not xeNormalizeScriptIdShape(AId, False, ANormalizedId) then
    Exit;

  AAbsolutePath := xeNormalizedIdToAbsolutePath(ANormalizedId);
  ARejectionKind := xeScriptStoragePathOutsideNamespace;

  if ARequireAgentWrite and not xeIdIsUnderAgentRoot(ANormalizedId) then
    Exit;

  if ARequireAgentWrite then begin
    if not xeCandidatePathIsUnderAgentRoot(AAbsolutePath) then
      Exit;
  end else if not xeCandidatePathIsUnderScriptsRoot(AAbsolutePath) then
    Exit;

  ARejectionKind := '';
  Result := True;
end;

function xeNormalizeScriptListPrefix(const APrefix: string; out ANormalizedPrefix: string): Boolean;
begin
  if Trim(APrefix) = '' then begin
    ANormalizedPrefix := '';
    Exit(True);
  end;

  Result := xeNormalizeScriptIdShape(APrefix, True, ANormalizedPrefix);
end;

function xeFinalPathVisitKey(const APath: string): string;
begin
  Result := AnsiUpperCase(ExcludeTrailingPathDelimiter(APath));
end;

procedure xeCollectScriptsInDirectory(const ARootPath, ADirectory, APrefix: string; const ALimit: Integer;
  const AScripts: TList<TxeScriptMeta>; const AVisitedDirectories: TDictionary<string, Boolean>; var ATotal: Integer);
var
  lSearch: TSearchRec;
  lPath: string;
  lRelativePath: string;
  lId: string;
  lMeta: TxeScriptMeta;
  lDirectoryFinalPath: string;
  lDirectoryVisitKey: string;
begin
  lDirectoryFinalPath := xeFinalPathForExistingPath(ADirectory);
  if lDirectoryFinalPath = '' then
    Exit;

  lDirectoryVisitKey := xeFinalPathVisitKey(lDirectoryFinalPath);
  if AVisitedDirectories.ContainsKey(lDirectoryVisitKey) then
    Exit;
  AVisitedDirectories.Add(lDirectoryVisitKey, True);

  if FindFirst(IncludeTrailingPathDelimiter(ADirectory) + '*', faAnyFile, lSearch) <> 0 then
    Exit;
  try
    repeat
      if (lSearch.Name = '.') or (lSearch.Name = '..') then
        Continue;

      lPath := IncludeTrailingPathDelimiter(ADirectory) + lSearch.Name;
      if (lSearch.Attr and faDirectory) <> 0 then begin
        // Listing intentionally skips reparse directories and also tracks visited
        // final paths so a same-root junction cycle cannot wedge scripts.list.
        if ((lSearch.Attr and FILE_ATTRIBUTE_REPARSE_POINT) = 0) and
          not StartsText('.', lSearch.Name) and xeExistingPathIsUnderScriptsRoot(lPath) then
          xeCollectScriptsInDirectory(ARootPath, lPath, APrefix, ALimit, AScripts, AVisitedDirectories, ATotal);
        Continue;
      end;

      if not SameText(ExtractFileExt(lSearch.Name), '.pas') then
        Continue;

      if not xeExistingPathIsUnderScriptsRoot(lPath) then
        Continue;

      lRelativePath := ExtractRelativePath(ARootPath, lPath);
      lId := StringReplace(ChangeFileExt(lRelativePath, ''), '\', '/', [rfReplaceAll]);
      if (APrefix <> '') and not StartsText(APrefix, lId) then
        Continue;

      if not xeBuildScriptMeta(lId, lPath, lMeta) then
        Continue;

      Inc(ATotal);
      if AScripts.Count >= ALimit then
        Continue;

      AScripts.Add(lMeta);
    until FindNext(lSearch) <> 0;
  finally
    // Windows.FindClose(THandle) shadows SysUtils.FindClose(TSearchRec) because
    // Windows is later in the uses clause; qualify so the search-record overload
    // is selected and the directory enumeration handle is released correctly.
    SysUtils.FindClose(lSearch);
  end;
end;

function xeListScripts(const APrefix: string; const ALimit: Integer;
  out AScripts: TArray<TxeScriptMeta>; out ATotal: Integer; out ATruncated: Boolean): Boolean;
var
  lScripts: TList<TxeScriptMeta>;
  lVisitedDirectories: TDictionary<string, Boolean>;
  lPrefix: string;
  lRootPath: string;
  lEffectiveLimit: Integer;
begin
  Result := False;
  SetLength(AScripts, 0);
  ATotal := 0;
  ATruncated := False;

  if not xeNormalizeScriptListPrefix(APrefix, lPrefix) then
    Exit;

  lRootPath := xeScriptsRootPath;
  if (xeScriptsRootFinalPath = '') or not DirectoryExists(lRootPath) then
    Exit;

  lEffectiveLimit := ALimit;
  if lEffectiveLimit <= 0 then
    lEffectiveLimit := xeScriptStorageDefaultLimit;
  if lEffectiveLimit > xeScriptStorageMaxLimit then
    lEffectiveLimit := xeScriptStorageMaxLimit;

  lScripts := TList<TxeScriptMeta>.Create;
  lVisitedDirectories := TDictionary<string, Boolean>.Create;
  try
    xeCollectScriptsInDirectory(lRootPath, lRootPath, lPrefix, lEffectiveLimit, lScripts, lVisitedDirectories, ATotal);
    AScripts := lScripts.ToArray;
    ATruncated := ATotal > lEffectiveLimit;
    Result := True;
  finally
    lVisitedDirectories.Free;
    lScripts.Free;
  end;
end;

function xeReadScript(const AId: string; out ASource: string): Boolean;
var
  lRejectionKind: string;
begin
  Result := xeReadScript(AId, ASource, lRejectionKind);
end;

function xeReadScript(const AId: string; out ASource: string; out ARejectionKind: string): Boolean;
var
  lNormalizedId: string;
  lAbsolutePath: string;
begin
  Result := False;
  ASource := '';
  ARejectionKind := '';
  if not xeCanonicalizeScriptId(AId, False, lNormalizedId, lAbsolutePath, ARejectionKind) then
    Exit;
  if not FileExists(lAbsolutePath) then begin
    ARejectionKind := xeScriptStorageScriptNotFound;
    Exit;
  end;
  if not xeExistingPathIsUnderScriptsRoot(lAbsolutePath) then begin
    ARejectionKind := xeScriptStoragePathOutsideNamespace;
    Exit;
  end;

  try
    Result := xeLoadScriptSource(lAbsolutePath, ASource);
    if not Result then
      ARejectionKind := xeScriptStorageIoError;
  except
    ARejectionKind := xeScriptStorageIoError;
    Result := False;
  end;
end;

function xeWriteScript(const AId, ASource: string; const AOverwrite: Boolean;
  out AMeta: TxeScriptMeta; out ACreated: Boolean): Boolean;
var
  lRejectionKind: string;
  lAlreadyExists: Boolean;
begin
  Result := xeWriteScript(AId, ASource, AOverwrite, AMeta, ACreated, lRejectionKind, lAlreadyExists);
end;

function xeWriteScript(const AId, ASource: string; const AOverwrite: Boolean;
  out AMeta: TxeScriptMeta; out ACreated: Boolean; out ARejectionKind: string;
  out AAlreadyExists: Boolean): Boolean;
var
  lNormalizedId: string;
  lAbsolutePath: string;
  lDirectory: string;
  lTempPath: string;
  lPreviouslyExisted: Boolean;
  lMoveFlags: DWORD;
  lMoveError: DWORD;
begin
  Result := False;
  AMeta.Id := '';
  AMeta.AbsolutePath := '';
  AMeta.SizeBytes := 0;
  AMeta.ModifiedTimeUtc := '';
  ACreated := False;
  AAlreadyExists := False;
  ARejectionKind := '';

  if not xeCanonicalizeScriptId(AId, False, lNormalizedId, lAbsolutePath, ARejectionKind) then
    Exit;
  if not xeIdIsUnderAgentRoot(lNormalizedId) then begin
    ARejectionKind := xeScriptStoragePathOutsideNamespace;
    Exit;
  end;
  if not xeCandidatePathIsUnderAgentRoot(lAbsolutePath, True) then begin
    ARejectionKind := xeScriptStoragePathOutsideNamespace;
    Exit;
  end;

  lDirectory := ExtractFilePath(lAbsolutePath);
  if not ForceDirectories(lDirectory) then begin
    ARejectionKind := xeScriptStorageIoError;
    Exit;
  end;
  if not xeExistingPathIsUnderAgentRoot(lDirectory) then begin
    ARejectionKind := xeScriptStoragePathOutsideNamespace;
    Exit;
  end;

  lPreviouslyExisted := FileExists(lAbsolutePath);
  if lPreviouslyExisted then begin
    if not xeExistingPathIsUnderAgentRoot(lAbsolutePath) then begin
      ARejectionKind := xeScriptStoragePathOutsideNamespace;
      Exit;
    end;
    if not AOverwrite then begin
      AAlreadyExists := True;
      ARejectionKind := xeScriptStorageAlreadyExists;
      Exit;
    end;
  end;

  lTempPath := IncludeTrailingPathDelimiter(lDirectory) + Format('.%s.%d.%d.tmp',
    [ExtractFileName(lAbsolutePath), GetCurrentProcessId, GetTickCount]);
  // Delphi has no flat try/except/finally; nested try is the canonical shape so the
  // outer finally always cleans the temp file regardless of whether an exception or
  // an early Exit landed first.
  try
    try
      xeSaveScriptSource(lTempPath, ASource);
      // MoveFileEx keeps the replace step inside the script directory so readers
      // never observe a partial write. Without overwrite, omit
      // MOVEFILE_REPLACE_EXISTING so a race-created destination is preserved and
      // reported as already_exists.
      lMoveFlags := MOVEFILE_WRITE_THROUGH;
      if AOverwrite then
        lMoveFlags := lMoveFlags or MOVEFILE_REPLACE_EXISTING;
      if not MoveFileEx(PChar(lTempPath), PChar(lAbsolutePath), lMoveFlags) then begin
        lMoveError := GetLastError;
        if (not AOverwrite) and ((lMoveError = ERROR_ALREADY_EXISTS) or (lMoveError = ERROR_FILE_EXISTS)) then begin
          AAlreadyExists := True;
          ARejectionKind := xeScriptStorageAlreadyExists;
        end else
          ARejectionKind := xeScriptStorageIoError;
        Exit;
      end;
      Result := xeBuildScriptMeta(lNormalizedId, lAbsolutePath, AMeta);
      if Result then begin
        ACreated := not lPreviouslyExisted;
        ARejectionKind := '';
      end else
        ARejectionKind := xeScriptStorageIoError;
    except
      ARejectionKind := xeScriptStorageIoError;
      Result := False;
    end;
  finally
    if FileExists(lTempPath) then
      SysUtils.DeleteFile(lTempPath);
  end;
end;

function xeDeleteScript(const AId: string): Boolean;
var
  lRejectionKind: string;
begin
  Result := xeDeleteScript(AId, lRejectionKind);
end;

function xeDeleteScript(const AId: string; out ARejectionKind: string): Boolean;
var
  lNormalizedId: string;
  lAbsolutePath: string;
begin
  Result := False;
  ARejectionKind := '';
  if not xeCanonicalizeScriptId(AId, False, lNormalizedId, lAbsolutePath, ARejectionKind) then
    Exit;
  if not xeIdIsUnderAgentRoot(lNormalizedId) then begin
    ARejectionKind := xeScriptStoragePathOutsideNamespace;
    Exit;
  end;
  if not FileExists(lAbsolutePath) then begin
    ARejectionKind := xeScriptStorageScriptNotFound;
    Exit;
  end;
  if not xeExistingPathIsUnderAgentRoot(lAbsolutePath) then begin
    ARejectionKind := xeScriptStoragePathOutsideNamespace;
    Exit;
  end;

  try
    Result := SysUtils.DeleteFile(lAbsolutePath);
    if Result then
      ARejectionKind := ''
    else
      ARejectionKind := xeScriptStorageIoError;
  except
    ARejectionKind := xeScriptStorageIoError;
    Result := False;
  end;
end;

end.
