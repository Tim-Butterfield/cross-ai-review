---
description: Run the cross-AI review cycle (host orchestrates; iterating reviewer iterates; optional cross-check + verify) over the named artifacts. Provider/model/role/thinking selection comes from ~/.claude/cross-ai-review-config.json with auto-detection of installed CLIs. Multi-primitive pipeline (mechanical-pre → semantic → mechanical-post) per declared primitive per layer. Layered DAG support. Apply mode (default) autonomously edits; --report mode writes findings without edits. Halts on quota or silent model fallback.
---

# /cross-ai-review $ARGUMENTS

Run the cross-AI review cycle defined in `~/.claude/cross-ai-review-methodology.md` (hereafter **methodology** in this file) against the artifacts identified by `$ARGUMENTS`. The argument may be:

- One or more file paths
- A git commit SHA, range, or `uncommitted`
- A free-form description that lets you identify which files / commits / sections to review
- An optional `--report` flag to switch from apply mode (default; autonomous edits) to report mode (single-pass; findings written to file, no edits)

If the scope is unclear, ask one focused clarifying question before starting. Do not guess the scope.

This file is the **execution authority** for the slash command. The **methodology authority** is the methodology file. This file references methodology sections by name for every methodology rule rather than duplicating them, to prevent drift. If a rule appears here that contradicts the methodology, the methodology wins.

The methodology file is loaded on demand by Step 0 of Setup below — it is NOT in `~/.claude/CLAUDE.md` by design (CLAUDE.md retains only a thin stub: when-to-offer trigger, read-only summary, and a pointer to the methodology). Do not assume the methodology is in the conversation context until Step 0 has loaded it.

## Hard rules

### 1. Read-only enforcement

Apply methodology § Read-only is non-negotiable on every CLI invocation. Never use any flag from the forbidden list there. Reviewers must not be able to modify the artifacts under review. The host (Claude) is the only entity that edits artifacts — reviewers report; host applies.

### 2. Halt-signal classification + documented fallback. Silent fallback always halts.

Apply methodology § Halt-signal taxonomy on every CLI failure (and on every successful call too — Class E silent-fallback can occur on a zero-exit response, so classification runs on every call result, not only failures). Mechanical hooks have their own halt classes (M1-M5) per the same section.

The single inviolable rule: silent model fallback (Class E) **always triggers immediate halt**. This applies regardless of mode (apply or report) and regardless of how the classification was reached. There is no `allow_unverified_actual_model` override in v1 — extraction failure halts as Class E.

When a halt event occurs, write `halt-classification.md` per methodology § halt-classification.md format, then write a consolidated per-call `.md` for the failed call (with halt details in `## Halt event`, raw stderr in `## Raw stderr`, partial findings if any) per methodology § Per-call markdown file. Leave the transient temp files in place for forensic recovery; reference their paths from `halt-classification.md`. Then STOP and report to the user.

### 3. Autonomous validity judgment + apply (apply mode)

For every finding from any reviewer (or evidence finding from a mechanical hook):

1. Judge validity per methodology § Validity judgment rubric. Apply severity downgrades per methodology § Severity baseline.
2. Apply valid actionable findings (kind ∈ {fail, ambiguity, inconsistency, gap, risk}) autonomously **in apply mode**. No per-finding user confirmation. The host makes the edits.
3. Record every decision inline in the per-call markdown file's `## Findings` section per methodology § Per-call markdown file.

Apply-mode decision states: `applied`, `skipped` (valid but not actionable, e.g., kind=pass), `already-addressed` (valid but the issue was already resolved by a prior finding), `upstream-conflict-deferred` (valid but contradicts an upstream-layer authority), `withheld-class-e` (Class E halt; finding recorded for audit but not applied), or invalid + reason.

**In `--report` mode**, no edits are applied. Findings are recorded with decision state `reported-valid` (host adjudication concluded the finding is valid; user is expected to act on it) or `reported-invalid` (host adjudication concluded invalid; reasoning logged). The host's adjudication step still runs (validity rubric + severity baseline + dedup) — it's just the apply step that's skipped.

