# xEdit Automation Roadmap

This roadmap exists to prevent design drift while the automation work is still forming. It describes the intended direction for an upstreamable xEdit automation subsystem and breaks the work into phases. Early phases are intentionally more specific than later phases.

This repo's scope is the xEdit-side extension only. It may expose a stable CLI automation surface that an external MCP project can drive, but the MCP server/adapter itself is out of scope here.

## Current Status

The current local truth on this branch is now the accepted Phase 13 `elements.*` mutation surface expansion on top of the Phase 12 Starfield plain `.esp` write enablement, Phase 11 navigate-to-record, and the scoped xEdit-side `1.0` freeze:

- Phase 9 remains the accepted `0.9` lower bound.
- Phase 10 passed the three-family semantic E2E freeze gate across Task A, Task B, and Task C.
- Task C is accepted as `DONE_WITH_CONCERNS`, not a perfect-clean claim; the concerns are explicit and non-blocking.
- Phase 11 locally adds `session.navigate_to_record` as a record-root navigation primitive and verifies it against the MO2-managed OpenCodeXEdit target.
- Phase 11 positive navigation passed for `Fallout4.esm:000000C1` / `KYWD` / `SplineLink`, with matching target/active/focused/tree-selection readback.
- Phase 11 negative cases passed for missing record (`record_not_found`) and non-empty child path (`invalid_request`).
- Phase 11 non-mutation proof passed: dirty-state readback stayed `dirty:false`, `dirtyFiles:[]`, and `unsavedChangeCount:0` before and after navigation.
- Phase 11 blocker/modal probing is honestly `NOT-COVERED`: deterministic modal/progress GUI setup was not available under the task constraints, Windows MCP was forbidden/unavailable for this task, and no product-only hooks were added.
- The current accepted Phase 11 evidence is `.opencode/artifacts/phase11-navigate-to-record/summary/semantic-acceptance-phase11.md` plus the latest run root `.opencode/artifacts/phase11-navigate-to-record/runs/task3-reviewfix-20260513-151640/`.
- Phase 12 locally lifts xEdit's hardcoded refusal to edit Starfield `.esp` files for the plain (unflagged) case, so authors can edit `.esp` in xEdit without round-tripping through Plugin Bridge. Concretely the patch removes the `(flModule.miExtension = meESP) and not wbRedPill` early-False clause in `TwbFile.GetIsEditable` at `Core/wbImplementation.pas:4241-4259`, restores a plain `<new file>.esp` template under SF1 mode at `Core/wbLoadOrder.pas:561-606`, and advertises `supports.filesCreate.starfieldEspWrite = { mode:"plain-only", masterPolicy:"full-only", allowMasterAdd:true }` in `system.capabilities` at `xEdit/xeAutomationCommandsSystem.pas:156-176` when `wbIsStarfield` is true. ESL / Update flag save guards, the SF1 "Only Full modules can be added as masters" `TwbFile.AddMaster` rule, the `fsIsGameMaster`/`fsIsHardcoded`/`fsIsOfficial` read-only protection, `wbStarfieldIsABugInfestedHellhole`, and `wbRedPill` are all left intact - the unlock is intentionally narrow to plain `.esp`, not to flagged ESP combinations or ESL/Update masters.
- Phase 12 fresh LiteDebug builds were taken for both targets and synced to the Starfield MO2 tool path: `Building xEdit.dproj (LiteDebug, Win64)` Success at `D:\Starfield MO2\tools\xEdit\xEdit64.exe` and `D:\Starfield MO2\tools\xEdit\SF1Edit64.exe`, and `Building xEdit.dproj (LiteDebug, Win32)` Success at `D:\Starfield MO2\tools\xEdit\xEdit.exe`. Build evidence at `.opencode/artifacts/phase12-starfield-esp-write/build-win64/xEdit-litedebug-win64.err` and `.opencode/artifacts/phase12-starfield-esp-write/build-win32/xEdit-litedebug-win32.err`.
- Phase 12 runtime semantic E2E was run against the real Steam Starfield install (`D:\SteamLibrary\steamapps\common\Starfield\Data`) in standalone `-SF1 -automation-serve -IKnowWhatImDoing` mode with an agent-owned plugins.txt, in-memory only (no `session.save`) so the protected Stock Game Data tree was not written to. The accepted run is `.opencode/artifacts/phase12-starfield-esp-write/runs/run-20260607-014616/` with `status=passed`, `caseCount=13`, `passed=13`, `failed=0`. The 13 cases verify: ping, describe (`gameMode:"gmSF1"`), `starfieldEspWrite` capability advertised, baseline files.list, plain `.esp` create with `isEditable:true`, auto-`AddMasters(['Starfield.esm'])` after create, `records.list` on `ShatteredSpace.esm`, `files.add_required_masters` adding `ShatteredSpace.esm` as a non-Starfield.esm Full master, `records.list` + `add_required_masters` for `BlueprintShips-Starfield.esm` (Blueprint flag is orthogonal to Full so ModuleType stays mtFull and the "Only Full" rule passes), final `get_masters` showing all three Full masters present, header readback confirming flags stay plain, and dirty-state readback showing the test plugin as dirty.
- Phase 12 semantic acceptance note is `.opencode/artifacts/phase12-starfield-esp-write/summary/semantic-acceptance-phase12.md`. The probe and plugins.txt live at `.opencode/artifacts/phase12-starfield-esp-write/runs/run-phase12-verification.ps1` and `.opencode/artifacts/phase12-starfield-esp-write/runs/phase12-plugins.txt`.
- Newly known from Phase 12 for later phases: Starfield Steam vanilla `Data` ships exactly three Full `.esm` files (`Starfield.esm`, `ShatteredSpace.esm`, `BlueprintShips-Starfield.esm`); Constellation, OldMars, and SFBGS004/007/008 are Light, SFBGS003/006 are Medium. `files.add_required_masters` takes a `source` locator object (`{file, formId, path}`) pointing at a record in the master, not a flat array of master names. First-time SF1 cache build inside `xEdit -SF1 -automation-serve` runs ~7-9 minutes against the 1.4 GB `Starfield.esm`, so SF1 verification harnesses need a >=600 s daemon-startup timeout. The automation daemon refuses mutating commands without `-IKnowWhatImDoing`. The SF1 "Only Full modules" master-add rule (`TwbFile.AddMaster` at `wbImplementation.pas:2479-2486`) correctly refuses Light or Medium masters even after the Phase 12 unlock; that refusal is intentional and documented as a known-good safety net, not a candidate for further loosening. A plain `.esp` save-to-disk run for SF1 still needs an MO2-VFS-backed harness so writes redirect away from the Steam Starfield Data tree; that is a separate follow-up phase, not Phase 12.
- Phase 13 locally adds 9 new `elements.*` verbs (`set_native_value`, `set_to_default`, `clear`, `move_up`, `move_down`, `next_member`, `previous_member`, `edit_capabilities`, `assign_templates`) and extends 2 existing verbs (`add_child` + `copy_child_to`) with optional placement/template/master-add args. Contract bumps `0.10 -> 0.11` via additive `supports.elementsMutation` block; frozen `supports.jobs.kinds` from Phase 6E unchanged. All mutation gates extend `xEdit/xeAutomationMutationPolicy.pas` with 7 new `Require*Target` procedures and 2 pure boolean helpers, all deferring to native xEdit predicates. Persistence stays behind explicit `session.save`. Consent gate (`wbIKnowWhatImDoing`) preserved.
- Phase 13 fresh LiteDebug builds were taken for both targets: `Build/xEdit.exe` (Win32) and `Build/xEdit64.exe` (Win64), both `Success`. Evidence is `.opencode/artifacts/phase13-elements-mutation/build-t10/`. Runtime semantic E2E ran against the MO2-managed `OpenCodeXEdit` tool target via `ModOrganizer.exe --multiple -p Default run -e OpenCodeVfsLauncher`. Final accepted run is `.opencode/artifacts/phase13-elements-mutation/runs/run-t10-accepted/` with `status:"passed"`, `caseCount:31`, `passed:26`, `failed:0`, `notCovered:5`, `harnessFailure:null`. Pre-shutdown `session.save` persisted `opencodetest.esp` via `savedFilesPendingShutdown`. Semantic acceptance note: `.opencode/artifacts/phase13-elements-mutation/summary/semantic-acceptance-phase13.md`.
- Newly known from Phase 13 for later phases: canonical bds command on this machine is `bds.exe -b xEdit.dproj` with NO MSBuild `/target:`/`/p:` flags (those trigger Enterprise license-required paths on Community Edition); dproj `<Platform Condition>` default chooses Win32 vs Win64, so symmetric release builds require editing the dproj twice. MO2 v2.5 enforces a global single-instance lock via hardcoded `QSharedMemory` key (`mo-43d1a3ad-eeb0-4818-97c9-eda5216c29b5` per `ModOrganizer2/src/multiprocess.cpp:7`); pass `--multiple` before the `run` subcommand to coexist with another MO2 instance (e.g. Starfield MO2). Automation harnesses must call explicit `session.save { files:[...] }` before daemon shutdown to avoid xEdit's GUI "Save changed files" dialog interrupting the run. `records.apply_filter` takes plural `files`/`signatures` args, not singular (design doc gap). Vanilla FO4 fixtures do not expose positive paths for `elements.set_to_default` / `clear` / `move_*` / `*_member` — gates validate negatively only; positive coverage deferred to future synthetic fixtures or a Skyrim/SSE harness. NV-003 design expected `read_only_target` but `Fallout4.esm` actually fires `mutation_not_allowed` first (protected-master check ordering); spec doc gap, not impl bug.
- Later phases inherit: `supports.elementsMutation` is a frozen additive surface alongside `supports.jobs.kinds`; any regression to structural ops requires a contract bump. Use `--multiple` whenever a second MO2 instance may be open. Call `session.save` explicitly before any `Stop-Process` on the daemon. The Phase 13 acceptance matrix (31 cases) is the template for future element-scope expansions.
- The BB-84C daemon issue follow-up is now locally implemented and semantically accepted: serve-mode partial/incomplete named-pipe writes reset only the current connection, normal GUI unsaved-change reminders are suppressed during automation daemon/call mode, and headless `scripts.run` exposes daemon-safe loaded-file globals (`FileCount`, `FileByIndex`, `FileByName`, `FileByLoadOrder`, `FileByLoadOrderFileID`) while preserving `frmMain` / `frmFileSelect` denial.
- Newly known from the BB-84C runtime runs: repeated `StreamReader.ReadToEnd` bridge calls plus an early-close client no longer stop the daemon; an in-memory dirty `files.create` probe leaves `session.get_gui_snapshot` blocker-free after the timer window; all five file globals resolve against real FO4 loaded data; bare `try...except` and `try...finally` work, while typed `on E: Exception do` still parse-fails in JvInterpreter and remains a characterized limitation rather than a patched behavior.
- BB-84C accepted evidence is `.opencode/artifacts/bb84c-daemon-issue-fix/build-final/xEdit-litedebug-win32.err`, runtime run `.opencode/artifacts/bb84c-daemon-issue-fix/runs/runtime-20260526/summary/runtime-summary.json`, supplemental globals run `.opencode/artifacts/bb84c-daemon-issue-fix/runs/runtime-20260526-fileglobals/summary/all-file-globals-summary.json`, and semantic review output in the current session. Later script-compatibility phases should treat `IntToStr` / `VarToStr` ledger denial, function-only script wrapping, and typed `Exception` handler syntax as follow-up compatibility gaps, not as blockers for this daemon-hardening fix.
- The `v4.1.6-automation.2` emergency release replacement removes the artificial `records.create` KYWD/MISC signature allow-list, avoids adding any CLI-side signature shape/length gate before xEdit's native `Add` path, advertises the widened native-create policy through `system.capabilities`, and adds Starfield `medium` header-flag exposure to `files.create`, `files.set_header_flags`, file-hygiene capabilities, and header readbacks.
- Newly known from the release-replacement audit: the earlier Phase 5/6 "arbitrary record signatures" and "medium plugin" deferrals are superseded for these thin CLI seams; future work should not reintroduce protocol-side record-signature allow-lists, and should treat `medium` as a named xEdit header flag alongside `esm`/`esl` while still preserving protected-target guards and the `Agent/` script write namespace.
- `v4.1.6-automation.2` replacement evidence is `.opencode/artifacts/r2-release-hotfix/green/assert-hotfix-source-green-after-review.log`, LiteDebug build logs `.opencode/artifacts/r2-release-hotfix/build-win32-after-review/xEdit.err` and `.opencode/artifacts/r2-release-hotfix/build-win64-after-review/xEdit.err`, MO2-backed runtime summary `.opencode/artifacts/r2-release-hotfix/runtime/summary/r2-hotfix-runtime-summary.json`, and the post-review semantic audit in the current session. Starfield `medium:true` remains source/build verified but not runtime-proven on the FO4-only harness.
- This status is local xEdit-side delivery only; it does not imply upstream merge, a git commit, or a reopened separate `1.x` boundary.

Historical progression notes from earlier phases remain below for traceability.

The local branch has completed the first automation skeleton milestone and the first daemon-based read-only automation round, with later local Phase 3 mutation work and early Phase 4 foundation work now also in place:

- Phase 0 architecture guardrails are documented.
- Phase 1 CLI automation skeleton is implemented locally in xEdit itself.
- The current local implementation includes:
  - automation session/mode detection
  - a central command registry
  - the first `system.*` command group
  - a thin pre-UI CLI host
  - structured success/error envelopes
  - a follow-up comment pass on lifecycle, validation, registry, and protocol seams for upstream review readability
- Runtime smoke verification has covered:
  - `system.describe`
  - `unknown_command`
  - `invalid_request`
  - partial-flag fail-fast behavior

- Phase 2 has now pivoted away from the superseded one-shot loaded-data model and into a load-once daemon/session model.
- The current local implementation now includes:
  - `automation-serve` mode
  - `automation-call` mode
  - PID-addressed named-pipe transport
  - loaded-session registration for `files.*`, `records.*`, and `elements.*`
  - object/locator traversal over the loaded daemon session
- Fresh daemon/runtime verification has covered:
  - `system.describe`
  - `files.list`
  - `files.get`
  - `records.get`
  - `elements.get`
  - `elements.children`
  - negative `file_not_found`
  - negative empty request file -> `invalid_request`
  - negative conflicting automation modes -> `invalid_request`

The current local follow-on workstream is capability enrichment on top of the completed Phase 3 mutation/save foundation and the initial Phase 4 groundwork. The CLI surface is still too narrow for many high-frequency xEdit tasks.

Local progress note for the current round:

- Loaded-data automation now runs on a serve/call daemon/session model instead of the superseded one-shot stateless CLI path.
- The CLI host keeps the original lightweight one-shot path for `system.*`, but all loaded-data commands now execute against the already-loaded xEdit session.
- `files.*`, `records.*`, and `elements.*` now share a stable locator/object/relations model over the loaded session.
- The shared record/element lookup seam is neutral instead of making one command group depend on another.
- File summaries now use loaded `IwbFile` data and explicitly exclude the hardcoded game executable from the file/plugin slice.
- The daemon/client transport now includes:
  - PID-derived pipe naming
  - client retry around normal pipe-open races
  - fail-fast handling for empty request files
  - explicit rejection of conflicting automation modes
  - recovery from `ERROR_NO_DATA` / broken-pipe style disconnects without killing the daemon session
- This machine now has a documented local verification path:
  - background `Start-Process ... bds.exe -b ...`
  - recurring Community Edition EULA reminder may need GUI dismissal
  - `LiteDebug` is the trustworthy local build configuration
  - runtime verification must use the MO2 Fallout 4 harness; for this Phase 6 workstream, the canonical xEdit target is `D:\awesome-bgs-mod-master\.artifacts\mo2\Stock Game\Fallout 4\Tools\OpenCodeXEdit\xEdit.exe`, and syncing the fresh LiteDebug build into that MO2-managed tool path is explicitly allowed
  - the Stock Game prohibition is specifically against mutating `D:\awesome-bgs-mod-master\.artifacts\mo2\Stock Game\Fallout 4\Data`; `D:\TES5Edit-contrib\Build\xEdit.exe` is not an acceptable runtime target for this FO4 MO2-backed Phase 6 verification path
  - there are two valid MO2 entrypoints for xEdit automation on this machine:
    - the fixed configured executable `OpenCode xEdit Automation Serve`
    - the programmable MO2 bootstrap path `ModOrganizer.exe -p Default run -e OpenCodeVfsLauncher -a "..."`
  - the drift to avoid is bypassing MO2 and invoking `mo2-vfs-launcher.ps1/cmd` directly from the host shell while assuming it activates the same VFS/profile state
