# Automation CLI Contract Reference

This reference freezes the wrapper-facing contract proven so far from preserved xEdit automation artifacts. JSON examples are linked to their source captures in `examples/` and are checked by the automation contract drift checker.

## Versioning

- Current `contractVersion`: `0.11`, captured in the Phase 13 accepted capability snapshot.
- Client rule: ignore unknown keys on objects and arrays unless a later contract version explicitly says otherwise.
- `supports.jobs.kinds` is frozen byte-for-byte across the `0.7` to `0.8` delta. The script-execution descriptors are adjacent to the job-kind list; script execution is not added to `jobs.*`.

## Capability discovery

Call `system.capabilities` before assuming wrapper behavior. The fields to key on are under `result.supports.scripts.execution`:

- `synchronous: true`
- `cancelable: false`
- `overlapPolicy: "single-process-single-runner"`
- `busyHolders: ["daemon", "gui"]`
- `failureMessagesOnError: true`
- `iKnowWhatImDoing: false|true` reflecting daemon launch state

## Transport and framing

- Transport is a Windows named pipe.
- Pipe naming convention for a spawned daemon is `\\.\pipe\xedit-<pid>` where `<pid>` is the xEdit process ID written by the launcher state file.
- Requests and responses are UTF-8 JSON.
- One connection carries one request and one response; the client connects, writes a single JSON request object, reads one full JSON response message, and disconnects.
- Requests use the shape `{ "command": "<name>", "args": { ... } }`. An empty arg object is still an object (`{}`), not an array.

The frozen `supports.jobs.kinds` list remains:

1. `files.hygiene.batch`
2. `plugin.esl.analyze`
3. `plugin.esl.apply`
4. `plugin.formids.compact_for_esl`
5. `validation.check_for_errors`
6. `validation.check_for_itm`
7. `validation.check_for_deleted_refs`
8. `cleaning.quick_clean`
9. `cleaning.quick_auto_clean`
10. `cleaning.sort_and_clean_masters`

See `examples/01-capabilities.md` for the source-linked response.

## Element Mutation Verbs (0.11)

See `docs/plans/2026-06-07-xedit-phase13-elements-mutation-surface-design.md` §4 for canonical request/response shapes.

### `elements.set_native_value`

Typed `NativeValue` write. Optional `kind` enum: `int`, `float`, `string`, `bool`, `formId`, `formIdArray`. Without `kind`, JSON type drives marshaling.

### `elements.set_to_default`, `elements.clear`

Mutation verbs deferring to native `IsEditable`/`IsClearable` predicates. Response includes `before` and `after` element envelopes.

### `elements.move_up`, `elements.move_down`, `elements.next_member`, `elements.previous_member`

Locator-drift family. Response includes `before.locator`, `after.locator`, top-level `locator` (post-mutation, authoritative), and `pathChanged: bool`. Caller MUST continue from `after.locator` after a successful operation.

### `elements.edit_capabilities`, `elements.assign_templates`

Read-only discovery. No consent gate. `edit_capabilities` returns `predicates`/`operations`/`assign` blocks; `assign_templates` returns a narrow template list.

### `elements.add_child` (extended)

Optional args:

- `targetIndex` (default `wbAssignAdd`)
- `templateIndex` / `templateName` — must agree if both provided
- Ambiguous multi-template targets without selector return `mutation_not_allowed` with `details.availableTemplates`.

### `elements.copy_child_to` (extended)

Optional args:

- `targetIndex` (default `wbAssignAdd`)
- `addRequiredMasters` (default `false`)

Response includes `masters.added`/`alreadyPresent`/`skipped` and `placement.sortOrderApplied` (internal GUI-equivalent fixup).

### Error taxonomy

No new error codes. Reuse `invalid_request` / `invalid_target` / `read_only_target` / `mutation_not_allowed` / `consent_required` / `file_not_found` / `record_not_found` / `element_not_found`.

## `scripts.run` success envelope

Successful `scripts.run` stays synchronous. A success response has `ok: true`, `command: "scripts.run"`, and `result` fields including:

- `id`
- `compile.ok`
- `lintBypassed`
- `lintWarnings`
- `ranInitialize`
- `ranFinalize`
- `processed`
- `terminatedEarly`
- `terminationCode`
- `timedOut`
- `statementBudgetExceeded`
- `messages`
- `messagesTruncated`
- `dirtyFiles`

The success example in `examples/02-scripts-run-success.md` is a preserved real capture of the same success envelope shape; the docs-only contract pass did not change product code or rerun a new success fixture.

## `scripts.run` failure envelope

Failed `scripts.run` responses have `ok: false`, `command: "scripts.run"`, and `error` with stable `code`, human-readable `message`, and per-code `details`. Clients must branch on `error.code`, not on `error.message` text.

For lifecycle-bearing script failures, the contract includes:

- `error.details.messages`: ordered JSON array of captured script messages, present even when empty.
- `error.details.messagesTruncated`: boolean; `true` means one or more emitted messages were dropped or clipped before response emission.

See `examples/03-scripts-run-failure.md` for a runtime failure carrying `messages` and `messagesTruncated`.

## Per-code `error.details` catalog

Unknown future keys may appear. Clients should consume the documented keys below and ignore extra keys.

### `script_blocker_lint`

- `lintWarnings`
- `lintScope`

### `script_busy`

- `holder`