Reviewers run read-only and report. The host applies (apply mode) or records (report mode). The user authorized this autonomy specifically for the cross-AI review workflow — do not regress to per-finding confirmation here.

The user can interrupt at any point.

### 4. Helper invocations use literal values, no shell variable expansion

Every Bash invocation of `codex-call.sh` / `gemini-call.sh` (or the `.ps1` equivalents) MUST be constructed with all parameter values as **literals**. Do not use shell variables (`$VAR`) or command substitution (`$(...)`) inside the bash command itself. Generate the timestamp, paths, model slug, thinking level, primitive code, and other values in your own logic (or in a prior shell call whose output you read), then write them as literals when assembling the helper invocation.

This rule exists so that Claude Code can offer "always allow" on the first permission prompt for each helper. A bash command containing shell variable expansion is non-deterministic from the permission system's view (the variable could expand to anything on a later call), so the system cannot safely allowlist a prefix that contains it — and the user therefore cannot grant session-long approval at the prompt.

**The runtime permission prompt is the intended consent moment.** Do NOT pre-populate `~/.claude/settings.json` with allowlist patterns from the slash command, and `INSTALL.md` likewise must not. Granting must be the user's action at the prompt, not a silent install-time decision.

### 5. Invoke helper scripts directly, never wrap them in `bash` / `sh` / `python` / other interpreters

When constructing a Bash tool call to invoke a helper, the **first token** of the command MUST be the helper's executable path, not a wrapping interpreter. The helpers ship with `#!/usr/bin/env bash` shebangs and executable permissions; they can and must be invoked directly.

Wrong:
```
bash /Users/.../cross-ai-review-helpers/codex-call.sh --layer 0 --outer 1 ...
```

Right:
```
/Users/.../cross-ai-review-helpers/codex-call.sh --layer 0 --outer 1 ...
```

This rule exists because Claude Code's permission system scopes the "always allow" pattern to the **leading executable** in the command. When the leading executable is `bash` (or any other general-purpose interpreter — `sh`, `python`, `pwsh`, `node`, etc.), the "always allow" pattern offered is `bash *` (or the interpreter equivalent) — which would grant the right to run **any** command through that interpreter for the rest of the session, not just the helper. The user MUST refuse such an overbroad grant.

When the helper itself is the leading executable, the offered pattern scopes to the helper's path (e.g., `<helper-path> *`). Allow-listing that pattern is safe: the helper enforces read-only sandboxing on the reviewer CLI internally and only accepts its documented arguments.

Applies to all helpers: `codex-call.sh`, `gemini-call.sh`, and the `.ps1` equivalents on Windows. (On Windows, invoke `.ps1` files via their path directly rather than via `pwsh -File <script>` or similar — the same leading-executable scoping principle applies.)

## Workflow

### Setup (once per invocation)

0. **Load the methodology.** Read `~/.claude/cross-ai-review-methodology.md` before doing anything else. This file contains the canonical rules referenced throughout this command (halt taxonomy, primitives, configuration, layered review pattern, audit formats, output modes, thinking levels, per-CLI recipes, etc.). It is NOT in `~/.claude/CLAUDE.md` and is NOT auto-loaded into the session, so it must be explicitly Read here.

   If the file is missing, halt and tell the user to re-run the pack's `INSTALL.md` Step 4b (which writes the methodology file). Do not attempt to proceed without it — every later step references its sections.

1. **Parse output mode.** If `$ARGUMENTS` contains `--report`, set `output_mode = report`; otherwise `output_mode = apply` (default).

