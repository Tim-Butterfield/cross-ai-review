<!-- BEGIN: cross-ai-review section (installed from cross-ai-review) -->

# Cross-AI review

This pack installs two complementary slash commands sharing the same provider config and reviewer helpers:

- **`/clarify`** — pre-settlement. Surfaces ambiguities, missing decisions, hidden assumptions, and unresolved tradeoffs as a **decision packet** for the user. No autonomous decisions; no artifact edits.
- **`/cross-ai-review`** — post-settlement. Verifies the artifact against declared authority (apply mode autonomously edits; `--report` mode just records findings). Halts on quota or silent model fallback.

Use `/clarify` for **intent formation**; use `/cross-ai-review` for **governed verification**.

Full rules live in two files loaded on demand, NOT auto-loaded into every Claude session: `~/.claude/cross-ai-review-methodology.md` (the `/cross-ai-review` cycle's halt taxonomy, config, layered DAG, audit formats, etc.) and `~/.claude/commands/clarify.md` (the `/clarify` workflow inline). Do not delete or move either; the slash commands depend on them.

## When to offer `/clarify`

Offer when the user is at the **intent-formation stage**:

- Working from new or under-specified requirements (mobile app spec with no tech stack, design doc with vague performance targets, deployment plan with no rollback story)
- About to make a major architectural choice without acknowledging tradeoffs
- Asks "what should we build" / "what should this look like" / "what's the right way to do X"
- Pre-implementation, when the user wants to know what they're committing to

Skip if the artifact's intent is firm and the user wants to verify correctness — that's `/cross-ai-review`.

## When to offer `/cross-ai-review`

Offer when the artifact is significant enough that a second opinion adds value:

- Architecture / design / ADR documents
- Non-trivial code changes with subtle correctness implications
- API surface changes, schema migrations, security-relevant code
- Anything the user flagged as "important to double-check"

Skip for routine bug fixes, mechanical refactors, single-line edits, doc typos.

Both commands are on-demand, not automatic.

## Read-only is non-negotiable

Reviewers (when consulted) MUST NOT modify any artifact under review. Invoke with read-only sandboxing — Codex: `-s read-only`; Gemini: `--approval-mode plan`. NEVER use `--full-auto` / `--dangerously-bypass-approvals-and-sandbox` / `-s workspace-write` / `-s danger-full-access` for Codex; NEVER use `-y` / `--yolo` / `--approval-mode auto_edit` / `--approval-mode yolo` / `--approval-mode default` for Gemini.

**Reviewers report; Claude is the only thing that edits artifacts.** Edit semantics differ per command: `/clarify` never edits; `/cross-ai-review` edits in apply mode (default) and records-without-editing in report mode. Per-command full rules (forbidden-flag rationale, output-mode semantics, cycle details) are in the loaded-on-demand files named above.

<!-- END: cross-ai-review section (installed from cross-ai-review) -->