### `script_external_declaration_not_allowed`

- `sourceUnit`
- `line`
- `ranInitialize`
- `ranFinalize`
- `processed`
- `messages`
- `messagesTruncated`

### `script_compile_error`

- `errorLocation` when available
- `ranInitialize`
- `ranFinalize`
- `processed`
- `messages`
- `messagesTruncated`

### `script_timeout`

- `timeoutMs`
- `elapsedMs`
- `ranInitialize`
- `ranFinalize`
- `processed`
- `messages`
- `messagesTruncated`

### `script_statement_budget_exceeded`

- `maxStatements`
- `ranInitialize`
- `ranFinalize`
- `processed`
- `messages`
- `messagesTruncated`

### `script_runtime_error`

- `runtimeDenied`
- `deniedIdentifier` when denial was detected
- `targetIndex` when Process-phase failure indexing is meaningful
- `ranInitialize`
- `ranFinalize`
- `processed`
- `messages`
- `messagesTruncated`

Runtime policy denials continue to normalize as `script_runtime_error` with `runtimeDenied: true`; this contract does not introduce `script_policy_denied`.

## Busy / overlap semantics

The contract advertises one process-wide script execution token shared by daemon script runs and GUI Apply Script. `supports.scripts.execution.overlapPolicy` is `single-process-single-runner`, and the possible holders are `daemon` and `gui`.

If the token is already held, clients should expect a failed `scripts.run` response with `error.code: "script_busy"` and `error.details.holder` naming the active holder. The GUI-held overlap is proven by manual GUI evidence: a daemon `scripts.run` was attempted while GUI Apply Script held the token, and the response returned `script_busy` with `error.details.holder: "gui"`.

The daemon-held mirror case remains **Not Covered** for an architectural reason, not because the response shape is undefined: daemon `scripts.run` executes synchronously on the GUI thread, freezing the GUI message pump while the daemon holds the guard. A user click queued during that freeze cannot reach the GUI Apply Script guard-acquire boundary until after the daemon releases the token, so the normal operator path cannot witness a GUI-side `script_busy` refusal for holder `daemon`. This is covered by the architectural rationale in `ARCHITECTURE.md`, which also cites the shared guard call sites.

## Locator/path lookup rules

Record and element locators use the stable `{file, formId, path}` shape. The locator audit captured `root-locator.json` with `file: "Fallout4.esm"`, `formId: "0000003C"`, and `path: ""`, and `nested-path.json` with a nested `locator.path` of `"[0]"` echoed as `object.path: "[0]"`.

Load-order FormID lookup remains the primary identity rule; file-local lookup is a compatibility carve-out, not a second addressing model. The audit artifact `load-order-lookup.json` found six hits for FormID `0000003C`, including the `Fallout4.esm` hit, and included both `masterOrSelf` and `winningOverride` readback fields.

## Save / durability semantics

`session.save` is the explicit save seam. A successful response reports what xEdit did during that save operation:

- `savedFilesNow`: files saved immediately in that call.
- `savedFilesPendingShutdown`: files whose save succeeded but whose final rename/durability is deferred until shutdown.
- `savedNowCount` and `savePendingShutdownCount`: counts for the two arrays.
- `dirtyState`: dirty-state readback after the save operation.

A successful `session.save` response is not by itself a fresh-restart durability proof. Strong durability claims need a later restart/readback artifact. The durability audit captured:

- `audits\save-now.json`: `savedNowCount: 1`, `savePendingShutdownCount: 0`, and `dirtyState.dirty: false` for a newly created first-save file.
- `audits\save-pending.json`: `savedNowCount: 0`, `savePendingShutdownCount: 1`, and `dirtyState.dirty: false` after reloading an already-on-disk target, mutating it again, and saving.
- `audits\save-pending-after-restart.json`: a fresh daemon readback found the second saved keyword in `VT_AutomationAudit_Pending_rerun2_20260508.esp`, proving the pending-shutdown response needed the explicit restart/readback step for a strong durability claim.

See `examples/05-save-durability.md` for the wrapper-facing save example and the locator/durability audit for the corresponding audit table.

## Client parsing rules

- Do not parse prose in `error.message` or script `messages` to decide control flow.
- Branch on `error.code`.
- Use documented `error.details` keys only.
- Treat `messages` as ordered observational output for operators and diagnostics.
- Ignore unknown keys for forward compatibility.
- Keep `scripts.run` outside `jobs.*`; it is synchronous and non-cancelable in this contract.

## 0.9 — Consent gate (`consent_required`)

Mutating daemon commands now require the daemon to have been launched with `-IKnowWhatImDoing`.

When the flag is absent, mutating commands fail at the request boundary with:

- `error.code: "consent_required"`
- `error.details.deniedReason: "iknowwhatimdoing-required"`
- `error.details.commandName: <the rejected command>`
- `error.details.mutationCategory: <the policy classifier category>`

This is a request-validation tier refusal. No script lifecycle has started yet, so no `messages`, `messagesTruncated`, `ranInitialize`, `ranFinalize`, or `processed` fields appear on this error code.

Read-only commands are unaffected.

`script_runtime_error` remains reserved for real script execution failures after execution starts; consent refusal is never reported through that lifecycle code.

The capability descriptor `result.supports.scripts.execution.iKnowWhatImDoing` reflects the daemon's current launch state.

See `examples/06-consent-required.md` for a source-linked example.