2. **Generate RUN_ID and run directory.** Resolve to the project repo root (use `git rev-parse --show-toplevel 2>/dev/null` if in a git repo, else fall back to the current working directory if the user is invoking from the project root). Then:
   ```sh
   RUN_ID="$(date -u +%Y%m%dT%H%M%S)-$$"
   REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
   mkdir -p "$REPO_ROOT/tmp/cross-ai-review/$RUN_ID"
   ```
   The path `tmp/cross-ai-review/$RUN_ID/` relative to the repo root is canonical and non-negotiable (per methodology § Persistence to canonical run directory). If the project doesn't have `tmp/` gitignored, warn the user and recommend adding it (one line: `tmp/`); do not silently switch to an alternate directory. Never use the OS temp directory (`/tmp/` or `%TEMP%`).

3. **Verify the schema file exists** at `~/.claude/cross-ai-review-schema.json`. If missing, write it from the canonical schema in methodology § Findings schema.

4. **Load config and resolve provider roles.** Per methodology § Configuration:
   - Resolve config (precedence: project override → global → shipped defaults)
   - Validate config: reject any `providers.<name>.reasoning_effort` (deprecated; produce migration error per methodology § Stale-config error)
   - Auto-detect installed CLIs via `command -v`
   - Resolve iterating-reviewer and cross-check-reviewer functional assignments from `role_preference`
   - If zero providers available, halt with a Class A-equivalent message naming the missing CLIs

5. **Identify the dependency DAG.** Per methodology § DAG identification:
   - Project extension's `### Authority documents` if present (recognizes both Layered-DAG and Peer-mode forms; the optional `Scope:` line disambiguates)
   - Heuristic detection (naming, cross-references, structure)
   - Interactive wizard if heuristics insufficient
   - Single artifact = no DAG question (treated as Layer 0 implicitly)
   - **Peer mode** (multi-artifact, no confident hierarchy): when the resolution above produces multiple artifacts with no declared authority, no confident heuristic-detected hierarchy, and the wizard's "is one of these the highest authority?" question is answered with "no" (or all derivation answers are "derives from nothing"), resolve `scope=peer-mode`. Record all artifacts as Layer 0 peers. P1 runs the **no-upstream case per artifact**; P4 peer-compatibility constraints (if any) are surfaced separately during the wizard and recorded for the P4 pass. Per methodology § DAG identification → Peer mode.
   - If a DAG was constructed via wizard (layered OR peer-mode), offer it back as a project-extension snippet the user can paste in for future reviews — both Layered-DAG and Peer-mode forms are documented in the project-extension template.

6. **Print the resolved-config + DAG line** as the first user-visible output of the invocation. Format per methodology § Per-iteration progress reporting. Include resolved scope (`scope=single-artifact` | `scope=layered-dag` | `scope=peer-mode`) and `output_mode=<apply|report>`.

7. **Load project-extension content** (if a project `## Cross-AI Review Extension` section exists): per-primitive declarations (P1 authority pairs, P2 coverage mappings, P3 ID schemas, P4 structural rules, P5 validation hooks, P6 checklist items), thinking-level overrides, severity overrides, final-pass criteria, context docs. Per methodology § Project extension discovery.

8. **Validate project-extension declarations.** Per methodology § Validation of project-extension declarations: reject thinking-level overrides for primitives not configured by this project, for terminally-mechanical primitives (P3, P5), or with non-canonical level values. Failure halts the run with the offending declaration cited.

### Per-layer execution

For each layer in topological DAG order (root first, then derived layers in dependency order — per methodology § Layer-by-layer iteration sequencing):

**Print the budget line** (mandatory when more than one primitive is configured for this layer): list configured primitives, resolved per-primitive thinking levels, output_mode, and worst-case max-calls calculation. Format per methodology § Per-iteration progress reporting.

