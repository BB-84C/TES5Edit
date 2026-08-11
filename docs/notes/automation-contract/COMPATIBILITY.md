# Automation Subsystem — Compatibility Policy

## Axes

This subsystem makes promises along these axes; each axis has its own compatibility tier:

| Axis | Stability tier (at 0.23) | Notes |
|---|---|---|
| Wire protocol envelope shape | Frozen | `{ok, result}` and `{ok, error: {code, details}}` shapes are stable. |
| `system.capabilities` schema | Additive-only | New fields under `supports.*` are additive; clients ignore unknown keys. |
| `supports.jobs.kinds` membership and order | Frozen | Byte-for-byte preserved from earlier freeze. Adding a kind is a major bump. |
| Per-code `error.details` shape (7 lifecycle codes) | Frozen at the 0.23 baseline | `script_blocker_lint`, `script_busy`, `script_external_declaration_not_allowed`, `script_compile_error`, `script_timeout`, `script_statement_budget_exceeded`, `script_runtime_error`. The 0.23 bump additively extends the timeout, statement-budget, and runtime-error shapes as documented below. |
| Request-validation tier error codes | Additive-only | New codes (e.g., `consent_required` in 0.9) may be introduced without major bump provided existing codes' details shapes are preserved. |
| Game-mode support | Best-effort | Verified against FO4; other modes inherit by structure but are not warranty-tested. |

## Contract Version

Current: **0.23** (accepted lifecycle readback, flush, and script-safety closeout)

### Additive history

- 0.6: Phase 6A jobs/file-hygiene
- 0.7-0.9: Phase 6B/6C/6D + 6E freeze
- 0.10: Phase 12 (Starfield .esp write enablement)
- **0.11: Phase 13** — 9 new `elements.*` verbs + 2 backward-compatible extensions
- 0.12: Phase 14 — `supports.stringDecoding` UTF-8 inline decode disclosure
- **0.13: Phase 15A** — `supports.childGroupNavigation` and `\Child Group` read-side navigation
- **0.14: Phase 15B** — `supports.applyFilterExtensions`, `parentFormId`, and `*Regex` filter fields
- **0.15: Phase 15C** — `supports.referencesRecursive`, `supports.conflictStatusChildGroup`, `records.references.recursive`, and additive `records.conflict_status.result.childGroup`
- **0.16: Phase 15D** — `supports.createParentSpec` and optional `records.create.parent` for CELL/DIAL/QUST ChildGroup authoring
- **0.17: Phase 15H** — `supports.elementsChildrenPagination` and optional `elements.children.limit` / `offset` pagination with additive response metadata
- **0.18: Phase 15E** — extends `supports.createParentSpec` and optional `records.create.parent` for WRLD persistent/exterior CELL authoring
- **0.19: Phase 15F** — `supports.reverseNavigation` and optional `includeParents:true` on read verbs to emit `relations.parents`
- **0.20: Phase 15G** — `supports.applyFilterExtensions.multiPattern` and scalar-or-array OR semantics for `records.apply_filter` identifier pattern/regex fields
- **0.21: Phase 16** — `records.apply_filter` offset pagination, `limit>100` rejection, and Starfield small/localized header-flag capability updates
- **0.22: bounded daemon-surface fixes** — locator `path` omission defaults to `""`, and `records.copy_into` reports native Reflection / Unmapped FormID nil-copy reasons when diagnosed
- **0.23: automation contract closeout** — pending-save readback, `session.flush`, script policy preflight and partial-mutation reporting, `RecordByFormIDStrict`, `IntToStr64` / `IntToHex`, and sortable-container notices

## 0.23 (2026-08-11) — lifecycle readback, flush, and script-safety closeout

This is an additive contract bump. No 0.22 field or command was removed, renamed,
or semantically narrowed.