- Phase 3 source work is now in place locally and runtime-verified against the dedicated audit plugin `opencodetest.esp` inside the MO2 `Default` profile for:
  - `session.get_dirty_state`
  - `elements.set_value`
  - `elements.add_child`
  - `elements.remove_child`
  - `elements.copy_child_to`
  - `session.save`
  - rejection of writes to `Fallout4.esm`
  - explicit `session.save` result-state distinction between `saved_now` and `save_pending_shutdown`
- Phase 4 foundation work is now in place locally with capability-coverage framing from the Task 1 research ledgers under `docs/notes/`.
- The current Phase 4 local implementation includes:
  - `session.get_gui_snapshot` as a blocker-only post-pipe probe with `hasBlockers`, `blockers`, and `blockerCount`
  - non-main-window filtering that excludes VCL infrastructure windows such as `TApplication`
  - `system.capabilities` with sorted command enumeration and daemon-surface verification
  - `records.list` with required `file`, optional `signature`, shallow locator-bearing results, and a bounded internal cap of 100 summaries per call
  - `records.list` now reports truthful `truncated` metadata when the bounded cap clips enumeration
  - `records.get` read-side lookup that now treats public `formId` as load-order-first, while still accepting older file-local FormIDs as a temporary compatibility path during the addressing transition
  - `records.get` now resolves emitted locator FormIDs through the public file-level load-order seam first and only falls back to file-local lookup for temporary local compatibility
  - `records.find_by_form_id` as an exact-only, shallow, bounded identity lookup over the public load-order-first FormID surface, returning concrete hits plus compact `masterOrSelf` and `winningOverride` facts
  - `records.find_by_editor_id` as an exact-only, shallow, bounded EditorID identity lookup that accepts an optional narrowing `signature` and intentionally does not add top-level winner collapse
  - `records.apply_filter` as the first bounded glob-driven discovery surface over explicit file scopes, including `*`, `?`, and contains-style `*text*` matching
  - `records.base_record` as a shallow root-record ancestry hop for downstream compare/navigation workflows
  - `records.references` and `records.referenced_by` as bounded unique relationship reports over shallow root-record hits
  - `xeAutomationConflictSnapshot.pas` as a protocol-neutral helper that computes stable root/child conflict snapshots from xEdit's aligned comparison rows without exposing raw view-node flags
  - `records.conflict_status` as a root conflict snapshot that lists only conflicted immediate children plus participant metadata
  - `elements.conflict_status` as the explicit child drill-down conflict endpoint over the same snapshot helper
  - `elements.required_masters` as a locator-based required-master report for both root (`path:""`) and child element scopes, with deduplicated load-order-sorted masters that exclude the target file itself
- Fresh local verification for this tranche has covered:
  - MO2-backed no-blocker GREEN for `session.get_gui_snapshot` when only the main xEdit window is present
  - daemon-surface GREEN for `system.capabilities`
  - canonical GREEN for `records.list`
  - canonical GREEN for `records.get` using both a round-tripped load-order locator FormID and the temporary local-form compatibility input for `opencodetest.esp`
  - canonical RED then GREEN for `records.find_by_form_id`, including the miss case, the optional `file` branch for `opencodetest.esp`, and a winning-override round-trip back through `records.get`
  - canonical RED then GREEN for `records.find_by_editor_id`, including exact-match GREEN, signature-free GREEN, lowercase-signature GREEN, exact-only prefix miss, and malformed-signature rejection
  - canonical GREEN for `records.apply_filter`, including `*`, `?`, and contains-style `*text*` glob semantics over `opencodetest.esp`
  - canonical GREEN for `records.base_record`
  - canonical GREEN for bounded unique `records.references` and `records.referenced_by` hits
  - canonical GREEN for `records.conflict_status` and `elements.conflict_status`, including participant blocks plus only conflicted immediate children
  - canonical GREEN for `elements.required_masters` at both the record root and a child locator path
  - supplemental Phase 4 closeout hardening GREEN with 26 runtime cases against the existing MO2-launched daemon, covering the previously light `records.apply_filter` predicates (`fullNamePattern`, base-record predicates, booleans, and conflict enums), positive non-null `records.base_record`, truncation branches for relationship/conflict reports, and structured invalid-request boundaries
  - negative `records.list` verification for invalid inputs
  - preserved RED `unknown_command` artifacts for the two new search commands, while the earlier `records.get` addressing RED was only observed and documented rather than preserved in this task artifact set
- Local startup-hardening follow-up is now documented more precisely for automation serve:
  - stale reference-cache confirmation no longer blocks `automation-serve` startup before the daemon pipe exists
  - serve mode already suppressed the first-run architecture warning and developer message before this tranche; those are part of the existing automation path, not newly added Phase 4 features
  - the startup behavior should be read as pre-pipe startup suppression/hardening versus post-pipe session GUI blockers, so `session.get_gui_snapshot` is understood as the latter only
- The local MO2 harness note is now sharper:
  - valid entrypoints are the fixed configured executable `OpenCode xEdit Automation Serve` and the MO2 bootstrap path `ModOrganizer.exe -p Default run -e OpenCodeVfsLauncher -a "..."`
  - the drift to avoid is direct host-shell invocation of `mo2-vfs-launcher.ps1/cmd`
  - `D:\awesome-bgs-mod-master\.artifacts\mo2\Stock Game\Fallout 4\Data\...` is no longer acceptable as disposable workspace state; future local runtime work must not write game Data there
  - if an agent believes it needs to change game-local Data files, it must package those changes as a dedicated MO2 mod under `D:\awesome-bgs-mod-master\.artifacts\mo2\mods\<mod-name>\...` and let MO2 VFS project them into runtime instead of mutating the game Data tree directly
- Phase 6A serve-startup follow-up has now completed the explicit-module and programmable-wrapper implementation attempt:
  - `xamServe` in normal edit mode now consumes an explicit positional module before load activation and records SimulateLoad exceptions through the normal log instead of silently swallowing them
  - the local MO2 harness now uses `OpenCodeVfsLauncher` with a no-spaces wrapper target that writes the actual xEdit child PID and launches with `-FO4`, `-automation-serve`, and the profile `plugins.txt`; the earlier positional `Fallout4.esm` argument was removed after tracing it to xEdit's real-file positional module validation path
  - the local harness now has a true pre-pipe GUI blocker probe and no longer degrades modal startup failures into blind readiness timeouts; it captured the prior xEdit-owned `#32770` OK dialog, and after removing the positional module the GUI blocker disappeared from the startup-only rerun
  - a VFS probe through the programmable wrapper path showed `CraftingTools.esp` and profile `plugins.txt` visible, but `Fallout4.esm` not visible under the Stock Game `Data` path; that explains why wrapper-launched headless autoload resolved no modules
  - historical/superseded: an earlier diagnostic physically mirrored official FO4 masters into the Stock Game `Data` directory and then switched `run-phase6A-verification.ps1` back to the programmable `OpenCodeVfsLauncher` route for PID/profile control; this is no longer an acceptable harness direction under the no-Stock-Game-Data rule, and future debugging must use the MO2-managed OpenCodeXEdit tool target plus MO2 overlay/overwrite state instead of Stock Game Data writes
  - restored after review and later tightened: the current harness targets the MO2-managed `D:\awesome-bgs-mod-master\.artifacts\mo2\Stock Game\Fallout 4\Tools\OpenCodeXEdit\xEdit.exe` for daemon and call-mode execution, and fresh LiteDebug builds may be synced into that tool path so the MO2-configured OpenCodeXEdit target stays current; all fixture/proof writes still go to MO2 `overwrite`, and no `Stock Game\Fallout 4\Data` copy/sync/delete step is allowed
  - historical/superseded by the accepted 6A baseline: the direct-bootstrap startup-only rerun (`run-phase6A-verification.ps1 -StartupTimeoutSeconds 120`) did not restore named-pipe readiness; summary generated at `2026-05-01T23:20:38.0858558Z` reported `status=failed`, `failed=1`, and `harnessFailure=Automation daemon was not ready before timeout...`; this remains useful diagnostic history but is no longer the current Phase 6A status
  - historical/superseded by the accepted 6A baseline: a serve-only startup diagnostic recorded the pre-`SimulateLoad` module state before the generic pre-pipe fail-fast line; that startup-only rerun showed `wbModulesByLoadOrder` returning `total=4`, `valid=4`, `active=0`, `taggedForPluginMode=0`, and `missingMasters=3`, with `Fallout4.esm` and `DLCRobot.esm` absent while `ArmorKeywords.esm`, `CraftingTools.esp`, and `RaiderOverhaul.esp` were present/valid but inactive and missing masters
  - historical/superseded by the accepted 6A baseline: the diagnostic follow-up at that time focused on why the direct-bootstrap serve process saw mod plugins without official game/DLC masters and without active/tagged module flags; do not reuse that stale red as the current 6A baseline now that the final accepted harness is green
  - the Phase 6A local harness now keeps the no-Stock-Game-Data write/delete rule while allowing the fresh build to be synced into, and then executed from, the existing MO2-managed xEdit tool path; it records concrete readiness-timeout evidence instead of `OrderedDictionary` strings and maps mutable proof/fixture disk evidence to MO2 `overwrite`, not real game Data
  - the latest harness-only correction removes indefinite `Start-Process -Wait` blocking from `Invoke-XEditAutomationCall`; call-mode xEdit clients now honor their per-call timeout, get killed if wedged, and report the request/response/stdout/stderr artifact paths so a startup-only rerun can return through harness summary/error handling instead of relying on the outer shell timeout
  - the next bounded harness step replaced the earlier dedicated-overlay expectation with a real MO2 `overwrite` proof: `files.create` plus `session.save` for `VT_Phase6A_OverlayProof.esp` must create `D:\awesome-bgs-mod-master\.artifacts\mo2\overwrite\VT_Phase6A_OverlayProof.esp` and must not create `D:\awesome-bgs-mod-master\.artifacts\mo2\Stock Game\Fallout 4\Data\VT_Phase6A_OverlayProof.esp`
  - historical/superseded by the accepted 6A baseline: the earlier full harness reached daemon readiness, passed the MO2 `overwrite` proof, and proceeded through mutation-capable semantic rows; `phase6A-verification-summary.json` generated at `2026-05-02T04:49:44.1926358Z` reported `status=failed`, `failed=1`, `harnessFailure=null`, with all rows through `SAVE-000` passing and only `SAVE-001` fresh reload persistence failing because the restarted daemon returned `file_not_found` for `VT_Phase6A_HeaderFlags.esp` even though `disk-evidence/header-after-save.json` proved it existed in MO2 `overwrite`
  - SAVE-001 is now corrected in the local harness by generating an artifact-local restart-only plugins list from the current MO2 `Default` profile and activating the saved Phase 6A fixtures in that generated copy only; the fresh restart passes that `.txt` list as xEdit's startup plugins file without mutating Stock Game, `%LOCALAPPDATA%\Fallout4\Plugins.txt`, or the real MO2 profile `plugins.txt`
  - fresh full harness verification generated at `2026-05-02T06:45:16.7086871Z` reports `status=passed`, `failed=0`, `harnessFailure=null`; `BATCH-002` now creates and saves a local `.esm` unused-master baseline for `VT_Phase6A_BatchB.esp`, proves apply-mode `clean_masters` removes that master in memory (`changed=true`, `applied=1`, `dirtyFiles=[VT_Phase6A_BatchB.esp]`, `requiresSave=true`), and confirms disk evidence stays unchanged until explicit `session.save`
- Phase 6B-E Task 1 has frozen the accepted Phase 6A artifact set as the dependency floor for the combined execution round:
  - prerequisite evidence is the Phase 6A summary at `.opencode/artifacts/phase6A-job-file-hygiene/phase6A-verification-summary.json` plus the semantic acceptance note at `.opencode/artifacts/phase6A-job-file-hygiene/semantic-acceptance-phase6A.md`
  - the confirmed entry facts are `status=passed`, `failed=0`, and `harnessFailure=null`
  - 6B, 6C, 6D, and 6E will be implemented in one combined local round, but each slice still has its own artifact root and must earn independent semantic acceptance before its claims are treated as complete
  - slice-local semantic matrix skeletons now live under `.opencode/artifacts/phase6B-esl-compact/`, `.opencode/artifacts/phase6C-validation-findings/`, `.opencode/artifacts/phase6D-cleaning-jobs/`, and `.opencode/artifacts/phase6E-contract-hardening/`
- Phase 6B Task 3 compact/apply source work is now in place locally:
  - `plugin.formids.compact_for_esl` plans/applies in-memory FormID remaps with dry-run defaulting, paged remap findings, dirty-file summaries, and no implicit ESL flag or disk save
  - `plugin.esl.apply` plans/applies the ESL header flag with dry-run defaulting, eligibility checks, old/new header-flag reporting, dirty-file summaries, and no implicit save
  - Task 3 review remediation made `allowAfterCompact:true` a real apply path: when analysis finds only compaction-required risk, apply can plan/apply the same FormID remaps before setting the ESL flag while still preserving the explicit `session.save` boundary
  - Task 3 review remediation aligned analysis capacity with the compaction planner's actual usable ObjectID range (`$800..$FFF` unless hardcoded range use is allowed) and now reports `lightObjectIdLowest`, `lightObjectIdLimit`, and `lightObjectIdCapacity`
  - Compact/apply remediation now preflights editable override/referrer files before any FormID assignment and reports every file whose FormID/reference state is actually dirtied, so `dirtyFiles` is not limited to the original target when xEdit's reference sweep touches non-target files
  - Final Task 3 referrer-safety remediation now builds the loaded reference graph before compact/apply remaps, reports `non_editable_referrer` findings during dry-run, and fails apply-mode compact or `allowAfterCompact:true` ESL apply before FormID/header mutation when a true non-editable referrer would otherwise remain stale; a follow-up narrowing corrected the local over-broad guard so editable external referrers are updated by the reference sweep and reported in `dirtyFiles` instead of being treated as stale-risk solely because they live in another plugin
  - capabilities now advertise `plugin.formids.compact_for_esl` and `plugin.esl.apply` only after the job handlers are registered
  - Task 3 RED is preserved at `.opencode/artifacts/phase6B-esl-compact/phase6B-task3-red-summary.json`, showing both kinds returned `unknown_job_kind` and were not advertised in the pre-Task-3 binary
  - Task 3 remediation RED is preserved in `.opencode/artifacts/phase6B-esl-compact/responses/phase6B-task3-esl-apply-default-dryrun-poll-01.response.json` from the pre-remediation binary, where omitted dry-run was normalized but `allowAfterCompact:true` still failed with `eligibility_failed`
  - Task 3 GREEN is preserved at `.opencode/artifacts/phase6B-esl-compact/phase6B-task3-green-summary.json`, with `status=passed` and positive checks for non-mutating analysis, omitted/default dry-run for compact and apply, `allowAfterCompact` remap planning, compact dry-run, editable external referrer dry-run/apply behavior, dirty-file reporting for both the compact target and editable external referrer, compact apply, ESL apply, no disk write before `session.save`, explicit save, fresh reload, and post-reload locator readback; the old local "blocked" fixture is now known to be editable under xEdit (`blockedReferrerFileIsNonEditable=false`), so it no longer proves the true non-editable stale-risk path after the guard was narrowed