**Layer-aggregate-cap accounting.** If the resolved config sets `layer_aggregate_cap` to a non-null integer (per methodology § Configuration → schema and § Layer-aggregate cap), initialize a per-layer reviewer-call counter at 0 at layer entry. Increment the counter by 1 for every helper invocation in this layer (iterating, cross-check, verify; mechanical-phase host-direct calls do NOT count toward the AI-reviewer cap). Emit a one-time warning to the chat output when the counter reaches **75% of the cap** (e.g., `[L=<L> aggregate-cap warn] reviewer calls = <count>/<cap> (75% threshold)`). When the counter reaches **100% of the cap**, halt the layer immediately and escalate per methodology § Escalation at outer cycle 3 (write the cap-exhaustion entry to `review-summary.md`'s "Unresolved (escalation)" section). When `layer_aggregate_cap` is `null` (the default), per-primitive caps apply only and no aggregate-cap accounting runs.

**Between-layer propagation.** After each layer reaches clean termination (and BEFORE starting the next layer's cross-AI review), the host runs a **propagation step**: mechanical updates to every doc in subsequent layers that references the just-stabilized layer. Rename references, update verbatim quotes, sync **literal-value examples** (per methodology § Layer-by-layer iteration sequencing — values whose correctness is determined by direct equality with upstream), propagate template changes, verify section-name references resolve. **Context-dependent examples** (where correctness depends on logical constraints from upstream that propagation alone might not capture) are NOT mechanically synced — instead, flag them in the propagation diff with `requires-substantive-review` and leave them for the downstream layer's cross-AI review to evaluate. This is the host's job, not the reviewer's — mechanical drift is fixed deterministically here so the next layer's cross-AI review can focus on substantive adherence rather than catching copy-paste drift. Record the diff at `<written-at>-propagation.md` per methodology § `<written-at>-propagation.md` format.

**For each declared primitive in this layer**, run the primitive pipeline per methodology § Pipeline structure:

#### Phase 1: Mechanical pre-check (skip if primitive has no mechanical aspect)

The host runs the primitive's deterministic check (P3 linkage scan, P5 hook command, P6 waiver scan, etc.). Write a per-call `.md` file `<call-started>-host-mpre-<primitive>-<O>-<N>.md` with the file-level audit header `**Thinking level**: N/A (mechanical)` (literal — per methodology § Thinking levels → Audit header format → Mechanical-phase grammar). Findings collected; they enter the addressed-context for the semantic phase that follows.

For **P6 (Checklist verification) mechanical pre-check**, the host scans the artifact for explicit waiver markers (e.g., `<!-- waive: ITEM-NAME -->` or a `waivers.md` file) per methodology § P6 → Pre-check waiver finding format. Each detected waiver becomes a finding with `kind=pass`, `severity=info`, `source=evidence`, structured title, and **decision state `already-addressed`** (NOT the default `skipped` for kind=pass). The `already-addressed` state ensures the waiver appears in the addressed-context for the semantic phase that follows, so the reviewer doesn't raise a `kind=gap` finding for the waived item.

For P5 (validation hooks), enforce side-effect policy by snapshotting the worktree before each hook runs and diffing after. Unexpected mutations (M5) halt immediately.

For mechanical halt classes (M1 with `required: true`, M5), follow Hard rule #2: write halt-classification.md and stop.

#### Phase 2: Semantic-iterate (skip if primitive has no semantic phase)

In **apply mode**: For O ≥ 2, do a **disposition pass first** per methodology § Inner cycle. Read every per-call markdown file from this layer + primitive's prior outer cycle. Write `<written-at>-disposition-<O>.md`. Compute growth and write `<written-at>-growth-<O>.md`.

For inner iteration N = 1, 2, 3, ...:

- Generate `<call-started>` timestamp (UTC, current time).
- First (only when prior per-call `.md` files exist for this layer + primitive in this run dir): construct the addressed-context blob per methodology § Addressed-context construction. The blob is appended to the iterating reviewer's prompt.
- Then assemble the prompt (instruction text + reference to artifacts in this layer + upstream content as reference context + addressed-context blob + standard schema-requesting prompt for the primitive) and write it to a temp file. **Artifact-content delivery branches by the CURRENT semantic call's resolved CLI** (not just the iterating reviewer's): each semantic phase resolves the CLI for its own role (semantic-iterate + semantic-verify use the iterating reviewer's CLI; semantic-cross-check uses the cross-check reviewer's CLI). Then for that resolved CLI:
  - **Codex** has file-tool access in its read-only sandbox: the prompt references artifact paths and Codex reads them itself (no `--stdin-file` needed).
  - **Gemini** does NOT have file-tool access by default: the host writes the artifact content (concatenated for multi-artifact layers) to `.tmp-stdin-<call-started>.txt` and passes it as `--stdin-file` to the helper, AND the prompt instructs Gemini to treat stdin as the artifact under review.

  This branching applies to all three semantic phases (iterate, cross-check, verify) — phase 3's existing `--stdin-file` step is the cross-check-specific instance of this rule, not a special case.
- Resolve thinking level per methodology § Override hierarchy.
- **Invoke the iterating reviewer's helper script** with parameters:
  - `--layer <L>` (current layer index)
  - `--primitive <P>` (current primitive code: P1/P2/P3/P4/P5/P6)
  - `--phase semantic-iterate`
  - `--outer <O>` `--iter <N>`
  - `--role iterating`
  - `--model <slug from config>`
  - `--thinking-level <fast|standard|deep>` (resolved level)
  - `--prompt-file <run-dir>/.tmp-prompt-<call-started>.txt`
  - `--run-dir <run-dir>` `--call-started <call-started>`
- Per Hard rules #4 and #5: literal values, direct invocation. The helper writes `.tmp-<call-started>-out.json` and `.tmp-<call-started>-err` and prints a JSON status object on stdout with `exit_code`, `output_file`, `stderr_file`, `model_actual`, and `halt_class`.
- Branch on the helper's exit code:
  - `0` (success): proceed to apply findings (apply mode) or record findings (report mode).
  - `1`-`7` (Class A-G halt): per Hard rule #2 — write `halt-classification.md` and a per-call `.md` for the failed call, STOP.
  - `8` (helper-arg validation failure): host-callsite bug. Normalize to **Class A-equivalent halt severity** per methodology § Codex CLI (and the Gemini equivalent). Audit records `Class: A (helper-arg validation failure; helper exit=8)`. Write halt artifacts and STOP — this is a slash-command-implementation bug that requires a host code fix, not transient retry.
- Apply Hard rule #3 (validity judgment + autonomous apply or record).
- Write the consolidated per-call file `<call-started>-<cli>-iter-<P>-<O>-<N>.md` per methodology § Per-call markdown file. Then delete transient temp files (only on a successful call; halts retain them per Hard rule #2).
- **Stabilization criteria** — break out of the iterating loop when ANY of:
  - `verdict=approve` with no actionable findings, OR
  - Set of findings unchanged across iterations N-1 and N (compare by content tuple per methodology § Set-stability via content tuple), OR
  - All remaining findings classified invalid (nothing to apply), OR
  - Inner-iteration cap of 4 reached — force progression to the cross-check pass (or to outer-cycle continuation in single-reviewer mode).

In **report mode**: skip the iteration loop. Run ONCE only — same prompt construction, same helper invocation with `--phase semantic-iterate`, same per-call file written. No N>1 iteration; no addressed-context referencing prior fixes (because none exist). Decision state for findings is `reported-valid` or `reported-invalid` instead of `applied`/`skipped`/etc.

#### Phase 3: Semantic-cross-check (skip if no cross-check reviewer configured OR primitive has no semantic phase)

One call per outer cycle (apply mode) or one call total (report mode).

- Generate `<call-started>` timestamp.
- Construct the **context blob**: in apply mode use the `addressed-context` form per methodology § Addressed-context construction (apply mode); in report mode use the `reported-context` form per methodology § Reported-context construction. Both forms include all iterating iterations from this outer cycle plus any prior outer cycles' calls — filtered by Layer + Primitive + Phase per methodology § Re-parsing contract — but with different decision-state filters and preamble wording per their respective sections.
- For artifact content (Gemini doesn't have file-tool access by default), write the artifact content to `.tmp-stdin-<call-started>.txt` and pass it as `--stdin-file` to the helper.
- Invoke the cross-check reviewer's helper with parameters:
  - `--layer <L>` `--primitive <P>` `--phase semantic-cross-check`
  - `--outer <O>` (no `--iter`)
  - `--role cross-check`
  - `--model <slug>` `--thinking-level <level>`
  - `--prompt-file ...` `--run-dir ...` `--call-started ...`
  - (For Gemini: `--stdin-file ...`)
- Branch on exit code as in Phase 2.
- Apply Hard rule #3.
- Write `<call-started>-<cli>-xchk-<P>-<O>.md` per the per-call template.

#### Phase 4: Semantic-verify (skip if no cross-check reviewer configured; ALSO skipped in report mode — nothing to verify)

One call per outer cycle (apply mode only).

- Generate `<call-started>` timestamp.
- Construct addressed-context (all prior calls in this outer cycle plus any prior outer cycles, layer+primitive filtered).
- Invoke the iterating reviewer's helper with parameters:
  - `--layer <L>` `--primitive <P>` `--phase semantic-verify`
  - `--outer <O>` (no `--iter`)
  - `--role verify`
  - `--model <slug>` `--thinking-level <level>`
  - `--prompt-file ...` `--run-dir ...` `--call-started ...`
- Branch on exit code.
- Apply Hard rule #3.
- Write `<call-started>-<cli>-vfy-<P>-<O>.md` per the per-call template.

#### Phase 5: Mechanical post-check (skip if primitive has no mechanical aspect)

Same shape as Phase 1, but runs AFTER the semantic phases (apply mode: re-validates after edits; report mode: re-validates against unchanged artifact). Write `<call-started>-host-mpost-<primitive>-<O>-<N>.md` with `**Thinking level**: N/A (mechanical)` (literal) and the same mechanical-phase audit conventions as Phase 1.

**Mechanical pre/post disagreement**: per methodology § Output format → Mechanical pre/post disagreement, when mechanical-post produces findings that differ in count or content from mechanical-pre against the same unchanged artifact (apply mode: post-edit state; report mode: same unchanged state both passes), surface the divergence as a `kind=risk` finding (default severity medium) naming the divergence. The mechanical-side analogue of M4 (nondeterminism). Field-recording differs by output mode:
- **Apply mode**: write the risk finding into the mechanical-post per-call `.md` file's `## Findings` section with `Source: evidence` (the file-level `**Phase**: mechanical-post` header carries the phase identity; per-call apply-mode files do NOT have a per-finding `Origin` field — that's a report-mode field).
- **Report mode**: surface the risk finding in `findings-summary.md` with `Origin=mechanical-post` (per the report-mode entry shape in methodology § Output format → Output format → entry shape), since report mode's iteration loop doesn't exist to absorb it.

If mechanical-post produces unresolved findings, end the primitive's current outer cycle with continuation semantics equivalent to `edits_applied > 0` (per methodology § Outer cycle continuation → Mechanical-post continuation rule). At cap, escalate via the existing cap-exhaustion path.

#### Decide outer-cycle continuation (apply mode only)

Count `edits_applied_in_outer_cycle_O` from the per-call decisions across all five phases.

- If `edits_applied = 0` AND mechanical-post produced no unresolved findings: this primitive's outer cycle for this layer is settled. Continue to the next declared primitive.
- If `edits_applied > 0` (or mechanical-post unresolved, per the continuation rule) AND O < 3: start outer cycle O+1 for this primitive in this layer.
- If continuation triggered AND O = 3: escalate per methodology § Escalation at outer cycle 3 (write the escalation report into `review-summary.md`'s "Unresolved (escalation)" section). Move to the next primitive regardless (so other primitives get reviewed).

In report mode, there is no outer-cycle continuation — single pass per primitive.

### After all primitives in a layer complete

**Per-layer final self-critique** (apply mode only). Per methodology § Final self-critique pass. Write `<written-at>-final-self-critique.md`. If it surfaces actionable issues AND outer-cycle budget remains for any primitive in this layer, run one more outer cycle for the affected primitive(s) — the methodology does NOT narrow the restart to "the most recent primitive only"; it scopes by which primitives' findings the final-pass identifies. At cap, applies suggestion-tier issues only and escalates non-suggestion issues per methodology § Final self-critique pass → at-cap branch.

**Upstream-conflict restart flow** (apply mode; per methodology § Cross-layer findings (upstream-conflict) and § Restart semantics). When a downstream-layer (Layer N>0) review surfaces findings with decision state `upstream-conflict-deferred` (P1 findings whose fix requires changing the upstream authority, not the current-layer doc), the cycle does NOT end with the current-layer review. Instead, after the current layer's final self-critique completes:

1. **Check for upstream-conflict-deferred findings** in the current-layer per-call files. Per methodology § Re-parsing contract, walk each `### N.` finding block, parse the `**Host decision**` line by splitting on the literal ` · ` separator, and select entries whose state token (the trimmed right-hand side) exactly equals `upstream-conflict-deferred`. Do NOT use substring containment (it would falsely match unrelated states).
2. **If any exist**, return the cycle to the contradicting upstream layer for one more outer cycle focused specifically on those findings — subject to that upstream layer's outer-cycle cap budget. If the upstream layer's cap is exhausted, escalate per methodology § Escalation at outer cycle 3.
3. **After upstream re-stabilizes**, re-run the propagation step from upstream to all downstream layers (per methodology § Layer-by-layer iteration sequencing → step 2/4). Record the diff at `<written-at>-propagation.md`.
4. **Invalidate downstream stability** for the affected layer(s) and any layers below them. Mark all prior per-call files in the affected downstream layers as superseded by adding two stable header lines: `**Status**: superseded-by-upstream-change` and `**Superseded at**: <ISO 8601 UTC timestamp>` (per methodology § Restart semantics → preserve prior per-call files).
5. **Start a fresh restart epoch** for each affected downstream layer (monotonic counter R1, R2, ... per methodology). Headers per methodology § Restart semantics:
   - **Each new per-call file** written after the restart records BOTH `**Restart epoch**: R<N>` and `**Restart of**: <prior-call-timestamp>` (per the per-call template's optional restart header lines).
   - **Per-cycle artifacts** (`<written-at>-disposition-<O>.md`, `<written-at>-growth-<O>.md`, `<written-at>-final-self-critique.md`) record only the headers their respective format specs document (typically `**Restart epoch**: R<N>` only — see each format spec in methodology § Audit artifact formats; `Restart of` is per-call-only). The propagation artifact format does not currently include restart headers; if a propagation diff is produced after a restart, it stands on the timestamp + the surrounding per-call files for restart linkage. Adding `Restart of` to per-cycle artifact formats would be a Layer-0 (methodology) change first, then propagated here.
6. **Restart the affected downstream-layer review** at fresh outer cycle indexing (O=1) within the new restart epoch. Per methodology, the addressed-context construction and disposition pass MUST filter out per-call files where `**Status**:` exactly equals `superseded-by-upstream-change`, so the restarted cycle treats only non-superseded files as the comparison base.
7. **Restart cap**: a layer with 3 accumulated restart epochs without reaching stability escalates per methodology § Escalation at outer cycle 3 (treating cumulative restart count as the escalation trigger).

This is the rare loop in the layered cycle; most reviews don't trigger it because Layer 0 is reviewed thoroughly first.

In report mode, final self-critique is **skipped** per methodology § Final self-critique in report mode.

### After all layers complete

In **apply mode**: write `review-summary.md` at the top of the run directory per methodology § `review-summary.md` format. This is the user's main entry point.

In **report mode**: write `findings-summary.md` at the top of the run directory per methodology § `findings-summary.md` format. Per-primitive filtered views (`findings-P1-authority.md`, etc.) are generated from the canonical summary.

**Mirror key contents in the final chat reply** so the user doesn't need to open the file unless they want detail. The set of fields is **mode-dependent**:

- **Apply mode**: outer cycles run per primitive, total iterations, provider config used, stable-state summary, notable findings, halt events (if any), unresolved escalations (if any), run directory path.
- **Report mode**: total findings (with breakdown by severity / kind / primitive / origin), provider config used, single-pass complete (or halt-classified <X>), notable findings, halt events (if any), run directory path. Stable-state summary and escalation are NOT applicable in report mode (no iteration loop, no escalation triggers); omit those fields rather than printing "N/A".

## Single-reviewer mode degradation

When `role_preference` resolves to only one available provider, the cycle runs in **single-reviewer mode**: the iterating reviewer function runs as configured; cross-check (Phase 3) and verify (Phase 4) phases are skipped per methodology § Single-reviewer mode. Validity judgment, severity baseline, addressed-context, disposition pass, growth tracking, and final self-critique all still run. The audit trail records the mode in each per-call `.md` file's header (`**Mode**: single-reviewer`) and in the final summary. Findings are still useful; the user just loses the cross-vendor second opinion.

## Notes on signal detection

If error-detection logic looks fishy on a live run (e.g., the model field isn't in the envelope where expected, or stderr patterns don't match documented forms), **classify conservatively per methodology § Halt-signal taxonomy and surface the raw evidence to the user for triage — but do NOT offer a proceed-or-halt choice for halt-mandatory classes**. Specifically, Class E (silent-fallback, including actual-model extraction failure) and Class G (unclassified) ALWAYS halt per methodology; there is no override flag in v1. The "surface to the user" action means: write `halt-classification.md` and a per-call `.md` with the raw evidence captured, then STOP the run, and present the raw evidence in the chat reply so the user can triage outside the cycle. Prefer false-halt to silent-degrade — but the false-halt is itself the action; not "halt or proceed." For halt classes that are NOT mandatory (e.g., Class C with a fallback chain not yet exhausted; Class F with one retry remaining), the methodology's existing recovery branches apply.

**Per-call audit-template selection on halt** (per methodology § Per-call markdown file → Halt variant of the per-call template, and § M5 halt — special case):

- **Halt BEFORE producing parseable reviewer output** (Class A, B, C-chain-exhausted, D-chain-exhausted, **Class E when no parseable reviewer output exists** — e.g., extraction failure on a non-zero-exit response or a fully-failed call, F-after-retry, G, M1-required): use the **halt-variant** per-call template — `Verdict: halt`, `Findings: 0 (no parseable reviewer output)`, `## Findings: _N/A_`, `## Halt event: <full block>`.
- **Halt AFTER producing parseable reviewer output** (rare; canonical case is **Class E silent-fallback on a successful zero-exit response with parseable JSON**): use the **standard** per-call template — list the parseable findings with decision state `withheld-class-e` (host does not apply Class E findings; they remain in the audit for forensic review), set `## Halt event` to the full halt classification.
- **M5 (unexpected mutation) — host-generated halt**: use the **standard** per-call template — host writes the M5 evidence finding (kind=fail, severity=critical, source=evidence) to `## Findings`, sets `**Verdict**: halt` (literal; not a schema enum value because the per-call markdown's Verdict header is host-written and not schema-validated), and writes the halt classification to `## Halt event` per methodology § M5 halt — special case.

For mechanical halt classes (M1-M5) specifically, methodology § Halt-signal taxonomy → Mechanical hook classes is the canonical reference. M5 (unexpected mutation) is the most consequential — it indicates the cycle's read-only invariant for the artifact has been compromised, and like Class E, halt is non-negotiable.
