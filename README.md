# cross-ai-review

A self-contained starter pack for the **Cross-AI Review** workflow: an autonomous review cycle where two CLI-based AI reviewers (OpenAI's Codex and Google's Gemini) evaluate an artifact, and Claude Code (the agent reading this) judges each finding's validity and applies the valid ones.

The cycle catches gaps, ambiguities, and assumptions a single reviewer would miss. It's been used to harden methodology documents, design specs, and code changes before declaring work done.

## What this pack contains

| File | Purpose |
|---|---|
| `README.md` | This file — user orientation |
| `INSTALL.md` | **Claude-readable install instructions** — open Claude Code, point it at this file |
| `cross-ai-review-claude-section.md` | **CLAUDE.md stub** (~2.9k chars) — installed/merged into `~/.claude/CLAUDE.md`. Always-loaded. Contains the when-to-offer trigger, a one-paragraph read-only + output-modes summary, and a pointer to the methodology file. |
| `cross-ai-review-methodology.md` | **Methodology authority** (~145k chars, v1) — installed to `~/.claude/cross-ai-review-methodology.md`. Loaded on demand by the slash command's Step 0, NOT auto-loaded into every Claude session. Defines the cycle's rules, formats, halt taxonomy, validity rubric, severity baseline, layered review pattern, six review primitives (P1-P6), pipeline structure (mechanical-pre → semantic → mechanical-post), output modes (apply / report), thinking levels, audit artifact formats, and per-CLI recipes. |
| `cross-ai-review.md` | **Execution authority** — the slash command (installed to `~/.claude/commands/`). Orchestrates the cycle following the methodology, which it loads as Step 0 of every invocation. |
| `cross-ai-review-config.example.json` | Example provider/model/role config (installed to `~/.claude/cross-ai-review-config.json`) |
| `project-extension-template.md` | Optional per-project rigor extension template (project-specific severity rules, evaluation criteria, layered DAG declaration, etc.) |
| `helpers/` | Wrapper scripts for reviewer CLIs — `.sh` (bash) and `.ps1` (PowerShell) versions of `codex-call` and `gemini-call`. INSTALL.md detects platform and copies the matching pair to `~/.claude/cross-ai-review-helpers/`. Reduces per-call permission-prompt friction. |
| `smoke-test/` | Tiny artifact + expected behavior to verify the install works end-to-end |
| `LICENSE` | MIT |

## Prerequisites

You need:

1. **Claude Code** — installed and able to run slash commands in your target workspace.
2. **At least one** AI provider CLI:
   - **Codex CLI** (OpenAI) — https://github.com/openai/codex. Verify with `codex --version` and `codex login status`.
   - **Gemini CLI** (Google) — https://github.com/google-gemini/gemini-cli. Verify with `gemini --version`.

Both providers is recommended (true cross-AI review needs two reviewers); one works in single-reviewer mode (degraded but still useful — see methodology § Configuration → Single-reviewer mode degradation for what's preserved and what's skipped).

Each provider's billing terms and model availability change over time and vary by region — check OpenAI's and Google's documentation. The cycle is billing-model-agnostic: it just needs your account to be able to invoke the configured models.

Optional: `jq` (for JSON inspection) and `ripgrep` / `rg`. Installable via Homebrew (macOS), apt/dnf (Linux), or scoop/winget/choco (Windows).

## Install

Open Claude Code in this directory (or any directory) and tell it:

> Read INSTALL.md from this starter pack and execute the install steps. Adapt commands to my platform.

Claude will verify prerequisites, back up existing config, install the slash command, the CLAUDE.md stub, and the methodology file, write a config file based on what you have installed and your role preference, optionally walk you through the project extension, and run a smoke test.

## How to invoke

In any project, after install:

```
/cross-ai-review <path-to-artifact>
```

The argument can be a single file, multiple files, a git commit SHA, or `uncommitted`. The first thing the slash command prints is a `[config]` line naming the resolved provider configuration and (for multi-artifact reviews) the dependency DAG it identified or constructed.

## Two output modes

The cycle runs in one of two modes per invocation:

| Mode | Invocation | What happens | Output |
|---|---|---|---|
| **apply** (default) | `/cross-ai-review <args>` | The host (Claude) iterates with the reviewers and **autonomously applies valid actionable findings** between iterations. Cycle continues to set-stability per primitive per layer (caps: 3 outer × 4 inner) plus cross-check + verify + per-layer final self-critique. | Updated artifact(s) + `review-summary.md` + per-call audit trail |
| **report** | `/cross-ai-review --report <args>` | Single-pass per primitive — no iteration, no edits applied. Findings adjudicated by the host (validity rubric + severity baseline + dedup) and written to file. The user decides what to fix manually. | Unchanged artifact(s) + `findings-summary.md` + per-call audit trail |

Apply is the default for "make my artifact better." Report is for "tell me what's wrong; I'll decide what to fix" — useful when you want a second opinion without authorizing autonomous edits, or when the artifact lives in a system you don't want Claude editing through this cycle (e.g., shared docs, frozen branches).

Both modes use the same reviewer infrastructure, the same halt taxonomy (silent model fallback always halts; quota errors halt; etc.), and the same per-call audit format. Differences are documented in methodology § Output modes.

## Reading the audit trail

Every `/cross-ai-review` invocation creates a **run directory** at `tmp/cross-ai-review/<RUN_ID>/` (relative to your project repo root) where every reviewer call's findings, every decision Claude made, every halt event, and every per-cycle metric is persisted. Open that folder months later and you can reconstruct what was reviewed, what was found, and what was applied — without needing transcripts.

### What's in the folder (apply mode)

```
tmp/cross-ai-review/20260430T223050-36134/
├── review-summary.md                                   ← start here — top-level summary
├── 20260430T223050-codex-iter-P1-1-1.md                ← per-call review records (unified grammar)
├── 20260430T223200-codex-iter-P1-1-2.md
├── 20260430T223315-gemini-xchk-P1-1.md
├── 20260430T223400-codex-vfy-P1-1.md
├── 20260430T223450-host-mpre-P5-1-1.md                 ← mechanical pre-check (host runs validation hook)
├── 20260430T223500-host-mpost-P5-1-1.md                ← mechanical post-check
├── 20260430T223510-disposition-2.md                    ← per-cycle disposition (only for cycle ≥ 2; per-primitive)
├── 20260430T223520-growth-2.md                         ← per-cycle growth metric (per-primitive)
├── 20260430T223530-codex-iter-P1-2-1.md
├── ... more per-call files ...
├── 20260430T224000-final-self-critique.md              ← post-layer self-check (one per layer; apply mode only)
├── 20260430T224100-propagation.md                      ← only present at inter-layer transitions
└── halt-classification.md                              ← only present if a halt occurred
```

In **report mode**, instead of `review-summary.md` the folder gets `findings-summary.md` (a consolidated findings file) plus optional per-primitive filtered views (`findings-P1-authority.md`, etc.). No `final-self-critique.md` (skipped in report mode).

Files are named with a leading timestamp so they sort chronologically — the order in the folder listing is the order calls happened.

### Folder name vs. file names

The folder name (the `<RUN_ID>`, e.g. `20260430T223050-36134`) and the per-file timestamps mean different things — both matter:

| Element | What the timestamp captures | Scope |
|---|---|---|
| Folder: `<RUN_ID>` = `<YYYYMMDDTHHMMSS>-<PID>` | Start of the `/cross-ai-review` **invocation** (when Setup ran), UTC | The whole run: every layer, every outer cycle, every reviewer call lands in this one folder. Set once and never changes. |
| Per-file timestamp prefix (e.g. `20260430T223200-codex-iter-P1-1-2.md`) | Start of **that single reviewer call**, UTC | One per call. Drifts forward as the run progresses, which is why `ls` order = call order. |

The trailing `-<PID>` segment of the folder name (e.g. `-36134`) is a collision-avoidance disambiguator for the rare case of two `/cross-ai-review` invocations starting the same second — it's the shell process ID, not a sequence number.

The folder is **not** scoped to a Claude Code session. Two `/cross-ai-review` invocations in the same Claude session produce two folders; one invocation that runs through a Claude restart still lives in its single folder.

### Filename segments

The unified per-call grammar is `<call-started>-<cli-or-host>-<phase-short>-<primitive>-<O>[-<N>].md`:

| Segment | Meaning |
|---|---|
| `<call-started>` (e.g. `20260430T223050`) | When this call started (YYYYMMDD T HHMMSS UTC) |
| `<cli-or-host>` (e.g. `codex`, `gemini`, `host`) | The CLI invoked for semantic phases, or the literal `host` for mechanical phases |
| `<phase-short>` | One of: `iter` (semantic-iterate), `xchk` (semantic-cross-check), `vfy` (semantic-verify), `mpre` (mechanical-pre), `mpost` (mechanical-post) |
| `<primitive>` | One of: `P1` / `P2` / `P3` / `P4` / `P5` / `P6` (or `none` during transition) |
| `<O>` | **Outer cycle** — re-runs (1, 2, 3) when edits applied and the primitive needs another full pass |
| `<N>` | **Inner iteration** — for `iter`, `mpre`, `mpost` only (not `xchk`, `vfy` which are one-shot) |

So `codex-iter-P1-1-2` means **"Codex's second inner iteration of the iterating phase, on primitive P1, in outer cycle 1."**

The model slug is NOT in the filename — it's in the per-call `.md` header (`**Model actual**:`). This avoids filename/header drift during fallback chains.

### The number patterns

| Pattern | Numbers | Notes |
|---|---|---|
| `<call-started>-<cli>-iter-<P>-<O>-<N>.md` | outer + inner | Iterating reviewer's role: re-runs until stable, both numbers present |
| `<call-started>-<cli>-xchk-<P>-<O>.md` | outer only | Cross-check reviewer: invoked once per outer cycle, no inner number |
| `<call-started>-<cli>-vfy-<P>-<O>.md` | outer only | Verify pass: invoked once per outer cycle (skipped if no cross-check configured; skipped in report mode) |
| `<call-started>-host-mpre-<P>-<O>-<N>.md` | outer + inner | Mechanical pre-check (deterministic, host-run) |
| `<call-started>-host-mpost-<P>-<O>-<N>.md` | outer + inner | Mechanical post-check |
| `<written-at>-disposition-<O>.md` / `<written-at>-growth-<O>.md` | outer only | Per-cycle metrics; written at start of cycle ≥ 2 (per primitive). Layer + primitive recorded in file headers, not filenames. |
| `<written-at>-final-self-critique.md` | — | One per layer at clean termination (apply mode only; skipped in report mode). |
| `<written-at>-propagation.md` | — | One per inter-layer transition; records the host's mechanical updates to downstream-layer docs after the upstream layer settles. |

Rule of thumb: **two numbers** = an iterating-style call; **one number** = a one-shot per-outer-cycle call (or a per-cycle metric file).

### Walking through a real sequence

A typical successful single-layer review with one primitive (P1) where outer cycle 1 took 2 Codex iterations to stabilize, then ran Gemini cross-check and verify, then needed outer cycle 2:

```
20260430T223050-codex-iter-P1-1-1.md         outer cycle 1, iterating iter 1 — 12 findings, applied 11, 1 invalid
20260430T223200-codex-iter-P1-1-2.md         outer cycle 1, iterating iter 2 — set-stable (no novel findings), break
20260430T223315-gemini-xchk-P1-1.md          outer cycle 1, cross-check — 3 cross-vendor issues, applied
20260430T223400-codex-vfy-P1-1.md            outer cycle 1, verify — 1 regression Gemini introduced, applied
20260430T223510-disposition-2.md             start of outer cycle 2 (P1) — classifies cycle 1 findings vs current state
20260430T223520-growth-2.md                  start of outer cycle 2 (P1) — line/finding count delta vs cycle 1
20260430T223530-codex-iter-P1-2-1.md         outer cycle 2, iterating iter 1
20260430T223700-codex-iter-P1-2-2.md         outer cycle 2, iterating iter 2 — set-stable, break
20260430T223800-gemini-xchk-P1-2.md          outer cycle 2, cross-check
20260430T223900-codex-vfy-P1-2.md            outer cycle 2, verify — verdict=approve
20260430T224000-final-self-critique.md       per-layer self-check
review-summary.md                            top-level summary you'd open first
```