- Phase 6C Task 4 validation source and live verification are now in place locally:
  - `validation.check_for_errors`, `validation.check_for_itm`, and `validation.check_for_deleted_refs` register as non-mutating validation-only job kinds with paged machine-readable findings shaped as severity/code/message/target/source/action
  - omitted or explicit apply-like validation starts are normalized to dry-run/validation-only semantics, and malformed `target.files` fails at `jobs.start` without poisoning the daemon for later requests
  - the live MO2-backed harness is `.opencode/artifacts/phase6C-validation-findings/run-phase6C-verification.ps1`; latest summary `.opencode/artifacts/phase6C-validation-findings/phase6C-verification-summary.json` reports `status=passed`, `failed=0`, and `harnessFailure=null`
  - runtime evidence now proves capabilities advertisement after implementation, all three validation kinds reaching terminal success, machine-readable findings with stable codes for every validation kind, positive `itm_record` detection for a real deep-copied override fixture, deleted-reference findings paged through `jobs.findings`, locator readback for finding targets, unchanged dirty-state before/after validation, a saved clean-file validation run that remains clean before/after, and malformed-target recovery
  - Task 4 spec-review follow-up found the original RED pass preserved requests and source-state notes but not actual pre-implementation response JSON; `.opencode/artifacts/phase6C-validation-findings/red-evidence.md` now records that limitation explicitly so later phases do not treat request-only RED as equivalent to response-envelope RED
  - Task 4 remediation captured a real semantic RED after tightening the harness: the intended ITM fixture returned `no_itm_records_found`; the final GREEN finding page now reports `code:"itm_record"` for the deep-copied `KYWD` override fixture
  - new implementation fact for later phases: fresh automation-created overrides may not have GUI conflict state populated, and xEdit's native `ContentEquals` refuses modified records; validation seams cannot depend solely on `ConflictThis`, and ITM proof for fresh overrides needs a master-side comparison plus a non-mutating structured fallback that ignores file-local header metadata
  - new harness fact for later phases: positive ITM setup must save the source master and use `records.copy_into deepCopy:true`; `deepCopy:false` creates a shallow override shell and is not semantic ITM evidence
- Phase 6D Task 5 cleaning source work and live MO2 semantic verification are now in place locally:
  - `cleaning.quick_clean`, `cleaning.quick_auto_clean`, and `cleaning.sort_and_clean_masters` register only after the new cleaning unit is linked, keeping capability advertising registry-derived and implementation-gated
  - the cleaning jobs default omitted `dryRun` to `true`, report planned/applied/skipped counts, page stable findings through `jobs.findings`, dirty only in-memory loaded files, and leave persistence to explicit `session.save`
  - non-GUI cleaning seams were extracted in `xeMainForm.pas` for ITM removal, deleted-reference undelete/disable, and sort+clean masters without selection, progress UI, save, or auto-exit behavior
  - Task 5 review remediation now explicitly lists the cleaning command unit in `xEdit.dpr` and `xEdit.dproj`, preflights all apply-mode cleaning targets before mutating any of them, adds exact dirty-set checks to the live harness, reports sort and clean-master operation counts separately, and gates deleted-reference mutation on per-record editability
  - new implementation constraint for later 6D/6E verification: the automation ITM seam must use the same master-side content comparison discovered in 6C because GUI conflict state may be unavailable for freshly built fixtures
  - current evidence: RED notes are preserved at `.opencode/artifacts/phase6D-cleaning-jobs/red-missing-cleaning-kinds.md`; the local `bds.exe -b` rebuild log `.opencode/artifacts/phase6D-cleaning-jobs/bds-lite-debug-build-rerun-xedit.err` shows `Building xEdit.dproj (LiteDebug, Win32)` and `Success`; the live MO2-backed summary `.opencode/artifacts/phase6D-cleaning-jobs/phase6D-verification-summary.json` reports `status=passed`, `failed=0`, and `harnessFailure=null`
  - runtime evidence now proves all three cleaning kinds are advertised only after implementation, dry-runs plan without mutation, apply mode mutates expected ITM/deleted-ref/master state, dirty readback names the changed files, `session.save` plus graceful shutdown persists changes, reload readback confirms persistence, and protected `Fallout4.esm` cleaning fails non-mutatingly
  - review-remediation RED/GREEN evidence: the strengthened harness first failed on the multi-target protected apply case because the writable target had already lost its ITM before the later `Fallout4.esm` failure; the final MO2-backed rerun generated at `2026-05-04T10:14:49-04:00` passed with `status=passed`, `failed=0`, and `harnessFailure=null`, including exact dirty-set assertions and per-operation master-clean counts
  - new implementation fact for later phases: the cleaning ITM seam must share the same header-skipping element comparison discovered in validation because stream/native `ContentEquals` is insufficient for freshly saved/reloaded automation fixtures; the Task 5 live harness caught this as a semantic RED before the final GREEN rerun
  - localization save regression follow-up now restores the GUI/shared temp-save seam for `TwbLocalizationFile` saves: existing localization files are written to a `.save...` temp path, then direct-renamed to the real path or queued in `FilesToRename` for shutdown before `Modified` is cleared; source-state RED/GREEN evidence is preserved under `.opencode/artifacts/localization-save-regression/`
- Phase 6E Task 6 contract hardening is now in place locally and has been included in the Task 7 final local-only closeout:
  - `system.capabilities` now freezes the final accepted 6A/6B/6C/6D `supports.jobs.kinds` membership and order: `files.hygiene.batch`, the three ESL/compact jobs, the three validation jobs, and the three cleaning jobs
  - the error/finding taxonomy now includes stable cleaning finding constants alongside the existing job, ESL eligibility, unsafe-operation, and validation values, so examples/wrappers can branch on codes instead of message text
  - local wrapper examples are preserved under `.opencode/artifacts/phase6E-contract-hardening/examples/` for MO2 `OpenCodeVfsLauncher` bootstrap, `jobs.start/get/findings` polling, explicit `session.save`, and artifact-local restart plugin lists
  - slice acceptance roll-ups now exist for 6B/6C/6D plus a 6E contract summary/acceptance note; the final Task 7 closeout treats those roll-ups as accepted only alongside the fresh final slice reruns and combined semantic artifact review
  - downstream phases should keep capability claims additive but explicit; if new job kinds land after Phase 6E, update the frozen contract list and source check together rather than falling back to dictionary order
- Phase 6B Task 7 final-slice rerun harness gap is corrected locally:
  - the historical Task 2 `run-phase6B-green-probe.ps1` remains unchanged and still preserves the original pre-Task-3 expectation that compact/apply kinds were not advertised
  - the new final rerun entrypoint `.opencode/artifacts/phase6B-esl-compact/run-phase6B-verification.ps1` generates a final-only analyze probe from the accepted Task 2 logic, swaps only the obsolete non-advertisement capability assertion for the final 6B compact/apply advertisement expectation, then composes it with the accepted Task 3 compact/apply probe
  - fresh MO2-backed final 6B rerun generated `.opencode/artifacts/phase6B-esl-compact/phase6B-verification-summary.json` at `2026-05-04T11:38:09.5628999-04:00` with `status=passed`, `failed=0`, and `harnessFailure=null`; checks cover analyze eligibility/ineligible/protected semantics, non-mutating dirty state, paged findings, final capability advertisement, compact/apply mutation, ESL flagging, and save/reload persistence
- Phase 6B-E final local-only closeout is now complete:
  - 6B delivered ESL/compact analysis and mutation jobs with explicit dry-run/apply split, paged remap/risk findings, editable-referrer handling, non-editable-referrer fail-fast protection, dirty-file reporting, explicit `session.save`, and fresh reload readback
  - 6C delivered validation-only `validation.check_for_errors`, `validation.check_for_itm`, and `validation.check_for_deleted_refs` jobs with stable machine-readable findings, dry-run-only semantics, malformed-target recovery, dirty-state non-mutation proof, and positive ITM/deleted-reference evidence
  - 6D delivered cleaning jobs for quick clean, quick auto clean, and sort-and-clean-masters with dry-run planning, apply-mode mutation, exact dirty-set checks, protected-target non-mutation, explicit save, and fresh reload persistence
  - 6E delivered contract hardening by freezing the accepted Phase 6 job-kind list/order in `system.capabilities`, stabilizing finding/error code names for wrappers, and preserving local wrapper examples for MO2 bootstrap, job polling, explicit save, and artifact-local restart plugin lists
  - final LiteDebug build evidence is fresh in `xEdit.err`, and the final 6B, 6C, 6D, and 6E summaries are approved with the combined semantic artifact review approved
  - GUI-coupled seams extracted in this round include non-GUI ITM comparison, deleted-reference undelete/disable, sort/clean-masters, ESL header flagging, compact-for-ESL FormID remapping, header/master file hygiene, validation finding production, and localization temp-save behavior; these now have headless automation paths that avoid selection, progress UI, modal wizard flow, implicit save, and auto-exit coupling
  - intentionally deferred GUI-coupled work remains outside 6B-E: arbitrary dialog/button automation beyond the coarse `session.get_gui_snapshot` blocker probe, full Pascal script execution, broad query DSLs, and any workflow macro layer that would hide the atomic command/job boundary; historical notes about deferring medium-plugin support and arbitrary record-signature creation are superseded by the `v4.1.6-automation.2` release replacement's thin native-pass-through seams
  - later phases must not regress the atomic-job contract: omitted `dryRun` stays non-mutating, apply stays explicit, protected targets fail before mutation, dirty state is inspectable before save, persistence claims require `session.save` plus restart/readback evidence, and `system.capabilities.supports.jobs.kinds` remains explicit and implementation-gated
  - later phases must not regress the accepted MO2 runtime discipline: use a fresh LiteDebug build synced to the MO2-managed `OpenCodeXEdit` tool target, enter through MO2, keep mutable fixtures in MO2 `overwrite` or dedicated mod overlays, never treat Stock Game `Data` as scratch, and never use `D:\TES5Edit-contrib\Build\xEdit.exe` as the canonical FO4 runtime target
  - evidence lessons from the final round: stale artifact references must be corrected rather than carried forward, early RED response capture must be preserved when available and limitations called out when missing, canonical tool-target discipline matters as much as source correctness, and final acceptance must inspect semantic request/response/readback artifacts rather than relying on build success or harness summaries alone
- Phase 5 patch-building primitives are now implemented locally and runtime-verified through the MO2 Fallout 4 harness:
  - `files.create` for non-light `.esp`, `.esm`, `.esl`, and light-flagged `.esp` module creation
  - `files.add_required_masters` for explicit required-master addition with idempotent reporting
  - historical/superseded by the `v4.1.6-automation.2` release replacement: `records.create` originally shipped with a bounded `KYWD` and `MISC` allow-list; the current branch delegates record-signature support to xEdit's native `Add` path instead
  - `records.copy_into` for override, overwrite, deep override, deep overwrite, copy-as-new, and deep copy-as-new paths
  - `records.delete` for physical removal of writable patch-owned root records
  - `records.mark_deleted` for one-way native `IsDeleted` tombstoning
  - historical/superseded by the `v4.1.6-automation.2` release replacement: `system.capabilities` originally reported contract `0.5`, Phase 5 command names, create-file extensions/flags, and `records.create` signatures; current capabilities advertise `recordsCreate.signaturePolicy = native-xedit-add` and include `medium` among create/header flags
- Fresh Phase 5 semantic verification used a LiteDebug RAD build and an expanded 61-case MO2-backed harness, then the controller checked command responses against actual xEdit readback artifacts; the latest summary is `.opencode/artifacts/phase5-patch-building/phase5-verification-summary.json` with `status=passed`, `caseCount=61`, and `failed=0`.
- The semantic acceptance audit is preserved at `.opencode/artifacts/phase5-patch-building/semantic-acceptance-phase5.md`; it records the RED found during audit, the file-summary master-list fix, and the command-by-command intent/readback matrix.
- Phase 1-4 supplemental semantic follow-up is now rerun against a user-confirmed fresh LiteDebug binary and the MO2 harness:
  - parsed request envelopes now echo optional top-level `requestId` and `id` on success and parsed-request error responses, while malformed JSON remains uncorrelated
  - `READ-010` now tests true `records.base_record` semantics with a reference-style `REFR -> STAT` base-record result instead of confusing override lineage with base-record links
  - `ERR-008` now has a real stale-state conflict case using `records.mark_deleted expectedDeleted:false`, including before/after readbacks proving no further mutation
  - the harness now clears stale per-run JSON artifacts, waits for named-pipe readiness after MO2 daemon launches/restarts, and compares result payloads for non-mutating checks so request-correlation metadata cannot create false reds
  - latest summary is `.opencode/artifacts/phase1-4-semantic-e2e/phase1-4-verification-summary.json` with `status=passed`, `caseCount=52`, `failed=0`, and `notCovered=1`
  - the remaining not-covered case is `SES-005`: `session.save` can report a non-light fixture as pending shutdown, the file reloads, but the harness cannot prove the newly created record persists through the daemon restart
- Phase 6A Task 1 job-control scaffolding is now implemented locally without bumping the public contract beyond `0.5`:
  - `jobs.start`, `jobs.get`, `jobs.findings`, `jobs.cancel`, and `jobs.discard` are registered only on the loaded daemon path
  - daemon-local in-memory jobs are poll-driven from `jobs.get`, single-active-job bounded, and retain terminal history for later file-hygiene work
  - no Phase 6A job kind is advertised yet; unsupported starts return `unknown_job_kind` until Task 3 registers `files.hygiene.batch`
  - Task 1 spec-review follow-up flattened public job responses so `jobs.start/get/cancel/discard` return job fields directly under `result`, `jobs.findings` reports job identity beside page metadata, accepted job execution failures live under `failure` rather than transport `error`, and top-level `dryRun` is now retained for future job handlers
  - Task 1 code-quality follow-up made `jobs.findings` always serialize a stable empty `findings: []` page, emits the Int64 `sequence` through the JsonDataObjects long setter, and cleaned the touched `xEdit.dproj` whitespace
  - Fresh post-review LiteDebug build evidence is `.opencode/artifacts/phase6A-job-file-hygiene/bds-task1-after-quality-fix-litedebug.err.log` with `Building xEdit.dproj (LiteDebug, Win32)` and `Success`
  - Direct-daemon command-surface verification was rerun from that binary using colon-form `-automation-call-*` arguments; `.opencode/artifacts/phase6A-job-file-hygiene/task1-direct-daemon-after-quality-fix-summary.json` reports all Task 1 cases passed while `system.capabilities` remains `contractVersion:"0.5"` without `supports.jobs`
  - historical/superseded by final Phase 6A acceptance: the local MO2 launch regression was a Task 1 semantic-acceptance blocker at the time, but later 6A harness corrections restored MO2-backed semantic acceptance; do not treat this older blocker as current status
  - Follow-up build attempts that produced `Building xEdit.dproj (Debug, Win32)` remain explicitly invalid; no refreshed runtime GREEN artifacts should be inferred from those logs or binaries
- Phase 6A Task 2 file header/master hygiene command source is now in place locally without bumping the public contract beyond `0.5`:
  - `files.get_header` and `files.get_masters` expose synchronous direct header/master readbacks over the loaded daemon session
  - `files.set_header_flags`, `files.sort_masters`, and `files.clean_masters` reuse the shared protected-target mutation policy and leave persistence at the explicit `session.save` boundary
  - file-hygiene commands are registered in both the loaded daemon startup path and capability command-list path, but no `supports.fileHygiene` field is advertised yet
  - RED request artifacts are preserved under `.opencode/artifacts/phase6A-job-file-hygiene/requests/`; the current direct-daemon RED attempt could not reach a ready pipe and is recorded as `responses/task2-red-run-skipped.txt`
  - Task 2 code-quality follow-up restored `xEdit.dproj` to CRLF with semantic-only project changes, removed the accidental `xEdit.dpr` BOM, and made malformed `files.set_header_flags` flag requests return `invalid_request` before protected-target policy can mask them
  - Fresh post-review LiteDebug build evidence is `.opencode/artifacts/phase6A-job-file-hygiene/bds-task2-after-quality-fix-litedebug.err.log` with `Building xEdit.dproj (LiteDebug, Win32)` and `Success`
  - Direct-daemon smoke verification was rerun from that binary using colon-form `-automation-call-*` arguments; `.opencode/artifacts/phase6A-job-file-hygiene/task2-direct-daemon-after-quality-fix-summary.json` reports read/protected-error/invalid-request cases passed while `system.capabilities` remains `contractVersion:"0.5"` without `supports.fileHygiene` or `supports.jobs`
  - historical/superseded by final Phase 6A acceptance: positive file mutation fixtures, save/reload readbacks, and semantic acceptance were still blocked during this Task 2 snapshot and were not inferred from the direct-daemon smoke pass; the later accepted 6A baseline is the current status
