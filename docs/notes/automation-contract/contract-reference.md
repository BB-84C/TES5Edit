# Automation CLI Contract Reference

This reference freezes the wrapper-facing contract proven so far from preserved xEdit automation artifacts. JSON examples are linked to their source captures in `examples/` and are checked by the automation contract drift checker.

## Versioning

- Current `contractVersion`: `0.15`, captured in the Phase 15C accepted capability snapshot.
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
- Ambiguous multi-template targets without selector return `mutation_not_allowed` with `details.availableTemplates`. (Note: this refusal-with-details branch is implemented but unverified end-to-end against FO4 fixtures in 0.11 — no probed vanilla FO4 container exposed `assign_templates count >= 2`. Clients should prefer the two-call `assign_templates` + `add_child{templateName}` pattern.)

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

## ChildGroup navigation (0.13)

Phase 15A adds a read-side navigation layer for xEdit ChildGroup-owned content without adding new verbs. Clients keep using `elements.children`, `elements.get`, and record locators; the only new locator vocabulary is the synthetic `\Child Group` prefix.

### Prefix grammar

Locator paths starting with `\Child Group` engage ChildGroup-aware resolution. The full grammar:

- `\Child Group` — the owning record's ChildGroup (a sibling `IwbGroupRecord`).
- `\Child Group\<sub-label>` — a named sub-group or named child inside the ChildGroup.
- `\Child Group\<sub-label>\...` — further descent (WRLD only, for Block / Sub-Block).