- Added to `session.get_dirty_state` and `session.save.result.dirtyState`:
  `pendingShutdownFiles` and `pendingShutdownCount`. Each pending entry contains
  the queued `tempFile` plus the loaded `file` summary. Pending rename state is
  independent of dirty state, so `dirty:false` can coexist with pending entries.
- Added command `session.flush`, capability `supports.sessionFlush`, and
  capability `supports.pendingSaveReadback`. `session.flush` is consent-gated,
  drains pending renames with per-file results, and cleanly exits only after its
  response has been written and flushed. It refuses dirty sessions without
  `force:true`; failed renames remain queued and visible for process-exit retry.
- Added `scripts.run` policy-preflight details: `policyPreflight`,
  `deniedIdentifier`, `preflightLine`, and `preflightColumn`. A denied entry-script
  call fails before `Initialize`, so it cannot mutate plugin state.
- Added `scripts.run` failure mutation details on runtime/exception, timeout, and
  statement-budget failures: `mutationsAppliedBeforeFailure`, conditional
  `modifiedFilesBeforeFailure`, and `preExistingDirtyFiles`.
- Added script-side `RecordByFormIDStrict`, `IntToStr64`, and the two-argument
  Int64-semantic `IntToHex`. Legacy `RecordByFormID` is unchanged.
- Added `supports.sortableContainerNotice` and the advisory `sortInvalidated` /
  `notice` fields on successful writes beneath sorted containers. The notice is
  non-blocking and absent when no sort invalidation occurred.

## 0.22 (2026-07-08) — locator default + copy_into nil-copy diagnostics

- Changed: locator `path` is no longer field-presence-required. Omitted `path`
  defaults to the record root and resolves identically to `path:""`.
- Preserved: `file` remains required, `formId` remains optional unless a command
  explicitly requires record identity, and resolver semantics are otherwise
  unchanged.
- Changed: when `records.copy_into` receives nil from native `wbCopyElementToFile`,
  it still returns `mutation_not_allowed` but now forwards the diagnosed native
  Starfield Reflection refusal or Unmapped FormID / missing-game-master refusal
  instead of collapsing both to the generic copied-record identification message.
- Preserved: unrecognized nil-copy failures keep the pre-0.22 generic message.

## 0.21 (2026-07-06) — Phase 16 apply_filter pagination + Starfield flag capabilities

- Added: `records.apply_filter.limit` defaults to 100 and is capped at 100 hits
  per page. `limit > 100` is rejected as `invalid_request` instead of silently
  clamping.
- Added: `records.apply_filter.offset` counts matched records, not raw record
  indices. Responses include `offset`, `limit`, `truncated`, and `nextOffset`
  when another page is available.
- Added: `supports.applyFilterExtensions.pagination` documents the cursor field,
  max/default limit, over-cap rejection, and matched-record offset semantics.
- Added: `supports.filesCreate.flags` and `supports.fileHygiene.headerFlags`
  advertise `small` and `localized`; `small` is an alias of `esl` for the
  Starfield light slot, and summaries/header readbacks expose localized state.

## 0.20 (2026-06-15) — Phase 15G apply_filter multi-pattern OR

Design: `docs/plans/2026-06-15-xedit-phase15g-apply-filter-multi-pattern-design.md`.

- Added: the five existing glob fields and five existing regex fields under
  `records.apply_filter` now accept either a scalar string or an array of strings.
  Scalar strings preserve the pre-0.20 behavior as a length-1 internal array.
- Added: within one `*Pattern` or `*Regex` array, matching uses OR semantics.
  Predicates across different fields remain AND-composed.
- Added: request-boundary `invalid_request` with
  `error.details.invalidField` for empty arrays, arrays longer than 32 entries,
  or non-string array elements.
- Added: `supports.applyFilterExtensions.multiPattern` capability block declaring
  scalar/array support, `maxArrayLength:32`, `semantics:"OR"`, and the ten
  fields to which it applies.