- Phase 6A Task 3 source work is now in place locally for the first concrete job kind:
  - `files.hygiene.batch` is registered from the file-hygiene command unit with a per-kind `jobs.start` validator for `target.files`, `options.operations`, and omitted-`dryRun` defaulting to true
  - the job manager now supports optional per-kind start validators plus durable top-level `summary` and handler-populated `failure` data, while preserving unknown-kind checks before active-job conflicts
  - `jobs.get` can advance a queued file-hygiene batch by processing files in order, collecting stable per-file findings, and reporting partial apply-mode changes when a later target fails
  - `system.capabilities` now reports contract `0.6`, advertises the implemented job/file-hygiene metadata, and intentionally lists only the current `files.hygiene.batch` job kind
  - Task 3 RED is preserved at `requests/task3-start-batch-red.json` and `responses/task3-start-batch-red.response.json`, showing the prior `unknown_job_kind` response
  - Fresh LiteDebug build evidence is `.opencode/artifacts/phase6A-job-file-hygiene/bds-task3-initial-litedebug.err.log` with `Building xEdit.dproj (LiteDebug, Win32)` and `Success`; a stray root `xEdit.err` log from an implementer attempt was quarantined under `.opencode/artifacts/phase6A-job-file-hygiene/xEdit-task3-stray-root-build.err.log`
  - Direct-daemon lifecycle smoke was rerun from that binary using colon-form `-automation-call-*` arguments; `.opencode/artifacts/phase6A-job-file-hygiene/task3-direct-daemon-lifecycle-summary.json` reports capability 0.6, queued start, active conflict, unknown-kind precedence, known-kind validation precedence, cancel/discard, dry-run terminal execution, and findings paging cases passed
  - historical/superseded by final Phase 6A acceptance: MO2-backed positive fixture mutation, save/reload persistence, and semantic acceptance remained pending at this Task 3 snapshot and were not inferred from the direct-daemon smoke pass; the accepted 6A baseline now supplies the dependency floor for 6B-E

## What We Now Know

The work so far has turned several earlier unknowns into known constraints and known working seams:

- We now know xEdit can serve a useful automation request before the main form is created. The pre-UI path is no longer a hypothesis.
- We now know the repo-scoped transport boundary should stay at CLI. That reduces later ambiguity about whether this repo should grow an MCP server.
- We now know a central registry plus `initialization`-based command self-registration works as the first extension seam, as long as command-group units are explicitly linked into the project.
- We now know the first stable request/response shape is viable:
  - request: `command` + `args`
  - success: `ok` + `command` + `result`
  - failure: `ok` + `command` + structured `error`
- We now know malformed or partial CLI invocations must fail fast headlessly rather than silently falling back into normal GUI startup.
- We now know stable protocol errors matter immediately, not later. `unknown_command` and `invalid_request` are already part of the usable contract surface.
- We now know the original Phase 2 one-shot model was the wrong fit for loaded-data commands. xEdit is a load-once program, so `files.*`, `records.*`, and `elements.*` need a long-lived session model.
- We now know the right local IPC direction for this repo is `serve mode` + `call mode` + PID-addressed named pipes, not PID-only relaunches, window messages, or embedded HTTP.
- We now know record-root and element-path traversal can share one locator model as
  long as the daemon treats an empty path as the record root and child locators stay
  record-relative.
- We now know that request ergonomics and response stability need different policy:
  record-root requests should stay terse, while emitted locators still need explicit
  `path` values for round-trippable downstream traversal.
- We now know progressive disclosure needs to be part of the object contract itself:
  relation stubs plus one-layer child expansion are a better default than embedding
  full recursive element trees.
- We now know the repo depends on initialized `External/*` submodules even for basic local builds; missing submodules can masquerade as unrelated compiler errors.
- We now know this local environment cannot be trusted as the sole source of Delphi build verification, so RAD-backed verification remains part of the practical workflow for now.
- We now know that having `dcc32` and `msbuild` available is not enough in this environment; the installed toolchain can still refuse command-line compilation while reporting a superficially successful MSBuild wrapper run.
- We now know the reliable local rebuild trigger on this machine is the exact background `Start-Process ... bds.exe -b ...` path, with GUI blocker handling when the Community Edition EULA reminder appears.
- We now know `LiteDebug` is the trustworthy local verification configuration on this machine, while `Release` can report success without producing a usable fresh executable.
- We now know pipe/client reliability details matter at Phase 2 scale already: normal pipe-open races need retry, empty request files must fail fast, and mixed automation modes must not silently pick precedence.
- We now know "one comment near the main architectural seam" is not enough for upstream review. Validation and error-contract branches also need local intent comments when they introduce policy decisions.
- We now know MO2-backed mutation verification is much more auditable when writes are redirected to a dedicated test plugin (`opencodetest.esp`) instead of mutating upstream fixture plugins directly.
- We now know the MO2 harness model needs a sharper distinction between entrypoints and implementation bodies: `ModOrganizer.exe ... run -e OpenCodeVfsLauncher -a "..."` is the MO2 bootstrap entry, while `mo2-vfs-launcher.ps1/cmd` is the launcher implementation behind that entry after MO2 has already activated the session.
- We now know the later harness drift was not "using OpenCodeVfsLauncher at all"; it was bypassing the MO2 bootstrap entry and running the launcher helper directly from the host shell, which is not the same thing.
- We now know the current `session.save` seam is weaker than the desired Phase 3 contract for some files: xEdit's existing GUI save path can queue a rename for shutdown rather than guaranteeing immediate on-disk persistence while the daemon stays alive.
- We now know that this save-seam behavior can be surfaced honestly in the protocol without replacing xEdit's native save path: `session.save` can distinguish `saved_now` from `save_pending_shutdown` while still reusing `xeSavePluginFile(...)`.
- We now know the first GUI-state seam can stay intentionally coarse: a blocker-only window snapshot is enough to tell automation whether the session is interactable without exposing per-dialog button trees yet.
- We now know VCL contributes at least one framework-owned top-level window (`TApplication`) that must be filtered out so GUI blocker reporting stays aligned with human-visible xEdit state.
- We now know the Phase 4 research ledgers are useful working inputs, not paperwork: the workflow coverage matrix, GUI blocker ledger, atomic capability ledger, and out-of-scope ledger now anchor capability planning to observed community usage instead of intuition.
- We now know capability coverage needs both a research-side framing and a runtime-side surface check: the ledgers describe what should exist, while `system.capabilities` reports what the current daemon actually exposes.
- We now know the safest read-side addressing seam for this tranche is `IwbFile.ContainedRecordByLoadOrderFormID[...]` first, with `RecordByFormID[...]` retained only as a temporary compatibility fallback for older local-form callers.
- We now know the first `records.list` surface needs an internal hard stop even before public pagination exists; otherwise a seemingly simple enumeration call can become an accidental full-file dump plus an avoidable intermediate allocation.
- We now know the first `records.list` contract can stay deliberately narrow without being misleading: required `file`, optional `signature`, shallow locator-bearing results, and bounded output are enough to support discovery while deferring richer querying and pagination.
- We now know an exact load-order FormID search can stay bounded without inventing a general search contract: iterating loaded plugin files and probing each one for the same public identity is enough to surface concrete hits plus the shared `masterOrSelf` / `winningOverride` endpoints, as long as it obeys the same internal cap and truthful `truncated` reporting as the other bounded record surfaces.
- We now know exact EditorID lookup needs a stricter split from GUI ergonomics: the automation primitive should use exact `SameText` identity only, optionally narrow by signature with caller-case normalization, and leave prefix/tree-navigation behavior out of the protocol entirely.
- We now know the current public read-side `formId` meaning for address-oriented and exact-search read commands should be described as load-order-first; temporary file-local acceptance is compatibility behavior, not the primary contract.
- We now know local verification notes must explicitly call out missing RED preservation when that happens during implementation, rather than implying the artifact set is complete.
- We now know `records.get` must resolve emitted load-order FormIDs through the public file-level conversion seam instead of assuming the in-file lookup can consume that public identifier directly.
- We now know the automation caller's valued switches use the existing `-name:value` command-line contract, which matters for local verification tooling and for interpreting missing response artifacts honestly.
- We now know at least one startup blocker lived earlier than the serve pipe itself: stale reference-cache cleanup used to show a modal confirmation before daemon readiness, so post-pipe GUI probes could never diagnose that class of failure.
- We now know that startup-hardening fix removes an important source of false blame on the GUI snapshot command: pre-pipe startup failures belong in startup code, not in post-pipe session blocker reporting.
- We now know the pre-pipe serve path was already doing more suppression than the earlier docs said: the first-run architecture warning and developer message are both skipped in serve mode, independent of the narrower stale-reference-cache fix.
- We now know the conflict snapshot extraction can stay protocol-neutral: root participants come from the master/override chain, while child and element participants can be derived from aligned comparison rows instead of leaking GUI view-node state into the automation contract.
- We now know the aligned-row helper must treat each `TDynViewNodeDatas` child-row buffer as single-use: `InitNodes` expects a fresh zeroed row, and the root snapshot should reuse that same aligned participant basis so root/child arrays stay stable for later JSON serialization.
- We now know `elements.required_masters` belongs on the same locator contract as the rest of `elements.*`: callers can use either the record root (`path:""`) or a child path and still receive the same addressed-object envelope plus a deduplicated load-order-sorted master list.
- We now know fresh LiteDebug rebuilds matter for command-registration verification specifically: the inspected source can be correct while an older MO2-synced binary still reports `unknown_command`, so runtime checks for newly added commands must follow a confirmed fresh build artifact.
- We now know MO2 serve readiness should be treated as a two-stage condition (`xEdit.exe` process first, named pipe second); process discovery alone is not yet sufficient evidence that the daemon can answer automation calls.
- We now know broad command-coverage claims need three separate roles: read-only `@explorer` reconnaissance produces the boundary/use-test matrix, bounded `@laborer` execution can run fixed MO2-backed CLI/named-pipe verification chores and preserve request/response artifacts, and the orchestrator owns routing, summary checks, review, and final claims.
- We now know direct daemon verification must launch a real `xEdit.exe -automation-serve` process and address that daemon PID; using the caller shell PID with `-automation-call-pid:<pid>` only proves the expected `Automation daemon pipe is unavailable` failure.
- We now know even Task 1's substrate needs stable empty-page JSON shape: clients should always see `findings: []` from `jobs.findings`, not infer an empty page from an omitted field.
- We now know `xEdit.dproj` should preserve its tracked CRLF style even though this local Git setup reports CRLF changed lines as `git diff --check` trailing whitespace; semantic project diffs should be judged with EOL ignored instead of shipping full-file LF normalization.
- We now know request-shape validation for mutating file-hygiene commands should happen before protected-target guards when malformed input is independent of target writability; otherwise invalid requests against Fallout4.esm get misclassified as protected-target mutation errors.
- We now know Task 2's direct-daemon smoke pass is useful for command registration and protected/read behavior, but it is not a substitute for MO2-backed positive mutation fixtures and save/reload readbacks.
- We now know concrete job kinds need their own start validators behind the job manager registration seam: `files.hygiene.batch` has kind-specific request shape and dry-run defaults that should run after known-kind lookup but before active-job conflict checks.
- We now know batch file-hygiene dry runs cannot truthfully predict every native `SortMasters`/`CleanMasters` result without mutation, so the safe contract is conservative planned findings plus a risk note and no mutation until `dryRun:false`.
- We now know xEdit's native copy/delete seams need GUI-parity details even for headless automation: deep-copy root records with child groups must follow the child-group seam, and physical root-record delete must remove the associated child group to avoid orphan GRUP state.
- We now know `wbNewFile(...)` can create file-backed modules before normal indexing is fully established, so file lookup/save surfaces must remain tolerant of automation-created plugin modules that do not yet satisfy the same `HasIndex` assumptions as loaded input files.
- We now know restart-time FormID readback for newly saved Phase 5 patches can remap ESL/load-order-visible IDs, so verification and later clients should prefer returned locators and read-side resolution over hard-coded pre-reload IDs.
- Historical/superseded by the `v4.1.6-automation.2` release replacement: `records.create` was previously kept intentionally narrow to `KYWD` and `MISC`, but the current branch no longer carries that protocol allow-list and instead lets xEdit's native group/record creation decide which signatures the active game/file model supports.
- We now know file summaries need actual `masters` readback, not just command-local master reports, because proving no hidden master mutation requires reading the real `IwbFile` master list through `files.get`, dirty-state summaries, save responses, and fresh reloads.
- We now know optional caller correlation can be added additively at the protocol envelope layer: parsed JSON-object requests can safely echo top-level `requestId` / `id`, while malformed JSON should remain on the legacy uncorrelated error path because no trustworthy request object exists.
- We now know `records.base_record` is not override ancestry. It is the xEdit linked-base-record relation for reference-style records such as `REFR -> STAT`; override lineage belongs to `records.master_or_self` and `records.winning_override`.
- We now know fresh MO2 daemon launch evidence must include pipe readiness, not just the launcher state-file PID. PID-only readiness can return before the replacement daemon accepts named-pipe requests.
- Historical/superseded: the programmable `OpenCodeVfsLauncher` path previously looked like the better mainline MO2 candidate after official masters were mirrored into the Stock Game `Data` path because it gave explicit child-PID handoff and profile `plugins.txt` control. That candidate direction must not be reused as a reason to write to Stock Game Data; the current Phase 6 harness syncs the fresh build into the MO2-managed OpenCodeXEdit tool path, launches that canonical target through MO2, and verifies fixture persistence through MO2 `overwrite` without copying, deleting, or mutating anything under `Stock Game\Fallout 4\Data`.
- Historical/superseded by the accepted 6A baseline: the Phase 6A harness had drifted beyond the documented Phase 5 contract by inserting a PowerShell wrapper and harness-side plugin-list/module arguments; restoring `OpenCodeVfsLauncher` to target xEdit directly did not by itself restore named-pipe readiness during that diagnostic pass, but the final accepted 6A harness later reached the required MO2-backed daemon readiness.
- We now know the Phase 6A job seam should stay in-memory and main-thread poll-driven until a concrete job kind requires more: this avoids adding background-thread assumptions around xEdit's loaded plugin graph while still giving callers stable job IDs, terminal retention, paging, and cancel/discard verbs.
- We now know Task 1 should not conflate command registration with contract maturity: daemon sessions may accept `jobs.*` early for validation, but `system.capabilities.supports.jobs` and concrete implemented job kinds should wait for the Task 3 `files.hygiene.batch` contract bump.
- Historical/superseded by the accepted 6A baseline: the local MO2 launch path could fail before logging or spawning xEdit during an earlier Task 1 session, so the plan at that time was to restore the MO2-backed launcher path and rerun preserved requests against a true MO2-backed daemon; the accepted 6A artifact set is now the current baseline, not a pending rerun requirement.
- We now know Task 1 build evidence must be treated as configuration-sensitive: `Debug` logs that say `Success` are not acceptable verification for this workstream, and `xEdit.dproj` must keep its upstream default config instead of being changed locally to force LiteDebug.
- We now know semantic artifact hygiene matters for repeated harness runs: stale request/response/readback JSON can mask current-run exceptions unless per-run artifact files are cleared or overwritten deterministically.
- We now know the current save/restart seam still cannot prove pending-shutdown persistence in all cases. Even when a non-light loaded fixture reports `savedFilesPendingShutdown` and the file reloads, a newly created record may not be discoverable after restart, so this remains a documented coverage gap rather than a green claim.
- We now know the Phase 6A harness itself contained forbidden Stock Game Data mutation assumptions: it deleted `VT_Phase6A*` fixtures from Stock Game `Data`, treated Stock Game `Data` as the disk-evidence root, and could drift by launching an unsynced repo `Build\xEdit.exe`. Those paths are now removed or guarded; the binary sync is limited to the MO2-managed `OpenCodeXEdit` tool executable, and the semantic fixture/save flow proves writes through MO2 `overwrite` while separately recording that real game Data remains unchanged.
- We now know the dedicated Phase 6A overlay mod being enabled in MO2 is not the actual native xEdit save destination for newly created plugins in this harness. The current proof gate expects `files.create` + `session.save` output under MO2 `overwrite`, not `mods\OpenCodePhase6AFileHygiene\Data`, before semantic mutation cases run.
- We now know the accepted Phase 6A baseline is stable enough to serve as the frozen dependency floor for 6B-E: the preserved summary reports `status=passed`, `failed=0`, and `harnessFailure=null`, and the semantic acceptance note records Phase 6A as passed with the known no-Stock-Game and no-op clean-master caveats.
- We now know Phase 6B compact/apply needs file-scoped FormID recovery to reuse the same locator compatibility seam as `records.get`; after ESL conversion and reload, exact file-scoped `records.find_by_form_id` cannot rely only on the pre-save load-order slot.
- We now know Task 3 save/reload proof must let xEdit drain pending native save/rename work through graceful shutdown before the fresh daemon starts; force-killing immediately after a pending-shutdown save can create false RED persistence evidence.
- We now know the 6B-E automation surface can replace several GUI-coupled xEdit operations with headless seams: ESL flag application, compact-for-ESL remapping, validation finding extraction, ITM/deleted-reference cleaning, sort/clean masters, and localization temp-save handling can run without selection-bound main-form flows, progress UI, implicit save, or auto-exit behavior.
- We now know some GUI-coupled work should stay deferred rather than smuggled into Phase 6 job handlers: arbitrary modal/button control, Pascal script execution, broad workflow macros, and unbounded query behavior need later explicit design instead of incidental 6B-E expansion. Historical deferrals for medium-plugin policy and arbitrary record-signature semantics are superseded for the current thin CLI seams by the `v4.1.6-automation.2` release replacement.
- We now know validation and cleaning cannot trust fresh-fixture GUI conflict state as the semantic oracle; both 6C and 6D had to use master-side/header-skipping comparisons because freshly automation-created or reloaded fixtures may not populate the same GUI comparison flags that native interactive flows expose.
- We now know final-round evidence is fragile unless artifact references are canonical and current: stale summary paths, stale expected capability assertions, or request-only RED notes can overstate acceptance unless the roadmap calls out what was actually captured and which final rerun supersedes it.
- We now know canonical tool-target discipline is a first-class verification requirement: final 6B-E runtime evidence is only meaningful when the fresh LiteDebug binary is synced to and launched as the MO2-managed `OpenCodeXEdit` tool target, not from the repo `Build\xEdit.exe` or a direct helper bypass.
- We now know the Phase 6 contract hardening should freeze job-kind membership/order explicitly enough for wrapper code to branch on stable codes and capability lists; dictionary iteration order or undocumented registration side effects are not acceptable contract evidence.

