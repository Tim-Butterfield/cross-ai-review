<!-- BEGIN: cross-ai-review section (installed from cross-ai-review) -->

# Cross-AI review

When available, Codex CLI (OpenAI) and Gemini CLI (Google) can be
invoked locally — authed against the user's account with each
provider — to second-opinion-review generated artifacts before
declaring work done. The `/cross-ai-review` slash command
auto-detects which CLIs are installed and authed at runtime; if
both are present it runs in cross-AI mode, and if only one is
present it degrades cleanly to single-reviewer mode. Cross-AI
review uncovers gaps, ambiguities, and assumptions a single
reviewer might miss.

The methodology — halt-signal taxonomy, configuration semantics,
project-extension discovery, layered review pattern, iteration
cycle, validity rubric, severity baseline, final self-critique,
escalation, findings schema, audit artifact formats, per-CLI
recipes — lives in **`~/.claude/cross-ai-review-methodology.md`**.
The slash command loads it as Step 0 of every invocation, so it
is **not** auto-loaded into every Claude session. Do not delete
or move that file; the slash command depends on it. If you find
yourself wanting to recall a methodology rule mid-conversation
(e.g., during a manual cross-AI review without the slash command),
read the methodology file directly.

## When to offer / run a review

Offer a review when the artifact is significant enough that a second
opinion adds value:

- Architecture / design / ADR documents
- Non-trivial code changes with subtle correctness implications
- API surface changes, schema migrations, security-relevant code
- Anything the user flagged as "important to double-check"

Skip routine bug fixes, mechanical refactors, single-line edits, doc
typos. Cost-to-catch ratio doesn't justify it.

This is on-demand, not automatic. Hooks for automatic review require
explicit user approval.

## Read-only is non-negotiable

Reviewers MUST NOT modify any artifact under review. Always invoke
with read-only sandboxing:

- Codex: `-s read-only`
- Gemini: `--approval-mode plan`

NEVER use `--full-auto`, `--dangerously-bypass-approvals-and-sandbox`,
`-s workspace-write`, or `-s danger-full-access` for Codex; NEVER
use `-y` / `--yolo` / `--approval-mode auto_edit` /
`--approval-mode yolo` / `--approval-mode default` for Gemini.
**Reviewers report; Claude is the only thing that edits artifacts.**
In **apply mode** (the slash command's default), Claude applies the
valid actionable findings between review iterations. In **report mode**
(`--report` flag), Claude does NOT apply edits — findings are written
to a summary file and the user decides what to fix. In both modes,
reviewers remain read-only. Full forbidden-flag list, rationale,
output-mode semantics, and the rest of the cycle's rules are in the
methodology file.

<!-- END: cross-ai-review section (installed from cross-ai-review) -->