- Preserved: same-identifier `*Pattern` + `*Regex` conflicts are still rejected,
  regex timeout and slot-saturation accounting remains per regex evaluation, and
  all scalar Phase 15B `apply_filter` behavior remains backward-compatible.

## 0.19 (2026-06-15) — Phase 15F reverse navigation parent relation

Design: `docs/plans/2026-06-15-xedit-phase15f-reverse-navigation-design.md`.

- Added: optional `includeParents` boolean arg, default `false`, on
  `records.get`, `records.find_by_form_id`, `records.find_by_editor_id`,
  `records.master_or_self`, `records.winning_override`, `elements.get`, and
  `elements.children`.
- Added: when `includeParents:true`, each affected record/entry gets
  `relations.parents`, an array of standard shallow record summaries with
  locators. The order is nearest-first and the depth is capped at 16.
- Added: top-level records return `relations.parents: []` when explicitly
  requested. When omitted or false, `relations.parents` is absent to preserve
  pre-0.19 response shape.
- Added: `supports.reverseNavigation` capability block documenting the opt-in
  arg, applies-to verb list, relation key, max depth, and ordering.

## 0.18 (2026-06-15) — Phase 15E records.create WRLD parent-spec

Design: `docs/plans/2026-06-15-xedit-phase15e-wrld-parent-spec-design.md`.

- Added: `WRLD` to `supports.createParentSpec.supportedParents`.
- Added: `records.create.parent` WRLD shapes for CELL authoring:
  `subGroup:"Persistent"` returns or creates the persistent worldspace CELL, and
  `coords:[x,y]` creates or returns the exterior CELL at signed int16 grid coords
  through xEdit's native `CELL[x,y]` path.
- Added: `supports.createParentSpec.subGroupVocabulary.WRLD:["Persistent"]`,
  `wrldCoords:true`, and `wrldRequiresCellSignature:true`.
- Evolved: the Phase 15D WRLD deferral fields remain present for additive
  `system.capabilities` clients. In 0.18+, `unsupportedParents` is the empty
  array `[]`, and `wrldDeferralReason` is retained as the sentinel
  `"superseded-by-0.18"` because WRLD is no longer deferred.
- Unchanged: non-CELL signatures under WRLD parents fail with `invalid_request`;
  create signature validity otherwise remains native xEdit behavior with no
  CLI-side signature allowlist.

## 0.17 (2026-06-15) — Phase 15H elements.children pagination

Design: `docs/plans/2026-06-15-xedit-phase15h-elements-children-pagination-design.md`.

- Added: optional `elements.children.limit` integer, default `200`, valid range
  `1..1000` inclusive. Values outside that range return `invalid_request`.
- Added: optional `elements.children.offset` integer, default `0`, valid range
  `>= 0`. Negative values return `invalid_request`.
- Added: response fields `count`, `total`, `offset`, and `truncated` beside the
  existing `children` array. `total` is the native immediate-child count and does
  not include synthetic ChildGroup stubs.
- Preserved: the Phase 15A `object.kind:"child_group"` navigation stub remains
  additive, but now appears only on the first page (`offset:0`) and counts as a
  returned entry, not as part of `total`.
- Added: `supports.elementsChildrenPagination` capability block documenting the
  default limit, maximum limit, and response metadata fields.

## 0.16 (2026-06-15) — Phase 15D records.create parent-spec

Design: `docs/plans/2026-06-15-xedit-phase15d-records-create-parent-spec-design.md`.

- Added: optional `records.create.parent = {file, formId, subGroup?}`. When
  supplied, `records.create` authors into the addressed parent record's ChildGroup
  instead of a top-level file group.
- Supported parents: `CELL`, `DIAL`, and `QUST`. `CELL` accepts
  `subGroup: "Persistent" | "Temporary" | "Visible when Distant"`; omitted
  `subGroup` defaults `REFR`/`ACHR`/`PGRD`/`LAND`/`NAVM` to `Temporary` and other
  signatures to `Persistent`.