Prefix detection is tight: only the exact `\Child Group` path or a path beginning `\Child Group\` enters the ChildGroup resolver. Other paths preserve the existing locator behavior.

### Parent record signatures and sub-label vocabulary

| Parent | GroupType | Sub-labels |
|---|---:|---|
| CELL | 6 | `Persistent`, `Temporary`, `Visible when Distant` |
| WRLD | 1 | `Persistent` (returns persistent worldspace CELL record), `Block <X>, <Y>`, `Block <X>, <Y>\Sub-Block <X>, <Y>` |
| DIAL | 7 | (none — contents are INFOs surfaced directly) |
| QUST | 10 | (none — contents are DLBR/SCEN/DIAL surfaced directly; only present when `wbVWDAsQuestChildren=True`) |

### Round-trip example

The WRLD walk uses ordinary `elements.children` breadcrumbs for every step:

1. `records.get { file:"Fallout4.esm", formId:"0000003C", path:"" }` returns the Commonwealth `WRLD` record.
2. `elements.children` on that WRLD root appends a trailing child with `object.kind:"child_group"` and `locator.path:"\\Child Group"`.
3. `elements.children` on `path:"\\Child Group"` returns the persistent worldspace CELL as a flat record locator plus `child_group` stubs such as `path:"\\Child Group\\Block 0, 0"`.
4. `elements.children` on a Block stub returns Sub-Block stubs such as `path:"\\Child Group\\Block 0, 0\\Sub-Block 0, 0"`.
5. `elements.children` on a Sub-Block stub returns exterior CELL records with flat FormID locators; a returned CELL record's own `elements.children` can then expose its `Temporary` ChildGroup and REFR/ACHR/etc. child records, again as flat record locators.

### Asymmetries

- READ-only: synthetic `\Child Group` paths resolve through `elements.get`, `elements.children`, and other read-side element lookup surfaces.
- Mutation verbs (`elements.set_value`, `elements.set_native_value`, `elements.add_child`, `elements.remove_child`, `elements.copy_child_to`, movement verbs, etc.) reject synthetic ChildGroup paths with `error.code:"invalid_target"`. To mutate a child record, use its flat FormID locator, which is what the breadcrumb emitted by `elements.children` always uses for records.

### Empty group suppression

ChildGroups with zero immediate children are suppressed; no stub appears. This is content-aware behavior, not a defect. Clients should treat the absence of a stub as "no ChildGroup content".

### Block / Sub-Block coordinate format

Block and Sub-Block labels use signed decimal coordinates matching xEdit GUI `ShortName` output, including the space after the comma: `Block 0, 0`, `Block -3, 2`, `Sub-Block 0, 1`.

## apply_filter extensions (0.14)

Phase 15B extends the existing `records.apply_filter` discovery verb. No new
verb was added; existing glob fields and response fields keep their previous
meaning.

### New argument families

- `parentFormId`: load-order FormID string. A candidate record matches when its
  xEdit container/ChildGroup ownership chain contains that MainRecord. This is an
  AND predicate with all other filters.
- Regex alternatives to existing glob fields:
  - `editorIdRegex`
  - `displayNameRegex`
  - `fullNameRegex`
  - `baseEditorIdRegex`
  - `baseDisplayNameRegex`

Regex fields use `System.RegularExpressions.TRegEx` with `roIgnoreCase` and
`roCompiled`. Matching is partial by default; callers should add `^` / `$` when
they want anchoring.

### Timeout behavior

Each regex evaluation is bounded by a 100ms `TTask.Wait` wall-time check. The
underlying `TRegEx.IsMatch` call is not interruptible in this RTL, so a timed-out
worker may finish later in the background. The daemon treats timeout as a
non-match for that record, caps concurrent in-flight regex workers, and increments
the optional response field `result.regexTimeouts`. The field is omitted when the
count is zero.

### Conflict and invalid-regex errors

Do not provide both glob and regex for the same identifier family. For example,
`editorIdPattern` plus `editorIdRegex` returns `invalid_request` with
`error.details.invalidField: "editorIdRegex"`.

Invalid regex syntax also returns `invalid_request` with `invalidField` naming the
bad regex argument.

### Example

```json
{
  "command": "records.apply_filter",
  "args": {
    "files": ["Fallout4.esm"],
    "signatures": ["REFR"],
    "parentFormId": "00000025",
    "displayNameRegex": "picket fence",
    "limit": 25
  }
}
```

Expected success shape is unchanged except for the optional timeout metadata:

```json
{
  "ok": true,
  "command": "records.apply_filter",
  "result": {
    "truncated": false,
    "hits": [],
    "count": 0,
    "regexTimeouts": 1
  }
}
```

## references recursive descent (0.15)

Phase 15C extends `records.references` with one optional argument:

- `recursive` (boolean, default `false`): when omitted or false, the command keeps
  the pre-0.15 shallow behavior and scans only the addressed record's own element
  tree. When true and the addressed record has a populated ChildGroup, xEdit walks
  ChildGroup-owned records with `wbGetSiblingRecords`, collects each child
  record's outgoing references, and unions them with the parent record's own hits.

The `supports.referencesRecursive` block advertises:

- `defaultRecursive: false`
- `appliesTo: ["CELL", "WRLD", "DIAL", "QUST"]`
- `dedupBy: "loadOrderFormId"`
- `limitSemantics: "post-union-post-dedup"`

Limit semantics are aggregate: deduplication happens across the parent and all
descended child-record hits, then the existing `limit` cap is applied to the final
`hits` array. Supplying `recursive:true` for a record with no populated ChildGroup
is a silent no-op and returns the same shape as `recursive:false`.

Example:

```json
{
  "command": "records.references",
  "args": {
    "file": "Fallout4.esm",
    "formId": "00000025",
    "path": "",
    "recursive": true,
    "limit": 100
  }
}
```

The success envelope remains `{ "truncated": bool, "hits": [...], "count": n }`.

## conflict_status ChildGroup (0.15)

Phase 15C adds an optional `result.childGroup` sub-block to
`records.conflict_status`. It is omitted entirely when the addressed record has no
ChildGroup or when the ChildGroup is empty.

When present, the block contains:

- `count`: number of ChildGroup-owned child main records included in the scan.
- `hasConflict`: true when any scanned child record reports a non-peaceful xEdit
  conflict state.
- `signatures`: object keyed by child record signature. Each value has `total`
  and `conflicting` counts.
- `conflictingHits`: capped array of shallow record stubs for conflicting child
  records. Entries reuse the normal record summary/locator shape and include a
  shallow `conflict` object.
- `conflictingHitsTruncated`: true when more than 20 conflicting child records
  were found.

The `supports.conflictStatusChildGroup` block advertises the sub-block key, field
names, omission rule, and `conflictingHitsMax: 20`. Existing main-record
`record`, `conflict`, and `children` fields are unchanged; clients that ignore the
new key keep pre-0.15 behavior.

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
- Ignore unknown `object.kind` values for forward compatibility; `child_group` is additive in 0.13 and future kinds may appear.
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
