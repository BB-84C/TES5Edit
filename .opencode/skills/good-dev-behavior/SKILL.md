---
name: good-dev-behavior
description: Use when working in this repo and creating local artifacts, preparing upstream-facing code changes, or closing an implementation round so disposable files stay quarantined, non-obvious code gets review-friendly comments, and ROADMAP.md is refreshed with completed work and newly known constraints.
---

# Good Dev Behavior

## Overview

This skill keeps local experimentation from bleeding into the upstreamable xEdit worktree.

Core rule: if a file is disposable, local-only, or unrelated to the approved automation subsystem, it must not live as visible clutter in the repo root.

## When to Use

Use this when:

- creating throwaway scripts, logs, captures, schema drafts, or request/response samples
- running tests or diagnostics that generate local artifacts
- running local build verification for `xEdit.dproj` in this repo
- running local runtime verification of xEdit automation in this repo
- designing, implementing, or closing any xEdit automation phase that adds new user-visible behavior or command arguments
- finding leftover files from older experiments
- deciding whether a new file belongs in version control or in a local ignored area
- finishing an implementation round and deciding whether local roadmap/planning docs need to be updated

Do not use this skill as a substitute for product design. It governs repo hygiene and agent behavior.

## Rules

1. Classify every new file before creating it: committed project asset or local artifact.
2. Local artifacts go under `.opencode/artifacts/<task>/...`, not in the repo root.
3. Repo-root scratch folders such as `tmp`, `.tmp`, `artifacts`, `scratch`, ad hoc `scripts`, and loose capture files are not acceptable destinations for disposable work, even if they are already ignored.
4. Docs worth keeping go in the real docs tree, usually `docs/notes/` or `docs/plans/`.
5. Helper scripts worth keeping in the project go in an intentional tracked location such as `Tools/Automation/` or another feature directory chosen for the workstream, not in the repo root.
6. If a file does not belong to upstream xEdit and is unrelated to the current automation subsystem plan, quarantine it under `.opencode/artifacts/legacy/` or add a narrow `.gitignore` rule immediately in the same session. Do not defer this cleanup.
7. If you are unsure whether a file is worth keeping, default to local artifact storage first; only promote it into the tracked tree when it has clear project value.
8. Upstream-facing code must carry clear, review-friendly comments at every non-obvious seam introduced by the change, especially lifecycle/order-of-execution decisions, registration or initialization wiring, request parsing and validation boundaries, protocol/error-shape decisions, and special-case behavior added for automation.
9. Do not treat "the code looks readable to me" as sufficient. If a reviewer would need to reconstruct why a branch exists, why a startup path runs early, why a unit self-registers, or why an error path is shaped a certain way, add a short comment that explains the why.
10. When a change introduces multiple non-obvious seams, comment each seam that carries distinct reviewer-facing intent. One comment at the first seam does not cover the rest.
11. Local planning and agent-assistance files such as `ROADMAP.md`, repo-local `.opencode/` skills, and working docs under `docs/` are for local workflow only and must not be included in upstream PR commits.
12. After each implementation round, update `ROADMAP.md` locally so it records three things: what was completed, which earlier unknowns became known, and how those new facts change the later phases.
13. Do not wait for the user to ask for a roadmap refresh after implementation. Treat roadmap maintenance as part of closing the round.
14. For local non-interactive builds of `xEdit.dproj` in this repo, use exactly the background `Start-Process` pattern with `bds.exe -b <project.dproj>` as the default and first-choice build path. Do not let bash block waiting on the process in the foreground.
15. On this machine for this repo, use the `LiteDebug` build configuration for trustworthy local binary output. Treat `Release` as a known false-build path that can report success while producing no usable fresh executable.
15a. A build log that says `Building xEdit.dproj (Debug, Win32)` or `Release` is not valid verification evidence for this repo, even if it ends with `Success`. Verification evidence must show `Building xEdit.dproj (LiteDebug, Win32)` and LiteDebug output paths such as `Temp\xEdit\Win32\LiteDebug` before any runtime evidence may be trusted.
15b. For this local workstream, `bds.exe -b` uses the active/default project configuration, so keeping `xEdit.dproj`'s active/default config on `LiteDebug` is acceptable when needed for trustworthy local verification. Do not churn unrelated project metadata or build-configuration ordering; enforce LiteDebug by checking the build log and rejecting non-LiteDebug artifacts.
16. Do not fall back to direct `dcc32`/`dcc64`, plain `msbuild`, or `rsvars.bat && msbuild` unless `bds.exe` is unavailable or the user explicitly asks for a different build route.
17. If `bds.exe` is not already on `PATH`, locate it first from the installed Embarcadero paths and then use that executable explicitly.
17a. On this machine, when `bds.exe -b` fails, or when the captured stdout/stderr evidence is incomplete or ambiguous, inspect the repo-root `xEdit.err` file before trying any alternate build command. Treat `xEdit.err` as the canonical compiler transcript for root-cause triage unless proved otherwise.
17b. After a failed or ambiguous `bds.exe -b` run, do not thrash through extra build commands just to hunt for output. First read `xEdit.err`, identify the actual compiler blocker, and only then decide whether the issue is source, capture plumbing, or build-route selection.
17c. If a bounded worker subagent such as `@fixer` runs the canonical build during implementation, it must still follow the same rule: first failed-build diagnosis is `xEdit.err`, not improvised alternate build commands. If diagnosis stops being mechanical, keep control in the main session.
18. For local runtime verification of automation commands, do not launch an arbitrary xEdit instance directly from the repo or from a random Fallout 4 installation. Use the portable MO2 instance rooted at `B:\WastelandBlues 2.0` and its broker-backed launcher client so xEdit runs under the intended Fallout 4 VFS and profile.
19. `B:\WastelandBlues 2.0\Stock Game\Fallout 4\Data\` is untouchable local game-data state. Do not copy files into it, delete from it, rewrite files under it, or treat it as a disposable sandbox unless the user explicitly overrides this rule in the current conversation.
20. Any agent that believes it needs to change “game installation” Data content must implement that change as an MO2 mod overlay instead: create a dedicated subfolder under `B:\WastelandBlues 2.0\mods\<mod-name>\...`, place the intended Data changes there, and let MO2 VFS project them into the runtime view. Do not mutate `Stock Game\Fallout 4\Data` directly.
21. When a harness or helper needs writable plugin fixtures, generated files, config overrides, or game-data substitutions, create them in a dedicated MO2 mod folder (or another non-Data runtime root the user explicitly approved), not under `Stock Game\Fallout 4\Data`.
22. For this FO4 MO2-backed workstream, after a trusted LiteDebug build, syncing the fresh executable into `B:\WastelandBlues 2.0\Stock Game\Fallout 4\Tools\FO4Edit\FO4Edit.exe` is explicitly allowed. This tool-directory sync is the narrow exception to the Stock Game write caution; it does not permit any writes under `Stock Game\Fallout 4\Data`.
23. Runtime verification must treat `B:\WastelandBlues 2.0\Stock Game\Fallout 4\Tools\FO4Edit\FO4Edit.exe` as the canonical xEdit target. Do not use `D:\TES5Edit-contrib\Build\xEdit.exe` as the runtime target, because that bypass reintroduces harness drift.
24. The canonical entrypoint is `D:\awesome-bgs-mod-master\tools\mo2-vfs-launcher\xedit-client.ps1 process launch`. The WastelandBlues MO2 GUI must already be running; the client delegates to the Mo2AgentControl `launch.start` broker inside that GUI.
25. Do not use MO2 CLI `run` mode for this instance lineage. It crashes and was never the surviving harness client's launch path. Do not substitute a raw `ModOrganizer.exe ... run -e ...` command for the broker client.
26. Preserve the canonical launch contract exactly: `--launcher-path "B:\WastelandBlues 2.0\Stock Game\Fallout 4\Tools\FO4Edit\FO4Edit.exe" --game-mode Fallout4 --mo2-root "B:\WastelandBlues 2.0" --mo-profile Default [--plugins-file <fixture.txt>] --data-path "B:\WastelandBlues 2.0\Stock Game\Fallout 4\Data" --i-know-what-im-doing 1`.
27. The client auto-appends `-automation-serve` and the session `-P:` plugins file. `--data-path` must end at `\Data`; the client supplies the trailing backslash. Use `--plugins-file` for an artifact-local fixture load order; otherwise the selected profile's load order is used.
28. Stop with `xedit-client.ps1 process stop --xedit-pid <pid>` and issue requests with `xedit-client.ps1 automation call ...`. `$env:BGS_MO2_ROOT` may override the MO2 root, but it is currently unset and the explicit `--mo2-root` remains canonical.
29. The first xEdit run after an executable swap may spend minutes rebuilding cache. Treat that as expected startup cost, not as proof of a containment breach.
30. Before claiming broad automation command coverage, dispatch `@explorer` for a read-only boundary/use-test matrix over the affected command surface. Treat the explorer result as planning only, not execution evidence.
31. When the runtime verification work is bounded, mechanical, and already specified (fixed harness, known command shape, known artifact directory, and machine-checkable pass/fail criteria), dispatch `@laborer` to execute it and collect request/response artifacts under `.opencode/artifacts/<task>/...`. The orchestrator owns routing, constraints, light summary verification, and final claims; it should not spend high-cost attention on deterministic verification loops.
32. Do not send `@laborer` into unclear harness design, new debugging, architectural judgment, or failing-runtime diagnosis. If the verification path is ambiguous or failures require root-cause analysis, keep control in the orchestrator and use `@oracle` for review/debugging guidance when needed.
33. For every future xEdit automation phase that adds functionality or changes behavior, design semantic end-to-end acceptance before or during implementation planning. Start from the user's intended effect in xEdit terms, enumerate meaningful argument combinations and negative cases, and define the concrete readback that proves the intended file, master, record, conflict, deleted, saved, or reloaded state.
34. Spec-compliance review, code-quality review, build success, and a harness/script returning pass are never sufficient completion evidence by themselves. They are support signals only. A phase is not complete until semantic E2E verification has actually run through the MO2-backed xEdit path and the outputs/readbacks have been inspected for whether they match the user's design intent.
35. Semantic E2E verification must include a reviewer subagent pass over the preserved request/response/readback artifacts. The reviewer must check meaning, not style: whether each command and important argument combination accomplished the intended xEdit result, whether failures were non-mutating where intended, and whether save/reload behavior still matches the design. Treat this as a semantic acceptance audit, not as another spec/code-quality review.
36. When semantic E2E finds a false-positive harness, missing readback, or ambiguous evidence, record the RED result under `.opencode/artifacts/<task>/...`, fix the product or harness root cause, rerun the real MO2-backed verification, and only then update `ROADMAP.md` with the newly learned constraint.
37. When semantic E2E hits an abnormal fixture situation, do not immediately weaken the assertion, declare NOT-COVERED, or accept a response-envelope pass. First use the already-available xEdit automation CLI commands to build the right semantic scene: create or prepare files, add required masters, create/copy records, mark/delete records, mutate elements, save/restart, and read back the resulting xEdit state. It is acceptable to use later-phase commands as setup helpers when they already exist, as long as the target assertion remains the current phase's behavior. Only mark NOT-COVERED after those setup attempts are impossible or still cannot prove the intended xEdit state, and preserve every setup/readback artifact.

## Quick Reference

| File type | Location | Track it? |
| --- | --- | --- |
| Throwaway scripts, logs, captures, raw JSON, scratch notes | `.opencode/artifacts/<task>/...` | No |
| Local planning docs and transcripts | `ROADMAP.md`, `docs/notes/`, or `docs/plans/` | No |
| Durable project helper scripts | `Tools/Automation/` or another intentional feature directory | Yes |
| Old unrelated local leftovers | `.opencode/artifacts/legacy/` or a narrow ignored path | No |

## Phase 13 Discoveries (2026-06-08)

### Build

Canonical command (Community Edition compatible):

```powershell
bds.exe -b xEdit.dproj
```

Do NOT pass `/target:`, `/p:config=...`, or `/p:platform=...` MSBuild flags — those trigger Enterprise license-required code paths and pop the "need new license" dialog.

The dproj `<Platform Condition>` default selects Win32 vs Win64. For symmetric release builds:

1. Edit dproj default to Win32, build, preserve evidence.
2. Edit dproj default to Win64, build, preserve evidence.
3. Restore dproj default to Win32, matching the FO4 harness steady state.

### MO2 Broker Launch

Keep the WastelandBlues MO2 GUI running and launch xEdit through its in-GUI Mo2AgentControl broker. The canonical client call is:

```powershell
pwsh -NoProfile -File D:\awesome-bgs-mod-master\tools\mo2-vfs-launcher\xedit-client.ps1 process launch `
  --launcher-path "B:\WastelandBlues 2.0\Stock Game\Fallout 4\Tools\FO4Edit\FO4Edit.exe" `
  --game-mode Fallout4 --mo2-root "B:\WastelandBlues 2.0" --mo-profile Default `
  [--plugins-file <fixture.txt>] --data-path "B:\WastelandBlues 2.0\Stock Game\Fallout 4\Data" `
  --i-know-what-im-doing 1