## How This Changes Later Phases

- Later read-only work should build on the daemon/session transport rather than extending the old one-shot loaded-data path.
- Later read-only work can keep richer element navigation on the existing `{file, formId, path}` locator contract instead of inventing separate root and child addressing schemes.
- Later read-only tasks should keep shared loaded-session lookup helpers in neutral units rather than letting one command group become another group's dependency hub.
- Later read-only tasks should preserve bounded progressive disclosure. Any broader query or search surface should return explicit summaries and follow-up locators, not nested trees.
- Later implementation rounds on this machine should expect an IDE-backed or GUI-assisted rebuild before trusting runtime smoke results.
- Later runtime verification should preserve the current harness boundary: sync the fresh LiteDebug binary into the MO2-managed `OpenCodeXEdit` tool path, enter through MO2 first, then let MO2's configured executable or bootstrap entry start that canonical xEdit target under VFS. Do not bypass MO2, do not point Phase 6 FO4 verification at `D:\TES5Edit-contrib\Build\xEdit.exe`, and do not call the launcher helper directly when the goal is canonical verification.
- The completed Phase 3 mutation work already proved that the daemon/session model is the correct base for write-capable automation, so later work should build on that seam rather than revisiting one-shot execution ideas.
- Later write-capable work should preserve the same headless fail-fast behavior and structured error discipline that Phase 3 established.
- Future save-related expansion should continue to respect the current explicit `session.save` boundary and the distinction between immediate persistence and queued-on-shutdown rename behavior.
- Phase 4 should no longer jump straight to contract polish. The next layer of work is capability enrichment: derive the missing atomic operations from real community usage, eliminate important GUI blockers, and broaden the first-class CLI surface before treating the contract as mature.
- Post-Phase-3 work should be organized around atomic capability families, not workflow macros and not a raw dump of internal Pascal APIs.
- `Run Script` should remain an escape hatch for long-tail or highly custom actions, not the main answer for high-frequency missing primitives.
- Later phases must explicitly audit workflow coverage and GUI blockers so the roadmap cannot silently miss common modding tasks while still claiming automation progress.
- Later GUI automation work should keep the current blocker probe as a coarse control-plane check and layer any dialog-specific actions on top of it, rather than collapsing detection and button-level interaction into one unstable response shape.
- Later startup-hardening work should distinguish pre-pipe blockers from post-pipe blockers. The former must be eliminated or auto-resolved in startup code; `session.get_gui_snapshot` only helps once the daemon is already reachable.
- Contract polish and upstream hardening still matter, but they should move later in the sequence after the mainline capability families exist.
- Later broader query surfaces should preserve the same bounded-first rule as `records.list`: small, shallow summaries first, richer traversal through follow-up locators instead of unbounded bulk payloads.
- Later exact-search additions should keep the current policy split: internal caps must drive truthful `truncated` reporting, and optional narrowing arguments should accept ergonomic casing without broadening the underlying match semantics.
- Later enrichment work should keep the research ledgers and `system.capabilities` in sync: coverage planning should come from the local notes, while runtime verification should confirm the daemon surface actually matches that plan.
- Later address-oriented read work should treat load-order FormIDs as the primary public locator shape and keep any remaining file-local support as an explicit compatibility layer, not as the main contract.
- Later Phase 4 search-oriented work should build outward from `records.find_by_form_id` and `records.find_by_editor_id` as atomic exact-identity primitives, layering any broader discovery/filter/report surfaces separately instead of mutating these commands into a fuzzy, prefix, or query-DSL contract.
- Later conflict-status command work should serialize from the shared snapshot helper instead of re-deriving alignment or participant policy inside the protocol writers.
- Later runtime verification on this machine should gate command-level claims on both a fresh LiteDebug build timestamp and actual pipe readiness, not merely on the appearance of an xEdit process under MO2.
- Later broad verification sweeps should first ask `@explorer` for a missing boundary/use-case matrix, then use `@laborer` for fixed-harness runtime execution when the method and pass/fail checks are already known; do not describe explorer planning as executed CLI coverage, and keep unclear failures or harness design in orchestrator/`@oracle` territory.
- Later patch-building work should preserve the Phase 5 atomic-command boundary. Compose workflows externally from `files.*`, `records.*`, `elements.*`, and `session.save` rather than adding in-repo compatibility-patch macros.
- Later create/copy/delete expansions should design each new signature or record family around native xEdit invariants first, not simply broaden the current allow-list.
- Later runtime harnesses should include restart/reload readback whenever saved plugin state is part of the claim, because in-memory locators and post-save locators can differ for light/load-order identity.
- Later protocol consumers may rely on optional `requestId` / `id` echo only for syntactically valid JSON-object requests; malformed JSON responses should not be treated as correlation-capable.
- Later relationship tests should choose fixtures that match the command's real xEdit meaning. Use `REFR`/reference-style records for `records.base_record`, and keep override lineage assertions on `master_or_self` / `winning_override`.
- Later save-persistence work needs either an automation-supported graceful shutdown/drain path or a different persistence fixture strategy before claiming pending-shutdown restart survival as covered.
- Later acceptance claims should be phrased around semantic xEdit-state evidence, not review approval or script status alone: each important command/argument combination needs a CLI invocation plus a readback that proves the intended file, master, record, deleted, or persistence state.
- Accepted Phase 6A baseline note: the final 6A semantic harness already exercised start-time validation ordering and poll-time execution summaries for `files.hygiene.batch`, including omitted dry-run defaults, unknown-kind handling during queued work, findings paging, and partial apply-mode failure behavior; future phases should preserve that coverage rather than treating it as pending 6A work.
- Historical/superseded: earlier MO2 startup diagnosis proposed continuing from the programmable wrapper route after mirrored official masters were visible. Future diagnosis must not depend on mirrored Stock Game masters; it should use the MO2-managed OpenCodeXEdit tool path as the canonical launch target, keep that target current by syncing the fresh build there, and prove any needed game-data substitutions through MO2 overlays, overwrite evidence, or another explicitly approved non-Stock-Game-Data root.
- Later MO2 startup diagnosis should continue from the restored direct `OpenCodeVfsLauncher -> xEdit.exe` bootstrap, not the diagnostic PowerShell wrapper, and should treat the wrapper/probe scripts as local diagnostics only unless a new bounded experiment explicitly needs them.
- Later Phase 6A runtime verification should keep the overwrite-based proof gate: `files.create` plus `session.save` must place Phase 6A fixture plugins under MO2 `overwrite` and leave real `Stock Game\Fallout 4\Data` untouched before guarded semantic rows can run.
- Later Phase 6A debugging should use the preserved overwrite proof artifacts to determine where native xEdit placed or attempted to place `VT_Phase6A_OverlayProof.esp`; do not advance to semantic rows unless that proof confirms the current overwrite destination and no real game Data write.
- Phase 6B-E should execute as one combined implementation round only for scheduling efficiency; acceptance remains slice-local. Each 6B, 6C, 6D, and 6E harness must independently cover positive paths, meaningful argument combinations, protected-target failures, dry-run versus apply behavior, dirty-state before save, explicit save, and fresh restart readback where persistence is claimed.
- Later 6C/6D/6E harnesses that save fixtures should preserve the Task 3 graceful-shutdown pattern whenever `session.save` reports pending-shutdown work, and later readback commands should reuse shared locator-recovery helpers instead of open-coding file-slot assumptions.
- Later phases must preserve the 6B-E atomic job boundary: jobs may plan, mutate in memory, report findings, and mark dirty state, but they must not hide implicit `session.save`, auto-exit, GUI wizard assumptions, or workflow-level macro behavior behind a single broad operation.
- Later validation/cleaning/analysis phases should continue extracting non-GUI seams from native logic only when the resulting automation path has independent semantic readback; do not reintroduce selection-coupled main-form dependencies for operations already proven headless in 6B-E.
- Later contract changes after Phase 6E must update `system.capabilities.supports.jobs.kinds`, stable finding/error code constants, examples, and source-side registration checks together; additive implementation without contract refresh is a regression.
- Later semantic acceptance must include early RED capture discipline and stale-artifact cleanup as part of the harness design. If pre-implementation response JSON is missing, record that limitation explicitly and do not let request-only RED notes masquerade as full response-envelope evidence.
- Later runtime verification must keep the canonical MO2/LiteDebug path as a non-regression gate: fresh `LiteDebug` build evidence, sync to `Stock Game\Fallout 4\Tools\OpenCodeXEdit\xEdit.exe`, MO2 entrypoint launch, pipe readiness, MO2 `overwrite`/overlay fixture writes, and no Stock Game `Data` mutation.

## Guiding Principles

- Build an in-process automation subsystem inside xEdit, not another external hook path.
- Prefer new Pascal units over widespread edits to existing xEdit units.
- Keep legacy-unit changes concentrated in a small number of startup and lifecycle seams.
- Expose stable automation contracts and facades, not raw internal symbols.
- Implement only the xEdit-side automation and CLI contract in this repo.
- Treat any MCP integration as an external consumer of that CLI contract, not as an in-repo host layer.
- Upstream-facing non-obvious code should carry review-friendly comments that explain lifecycle seams, registration seams, protocol/error boundaries, and special-case behavior that a maintainer would otherwise need to reverse-engineer.
- Sequence read-only coverage before write-capable automation.

## Phase 0 - Architecture Freeze

### Goal

Freeze the architecture boundary so later work does not slide back toward hook-era assumptions or ad hoc API exposure.

### Task Specs

- Document the approved subsystem shape: contracts, registry, command facades, session layer, and the xEdit-side CLI host.
- Record the primary non-goals, especially no runtime hook architecture and no attempt to auto-reflect all upstream Pascal APIs.
- Identify the expected small legacy touch surface (`xEdit.dpr`, `xeInit.pas`, likely one lifecycle seam such as `xeMainForm.pas`).
- Define the first command grouping strategy so later API additions stay organized by stable intent rather than incidental unit ownership.
- Establish local development hygiene rules for temporary artifacts, scripts, and gitignore handling.

### Expected Outcomes

- The project has one approved architectural story.
- Future tasks can be evaluated against an explicit boundary instead of memory or chat context.
- Contributors know that most new behavior belongs in new `xeAutomation*.pas` units.

## Phase 1 - Automation Skeleton

### Goal

Prove that xEdit can host a first-class automation subsystem with minimal legacy-unit edits and a stable internal dispatch path.

### Task Specs

- Add the core automation units:
  - contract/types
  - structured errors
  - central registry
  - session/execution context
  - thin CLI host
- Wire the subsystem into the smallest practical set of existing startup/lifecycle seams.
- Implement command self-registration through `initialization` so new command groups can be compiled in without repeatedly editing a single master switchboard.
- Define and expose a tiny read-only command slice that proves the full path works end to end.
- Make capability/introspection available early so clients can learn what a given build supports.

### Expected Outcomes

- xEdit can start in an automation-aware mode.
- A client can invoke a small number of typed read-only commands through the shared registry path.
- The project has a concrete base for later command groups without having to redesign the host boundary.

### Completed In This Round

- Added xEdit-side automation core units for types, session state, errors, registry, command registration, and CLI hosting.
- Proved that automation can run before `Application.CreateForm`, so the first headless path does not need to wait for main-form lifecycle integration.
- Implemented the first command slice:
  - `system.ping`
  - `system.describe`
- Implemented structured success/error envelopes on the CLI path.
- Verified runtime behavior against a rebuilt binary for:
  - successful `system.describe`
  - `unknown_command`
  - `invalid_request`
  - fail-fast handling when automation flags are only partially supplied

### Unknowns Resolved By Phase 1

- Earlier unknown: can xEdit serve a useful automation request before the GUI comes up?
  Now known: yes, a pre-UI CLI path works and is a valid seam.
- Earlier unknown: should this repo grow an in-process MCP layer?
  Now known: no. The practical and reviewable boundary for this repo is still CLI.
- Earlier unknown: can command groups be added without repeatedly editing one giant switchboard?
  Now known: yes, registry dispatch plus `initialization`-based self-registration works, as long as command units are linked into the project.
- Earlier unknown: do stable protocol errors matter only later, once the surface is larger?
  Now known: no. Stable `unknown_command` and `invalid_request` behavior is required immediately.
- Earlier unknown: what should happen on malformed or partial automation invocation?
  Now known: the product contract must fail fast headlessly rather than falling back into normal GUI startup.
- Earlier unknown: is comment discipline optional for early phases?
  Now known: no. Upstream-facing lifecycle, registration, validation, and error-boundary seams need explicit review-friendly comments even in the first milestone.

### How Phase 1 Changes Later Phases

- Phase 2 should build on the existing CLI contract instead of revisiting transport shape.
- Phase 2 should prioritize additional read-only command groups over new hosting layers.
- Phase 2 should treat schema quality, command naming, and capability reporting as product work, not cleanup.
- Phase 2 should add broader verification around malformed inputs, more command examples, and more read-only coverage now that the contract shape is known.
- Phase 3 must preserve headless fail-fast behavior and structured error discipline when write-capable commands are introduced.
- Later phases should budget explicitly for upstream review readability: non-obvious seams need comments, and each implementation round should refresh this roadmap with newly learned facts.
- Later phases should expect a dedicated comment/reviewability pass before claiming a round is ready for upstream discussion.

## Phase 2 - Read-Only API Expansion

### Goal

Grow the automation surface into a credible read-only API across the xEdit data model.

### Task Specs

- Add command groups for files/plugins, records, element traversal, and query/filter operations.
- Improve request/response schemas where the first skeleton exposed weak spots.
- Add stronger capability metadata and versioning expectations.
- Start assembling client-facing CLI examples and define the CLI contract clearly enough for an external MCP adapter to consume.

### Expected Outcomes

- The subsystem exposes a useful first-generation inspection API.
- Automation consumers can discover capabilities rather than depending on undocumented behavior.
- The project has enough real command coverage to pressure-test naming and contract quality.

### Completed In This Round