If the project also declares P5 (validation hooks), each cycle would additionally include `host-mpre-P5-...` and `host-mpost-P5-...` files for the deterministic pre and post checks.

### What's inside each file

Per-call files contain: a header block with call metadata (timestamp, CLI/host, layer + primitive + phase + role + output mode + thinking level; plus optional restart-epoch + status headers when an upstream-conflict restart occurred), a snapshot (verdict, finding counts), the reviewer's summary, every finding with the host's per-finding decision and reasoning, the addressed-context that was sent to the reviewer, the halt event if any, and the raw stderr.

The decision-state taxonomy depends on output mode:

- **Apply mode**: `applied` (host edited the artifact), `skipped` (valid but not actionable, e.g. kind=pass), `already-addressed` (issue was resolved by a prior finding's edit, OR a P6 waiver pre-populates the addressed-context), `upstream-conflict-deferred` (valid but contradicts an upstream-layer authority — defers per the restart flow), `withheld-class-e` (Class E silent-fallback halt — finding kept for audit but not applied), or `invalid` + reason.
- **Report mode**: `reported-valid` (host adjudication says valid; user is expected to act on it) or `reported-invalid` (host adjudication says invalid; reasoning logged).

Per-cycle files (`disposition-O.md`, `growth-O.md`) contain a small markdown table comparing this cycle to the prior one. Per-primitive: layer + primitive in headers.

`review-summary.md` is the user's main entry point — it cross-references everything else, summarizes per-cycle counts, and lists notable findings.

### For the full spec

The canonical spec for these formats — including the re-parsing rules Claude uses to walk prior files in subsequent iterations — is in `~/.claude/cross-ai-review-methodology.md` § Audit artifact formats. The README description above is a user-friendly summary; the methodology file is authoritative.

## Example runs

Two abbreviated runs to set expectations for what you see when you invoke the cycle. Both come from real validation traces; only formatting and length are tightened for the README.

### Example A — apply mode (default)

You invoke `/cross-ai-review docs/architecture.md` against a single architecture document. Chat output:

```
[config] /Users/<user>/.claude/cross-ai-review-config.json (global)
         host=claude(orchestrator)
         iterating=codex(gpt-5.5, thinking=deep)
         cross-check=gemini(gemini-3.1-pro-preview, thinking=deep)
         scope=single-artifact  output_mode=apply  mode=cross-AI
[L=0 P1 mpre] (skipped — P1 has no mechanical pre-check)
[L=0 P1 O=1 N=1 codex] 9 findings (1 fail, 2 inconsistency, 2 gap, 1 ambiguity, 3 pass)
  novel=9 applied=6 verdict=request_changes
[L=0 P1 O=1 N=2 codex] 6 findings (3 inconsistency, 1 ambiguity, 2 pass)
  novel=4 applied=4 verdict=request_changes
[L=0 P1 O=1 N=3 codex] 4 findings (1 gap, 1 inconsistency, 2 pass)
  novel=2 applied=2 verdict=request_changes
[L=0 P1 O=1 N=4 codex] 3 findings (1 gap, 2 pass) → cap reached
  novel=1 applied=1 verdict=request_changes
[L=0 P1 O=1 cross-check gemini] 6 findings (1 fail, 1 incon, 1 amb, 2 gap, 1 risk)
  novel=6 applied=6 verdict=approve_with_suggestions
[L=0 P1 O=1 verify codex] 3 findings (2 inconsistency, 1 gap) ← regressions from cross-check
  novel=3 reg=3 applied=3 verdict=request_changes
[L=0 P1 mpost] (skipped — P1 has no mechanical post-check)
[L=0 P1 O=1 done] edits_applied=22 growth=+54 lines (cycle 1, expected) → continuing to L=0 P1 O=2
[L=0 P1 O=2 disposition] prior=12 → resolved=18 still_open=0 changed=2 n/a=2
... (additional outer cycles + per-layer final self-critique) ...
[review-summary] all layers settled → tmp/cross-ai-review/<RUN_ID>/review-summary.md written
```

What to read:

- **`[L=0 P1 O=<O> N=<N>]`** is the location: layer 0, primitive P1, outer cycle O, inner iteration N. Counts on the second line: `novel` = new content tuples this iteration; `applied` = host-edited findings; `reg` = regressions (a prior-iteration `pass` flipped to non-pass).
- The trend `9 → 6 → 4 → 3` (then `0 actionable` at N=4) is **set-stability convergence**: the iterating reviewer found 9 issues on first pass; after host applied 6 of them, iter-2 found 4 net-new issues introduced or surfaced by those fixes; iter-3 found 2; iter-4 found 0 actionable + 3 pass observations confirming the prior fixes. The cap of 4 was reached without a clean approve, so the cycle force-progressed to cross-check.
- **Cross-check (Gemini)** found 6 distinct issues Codex missed — the cross-vendor second opinion's main value. The host applied all 6 as valid.
- **Verify (Codex)** caught 3 regressions the cross-check fixes introduced — exactly the case the verify phase exists to catch.
- The cycle then runs outer cycle 2 (with a disposition pass first, comparing prior findings to the current artifact state), continuing until set-stability or the 3-outer-cycle cap.
- The final line points to `review-summary.md` — your main entry point for what happened.

After this run, your `docs/architecture.md` has been improved by the applied edits, and `tmp/cross-ai-review/<RUN_ID>/` contains the full audit trail (per-call `.md`s + per-cycle artifacts + summary).

### Example B — report mode (no edits)

You invoke `/cross-ai-review --report docs/architecture.md`. Chat output:

```
[config] /Users/<user>/.claude/cross-ai-review-config.json (global)
         host=claude(orchestrator)
         iterating=codex(gpt-5.5, thinking=deep)
         cross-check=gemini(gemini-3.1-pro-preview, thinking=deep)
         scope=single-artifact  output_mode=report  mode=cross-AI
[L=0 P1 mpre] (skipped — P1 has no mechanical pre-check)
[L=0 P1 iterate codex] 12 findings (3 fail, 2 amb, 1 gap, 1 risk, 5 pass)
  source=reviewer  reported-valid=10 reported-invalid=2 downgraded=1
[L=0 P1 cross-check gemini] 8 findings (2 fail, 1 inconsistency, 5 pass)
  source=reviewer  reported-valid=6 reported-invalid=2
[L=0 P1 mpost] (skipped — P1 has no mechanical post-check)
[L=0 P1 done] single-pass complete → 16 findings recorded in findings-summary.md
[findings-summary] all primitives complete → tmp/cross-ai-review/<RUN_ID>/findings-summary.md written
```

The artifact is **unchanged**. The cycle ran each phase **once** (no inner-iteration loop, no verify pass, no per-layer final self-critique — all skipped in report mode per methodology § Output modes). The host's adjudication still runs (validity rubric + severity baseline), so findings come back already filtered.

`findings-summary.md` excerpt — this is what the user opens to decide what to fix:

```markdown
# Findings — 20260430T223050-36134

**Date**: 2026-04-30T22:30:50Z
**Mode**: cross-AI
**Output mode**: report
**Artifact(s)**: docs/architecture.md
**Termination**: single-pass complete
**Configured primitives**: P1

## Per-primitive findings

### P1 — Authority adherence

#### Authority document references stale ADR — fail / high
- **File**: `docs/architecture.md`
- **Location**: `§ Decision Log`
- **Origin**: iterating-reviewer
- **Source**: reviewer
- **Origin detail**: The "Decision Log" section references `ADR-007` for the
  caching strategy, but no `ADR-007` exists in the docs/adr/ directory; the
  caching ADR is `ADR-009`.
- **Origin suggestion**: Update reference to `ADR-009` and verify any other
  ADR references against docs/adr/.
- **Host adjudication**: ✓ valid · reported-valid
- **Host reasoning**: factually verifiable (the reviewer named the missing
  file); actionable; matches existing ADR file naming.
- **Host severity adjustment**: none

#### Coupling between Auth and Billing modules underspecified — gap / medium
... (more findings) ...

## Aggregate counts
- Total findings: 16
- By severity: 2 critical, 5 high, 6 medium, 3 low
- By kind: 5 fail, 4 inconsistency, 4 gap, 2 ambiguity, 1 risk
- By primitive: 16 (P1)
- By origin: 10 iterating-reviewer, 6 cross-check-reviewer
```

Same reviewer infrastructure, same audit-trail format — just no edits. Pick this mode when you want the second opinion without authorizing autonomous edits, or when the artifact is in a system you don't want Claude editing through this cycle.

## Multi-artifact reviews and the dependency DAG

When the review covers more than one artifact, the cycle works best when the artifacts have a declared review scope. Most projects with a hierarchy have a single "highest authority" document (architecture, spec, charter) that everything else derives from, with one or more layers of derived documents below — those use **layered-DAG** mode. Projects whose artifacts are genuinely peers (no inherent hierarchy) use **peer-mode**. Both are first-class scope forms in v1.

Three ways the cycle resolves the scope (in precedence order):

1. **Declared in your project's extension** — the most reliable. Add an `### Authority documents` block to your project's `## Cross-AI Review Extension` section. The block supports two canonical forms:
   - **Layered-DAG form** — declare `Layer 0 (root authority): <doc>` plus subsequent `Layer N (derives from Layer M): <docs>` lines. The optional `Scope: layered-dag` discriminator makes the choice explicit.
   - **Peer-mode form** — declare `Scope: peer-mode` plus `Layer 0 peers: <docs>` plus optional `Peer compatibility constraints: <P4 rules>`.

   Both forms are documented in `project-extension-template.md`. The cycle uses whichever the user declared, no questions asked.

2. **Heuristic detection** — when no extension exists, the cycle infers a candidate scope from naming conventions, cross-references, and directory structure, then proceeds without asking if it's confident (printing the assumed scope in the `[config]` block so you can correct).

3. **Interactive wizard** — when heuristics aren't confident, the cycle asks you a few focused questions to construct the scope (including the "is one of these the highest authority?" question that disambiguates layered-DAG from peer-mode), then offers it back as a project-extension snippet you can paste in (so future reviews don't re-ask). Both layered-DAG and peer-mode wizard outputs are offerable.