```

The old portable-harness `ModOrganizer.exe ... run -e ...` path is historical and is not valid for the WastelandBlues lineage. Do not kill another MO2 instance or improvise around the old global single-instance lock; the broker-backed client is the supported launch boundary.

### Daemon Shutdown

Automation harnesses that dirtied plugin state MUST call:

```json
{ "command": "session.save", "args": { "files": ["<dirty.esp>"] } }
```

before `Stop-Process` or `CloseMainWindow` on the daemon. Otherwise xEdit pops a "Save changed files" GUI dialog that blocks the harness. Verify post-save dirty state via `session.get_dirty_state` returning `dirty:false` before shutdown.

### `records.apply_filter`

Takes plural array args: `files: [...]`, `signatures: [...]`. Not singular `file`/`signature`.

For local `xEdit.dproj` build verification, prefer a command shape like:

```powershell
Start-Process "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\bds.exe" -ArgumentList @('-b', 'D:\TES5Edit-contrib\xEdit.dproj')
```

Use this repo's actual project path. If `bds.exe` lives elsewhere, locate it first and substitute the discovered path.

This is the established non-interactive build path for this machine and repo. Treat other command-line build routes as fallback-only. For actual verification on this machine, the preserved build log must show `Building xEdit.dproj (LiteDebug, Win32)`. If it shows `Debug` or `Release`, record RED/invalid-build evidence and do not use that binary for runtime verification.

If a `bds.exe -b` run fails or the redirected stderr/stdout logs are suspiciously empty, open `D:\TES5Edit-contrib\xEdit.err` next. On this machine that file is often the real compiler transcript, including the actionable `dcc32` error/fatal lines. Do not switch to `msbuild`, `dcc32`, or random alternative command shapes before checking `xEdit.err`.

For local runtime verification after the build succeeds, use this harness sequence:

1. do not write to `B:\WastelandBlues 2.0\Stock Game\Fallout 4\Data\...`; if a runtime change would affect game Data, package it as an MO2 mod overlay under `B:\WastelandBlues 2.0\mods\<mod-name>\...`
2. after a trusted LiteDebug build, sync the fresh executable into `B:\WastelandBlues 2.0\Stock Game\Fallout 4\Tools\FO4Edit\FO4Edit.exe`; `D:\TES5Edit-contrib\Build\xEdit.exe` is not an acceptable runtime target for this FO4 MO2-backed verification path
3. with the WastelandBlues MO2 GUI running, call `xedit-client.ps1 process launch` with the canonical launcher, game mode, MO2 root/profile, explicit Data path, mutation-consent flag, and optional artifact-local plugins file shown above
4. send automation requests against that MO2-backed daemon session
5. when coverage is broad or edge-heavy, first use `@explorer` only to map the missing boundary/use cases
6. if the execution path is fixed and the expected checks are machine-readable, dispatch `@laborer` to run the known verification harness and preserve artifacts; the orchestrator then reads the summary and makes the final claim
7. before any phase-complete claim, run a semantic acceptance audit over those artifacts: map each user-intended behavior to actual CLI inputs plus xEdit readback, inspect every important argument combination and negative case, and have a reviewer subagent independently check that the outputs make sense semantically

This avoids drifting onto the wrong xEdit instance, the wrong Fallout 4 install, or a noisy load order.

For the broker client, remember:

1. the WastelandBlues MO2 GUI is a prerequisite; the client does not replace it
2. `process launch` delegates to the Mo2AgentControl `launch.start` broker and auto-appends `-automation-serve` plus the session `-P:` file
3. `--data-path` is mandatory because registry discovery would select Steam Data
4. `--plugins-file` is optional; without it, the selected profile's full load order is used
5. `process stop --xedit-pid <pid>` and `automation call ...` are the lifecycle and request surfaces

Use this launch shape:

```powershell
pwsh -NoProfile -File D:\awesome-bgs-mod-master\tools\mo2-vfs-launcher\xedit-client.ps1 process launch `
  --launcher-path "B:\WastelandBlues 2.0\Stock Game\Fallout 4\Tools\FO4Edit\FO4Edit.exe" `
  --game-mode Fallout4 --mo2-root "B:\WastelandBlues 2.0" --mo-profile Default `
  [--plugins-file <fixture.txt>] --data-path "B:\WastelandBlues 2.0\Stock Game\Fallout 4\Data" `
  --i-know-what-im-doing 1
