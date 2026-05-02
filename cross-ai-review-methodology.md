# Cross-AI review — methodology

**Version**: v1.0 (draft)

This is the canonical methodology for the cross-AI review cycle. It is loaded by the `/cross-ai-review` slash command as Step 0 of every invocation, NOT auto-loaded into every Claude session — the always-loaded stub at `~/.claude/CLAUDE.md` (the user's global config; see `cross-ai-review-claude-section.md` for the stub content) points here. Keep CLAUDE.md lean by leaving the bulk in this file.

## Purpose

The cross-AI review methodology defines a structured, multi-primitive review cycle for artifact sets. The cycle composes:

- **Authoritative review** — does an artifact adhere to its declared upstream authority?
- **Coverage review** — does every item in a declared set have a corresponding item in another set?
- **Linkage verification** — do declared ID-based references resolve, and are there orphans or danglers?
- **Structural review** — does the artifact satisfy declared structural rules (dependency direction, naming, layering)?
- **Validation hooks** — do declared deterministic commands (build, test, lint, schema-check) succeed cleanly?
- **Checklist verification** — has each item in a declared checklist been addressed or explicitly waived?

Different projects need different combinations of these. A research team may want only authority + coverage. A regulated-finance team may want all six. The methodology defines how each one works (semantics, audit format, halt behavior); the project extension declares the project-specific content (which authorities, which IDs, which commands, which checklists).

The cycle is **autonomous by default** — Claude (the host) judges every reviewer finding's validity and applies the valid actionable ones to the artifact, iterating with reviewer CLIs until findings stabilize. A `--report` mode is also supported for runs where the user wants findings written to a file rather than auto-applied.

## Reviewer-agnostic by design

The methodology describes review functions, not review providers. The host role is fixed (Claude orchestrates; the slash command runs in Claude Code). The non-host roles are described by **what they do**, not by which CLI fills them:

- **Iterating reviewer** — runs across multiple iterations against an artifact until findings stabilize. Mandatory in any non-degraded run.
- **Cross-check reviewer** — runs once per outer cycle to catch what the iterating reviewer missed. Optional.
- **Verify pass** — the iterating reviewer re-running once after the cross-check, to catch regressions that the cross-check's applied findings introduced. Runs only when a cross-check reviewer is configured.

The user picks which reviewer CLI fills each function (Codex, Gemini, others) via `~/.claude/cross-ai-review-config.json`. The methodology does not name CLIs in role definitions, prescribe vendor preferences, or compare model strengths. Per-CLI invocation details live in the per-recipe sections at the bottom of this document.

## Goals vs. primitives — design principle

Review processes vary by team and domain. A research lab cares about authority alignment and coverage; a regulated industry cares about traceability, determinism, and delivery readiness; a public-API team cares about executability and structural integrity. The set of *outcomes* a review should produce — call them goals — is project-specific.

Underneath those project-specific goals are a small number of **stable enforcement mechanisms** — primitives — that compose into any reasonable goal. The methodology standardizes the primitives; the project extension declares which goals matter and which primitives instantiate each goal with what content.

This separation is the methodology's central design principle:

- **Methodology defines** primitive semantics: what each primitive checks, when it runs in the cycle, what its findings look like, what its halt behavior is, how it interacts with the iteration loop.
- **Project extension defines** primitive content: which authority documents, which ID schemas, which validation commands, which checklist items, with what severity overrides.

The same six primitives serve a research lab and a regulated industry — the project extension is what makes the cycle apply to one or the other. Goals vary; primitives stay stable.

A medical-device project and a game-engine project both compose primitives like "authority adherence" and "validation hook execution," but their authority documents (a regulatory submission vs. a design doc), their hooks (`pytest && asil-sanity-check` vs. `cargo test`), and their checklists (rollback to FDA-recordable state vs. ship to Steam Store) are completely different. The methodology doesn't care; the project extension does.

## Six review primitives

The methodology defines six primitives. Each has well-defined semantics, audit-trail expectations, and lifecycle position. The phase composition varies:

- **Terminally mechanical** (no semantic phase, no thinking-level applies): **P3** (Linkage), **P5** (Validation hooks).
- **Semantic-only** (no mechanical phase): **P1** (Authority adherence). **P4** (Structural rules) is also semantic-only when the project does not declare a static-check command — see § P4 → Tooling-conditional behavior.
- **Mixed** (mechanical pre-check + semantic phases): **P2** (Coverage), **P6** (Checklist), and **P4** (Structural rules) when the project declares a static-check command.

All six can produce findings; only semantic phases consume reviewer thinking effort.

### P1 — Authority adherence (semantic)

An artifact in layer N must be consistent with its declared upstream authority in layer M (where M is upstream of N in the dependency DAG).

Inputs:
- The artifact under review (in layer N).
- The upstream authority's content as immutable reference context.

Reviewer prompt: "Does this artifact correctly adhere to the upstream authority? Identify any contradiction, deviation, or unjustified divergence from upstream."

Findings:
- `kind=inconsistency` when the artifact contradicts upstream.
- `kind=ambiguity` when the artifact's compliance with upstream is unclear.
- `kind=gap` when upstream describes something the artifact omits.
- A finding that suggests the *upstream* layer should change to accommodate this artifact's design carries `kind` as appropriate (typically `inconsistency`, `gap`, or `fail`) and is assigned the host decision state `upstream-conflict-deferred` — recorded but not applied to the current layer; deferred per § Cross-layer findings (upstream-conflict).

Default thinking level: `standard`. Documented project override: `deep` for high-risk authority interpretation (charter / compliance / public-API).

P1 is the methodology's most-used primitive. Layered DAG runs always include it implicitly; project extensions can additionally configure it for specific authority pairs.

#### No-upstream case (Layer 0 root authority and minimal-profile single artifacts)

When P1 runs against an artifact that has no upstream authority — the root of a layered DAG, or a single-artifact / minimal-profile review where there is nothing for the artifact to "derive from" — the comparison shifts from external adherence to **internal consistency**. The artifact is reviewed against its own stated goals, structure, and self-references.

Inputs (no-upstream case):
- The artifact under review.
- (No upstream content; the artifact's own header, abstract, section structure, and self-cross-references are the implicit reference.)

Reviewer prompt (no-upstream case): "Review this artifact for internal consistency, ambiguities, gaps, and risks against its own stated goals and structure. Identify contradictions between sections, terminology drift, broken cross-references, schema/example mismatches, and rules whose edge cases are unaddressed."

Findings (no-upstream case): same kinds as the upstream case (`inconsistency`, `ambiguity`, `gap`, `fail`, `risk`, `pass`); the substance shifts from "does X match upstream?" to "is X internally coherent and complete?" Upstream-conflict-deferred is **not applicable** in the no-upstream case (there is no upstream to defer to).

The slash command's setup phase (§ DAG identification → Single artifact) treats a single-artifact review as Layer 0 implicitly; the no-upstream case applies. For multi-layer runs, only Layer 0 uses the no-upstream case; Layer 1+ always have an upstream and use the standard adherence-comparison case.

**Peer mode (no hierarchy declared).** Pure peer mode (per § Layered review pattern) is a single layer of artifacts with no declared external authority. P1 in peer mode runs the **no-upstream case per artifact** — each peer is reviewed for internal consistency against its own stated goals, NOT against the other peers. Peer-to-peer compatibility (the "code and tests must remain mutually consistent" case) is handled by **P4 with peer-compatibility rules** (§ P4 — Structural rules), not by P1. This separation prevents oscillation: P1 stabilizes each peer's internal consistency independently, then P4 surfaces inter-peer inconsistencies as structural findings against a declared compatibility rule. If the project wants a global authority for peer-mode review (e.g., the user's intent or an external charter not in the review scope), declare it explicitly in the project extension's authority documents — peer mode then becomes a layered DAG with that authority as Layer 0.

### P2 — Coverage interpretation (semantic with mechanical pre-check)

Every item in declared set A must have a corresponding item in declared set B (1:1, 1:N, or N:1, as the project specifies).

Mechanical pre-check: enumerate IDs in set A and set B; compute the unmatched-in-A and unmatched-in-B sets. These are the candidates for "coverage gap" findings. Output: a list of candidate gaps with their IDs.

Semantic phase: the reviewer evaluates whether each candidate gap is a *real* gap (a coverage failure) or an explained absence (e.g., "REQ-005 is intentionally deferred per ADR-012"). The reviewer also checks whether existing matches are *substantive* — does the test that mentions REQ-001 actually verify what REQ-001 claims, or is it merely a name match?

Findings:
- `kind=gap` for unmatched-in-A items (items in A that should have a match in B but don't).
- `kind=inconsistency` for matches that are nominal-only (B mentions A's ID but doesn't substantively cover it).
- `kind=risk` for declared deferrals that no longer apply.

Default thinking level: `standard`. The mechanical pre-check is deterministic; the semantic interpretation is what the level governs.

### P3 — Linkage verification (mechanical)

Declared ID-based references between artifact sets must resolve. Orphans (un-referenced items where references are required) and danglers (references to items that don't exist) are findings.

This is purely mechanical — there is no semantic phase. The reviewer's job is to define the linkage rules; the host's job is to verify them.

Inputs:
- ID schemas declared in the project extension (e.g., `REQ-NNN`, `ADR-NNN`, `TKT-NNN`).
- Linkage rules: which schemas link to which, in what direction, with what cardinality.

Outputs:
- `kind=gap` findings for orphans (items lacking required back-references).
- `kind=fail` findings for danglers (references that don't resolve).

Default thinking level: N/A (mechanical primitive; no thinking applies).

P3 is the basis for traceability. Coverage (P2) builds on P3 — without resolved IDs, "every X has a Y" can't be checked. Project extensions that configure P2 typically also configure P3, and the methodology recommends implementing P3 mechanics before P2 prompts (coverage interpretation depends on resolvable identifiers).

### P4 — Structural rules (semantic with mechanical pre-check, optional)

Declared structural rules must be satisfied. Examples:

- Dependency direction: "module A must not import from module B."
- Naming convention: "all public types in `src/api/` must be PascalCase."
- Layering: "code in the persistence layer must not call the presentation layer."
- Peer-compatibility: "named peer artifacts must remain mutually compatible" (the within-layer peer-compatibility case).

Mechanical pre-check (when supported by tooling, e.g., a linter): runs the rule's static check; produces violations as candidate findings.

**Tooling-conditional behavior.** P4's mechanical phase is **conditional on tooling availability declared in the project extension**. When the project declares P4 with a static-check command (linter / dependency-rule checker / etc.), P4 runs as a mixed primitive — mechanical pre-check, semantic phases, mechanical post-check. When the project declares P4 with semantic-only rules (e.g., judgment-based architectural rules with no static checker), P4 runs as a **semantic-only primitive for that run** — mechanical phases are skipped, the audit records `Phase: semantic-iterate / semantic-cross-check / semantic-verify` only, and P4's worst-case budget reduces from 24 calls to 18 (matching the P1 semantic-only shape). The phase-skip behavior follows the general "primitives with no mechanical aspect skip mechanical phases" rule from § Pipeline structure.

Semantic phase: the reviewer evaluates rule violations and surface ambiguous structural decisions that the mechanical check can't catch (e.g., "this architecture violates separation of concerns" — a judgment, not a static rule).

Findings:
- `kind=fail` for hard rule violations (linter caught).
- `kind=ambiguity` for structural decisions the reviewer flags but the rule doesn't formally define.
- `kind=risk` for emerging anti-patterns.

Default thinking level: `standard`.

P4 includes the peer-compatibility pass: when the project declares within-layer peers (e.g., "src/ and tests/ must remain mutually compatible") via the layered-DAG `Within-layer peer constraints:` line or the peer-mode `Peer compatibility constraints:` line in § DAG identification, P4 checks that compatibility. Peer passes are recorded with the same per-call audit format as upstream-adherence passes (file headers carry `**Phase**: semantic-iterate / semantic-cross-check / semantic-verify` and `**Primitive**: P4`), with no special audit shape required — the canonical per-call markdown template covers both adherence and peer-compatibility passes.

### P5 — Validation-hook execution (mechanical)

Declared deterministic commands must succeed cleanly. The host runs each declared hook; non-zero exit, declared-fatal output patterns, or unexpected mutations are findings. Some examples:

- Build: `npm run build`, `cargo build --release`, `make`.
- Type-check: `tsc --noEmit`, `mypy`, `pyright`.
- Lint: `eslint`, `cargo clippy`, `ruff`.
- Test: `pytest`, `vitest run`, `cargo test`.
- Schema validation: `jsonschema --validate`, `proto-check`, `xmllint --schema`.
- Determinism check: build twice, diff outputs (project-defined).

Inputs:
- Hook declarations in the project extension (name, command, side-effect category, timeout, required flag).

Each declared hook has a `side_effects` field with values:

| Value | Meaning | Mutation policy |
|---|---|---|
| `read-only` | Must not modify any tracked or untracked file in the worktree | Any worktree modification triggers M5 halt |
| `generated-output-allowed` | May write to paths matching declared `output_paths` globs | Modifications outside `output_paths` trigger M5 halt |
| `snapshot-updating` | May update paths matching declared `snapshot_paths` globs (e.g., `__snapshots__/`); reviewer should examine diffs as findings | Diffs in `snapshot_paths` are surfaced as findings; modifications outside trigger M5 halt |
| `environment-dependent` | May install/touch declared in-worktree paths (`worktree_paths` globs, e.g. `node_modules/`, `.venv/`, generated caches) AND may touch out-of-worktree state | Modifications inside worktree but outside `worktree_paths` trigger M5 halt; out-of-worktree effects are not audited |

The host enforces side-effect policy by snapshotting worktree state (content-hash + path-set, per `git status` semantics) before each hook runs and diffing after. Tracked, untracked, ignored, and generated files are all included in the snapshot. mtime is not the snapshot key — it's an implementation optimization only when it provably cannot change results.

Findings:
- `kind=fail` for non-zero exit on a `required: true` hook.
- `kind=risk` for non-zero exit on a `required: false` hook.
- `kind=fail` for unexpected mutation (M5 halt; recorded as a finding even though the run halts).
- `kind=risk` for nondeterministic build (M4) when the hook is declared `deterministic: true`.

Default thinking level: N/A (mechanical primitive; no thinking applies).

P5 is the methodology's bridge to non-AI validation. Reviewers can't run tests or type-checkers; the host can. P5 makes those signals first-class participants in the review cycle.

### P6 — Checklist verification (semantic with mechanical pre-check)

For each item in a declared checklist, the host evaluates whether the artifact set addresses it (or explicitly waives it with rationale).

Mechanical pre-check: scan for explicit waiver markers in the artifact (e.g., `<!-- waive: ITEM-005 -->` or a `waivers.md` file) and pre-populate which items are user-acknowledged-deferred.

**Pre-check waiver finding format.** Each detected waiver becomes a finding in the mechanical-pre-check per-call file with `kind=pass`, `severity=info`, `source=evidence`, `title="<ITEM-ID> waived: <waiver rationale or 'no rationale'>"`, `file=<artifact path>`, `location=<line range or section heading where the waiver marker was found>`, `detail` containing the verbatim waiver-marker text. The host assigns the **decision state `already-addressed`** to each waiver finding (NOT the default `skipped` for `kind=pass`) — explicitly so the apply-mode addressed-context construction filter (which emits `applied | already-addressed | upstream-conflict-deferred | invalid`) includes the waiver. The reasoning recorded inline is "P6 waiver: user-acknowledged-deferred per <waiver-marker source>". The semantic phase that follows therefore receives the waiver evidence and knows the item was deliberately deferred, so it should not raise a `kind=gap` finding for it. The semantic phase still surfaces a `kind=risk` finding if the waiver rationale doesn't match the item's substance, per § Findings → Risk for unjustified waivers.

Semantic phase: the reviewer evaluates each non-waived item against the artifact and judges whether the item is genuinely addressed. "Rollback plan documented" is a judgment, not a string match — does the documented plan actually rollback?

Findings:
- `kind=gap` for items that are neither addressed nor waived.
- `kind=ambiguity` for items where the artifact's coverage is unclear.
- `kind=risk` for items declared as waived without justification, or where the waiver justification doesn't match the item.

Default thinking level: `standard`.

P6 is where operational concerns (rollback, observability, security review, on-call docs) are captured. It's also where the user's own personal review process — like the 10-goal list a user might compose for their team — gets instantiated as a project-specific checklist.

## Composability — primitives into goals

Different project goals compose primitives differently. The methodology documents canonical compositions in § Composite recipes; here is a representative sample to anchor the abstraction:

| Project goal | Composes |
|---|---|
| Business alignment | P1 (against charter as upstream authority) |
| Authority consistency | P1 across the layered DAG |
| Coverage | P2 + P3 (linkage resolved first) |
| Traceability | P3 |
| Structural integrity | P4 |
| Executability | P5 (build, type-check, lint, test) |
| Correctness | P5 (validation hooks) + iterating-reviewer cycle (interpretive logic review) |
| Change impact | P3 (linkage discovery of impacted) + P2 (coverage of impacts) + P6 (waiver checklist for deferrals) |
| Determinism | P5 (build twice and diff) |
| Delivery readiness | P6 (rollback / observability / sign-off) + P5 (smoke tests) |

A project that declares a charter as a Layer-0 authority and composes with the right project-extension content gets all 10 of those goals from the same six primitives. A project that declares only P1 + P5 gets a much lighter cycle. Both are valid compositions.

Recipes are documentation. They show users how to compose primitives. They do NOT impose primitive declarations. Each project still declares its own primitives in its project extension; recipes are not opt-in by reference.

## Pipeline structure

For each layer in the DAG, the cycle runs each declared primitive through a five-phase pipeline. Mechanical phases run only when the primitive has a mechanical aspect; semantic phases run only when the primitive has a semantic aspect.

```
Layer setup
  ↓
For each declared primitive (in declaration order):

  ┌─ Mechanical pre-check ───────────────────────┐
  │   Host runs deterministic check              │
  │   Findings collected                          │
  │   Findings enter addressed-context for next  │
  │   (Skipped for primitives with no mechanical aspect)│
  └──────────────────────────────────────────────┘
                    ↓
  ┌─ Semantic iterate ───────────────────────────┐
  │   Iterating reviewer iterates                 │
  │   Until convergence (set-stable, approve, all-invalid, or cap)│
  │   In report mode: ONCE; no iteration         │
  │   (Skipped for terminally-mechanical primitives — P3, P5)│
  └──────────────────────────────────────────────┘
                    ↓
  ┌─ Semantic cross-check ───────────────────────┐
  │   Cross-check reviewer runs ONCE             │
  │   (Skipped if no cross-check reviewer configured)│
  │   (Skipped for terminally-mechanical primitives)│
  └──────────────────────────────────────────────┘
                    ↓
  ┌─ Semantic verify ────────────────────────────┐
  │   Iterating reviewer re-runs ONCE             │
  │   (To catch regressions from cross-check fixes)│
  │   (Skipped if no cross-check reviewer configured;│
  │    skipped in report mode — nothing to verify)│
  │   (Skipped for terminally-mechanical primitives)│
  └──────────────────────────────────────────────┘
                    ↓
  ┌─ Mechanical post-check ──────────────────────┐
  │   Host re-runs deterministic check            │
  │   Catches regressions introduced by edits     │
  │   In report mode: re-validates unchanged artifact│
  │   (Skipped for primitives with no mechanical aspect)│
  └──────────────────────────────────────────────┘
                    ↓
End of primitive cycle. If edits applied → next outer cycle (cap=3).
                    ↓
End of layer (all primitives complete) → propagation step → next layer.
```

The pipeline matters because:

- Mechanical pre-checks are cheap and high-precision; running them first means the (expensive, interpretive) semantic phases don't waste output budget on what tooling can already nail.
- Mechanical post-checks catch regressions Claude or the reviewer introduce during the cycle.
- The audit trail naturally records both classes side-by-side, with mechanical findings dated before the semantic phase that consumed them.
- Each phase has a distinct **Phase** value in the audit metadata (mechanical-pre, semantic-iterate, semantic-cross-check, semantic-verify, mechanical-post), enabling re-parsers to filter precisely.

A primitive with no mechanical aspect skips the mechanical phases entirely (e.g., P1 has no mechanical pre/post; only the three semantic phases run). A terminally-mechanical primitive (P3, P5) skips all semantic phases — only the mechanical phases run.

Per-primitive caps within a layer: 3 outer cycles × 4 inner iterations per outer cycle. Caps apply per primitive — a layer with three configured primitives has up to 3 × 3 × 4 = 36 iterating-reviewer calls in the worst case (plus cross-check, verify, and mechanical phases). Worst-case budget is exposed at layer entry — see § Iteration cycle for the budget-line format.

## Layered review pattern

For multi-artifact reviews, the cycle works best when the artifacts under review form an explicit dependency hierarchy. Most projects have one — even when it isn't written down, there's usually a single "highest authority" document (architecture, charter, methodology) that everything else derives from, with one or more layers of derived documents below it.

The cycle models this as a directed acyclic graph (DAG):

- **Layer 0 (root authority)**: the single highest-authority document. Reviewed against its own merits, no upstream comparison.
- **Layer 1, 2, ...**: each derived document declares which layer-N document(s) it adheres to. Multiple docs can occupy the same layer.
- **Within-layer peer constraints**: docs in the same layer that derive from common upstream may also need to remain mutually compatible. The canonical case: code and tests both derive from design AND must match each other.

Pure peer mode (no hierarchy) is a degenerate case — a single layer with all artifacts as peers under an implicit higher authority outside the review scope (typically the user's intent).

### DAG identification

The cycle's setup phase identifies the DAG before invoking any reviewer. Resolution order:

1. **Project extension's `### Authority documents` subsection** — if the project's `## Cross-AI Review Extension` declares a scope, use that. The extension supports two canonical scope forms; both are mirrored from the project-extension template:

   **Layered-DAG form:**

   ```markdown
   Scope: layered-dag

   Layer 0 (root authority): <single doc>

   Layer 1 (derives from Layer 0): <doc A>, <doc B>
     Within-layer peer constraints: <none | "doc A and doc B must remain mutually compatible">

   Layer 2 (derives from Layer 1): <doc C>, <doc D>
     Within-layer peer constraints: <e.g., "doc C and doc D must remain mutually compatible">
   ```

   Each layer line names the docs in that layer; "derives from" names the upstream layer index (or comma-separated indexes if a layer derives from multiple upstream layers, e.g., "derives from Layer 0+1"). The peer constraints sub-line is optional — omit when not needed. The `Scope: layered-dag` line is optional for layered runs (presence of `Layer 0 (root authority):` implies it); writing it explicitly is recommended for clarity.

   **Peer-mode form:**

   ```markdown
   Scope: peer-mode

   Layer 0 peers: <doc A>, <doc B>, <doc C>

   Peer compatibility constraints: <none | "doc A and doc B must remain mutually compatible (P4 peer-compatibility rule)" | ...>
   ```

   Peer-mode declarations have no `Layer 1+` because peer mode is a single layer of peers (per § Layered review pattern). The `Peer compatibility constraints:` sub-line is optional — omit when no inter-peer P4 rules are declared. When present, each constraint becomes a P4 peer-compatibility rule for the listed peers; if the project also declares a static-check command for that constraint, P4 runs mixed for that rule, otherwise semantic-only (per § P4 → Tooling-conditional behavior).

   The resolution order recognizes both forms — the `Scope:` line (or its implicit form) determines which branch is selected. Single-artifact reviews (one doc named in the extension or via the slash-command argument) skip the extension entirely and resolve via branch 4 below.

2. **Heuristic detection** — when no extension exists or the extension isn't layered, derive a candidate DAG from:
   - File naming conventions (e.g., `architecture.md` + `design.md` + `implementation.md` → architecture is upstream)
   - Cross-references in the docs themselves (if doc A says "see specifications in B", B is upstream of A)
   - Directory structure (more general directories often = upstream)
   - Explicit "authority for X" / "canonical reference" / "source of truth" claims in headers or front matter

   When the candidate DAG is unambiguous, propose it in the `[config]` startup block and proceed without asking. When ambiguous, fall through to the wizard.

3. **Interactive wizard** — when heuristics can't produce a confident DAG, ask the user a short structured set of questions:
   - "Is one of these documents the highest authority?"
   - For each remaining doc: "Which document(s) does this derive from?"
   - Within each derived layer: "Do any of these need to remain compatible with each other (beyond their shared upstream)?"

   After construction, **offer the DAG back to the user as a project-extension snippet they can paste in**, so future reviews don't re-ask.

4. **Single artifact** — no DAG question needed; the artifact is its own scope (treated as Layer 0 implicitly).

5. **Peer mode (multi-artifact, no confident hierarchy)** — when the resolution above produces multiple artifacts with no declared authority, no confident heuristic-detected hierarchy, and the wizard's "is one of these the highest authority?" question is answered with "no" (or all derivation answers are "derives from nothing"), resolve `scope=peer-mode`. All artifacts are recorded as Layer 0 peers. P1 runs the **no-upstream case per artifact** (per § P1 — No-upstream case → Peer mode). P4 peer-compatibility constraints are surfaced separately during the wizard ("do any of these need to remain compatible with each other?") and recorded for the P4 pass; if the project declares a static-check command for the peer-compatibility rule, P4 runs mixed; otherwise P4 runs semantic-only. Peer-mode runs benefit from being offered back as a project-extension snippet exactly like layered runs, so the user can pin the resolved scope (and any P4 peer rules) for future invocations.

### Auto-detection of scope

Auto-detection of review scope (single-artifact vs. layered DAG vs. peer mode) happens at invocation. The `[config]` line at invocation start surfaces the resolved scope:

```
[config] /Users/<user>/.claude/cross-ai-review-config.json
         host=claude(orchestrator)
         iterating=codex(gpt-5.5, thinking=standard)
         cross-check=gemini(gemini-3.1-pro-preview, thinking=standard)
         scope=layered-dag  output_mode=apply
[DAG] Layer 0: docs/architecture.md
      Layer 1: docs/design.md
      Layer 2: src/, tests/ (peers)
```

Users can abort early if the resolved scope is wrong. Auto-detection is **orthogonal to output mode** (apply or report) — any combination of {single-artifact, layered-dag, peer-mode} × {apply, report} is supported.

### Layer-by-layer iteration sequencing

Once the DAG is identified, the cycle iterates one layer at a time, with **explicit propagation** by the host between layers:

1. **Iterate Layer 0 (root authority) to stability first.** Run the standard pipeline (mechanical-pre → semantic-iterate → semantic-cross-check → semantic-verify → mechanical-post) per declared primitive. Outer-cycle and inner-iteration caps apply per primitive. Run the per-layer final self-critique pass before declaring the layer settled.

2. **Host propagation step (Layer 0 → Layer 1+).** Before any cross-AI review of derived layers, the host propagates the now-stable Layer 0 changes through every Layer 1+ doc that references Layer 0. This is **mechanical work**, not substantive re-architecture:

   - Rename references when Layer 0 renamed sections, fields, or terminology
   - Update verbatim quotes when Layer 0's quoted content changed
   - Sync **literal-value examples** when Layer 0's canonical examples changed (e.g., a renamed field appearing in an example object). **Context-dependent examples** (where the example's correctness depends on logical constraints from upstream that propagation alone might not capture) are NOT mechanically synced — instead, flag them in the propagation diff with `requires-substantive-review` and leave them for the downstream layer's cross-AI review pass to evaluate.
   - Update template references when Layer 0's templates changed
   - Verify section-name references in derived docs still resolve

   This step is NOT a cross-AI review — the host does it directly, following the principle that **mechanical drift is the host's job to fix; substantive adherence is the cross-AI review's job to verify**. Wasting reviewer calls on copy-paste drift (which the original cycle did, slowly and unreliably) is replaced by the host doing the propagation deterministically in seconds.

   Record the propagation diff at `<written-at>-propagation.md` per § Audit artifact formats.

3. **Then for each subsequent layer in topological order:**
   - Run the pipeline per declared primitive against the derived layer's artifacts. The reviewer prompt for semantic phases includes the upstream content as immutable reference context.
   - The cross-AI review's job here is **substantive adherence verification** — does this derived doc, in its propagated state, correctly adhere to the upstream methodology? — NOT catching mechanical drift (the host already handled that).
   - After upstream-adherence is stable for all docs in the layer, run a **peer-compatibility pass** (P4 with peer-compatibility rule) for any declared within-layer peer constraints.
   - Run the per-layer final self-critique before declaring this layer settled.
   - Outer-cycle and inner-iteration caps apply per primitive within the layer.

4. **Host propagation step (Layer N → Layer N+1+).** Same as step 2 — after each layer settles, the host propagates stable state to the next layer's docs before that layer's cross-AI review begins. Audit at `<written-at>-propagation.md`.

5. **Disposition pass per layer.** When entering outer cycle 2+ for a given layer, the disposition pass reads only that layer's prior per-call markdown files (filtered by Layer + Primitive + Phase header fields). Per-cycle artifacts use timestamp-prefixed grammar `<written-at>-disposition-<O>.md` and `<written-at>-growth-<O>.md`. Layer + primitive index live in the file's headers (not the filename).

### Cross-layer findings (upstream-conflict)

When a Layer-N (N>0) review surfaces a finding that contradicts an upstream layer (the cross-AI review found something propagation alone couldn't fix because it requires changing the upstream authority), the finding is recorded as **upstream-conflict-deferred** in the per-call markdown. The current layer's review continues; the deferred findings are handled as follows:

- The current layer's review continues; upstream-conflict findings are NOT applied to the current-layer doc.
- At the end of the current layer's review, if any upstream-conflict findings exist, the cycle returns to the contradicting upstream layer for **one more outer cycle** focused specifically on those findings (subject to the upstream layer's outer-cycle cap budget — if exhausted, escalate per § Escalation).
- After the upstream layer re-stabilizes, the host re-runs the propagation step for downstream layers, then resumes the downstream layer review per § Restart semantics below.

This is the rare loop in the layered cycle. Most reviews don't trigger it because Layer 0 is reviewed thoroughly first.

#### Restart semantics

After upstream re-stabilization + re-propagation, the affected downstream layers restart per these rules:

- **Invalidate downstream stability** for the affected layer and any layers below it. Their prior "stable" status is superseded because they were stabilized against an obsolete upstream authority.
- **Start a fresh restart epoch** for each affected downstream layer. The restart epoch is a monotonic counter `R1, R2, ...` that lives in **headers, not filenames** — filenames stay simple per the canonical grammar in § Audit artifact formats. Each new per-call file written after a restart records two header lines: `**Restart epoch**: R<N>` and `**Restart of**: <prior-call-timestamp>`. R0 (the original pre-restart cycle) is implicit; the field is only written into headers when a restart has happened.
- The restart starts the layer at fresh outer cycle indexing (O=1) within the new restart epoch. The layer's outer-cycle cap of 3 still applies per restart epoch. If a layer has accumulated 3 restart epochs without reaching stability, escalate per § Escalation (treating the cumulative restart count as the escalation trigger).
- **Preserve prior per-call files** with their original filenames AND mark them superseded by adding two stable header lines (positioned in the header block, after `**Layer**:`):
  - `**Status**: superseded-by-upstream-change`
  - `**Superseded at**: <ISO 8601 UTC timestamp>`

  Addressed-context construction and disposition pass MUST filter out per-call files where `**Status**:` exactly equals `superseded-by-upstream-change` — see § Re-parsing contract for the canonical filter.
- **Disposition pass on the restarted cycle** treats only the non-superseded prior files as the comparison base. Items that were resolved against the obsolete upstream may flip back to still_open if the upstream change re-introduced them.

### Why layered mode converges faster than peer mode

In peer mode, **inter-peer compatibility checks** (the P4 pass, when peer-compatibility rules are declared) are N-1 dimensional — each artifact must remain compatible with every other peer. A fix to artifact A can break P4 compatibility with peers B, C, D, etc., leading to oscillation across multiple peers. (P1 in peer mode is **per-artifact internal consistency** — see § P1 — No-upstream case → Peer mode — and is NOT N-1 dimensional, so the convergence cost arises specifically from declared P4 peer-compatibility rules, not from P1 itself.)

In layered mode, each artifact's "consistent" check is at most K-dimensional, where K = number of upstream authorities (often just 1). Each fix in a derived artifact only needs to maintain adherence to upstream and (optionally) compatibility with same-layer peers. The search space shrinks dramatically.

This is the architect-toolkit pattern: design must match architecture, code must match design, tests must match design and be compatible with code. Each layer reviewed only against its upstream + same-layer peers.

## Iteration cycle

When invoked via `/cross-ai-review`, the cycle runs **autonomously** in apply mode (the default): the host analyzes each finding, judges its validity, applies the valid ones, and proceeds to the next reviewer call without per-finding or per-iteration user confirmation. Read-only enforcement and no-silent-model-fallback are the inviolable guardrails. The user can interrupt at any point.

In **report mode** (`--report` flag), the cycle runs single-pass per primitive — no iteration loop, no autonomous edits. See § Output modes.

This section describes the **apply-mode** iteration cycle. Differences in report mode are noted inline and detailed in § Output modes.

### Inner cycle (one full iterating-reviewer pass per primitive)

For outer cycles ≥ 2, run a **disposition pass first**: read every per-call `.md` file from the prior outer cycle for the current Layer + Primitive + Phase scope (apply the canonical filters from § Re-parsing contract — status filter to exclude `superseded-by-upstream-change` files; layer + primitive + phase exact-match). Within the filtered set, include all iterating iterations (inner-loop N=1 through whatever N the loop broke at), the cross-check pass, the verify pass, and any mechanical-pre / mechanical-post calls (for primitives that have mechanical phases). The disposition format's `**Phase scope**` line lists the same set, and the mechanical-post continuation rule (§ Outer cycle continuation) feeds unresolved mechanical findings into the next outer cycle, so disposition MUST collect mechanical calls or those continuation triggers will not be re-evaluated. Findings applied or rejected in the prior cycle still belong in disposition because their state can change between cycles. After collecting, dedupe by content tuple `(file, location, underlying-issue)`, then for each unique tuple classify against the current artifact state as `resolved` (underlying issue is fixed), `still_open` (issue persists), `changed` (kind/severity changed without resolution), or `not_applicable` (no longer relevant). Log to `<written-at>-disposition-<O>.md`. Surface any `still_open` items explicitly — they signal fixes from the prior cycle that did not take.

Then for any outer cycle, the inner cycle runs three semantic phases (per § Pipeline structure):

1. **Iterating reviewer** iterates against the artifact (using the first available model from its config chain; with the required read-only flag for that CLI; with the resolved thinking level passed via `--thinking-level`) until findings stabilize. Stop when ANY of:

   - `verdict=approve` with no actionable findings, OR
   - **Set of findings unchanged across two consecutive iterations** — the host judges each finding by content tuple `(file, location, underlying-issue)`, NOT by title. Titles drift naturally on the same underlying issue (reviewer non-determinism); the substance is the comparison key. If every finding in iteration N maps to a same-content prior finding, the cycle has stabilized regardless of title differences, OR
   - All remaining findings classified invalid by the host (nothing to apply), OR
   - **Inner-iteration cap of 4** reached (safety net for pathological cases; force progression to the cross-check pass, or to outer-cycle continuation if no cross-check is configured).

2. **Cross-check reviewer** runs once (using the first available model from its config chain; with the required read-only flag for that CLI). Apply valid actionable findings. **Skipped if no cross-check reviewer is configured (single-reviewer mode).**

3. **Verify pass** — the iterating reviewer runs one verification pass to catch regressions introduced by cross-check-driven changes. **Skipped if no cross-check reviewer is configured** (no cross-check findings exist to verify; nothing for verify to catch).

#### Set-stability via content tuple

The set-stable check compares findings between iterations N-1 and N by **content tuple** `(file, location, underlying-issue)`, not by title. A finding's underlying issue is the substantive defect/risk/ambiguity it identifies. If iteration N's finding "Section 4.2 has ambiguous error handling" matches iteration N-1's "Error handling in Section 4.2 is unclear" by file (`spec.md`), location (`§ 4.2`), and underlying issue (ambiguity in error handling), they're the same finding — set-stable.

Title drift is reviewer non-determinism, not a substantive change. Treating it as a substantive change produces false non-stable signals and pathological cycles.

The host judges content-tuple equivalence semantically — see § Re-parsing contract for the formal contract.

### Addressed-context for reviewer calls after the first

Every reviewer call after the first call **for the current primitive in the current layer** receives an "addressed findings" context appended to the prompt. This prevents output-budget crowding where the reviewer fills its response with already-known issues and fails to surface new ones.

Format: see § Addressed-context construction (under § Audit artifact formats).

In **report mode**, the addressed-context preamble is replaced with a `reported-context` form — see § Output modes.

### Outer cycle continuation

If the inner cycle made any artifact edits (apply mode), repeat for the next outer cycle. **Capped at 3 outer cycles per primitive per layer.** Beyond cycle 3 with edits still landing, stop and escalate (see § Escalation).

**Mechanical-post continuation rule.** If the mechanical post-check produces unresolved findings (regressions or new violations) even when no semantic edits were applied during the cycle, treat as `edits_applied > 0` for continuation purposes. The unresolved mechanical findings end the current outer cycle and trigger the next outer cycle (subject to the 3-cycle cap). At cap, escalate via the existing cap-exhaustion path. The next outer cycle re-runs the full primitive pipeline (mechanical-pre → semantic phases → mechanical-post), since the unresolved findings need re-evaluation in the next cycle's context.

In **report mode**, there is no outer-cycle continuation — a report-mode run is single-pass per primitive.

#### Convergence escape hatch (composes with the cap)

Also terminate cleanly without escalation when an outer cycle completes with all non-`pass` findings classified as valid-but-marginal — i.e., every actionable finding falls under the severity baseline's ALWAYS-suggestion categories (or the project's sharpened equivalent). The artifact is structurally sound; reviewers are nibbling at style margins. Prevents forced escalation in the common-good-artifact case.

### Per-primitive caps and budget surfacing

Caps are **per-primitive per-layer**:

- Inner-iteration cap: 4 per outer cycle
- Outer-cycle cap: 3 per primitive per layer
- Restart-epoch cap: 3 epochs per layer (when upstream-conflict loops trigger restarts)

For a layer with K primitives configured, the worst-case reviewer-call budget per primitive is:

- `iterating_calls`   = 4 × 3       = 12 (inner-iter × outer)
- `cross_check_calls` = 1 × 3       =  3 (one per outer cycle, if cross-check configured; else 0)
- `verify_calls`      = 1 × 3       =  3 (one per outer cycle, if cross-check configured; else 0)
- `mechanical_pre_calls`  = 1 × 3 = 3 (if primitive has mechanical pre-check; else 0)
- `mechanical_post_calls` = 1 × 3 = 3 (if primitive has mechanical post-check; else 0)

Total worst-case per primitive (all phases active, cross-check configured): **24 calls**.

Layer worst-case: sum across all configured primitives.

#### Layer-aggregate cap (optional)

Projects can declare an optional `layer_aggregate_cap` in config to bound total reviewer calls per layer (e.g., "halt if this layer exceeds 60 reviewer calls regardless of per-primitive caps"). Default is `unset` — per-primitive caps apply only.

When an aggregate cap is set, the cycle warns the user at 75% of cap reached, halts and escalates at 100%.

#### Budget line at layer entry

When more than one primitive is configured for a layer, the host emits a budget line at layer entry as the first user-visible output for that layer:

```
[L=0 budget] primitives=[P1, P2, P5]
             thinking=[P1=standard, P2=standard, P5=N/A]
             output_mode=apply
             max_calls = 18 (P1) + 24 (P2) + 6 (P5) = 48 (semantic 36 + mechanical 12)
```

The line is mandatory whenever multiple primitives are configured. Single-primitive runs may omit it.

### Native session-resumption — available but deferred

Both common reviewer CLIs expose native session continuity (Codex `codex exec resume`; Gemini `gemini -p ... --resume`). These could let a reviewer "remember" prior iterations without re-sending context. **Not used in the current cycle**, for these reasons:

- The artifact mutates between iterations, so session-cached state would be stale (model may carry stale line-number references, prior-state quotes, etc.)
- Sessions are opaque — visibility into what the model "remembers" vs. what we explicitly told it is lost
- The disagreement-required gating in addressed-context relies on explicit context; sessions might bypass it
- Cross-reviewer continuity is impossible (sessions can't be shared between different CLIs)

Worth revisiting if (a) iteration token cost becomes a constraint, or (b) we identify a use case where the artifact is stable across iterations (e.g., resumption of a halted run after vendor capacity recovers, where the artifact hasn't changed in the interim).

### Persistence to canonical run directory

All reviewer outputs and decision logs persist to:

```
<repo-root>/tmp/cross-ai-review/$RUN_ID/
```

This path is non-negotiable — every consumer of the run directory (README, INSTALL, the slash command, the per-call markdown filename glob conventions, the cross-run/cross-model comparison patterns) assumes this exact location. If the project does not have `tmp/` gitignored, **warn the user and recommend adding it** (one line: `tmp/`); do not silently switch to an alternate directory. Never use the OS temp directory (`/tmp/` or `%TEMP%`) — those are hidden and wiped on reboot.

`$RUN_ID` is generated at slash-command entry as `YYYYMMDDTHHMMSS-PID` (UTC timestamp + shell process ID for collision avoidance).

### Cycle-1 expansion is expected

Initial fixes substantively improve the artifact. **From outer cycle 2 onward, growth without proportionate net-new actionable findings is the bloat signal**: surface specifically in escalation diagnostics if outer cycle ≥ 2 grows the artifact without surfacing new structural concerns. Full growth-tracking format lives in § `<written-at>-growth-<O>.md` format.

A finding whose **content tuple** matches a prior iteration's finding and is still non-`pass` is evidence the loop is not progressing on that issue. Title-drift on the same content tuple is normal reviewer behavior and is NOT itself a non-progress signal — the comparison key is the substance, not the label. Record content-tuple repeats explicitly; they feed the escalation diagnostics if cycle 3 doesn't stabilize.

## Output modes

The methodology supports two output modes, selectable per invocation via the `--report` flag on the slash command:

| Mode | How invoked | Iteration | Edits applied | Output | Use case |
|---|---|---|---|---|---|
| **apply** (default) | `/cross-ai-review <args>` | Yes — to convergence (caps unchanged) | Yes — autonomous, host applies valid actionable findings | Updated artifact + audit trail | "Make my artifact better" |
| **report** | `/cross-ai-review --report <args>` | Single-pass per primitive (no inner-iteration loop) | No — findings written to file only | `findings-summary.md` + per-primitive filtered views + audit trail | "Tell me what's wrong; I'll decide what to fix" |

Hard rule: autonomous-apply (no per-finding user confirmation) is unchanged in **apply mode**, the default. Report mode is a distinct opt-in mode with different semantics — it does NOT regress apply mode to per-finding confirmation.

### Why report mode doesn't break the cycle

The autonomous-apply cycle's iteration mechanics depend on edits being applied between iterations. Without applied edits, set-stability is trivially true (and falsely positive), addressed-context can't say anything was "addressed," and verify passes have nothing to verify.

Report mode resolves this by **not running the iteration loop at all**. It is structurally a degradation parallel to single-reviewer mode (no cross-check reviewer): the methodology's machinery runs in a simpler topology. Specifically:

- Report mode runs **single-pass per primitive**: the iterating reviewer runs ONCE (not iterated to set-stability), the cross-check reviewer runs ONCE (if configured), and the verify pass is **skipped entirely** (nothing to verify against).
- Termination is reported as `single-pass complete`, **never** as `stable`. Set-stability semantics do not apply.
- If multiple reviewers run, their findings are aggregated independently — not deduped via the iteration mechanism.
- Mechanical pre-checks run as in apply mode. Mechanical post-checks also run in report mode, but as a **re-validation of the unchanged artifact** rather than a regression check after edits.

### Report-mode pipeline (per primitive per layer)

For each declared primitive in this layer:

1. **Mechanical pre-check** (if the primitive has one) — same as apply mode. Findings collected.
2. **Iterating reviewer** runs ONCE — *if the primitive has a semantic phase* (P1, P2, P4, P6). For terminally-mechanical primitives (P3, P5), this step is skipped entirely. Findings collected. No N>1 iteration; no addressed-context referencing prior fixes (because none exist).
3. **Cross-check reviewer** runs ONCE if configured AND if the primitive has a semantic phase. Findings collected.
4. **Verify pass** is **skipped** (no edits to verify).
5. **Mechanical post-check** (if the primitive has one) — runs once against the unchanged artifact. Functions as a re-validation of findings (e.g., a P5 hook re-run confirming command output matches).
6. Findings adjudicated by the host (validity rubric + severity baseline + dedup).
7. Findings written to `findings-summary.md` (and per-primitive filtered views).

There is no outer-cycle continuation in report mode. A single pass through every configured primitive is the run.

For terminally-mechanical primitives (P3, P5), report mode runs only steps 1, 5, 6, 7 — mechanical pre, mechanical post, host adjudication, write to summary. No reviewer calls.

### Output format

The canonical output is a single file: `findings-summary.md` at the top of the run directory. **Per-primitive files (`findings-P1-authority.md`, etc.) are generated filtered views of the canonical**, not separate sources of truth.

`findings-summary.md` structure:

```markdown
# Findings — <RUN_ID>

**Date**: <ISO 8601 UTC>
**Mode**: <cross-AI | single-reviewer>
**Output mode**: report
**Artifact(s)**: <files reviewed, comma-separated>
**Termination**: single-pass complete
**Configured primitives**: <list, e.g., P1, P2, P5>

## Per-primitive findings

### P1 — Authority adherence
<findings, ordered by severity then file/location>

### P2 — Coverage interpretation
<findings>

... (one section per configured primitive)

## Aggregate counts
- Total findings: <n>
- By severity: <breakdown>
- By kind: <breakdown>
- By primitive: <breakdown>
```

Each finding entry uses this shape:

```markdown
#### <Title> — <kind> / <severity>
- **File**: `<file>`
- **Location**: `<location>`
- **Origin**: <iterating-reviewer | cross-check-reviewer | mechanical-pre | mechanical-post>
- **Source**: <reviewer | evidence>
- **Origin detail**: <reviewer's verbatim detail | host-run command output | hook name + exit context>
- **Origin suggestion**: <reviewer's verbatim suggestion | "none" | mechanical hooks have no suggestion field>
- **Host adjudication**: ✓ valid · reported-valid | ✗ invalid · reported-invalid
- **Host reasoning**: <validity rubric category + reasoning>
- **Host severity adjustment**: <none | downgraded from <X> to <Y>: reason>
```

The **Origin detail** and **Host adjudication** fields are kept separate so users see both layers and can override the host's judgment if they disagree. Raw reviewer outputs and raw mechanical-hook stderr remain in per-call audit files unchanged.

**Origin** captures four possibilities — the two semantic-reviewer roles plus the two mechanical phases. Origin=`mechanical-pre` carries `Source=evidence`, comes from the host's pre-pass deterministic check, and uses the hook's command output as `Origin detail`. Origin=`mechanical-post` captures the same shape but from the post-pass re-validation.

**Mechanical pre/post disagreement.** When `mechanical-post` produces findings that differ in count or content from `mechanical-pre` against the same unchanged artifact, the disagreement is itself surfaced as a finding (not silently collapsed). It appears in `findings-summary.md` under the relevant primitive with kind `risk` (default severity medium) and Origin `mechanical-post`, naming the divergence. This is the mechanical-side analogue of M4 (nondeterminism) and uses the same disposition: by default a finding (not a halt), configurable to halt when the affected hook is declared `deterministic: true`. Apply mode and report mode share this disposition; report mode additionally surfaces the finding in `findings-summary.md` because there is no iteration loop to absorb it.

### Addressed-context in report mode

Apply mode's addressed-context preamble says "the following findings have been addressed" — that wording cannot be used when no edits were applied. Report mode uses a **`reported-context`** preamble form instead:

> The following findings were raised in earlier passes of this run. They have NOT been applied (this is a report-only run). The reviewer may re-raise any of them; repeats will be aggregated as additional evidence rather than rejected as already-addressed.

In report mode, **repeats are not auto-rejected** as duplicates the way apply mode rejects re-raises without disagreement. Findings raised by multiple reviewers (or by the same reviewer across passes) are aggregated in `findings-summary.md` with reviewer attribution, not deduplicated away.

### Decision-state taxonomy in report mode

Apply-mode and report-mode use distinct decision-state taxonomies. Apply-mode states have precise meanings:

- **`applied`** — the host changed the artifact in response to this finding.
- **`skipped`** — the finding is valid but not actionable (e.g., `kind=pass`); no action taken.
- **`already-addressed`** — the finding is valid but the underlying issue was already resolved by a prior finding's edit; no new edit needed.
- **`upstream-conflict-deferred`** — the finding is valid but contradicts an upstream-layer authority; deferred per § Cross-layer findings (upstream-conflict). No edit applied to current layer.
- **`withheld-class-e`** — the finding came from a Class E (silent fallback) call; not used because review integrity is compromised. Findings remain in the per-call file for audit but are not applied.

Report mode adds two new states:

- **`reported-valid`** — host's adjudication concluded the finding is valid. The user is expected to act on it. Source field captures whether the finding came from a reviewer or evidence (mechanical check).
- **`reported-invalid`** — host's adjudication concluded the finding is invalid (per the validity rubric). Reasoning is logged in the per-call audit file and in the `findings-summary.md` entry.

Re-parsing contract recognizes these two new states. Apply-mode states remain apply-mode-only — they do not appear in report-mode runs (which never apply edits).

### Halt taxonomy in report mode

Halt behavior is largely unchanged:

- **Class E (silent fallback)** still halts immediately — review integrity depends on findings being attributable to the requested model.
- **M1 (tool unavailable)** with `required: true` still halts the layer. With `required: false`, it records a finding and proceeds.
- **M5 (unexpected mutation by read-only hook)** still halts (cycle's read-only invariant for the artifact is compromised).
- **M2-M4** remain findings (not halts) unless the project explicitly configures otherwise.

Report mode does NOT change halt semantics — the same conditions that halt apply mode halt report mode.

### Final self-critique in report mode

Apply mode runs a per-layer final self-critique pass that performs **dismissal-verification** (re-reading rejected findings against the artifact to confirm rejection reasons cite content, not the host's reasoning alone) plus the project's final-pass criteria evaluation.

In report mode, dismissal-verification is structurally not applicable — no edits were applied, so there is no post-edit state to verify rejected findings against. Therefore:

**Final self-critique is SKIPPED in report mode.** The host adjudication step that runs as part of the report-mode pipeline (validity rubric + severity baseline + dedup) IS the host's contribution to filtering in report mode; it covers the same intent as the final-pass criteria evaluation but at the per-finding level rather than as a separate post-cycle pass.

If a project's final-pass criteria includes checks that should still run in report mode (e.g., "verify no placeholders remain"), those checks are appropriate to declare as P5 validation hooks (mechanical) or P6 checklist items rather than as final-pass criteria, so they run naturally as part of the report-mode pipeline.

### Termination semantics

The termination record for a report-mode run is one of:

- **`single-pass complete`** — the run completed all configured primitives in a single pass without halt. Findings written to `findings-summary.md`.
- **`halt-classified <class>`** — the run halted on Class A-G or M1-M5 conditions per the existing halt taxonomy. The `halt-classification.md` is the termination record; whatever partial findings exist at halt time are written to `findings-summary.md` with a banner indicating the run halted.

The `single-pass complete` label applies ONLY to non-halted runs. Halted report runs use the existing halt-classification audit pattern unchanged.

## Thinking levels

Reviewer calls (semantic primitives only) consume reasoning effort that affects cost and quota. The methodology specifies thinking levels using a **reviewer-agnostic abstract vocabulary**; provider helpers translate to native form internally.

### Vocabulary

Three abstract tiers:

| Level | Intent |
|---|---|
| `fast` | Minimum cost; appropriate for quick screening |
| `standard` | Balanced; appropriate for routine review |
| `deep` | Maximum effort; appropriate for complex semantic judgment |

These are the **only** levels the methodology recognizes. Provider helpers map abstract → native (e.g., a Codex helper maps `standard` to `model_reasoning_effort=medium`; a Gemini helper maps it to a thinking-budget value). The mapping is a **helper-owned implementation detail**; the methodology does NOT enumerate native values.

Configuration must remain schema-governed and auditable. **There is no "helper-edit escape hatch"** — users wanting to override native values must do so through the schema (a future v2 extension if needed), not by editing helper scripts directly. Local helper edits would bypass the audit trail and break reproducibility.

### Default per-primitive levels

The methodology recommends **conservative defaults**: every semantic primitive defaults to `standard`. Projects opt up to `deep` per primitive when the use case warrants it.

| Primitive | Default | Notes |
|---|---|---|
| P1 — Authority adherence | `standard` | Documented as the best candidate for a project-level `deep` override when authority interpretation is complex or high-risk. |
| P2 — Coverage interpretation | `standard` | |
| P3 — Linkage | N/A | Mechanical primitive; no thinking applies. |
| P4 — Structural rules | `standard` | |
| P5 — Validation hooks | N/A | Mechanical primitive; no thinking applies. |
| P6 — Checklist | `standard` | |

P3 and P5 are **terminally N/A** unless a future semantic sub-pass is added to those primitives. The audit header for mechanical-phase calls records `Thinking level: N/A (mechanical)`.

### Override hierarchy

Effective thinking level for any reviewer call is resolved in this precedence:

1. **Project per-primitive override** — declared in the project extension's `### Thinking levels (per-primitive)` subsection.
2. **Provider default** — declared in the user's `~/.claude/cross-ai-review-config.json` as `providers.<name>.thinking_level`.
3. **Methodology fallback** — `standard` for semantic primitives; N/A for mechanical primitives.

### Validation of project-extension declarations

Project-extension thinking-level overrides are schema-validated at slash-command entry. The cycle fails fast (does not start) when:

- An override is declared for a primitive the project hasn't otherwise configured (declared in the extension's primitive sections). This catches typos like declaring `P7` (no such primitive) or declaring P2 thinking but no P2 coverage mapping — both render the override unreachable.
- An override is declared for a terminally-mechanical primitive (P3, P5). These primitives have no semantic phase to which a thinking level applies; the override is meaningless. If a future v2/v3 introduces a semantic sub-pass for a currently-mechanical primitive, the override schema will gain that primitive at the same time; until then it is rejected.
- An override value is not one of the abstract levels (`fast | standard | deep`).

Failure messages cite the offending declaration and name the rule violated, so users can correct without guessing.

This is schema-governed validation, not silent no-op behavior — the goal is reproducibility and typo detection, not lenient acceptance.

### Resolution stability

Effective thinking level is **resolved once per primitive call type at layer entry** and remains stable across:

- Inner iterations (apply mode)
- Outer cycles (apply mode)
- Single-pass execution (report mode)

On a Class C/D fallback to a different model in the chain, the **abstract** level stays the same but the **native** value may change (different model, possibly different mapping). The native value is re-audited on every fallback.

### Audit header format

Per-call `.md` headers carry a single `Thinking level` field. The field has two canonical grammars — one for semantic-phase calls, one for mechanical-phase calls — re-parsers may exact-match on either.

**Semantic-phase grammar** (Phase ∈ {`semantic-iterate`, `semantic-cross-check`, `semantic-verify`}):

```
**Thinking level**: <abstract> (native: <native-value-or-marker>)
```

Where `<abstract>` is `fast | standard | deep` and `<native-value-or-marker>` is the provider helper's resolved native value (e.g., `codex model_reasoning_effort=medium`) OR the literal marker `unsupported` when the provider has no supported thinking-level knob.

Examples:

```
**Thinking level**: standard (native: codex model_reasoning_effort=medium)
**Thinking level**: deep (native: codex model_reasoning_effort=high)
**Thinking level**: standard (native: unsupported)
```

**Mechanical-phase grammar** (Phase ∈ {`mechanical-pre`, `mechanical-post`}):

```
**Thinking level**: N/A (mechanical)
```

This is the **exact literal form** for mechanical-phase calls. No abstract level appears (none applies); the parenthetical is `(mechanical)` not `(native: ...)`.

Re-parsing contract for the field:

- A line matching `^\*\*Thinking level\*\*: (fast|standard|deep) \(native: ` is a semantic-phase record; capture both the abstract level and the native value.
- A line matching `^\*\*Thinking level\*\*: N/A \(mechanical\)$` is a mechanical-phase record; no abstract level applies.
- Any other shape is malformed and surfaces as a re-parsing finding (severity medium per § Re-parsing contract).

The `unsupported` marker is recorded explicitly — never silently omitted — so future forensic review can distinguish "this provider couldn't honor the level" from "we forgot to record it."

### Stale-config error

The pre-v1 config field `providers.codex.reasoning_effort` is **removed without a compatibility alias**. A config still containing it must fail loudly with an actionable error:

```
ERROR: providers.codex.reasoning_effort is removed in v1.
Replace with providers.codex.thinking_level using:
  low    → fast
  medium → standard
  high   → deep
```

Validation runs at slash-command entry. Stale configs prevent the run from starting, with the migration mapping included in the error message.

### Helper translation contract

Each provider helper documents its abstract → native mapping in its README. The mapping is helper-owned implementation, not methodology content. The contract:

- Helpers MUST accept `--thinking-level <fast|standard|deep>` and translate internally.
- Helpers MUST emit the resolved native value for inclusion in the per-call audit header.
- Helpers running on an `N/A` primitive (mechanical phase) are not expected to receive `--thinking-level`.
- Helpers running on a provider that doesn't support thinking-level control MUST record `native=unsupported` in the audit value.

The helper interface is `--thinking-level <abstract>` — universal, replacing the legacy Codex-only `--reasoning <effort>` parameter.

## Configuration

Provider, model, and role choices are read from a config file at **`~/.claude/cross-ai-review-config.json`**. This file is the user's source of truth — they edit it when they want to swap which provider is iterating, prefer a newer model, or drop a provider entirely. They do **not** need to edit it just because they installed or uninstalled a CLI; the slash command auto-detects which CLIs are present at runtime.

### Schema

```json
{
  "schema_version": 1,
  "providers": {
    "codex": {
      "models": ["gpt-5.5", "gpt-5.4", "gpt-5.4-mini"],
      "thinking_level": "standard"
    },
    "gemini": {
      "models": ["gemini-3.1-pro-preview", "gemini-3-flash-preview"],
      "thinking_level": "standard"
    }
  },
  "role_preference": ["codex", "gemini"],
  "layer_aggregate_cap": null
}
```

- `providers.<name>.models` — left-to-right preference. The first entry is the preferred model; subsequent entries form the documented fallback chain consulted by the halt-signal taxonomy on Class C/D failures.
- `providers.<name>.thinking_level` — abstract level (`fast | standard | deep`). Default `standard`. Applied to every semantic call this provider makes unless overridden by a project extension's per-primitive declaration.
- `role_preference` — providers in iterating-first order. The first available provider fills the **iterating reviewer** function; the next fills the **cross-check reviewer** function. Swap the order to swap functions.
- `layer_aggregate_cap` — optional integer; bounds total reviewer calls per layer regardless of per-primitive caps. Default `null` (no aggregate cap; per-primitive caps apply only).

### Resolution order at runtime

Read every invocation (microsecond cost; ensures edits take effect immediately):

1. Per-invocation overrides (none currently defined; reserved for future flag support)
2. Project's `CLAUDE.md` `## Cross-AI Review Extension` → `### Provider override` subsection
3. Global config: `~/.claude/cross-ai-review-config.json`
4. Shipped defaults (Codex iterating with `gpt-5.5` chain, Gemini cross-check with `gemini-3.1-pro-preview` chain, both at `thinking_level: "standard"`)

Merge semantics across precedence layers are **shallow per-top-level-key replacement** — a higher layer's `providers` (or `role_preference`) entirely replaces the lower layer's. Within `providers`, including a provider means restating its full intended block; partial-block inheritance is intentionally not supported, to avoid silent surprises like a `models` override leaving a `thinking_level` from the global tier.

### Auto-detection of installed CLIs

After loading config, run a presence check for each provider in `providers`. A provider that is not installed (or not authed at first call) is marked unavailable and skipped during role resolution. This is what makes "the user installed a new CLI last week" work without a config edit — auto-detection picks it up on the next invocation.

### Single-reviewer mode

If `role_preference` resolves to only one available provider, the cycle runs in **single-reviewer mode**: the iterating reviewer function runs as configured; cross-check and verify phases are skipped per § Pipeline structure. Validity judgment, severity baseline, addressed-context, disposition pass, growth tracking, and final self-critique all still run. The audit trail records the mode in each per-call `.md` file's header and in the final `review-summary.md`.

### Common edits

- **Adopt a new model** (e.g., `gpt-5.6` ships): prepend it to the relevant `providers.<name>.models` list.
- **Swap iterating/cross-check assignment**: swap the order of `role_preference`.
- **Drop a provider permanently**: delete its block, or just uninstall the CLI.
- **Add a provider later**: install/auth its CLI; if it's already in `providers` and `role_preference`, the next invocation uses it automatically.
- **Increase thinking-level globally**: set `providers.<name>.thinking_level` to `deep`. (Will be overridden per-primitive if the project extension declares overrides.)

## Project extension discovery

Before invoking reviewers, check the project's `CLAUDE.md` (the project root, not this global file) for a section titled `## Cross-AI Review Extension`. If present, that section names:

- **Authority documents** — layered DAG declaration. See § Layered review pattern → DAG identification.
- **Per-primitive declarations** — which primitives are configured for this project, with their content (authority pairs, ID schemas, coverage mappings, structural rules, validation hooks, checklist items).
- **Thinking levels (per-primitive)** — overrides to the provider default for specific primitives.
- **Severity discipline overrides** — project-specific rules that sharpen the generic severity baseline.
- **Final-pass criteria** — what the host's per-layer final self-critique evaluates against (apply mode only; skipped in report mode).
- **Provider override** — project-pinned config that takes precedence over the user's global config.

If the project has no extension section, the cycle runs with **minimal profile** defaults — see § Minimal profile.

Templates and methodology documents remain owned by the project; the global cycle composes with them, it does not replace them.

## Read-only is non-negotiable

Reviewers MUST NOT modify any artifact under review. The host (Claude) is the only entity that edits artifacts between review iterations. Reviewers report; host applies.

Always invoke reviewer CLIs with read-only sandboxing. NEVER use any of these flags:

- Codex: `--full-auto`, `--dangerously-bypass-approvals-and-sandbox`, `-s workspace-write`, `-s danger-full-access`
- Gemini: `-y` / `--yolo`, `--approval-mode auto_edit`, `--approval-mode yolo`, `--approval-mode default`

Required flags every invocation:

- Codex: `-s read-only`
- Gemini: `--approval-mode plan`

Helper scripts enforce this. The slash command does not invoke reviewer CLIs directly — it invokes through helpers that hard-code the read-only flags. This prevents accidental flag-reordering or copy-paste errors from compromising the read-only invariant.

The read-only invariant also applies to **mechanical hooks** (P5). Hooks declare side-effect categories (read-only, generated-output-allowed, snapshot-updating, environment-dependent — see § P5 — Validation-hook execution (mechanical)). The host snapshots the worktree before each hook runs and verifies post-hook state matches the declared category. Unexpected mutations (M5) halt immediately.

## Halt-signal taxonomy

When a reviewer call fails, **classify the failure before deciding** whether to halt, retry, or fall back. The cycle uses two parallel taxonomies — one for AI-reviewer failures (Class A-G), one for mechanical-hook failures (M1-M5). The two are independent; a layer can have AI halts AND mechanical halts simultaneously, recorded with class prefix to disambiguate.

### AI reviewer classes (A through G)

**Class A — Confirmed hard halt** (always abort, no fallback):
- Authentication / permission errors (401, 403)
- Account suspended / billing issue
- Persistent network failure after one quick retry
- Caller-supplied invalid request (400 with structured error code, e.g., `INVALID_ARGUMENT`, `invalid_request_error`, or `invalid_json_schema` — including malformed `--output-schema` rejected by the structured-output API at request time before any model reasoning runs)

**Class B — Account quota exhausted** (user-level, persistent until reset):
- Codex: stderr contains `payment required`, `usage limit`, `monthly quota`, `daily quota` plus a non-zero exit
- Gemini: structured error with `code: 429`, `status: RESOURCE_EXHAUSTED`, and `details[].reason: QUOTA_EXCEEDED` (NOT `MODEL_CAPACITY_EXHAUSTED`)
- If a `retry-after` header or `retryDelay` field is parseable → use it; otherwise classify reset as "unknown — likely a daily or monthly window"
- Action: halt. User options: wait for the account's quota window to reset, change the account's quota allocation if their billing arrangement allows it, or skip the artifact.

**Class C — Server-side capacity exhausted** (vendor's servers overloaded, not the user). Has two sub-classes:
- **C1 (transient)**: typically clears in 10-30 minutes
- **C2 (sustained)**: persists across multiple retry attempts spanning >30 minutes; may indicate regional issue, account-tier rate limit, or sustained vendor service overload
- Gemini: structured error with `code: 429`, `status: RESOURCE_EXHAUSTED`, and `details[].reason: MODEL_CAPACITY_EXHAUSTED` (not `QUOTA_EXCEEDED`). Error type `RetryableQuotaError` from Gemini CLI is a Class C indicator.
- Codex: HTTP 503/529, "service overloaded", "try again later"
- Action: try the next model in the documented fallback chain. If the entire chain returns Class C, halt that call as **`C-chain-exhausted`** and write the halt-variant per-call audit file. Sub-class disposition:
  - First attempt → record halt-classification reason as "C1 — transient, retry in 10-30 minutes"
  - If a retry attempt >30min later still hits chain-wide Class C → reclassify as C2 ("sustained service capacity, skip and try tomorrow")

  **Cross-run state — human-facing guidance only.** The C1 → C2 reclassification rule is **human-facing triage guidance**, not an automated cycle behavior. Each `/cross-ai-review` invocation runs in an isolated `$RUN_ID` directory and halts immediately on chain-exhaustion; the cycle does NOT inspect prior run directories to compute the >30min window. The reclassification narrative is for the user reading two `halt-classification.md` files from separate runs and deciding whether to re-attempt soon (C1) or wait until tomorrow (C2). No global cross-run state file is read or written; no automated promotion of C1 → C2 occurs. Implementations MUST NOT add cross-run state machinery to automate this — the user's decision is the authoritative signal.
- NOT an account-quota issue; the user changing their billing arrangement won't help in either sub-class.

**Class D — Model not available on this account** (account configuration):
- HTTP 404 with `ModelNotFoundError` ("Requested entity was not found")
- Action: skip this model; try the next in the fallback chain. If a fallback succeeds, label the run with the actual model used (do not silently report the requested-model name). If **every** model in the provider chain returns Class D for the same logical role call, halt that call as **`D-chain-exhausted`** and write the halt-variant per-call audit file. Do NOT silently re-resolve the role (e.g., promoting cross-check to iterating) — role re-resolution is a configuration decision the user must make explicitly. Recovery: (a) update `providers.<name>.models` in the config to slugs the account has access to, (b) drop the provider entirely, or (c) skip the artifact for now.

**Class E — Silent model fallback** (catastrophic for review integrity, ALWAYS halt):
- Response's reported model field does not match the model passed via `-m`, AND the reviewer call did NOT explicitly fall back via the documented chain
- Gemini's documented Pro→Flash auto-degrade is the canonical example
- Action: immediate halt, no exception. The review's integrity is compromised because findings can no longer be attributed to the requested reviewer.

**Class F — Suspected transient bug**:
- Error message contains content irrelevant to the API call (e.g., `Ripgrep is not available` mixed into a Gemini API failure)
- Error structure inconsistent with documented format
- Single retry after 10-30 seconds → if succeeds, log as `retried-after-suspected-bug` and proceed; if fails identically, reclassify into the appropriate class (B/C/D) and follow that class's policy
- Do NOT loop on this — one retry only, then escalate

**Class G — Unclassified**:
- Error pattern doesn't match any class above
- Action: halt and surface the raw error to the user for triage. Do not silently continue or guess — unclassified errors may include security-relevant signals (token leak, unexpected backend call, etc.).
- **Triage direction** to record in `halt-classification.md` and surface to the user: (a) check the vendor's status page for known incidents, (b) check whether your installed CLI version matches the vendor's current stable release, (c) check local network state and DNS, (d) inspect the raw error for references to other CLIs/tools the reviewer might have invoked unexpectedly, (e) check whether the error includes any token, key, or credential material — if so, treat as a security incident and rotate before proceeding.

### Mechanical hook classes (M1 through M5)

**M1 — Tool unavailable**:
- Command not found, install required, or permission denied to execute the hook command
- Action depends on hook's `required` flag:
  - `required: true` → halt the layer with M1 (analogous to Class A — configuration error)
  - `required: false` → record a finding ("hook X unavailable, validation skipped") and proceed

**M2 — Command error**:
- Hook ran successfully but exited non-zero with diagnostic output
- Action: always a finding (not a halt). The hook's output IS the finding's `detail`.

**M3 — Timeout**:
- Hook ran longer than its declared `timeout_seconds`
- Action: finding by default (kind=`risk`); project may configure a single retry. Default retry count: 1. Configurable up to 3.

**M4 — Nondeterministic result**:
- Run-twice-and-diff produces different output (only checked when hook is declared `deterministic: true`)
- Action: finding. Severity high if the hook is declared `deterministic: true`. Configurable to halt instead (project-level setting).

**M5 — Unexpected mutation**:
- A hook with `side_effects: read-only` (or any category) modified files outside its declared scope
- Action: HALT — the cycle's read-only invariant for the artifact is compromised. Same severity tier as Class E.

The mechanical taxonomy is independent of the AI taxonomy. Class prefix in `halt-classification.md` disambiguates: `A`-`G` for AI, `M1`-`M5` for mechanical.

### Documented fallback chain

Fallback only applies to AI Class C and Class D. Use the chain in order; stop as soon as one model succeeds. Label all run artifacts with the actual model used.

The chain for each provider is the `providers.<name>.models` array in the loaded config. The user-edited config IS the documented chain.

When falling back, **explicitly invoke the next model with `-m <slug>`**. Never let the CLI's internal auto-fallback decide. If the CLI auto-falls-back without explicit `-m`, that's Class E (silent fallback) and triggers an immediate halt.

### Fallback audit grouping rule

A fallback chain (Class C/D recovery — multiple `-m` attempts within one logical reviewer role call) MUST produce **exactly one per-call markdown file**, regardless of how many model attempts it contained. The whole chain is one logical reviewer call from the cycle's perspective, so dispositions, addressed-context, and disposition counts treat it as one event. Recording rules:

- **`Model requested`** (per-call header): the **first** model slug attempted (i.e., the preferred model from the config chain at the time of the call).
- **`Model actual`** (per-call header): the model slug whose response was used for findings — the first attempt that succeeded with verified actual-model match. If every attempt in the chain failed, this is the last attempted slug, paired with a halt event.
- **Filename**: contains no model segment per the unified grammar (model identity is recorded in headers only — `Model requested`, `Model actual`, `Fallback attempts`). Filename uniqueness comes from `<call-started>` regardless of which model in the chain produced findings.
- **`Fallback attempts`** (per-call header): comma-separated list of `<model>:<class>` for every attempt **other than the successful one** (e.g., `gemini-3.1-pro-preview:C`). Empty (`none`) when the first attempt succeeded.
- **`## Raw stderr`**: contains the stderr capture from the **final** attempt (the one whose findings were used, or — on full-chain halt — the last one tried).
- **`## Fallback attempt logs`**: **always present** in every per-call `.md`. Body shape depends on `Fallback attempts`: when it is `none`, the section body is the literal sentinel `_None — first attempt succeeded._`; when it is non-empty, the body is one labeled fenced code block per failed attempt, in chain order, captioned `### <model> — Class <X>`, containing the failed attempt's stderr capture inlined.
- **`## Halt event`**: present only when the entire chain halted (no successful attempt). For partial-chain halts where a later attempt succeeded, the prior failures appear in `Fallback attempts` AND have their stderr captured in `## Fallback attempt logs`, but no halt event is logged (the call as a whole succeeded).

This rule prevents the same logical reviewer call from being recorded as multiple per-call files (which would double-count in disposition and addressed-context) while still preserving full audit traceability of each attempt.

### Parsing structured error reports

When a reviewer call fails:

1. **Capture full stderr** (do not truncate to last few lines)
2. **For Gemini**: also read the structured error report written to the OS temporary directory:
   - macOS: `/var/folders/.../gemini-client-error-*.json`
   - Linux: `/tmp/gemini-client-error-*.json`
   - Windows: `%TEMP%\gemini-client-error-*.json`

   The CLI writes one per failed call. Parse `.error.code`, `.error.status`, `.error.details[].reason` to classify.
3. **For Codex**: parse stderr for HTTP status codes, header echoes (`retry-after`, `x-ratelimit-reset`), and known error patterns
4. **Reset timing**: if any source provides a parseable reset timestamp, log it and surface to the user. Otherwise use class-based defaults (Class B: "account quota window", Class C: "minutes")

Log the classification decision and evidence to `tmp/cross-ai-review/$RUN_ID/halt-classification.md`. Include: requested model, actual response (if any), error type, parsed class, fallback chain attempts, reset timing (if found), final action taken.

## Validity judgment rubric

For every finding from any reviewer (or evidence finding from a mechanical hook), classify as **valid** or **invalid**, log the decision, then apply only the valid actionable ones (kind ∈ {fail, ambiguity, inconsistency, gap, risk}) — apply mode. In report mode, valid findings are recorded as `reported-valid`; invalid as `reported-invalid`.

**Valid:** factually correct, in-scope (about the artifact under review), actionable (the host knows what change addresses it), and not contradicted by explicit user instructions or established project conventions.

**Invalid (common reasons to log):**

- Out-of-scope — concerns code/files not in the review set
- Misread — reviewer misunderstood the diff or current state
- Style preference disagreeing with project conventions
- Speculative — "could be a problem someday" without concrete impact
- Duplicate — already addressed by another applied finding
- Conflicts with explicit user instruction or project CLAUDE.md
- Contradicts a higher-confidence finding from a prior iteration

The validity rubric applies equally to **reviewer findings** and **evidence findings** (mechanical hook outputs). A coverage gap from P3 may be invalid if the IDs are typos in the source-of-truth, not actual gaps. A hook error from P5 may be invalid if the hook is mis-configured for the project's environment.

Decision is recorded inline in the per-call `.md` file's `## Findings` section per § Audit artifact formats. There is no separate decisions file.

## Severity baseline

In the absence of project-specific severity rules (via the extension section), apply this generic baseline when judging findings.

**ALWAYS suggestion (cannot be high/critical, never blocks the gate):**

- Formatting, line spacing, markdown structure
- Stylistic clarity or wording preference
- Terminology harmonization that does not change meaning
- Speculative edge-case hardening for scenarios not demonstrated to occur in the artifact's evidence
- Adding redundant checks for conditions already covered
- Regex or command expansion for hypothetical names not in the evidence

**Allowed to be high/critical:**

- Findings that violate stated governance, contracts, or invariants
- Findings that break executability or determinism
- Findings that demonstrate concrete failure scenarios

If a reviewer marks a finding as `severity: high` or `critical` but the finding falls into the always-suggestion list above, **auto-downgrade to `severity: low`** in the decision log with reason `severity-baseline-downgrade: <category>`. The finding remains valid but cannot block the gate.

### Default severity baseline for evidence findings

Mechanical findings (`source: evidence`) carry these default severities (project-extension can override):

| Mechanical finding | Default severity |
|---|---|
| Failed required validation hook (P5, M2 with `required: true`) | high |
| Failed advisory validation hook (P5, M2 with `required: false`) | low |
| Unresolved linkage / orphan ID / dangling ref (P3) | medium |
| Coverage gap — declared item without match (P2 mechanical pre-check) | medium |
| Nondeterministic build / test (M4 with `deterministic: true`) | high |
| Unexpected mutation by read-only hook (M5) | critical (halt-adjacent) |
| Tool unavailable for required hook (M1 with `required: true`) | high (halts) |
| Tool unavailable for advisory hook (M1 with `required: false`) | low |
| Mechanical pre/post disagreement (run-time nondeterminism) | medium |

Project extensions can sharpen this list (e.g., naming explicit ALWAYS-suggestion categories not covered above, or requiring a concrete-failure justification field for any non-suggestion finding).

## Final self-critique pass

After the cycle terminates cleanly (apply mode only — see § Output modes for report-mode behavior), the host runs a dedicated final pass against the project's **final-pass criteria** (named in the extension section).

**Scope in layered runs**: the final self-critique runs **once per layer**, immediately after that layer reaches clean termination and BEFORE moving to the next layer. This ensures each layer is fully settled (including final-pass dismissal verification) before downstream layers are reviewed against it. There is NO additional whole-run final self-critique after all layers complete — the per-layer passes are sufficient.

If a per-layer final self-critique modifies the layer's docs (per the cap-aware branching below), and that layer is upstream of any later layer, the modification is fine because later layers haven't been reviewed yet. The modification CANNOT be triggered after downstream layers are stable (since the final pass runs at layer clean-termination, before downstream review starts).

This pass:

- Is performed by the host in-process — no API call, no reviewer CLI.
- Evaluates the artifact against the project's final-pass criteria AND a generic dismissal-verification rule: any finding rejected as invalid earlier in the cycle must have a logged reason citing artifact content, not the host's reasoning alone. Re-verify each invalid-rejection against the actual file content.
- Produces markdown output to `<written-at>-final-self-critique.md` in the run directory (one file per layer; the file's content scopes to that layer only).
- If it surfaces any new actionable issues, behavior depends on remaining outer-cycle budget:
  - **If budget remains** (current cycle index < 3): apply the issues and run one more outer cycle. The next outer cycle counts against the 3-cycle cap as usual.
  - **If the cap is exhausted** (current cycle index = 3): do NOT silently apply and re-iterate. Apply only the suggestion-tier issues (severity-baseline ALWAYS-suggestion categories) and produce the clean-termination summary noting "applied at-cap final-pass suggestions." Escalate any non-suggestion final-pass issues by listing them in `review-summary.md` under an "Unresolved (escalation)" section, leave the artifact in its pre-final-pass state for those issues, and recommend the user run a fresh `/cross-ai-review` invocation (which gets a new 3-cycle budget) or apply the issues manually.
- If the project has no final-pass criteria, run a generic check: the artifact's stated definition-of-done has corresponding verification, no placeholders remain, internal cross-references agree.

This final pass closes the gap between "reviewers agree" and "host has done its own honest review against project-specific criteria the reviewers may not weigh." It is a generalized self-critique, applicable to any project that supplies its own criteria.

**Skipped in report mode** — see § Output modes → Final self-critique in report mode.

## Escalation at outer cycle 3

If outer cycle 3 still produces edits **from the reviewer pipeline** (iterating, cross-check, or verify), STOP. Do not silently extend.

**Suggestion-tier final-pass edits at cap are exempt from this trigger.** When the layer is at outer-cycle cap and the final self-critique applies suggestion-tier edits per its at-cap branch, those edits are recorded but do NOT count as cycle-3 reviewer edits for escalation purposes. The clean-termination summary will note "applied at-cap final-pass suggestions" alongside the suggestion-tier edits applied. Non-suggestion final-pass issues at cap are escalated per the final-pass section's at-cap branch.

When reviewer-pipeline edits trigger escalation, surface to the user:

- **Total iterations** across all outer cycles (iterating-reviewer count / cross-check count; cross-check is zero in single-reviewer mode)
- **Findings churn** — content tuples repeated across cycles, with their kind trajectory (e.g. `fail → ambiguity → fail` suggests reviewer non-determinism rather than genuine convergence)
- **Per-cycle delta sizes** — did edits decrease cycle 1 → 2 → 3, or stay roughly constant?
- **Document growth metric** — line-count delta per outer cycle vs. findings count delta. If the artifact grew across cycles without findings count dropping correspondingly, that signals defensive bloat rather than rigor improvement; flag specifically.
- **Suspected causes** to investigate:
  1. **Prompt clarity** — review instructions may not adequately demand "include all feedback in one pass," letting reviewers drip-feed findings across iterations
  2. **Reviewer non-determinism** — same input producing different findings on retry
  3. **Genuinely complex artifact** requiring human judgment
  4. **Conflicting findings between iterating and cross-check** that the validity rubric isn't resolving cleanly (cross-AI mode only; not applicable in single-reviewer mode)

## Findings schema

`kind` classifies the finding for cross-iteration tracking:

- `pass` — positive observation, no action needed. Tracked because a prior `pass` flipping to `fail` in a later iteration signals a regression introduced by an earlier "fix."
- `fail` — defect / incorrect behavior / broken state
- `ambiguity` — unclear, multiple valid interpretations possible
- `inconsistency` — contradicts another part of the artifact or repo
- `gap` — missing piece (handling, doc, test, edge case)
- `risk` — not currently broken, but fragile / future-hazardous

`severity` is independent of `kind`: a `gap` can be `critical`, an `inconsistency` can be `info`, etc.

`title` is a label for human reading; cross-iteration comparison uses content tuples, not titles. Reviewers naturally drift title wording even when the underlying issue is the same.

`primitive` records which review primitive produced the finding. The host writes this when constructing per-call audit files; reviewers don't need to be aware of primitive semantics, since the prompt for each primitive call is built around that primitive.

`source` distinguishes reviewer findings from evidence findings. `reviewer` for findings produced by an AI reviewer's response; `evidence` for findings produced by a mechanical hook. Default severity baselines apply differently per source — see § Severity baseline.

Schema (write to `~/.claude/cross-ai-review-schema.json` once during install; verify it exists at the start of each task):

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": ["summary", "verdict", "findings"],
  "properties": {
    "summary": { "type": "string" },
    "verdict": {
      "type": "string",
      "enum": ["approve", "approve_with_suggestions", "request_changes", "block"]
    },
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["kind", "severity", "title", "file", "location", "detail", "suggestion", "primitive", "source"],
        "properties": {
          "kind": {
            "type": "string",
            "enum": ["pass", "fail", "ambiguity", "inconsistency", "gap", "risk"]
          },
          "severity": {
            "type": "string",
            "enum": ["info", "low", "medium", "high", "critical"]
          },
          "title": {
            "type": "string",
            "description": "Short stable identifier (<=80 chars) usable for cross-iteration dedupe"
          },
          "file": { "type": "string" },
          "location": {
            "type": ["string", "null"],
            "description": "Line range (e.g. '42-58'), section heading, or symbol name"
          },
          "detail": { "type": "string" },
          "suggestion": { "type": ["string", "null"] },
          "primitive": {
            "type": ["string", "null"],
            "enum": ["P1", "P2", "P3", "P4", "P5", "P6", "none", null]
          },
          "source": {
            "type": ["string", "null"],
            "enum": ["reviewer", "evidence", null]
          }
        }
      }
    }
  }
}
```

The `primitive` and `source` fields are **required by the schema** but **nullable** — reviewers MAY return `null` when they cannot determine the value, and the host normalizes nulls before audit/adjudication (filling `primitive` from the call's primitive context and `source` as `"reviewer"` for findings produced by an AI reviewer's response). Mechanical-hook findings are produced host-side and the host writes `"evidence"` into per-call audit files directly without going through reviewer schema validation.

This required-but-nullable shape is mandatory because OpenAI's Structured Outputs API (used by Codex's `--output-schema`) enforces that every key in `properties` must also appear in `required` when `additionalProperties: false`. A schema with keys in `properties` but absent from `required` is rejected at request time with HTTP 400 `invalid_json_schema`. The nullable union (`type: ["string","null"]`) plus `null` enum entry is the canonical "optional in practice but required by schema" pattern for that API.

## Audit artifact formats

Every cross-AI review run produces a set of markdown artifacts in `tmp/cross-ai-review/<RUN_ID>/`. The formats below are canonical; the slash command and any manual cross-AI review must produce artifacts in these exact shapes so they remain re-parseable in later iterations.

### Per-call markdown file

Each reviewer call (semantic-iterate, semantic-cross-check, semantic-verify) and each mechanical-phase invocation (mechanical-pre, mechanical-post) produces a single consolidated file. The filename grammar is **unified across all phases**:

```
<call-started>-<cli-or-host>-<phase-short>-<primitive>-<O>[-<N>].md
```

Where:
- `<call-started>` is the call's start timestamp in `YYYYMMDDTHHMMSS` UTC form (different per call, guaranteed unique because calls execute sequentially within a run)
- `<cli-or-host>` is the reviewer CLI's name (e.g., `codex`, `gemini`) for semantic phases, or the literal `host` for mechanical phases
- `<phase-short>` is one of: `iter` (semantic-iterate), `xchk` (semantic-cross-check), `vfy` (semantic-verify), `mpre` (mechanical-pre), `mpost` (mechanical-post)
- `<primitive>` is one of `P1` / `P2` / `P3` / `P4` / `P5` / `P6` (or `none` during transition)
- `<O>` is the outer-cycle index (1-3)
- `<N>` is the inner-iteration index (1-4); present for `iter`, `mpre`, `mpost`; absent for `xchk` and `vfy` (one-shot per outer cycle)

Examples:

- `20260501T220000-codex-iter-P1-1-2.md` — semantic iterate, Codex, P1, outer cycle 1, iteration 2
- `20260501T220500-gemini-xchk-P1-1.md` — semantic cross-check, Gemini, P1, outer cycle 1
- `20260501T220800-codex-vfy-P1-1.md` — semantic verify, Codex, P1, outer cycle 1
- `20260501T221000-host-mpre-P3-1-1.md` — mechanical pre, host, P3, outer cycle 1, iteration 1
- `20260501T221200-host-mpost-P5-1-1.md` — mechanical post, host, P5, outer cycle 1, iteration 1

**Note on model identifier**: the model slug is NOT in the filename — it's recorded in the per-call `.md` header (`**Model actual**:`). This avoids filename/header drift during fallback chains, where the model used can differ from the model requested. Audit consumers that need to filter by model read the header.

**Layer information lives in the file header**, not the filename. Re-parsing (disposition pass, addressed-context construction) filters by reading the `**Layer**:` header field. This keeps filenames short and user-readable; layer-qualification is internal detail.

**Restart epoch information also lives in headers**, not filenames. After an upstream-conflict restart, new per-call files use new timestamps and the header records `**Restart of**: <prior-call-timestamp>` linking back to the superseded call.

Per-cycle artifacts follow the same timestamp-prefix convention: `<written-at>-disposition-<O>.md`, `<written-at>-growth-<O>.md`, `<written-at>-final-self-critique.md`, `<written-at>-propagation.md`. Layer info in their headers as well.

For single-artifact reviews and peer mode, the layer header records `0` (treated as Layer 0 implicitly). Glob conventions for cross-run comparison: `tmp/cross-ai-review/*/*-codex-iter-P1-1-1.md` matches every N=1 outer-cycle-1 Codex iterate call on P1 across all runs.

The file is the canonical audit record for that call, containing call metadata, the reviewer's findings (or the mechanical hook's output), the host's per-finding decisions, the addressed-context that was sent (semantic only), the halt event (if any), and the raw stderr.

**Header convention by phase:**

- Semantic iterate: `# Review Call — <cli> (outer=<O> iteration=<N>) — Primitive=<P>` 
- Semantic cross-check: `# Review Call — <cli> (outer=<O> phase=cross-check) — Primitive=<P>`
- Semantic verify: `# Review Call — <cli> (outer=<O> phase=verify) — Primitive=<P>`
- Mechanical pre: `# Review Call — host (outer=<O> iteration=<N> phase=mechanical-pre) — Primitive=<P>`
- Mechanical post: `# Review Call — host (outer=<O> iteration=<N> phase=mechanical-post) — Primitive=<P>`

The example below shows a semantic-iterate call; substitute the appropriate header form for other phases.

```markdown
# Review Call — codex (outer=1 iteration=2) — Primitive=P1

**Run**: `<RUN_ID>`
**Started**: <ISO 8601 UTC timestamp> · **Duration**: <seconds>s
**Layer**: <int>
**Primitive**: <P1 | P2 | P3 | P4 | P5 | P6 | none>
**Phase**: <mechanical-pre | semantic-iterate | semantic-cross-check | semantic-verify | mechanical-post>
**Role**: <host | iterating | cross-check | verify>
**Output mode**: <apply | report>
**Mode**: <cross-AI | single-reviewer>
**Thinking level**: <one of the two canonical grammars below>
**CLI**: <cli | "host" for mechanical phases>
**Model requested**: <model_requested | "n/a" for mechanical phases>
**Model actual**: <model_actual | "unverified" | "n/a">
**Config source**: `<absolute config path>` (<global | project-override | shipped-defaults>)
**Fallback attempts**: <none | comma-separated list of "<model>:Class<X>">
**Restart epoch**: <R<N>> (omit this entire line when no restart has occurred; per § Restart semantics)
**Restart of**: <prior-call-timestamp> (omit this entire line when no restart has occurred; present only when **Restart epoch** is)
**Status**: <active | superseded-by-upstream-change> (omit this line when status is `active`; per § Restart semantics → preserve prior per-call files)
**Superseded at**: <ISO 8601 UTC timestamp> (present ONLY when **Status** is `superseded-by-upstream-change`; required in that case per § Restart semantics)

## Snapshot
- **Verdict**: `<verdict>`
- **Findings**: <total> total — <breakdown by kind, e.g., 3 fail, 2 ambiguity, 1 gap, 1 risk, 5 pass>
- **Host decisions**: <valid count> valid (<applied/reported-valid count> applied or reported-valid, <addressed count> already-addressed), <invalid count> invalid; <downgrade count> severity-downgraded
- **Halt event**: <none | brief class label, e.g., "Class C — vendor capacity">

## Reviewer summary

> <reviewer's own summary text, blockquoted (or "host mechanical pre-check" for mechanical phases)>

## Findings

### 1. <finding title> — `<kind> / <severity>`<_( downgraded from `<orig severity>`)_ if applicable>
- **File**: `<file>`
- **Location**: `<location>` (or "null" if the reviewer provided no location — keep the field present so re-parsing is consistent)
- **Source**: <reviewer | evidence>
- **Detail**: <reviewer's detail text or mechanical-hook output>
- **Suggestion**: <reviewer's suggestion text or "none">
- **Host decision**: <✓ valid | ✗ invalid> · <state>
- **Reasoning**: <host's reason, citing the rubric category>

(File and Location are kept as separate fields rather than collapsed into `file:location` because file paths can contain colons (Windows `C:\...`) and locations can be section headings that contain colons (`## Performance: targets`). Separate fields make re-parsing unambiguous.)

**Robustness note for re-parseability.** The `**Detail**` and `**Suggestion**` fields contain free-form text from the reviewer that could include markdown structure (headings, bullet lists, fenced code blocks) which, in pathological cases, could confuse the `### N.` heading walker the disposition pass and addressed-context construction rely on. When writing per-call markdown, the host is responsible for **inline-quoting or escaping** any reviewer text that contains `### ` at the start of a line (replace with `\### ` or wrap in a fenced block), so the only `### N.` headings in the file are the ones the host wrote for finding boundaries.

### 2. <next finding>
...

## <Addressed | Reported> context sent to reviewer

(The literal heading is `## Addressed context sent to reviewer` in apply-mode files and `## Reported context sent to reviewer` in report-mode files. Choose by the file's `**Output mode**:` header. Re-parsers MUST accept either heading and key off the Output mode header to disambiguate. Glob-based audit consumers searching across both modes can match `^## (Addressed|Reported) context sent to reviewer$` as a single regex. Producers MUST emit one of the two literal headings — never the placeholder `<Addressed | Reported>`.)

<"_N/A — first call in this run for this primitive in this layer; no prior per-call .md files exist._" | the full text of the context blob that was appended to the prompt (apply-mode `addressed-context` form per § Addressed-context construction OR report-mode `reported-context` form per § Reported-context construction) | "_N/A — mechanical phase; no reviewer prompt._" for mechanical phases>

## Fallback attempt logs

<"_None — first attempt succeeded._" when `Fallback attempts` is `none`; otherwise one labeled fenced block per failed attempt — `### <model> — Class <X>` followed by a fenced code block with that attempt's stderr capture, in chain order. See § Halt-signal taxonomy → Fallback audit grouping rule for the canonical contract.>

## Halt event

<"None." | full halt-classification block: reviewer/host, requested model, class, reason_code, fallback attempts, final action>

## Raw stderr

<fenced code block containing the full stderr capture from the final (successful, or — on full-chain halt — last-tried) attempt; include even when empty so the section is always present>
```

The `**Thinking level**:` field uses one of the two canonical grammars defined in § Thinking levels → Audit header format:

- **Semantic-phase calls** use: `<abstract> (native: <native-value-or-marker>)`
- **Mechanical-phase calls** use the literal: `N/A (mechanical)`

There is no combined or nested form. Re-parsers exact-match on the two shapes.

**Sorting note.** Findings are listed in the order the reviewer returned them (preserves any priority signal the reviewer used). If you want them sorted by severity or kind for review, sort downstream.

**Halt variant of the per-call template.** When a call halts before producing parseable reviewer output (Class A, B, C-chain-exhausted, D-chain-exhausted, E, F-after-retry, G, or M1-required), use this variant:
- `**Snapshot**` — `Verdict: halt`, `Findings: 0 (no parseable reviewer output)`, `Halt event: <class label>`
- `## Reviewer summary` — `_N/A — call halted before reviewer summary was produced._`
- `## Findings` — `_N/A — no parseable findings due to halt. See ## Halt event below for the halt classification and ## Raw stderr for the captured stderr._`
- `## Addressed context sent to reviewer` (apply mode) or `## Reported context sent to reviewer` (report mode) — populate normally with what was sent (this is independent of whether the reviewer responded; choose heading by Output mode per the standard template's mode-dependent heading rule)
- `## Fallback attempt logs` — populated normally if the halt resulted from chain-exhaustion and at least one earlier attempt produced stderr; `_None._` otherwise
- `## Halt event` — full halt-classification block
- `## Raw stderr` — full stderr capture from the final (last-tried) attempt

If a call halts AFTER producing parseable reviewer output (rare — would be a Class E silent-fallback halt on a successful exit), use the standard template and set the `## Halt event` section to the halt details; findings can still be listed but flagged with the decision state `withheld-class-e` (host does not apply findings from a Class E call because they're attributed to an unverified model). The `withheld-class-e` state is intentionally distinct from `applied` so the re-parsing contract's exact-match filter excludes withheld findings from addressed-context and disposition.

**M5 halt — special case (host-generated finding, halt event, standard template).** M5 (unexpected mutation by a mechanical hook) is host-detected and host-generated: the host's snapshot-and-diff has already produced the mutation evidence. The host writes that evidence into the per-call file's `## Findings` section as a single finding (`kind=fail`, `severity=critical`, `Source: evidence`) BEFORE halting, then writes the halt classification into `## Halt event`. The mechanical phase that detected the mutation is recorded in the per-call file's `**Phase**:` header (one of `mechanical-pre` or `mechanical-post`) — there is NO per-finding `Origin` field in the apply-mode per-call template; phase identity comes from the file-level header, not from a per-finding field. (`Origin` is a report-mode `findings-summary.md` field, not a per-call apply-mode field — see § Output format vs. § Per-call markdown file.) M5 therefore uses the **standard template**, not the halt-variant template, even though the cycle halts. This makes M5 deterministically auditable: the evidence finding records what mutated, the file's `**Phase**:` header records which mechanical phase detected it, and `## Halt event` records the cycle-stopping decision.

For M5 (and any other host-generated halt that uses the standard template), the host fills the standard template's reviewer-required fields with these literal values: `**Verdict**: halt`, `## Reviewer summary` body = `> _Host mechanical pre/post check (no reviewer involved); see Findings below for the host-generated evidence finding and ## Halt event for the cycle-stopping decision._`. The Verdict value `halt` is intentionally not one of the reviewer schema's enum values (`approve`, `approve_with_suggestions`, `request_changes`, `block`) because the per-call markdown's `**Verdict**:` header is **host-written and not schema-validated** — the schema applies to reviewer JSON output, not to the markdown audit envelope. The literal `halt` is the canonical Verdict marker for host-generated halt audits.

#### Actual-model extraction failure

When the actual-model extraction (per § Codex CLI → Actual-model extraction or § Gemini CLI → Actual-model extraction) cannot confirm the responding model from CLI output, the cycle **halts as Class E** (silent fallback policy applies regardless of whether the failure is mismatch-detected or extraction-impossible). There is no override — the no-silent-model-fallback guardrail is inviolable.

If a CLI version does not expose model identifiers in retrievable form, the cycle is unusable with that CLI version. Recovery: upgrade the CLI to a version that exposes model identifiers, or use a different reviewer CLI for the role.

**Install-time preflight**: the install procedure (`INSTALL.md`) verifies actual-model extractability for each installed CLI by running a test call and attempting extraction. If extraction fails, the install warns the user that the CLI is incompatible and recommends upgrading or substituting before proceeding.

### Re-parsing contract

When the host reads a prior call's `.md` in a later step:

- **First, filter by status**: check the `**Status**:` header line if present. If it equals `superseded-by-upstream-change`, the file is excluded from disposition pass and addressed-context construction (it was rendered obsolete by an upstream-conflict restart). The file remains in the run dir for audit but does NOT participate in re-parsing.
- **Filter by Output mode**: apply-mode disposition reads only apply-mode files (header `**Output mode**: apply`); report-mode aggregation reads only report-mode files. Mixing is not meaningful within a single run.
- **Filter by Layer**: include only per-call files whose `**Layer**:` header exactly matches the current layer being reviewed.
- **Filter by Primitive**: include only per-call files whose `**Primitive**:` header exactly matches the current primitive being reviewed.
- **Filter by Phase** (when scoping to a specific phase, e.g., addressed-context for the iterating reviewer's next call): include only per-call files whose `**Phase**:` header matches.
- **Validate Role consistency**: re-parsers should confirm the `**Role**:` field is consistent with the canonical Phase mapping (Phase=`semantic-iterate` ⇒ Role=`iterating`, etc.). Mismatches surface as malformed-audit findings (severity medium) and the file is excluded from disposition.
- **For disposition pass**: walk each `### N.` heading in the filtered files; extract the content tuple `(file, location, underlying-issue)` from the separate `**File**:` and `**Location**:` fields and the reviewer's `**Detail**:` text. **`underlying-issue` matching is semantic, not literal** — LLM reviewers vary wording, formatting, and emphasis even for the same issue, so literal string comparison of `**Detail**:` text systematically fails to identify repeats. The host judges whether two findings reference the same underlying defect/risk/ambiguity by reading both detail texts and the file/location context, not by string-equality.
- **For addressed-context construction (apply mode)**: walk each `### N.` heading in the filtered files. **Parse the decision-state segment exactly**: the `**Host decision**` line has shape `<✓ valid | ✗ invalid> · <state>` — split on the literal ` · ` separator and take the trimmed right-hand side as the state token. Emit an entry only when the state token equals one of `applied`, `already-addressed`, or `upstream-conflict-deferred`, OR when the validity segment equals `✗ invalid` (regardless of state — `✗ invalid · skipped` is the canonical invalid-rejection shape). **Do NOT use substring containment** on the decision line: `not-applied` and `withheld-class-e` would falsely match a `contains "applied"` filter. States `skipped` (valid but not actionable, e.g., kind=pass) and `withheld-class-e` (Class E halt) are intentionally excluded from addressed-context.
- **For addressed-context construction (report mode)**: emit entries when the state token equals `reported-valid` (regardless of validity, since `reported-invalid` represents a finding the host already filtered out). The preamble form is `reported-context` rather than `addressed-context` — see § Output modes.
- **For halt-classification audit**: read the "## Halt event" section.
- **For chronological ordering**: parse the `**Started**` ISO 8601 timestamp from each per-call `.md`'s header. Filename lexical sort is NOT a reliable chronological key (cross-check files have no `{N}`, verify files use `verify-{O}`, lexical CLI ordering can put verification before cross-check).

### Addressed-context construction (apply mode)

Before each reviewer call after the very first call **for the current primitive in the current layer**, build an addressed-context blob to append to the reviewer prompt.

**Scope**: walk per-call `.md` files filtered by exact-match on `**Output mode**: apply`, `**Layer**: <current>`, `**Primitive**: <current>`, and `**Phase**:` to scope to relevant phases (typically the iterating phase of the current and prior outer cycles, plus the cross-check and verify phases of prior outer cycles). Apply the status filter to exclude `superseded-by-upstream-change` files.

Walk the filtered per-call files **in chronological order** (sorted by `**Started**` timestamp). For each `### N.` block in those files, emit an entry per the **exact-match decision-state filter** defined in § Re-parsing contract above (split the decision line on ` · `, trim, exact-equal the state token against `applied | already-addressed | upstream-conflict-deferred`, OR include any finding whose validity segment is `✗ invalid`).

Format each entry as:
```
- title: <finding title from the ### heading>
  file: <value of the **File** field>
  location: <value of the **Location** field>
  status: applied | rejected-as-invalid | already-addressed | upstream-conflict-deferred
  summary: <one-line condensation of the **Reasoning** field>
```

Wrap the list with the following preamble in the prompt:

> The following findings have been raised in prior iterations and addressed in the current artifact (either by an applied fix, by validity-rejection with a logged reason, or recognized as already-addressed at the time). **Focus your output budget on novel issues** — issues whose content tuple `(file, location, underlying-issue)` does not match any entry below. You MAY still re-raise a specific finding if you disagree with how it was addressed, but the re-raise MUST explicitly state the disagreement in `detail` and propose a different fix in `suggestion`. Findings that simply repeat a prior finding without explicit disagreement will be rejected as invalid.

This is **context, not suppression**: the reviewer remains free to raise any concern. The disagreement-required gating bounds the gaming risk, since every re-raise is validity-judged and re-raises with weak disagreement are auto-classified invalid.

Persist the constructed blob within the per-call `.md` file itself (in the apply-mode `## Addressed context sent to reviewer` section, or the report-mode `## Reported context sent to reviewer` section per the per-call template's mode-dependent heading rule) so the audit trail records exactly what context was sent to the reviewer for that call.

### Reported-context construction (report mode)

In report mode, the addressed-context preamble is replaced with a `reported-context` form. Same scoping (filter by output_mode=report, layer, primitive, phase) and same chronological ordering, but the entry filter is different:

Emit entries only for `**Host decision**: ✓ valid · reported-valid` — these are the findings the host already adjudicated as valid in earlier passes of the current run. Invalid findings (`reported-invalid`) are NOT emitted (they're already filtered out by the host's adjudication; no need to remind the reviewer).

Preamble:

> The following findings were raised in earlier passes of this run. They have NOT been applied (this is a report-only run). The reviewer may re-raise any of them; repeats will be aggregated as additional evidence rather than rejected as already-addressed.

Repeats from multiple reviewers (or the same reviewer across passes) are aggregated in `findings-summary.md`, not deduplicated away.

### `halt-classification.md` format

Written when any reviewer call produces a halt event (Class A-G or M1-M5). One file per run; if multiple halts occur, append entries.

```markdown
# Halt event — <reviewer | host> Class <X>

**Reviewer/Host**: gemini | codex | host
**Phase**: <semantic-iterate | semantic-cross-check | semantic-verify | mechanical-pre | mechanical-post>
**Primitive**: <P1 | P2 | P3 | P4 | P5 | P6>
**Layer**: <int>
**Output mode**: <apply | report>
**Requested model**: <model | "n/a" for mechanical>
**Class**: <X> — <reason_code, e.g., MODEL_CAPACITY_EXHAUSTED or M5 unexpected mutation>
**Reset timing parsed**: <ISO timestamp | null>

## Fallback attempts (AI halts only)
| Attempt | Model | Result |
|---|---|---|
| 1 | gemini-3.1-pro-preview | 429 Class C |
| 2 | gemini-3-flash-preview | 429 Class C |

## Final action
halt — entire chain Class C

## Raw stderr from final attempt
<fenced code block with stderr capture>

## Per-call file for the failed call
<path to the per-call .md written for the failed call (which itself has the same halt info in its ## Halt event section)>
```

### `<written-at>-disposition-<O>.md` format

For outer cycles ≥ 2 only. Apply mode only (report mode has no disposition since it's single-pass).

```markdown
# Disposition — Layer <layer> Primitive <P> outer cycle <O>

**Layer**: <layer index>
**Primitive**: <P1 | P2 | P3 | P4 | P5 | P6>
**Phase scope**: across all phases of this primitive (mechanical-pre + semantic-iterate + semantic-cross-check + semantic-verify + mechanical-post)
**Restart epoch**: <R<N>; omit this header line when no restart has occurred>

Comparing the prior outer cycle's per-call `.md` files for this layer + primitive (filtered by Status + Layer + Primitive per § Re-parsing contract) to the current artifact state. Findings deduped by content tuple (file, location, underlying-issue).

| Prior finding (content tuple) | Disposition |
|---|---|
| `(handler.ts:42-58, missing nil-check)` | resolved |
| `(spec.md:12, terminology drift)` | still_open |
| ... | ... |

## Summary
- Resolved: <count>
- Still open: <count>
- Changed: <count>
- Not applicable: <count>

## Still-open items (require root-cause investigation rather than another fix attempt)
1. <title> — content tuple, last-iteration disposition, suggested investigation direction
2. ...
```

### `<written-at>-growth-<O>.md` format

For outer cycles ≥ 2 only. Apply mode only.

```markdown
# Growth metric — Layer <layer> Primitive <P> outer cycle <O>

**Layer**: <layer index>
**Primitive**: <P1 | P2 | P3 | P4 | P5 | P6>
**Restart epoch**: <R<N>; omit when no restart>

Comparing edited artifact line counts and findings counts vs. the start of the prior outer cycle, scoped to the docs covered by the current Layer + Primitive scope.

| Artifact | Lines (start of O-1) | Lines (start of O) | Delta |
|---|---|---|---|
| spec.md | 142 | 156 | +14 |
| ... | ... | ... | ... |

| Findings count | Cycle <O-1> end | Cycle <O> start | Delta |
|---|---|---|---|
| total | 12 | 5 | -7 |

## Interpretation
<one-paragraph note: cycle-1 expansion is expected; from cycle 2 onward, growth without proportionate net-new actionable findings is the bloat signal>
```

### `<written-at>-propagation.md` format

Written by the host after Layer N reaches clean termination and BEFORE the next layer's cross-AI review begins. Records the mechanical propagation the host performed across all downstream-layer docs that reference Layer N.

```markdown
# Propagation — Layer <N> → Layer <N+1>+ — <RUN_ID>

**Source layer (just stabilized)**: <doc(s) in Layer N>
**Target layers/docs considered**: <comma-separated list of all Layer N+1+ docs scanned>
**Categories of mechanical changes propagated**:
- Renamed sections / fields / terminology
- Updated verbatim quotes
- Synced example values
- Updated template references
- Section-name reference verification

## Files updated
| Target file | Categories applied | Brief diff summary |
|---|---|---|
| <path> | rename, quote, example | <one-line summary of what changed> |
| ... | ... | ... |

## Files considered with no changes needed
<list any downstream docs scanned but found to already be in sync, so the audit shows the scan was thorough>

## Files skipped (with reason)
<list any downstream docs deliberately not propagated to, with rationale>

## Restart/resume implications
<note any prior downstream layer state this propagation invalidates. For Layer 0 → Layer 1 propagation when Layer 1 has not been reviewed yet, this is "none". For propagation triggered by an upstream-conflict loop after Layer 1 was already reviewed, list which prior Layer 1 stability is now superseded.>
```

This artifact is required for every inter-layer transition; absence means propagation didn't happen and downstream review cannot start.

### `<written-at>-final-self-critique.md` format

Apply mode only. Written by the host per-layer at clean termination of that layer (before propagation to the next layer). No reviewer CLI involved.

```markdown
# Final self-critique — Layer <layer> — <RUN_ID>

**Layer**: <layer index>
**Restart epoch**: <R<N>; omit when no restart>
**Triggered by**: <stable agreement | escape hatch | cycle-3 with zero edits>
**Project final-pass criteria**: <path | "generic (no project criteria declared)">

## Findings
<same `### N.` block format as per-call markdown findings, with kind/severity/file/location/detail/suggestion, plus the host's decision and reasoning>

## Dismissal verification
<for every finding marked ✗ invalid during the cycle: re-verify the rejection reason against the actual artifact content. List any rejection that cannot be substantiated and the resulting flip to valid + applied.>

## Outcome
- <"No actionable issues — cycle truly settled.">
- <OR "Applied N issues; running one more outer cycle.">
- <OR (at cap) "Applied N suggestion-tier issues; escalated <count> non-suggestion issues to review-summary.md">
```

### `findings-summary.md` format (report mode)

Written at the top of the run directory in report mode, instead of `review-summary.md`. The user's main entry point for a report-mode run.

```markdown
# Findings — <RUN_ID>

**Date**: <ISO 8601 UTC>
**Mode**: <cross-AI | single-reviewer>
**Output mode**: report
**Artifact(s)**: <files reviewed, comma-separated>
**Termination**: <single-pass complete | halt-classified Class<X>>
**Configured primitives**: <list, e.g., P1, P2, P5>

## Per-primitive findings

### P1 — Authority adherence
<findings, ordered by severity then file/location>

### P2 — Coverage interpretation
<findings>

(one section per configured primitive)

## Aggregate counts
- Total findings: <n>
- By severity: <breakdown>
- By kind: <breakdown>
- By primitive: <breakdown>
- By origin: <iterating-reviewer / cross-check-reviewer / mechanical-pre / mechanical-post>
```

Each finding entry uses the report-mode entry shape defined in § Output modes → Output format.

Per-primitive filtered views (`findings-P1-authority.md`, `findings-P2-coverage.md`, etc.) are **generated** from `findings-summary.md` — they're filtered views, not separate sources of truth.

### `review-summary.md` format (apply mode)

Written at the top of the run directory at clean termination, escalation, or halt termination. Apply mode only. The user's main entry point when revisiting a run later.

```markdown
# Cross-AI Review — <RUN_ID>

**Date**: <ISO 8601 UTC>
**Artifact(s)**: <files reviewed, comma-separated>
**Outcome**: <stable agreement | escape hatch | cycle-3 zero edits | escalation | halt>
**Output mode**: apply

## Configuration
- Config source: <path> (<global | project-override | shipped-defaults>)
- Iterating reviewer: <cli> (<model_actual>; thinking_level=<level>)
- Cross-check reviewer: <cli> (<model_actual>; thinking_level=<level>) | none (single-reviewer mode)
- Mode: <cross-AI | single-reviewer>

## Dependency DAG
<rendered DAG showing layers, e.g.:
- Layer 0 (root): <doc>
- Layer 1 (derives from L0): <docs>
- Layer 2 (derives from L1): <docs>
  - Within-layer peer constraints: <peers>
or "Single artifact, no DAG" or "Peer mode (no hierarchy declared)">

## Per-layer summary
| Layer | Outer cycles run | Iterating-reviewer iters | Cross-check calls | Edits applied | Growth |
|---|---|---|---|---|---|
| 0 | <N> | <count> | <0 or 1 per cycle> | <count> | <delta lines> |
| 1 | <N> | ... | ... | ... | ... |
| ... | ... | ... | ... | ... | ... |

## Final findings disposition
- Resolved: <count>
- Remaining (suggestions only): <count>
- Rejected as invalid during cycle: <count> (with one-line reason for each, or a sample if many)
- Final self-critique added: <count> (with dismissal-verifications that flipped to valid)

## Notable findings
<2-3 most significant findings with content tuple and kind trajectory across cycles>

## Halt events
<None | brief list of halt events with reference to halt-classification.md>

## Unresolved (escalation)
<Only present when escalation triggered: list of findings the cycle could not resolve, with a recommendation to run a fresh /cross-ai-review invocation (which gets a new 3-cycle budget) or apply manually.>

## Audit trail
- Per-call review files: <total count>; unified grammar `<call-started>-<cli-or-host>-<phase-short>-<primitive>-<O>[-<N>].md`. Layer + Primitive + Phase in headers; model slug in `**Model actual**:` header.
- Per-cycle disposition + growth: `<written-at>-disposition-<O>.md`, `<written-at>-growth-<O>.md` (cycles ≥ 2; one set per layer per primitive)
- Final self-critique: `<written-at>-final-self-critique.md` (one per layer)
- Propagation diffs: `<written-at>-propagation.md` (one per inter-layer transition)
- Halt classification (if any): `halt-classification.md`
```

### Per-iteration progress reporting (chat output, not file)

After each reviewer call, the cycle prints one compact line so the user can follow what's happening. The first lines of every invocation are the resolved-config, DAG, and budget lines.

Example apply-mode run:

```
[config] /Users/<user>/.claude/cross-ai-review-config.json
         host=claude(orchestrator)
         iterating=codex(gpt-5.5, thinking=standard)
         cross-check=gemini(gemini-3.1-pro-preview, thinking=standard)
         scope=layered-dag  output_mode=apply
[DAG] Layer 0: docs/architecture.md  Layer 1: docs/design.md  Layer 2: src/, tests/ (peers)
[L=0 budget] primitives=[P1]; thinking=[P1=standard]; output_mode=apply; max_calls=18
[L=0 P1 mpre] (skipped — P1 has no mechanical pre-check)
[L=0 P1 O=1 N=2 codex] 12 findings (3 fail, 2 amb, 1 gap, 1 risk, 5 pass)
  novel=2 repeat=4 reg=0 invalid=1 downgraded=1 applied=4
[L=0 P1 O=1 N=3 codex] 6 findings (1 fail, 1 amb, 4 pass)
  novel=0 repeat=2 reg=0 invalid=0 applied=2 → set-stable, break
[L=0 P1 O=1 cross-check gemini] 8 findings (2 fail, 1 inconsistency, 5 pass)
  novel=3 repeat=0 invalid=1 applied=2
[L=0 P1 O=1 verify codex] 5 findings (5 pass) → verdict=approve
[L=0 P1 O=1 done] edits_applied=8 growth=+12 lines (cycle 1, expected) → continuing to L=0 P1 O=2
[L=0 P1 O=2 disposition] prior=12 → resolved=8 still_open=2 changed=1 n/a=1
[L=0 P1 O=2 N=1 codex] 6 findings (...)
[L=0 final self-critique] 2 findings (1 valid, 1 dismissal-verified) → applied=1
[L=0 final self-critique] 0 findings → layer settled
[L=0 done] all primitives + final-self-critique complete, layer stable
[propagation from L=0] propagated 4 categories of changes across 3 docs → <written-at>-propagation.md written
[L=1 budget] primitives=[P1]; thinking=[P1=standard]; output_mode=apply; max_calls=18
[L=1 P1 O=1 N=1 codex] 4 findings (...)
[L=1 final self-critique] 0 findings → layer settled
[L=1 done] → propagation L=1 → L=2+ → L=2 review starts
... (continues through all layers)
[review-summary] all layers settled → review-summary.md written
```

Counts:
- `novel` — findings whose content tuple `(file, location, underlying-issue)` does NOT match any prior finding
- `repeat` — findings whose content tuple matches a prior finding (regardless of title differences)
- `reg` — regressions: a content tuple that was `pass` previously is non-`pass` now
- `invalid` — findings rejected by validity judgment
- `downgraded` — findings auto-downgraded by the severity baseline

Set-based stability indicator: when `novel=0 AND reg=0` for two consecutive iterations within the iterating reviewer's inner loop, break out and proceed to the cross-check pass (or, in single-reviewer mode, proceed to outer-cycle continuation).

In single-reviewer mode, the `cross-check` and `verify` lines are absent.

In report mode, the layer-budget line shows `output_mode=report`, and per-primitive output is single-pass:

```
[L=0 P1 mpre] (skipped — P1 has no mechanical pre-check)
[L=0 P1 iterate codex] 12 findings (3 fail, 2 amb, 1 gap, 1 risk, 5 pass)
  source=reviewer  reported-valid=10 reported-invalid=2 downgraded=1
[L=0 P1 cross-check gemini] 8 findings (2 fail, 1 inconsistency, 5 pass)
  source=reviewer  reported-valid=6 reported-invalid=2
[L=0 P1 mpost] (skipped — P1 has no mechanical post-check)
[L=0 P1 done] single-pass complete → 16 findings recorded in findings-summary.md
[findings-summary] all primitives complete → findings-summary.md written
```

## Codex CLI

The Codex CLI is invoked through a wrapper helper installed at `~/.claude/cross-ai-review-helpers/codex-call.{sh,ps1}` (the `.sh` form is installed on macOS/Linux/WSL/Git-Bash; the `.ps1` form on Windows-native PowerShell — see INSTALL.md). The wrapper centralizes all the non-negotiable invocation details so the slash command's per-call step stays short, and so a single allowlist pattern in `~/.claude/settings.local.json` (granted at runtime by the user) can pre-approve all reviewer calls.

The wrapper handles:

- The two non-negotiable invocation flags (validated empirically; their absence breaks the cycle):
  - `< /dev/null` (or PowerShell equivalent): `codex exec` prints `Reading additional input from stdin...` and **blocks indefinitely** waiting for an EOF if stdin is not closed.
  - `--skip-git-repo-check`: `codex exec` refuses to run in non-git directories without this.
- Required flags: `-s read-only` (sandbox), `-m <model>` (from config), `--output-schema ~/.claude/cross-ai-review-schema.json`.
- Translation of `--thinking-level <fast|standard|deep>` to Codex's native `-c model_reasoning_effort=<low|medium|high>`. Mapping: fast→low, standard→medium, deep→high.
- Output capture to canonical temp paths.
- Halt-signal classification per § Halt-signal taxonomy.
- Class E actual-model extraction from stderr (parses `model=...` log line; halts on mismatch or extraction failure per § Actual-model extraction failure).
- Returns a structured JSON status object on stdout + exit code that maps to halt class (0=ok, 1-7=Class A-G, 8=invalid args). Exit code 8 signals a **host-programming error** (the host invoked the helper with missing or malformed arguments — a callsite bug, not a downstream API failure). The host normalizes exit 8 to **Class A-equivalent halt severity** for audit and cycle-stop purposes (configuration error; not transient; cycle cannot proceed without a host code fix). The audit records `Class: A (helper-arg validation failure; helper exit=8)` to disambiguate from API-side Class A halts.

The wrapper interface (same args on both `.sh` and `.ps1`, with platform-appropriate flag style) is documented at `helpers/README.md`.

**Recommended models** (these go in `providers.codex.models` in config; left-to-right preference):
- Default chain: `gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini`
- Other slugs available depending on the user's account (listed in `~/.codex/models_cache.json` if present): `gpt-5.3-codex`, `gpt-5.2`

**Codex behavior worth knowing:**

- Benign `ERROR codex_core::session: failed to record rollout items` lines may appear on stderr — bookkeeping noise, ignore.
- Codex actively runs read-only commands during review (`git show`, `rg`, `sed`, `ls`) to verify, not just hand-wave on the diff.
- Codex also has a non-`exec` review mode for prose verdicts: `codex review --commit <sha>`, `codex review --uncommitted`, `codex review --base <branch>`. **Not used in the cycle** — those modes don't return schema-enforced JSON. Mentioned only for awareness.

### Actual-model extraction

The Codex helper extracts the responding model identifier from stderr by parsing the `model=<slug>` log line that Codex emits during execution. The extracted slug is compared against the `-m <slug>` value passed in: a mismatch triggers Class E (silent fallback) and halts the cycle. When the stderr does not contain a parseable model identifier, the cycle also halts as Class E per § Actual-model extraction failure — there is no override.

## Gemini CLI

The Gemini CLI is invoked through a wrapper helper at `~/.claude/cross-ai-review-helpers/gemini-call.{sh,ps1}` (same install convention as the Codex helper).

The wrapper handles:

- Required flags: `-m <model>` (from config), `--approval-mode plan` (read-only sandbox), `--output-format json` (returns the CLI envelope).
- Translation of `--thinking-level <fast|standard|deep>` to Gemini's native thinking-budget value (per Gemini SDK; the helper README documents the current numeric mapping).
- **Envelope parsing**: Gemini's `--output-format json` returns `{response, stats, error}`, not the reviewer JSON directly. The reviewer's response lives inside `.response` (as a string, possibly wrapped in markdown code fences). The wrapper:
  1. Reads stdout as JSON; verifies envelope shape.
  2. If `.error` is non-null, classifies per the halt-signal taxonomy.
  3. Otherwise extracts `.response`, strips markdown code fences, parses as reviewer schema.
  4. Preserves `.stats` and `.error` in the per-call audit record.
- Optional `--stdin-file` for piping artifact content into Gemini (`cat <file> | gemini -p "..."`).
- Halt-signal classification (Class C `RetryableQuotaError`, Class D `ModelNotFoundError`, etc.).
- Class E actual-model extraction (parses model identifier from `.stats.models` if present; halts on mismatch or extraction failure per § Actual-model extraction failure).
- Returns the same JSON status object + exit code mapping as the Codex helper.

**Recommended models** (in `providers.gemini.models` in config; left-to-right preference):
- Default chain: `gemini-3.1-pro-preview`, `gemini-3-flash-preview`
- Other bundled slugs: `gemini-3-pro`, `gemini-2.5-pro`, `gemini-2.5-flash`

**Gemini behavior worth knowing:**

- Stderr may contain `Ripgrep is not available. Falling back to GrepTool.` — Class F-pattern noise that the wrapper recognizes as benign when output is otherwise clean.
- Gemini's documented Pro→Flash auto-degrade is the canonical Class E threat: if the request model is `gemini-3.1-pro-preview` but the response actually came from `gemini-3-flash-preview`, the wrapper detects the mismatch and halts (Class E) — review integrity depends on findings being attributable to the requested model.

### Actual-model extraction

The Gemini helper extracts the responding model identifier from the CLI envelope's `.stats.models` field (when present). The extracted slug is compared against the `-m <slug>` value passed in: a mismatch triggers Class E (silent fallback) and halts the cycle. When `.stats.models` is missing or empty in the envelope, the cycle also halts as Class E per § Actual-model extraction failure — there is no override.

## Composite recipes

Composite recipes are documented patterns showing how to compose primitives into common review goals. They are **non-normative documentation** — projects don't opt into them by reference; each project still declares its own primitives in its project extension.

| Goal | Composes | Recommended thinking-level overrides |
|---|---|---|
| **Business alignment** | P1 (against charter / PRD as Layer-0 authority) | P1=`deep` (charter-adherence judgment is high-stakes) |
| **Authority consistency** | P1 across the layered DAG | P1=`standard` for routine layers; `deep` for governance-binding layers |
| **Coverage** | P3 (linkage discovery) + P2 (coverage interpretation) | P2=`standard`; P3 is mechanical (no thinking) |
| **Traceability** | P3 across declared ID schemas | P3 is mechanical |
| **Structural integrity** | P4 with declared dependency / naming / layering rules | P4=`standard`; deeper for novel architecture decisions |
| **Executability** | P5 with build / typecheck / lint / test hooks | P5 is mechanical |
| **Correctness** | P5 (validation hooks) + the iterating reviewer cycle | P5 mechanical; iterating thinking varies by primitive |
| **Change impact** | P3 (linkage discovery of impacted artifacts) + P2 (coverage of impacts) + P6 (waiver checklist for deferrals) | P2=`standard`; P6=`standard`; P3 mechanical |
| **Determinism** | P5 with `deterministic: true` hooks (build twice and diff) | P5 mechanical |
| **Delivery readiness** | P6 (rollback / observability / sign-off) + P5 (smoke tests) | P6=`standard`; P5 mechanical |
| **Documentation completeness** | P2 (every public API has docs) + P5 (docs build clean) | P2=`standard`; P5 mechanical |
| **Security** | P5 (run scanner: `npm audit`, etc.) + P6 (security checklist: STRIDE review, threat model, secret scan) | P5 mechanical; P6=`standard` |

Recipes are documentation. They show users how to compose primitives. They do NOT impose primitive declarations or thinking-level overrides — projects still declare per-primitive content explicitly in their project extension.

## Minimal profile

The methodology has a minimal profile for projects without a project extension or for the smallest review use cases. The default profile is:

- **P1 only**, against the artifact's own merits (no upstream authority comparison; treats the artifact as Layer 0 implicitly).
- No P2/P3/P4/P5/P6 unless explicitly declared in a project extension.

Per-primitive declarations in project extension activate primitives:

- **P5 declarations** (validation hooks) → P5 runs on the named hooks
- **ID schema declaration** → P3 runs on the declared IDs
- **Coverage mapping declaration** → P2 runs on the declared mappings
- **Checklist declaration** → P6 runs on the named checklist
- **Structural rule declaration** → P4 runs on the declared rules

Audit trail records configured primitives at run start:

```
[L=0 primitives] configured=[P1, P5]; not-configured=[P2, P3, P4, P6]
```

`not-configured` is distinct from `failed` — it means "the project didn't declare this primitive's content," not "the primitive ran and failed."

This is structurally the same as today's "project extension is optional" stance, just made explicit per-primitive. A single-artifact, no-IDs, no-commands review sees a lightweight cycle (only P1 runs); a fully-instrumented project sees the complete pipeline. Both are valid, with no methodology failures introduced by the lighter profile.

---

End of v1 methodology.