**Layered mode** iterates the root authority to stability first. Between layers, Claude runs a **propagation step** — mechanical updates to derived docs to reflect the now-stable upstream (renames, reference updates, literal-value example syncs; context-dependent examples are flagged for substantive review rather than mechanically synced). Each derived layer's cross-AI review then focuses on substantive adherence rather than catching copy-paste drift. The cycle continues layer-by-layer.

**Peer mode** runs P1 as **per-artifact internal consistency** for each peer (no cross-peer P1 comparison). Peer-to-peer compatibility is handled by **P4 with peer-compatibility rules** when the project declares them — keeping the convergence cost localized. (P1 in peer mode is per-artifact, not N-1 dimensional; only P4 peer-compatibility checks are N-1 dimensional, and only when explicit constraints are declared.)

See `cross-ai-review-methodology.md` § Layered review pattern (including § DAG identification → Peer mode and § P1 → No-upstream case) for the full methodology, including the propagation step contract and per-layer iteration sequencing.

## Where to learn more

- **`cross-ai-review-methodology.md`** is the canonical reference for everything: cycle methodology, halt taxonomy, validity rubric, severity baseline, configuration, layered review pattern, audit artifact formats, per-CLI recipes. After install it's at `~/.claude/cross-ai-review-methodology.md` and is loaded on demand by the slash command's Step 0 (not auto-loaded into every Claude session — that keeps `CLAUDE.md` lean).
- **`cross-ai-review-claude-section.md`** is the slim stub that gets merged into `~/.claude/CLAUDE.md`. It carries only the when-to-offer trigger, the read-only summary, and a pointer to the methodology — just enough to make Claude proactively suggest a review without auto-loading the full methodology.
- **`cross-ai-review.md`** is the slash command — the procedural script that orchestrates the cycle. Reads short; loads the methodology file in Step 0 and refers to its sections by name throughout.
- **`project-extension-template.md`** is what you'd add to a specific project's `CLAUDE.md` to declare project-specific severity rules, evaluation criteria, authority document DAG, and (optionally) override the global provider config.
- **`smoke-test/`** is the install-verification fixture.

## Questions or issues

If something doesn't work, open an issue on the GitHub repo (or a discussion). The pack is shared as-is — bug reports and use-case feedback are welcome.