```

Avoid patterns like:

```powershell
# Do not invoke WastelandBlues through ModOrganizer.exe CLI run mode.
```

When updating `ROADMAP.md` after implementation, include:

- what this round actually delivered
- what was previously unknown but is now known from real implementation or verification
- what later phases should now do differently because of that knowledge
- any semantic E2E gaps or false-positive harness assumptions discovered during acceptance

## Semantic E2E Acceptance Standard

Use this standard for future phase design, implementation, and closeout:

1. Convert each requested feature into the real xEdit effect the user wants, not just an API shape. Examples: a file exists with the expected flags and masters; a copied override has the intended record identity and children; a failed mutation leaves the target unchanged; `session.save` survives fresh daemon reload.
2. Build the acceptance matrix from that intent: positive paths, meaningful argument combinations, malformed/unsupported combinations, protected-target cases, idempotent repeats, non-mutating failures, and save/reload behavior when persistence is part of the claim.
3. Preserve the exact request/response/readback artifacts under `.opencode/artifacts/<task>/...` so someone can audit what actually ran.
4. Inspect the xEdit-state readback, not only the command envelope. `ok:true`, a green script, or a passing review does not prove the feature did the right thing.
5. Dispatch a reviewer subagent for semantic acceptance after the run. Give it the design intent, the matrix, and artifact paths; ask it to judge whether the observed xEdit state matches the user's intent and to identify false-positive harness checks.
6. If the audit discovers missing evidence, first make the harness go RED for the missing semantic assertion when practical, then use existing xEdit automation CLI capabilities to construct a suitable test fixture before changing expectations. Examples: use `files.create` / `files.add_required_masters` for plugin setup, `records.create` / `records.copy_into` for record identity and override fixtures, `records.mark_deleted` for current-state conflict fixtures, `elements.*` commands for mutation/no-mutation readbacks, and `session.save` plus fresh-daemon readback for persistence claims.
7. Mark a case NOT-COVERED only after fixture construction through existing CLI commands is not possible or xEdit lifecycle behavior still leaves the intended state unprovable. The NOT-COVERED reason must say what setup was attempted and point at preserved artifacts.

## Comment Standard

For upstream-facing code, comments are required around:

- pre-UI or pre-main-form execution paths
- initialization and self-registration seams
- request parsing and validation branches when malformed inputs are handled intentionally
- protocol request/response or error-shape decisions
- fail-fast branches and other special-case automation behavior

Under time pressure, do not collapse these into a single "architecture comment" if the change also introduces a separate validation or error-contract seam.

Comments should explain why the code is shaped that way, not restate syntax.

## Example

Bad:

- `D:\TES5Edit-contrib\.tmp\probe.ps1`
- `D:\TES5Edit-contrib\response.json`
- `D:\TES5Edit-contrib\debug-output.txt`

Good:

- `D:\TES5Edit-contrib\.opencode\artifacts\schema-probe\scripts\probe.ps1`
- `D:\TES5Edit-contrib\.opencode\artifacts\schema-probe\captures\response.json`
- `D:\TES5Edit-contrib\.opencode\artifacts\schema-probe\logs\debug-output.txt`

If `probe.ps1` becomes a real project tool, move it into a tracked location such as `Tools/Automation/` and document why it belongs there.

## Common Mistakes

- Creating a new root-level scratch folder because it is fast.
- Leaving unrelated local files visible because they might be useful later.
- Deferring `.gitignore` updates until the repo gets noisy.
- Using `tmp/` because it is already ignored.
- Treating one-off helper scripts as committed assets before they earn that status.
- Moving everything outside the repo when the work still needs a discoverable local home in this workspace.
- Assuming one short comment near the first seam is enough for the whole change.
- Omitting comments from non-obvious startup, registration, or error-handling paths because the author already understands them.
- Treating request parsing and error-envelope code as self-explanatory just because exception names are readable.
- Treating `ROADMAP.md` as a static one-time planning document instead of a local anti-drift record that should be refreshed after implementation rounds.
- Trusting `dcc32`/`dcc64` or plain `msbuild` output for this repo after they have already shown false-green or license-blocked behavior on this machine.
- Choosing `rsvars.bat && msbuild` out of habit after this repo already established `bds.exe -b` as the primary non-interactive build path.
- Waiting in bash for `bds.exe` to exit instead of starting it in the background and using GUI/blocker handling plus artifact checks.
- Assuming `Release` is a trustworthy verification config for this repo on this machine.
- Hitting a build failure or empty redirected log and then trying alternate build commands before opening `xEdit.err`.
- Launching runtime verification against an arbitrary local `xEdit.exe` instead of the MO2-managed harness.
- Touching or treating `B:\WastelandBlues 2.0\Stock Game\Fallout 4\Data\...` as disposable workspace state after the user explicitly forbade Data mutation.
- Applying a game-local change directly to the game tree instead of packaging it as a dedicated MO2 mod folder and letting VFS project it.
- Using MO2 CLI `run` mode instead of the broker-backed `xedit-client.ps1 process launch` path.
- Omitting the explicit WastelandBlues Data path and allowing registry discovery to select Steam Data.
- Forgetting that the WastelandBlues MO2 GUI must already be running before the broker client can launch xEdit.
- Saying `@explorer` ran xEdit CLI tests. `@explorer` is read-only planning/recon; runtime execution needs `@laborer` for bounded known-method chores or the orchestrator for unclear cases, plus preserved artifacts.
- Keeping fixed, deterministic runtime-verification loops in the main orchestrator after `@laborer` has enough context to run the harness safely.
- Sending `@laborer` to invent a new harness, debug a failing daemon, or make architecture decisions instead of using it for bounded execution.
- Treating spec-compliance review, code-quality review, or a script/harness pass as semantic acceptance.
- Designing a new phase without defining what each feature is supposed to accomplish in xEdit state and what readback proves it.
- Testing only happy-path command envelopes instead of meaningful argument combinations, negative cases, non-mutating failures, and save/reload semantics.
- Treating missing fixtures, `baseRecord: null`, state-conflict setup gaps, or pending-save ambiguity as immediate NOT-COVERED results before trying to build the needed scene with existing xEdit CLI commands.

## Rationalizations

| Excuse | Reality |
| --- | --- |
| "No path was specified, so `.tmp/` in the repo root is fine." | Root scratch folders linger and confuse later work. Use `.opencode/artifacts/<task>/...`. |
| "`tmp/` is already ignored, so I can use that." | Existing ignore rules are not permission to create new repo-root scratch conventions. Use `.opencode/artifacts/<task>/...`. |
| "I'll update `.gitignore` later if this becomes recurring noise." | Once a file is clearly local-only and unrelated, quarantine or ignore it now. |
| "I'll keep it visible in root because it might become useful." | Promote durable files into `docs/...` or `Tools/...`; everything else stays local and ignored. |
| "I'll just move it outside the repo." | Use the repo-local ignored area when the artifact still matters to the current session and should remain discoverable. |
| "I already added one comment near the top." | Each distinct non-obvious seam needs its own short explanation. One comment does not cover unrelated startup, registration, and error-boundary decisions. |
| "The code is readable enough without comments." | Readable syntax is not the same as reviewable intent. Upstream reviewers need the why for non-obvious automation paths. |
| "The request/error code is obvious from the exception names." | Names show mechanics, not policy. If malformed input is intentionally mapped to a stable protocol error, comment that boundary. |
| "I'll update the roadmap later if we still remember what changed." | Roadmaps drift exactly when updates are deferred. Refresh it at the end of each implementation round while the discoveries are still concrete. |
| "`msbuild` said success, so the binary must be fresh." | In this repo on this machine, command-line compiler output has already proven unreliable. Use `bds.exe -b` through `Start-Process` for trustworthy non-interactive builds. |
| "`rsvars.bat && msbuild` is close enough to using RAD." | Not in this repo. The established reliable path is launching `bds.exe -b` itself; other command-line routes are fallback-only. |
| "I'll just wait on `bds.exe` in bash until it exits." | That can block the agent without proving anything. Start it in the background, clear GUI blockers, and verify by artifact/timestamp changes. |
| "The redirected log was empty, so I should try random build commands until one prints something." | No. First inspect `D:\TES5Edit-contrib\xEdit.err`; on this machine it is often the actual compiler transcript and the fastest route to the real blocker. |
| "Release built cleanly, so we're done." | Not on this machine for this repo. `Release` is a known false-build path; use `LiteDebug` for real verification unless the user changes the rule. |
| "Any xEdit instance is fine for runtime checks." | Not in this repo. Runtime verification must use the MO2-managed harness so the binary, VFS, profile, and Fallout 4 target all stay correct. |
| "MO2 CLI `run` worked for the old portable harness, so it is still canonical." | No. The WastelandBlues lineage crashes on CLI `run`; use the surviving `xedit-client.ps1` broker path with the MO2 GUI already running. |
| "The registry can find Fallout 4 Data for me." | It resolves the Steam installation, not the WastelandBlues Stock Game. Pass `--data-path "B:\WastelandBlues 2.0\Stock Game\Fallout 4\Data"` explicitly. |
| "The client should start MO2 if needed." | It does not. The client delegates to the broker inside the running WastelandBlues MO2 GUI. |
| "The explorer found the missing cases, so coverage is verified." | Explorer output is a test matrix, not execution evidence. Dispatch `@laborer` for bounded known-method execution or run the MO2-backed CLI calls yourself, then save request/response artifacts before claiming coverage. |
| "The orchestrator owns verification, so it must personally run every CLI call." | The orchestrator owns routing and final claims. For fixed harnesses with clear pass/fail checks, `@laborer` should execute the mechanical loop and the orchestrator should verify the summary. |
| "Laborer can handle runtime verification, so it can design/debug the harness too." | No. `@laborer` is for bounded execution. Harness design, ambiguous failures, and root-cause analysis stay with the orchestrator/`@oracle`. |
| "Spec and code-quality reviewers approved it, so the feature is accepted." | Reviews are support signals. Acceptance requires semantic E2E artifacts showing the user's intended xEdit outcome actually happened. |
| "The harness passed, so the semantics must be right." | A harness can be a false positive. Inspect request/response/readback artifacts against the design intent and use a semantic reviewer subagent. |
| "We can add semantic verification after implementation." | Future phase design must define semantic E2E acceptance up front so argument combinations, negative cases, and readback evidence shape the implementation. |
| "The fixture is missing/null/ambiguous, so this is NOT-COVERED." | First use existing xEdit CLI commands to create the right file, record, conflict, mutation, save, or reload scene. NOT-COVERED is only honest after setup/readback attempts are preserved and still cannot prove the state. |

## Red Flags

- Creating or using repo-root `tmp/`, `.tmp/`, `artifacts/`, or `scratch/` for local work
- Adding loose logs, captures, JSON samples, or helper scripts at the repo root
- Saying "I'll ignore it later"
- Keeping unrelated old experiment files visible in the worktree
- Shipping non-obvious startup, registration, or protocol-error code without nearby intent comments
- Shipping request-validation or fail-fast automation code with only a distant top-level architecture comment
- Finishing an implementation round without refreshing `ROADMAP.md` with completed work, resolved unknowns, and downstream phase impact
- Repeating `msbuild`/`dcc32` build attempts for `xEdit.dproj` after the repo already established `bds.exe -b` as the reliable non-interactive build path on this machine
- Choosing `rsvars.bat && msbuild` as the first build attempt for `xEdit.dproj` after this repo established `bds.exe -b` as the primary path
- Starting `bds.exe` in a way that blocks bash instead of running it in the background
- Encountering a failed or ambiguous `bds.exe -b` run and not opening `xEdit.err` before trying alternate build commands
- Using `Release` as the verification config for this repo on this machine after it was established as a false-build path
- Launching runtime verification outside the MO2-managed harness entrypoints
- Running runtime verification before syncing the fresh repo binary into the canonical `FO4Edit\FO4Edit.exe` tool target
- Using `D:\TES5Edit-contrib\Build\xEdit.exe` as the runtime target instead of the canonical WastelandBlues `FO4Edit.exe`
- Launching through MO2 CLI `run` mode instead of the Mo2AgentControl broker client
- Omitting `--data-path`, `--mo2-root`, or the running-MO2-GUI prerequisite from the canonical client launch
- Claiming broad automation coverage from `@explorer` output without `@laborer`-run or orchestrator-run CLI/named-pipe artifacts and a main-session summary check
- Using the expensive orchestrator for fixed, repetitive runtime-verification execution when `@laborer` has a precise harness, artifact path, and pass/fail criteria
- Delegating unclear runtime failures or harness design to `@laborer` instead of escalating to orchestrator/`@oracle`
- Claiming phase completion from spec/code-quality review, build success, or script pass without semantic E2E artifact inspection
- Skipping a semantic reviewer subagent over actual request/response/readback outputs for new phase functionality
- Adding new command arguments or behaviors without a comprehensive semantic acceptance matrix tied to the user's intended xEdit effects
- Encountering an awkward semantic E2E fixture and lowering the assertion instead of using existing xEdit CLI setup commands to create the needed test scene first

Any of these means: stop and re-home the files before continuing.