- Deferred: `WRLD` parent-spec returns `invalid_request` with
  `error.details.unsupportedParent: "WRLD"` because Block/Sub-Block parent
  resolution is a later-phase problem.
- Added: `supports.createParentSpec` capability block documenting supported
  parents, CELL subgroup vocabulary, defaults, and WRLD deferral.
- Unchanged: callers omitting `parent` keep the pre-0.16 top-level
  `records.create` behavior. Signature support remains native xEdit behavior; no
  CLI-side signature allowlist was added.

## 0.15 (2026-06-15) — Phase 15C references + conflict ChildGroup descent

Design: `docs/plans/2026-06-15-xedit-phase15c-references-conflict-childgroup-descent-design.md`.

- Added: optional `records.references.recursive` boolean argument. Default remains
  `false`; when true on a populated ChildGroup-owning record, the response unions
  outgoing references from ChildGroup-owned child records and applies dedup/limit
  semantics to the aggregate result.
- Added: `records.conflict_status.result.childGroup`, omitted when the target has
  no populated ChildGroup. The sub-block reports aggregate child count,
  per-signature totals/conflicting counts, `hasConflict`, and a capped
  `conflictingHits` summary list.
- Added: `supports.referencesRecursive` and `supports.conflictStatusChildGroup`
  capability blocks describing the opt-in recursion flag and childGroup conflict
  result block.
- Unchanged: existing `records.references` shallow behavior when `recursive` is
  omitted/false, and existing main-record `records.conflict_status` fields.

## 0.14 (2026-06-15) — Phase 15B apply_filter parent + regex

Design: `docs/plans/2026-06-15-xedit-phase15b-apply-filter-parent-and-regex-design.md`.

- Added: `records.apply_filter.parentFormId`, a read-only predicate that matches
  records whose xEdit container/ChildGroup ownership chain contains the supplied
  load-order MainRecord FormID.
- Added: five regex alternatives to existing glob fields: `editorIdRegex`,
  `displayNameRegex`, `fullNameRegex`, `baseEditorIdRegex`, and
  `baseDisplayNameRegex`.
- Added: `supports.applyFilterExtensions` capability block describing the parent
  predicate, regex engine (`System.RegularExpressions.TRegEx`), fields,
  case-insensitive partial-match behavior, pattern/regex conflict rule, and
  `result.regexTimeouts` metadata field.
- Added: request-boundary `invalid_request` details with `invalidField` for
  invalid regex syntax and same-field pattern/regex conflicts.
- Unchanged: existing glob fields and non-regex `records.apply_filter` response
  envelope. The optional `regexTimeouts` field is omitted when zero.

### Phase 13 additive surface (0.11)

New commands:
- `elements.set_native_value`
- `elements.set_to_default`
- `elements.clear`
- `elements.move_up`, `elements.move_down`
- `elements.next_member`, `elements.previous_member`
- `elements.edit_capabilities`
- `elements.assign_templates`

Extended (backward-compatible) commands:
- `elements.add_child` — optional `targetIndex`, `templateIndex`, `templateName`
- `elements.copy_child_to` — optional `targetIndex`, `addRequiredMasters` (default `false`)

New capability block: `supports.elementsMutation` (see `contract-reference.md`).

Frozen Phase 6E `supports.jobs.kinds` membership and order unchanged.

### Phase 15A additive surface (0.13)

- Added: `supports.childGroupNavigation` capability block advertising the
  `\Child Group` locator prefix, the four parent signatures (CELL / WRLD /
  DIAL / QUST), the sub-label vocabulary, the GroupType integer mapping,
  and the `recordLocatorReentry: true` flag.
- Extended: `elements.children` appends a trailing `object.kind:"child_group"`
  navigation stub when the target record has a non-empty `IwbMainRecord.ChildGroup`.
