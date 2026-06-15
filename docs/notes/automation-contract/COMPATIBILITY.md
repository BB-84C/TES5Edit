# Automation Subsystem — Compatibility Policy

## Axes

This subsystem makes promises along these axes; each axis has its own compatibility tier:

| Axis | Stability tier (at 0.15) | Notes |
|---|---|---|
| Wire protocol envelope shape | Frozen | `{ok, result}` and `{ok, error: {code, details}}` shapes are stable. |
| `system.capabilities` schema | Additive-only | New fields under `supports.*` are additive; clients ignore unknown keys. |
| `supports.jobs.kinds` membership and order | Frozen | Byte-for-byte preserved from earlier freeze. Adding a kind is a major bump. |
| Per-code `error.details` shape (7 lifecycle codes) | Frozen | `script_blocker_lint`, `script_busy`, `script_external_declaration_not_allowed`, `script_compile_error`, `script_timeout`, `script_statement_budget_exceeded`, `script_runtime_error`. Adding a field to any of these is a major bump. |
| Request-validation tier error codes | Additive-only | New codes (e.g., `consent_required` in 0.9) may be introduced without major bump provided existing codes' details shapes are preserved. |
| Game-mode support | Best-effort | Verified against FO4; other modes inherit by structure but are not warranty-tested. |

## Contract Version

Current: **0.15** (Phase 15C — ChildGroup-aware `records.references` and `records.conflict_status`)

### Additive history

- 0.6: Phase 6A jobs/file-hygiene
- 0.7-0.9: Phase 6B/6C/6D + 6E freeze
- 0.10: Phase 12 (Starfield .esp write enablement)
- **0.11: Phase 13** — 9 new `elements.*` verbs + 2 backward-compatible extensions
- 0.12: Phase 14 — `supports.stringDecoding` UTF-8 inline decode disclosure
- **0.13: Phase 15A** — `supports.childGroupNavigation` and `\Child Group` read-side navigation
- **0.14: Phase 15B** — `supports.applyFilterExtensions`, `parentFormId`, and `*Regex` filter fields
- **0.15: Phase 15C** — `supports.referencesRecursive`, `supports.conflictStatusChildGroup`, `records.references.recursive`, and additive `records.conflict_status.result.childGroup`

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

## What `0.15` promises

The `0.15` public wrapper-facing contract surface comprises:

- **Wire envelope shapes**: `{ok: true, result: <value>}` for success; `{ok: false, error: {code: <string>, details: <object>}}` for failure. Both shapes are stable across `0.x` versions.
- **`system.capabilities` schema**: top-level `contractVersion` (string), `supports.transport.*`, `supports.jobs.kinds` (frozen membership and order — see below), `supports.jobs.options`, `supports.scripts.execution.*` including `overlapPolicy = "single-process-single-runner"`, `busyHolders`, `failureMessagesOnError`, the new-in-0.9 `iKnowWhatImDoing` boolean reflecting daemon launch state, and the additive `supports.elementsMutation`, `supports.stringDecoding`, `supports.childGroupNavigation`, `supports.applyFilterExtensions`, `supports.referencesRecursive`, and `supports.conflictStatusChildGroup` blocks introduced through 0.15.
- **`supports.jobs.kinds` membership and order**: byte-for-byte preserved from the earlier freeze. The exact list is enumerated in `contract-reference.md`. Adding, removing, or reordering any kind is a major bump.
- **Per-code `error.details` shape for the 7 lifecycle codes**: `script_blocker_lint`, `script_busy`, `script_external_declaration_not_allowed`, `script_compile_error`, `script_timeout`, `script_statement_budget_exceeded`, `script_runtime_error`. The full per-code field set is documented in `contract-reference.md` and is preserved byte-for-byte from `0.8` into `0.9`. Adding a field to any of these codes is a major bump.
- **New request-validation tier error code `consent_required`**: `error.details = {deniedReason: string, commandName: string, mutationCategory: string}`. Returned at the request boundary when a mutating command is issued against a daemon launched without `-IKnowWhatImDoing`. Does NOT carry script-lifecycle fields (`messages`, `messagesTruncated`, `ranInitialize`, etc.) because no script execution has begun.
- **Locator semantics**: file-by-name and master-by-id resolution rules from `0.8` are preserved.
- **Durability semantics**: `session.save` saved-files vs pending-shutdown distinction from `0.8` is preserved.

The full schema reference, per-field types, and per-command envelope examples live in `contract-reference.md`.

## What counts as breaking

- Renaming any field present in `0.15`.
- Removing any field present in `0.15`.
- Semantically narrowing the meaning of any field present in `0.15`.
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
