{******************************************************************************

  This Source Code Form is subject to the terms of the Mozilla Public License,
  v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain
  one at https://mozilla.org/MPL/2.0/.

*******************************************************************************}

unit xeScriptRuntimePolicy;

interface

function IsPathUnderScriptsRoot(const aPath: string): Boolean;
procedure xeInstallScriptRuntimePolicy;
procedure xeUninstallScriptRuntimePolicy;

implementation

uses
  Windows,
  Classes,
  SysUtils,
  Variants,
  JvInterpreter,
  wbInterface;

type
  TxeScriptRuntimePolicy = (
    srpAllowPureRead,
    srpAllowInMemoryMutate,
    srpAllowBoundedFsRead,
    srpDenyBlockerUI,
    srpDenyBlockerInput,
    srpDenyWriteFs,
    srpDenySideEffectOs,
    srpDenyHostGuiHook,
    srpDenyHiddenPrompt,
    srpDenyUncategorized);

  TxeScriptRuntimePolicyEntry = record
    Symbol: PChar;
    Action: TJvInterpreterAuthAction;
    Policy: TxeScriptRuntimePolicy;
    PathArgIndex: Integer;
  end;

const
  xePathPrefixWin32Device = '\\?\';
  xePathPrefixDosDevice = '\\.\';
  xePathPrefixNativeDosDevice = '\??\';

  // The runtime policy deliberately stays ledger-shaped instead of using broad
  // type-family shortcuts so newly exposed JvI surfaces remain deny-by-default.
  // Host callback OnGetValue/OnSetValue rows are intentionally excluded here;
  // the headless host owns those callback-policy boundaries.
  xeScriptRuntimePolicyEntries: array[0..686] of TxeScriptRuntimePolicyEntry = (
    (Symbol: 'TwbVector'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'wbVector'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbGridCell'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'wbGridCell'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'Assigned'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'ObjectToElement'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'FullPathToFilename'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'EnableSkyrimSaveFormat'; Action: aaGet; Policy: srpDenyUncategorized; PathArgIndex: -1),
    (Symbol: 'GetRecordDefNames'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'wbFilterStrings'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'wbRemoveDuplicateStrings'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'wbVersionNumber'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'Name'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'ShortName'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'BaseName'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'DisplayName'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'Path'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'IndexedPath'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'FullPath'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'PathName'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'ElementType'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'ElementTypeAsText'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'DefType'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'DefTypeAsText'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'EnumValues'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'FlagValues'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SortKey'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'IsInjected'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'IsEditable'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'GetEditValue'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'GetValue'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SetEditValue'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'GetNativeValue'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SetNativeValue'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'Remove'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'GetFile'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'GetContainer'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'ContainingMainRecord'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'LinksTo'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'Check'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'ElementAssign'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TemplateAssign'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'Equals'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'CanContainFormIDs'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'CanMoveUp'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'CanMoveDown'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'MoveUp'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'MoveDown'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'wbCopyElementToFile'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'wbCopyElementToFileWithPrefix'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'wbCopyElementToFileWithPrefixAndSuffix'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'wbCopyElementToRecord'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'ClearElementState'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'SetElementState'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'GetElementState'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'ReportRequiredMasters'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'BuildRef'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'MarkModifiedRecursive'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'SetToDefault'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'BeginUpdate'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'EndUpdate'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'GetSummary'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'AssignTemplateCount'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'AssignTemplateByIndex'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'AssignTemplateByName'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'GetElementEditValues'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'GetElementValues'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SetElementEditValues'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'GetElementNativeValues'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SetElementNativeValues'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'ElementByName'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'ElementBySignature'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'ElementByPath'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'AdditionalElementCount'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'ElementCount'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'ElementByIndex'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'ElementExists'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'LastElement'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'IndexOf'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'Add'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'AddElement'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'InsertElement'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'RemoveElement'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'RemoveByIndex'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'ReverseElements'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'ContainerStates'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'IsSorted'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'Signature'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'FormID'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'EditorID'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SetEditorID'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'FixedFormID'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'GetLoadOrderFormID'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SetLoadOrderFormID'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'GetIsDeleted'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SetIsDeleted'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'GetIsInitiallyDisabled'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SetIsInitiallyDisabled'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'GetIsPersistent'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SetIsPersistent'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'GetIsVisibleWhenDistant'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SetIsVisibleWhenDistant'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'GetFormVersion'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SetFormVersion'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'GetFormVCS1'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SetFormVCS1'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'GetFormVCS2'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SetFormVCS2'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'OverrideCount'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'OverrideByIndex'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'ReferencedByCount'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'ReferencedByIndex'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'ReferencesCount'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'ReferencesByIndex'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'Master'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'MasterOrSelf'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'IsMaster'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'IsWinningOverride'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'WinningOverride'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'HighestOverrideOrSelf'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'BaseRecord'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'BaseRecordID'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'UpdateRefs'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'ChildGroup'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'CompareExchangeFormID'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'ChangeFormSignature'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'GetPosition'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'GetRotation'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'GetGridCell'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'HasPrecombinedMesh'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'PrecombinedMesh'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'GroupType'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'GroupLabel'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'ChildrenOf'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'MainRecordByEditorID'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'FindChildGroup'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'GetFileName'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'GetLoadOrderFileID'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'GetLoadOrder'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'GetNewFormID'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'GetIsESM'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SetIsESM'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'GetIsESL'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SetIsESL'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'CanBeESL'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'GetIsLight'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SetIsLight'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'CanBeLight'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'GetIsSmall'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SetIsSmall'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'CanBeSmall'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'GetIsMedium'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SetIsMedium'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'CanBeMedium'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SortMasters'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'CleanMasters'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'MasterCount'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'MasterByIndex'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'RecordCount'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'RecordByIndex'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'GroupBySignature'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'RecordByFormID'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'RecordByFormIDStrict'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'RecordByEditorID'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'GetMasters'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'AddMasters'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'AddMasterIfMissing'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'AddMastersIfMissing'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'HasMaster'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'HasGroup'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'LoadOrderFormIDtoFileFormID'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'FileFormIDtoLoadOrderFormID'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'FileWriteToStream'; Action: aaGet; Policy: srpDenyWriteFs; PathArgIndex: -1),
    (Symbol: 'ResourceContainerList'; Action: aaGet; Policy: srpDenyUncategorized; PathArgIndex: -1),
    (Symbol: 'ResourceExists'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'ResourceCount'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'ResourceList'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'ResourceOpenData'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'ResourceCopy'; Action: aaGet; Policy: srpDenyWriteFs; PathArgIndex: 2),
    (Symbol: 'TwbFastStringList'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbFastStringList.Create'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'NifBlockList'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'NifTextureList'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'NifTextureListResource'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'NifTextureListUVRange'; Action: aaGet; Policy: srpDenyUncategorized; PathArgIndex: -1),
    (Symbol: 'wbDDSStreamToBitmap'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'wbDDSDataToBitmap'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'wbDDSResourceToBitmap'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'wbFlipBitmap'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'wbAlphaBlend'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'wbPositionToGridCell'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'wbSubBlockFromGridCell'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'wbBlockFromSubBlock'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'wbGridCellToGroupLabel'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'wbIsInGridCell'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'wbCRC32Data'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'wbCRC32Resource'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'wbCRC32File'; Action: aaGet; Policy: srpDenySideEffectOs; PathArgIndex: 0),
    (Symbol: 'bscrc32'; Action: aaGet; Policy: srpDenySideEffectOs; PathArgIndex: 0),
    (Symbol: 'CreateHashTES3'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'CreateHashTES4'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'CreateHashFO4'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'wbSHA1Data'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'wbSHA1File'; Action: aaGet; Policy: srpDenySideEffectOs; PathArgIndex: 0),
    (Symbol: 'wbMD5Data'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'wbMD5File'; Action: aaGet; Policy: srpDenySideEffectOs; PathArgIndex: 0),
    (Symbol: 'wbFindREFRsByBase'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'wbGetSiblingRecords'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'wbNormalizeResourceName'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'wbStringListInString'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'LocalizationGetStringsFromFile'; Action: aaGet; Policy: srpDenySideEffectOs; PathArgIndex: 0),
    (Symbol: 'wbFormIDErrorCheckLock'; Action: aaGet; Policy: srpDenyUncategorized; PathArgIndex: -1),
    (Symbol: 'wbFormIDErrorCheckUnlock'; Action: aaGet; Policy: srpDenyUncategorized; PathArgIndex: -1),
    (Symbol: 'wbIsPseudoESLMode'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'wbIsPseudoLightMode'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'wbIsPseudoSmallMode'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'wbIsPseudoMediumMode'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'dfFloatToStr'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'dfStrToFloat'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'dfCalcHash'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfDef'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfDef.Name'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfDef.DefaultDataSize'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfDef.DefaultValue'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfDef.Size'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfElement'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfElement.DataType'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfElement.Def'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfElement.Name'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfElement.Path'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfElement.Root'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfElement.Parent'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfElement.Parent'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TdfElement.DataSize'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfElement.BeginUpdate'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TdfElement.EndUpdate'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TdfElement.Enabled'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfElement.Enabled'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TdfElement.Count'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfElement.Count'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TdfElement.Index'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfElement.IndexOf'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfElement.Add'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TdfElement.Remove'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TdfElement.Delete'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TdfElement.Move'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TdfElement.LinksTo'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfElement.NativeValue'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfElement.NativeValue'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TdfElement.NativeValues'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfElement.NativeValues'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TdfElement.EditValue'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfElement.EditValue'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TdfElement.EditValues'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfElement.EditValues'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TdfElement.Items'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfElement.<default indexed get>'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfElement.Elements'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfElement.ElementByName'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfElement.ElementByPath'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfElement.LoadFromData'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TdfElement.LoadFromFile'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: 0),
    (Symbol: 'TdfElement.LoadFromJSONFile'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: 0),
    (Symbol: 'TdfElement.LoadFromResource'; Action: aaGet; Policy: srpDenySideEffectOs; PathArgIndex: -1),
    (Symbol: 'TdfElement.SaveToFile'; Action: aaGet; Policy: srpDenyWriteFs; PathArgIndex: 0),
    (Symbol: 'TdfElement.SaveToJSONFile'; Action: aaGet; Policy: srpDenyWriteFs; PathArgIndex: 0),
    (Symbol: 'TdfElement.SetToDefault'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TdfElement.Assign'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TdfElement.FromJSON'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TdfElement.ToJSON'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfElement.ToText'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfValueDef'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfValue'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfContainer'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfArrayDef'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfArray'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfStructDef'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfStruct'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfUnionDef'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfUnion'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfValueUnionDef'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfValueUnion'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfMergeDef'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfMerge'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfIntegerDef'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfInteger'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfMappedIntegerDef'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfFlagsDef'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfFlags'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfEnumDef'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfEnum'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfFloatDef'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfFloat'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfBytesDef'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfBytes'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfCharsDef'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TdfChars'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNiRefDef'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNiRef'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNiRef.Template'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNiRef.Ptr'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifBlockDef'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifBlock'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifBlock.BlockType'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifBlock.NifFile'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifBlock.RefsCount'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifBlock.Refs'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifBlock.StringsCount'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifBlock.Strings'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifBlock.IsNiObject'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifBlock.AddChild'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TwbNifBlock.AddExtraData'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TwbNifBlock.AddProperty'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TwbNifBlock.PropertyByName'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifBlock.ExtraDataByName'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifBlock.ChildrenByType'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifBlock.ChildByType'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifBlock.PropertiesByType'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifBlock.PropertyByType'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifBlock.ExtraDatasByType'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifBlock.ExtraDataByType'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifBlock.UpdateBounds'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TwbNifBlock.UpdateNormals'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TwbNifBlock.UpdateTangents'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TwbNifBlock.GetAssetsList'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifFile'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifFile.Create'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifFile.NifVersion'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifFile.NifVersion'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TwbNifFile.InternalUpdates'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TwbNifFile.InternalUpdates'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TwbNifFile.Options'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifFile.Options'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TwbNifFile.Header'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifFile.Footer'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifFile.BlocksCount'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifFile.Blocks'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifFile.AddBlock'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TwbNifFile.InsertBlock'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TwbNifFile.ConvertBlock'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TwbNifFile.CopyBlock'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TwbNifFile.BlockByType'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifFile.BlocksByType'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifFile.BlockByName'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbNifFile.SpellTriangulate'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TwbNifFile.SpellFaceNormals'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TwbNifFile.SpellUpdateTangents'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TwbNifFile.SpellAddUpdateTangents'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TwbNifFile.GetAssetsList'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbBGSMFile'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbBGSMFile.Create'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbBGEMFile'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbBGEMFile.Create'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbLODTreeLSTFile'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbLODTreeLSTFile.Create'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbLODTreeBTTFile'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbLODTreeBTTFile.Create'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbLODSettingsFO3File'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbLODSettingsFO3File.Create'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TwbLODSettingsTES5File'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbLODSettingsTES5File.Create'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TwbFUZFile'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbFUZFile.Create'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbDDSFile'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TwbDDSFile.Create'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'GetClipboardText'; Action: aaGet; Policy: srpDenySideEffectOs; PathArgIndex: -1),
    (Symbol: 'SetClipboardText'; Action: aaGet; Policy: srpDenySideEffectOs; PathArgIndex: -1),
    (Symbol: 'ContainsStr'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'ContainsText'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'DupeString'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'EndsStr'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'EndsText'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'IfThen'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'IndexStr'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'IndexText'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'LeftStr'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'MatchStr'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'MatchText'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'MidStr'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'ReverseString'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'RightStr'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'StartsStr'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'StartsText'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SplitString'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'StuffString'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'VarType'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'VarTypeAsText'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'Inc'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'Dec'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'Succ'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'Pred'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'Frac'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'Int'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SameText'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SameValue'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'StringReplace'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'IntToHex64'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'StrToInt64'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'StrToInt64Def'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'StrToFloatDef'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'DirectoryExists'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: 0),
    (Symbol: 'FileExists'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: 0),
    (Symbol: 'fmOpenRead'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'fmCreate'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TFileStream'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TFileStream.Create'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: 0),
    (Symbol: 'ForceDirectories'; Action: aaGet; Policy: srpDenyWriteFs; PathArgIndex: 0),
    (Symbol: 'IncludeTrailingBackslash'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'ExcludeTrailingBackslash'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'StringOfChar'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'CopyFile'; Action: aaGet; Policy: srpDenyWriteFs; PathArgIndex: 0),
    (Symbol: 'ShellExecute'; Action: aaGet; Policy: srpDenySideEffectOs; PathArgIndex: 2),
    (Symbol: 'ShellExecuteWait'; Action: aaGet; Policy: srpDenySideEffectOs; PathArgIndex: 2),
    (Symbol: 'CreateProcessWait'; Action: aaGet; Policy: srpDenySideEffectOs; PathArgIndex: 0),
    (Symbol: 'Sleep'; Action: aaGet; Policy: srpDenySideEffectOs; PathArgIndex: -1),
    (Symbol: 'GetKeyState'; Action: aaGet; Policy: srpDenyBlockerInput; PathArgIndex: -1),
    (Symbol: 'SelectDirectory'; Action: aaGet; Policy: srpDenyBlockerInput; PathArgIndex: 2),
    (Symbol: 'TEncoding'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TEncoding.Default'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TEncoding.ASCII'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TEncoding.Unicode'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TEncoding.UTF8'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'CompareValue'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'EnsureRange'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'FMod'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'GetPrecisionMode'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'GetRoundMode'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'InRange'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'IsZero'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'InverseLerp'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'Lerp'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'LerpUnclamped'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'RoundTo'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SetPrecisionMode'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'SetRoundMode'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'Sign'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'SimpleRoundTo'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TStrings.Delimiter'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TStrings.Delimiter'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TStrings.StrictDelimiter'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TStrings.NameValueSeparator'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TStrings.DelimitedText'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TStrings.DelimitedText'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TStrings.ValueFromIndex'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TStrings.ValueFromIndex'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TStrings.CaseSensitive'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TStrings.CaseSensitive'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TStrings.Difference'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TStrings.Intersection'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TStrings.SymmetricDifference'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TStrings.Union'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'THashedStringList'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'THashedStringList.Create'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TBytesStream'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TBytesStream.Create'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TBinaryReader'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TBinaryReader.Create'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'TBinaryReader.Read'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'TBinaryReader.ReadBoolean'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'TBinaryReader.ReadByte'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'TBinaryReader.ReadBytes'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'TBinaryReader.ReadChar'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'TBinaryReader.ReadDouble'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'TBinaryReader.ReadShortInt'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'TBinaryReader.ReadSmallInt'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'TBinaryReader.ReadUInt16'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'TBinaryReader.ReadUInt32'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'TBinaryReader.ReadInteger'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'TBinaryReader.ReadSingle'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'TBinaryReader.ReadString'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'TBinaryWriter'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TBinaryWriter.Create'; Action: aaGet; Policy: srpDenyWriteFs; PathArgIndex: -1),
    (Symbol: 'TBinaryWriter.Write'; Action: aaGet; Policy: srpDenyWriteFs; PathArgIndex: -1),
    (Symbol: 'TBinaryWriter.WriteSingle'; Action: aaGet; Policy: srpDenyWriteFs; PathArgIndex: -1),
    (Symbol: 'TWinControl.DoubleBuffered'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TWinControl.DoubleBuffered'; Action: aaSet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TCustomForm.PopupMode'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TCustomForm.PopupMode'; Action: aaSet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TCustomForm.PopupParent'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TCustomForm.PopupParent'; Action: aaSet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TCheckListBox'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TCheckListBox.Create'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TCheckListBox.CheckAll'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TCheckListBox.Checked'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TCheckListBox.Checked'; Action: aaSet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TCheckListBox.State'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TCheckListBox.State'; Action: aaSet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TCheckListBox.Header'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TCheckListBox.Header'; Action: aaSet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TCheckListBox.ItemEnabled'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TCheckListBox.ItemEnabled'; Action: aaSet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TCheckListBox.AllowGrayed'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TCheckListBox.AllowGrayed'; Action: aaSet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'CheckLst.TNotifyEvent handler'; Action: aaSet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TComboBox.DropDownCount'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TComboBox.DropDownCount'; Action: aaSet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TCustomLabeledEdit'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TCustomLabeledEdit.Create'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TCustomLabeledEdit.EditLabel'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TCustomLabeledEdit.LabelPosition'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TCustomLabeledEdit.LabelPosition'; Action: aaSet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TCustomLabeledEdit.LabelSpacing'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TCustomLabeledEdit.LabelSpacing'; Action: aaSet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TLabeledEdit'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TLabeledEdit.Create'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TBoundLabel'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TListItem.SubItems'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TListItem.SubItems'; Action: aaSet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TListItems.Count'; Action: aaSet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'ComCtrls.TLVOwnerDataEvent handler'; Action: aaSet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'ComCtrls.TLVSelectItemEvent handler'; Action: aaSet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TMenu.AutoHotKeys'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TMenu.AutoHotKeys'; Action: aaSet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TMenuItem.Clear'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TBitmap.SetSize'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TCustomIniFile'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TCustomIniFile.ReadString'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'TCustomIniFile.ReadInteger'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'TCustomIniFile.ReadFloat'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'TCustomIniFile.ReadBool'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'TCustomIniFile.WriteString'; Action: aaGet; Policy: srpDenyWriteFs; PathArgIndex: -1),
    (Symbol: 'TCustomIniFile.WriteInteger'; Action: aaGet; Policy: srpDenyWriteFs; PathArgIndex: -1),
    (Symbol: 'TCustomIniFile.WriteFloat'; Action: aaGet; Policy: srpDenyWriteFs; PathArgIndex: -1),
    (Symbol: 'TCustomIniFile.WriteBool'; Action: aaGet; Policy: srpDenyWriteFs; PathArgIndex: -1),
    (Symbol: 'TCustomIniFile.DeleteKey'; Action: aaGet; Policy: srpDenyWriteFs; PathArgIndex: -1),
    (Symbol: 'TCustomIniFile.EraseSection'; Action: aaGet; Policy: srpDenyWriteFs; PathArgIndex: -1),
    (Symbol: 'TCustomIniFile.SectionExists'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'TCustomIniFile.ValueExists'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'TCustomIniFile.ReadSection'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'TCustomIniFile.ReadSections'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'TCustomIniFile.ReadSectionValues'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'TCustomIniFile.UpdateFile'; Action: aaGet; Policy: srpDenyWriteFs; PathArgIndex: -1),
    (Symbol: 'TIniFile'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TIniFile.Create'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: 0),
    (Symbol: 'TMemIniFile'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TMemIniFile.Create'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: 0),
    (Symbol: 'TMemIniFile.GetStrings'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TMemIniFile.SetStrings'; Action: aaGet; Policy: srpDenyWriteFs; PathArgIndex: -1),
    (Symbol: 'TRegistryIniFile'; Action: aaGet; Policy: srpDenySideEffectOs; PathArgIndex: -1),
    (Symbol: 'TRegistryIniFile.Create'; Action: aaGet; Policy: srpDenySideEffectOs; PathArgIndex: -1),
    (Symbol: 'TControl.ScaleValue'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TControl.StyleElements'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TControl.StyleElements'; Action: aaSet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'frmMain'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'frmFileSelect'; Action: aaGet; Policy: srpDenyHostGuiHook; PathArgIndex: -1),
    (Symbol: 'TStringList'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TStringList.Create'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TStrings.Text'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TMemoryStream'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TMemoryStream.Create'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TStream.Size'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TDirectory'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TDirectory.GetDirectories'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: 0),
    (Symbol: 'TDirectory.GetFiles'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: 0),
    (Symbol: 'TFile'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TFile.ReadAllText'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: 0),
    (Symbol: 'TStrings.LoadFromFile'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: 0),
    (Symbol: 'TMemoryStream.LoadFromFile'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: 0),
    (Symbol: 'TFile.WriteAllText'; Action: aaGet; Policy: srpDenyWriteFs; PathArgIndex: 0),
    (Symbol: 'TPerlRegEx'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.Create'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.EscapeRegExChars'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.Compile'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.Compiled'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.Study'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.Studied'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.Match'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.MatchAgain'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.Replace'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.ReplaceAll'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.ComputeReplacement'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.StoreGroups'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.NamedGroup'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.Split'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.SplitCapture'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.FoundMatch'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.MatchedText'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.MatchedLength'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.MatchedOffset'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.Start'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.Start'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.Stop'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.Stop'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.GroupCount'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.Groups'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.GroupLengths'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.GroupOffsets'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.Subject'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.Subject'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.SubjectLeft'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.SubjectRight'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.Options'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.Options'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.RegEx'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.RegEx'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.Replacement'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TPerlRegEx.Replacement'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'SetJDOLineBreak'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'SetJDOIndentChar'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'SetJDOUseUtcTime'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'SetJDONullConvertsToValueTypes'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonBaseObject'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonBaseObject.Parse'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonBaseObject.LoadFromFile'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: 0),
    (Symbol: 'TJsonBaseObject.LoadFromStream'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonBaseObject.LoadFromResource'; Action: aaGet; Policy: srpAllowBoundedFsRead; PathArgIndex: -1),
    (Symbol: 'TJsonBaseObject.SaveToFile'; Action: aaGet; Policy: srpDenyWriteFs; PathArgIndex: 0),
    (Symbol: 'TJsonBaseObject.SaveToStream'; Action: aaGet; Policy: srpDenyWriteFs; PathArgIndex: -1),
    (Symbol: 'TJsonBaseObject.SaveToLines'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonBaseObject.FromJSON'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonBaseObject.ToJSON'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonBaseObject.ToString'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonArray'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonArray.Create'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonArray.Parse'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonArray.Count'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonArray.Count'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonArray.Types'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonArray.Clear'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonArray.Delete'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonArray.Extract'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonArray.ExtractArray'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonArray.ExtractObject'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonArray.Assign'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonArray.AddArray'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonArray.AddObject'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonArray.Add'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonArray.Insert'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonArray.InsertArray'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonArray.InsertObject'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonArray.IsNull'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonArray.S'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonArray.S'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonArray.I'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonArray.I'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonArray.L'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonArray.L'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonArray.U'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonArray.U'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonArray.F'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonArray.F'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonArray.D'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonArray.D'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonArray.B'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonArray.B'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonArray.A'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonArray.A'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonArray.O'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonArray.O'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonArray.<default indexed get>'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonArray.<default indexed set>'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonObject'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonObject.Create'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonObject.Parse'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonObject.Count'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonObject.Types'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonObject.Names'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonObject.Clear'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonObject.Delete'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonObject.Remove'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonObject.IndexOf'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonObject.Contains'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonObject.Extract'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonObject.ExtractArray'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonObject.ExtractObject'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonObject.Assign'; Action: aaGet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonObject.IsNull'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonObject.S'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonObject.S'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonObject.I'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonObject.I'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonObject.L'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonObject.L'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonObject.U'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonObject.U'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonObject.F'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonObject.F'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonObject.D'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonObject.D'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonObject.B'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonObject.B'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonObject.A'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonObject.A'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonObject.O'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonObject.O'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1),
    (Symbol: 'TJsonObject.<default indexed get>'; Action: aaGet; Policy: srpAllowPureRead; PathArgIndex: -1),
    (Symbol: 'TJsonObject.<default indexed set>'; Action: aaSet; Policy: srpAllowInMemoryMutate; PathArgIndex: -1)
  );

var
  xeScriptRuntimePolicyInstalled: Boolean;
  xePreviousJvInterpreterAuthHook: TJvInterpreterAuthHook;

function xePolicyIsDeny(aPolicy: TxeScriptRuntimePolicy): Boolean;
begin
  Result := aPolicy in [
    srpDenyBlockerUI,
    srpDenyBlockerInput,
    srpDenyWriteFs,
    srpDenySideEffectOs,
    srpDenyHostGuiHook,
    srpDenyHiddenPrompt,
    srpDenyUncategorized];
end;

function xePolicyName(aPolicy: TxeScriptRuntimePolicy): string;
begin
  case aPolicy of
    srpAllowPureRead: Result := 'allow_pure_read';
    srpAllowInMemoryMutate: Result := 'allow_inmemory_mutate';
    srpAllowBoundedFsRead: Result := 'allow_bounded_fs_read';
    srpDenyBlockerUI: Result := 'deny_blocker_ui';
    srpDenyBlockerInput: Result := 'deny_blocker_input';
    srpDenyWriteFs: Result := 'deny_write_fs';
    srpDenySideEffectOs: Result := 'deny_side_effect_os';
    srpDenyHostGuiHook: Result := 'deny_host_gui_hook';
    srpDenyHiddenPrompt: Result := 'deny_hidden_prompt';
    srpDenyUncategorized: Result := 'deny_uncategorized';
  else
    Result := 'unknown';
  end;
end;

function xeStartsWithText(const aValue, aPrefix: string): Boolean;
begin
  Result := (Length(aValue) >= Length(aPrefix)) and
    SameText(Copy(aValue, 1, Length(aPrefix)), aPrefix);
end;

function xeContainsTraversalSegment(const aPath: string): Boolean;
var
  i: Integer;
  lPart: string;
  lPath: string;
begin
  lPath := StringReplace(aPath, '/', '\', [rfReplaceAll]);
  lPart := '';
  for i := 1 to Length(lPath) do begin
    if lPath[i] = '\' then begin
      if lPart = '..' then
        Exit(True);
      lPart := '';
    end else
      lPart := lPart + lPath[i];
  end;
  Result := lPart = '..';
end;

function xeHasExtraColon(const aPath: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 1 to Length(aPath) do
    if aPath[i] = ':' then
      if i <> 2 then
        Exit(True);
end;

function xeHasSuspiciousPathSyntax(const aPath: string): Boolean;
var
  lPath: string;
begin
  lPath := Trim(aPath);
  Result := (lPath = '') or
    (Pos(#0, lPath) > 0) or
    xeStartsWithText(lPath, xePathPrefixWin32Device) or
    xeStartsWithText(lPath, xePathPrefixDosDevice) or
    xeStartsWithText(lPath, xePathPrefixNativeDosDevice) or
    ((Length(lPath) > 0) and (lPath[1] in ['\', '/']) and
      not ((Length(lPath) > 1) and (lPath[2] in ['\', '/']))) or
    xeHasExtraColon(lPath) or
    xeContainsTraversalSegment(lPath);
end;

function xeIsAbsoluteWinPath(const aPath: string): Boolean;
begin
  Result := ((Length(aPath) >= 3) and (aPath[2] = ':') and
      (aPath[3] in ['\', '/'])) or
    ((Length(aPath) >= 2) and (aPath[1] in ['\', '/']) and
      (aPath[2] in ['\', '/']));
end;

function xeNormalizeFinalPathPrefix(const aPath: string): string;
begin
  Result := StringReplace(aPath, '/', '\', [rfReplaceAll]);
  if xeStartsWithText(Result, '\\?\UNC\') then
    Result := '\\' + Copy(Result, 9, MaxInt)
  else if xeStartsWithText(Result, xePathPrefixWin32Device) then
    Result := Copy(Result, 5, MaxInt);
end;

function xeFinalPathForExistingPath(const aPath: string): string;
var
  lHandle: THandle;
  lLength: DWORD;
begin
  Result := '';
  lHandle := CreateFile(PChar(aPath), 0,
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

function xeStrictDescendantOf(const aChild, aRoot: string): Boolean;
var
  lRoot: string;
  lChild: string;
begin
  lRoot := ExcludeTrailingPathDelimiter(aRoot);
  lChild := ExcludeTrailingPathDelimiter(aChild);
  Result := (Length(lChild) > Length(lRoot) + 1) and
    SameText(Copy(lChild, 1, Length(lRoot)), lRoot) and
    (lChild[Length(lRoot) + 1] = '\');
end;

function IsPathUnderScriptsRoot(const aPath: string): Boolean;
var
  lCandidatePath: string;
  lRootPath: string;
  lCandidateFinalPath: string;
  lRootFinalPath: string;
begin
  Result := False;

  // Bounded filesystem reads are still host-file reads, so normalize through
  // Win32 final paths before comparing. This closes traversal, symlink, and
  // junction escapes that a simple ExpandFileName prefix check would miss.
  if xeHasSuspiciousPathSyntax(aPath) or (Trim(wbScriptsPath) = '') then
    Exit;

  lRootPath := ExpandFileName(IncludeTrailingPathDelimiter(wbScriptsPath));
  if xeIsAbsoluteWinPath(aPath) then
    lCandidatePath := ExpandFileName(aPath)
  else
    lCandidatePath := ExpandFileName(IncludeTrailingPathDelimiter(wbScriptsPath) + aPath);

  lRootFinalPath := xeFinalPathForExistingPath(lRootPath);
  lCandidateFinalPath := xeFinalPathForExistingPath(lCandidatePath);
  if (lRootFinalPath = '') or (lCandidateFinalPath = '') then
    Exit;

  Result := xeStrictDescendantOf(lCandidateFinalPath, lRootFinalPath);
end;

function xeEntrySymbolMatches(const aEntrySymbol, aIdentifier: string; aObjClass: TClass): Boolean;
var
  lClass: TClass;
  lDotPos: Integer;
  lClassName: string;
  lMemberName: string;
begin
  Result := False;
  if SameText(aEntrySymbol, aIdentifier) and
    (Pos('.', aEntrySymbol) > 0) and (Pos('.', aIdentifier) > 0) then
    Exit(True);

  lDotPos := Pos('.', aEntrySymbol);
  if lDotPos = 0 then begin
    // Bare ledger rows describe globals and class tokens only. Member access
    // must match a qualified Class.Member row with an object class.
    Result := (aObjClass = nil) and SameText(aEntrySymbol, aIdentifier);
    Exit;
  end;

  if not Assigned(aObjClass) then
    Exit;

  lClassName := Copy(aEntrySymbol, 1, lDotPos - 1);
  lMemberName := Copy(aEntrySymbol, lDotPos + 1, MaxInt);
  if not SameText(lMemberName, aIdentifier) then
    Exit;

  lClass := aObjClass;
  while Assigned(lClass) do begin
    if SameText(lClass.ClassName, lClassName) then
      Exit(True);
    lClass := lClass.ClassParent;
  end;
end;

function xeFindPolicyEntry(const aIdentifier: string; aObjClass: TClass;
  aAction: TJvInterpreterAuthAction; aDenyOnly: Boolean;
  aRequireMutableSet: Boolean; out aEntry: TxeScriptRuntimePolicyEntry): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := Low(xeScriptRuntimePolicyEntries) to High(xeScriptRuntimePolicyEntries) do begin
    if xeScriptRuntimePolicyEntries[i].Action <> aAction then
      Continue;
    if aDenyOnly <> xePolicyIsDeny(xeScriptRuntimePolicyEntries[i].Policy) then
      Continue;
    if aRequireMutableSet and (xeScriptRuntimePolicyEntries[i].Policy <> srpAllowInMemoryMutate) then
      Continue;
    if xeEntrySymbolMatches(string(xeScriptRuntimePolicyEntries[i].Symbol), aIdentifier, aObjClass) then begin
      aEntry := xeScriptRuntimePolicyEntries[i];
      Exit(True);
    end;
  end;
end;

function xeAnyPolicyEntryMatches(const aIdentifier: string; aObjClass: TClass): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := Low(xeScriptRuntimePolicyEntries) to High(xeScriptRuntimePolicyEntries) do
    if xeEntrySymbolMatches(string(xeScriptRuntimePolicyEntries[i].Symbol), aIdentifier, aObjClass) then
      Exit(True);
end;

function xePathArgumentAllowed(aArgs: TJvInterpreterArgs; aPathArgIndex: Integer;
  out aDenyReason: string): Boolean;
var
  lPath: string;
begin
  Result := False;
  if not Assigned(aArgs) or (aPathArgIndex < 0) or (aPathArgIndex >= aArgs.Count) then begin
    aDenyReason := 'missing bounded filesystem path argument';
    Exit;
  end;

  lPath := VarToStr(aArgs.Values[aPathArgIndex]);
  if not IsPathUnderScriptsRoot(lPath) then begin
    aDenyReason := 'filesystem read path is outside ScriptsPath or crosses a reparse boundary';
    Exit;
  end;

  Result := True;
end;

function xeFileStreamReadModeAllowed(aArgs: TJvInterpreterArgs; out aDenyReason: string): Boolean;
var
  lMode: Integer;
begin
  Result := False;
  if not Assigned(aArgs) or (aArgs.Count < 2) then begin
    aDenyReason := 'missing TFileStream.Create mode argument';
    Exit;
  end;

  lMode := VarAsType(aArgs.Values[1], varInteger);
  if (lMode = fmCreate) or ((lMode and 3) <> fmOpenRead) then begin
    aDenyReason := 'TFileStream.Create write mode is denied by headless runtime policy';
    Exit;
  end;

  Result := True;
end;

function xeScriptRuntimePolicyAuthHook(const Identifier: string; ObjClass: TClass;
  Args: TJvInterpreterArgs; Action: TJvInterpreterAuthAction; var DenyReason: string): Boolean;
var
  lEntry: TxeScriptRuntimePolicyEntry;
begin
  Result := False;
  DenyReason := '';

  // Deny rows are evaluated before allow rows so high-risk surfaces from the
  // audit remain blocked even when a similarly named read helper exists.
  if xeFindPolicyEntry(Identifier, ObjClass, Action, True, False, lEntry) then begin
    DenyReason := 'runtime policy denied by ledger classification ' + xePolicyName(lEntry.Policy);
    Exit;
  end;

  if Action = aaSet then begin
    // Most ledger rows are read-only even though the JVCL seam observes all
    // assignments as aaSet. Only explicit allow_inmemory_mutate setter rows may
    // pass; everything else preserves read-only script API semantics.
    if xeFindPolicyEntry(Identifier, ObjClass, Action, False, True, lEntry) then
      Exit(True);
    if xeAnyPolicyEntryMatches(Identifier, ObjClass) then
      DenyReason := 'runtime policy denied setter for non-mutable ledger classification'
    else
      DenyReason := 'runtime policy deny-default: symbol is not in the JvI ledger';
    Exit;
  end;

  if not xeFindPolicyEntry(Identifier, ObjClass, Action, False, False, lEntry) then begin
    DenyReason := 'runtime policy deny-default: symbol is not in the JvI ledger';
    Exit;
  end;

  if (lEntry.Policy = srpAllowBoundedFsRead) and (lEntry.PathArgIndex >= 0) then begin
    if not xePathArgumentAllowed(Args, lEntry.PathArgIndex, DenyReason) then
      Exit(False);
    // TFileStream.Create is allowed only for read-only opens under ScriptsPath;
    // write/create modes stay denied even when the path itself is in-bounds.
    if SameText(string(lEntry.Symbol), 'TFileStream.Create') then
      Exit(xeFileStreamReadModeAllowed(Args, DenyReason));
    Exit(True);
  end;

  Result := True;
end;

procedure xeInstallScriptRuntimePolicy;
begin
  if xeScriptRuntimePolicyInstalled then
    Exit;

  // Policy lifetime is scoped explicitly around a headless run. Preserve any
  // pre-existing JVCL auth hook so temporary daemon policy does not permanently
  // erase another host/tool's authorization seam when the run unwinds.
  xePreviousJvInterpreterAuthHook := JvInterpreterAuthHook;
  JvInterpreterAuthHook := xeScriptRuntimePolicyAuthHook;
  xeScriptRuntimePolicyInstalled := True;
end;

procedure xeUninstallScriptRuntimePolicy;
begin
  if not xeScriptRuntimePolicyInstalled then
    Exit;

  // Only restore when our hook is still current. If a later owner replaced it,
  // do not clobber that owner; just forget our saved state and mark this policy
  // scope closed.
  if @JvInterpreterAuthHook = @xeScriptRuntimePolicyAuthHook then
    JvInterpreterAuthHook := xePreviousJvInterpreterAuthHook;
  xePreviousJvInterpreterAuthHook := nil;
  xeScriptRuntimePolicyInstalled := False;
end;

end.