- Extended: locator-path resolver accepts the `\Child Group` prefix on the read
  side (`xeAutomationRequireElement`); the prefix is rejected on the write side
  (`xeAutomationRequireOwnedElement`) — synthetic ChildGroup paths are
  navigation-only. Mutate child records via their flat FormID locator.
- Unchanged: all existing verbs, signatures, and response envelopes for paths
  that do NOT start with `\Child Group`. Backward compatibility verified by
  CG-BWC-001 on the MO2-backed FO4 harness.

Note: clients should not assume new `object.kind` enum values are exhaustive.
Forward compatibility requires that unknown `kind` values are ignored.

## What `0.23` promises

The `0.23` public wrapper-facing contract surface comprises:

- **Wire envelope shapes**: `{ok: true, result: <value>}` for success; `{ok: false, error: {code: <string>, details: <object>}}` for failure. Both shapes are stable across `0.x` versions.
- **`system.capabilities` schema**: top-level `contractVersion` (string), `supports.transport.*`, `supports.jobs.kinds` (frozen membership and order — see below), `supports.jobs.options`, `supports.scripts.execution.*` including `overlapPolicy = "single-process-single-runner"`, `busyHolders`, `failureMessagesOnError`, the new-in-0.9 `iKnowWhatImDoing` boolean reflecting daemon launch state, and the additive `supports.elementsMutation`, `supports.stringDecoding`, `supports.childGroupNavigation`, `supports.applyFilterExtensions`, `supports.referencesRecursive`, `supports.conflictStatusChildGroup`, `supports.createParentSpec`, `supports.elementsChildrenPagination`, `supports.reverseNavigation`, `supports.pendingSaveReadback`, `supports.sessionFlush`, and `supports.sortableContainerNotice` surfaces introduced through 0.23.
- **`supports.jobs.kinds` membership and order**: byte-for-byte preserved from the earlier freeze. The exact list is enumerated in `contract-reference.md`. Adding, removing, or reordering any kind is a major bump.
- **Per-code `error.details` shape for the 7 lifecycle codes**: `script_blocker_lint`, `script_busy`, `script_external_declaration_not_allowed`, `script_compile_error`, `script_timeout`, `script_statement_budget_exceeded`, `script_runtime_error`. The full 0.23 baseline is documented in `contract-reference.md`; future changes require another contract bump.
- **New request-validation tier error code `consent_required`**: `error.details = {deniedReason: string, commandName: string, mutationCategory: string}`. Returned at the request boundary when a mutating command is issued against a daemon launched without `-IKnowWhatImDoing`. Does NOT carry script-lifecycle fields (`messages`, `messagesTruncated`, `ranInitialize`, etc.) because no script execution has begun.
- **Locator semantics**: file-by-name and master-by-id resolution rules from `0.8` are preserved. As of 0.22, omitted `path` defaults to `""`.
- **Durability semantics**: `session.save` saved-files vs pending-shutdown distinction from `0.8` is preserved and now has explicit pending-queue readback plus the `session.flush` drain-and-exit path.

The full schema reference, per-field types, and per-command envelope examples live in `contract-reference.md`.

## What counts as breaking

- Renaming any field present in `0.23`.
- Removing any field present in `0.23`.
- Semantically narrowing the meaning of any field present in `0.23`.
- Adding a member to or reordering `supports.jobs.kinds`.
- Adding a field to or modifying any frozen 7-code lifecycle `error.details` shape.

## What stays additive

- New fields under `supports.*` subtrees.
- New request-validation tier error codes with their own `error.details` shapes.
- New examples in the `examples/` directory.

## Major-bump triggers

A `1.0` or later `0.x` bump is triggered by any breaking change as defined above. The capability descriptor `contractVersion` documents the current major/minor contract version.

## Forward path notes

A future async `scripts.run` or worker-thread script execution requires moving daemon execution off the GUI thread. That is a `1.x` change with explicit migration documentation, not a `0.x` additive evolution. Clients that depend on synchronous semantics today are safe.