- Replaced the superseded one-shot loaded-data CLI plan with a daemon/session model.
- Added `automation-serve` and `automation-call` process modes.
- Added PID-addressed named-pipe transport between the thin call-mode client and the loaded daemon session.
- Moved loaded-data command registration to the serve lifecycle after xEdit's real load path completes.
- Added and verified the first loaded-session command slice:
  - `files.list`
  - `files.get`
  - `records.get`
  - `elements.get`
  - `elements.children`
- Verified negative `file_not_found` behavior.

### Unknowns Resolved By Phase 2

- Earlier unknown: can loaded-data commands fit the same one-shot lifecycle as `system.*`?
  Now known: no. Loaded-data commands need a load-once daemon/session model.
- Earlier unknown: what local IPC is the best fit for xEdit itself?
  Now known: PID-addressed named pipes are the most balanced in-repo transport.
- Earlier unknown: can the object locator/envelope model survive the daemon pivot?
  Now known: yes. `{file, formId, path}` plus bounded `object` / `relations` still works when the data comes from a loaded session.
- Earlier unknown: can progressive disclosure stay bounded in real runtime use?
  Now known: yes. `elements.children` can return one layer of child stubs while `elements.get` handles deeper inspection.
- Earlier unknown: can the daemon/client transport be made reliable enough for normal CLI use without widening scope to HTTP?
  Now known: yes, provided the client retries normal pipe-open races and malformed transport cases fail fast with structured errors.

### How Phase 2 Changes Later Phases

- Phase 3 should assume one long-lived loaded daemon session instead of repeated one-shot process startup.
- Mutation work should be attached to the same loaded-session seam used by read-only commands.
- Future command additions should keep request execution transport-agnostic, but lifecycle-aware: loaded-data work belongs behind serve mode.
- Reliability work should explicitly include pipe disconnect handling, malformed transport cases, and repeated/concurrent call verification.
- Phase 3 is now clearer than before: it no longer needs to decide transport or lifecycle first. It can focus directly on mutation boundaries, staged edits, explicit save/commit semantics, and mutation-specific validation/error rules on top of the verified daemon/session model.

## Phase 3 - Mutation and Save Semantics

### Goal

Introduce write-capable automation without compromising safety or turning persistence into hidden side effects.

### Task Specs

- Define mutation boundaries and validation rules.
- Introduce explicit save/commit behavior.
- Harden structured error reporting for mutation failures.
- Add targeted tests and examples around destructive or stateful operations.

### Expected Outcomes

- Write operations are explicit, reviewable, and easier to reason about.
- Automation clients can tell the difference between inspection, staged mutation, and persistence.

### Completed In This Round

- Added daemon-only `session.get_dirty_state` so clients can ask whether the loaded automation session has unsaved plugin changes.
- Added a narrow mutation-policy unit that centralizes Phase 3A writable-target checks.
- Extended the automation error catalog with mutation-specific protocol codes including:
  - `mutation_not_allowed`
  - `read_only_target`
  - `invalid_target`
  - `save_failed`
- Added the first mutation command slice on top of the loaded daemon session:
  - `elements.set_value`
  - `elements.add_child`
  - `elements.remove_child`
  - `elements.copy_child_to`
  - `session.save`
- Verified the mutation flow against the dedicated audit plugin `opencodetest.esp` under the MO2 `Default` profile.
- Verified that writes to `Fallout4.esm` are rejected by the mutation policy.
- Kept mutation commands staged in memory until explicit save.
- Reused xEdit's native save seam through `xeSavePluginFile(...)` instead of inventing a parallel persistence stack.
- Added explicit `session.save` result-state distinction:
  - `savedFilesNow`
  - `savedFilesPendingShutdown`
  - `savedNowCount`
  - `savePendingShutdownCount`

### Unknowns Resolved By Phase 3

- Earlier unknown: should dirty-state reporting be tied to individual file commands or to the daemon session itself?
  Now known: it belongs to the daemon session, because dirty/unsaved status is shared across the long-lived loaded in-memory state.
- Earlier unknown: where should writable-target rules live?
  Now known: a dedicated mutation-policy seam is the cleanest place to keep master/hardcoded/editability checks.
- Earlier unknown: can the first write slice stay bounded while still being useful?
  Now known: yes. Value edits, structural child add/remove/copy, dirty-state reporting, and explicit save are a coherent first mutation surface.
- Earlier unknown: should copy/paste be modeled as hidden clipboard state?
  Now known: no. Explicit `source` / `target` requests are more reviewable and more automation-friendly.
- Earlier unknown: does save need its own persistence stack?
  Now known: no. Reusing xEdit's native save seam is viable, but the protocol must expose whether the save completed immediately or is still queued for shutdown rename.
- Earlier unknown: can mutation verification be done safely against ordinary loaded plugins?
  Now known: the safest and most auditable approach is a dedicated audit plugin (`opencodetest.esp`) inside the MO2 profile.

### How Phase 3 Changes Later Work

- Phase 4 should assume the read/write daemon foundation already exists and continue broadening read-side and later write-side capability coverage before treating contract polish as the primary focus.
- Later mutation work can expand outward from the current bounded slice to larger record-level operations without having to reopen the staged-vs-save boundary question.
- Future save-related work should preserve the distinction between immediate persistence and queued-on-shutdown behavior rather than collapsing them into one success state.
- Later verification work should broaden from functional correctness to durability guarantees, restart behavior, and pipe/session robustness under repeated use.

## Post-Phase-3 Roadmap Rules

The remaining roadmap must follow these rules:

- this repo continues to own the xEdit-side CLI substrate only
- roadmap phases should add stable, bounded, headless, machine-consumable atomic capabilities
- roadmap phases must not be written as workflow macros
- roadmap phases must not be written as a raw Pascal API exposure plan
- community workflows are used as coverage oracles to derive which atomic capabilities must exist
- important GUI blockers should be turned into headless CLI capabilities whenever they correspond to high-frequency or high-value xEdit operations
- `Run Script` is a controlled escape hatch, not the mainline enrichment path

Each later phase should explicitly track:

- a workflow coverage matrix
- a GUI blocker ledger
- an atomic capability ledger
- an out-of-scope ledger

## Phase 4 - Coverage Research, Blocker Introspection, and Read-Side Enrichment

### Goal

Start the enrichment program with a deep research pass over BGS modding communities, add the first headless GUI-blocker snapshot primitive, and broaden the read-side CLI into a discovery, enumeration, query, analysis, and report surface.

### Task Specs

- Run a detailed multi-agent research pass across the major BGS modding technical communities to identify the high-frequency xEdit tasks that matter for automation coverage.
- Convert that research into a workflow coverage matrix and GUI blocker ledger.
- Add an early `session/gui snapshot` style primitive that reports whether xEdit currently has non-main-window blockers waiting for operator interaction.
- Add read-side capability families for:
  - session and capability control
  - addressing, enumeration, and discovery
  - query, search, and filtering
  - relationship and analysis primitives
  - machine-readable export and report primitives

### Expected Outcomes

- The project has an explicit coverage map of which high-frequency community tasks are already supported, partially supported, or still blocked.
- Agents can detect GUI blockers headlessly instead of depending on a human to notice and report them.
- The read-side CLI has begun its bounded enrichment with the first coverage-driven discovery and enumeration primitives, without yet claiming broad search or analysis coverage.

### Completed In This Round

- Added local Task 1 research ledgers under `docs/notes/` to drive capability-coverage framing for later phases.
- Added daemon-only `session.get_gui_snapshot` as a blocker-only post-pipe GUI probe.
- Added `system.capabilities` so clients can enumerate the current daemon command surface and basic mode support.
- Added the first bounded record-enumeration primitive:
  - `records.list`
- Added the first bounded exact-search and addressing tranche:
  - `records.get` now resolves public read-side locator FormIDs as load-order-first, with temporary local-form compatibility retained during the transition
  - `records.find_by_form_id`
  - `records.find_by_editor_id`
- Kept the initial `records.list` contract intentionally narrow:
  - required `file`
  - optional `signature`
  - shallow locator-bearing record summaries
  - bounded internal cap of 100 results per call
- Kept the first search contracts intentionally narrow:
  - exact-only lookup, not fuzzy/prefix/query-DSL behavior
  - shallow locator-bearing hits
  - bounded results
  - `records.find_by_form_id` carries compact `masterOrSelf` and `winningOverride` facts
  - `records.find_by_editor_id` does not add top-level winner collapse
- Hardened `automation-serve` startup so stale reference-cache confirmation no longer blocks daemon startup before the pipe exists.
- Clarified the startup-hardening scope in local docs: serve mode already bypassed the first-run architecture warning and developer message, while stale reference-cache confirmation was the newly addressed pre-pipe blocker.
- Clarified the local MO2 harness contract: canonical verification enters through either `OpenCode xEdit Automation Serve` or `ModOrganizer.exe -p Default run -e OpenCodeVfsLauncher -a "..."`, not by directly invoking `mo2-vfs-launcher.ps1/cmd` from the host shell.

### Unknowns Resolved By Phase 4 Foundation

- Earlier unknown: should post-Phase-3 enrichment be driven mainly by intuition, ad hoc requests, or explicit workflow evidence?
  Now known: capability planning is materially better when local research ledgers capture workflow coverage, GUI blockers, atomic capabilities, and explicit out-of-scope items.
- Earlier unknown: is a coarse GUI probe still useful if it does not expose actionable button trees?
  Now known: yes. A blocker-only post-pipe snapshot is enough to tell clients whether the loaded session is presently interactable.
- Earlier unknown: can clients learn the actual daemon command surface headlessly instead of inferring it from docs or build context?
  Now known: yes. `system.capabilities` provides a machine-readable surface check that is more trustworthy than assumptions about what a given binary should support.
- Earlier unknown: does the first record-enumeration primitive need full query/search richness to be worth adding?
  Now known: no. A narrow `records.list` with required `file`, optional `signature`, shallow summaries, and bounded output is already useful and much safer than a broad first cut.
- Earlier unknown: should the new public read-side `formId` meaning stay ambiguous between load-order and file-local semantics?
  Now known: no. The public meaning for the new read-side addressing/search tranche should be described as load-order-first, with any remaining file-local acceptance called out explicitly as temporary compatibility behavior.
- Earlier unknown: do the first search commands need to inherit GUI-style prefix or winner-collapse behavior to be useful?
  Now known: no. Exact-only, shallow, bounded search primitives are already useful when they return stable locators and keep special facts narrowly scoped.
- Earlier unknown: can GUI blocker diagnosis explain every failure to reach a usable daemon session?
  Now known: no. Some failures happen before the pipe exists, so startup hardening and post-pipe blocker reporting must stay separate concerns.
- Earlier unknown: did the startup-hardening scope consist only of the stale reference-cache confirmation path?
  Now known: no. That fix was only one part of the pre-pipe story; serve mode was already suppressing the first-run architecture warning and developer message.
- Earlier unknown: was the MO2 harness drift about using `OpenCodeVfsLauncher` at all?
  Now known: no. The real drift was bypassing MO2 and invoking `mo2-vfs-launcher.ps1/cmd` directly from the host shell instead of entering through a valid MO2 entrypoint.

### How Phase 4 Foundation Changes Later Phases

- Later enrichment phases should continue deriving atomic capability priorities from the local coverage and blocker ledgers instead of jumping straight from anecdotal workflow requests to API design.
- Later diagnostic work should treat `session.get_gui_snapshot` as a post-pipe control-plane check only; startup blockers must still be removed or handled earlier in the automation lifecycle.
- Later capability additions should keep `system.capabilities` accurate enough that clients can trust runtime surface discovery instead of pinning behavior to roadmap text.
- Later read-side expansion should preserve the `records.list` design pattern: require the minimum stable locator inputs, return shallow summaries first, and keep internal bounds until explicit pagination/search semantics are designed.
- Later read-side expansion should treat the current exact-search commands as base primitives: keep `records.find_by_form_id` and `records.find_by_editor_id` exact and bounded, then add any richer discovery or analysis as separate commands.
- Later verification notes must keep distinguishing between canonical preserved artifacts and implementation-time observations that were not fully captured, so the roadmap does not imply stronger evidence than exists.

## Phase 5 - Record Construction, Override, and Patch-Building Primitives

### Goal

Add the atomic record- and element-level construction primitives needed to create patch plugins, copy overrides, perform structural edits, and persist the result headlessly.

### Task Specs

- Add patch/plugin creation primitives.
- Local implementation now covers the file-scope foundation:
  - `files.create` creates in-memory empty `.esp`, `.esm`, `.esl`, and ESPFE-style light plugins, validates filename/template/header-flag combinations, rejects duplicate loaded/on-disk plugin names as `state_conflict`, and can add validated `initialMasters` before the explicit `session.save` boundary.
  - `files.add_required_masters` resolves a target file plus source locator, reuses xEdit's native required-master walker, filters self-dependencies, and reports `masters.added`, `masters.alreadyPresent`, and `masters.skipped`.
  - RED/GREEN request and response artifacts for the create/add-required-masters tranche live under `.opencode/artifacts/phase5-patch-building/`.
- Add record-level copy/create/delete primitives where they can be bounded safely.
  - Historical/superseded by the `v4.1.6-automation.2` release replacement: local implementation originally included `records.create` for `KYWD` and `MISC`; the current branch removes that allow-list and keeps `records.copy_into`, `records.delete`, and `records.mark_deleted` unchanged.
  - Runtime coverage includes override, overwrite, deep override, deep overwrite, copy-as-new, deep copy-as-new, invalid new+overwrite, existing-override conflict, automatic required masters, `addRequiredMasters=false`, protected targets, child-path rejection, physical delete, mark-deleted idempotence, and save/reload readback.
- Add the first-class CLI equivalents of the highest-value patch authoring GUI actions such as `Copy as override into ...` and required-master management.
- Keep the surface atomic and composable rather than bundling full compatibility-patch workflows.

### Phase 5 Implementation Notes

- `wbNewFile(...)` is usable as the automation creation seam when paired with an explicit next-load-order scan over loaded plugin modules and a later `session.save` call for persistence.
- Phase 5 file creation must keep new module discovery index-tolerant: automation-created modules may be loaded and file-backed before they have a normal load-order index, so file lookup/list/save surfaces should accept assigned non-hardcoded plugin files rather than requiring `HasIndex` up front.
- File summaries now include the real master list from `IwbFile.MasterCount[True]` / `Masters[i, True]`; this is required semantic evidence for no-hidden-master, self-master skip, save, and reload acceptance.
- xEdit's `AddMastersIfMissing(..., sort=true, silent=true)` works for the headless required-master add path, but automation should pre-filter and report self-dependencies and load-order-ineligible masters so raw native exceptions do not become the public contract.
- Initial master validation belongs before `wbNewFile(...)`, and create-style commands must check edit mode before mutation so malformed requests do not leave dirty in-memory plugins behind.
- `records.copy_into` must mirror native GUI seams for deep-copy child groups and must preflight/report required masters before copy mutation when requested.
- `records.delete` must remove the root record's child group after physical removal, matching the native UI path and preventing orphan GRUP state.
- `records.mark_deleted` remains one-way and idempotent; there is no Phase 5 undelete primitive.
- Contract `0.5` is the Phase 5 historical surface marker; the current branch supersedes its `records.create` signature allow-list by advertising native xEdit Add policy through `system.capabilities`.
- Historical/superseded by the `v4.1.6-automation.2` release replacement: medium plugins and arbitrary record signatures were originally out of scope for Phase 5; the current branch exposes `medium` as a named header flag and delegates record-signature creation to xEdit native support. Child-path delete/mark-delete, direct protected-file mutation, workflow macros, and implicit save-on-mutation behavior remain out of scope.

### Expected Outcomes

- Agents can build and save common patch artifacts without GUI menus or dialogs.
- Community patch-building workflows stop depending on right-click menus as the last blocking step.

## Phase 6 - Plugin/File Management, Validation, and Cleaning Jobs

### Goal

Move the highest-value plugin hygiene, validation, and cleaning actions behind bounded headless CLI primitives and jobs.

### Task Specs

- Add plugin/file management primitives such as header and master-hygiene operations.
- Add ESL and compact-related analysis and mutation primitives with explicit risk and result reporting.
- Add validation and cleaning job surfaces such as `Check for Errors`, cleaning, and related machine-readable findings.
- Ensure these jobs report progress, completion, and failure in a way external tooling can consume.

### Expected Outcomes

- High-frequency plugin hygiene work no longer depends on GUI menus or wizard-style flows.
- Validation and cleaning outputs can be consumed directly by later automation layers.

## Phase 7 - Script Bridge and Residual Headless Gaps

### Goal

Add a controlled bridge to xEdit's built-in Pascal scripting system for long-tail tasks, and remove the remaining high-value GUI blockers that do not justify their own larger capability tranche.

### Task Specs

- Add a controlled script discovery and execution bridge.
- Keep script bridging clearly secondary to first-class CLI primitives.
- Resolve any remaining high-value GUI blockers that are still preventing headless end-to-end automation.

### Local Phase 7A status

- The local Phase 7A substrate now has a MO2-backed semantic harness under `.opencode/artifacts/phase7A-headless-jvi/` with `phase7A-verification-summary.json` reporting `passed=true`, `passedCount=18`, and `failedCount=0` after the final target-model rerun.
- Completed substrate coverage now includes headless JvI runtime-policy enforcement, external declaration rejection, bounded Scripts-root file reads, traversal and junction escape denial, a `TFileStream.Create` read/write split, a selftest-only deny-default probe for adapter-registered unknown symbols, statement-budget failure coding, finalize-after-failure behavior, same-process hook cleanup after compile/runtime failures, and explicit `Process` target coverage against a loaded Fallout 4 reference.
- GUI non-regression is also accepted locally: repeated native `Apply Script...` runs completed successfully with no `Script is already running` guard leak.
- Newly learned harness/lifecycle constraint: target-model selftests that need loaded records cannot run immediately after `Application.CreateForm`; they must wait for `WMUserLoaderDone` after `TLoaderThread` populates `wbModulesByLoadOrder`, or valid locators falsely fail as missing files. The final harness also avoids passing `-P:<plugins.txt>` and avoids extra positional module arguments through `OpenCodeVfsLauncher`; the MO2 `Default` profile plus `-autoload` is the stable route for this selftest.
- Later Phase 7B script-surface work should preserve these substrate invariants while adding the real `scripts.*` daemon API, and should still add separate coverage for storage CRUD/list/read/write, lint/capability advertising, full concurrency behavior, and any mutating script save/reload behavior. The current 7A save-boundary evidence is intentionally only non-mutating/dirty-state proof, not a fresh mutating persistence claim.

### Local Phase 7B closeout

**What 7B delivered**

- Real `scripts.list/read/write/delete/run` daemon surface.
- `xeScriptStorage` storage helpers with namespace/junction safety, atomic write, and a detailed rejection-kind contract.
- `xeScriptLint` entry-script lexer with a 55-symbol denylist plus dotted-token whitespace/comment tolerance.
- `error.details` envelope on automation errors with copy-based ownership.
- Capability `contractVersion=0.7` and spec-exact `supports.scripts` block.
- Removal of the temporary `scripts-internal-selftest` product path.
- MO2-backed semantic harness with 33 cases and per-case request/response/readback artifacts.

**What we learned (now known)**

- The JvI ledger does not register the `TFile.*` family; spec-allowed reads will surface as `Undeclared Identifier` until 7C registers them.
- The JvI ledger does not register `frmMain` and similar GUI-form symbols; lint denylist entries for those symbols cannot run-deny without registration.
- The daemon serve loop is single-pipe/serial; `script_busy` between two same-pipe daemon calls is architecturally not exercisable in the MVP harness.
- The current `scripts.run` failure envelope does not surface `ranFinalize`, so finalize-after-`Process`-failure is not directly testable from the response shape today.
- The `dcc32` warnings about LF line endings are benign on this build path; canonical build still produces a usable LiteDebug binary.
- `xeScriptStorage`-side detail rejection-kind constants are valuable for the command facade; future commands should follow the same pattern.

**What later phases should now do differently**

- 7C should register `TFile.*` reads and decide which GUI-form symbols belong in JvI versus runtime-only deny.
- A future revision of the `scripts.run` response should expose `ranFinalize` on the error envelope so finalize-after-`Process`-failure is directly observable from a single call.
- Consider exposing a true consumed-statement counter from the host so `script_statement_budget_exceeded.error.details.statements` can be honest.
- Revisit busy-guard testability via a multi-pipe/parallel-session harness.
- Consider a per-symbol denylist regression suite that exhaustively exercises the spec's named deny symbols at the daemon surface.

**NOT-COVERED items by id**

- `C9` — script_busy guard (daemon-vs-daemon and GUI-vs-daemon) — architecturally not exercisable from a single-pipe non-interactive harness; code-level guard evidence preserved.
- `finalize-after-process-failure-001` — finalize-after-Process-failure is proved at the 7A substrate level but the public scripts.run error envelope does not currently surface ranFinalize, so daemon-surface proof is deferred.
- `default-deny-broad-symbols-001` — the runtime deny-default mechanism is proved by C2-C5 with deniedIdentifier emitted, but the spec-named individual symbols (TBinaryWriter.Create, TJsonBaseObject.SaveToFile, TCustomIniFile.DeleteKey, ResourceCopy, wbCRC32File, wbSHA1File, wbMD5File) are not enumerated through the daemon surface.
- `external-declaration-daemon-surface-001` — JvI external-declaration rejection is proved at the 7A substrate level; the 7B scripts.run facade currently maps it to script_compile_error pending a stable JvI exception shape (Task 5 authorized C3 TODO).

**Final harness facts**

- 29 passed / 0 failed / 4 NOT-COVERED / 33 total.
- `coverageStrict=false` deliberately, due to the 4 disclosed NOT-COVERED items.
- Binary SHA256 `D92C0DC812382BA99B7819357BE20CB01F660C99771E639F81BDD6FBB5511E08` synced to the canonical MO2 tool target.
- Daemon entrypoint: `ModOrganizer.exe -p Default run -e OpenCodeVfsLauncher -a "..."`.

### Local Phase 7C closeout

**What 7C delivered**

- JVCL `EJvInterpreterExternalDeclarationDenied` discriminator plus daemon mapping to `script_external_declaration_not_allowed`.
- Lifecycle fields on failed `scripts.run` error envelopes: `ranInitialize`, `ranFinalize`, and `processed`.
- Long-tail default-deny daemon coverage for D1-D7.
- Runtime-policy ledger completion for `TStrings.LoadFromFile` / `TMemoryStream.LoadFromFile`.
- Restored honest daemon-surface coverage for `TFile.ReadAllText` through the `C1` rewrite-back case.
- Restored honest daemon-surface coverage for `frmMain` runtime denial through the `C3` rewrite-back case.
- Spec-exact additive documentation fields under `supports.scripts`.
- MO2-backed semantic harness with 50 entries: 48 PASS / 0 FAIL / 2 NOT-COVERED.

**What we learned (now known)**

- The 7B `C1` reshape root cause was wrong: `TFile.*` / `TDirectory.*` were already registered; the failure was fixture-pattern, not substrate absence.
- `TStrings.LoadFromFile` / `TMemoryStream.LoadFromFile` were JVCL-registered but missing policy ledger rows.
- Adapter lookup precedes `OnGetValue`; permanent adapter sentinels would shadow GUI behavior, so the final 7C closeout used a headless-only explicit deny seam instead of claiming fresh GUI proof.
- Object cleanup (`Free`) can mask primary semantic assertions in harnesses; read-contract tests should isolate the symbol under test.
- `deniedIdentifier` may surface concrete subtype names such as `TJsonObject.SaveToFile`, `TMemIniFile.DeleteKey`, or `TStringList.LoadFromFile` even when the spec family is broader; this is acceptable if documented honestly.

**What later phases should do differently**

- Phase 8 should own `C9` busy/concurrency semantics with a multi-pipe and/or GUI automation strategy.
- Phase 8 contract-freeze work should decide whether additive capability keys stay at `0.7` or trigger a version bump.
- Phase 8 or later should decide whether failed `scripts.run` envelopes should ever carry `messages` in addition to lifecycle fields.
- Future semantic harnesses should distinguish product bugs from harness-shape bugs earlier by avoiding non-contract helper calls such as `IntToStr` and `Free` in focused cases.

**NOT-COVERED items by id**

- `C9` — busy/concurrency (`script_busy` daemon-vs-daemon and GUI-vs-daemon) — architecturally not exercisable in the current harness; code-level guard evidence preserved.
- `gui-non-regression-001` — fresh final-7C GUI Apply Script non-regression against the final binary was attempted but not captured reliably through non-interactive automation; failed attempt preserved, and 7A GUI provenance remains the last positive GUI artifact.

**Final harness facts**

- 48 passed / 0 failed / 2 NOT-COVERED / 50 total.
- `coverageStrict=false` deliberately, due to the 2 disclosed NOT-COVERED items.
- Binary SHA256 `A393E42DF51777ED9FBB247020CAE9A20F1379D003695A699C8F06D41BD3E4FD` synced to the canonical MO2 tool target.
- Daemon entrypoint: `ModOrganizer.exe -p Default run -e OpenCodeVfsLauncher -a "..."`.

**Phase 7 status statement**

- After 7C, Phase 7 is honestly closed at the daemon-surface level with rule-37 disclosures, not “fully completed with zero uncovered cases”.
- 7C closed the four non-concurrency 7B audit gaps, while the remaining two uncovered items are `C9` and fresh final-binary GUI non-regression.

### Expected Outcomes

- Long-tail custom actions become headless without turning the script system into the mainline product surface.
- Remaining GUI blockers are either removed, clearly deferred, or explicitly out of scope.

## Phase 8 - CLI Contract Maturity and Ergonomics

### Goal

Mature the now-broader CLI surface into a stable external contract with strong diagnostics, examples, and ergonomics.

### Task Specs

- Refine locator identity, path ergonomics, and response consistency across the enriched surface.
- Improve session handling, diagnostics, save/durability reporting, and concurrency semantics.
- Add examples and capability/version documentation once the command surface is broad enough to justify freezing those stories.

### Expected Outcomes

- The xEdit-side CLI surface is stable enough for external wrappers to depend on.
- Protocol concerns stay out of facade logic.

### Local Phase 8 closeout

Status: accepted at `contractVersion = 0.8`, dual-oracle independent semantic-acceptance review (`oracle-beta` + `oracle-gamma`) returned `PHASE_8_ACCEPTABLE`. C2 carried forward under rule 37 with new live architectural evidence; all other acceptance rows backed by real preserved artifacts under `.opencode/artifacts/phase8-cli-contract-maturity/`.

**What this round actually delivered**

- `contractVersion` conditionally bumped from `0.7` to `0.8`. The bump is gated on the new normative failure-message guarantee landing; spec criteria in `docs/plans/2026-05-08-xedit-phase-8-cli-contract-maturity-and-ergonomics-design.md` honored byte-for-byte.
- `supports.scripts.execution` gained adjacent descriptors `overlapPolicy = "single-process-single-runner"`, `busyHolders = ["daemon", "gui"]`, `failureMessagesOnError = true`. `supports.jobs.kinds` preserved byte-for-byte from the Phase 6E freeze; full preserved-surface comparison enforced by harness.
- Failed lifecycle-bearing `scripts.run` responses now expose `error.details.messages` (ordered string array, host emission order) and `error.details.messagesTruncated` (boolean, set when host capture budget clipped or dropped entries). Frozen per-code `error.details` catalog covers `script_blocker_lint`, `script_busy`, `script_external_declaration_not_allowed`, `script_compile_error`, `script_timeout`, `script_statement_budget_exceeded`, `script_runtime_error`.
- GUI-held overlap fast-fail at the `scripts.run` request boundary: when `xeScriptExecutionGuard` is held by `gui`, the facade raises `script_busy` with `error.details.holder = "gui"` before script-ID canonicalization, storage reads, lint, or headless runner setup. This replaced the deep-overlap path that previously crashed inside `Vcl.Styles.Utils.SysControls`.
- `xeHeadlessRunScript` and `xeAutomationScriptsRun` now `Default`-initialize their `TxeHeadlessScriptRunResult` records so the busy early-exit cannot expose uninitialized ownership-bearing fields to cleanup code.
- Daemon `scripts.run` UX indicator landed in `xeMainForm.pas` (`BeginDaemonScriptIndicator` returning the previous `pnlClient.Enabled` snapshot, `EndDaemonScriptIndicator` taking that snapshot back as a parameter, lifecycle `AddMessage` lines bracketing the synchronous run, `pnlCancel.Update` forcing paint before the GUI thread freezes, and `wbForceTerminate := False` reset at the end so a queued click on the reused cancel surface cannot leak `True` into a later non-script long action).
- Tracked technical contract reference and five examples under `docs/notes/phase8-cli-contract/` (capabilities, sync `scripts.run` success, lifecycle-bearing failure with frozen `error.details`, busy/overlap, save/durability). All JSON fences source-linked to live artifacts and gated against drift by `check-phase8-docs.ps1`.
- Locator/path audit and restart-backed durability proof: six green audit rows under `audits/locator-durability-audit.md`, with a real `savedFilesPendingShutdown` case proved by closing the daemon, relaunching, and reading back the second-mutation record (`audits/save-pending-after-restart.json`).
- Live-witnessed C1 (GUI holds, daemon refused) with `c1-gui-holds-daemon-busy.response.json` showing `error.code = "script_busy"` and `error.details.holder = "gui"` cleanly returned, no AV.
- Live-witnessed C3 recovery and 8D fresh-final-binary GUI Apply Script success on the canonical MO2-managed `OpenCodeXEdit\xEdit.exe`. `gui-non-regression-001` (carried as not-covered from Phase 7C) is now retired with operator-evidenced proof.
- C2 (daemon holds, GUI refused) preserved under rule 37 with new live architectural evidence: the same-thread serve loop means the GUI message pump is fully frozen for the duration of `scripts.run`, so an operator click cannot reach the GUI-side guard-acquire boundary inside that window. Disclosure at `manual-gui-closeout/c2-disclosure.txt`.

**What is now known**

- The pre-Phase-8 overlap path crashed reproducibly during a true GUI-held overlap with an Access Violation inside `Vcl.Styles.Utils.SysControls`. Root cause was a combination of uninitialized busy-result record fields and the daemon serve loop descending too deeply into request execution while the GUI was actively pumping messages from inside `PerformLongAction`. The Phase 8 fix is structural: refuse `scripts.run` at the request boundary when `gui` already holds the guard, plus default-initialize the result record, plus narrow the busy/refusal cleanup path so it cannot interleave with GUI script teardown.
- The daemon `TTimer` runs on the GUI thread, so daemon `scripts.run` execution is synchronous on the GUI thread and freezes the message pump for the duration of the script. This is fundamental to the current architecture and not changeable within Phase 8 scope. C2 (daemon-held → GUI refused) is therefore architecturally not operator-witnessable; the shared script guard remains the canonical mutual-exclusion authority and provides correct refusal semantics in code, but the GUI-side click cannot reach the guard-acquire boundary while the daemon holds it.
- The reused `pnlCancel` surface is safe as a busy indicator only; capabilities advertise `supports.scripts.execution.cancelable = false`. The implementation forces a paint via `pnlCancel.Update` before the synchronous run starts so the indicator is visible during the freeze, restores `pnlClient.Enabled` from a stack-local snapshot (no shared form field), and explicitly resets `wbForceTerminate := False` at teardown.
- The `0.8` capability surface is now byte-for-byte snapshotted at `snapshots/capabilities-0.8.json` and continuously compared against the live emitter via the harness. Adding fields under `supports.*` is allowed only as adjacent descriptors that do not mutate `supports.jobs.kinds`.
- The lifecycle-bearing failure-message guarantee is honest about the host capture budget: `messagesTruncated = true` is set when the in-process budget clipped a message or dropped one outright; the exact cap is implementation-defined and not part of the wire contract.

**What later phases should do differently**

- Phase 9 should treat `0.8` as the frozen public wrapper-facing contract. Any field rename, removal, or semantic narrowing is a breaking change requiring an explicit major bump and documented downgrade plan. Adding new fields stays additive and clients are required to ignore unknown keys.
- True async or cancelable `scripts.run` is out of scope for the current architecture. Anyone proposing it must accept that it requires moving daemon script execution off the GUI thread (worker thread + interlocked guard), and must re-derive the C2 acceptance row from scratch under the new model.
- `wbForceTerminate` is process-wide; any new long-action seam that reuses `pnlCancel` or otherwise depends on `wbForceTerminate` must reset it in `finally` to prevent leak into unrelated subsequent long actions. The Phase 8 daemon UX indicator's reset is the canonical pattern.
- New examples in `docs/notes/phase8-cli-contract/examples/` must remain source-linked to a real preserved artifact under `.opencode/artifacts/phase8-cli-contract-maturity/` and pass `check-phase8-docs.ps1`. The harness now forbids the previous "interim pre-Task-6 example" placeholder text from re-entering `04-busy-overlap.md`.
- Future overlap or concurrency expansions should explicitly distinguish "what the shared `xeScriptExecutionGuard` says in code" from "what an operator can witness in this same-thread architecture". Both must be true to claim a live-exercisable contract; same-thread architecture only guarantees the former.


## Phase 9 - Upstream Hardening

### Goal

Prepare the subsystem for serious upstream discussion and long-term maintenance.

### Task Specs

- Reduce unnecessary legacy touch points.
- Improve documentation, examples, and review notes.
- Clarify compatibility/version support expectations.
- Package the contribution in a way that makes the new subsystem easy to audit.

### Expected Outcomes

- The work reads like a contained engineering contribution instead of a local integration experiment.
- Upstream reviewers can evaluate the subsystem on clear boundaries and trade-offs.

### Local Phase 9 closeout

Status: local closeout accepted. Final implementation/harness summary at `.opencode/artifacts/phase9-upstream-hardening/run-phase9-verification.json` is GREEN, and the dual final reviewer pass (`oracle-beta` + `oracle-gamma`) returned PASS for local closeout. Final build SHA256 matches the canonical MO2 tool target: `4E7FD5F3186A1F22CD8D2C0872A45574FA2DAF3FE0351665A666D731F67598C0` for both `Build\xEdit.exe` and `...\Tools\OpenCodeXEdit\xEdit.exe`.

**What this round actually delivered**

- Public contract docs were renamed and reshaped into `docs/notes/automation-contract/`: `ARCHITECTURE.md` now carries the same-thread / GUI-message-pump rationale and the verbatim C2 disclosure; `COMPATIBILITY.md` defines frozen vs additive surfaces at `0.9`; `VERIFICATION.md` summarizes the artifact-backed proof; `contract-reference.md` now includes the `0.9` consent-gate section; `examples/01-capabilities.md` was refreshed to the `0.9` flag-absent capability snapshot; `examples/06-consent-required.md` documents the new request-validation refusal shape.
- Product code landed the daemon-side `-IKnowWhatImDoing` contract at `0.9`: `xeAutomationMutationPolicyConsentSatisfied` now gates every mutating daemon command at the request boundary, `xeAutomationErrors.pas` now defines `consent_required`, `xeAutomationCommandsSystem.pas` now reports `contractVersion = 0.9` plus `supports.scripts.execution.iKnowWhatImDoing`, and the paired green build proved the `0.8` surface survived additively.
- Comment / log-surface hygiene is substantially cleaner: Phase/task vocabulary was stripped from the Phase 7/8 automation units, the serve-startup targeted-fixture diagnostic block was removed from `xeMainForm.pas`, `MO2 runs` wording was neutralized to `VFS-overlay environments`, the useful daemon `scripts.run` UX indicator messages were retained, and the GUI Apply Script warning flow around `xeMainForm.pas:5867-5889` was proved unchanged.
- Local tree hygiene now enforces the publication split: `.gitignore` and `git rm --cached` remove local-only workflow surfaces (`ROADMAP.md`, `docs/plans/`, historical phase notes, `.opencode/`) from the intended publication payload, while `README.md` now has an explicit `Automation Mode (Daemon)` section linking readers to the new contract docs.
- The local closeout evidence set is complete for the meaningful rows: flag-absent capability snapshot, flag-present capability snapshot, `consent_required` matrix, read-only non-regression, row 18 real `script_runtime_error` proof, row 15 GUI-flow unchanged proof, sibling-flag coverage audit, self-sufficiency reviewer PASS, and a full `0.9` locator/durability rerun proving root locator, nested path, load-order lookup, immediate save, pending-shutdown save, and post-restart readback.

**What was previously unknown but is now known**

- For publication-style closeout, a repo-wide `MO2`/phase-vocabulary grep is too blunt. The meaningful scan scope is the **Phase 9 publication payload** (README + `docs/notes/automation-contract/**` + Phase-9-touched automation units and project files), not the whole historical xEdit fork. That narrowing is now explicit inside `Tools/Automation/run-phase9-verification.ps1`.
- Provenance `source-link` comments into `.opencode/artifacts/` are compatible with a clone-readable public docs surface only if they are treated as **optional local provenance**, not as hard requirements for a fresh clone. `check-automation-contract-docs.ps1` now enforces in-root provenance when present but no longer hard-fails when the local artifact tree is absent.
- `0.x` contract growth is cleaner when early refusals use a **new request-validation-tier code** instead of overloading lifecycle-bearing script codes. `consent_required` now demonstrates that pattern: it gates before any lifecycle starts, while `script_runtime_error` remains reserved for actual execution failures. This is the accepted template for future pre-execution refusals.
- A missed late `0.8` post-9C runtime snapshot does not automatically invalidate closeout if the phase's edits are mechanically provable as non-semantic (comments, log strings, fixture literals only). `row06-structural-proof.md` is the accepted substitute in this specific case, and the later `0.9` additive-only proof plus green build preserve the integrity of that substitution.

**What later phases should do differently**

- Treat `0.9` as the new lower bound. Later phases must preserve: `supports.jobs.kinds` membership/order, the 7 lifecycle `error.details` schemas, `supports.scripts.execution.iKnowWhatImDoing`, and the `consent_required` `{ deniedReason, commandName, mutationCategory }` shape. Any future early refusal should follow the same request-validation-tier pattern rather than overloading lifecycle codes.
- If a future phase changes clone-visible docs or publication tooling, scope the forbidden-token scan to the intended publication payload **from the start** and make that scope explicit in the harness, instead of retrofitting it late in closeout.
- If a future phase wants pure runtime proof of a pre/post capability surface, capture both snapshots before the version bump lands. The structural-proof fallback used here is honest and sufficient for this non-semantic cleanup phase, but it should remain the exception rather than the default.
- Any future async / worker-thread `scripts.run` design is a `1.x` boundary, not a `0.x` additive tweak. `ARCHITECTURE.md` and `COMPATIBILITY.md` now commit the project to that distinction.

## Phase 10 - Semantic E2E Freeze Gate

### Goal

Run three real-material semantic E2E task families against the MO2-backed Fallout 4 harness, prove the current xEdit-side surface on genuine modding workflows, and decide whether the local branch can freeze at `1.0`.

### Task Specs

- Lock exact Task A / Task B / Task C materials, answer surfaces, and refusal rules.
- Execute one solver at a time against the MO2-backed daemon with preserved request/response/readback/disk/restart artifacts.
- If a real defect appears, stop, docket it, repair systemically, rerun from a clean baseline, and only then resume the freeze gate.
- Close with a phase-level PASS decision before making any `1.0` recommendation.

### Expected Outcomes

- The local branch can truthfully say whether the xEdit-side subsystem is ready for a scoped `1.0` freeze.
- Later work inherits explicit known limits and does not confuse accepted concerns with unresolved blockers.

### Local Phase 10 closeout

Status: local closeout accepted at `1.0` scope for the xEdit-side automation surface only. Phase 10 final report is `.opencode/artifacts/phase10-semantic-e2e/report/phase10-final-report.md`. Current canonical build hash matches the MO2 tool target after closeout sync: `4ADCF3350E083A9635926C939F812176FA0983C3B4E0F9EBCE042E03766FF8A2` in both `Build\xEdit.exe` and `...\Tools\OpenCodeXEdit\xEdit.exe` (`.opencode/artifacts/phase10-semantic-e2e/report/closeout-binary-sync.md`).

**What this round actually delivered**

- Task A proved a real conflict-resolution patch workflow on locked Munitions / `.223 Revolver REDUX` materials. The saved solver patch `Phase10_TaskA_Munitions223Patch.esp` survived restart, forwarded `.223 Revolver` ammo to `Munitions_Ammo223Caliber [AMMO:FE000FAA]`, preserved the source plugin unchanged, and exercised a negative malformed-locator branch non-mutatingly.
- Task B proved a real bridge-patch slice over StG-44 distribution/attachment/naming seams. `Phase10_TaskB_StG44PeerBridge.esp` survived restart with minimal masters, exercised all five locked LVLI hooks, the required OMOD/mod-collection families, INNR/naming/sorter readback, and a negative nonexistent-record linkage branch.
- Task C proved the release-prep family with dual semantics: YES-GO cleaning on `DLCNukaWorld.esm` through a staged writable copy plus restart revalidation, and NO-GO pre-load canonicalization refusal for `unofficial fallout 4 patch.esp` with exact accepted wording and no mutation/output/save. The truthful Task C result is `DONE_WITH_CONCERNS`, not perfect-clean.
- Phase 10 exposed one real product defect: master-record override resolution could falsely report `state_conflict` and then misroute later mutation attempts back into `Fallout4.esm`. The fix introduced strict target-file-owned resolution on the mutation/existence seams, preserved read-side compatibility, green-reproduced the isolated failure, and turned the full Task B rerun GREEN.
- The closeout package now includes material locks, work orders, accepted-vs-historical evidence manifests, multi-lens oracle gate review notes, a final report, and a final binary-sync note. The canonical MO2 tool target was resynced to the trusted repo build before the freeze claim.

**What was previously unknown but is now known**

- Real-material semantic E2E is now proven across three genuinely different workflow families: conflict-resolution patching, bridge patching, and release-prep judgment. The surface is no longer only a command catalog or harness story.
- The old read-side fallback in record resolution was too permissive for mutation/existence seams. A workflow that starts from a master-reachable record can look valid in readback while still being semantically wrong for patch ownership. That is now a product rule, not a suspicion.
- LOOT dirty metadata counts and xEdit job-level planned/applied counts are not interchangeable proof surfaces even when CRC matches. For `DLCNukaWorld.esm`, CRC `0x43D25C56` still anchored the baseline, while the `193` ITM LOOT surface and the `235` ITM xEdit surface had to be reported honestly as an accepted divergence rather than forced into fake agreement.
- Deleted NAVM findings that xEdit itself marks as `deleted_navmesh` / non-auto-cleanable / skipped are a distinct semantic category from unresolved actionable cleaning work. They can support a truthful `DONE_WITH_CONCERNS` release-prep result without blocking the phase.
- For the current UFO4P install, missing CC/NG masters are a local runtime caveat, not the accepted NO-GO semantic proof path. The accepted proof path is pre-load canonicalization refusal with exact wording and no mutation.
- Final closeout on this repo still depends on runtime-discipline details as much as source correctness: use LiteDebug, sync the MO2 tool target, enter through MO2, preserve short request/response calls, and keep mutable outputs in overlays/staging rather than `Stock Game\Fallout 4\Data`.

**What later phases should do differently**

- Treat `1.0` as the new local lower bound for the xEdit-side surface. New work should start from the accepted Task A/B/C semantic evidence rather than from earlier command-level floors.
- If a later phase touches mutation/existence routing again, keep strict target-file-owned resolution on the write-bearing seams and re-derive the RED/green proof before widening any fallback behavior.
- If a later phase wants to tighten release-prep proof, treat three follow-ups as optional improvement work rather than hidden blockers: reconcile xEdit/LOOT ITM-count divergence semantics, improve any job-layer refusal symmetry that is worth exposing publicly, and decide whether deleted NAVM accepted-concern handling should become a more formal contract story.
- Preserve accepted-vs-historical artifact separation early. Summary files should point at the current accepted evidence surface; stale diagnostic summaries must be corrected or explicitly marked historical before final review.
- Keep the MO2-tool-target sync as part of closeout whenever the repo build is the intended runtime binary. The freeze claim should never silently rely on a stale MO2 executable.

## Phase 11 - Navigate-to-Record

### Goal

Add a bounded headless navigation primitive that can move the loaded xEdit UI/session to a requested record root and return semantic readback proving the selected target.

### Local Phase 11 closeout

Status: local closeout accepted as `DONE_WITH_CONCERNS`. The command semantics are green on the accepted MO2-backed evidence set; the blocker/modal probe remains an explicit `NOT-COVERED` limitation, not a green claim. Semantic acceptance summary: `.opencode/artifacts/phase11-navigate-to-record/summary/semantic-acceptance-phase11.md`.

**What this round actually delivered**

- Implemented and verified `session.navigate_to_record` on the loaded daemon path for record-root locators.
- Verified the positive case against the canonical MO2-managed runtime target `D:\awesome-bgs-mod-master\.artifacts\mo2\Stock Game\Fallout 4\Tools\OpenCodeXEdit\xEdit.exe`, launched with `-FO4`, `-IKnowWhatImDoing`, and `-automation-serve`.
- Positive proof selected `Fallout4.esm:000000C1` / `KYWD` / `SplineLink` and returned matching `targetRecord`, `activeRecord`, `focusedRecord`, and `treeSelection` readback.
- Verified missing-record failure as `record_not_found` and non-empty child-path input as `invalid_request`.
- Verified navigation as non-mutating: dirty-state readback stayed clean before and after the navigate call.
- Preserved valid LiteDebug build evidence at `.opencode/artifacts/phase11-navigate-to-record/build/xEdit-task3-reviewfix-20260513-151540.err`, showing `Building xEdit.dproj (LiteDebug, Win32)`, LiteDebug output paths, and `Success`.
- No git commit was created for this local closeout.

**What was previously unknown but is now known**

- `session.navigate_to_record` can produce useful semantic readback from the real xEdit UI/session state: active, focused, and tree-selection records can all be checked against the requested locator.
- The safe first contract is record-root navigation only. Non-empty element paths should stay rejected as `invalid_request` until a separate element-navigation design exists.
- Navigation itself is non-mutating in the accepted harness: the loaded dirty-state surface stayed clean before and after selection.
- The blocker/modal refusal case is still not proven. Without deterministic GUI blocker setup through Windows automation or product-owned test hooks, the honest status is `NOT-COVERED`, even though ordinary no-blocker navigation is green.

**What later phases should do differently**

- Treat `session.navigate_to_record` as available for record-root positioning only; do not infer covered element-path navigation or dialog-button automation from this phase.
- Any future blocker/modal acceptance row must first provide a deterministic way to create and observe the blocker condition, then prove the command refuses or reports it semantically. Do not lower this to a no-blocker happy-path rerun.
- Keep navigation verification tied to semantic readback (`targetRecord`, `activeRecord`, `focusedRecord`, `treeSelection`) and dirty-state before/after checks rather than response-envelope success alone.
- If later phases add element-level navigation, they should design it as a distinct contract with its own locator/readback matrix instead of widening `session.navigate_to_record` implicitly.

## Out of Scope For Now

- Reviving the older external hook path as part of this roadmap.
- Building an MCP server/adapter inside this repo.
- Designing the complete final API catalog before the skeleton exists.
- Chasing automatic exposure of all internal Pascal functions.
- Spreading automation-specific edits throughout unrelated xEdit units.

## Updating This Roadmap

Phase 0 through Phase 10 are now historical ledger entries. Do not go back and re-shape those older sections just to make the structure look cleaner.

From Phase 11 onward, this roadmap is maintained as an append-only local truth surface:

- when a new implementation round is accepted, append the next real phase section (`Phase 12`, `Phase 13`, and so on) after the latest accepted phase;
- do not pre-create placeholder future phases;
- do not pretend there is still a single preplanned roadmap direction that can authoritatively predict later work.

Each new appended phase should answer exactly three questions:

- what was actually completed;
- what was previously unknown but is now known;
- what those new facts require later phases to do differently.

Keep product-contract facts, semantic acceptance outcomes, and accepted limitations here. Keep demo/recording mechanics, one-off operator narration, transient PIDs, and similar local execution noise in `.opencode/artifacts/...`, not in the roadmap.

This keeps the roadmap anchored to accepted current truth instead of turning it into either historical churn or fake future planning.
