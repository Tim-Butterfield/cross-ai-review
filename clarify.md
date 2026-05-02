---
description: Surface ambiguities, missing decisions, hidden assumptions, and unresolved tradeoffs in an artifact (prompt, requirements, design, plan, etc.) BEFORE review or implementation. Output is a decision packet for the user — not edits, not correctness verification. Companion to /cross-ai-review (which verifies a SETTLED artifact); /clarify helps form the intent the artifact is verified against. Claude is the host. Each invocation has one analyst (--analyst claude default; --analyst codex or --analyst gemini for an alternate perspective).
---

# /clarify $ARGUMENTS

Help the user surface decisions that need to be made BEFORE the artifact identified by `$ARGUMENTS` is reviewed for correctness or used for implementation. The argument may include:

- One or more file paths
- A free-form description of the artifact (when not yet written down)
- An optional `--analyst <name>` flag (`claude` | `codex` | `gemini`) selecting which model surfaces the ambiguities. Default is `claude` (the host). The flag substitutes the analyst — it does NOT add a second analyst on top of claude. See § Analyst selection.

`/clarify` does NOT accept git commit SHAs or `uncommitted` — those argument forms are for `/cross-ai-review` (which has the cycle infrastructure to resolve a commit into reviewable artifact content). `/clarify` is for pre-settlement artifacts whose intent is still being formed; commit-based arguments imply the artifact is in version control, which usually means it has past the intent-formation stage.

If the scope is unclear, ask one focused clarifying question before starting. Do not guess.

`/clarify` is **the companion to `/cross-ai-review`** — and the distinction matters:

- **`/clarify`** runs BEFORE the artifact is settled. It surfaces ambiguities, missing decisions, hidden assumptions, and unresolved tradeoffs so the user can decide them deliberately. **The user remains the decision authority — Claude does NOT pick.**
- **`/cross-ai-review`** runs AFTER the artifact is settled. It verifies the artifact against its declared upstream authority (or against itself, in the no-upstream case) and applies fixes for adherence drift.

If you find yourself wanting to "review" an artifact that hasn't yet decided what it's supposed to do, you want `/clarify`, not `/cross-ai-review`. If you find yourself wanting to "clarify" an artifact that already has firm intent and you want to verify the implementation matches, you want `/cross-ai-review`.

## Hard rules

### 1. No autonomous decisions

`/clarify` MUST NOT pick options for the user. The decision packet's `Recommendation` field is **advisory only** — it captures the host's judgment of which option is best given the evidence in the artifact and the surrounding context, but it is NEVER applied without explicit user direction. Surfacing > deciding.

This rule exists because `/clarify` runs at the moment of intent formation. If the host silently picks a default (e.g., "I'll assume cross-platform React Native" for a mobile app spec that doesn't specify a stack), the user loses the chance to make the decision deliberately. Worse, downstream work (review, implementation, deployment) inherits that silent choice and propagates it as if it were intentional.

The user's decision is what makes an ambiguity into intent. Until the user decides, the ambiguity remains an ambiguity.

### 2. Read-only by default

`/clarify` MUST NOT edit the artifact. Each ambiguity's decision packet includes a `Suggested artifact update` field describing what the host would change in the artifact AFTER the user decides — but the host does NOT apply that update during `/clarify`. The user applies it themselves (manually or by asking Claude to apply specific decisions in a follow-up turn).

If the user asks `/clarify` to apply suggested updates, the host SHOULD redirect them: "I can apply your decisions if you tell me which option you picked for each ambiguity. The packet at `<path>` lists them."

### 3. Single analyst per run; analyst is user-selected, never auto-substituted

Each `/clarify` invocation has exactly one analyst — the entity that surfaces the candidate ambiguities. The default analyst is **claude (host)**, which works without external dependencies. The `--analyst codex` and `--analyst gemini` flags substitute the named CLI as the analyst (Claude continues to orchestrate the run, format the packet, and apply user decisions on follow-up). See § Analyst selection for the workflow rationale and per-analyst trade-offs.

The flag is the user's choice — `/clarify` MUST NOT auto-substitute the analyst (e.g., "claude is unavailable, fall back to codex"). Substitution must be explicit. Reasons:

- The packet's character (which questions get surfaced, what options get listed) varies by analyst. Silently swapping changes what the user sees without their consent.
- The user's mental model — "this packet was produced by analyst X" — depends on Source-of-truth correctness. An auto-substitute makes the `**Analyst**:` header field unreliable.

If the user selects `--analyst codex` or `--analyst gemini` but the chosen CLI is not installed/authed (per `~/.claude/cross-ai-review-config.json` + runtime detection), `/clarify` HALTS with a diagnostic chat reply naming the missing analyst. It does NOT silently fall back to claude.

If the chosen non-claude analyst halts mid-run (any halt class A–G), `/clarify` HALTS the current run, writes the halt artifact to the run dir, and reports the halt in the chat reply. The user can manually re-invoke with `--analyst <other>` if they want a different perspective. `/clarify` does NOT silently retry with a different analyst.

This is a deliberate contrast with `/cross-ai-review`'s multi-reviewer cycle. `/cross-ai-review` cross-checks findings between two reviewers because finding-validation needs the second perspective. `/clarify` produces decision support, not validated findings — and decision support is by-perspective. Each analyst sees the artifact differently; running them in sequence (claude, then codex, then gemini) gives the user multiple distinct decision packets they can compare and combine. Running them concurrently and merging would muddle attribution and dilute each perspective's distinctness.

### 4. Decision packet, not review report

The output of `/clarify` is a **decision packet**, not a review report. The packet's structure (defined below) is fundamentally different from `/cross-ai-review`'s findings:

- A finding from `/cross-ai-review` says: "Section 4.2 contradicts upstream authority — the host applied a fix."
- An entry in a `/clarify` packet says: "Section 4.2 says X but does not specify whether to use approach A or approach B. Here are the tradeoffs and a recommendation. **You decide.**"

Reviewer-style verdicts (`approve`, `request_changes`, `block`) do NOT apply to `/clarify`. There is no "verdict" — the artifact is neither correct nor incorrect at the `/clarify` stage; it is incompletely specified. The packet's purpose is to make that incompleteness explicit and tractable.

## Workflow

### Setup (once per invocation)

1. **Locate the artifact**. If `$ARGUMENTS` is a file path or paths, read the file(s). If it's a free-form description, the description IS the artifact (treat it as inline content). If unclear, ask the user one focused question.

2. **Generate a run identifier and run directory**:
   ```sh
   RUN_ID="$(date -u +%Y%m%dT%H%M%S)-$$"
   REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
   RUN_DIR="$REPO_ROOT/tmp/clarify/$RUN_ID"
   mkdir -p "$RUN_DIR"
   PACKET_PATH="$RUN_DIR/clarify-packet.md"
   ```
   The path `tmp/clarify/<RUN_ID>/` (relative to repo root) is canonical and **parallel to `/cross-ai-review`'s `tmp/cross-ai-review/<RUN_ID>/`** — one folder per `/clarify` invocation, same shape as the verification cycle. Both are covered by the standard `tmp/` line in `.gitignore`.

   The folder gives the user a workspace: the packet lives inside it, and when the analyst is codex or gemini, the analyst's raw call audit lands alongside the packet (see § Identify ambiguities — analyst invocation). When the user is ready to apply decisions, they can either tell Claude inline ("apply my decisions: tech stack = React Native, auth = OAuth") OR drop a `user-decisions.md` (or any name) into the same folder and ask Claude to read it. The folder also makes cleanup atomic: `rm -rf tmp/clarify/<RUN_ID>/` discards everything from a single run.

3. **Resolve the analyst** for this run:
   - Parse `--analyst <name>` from `$ARGUMENTS`. Accepted values: `claude` (default), `codex`, `gemini`. Anything else is an invalid argument; halt with a diagnostic chat reply naming the bad value and the accepted set.
   - If `--analyst claude` (or no flag): the analyst is Claude (the host). No external CLI needed; proceed.
   - If `--analyst codex` or `--analyst gemini`: verify `~/.claude/cross-ai-review-config.json` exists, parses as valid JSON, and lists the named provider in its `providers` block. Verify the corresponding CLI is installed via `command -v codex` / `command -v gemini`. If either check fails, **halt** with a diagnostic chat reply naming the missing prerequisite (e.g., "selected analyst is `codex`, but `command -v codex` returned no result; install Codex CLI or invoke `/clarify` without `--analyst`"). Do NOT silently fall back to claude — see Hard rule #3.
   - The resolved analyst is written into the packet's `**Analyst**:` header field and the `[clarify]` chat-reply config line.

4. **Print a short config line** as the first user-visible output:
   ```
   [clarify] artifact=<path-or-description-summary>
            host=claude
            analyst=<claude | codex (model_slug) | gemini (model_slug)>
            run-dir=<RUN_DIR>
   ```
   The `analyst=` value names the analyst for this run. When non-claude, also include the resolved model slug from the config's `providers.<name>.models[0]` (e.g., `codex (gpt-5.5)`, `gemini (gemini-3.1-pro-preview)`). The `run-dir` value is the per-run workspace path (e.g., `tmp/clarify/20260502T030000-12345/`). The decision packet is written to `<run-dir>/clarify-packet.md`; the analyst's raw call audit (if non-claude) and any user-authored decision notes also live in this folder.

### Identify ambiguities (analyst)

The analyst (claude / codex / gemini, as resolved in Setup) reads the artifact and surfaces, in order of decreasing impact:

- **Ambiguities** — places where the artifact's wording allows multiple valid interpretations (e.g., "it should be fast" without a metric; "supports mobile" without naming iOS / Android / both / cross-platform).
- **Missing decisions** — choices that downstream work (review, implementation, deployment) MUST resolve, but the artifact doesn't (e.g., a mobile-app spec with no tech stack named; a deployment plan with no rollback strategy).
- **Hidden assumptions** — beliefs the artifact implicitly relies on without stating them (e.g., "the API returns JSON" assumed without a content-type spec; "the user has internet connectivity" assumed without an offline-mode story).
- **Unresolved tradeoffs** — places where the artifact wants two or more things that genuinely conflict and the conflict isn't acknowledged (e.g., "fast and accurate" without naming which to prefer when they conflict; "secure and easy to use" without acknowledging the friction).

For each item surfaced, decide whether it RISES to the level of needing a decision packet entry. The bar: "would a reasonable downstream consumer (reviewer, implementer, deployer) get this wrong if they didn't ask?" If yes, include it. If no (e.g., minor wording polish, low-impact phrasing), do NOT include it — the packet should be focused on decisions that materially affect the artifact's outcome.

Do NOT generate exhaustive lists. If you find yourself listing every possible interpretation of every word, you're filtering wrong — focus on what the user actually has to decide before the artifact can move forward.

**Substantive findings only — no "weather-talk".** Every entry must name a CONCRETE downstream impact. If the question is essentially "what do you think about X?" without a downstream-decision consequence, it does NOT belong in the packet. Counterexamples (do NOT surface):

- "Should the document use Title Case or sentence case for section headings?" — formatting; doesn't affect implementer or reviewer behavior.
- "What's a good name for the wuzzle thing?" — naming preference; deferrable; no decision-impact.
- "How should we describe the auth flow in marketing materials?" — out of scope for a requirements artifact.
- "Have you considered alternative approaches like X, Y, Z?" — speculative; not grounded in the artifact's evidence.
- "Should we add a 'further reading' section?" — nice-to-have; not blocking.
- "What's the team's preference for indentation?" — style; doesn't change behavior.

Substantive entries (DO surface):

- "Which of {iOS-only, Android-only, cross-platform} is v1's target?" — drives team, schedule, framework choice; downstream blocking.
- "What's the P95 latency target for tap-to-result?" — concrete, testable; without a number, performance can't be validated.
- "Does 'offline support' include create-while-offline, or only read-while-offline?" — drives architecture; 5–10× engineering-effort difference between options.

If you cannot complete the sentence "if this isn't decided, the implementer/reviewer/deployer will silently default to X, leading to Y problem", **the entry doesn't belong in the packet**. The "Impact if left unresolved" field is the test: if you can't write a non-trivial, concrete answer there, drop the entry.

**Aim for at least 10 entries when the artifact has that many genuine ambiguities.** The 10 is a **target floor**, not a ceiling — its purpose is to push thoroughness, not to cap output. The analyst MUST NOT stop the impact-filter walk early once it has 10 candidates; the analyst MUST continue surfacing candidates until none of the remaining unsurveyed material rises to the impact bar. There is **no upper bound**; if the artifact has 15 or 20 genuine ambiguities and they all clear the impact filter, the packet has 15 or 20 entries — write them all.

Specifically:

- If the filter surfaces **≥ 10 candidates**, write all of them. Order entries by decreasing impact (most consequential first) so the user can read top-down.
- If the filter surfaces **< 10 candidates**, write what you have — do NOT pad with weak items just to hit 10. The 10 is a floor of intent, not a quota; if the artifact genuinely has 4 high-impact ambiguities and nothing else, write 4 entries. (But before settling on a low count, double-check you haven't impact-filtered too aggressively. The bar is "would a reasonable downstream consumer get this wrong without asking?" Many things do, and the analyst should be honest about surfacing them.)
- If the filter surfaces **0 candidates**, see § Empty-packet case below — the packet is still written, with a clear "no questions" status; the user is informed that the manual cycle (with this analyst) is complete and the artifact is ready for either a different analyst's perspective via `/clarify --analyst <other>` or `/cross-ai-review` for governed verification.

The "10 floor" is calibrated against typical real-world artifacts. A complex spec (mobile app requirements, deployment plan, architecture doc) usually has 10–20 genuine ambiguities the first time `/clarify` runs; few have under 5. If the analyst produces a packet with 3 or 4 entries against a one-page-or-larger artifact, that's a soft signal something is off — the analyst may have skimmed (try increasing `thinking_level`), or treated the run as a `/cross-ai-review` correctness pass instead of a `/clarify` intent-formation pass.

#### Analyst invocation

The candidate-surfacing step branches on the resolved analyst:

- **`--analyst claude` (default)**: Claude (the host) reads the artifact in-process and surfaces candidates directly. No external CLI call. The packet's `**Source**:` line for each entry reads `claude (host as analyst)`.

- **`--analyst codex` or `--analyst gemini`**: Claude orchestrates the call to the named CLI via the existing helper (`~/.claude/cross-ai-review-helpers/codex-call.sh` or `gemini-call.sh`), passing the helper's `--schema none` flag (the analyst returns the packet's entry-block markdown directly, not schema-enforced JSON — see § Helper schema modes). The helper invocation uses:
  - `--layer 0 --primitive P1 --phase semantic-iterate --outer 1 --iter 1 --role iterating` (closest reuse of existing helper interface — there is no `/clarify`-specific primitive or phase in v1; the helper just passes through the prompt and captures the response with halt classification preserved)
  - `--model <provider's first model from config>` `--thinking-level <provider's thinking_level from config>`
  - `--prompt-file <RUN_DIR>/.tmp-prompt-<call-started>.txt` (Claude writes the prompt here first; the prompt instructs the model to surface ambiguities + render them in the packet's entry-block markdown shape verbatim)
  - For Gemini: `--stdin-file <RUN_DIR>/.tmp-stdin-<call-started>.txt` containing the artifact content concatenated (Gemini does not have file-tool access by default; see /cross-ai-review's same rule)
  - `--run-dir <RUN_DIR>` `--call-started <call-started>`
  - **`--schema none`** to disable JSON schema enforcement (the analyst returns markdown, not JSON)

  **On analyst success**: Claude reads the helper's output (markdown text), validates it parses as a sequence of `### N) ...` entry blocks, and writes the packet (header + entries + `## Next steps for the user` section) to `<RUN_DIR>/clarify-packet.md`. Claude also writes the raw call audit to `<RUN_DIR>/<call-started>-<cli>-iter-P1-1-1.md` using the standard per-call markdown template (with `**Source**: analyst` on the call file's findings — this is one call, one analyst, not a cross-check), so the user can audit what the analyst surfaced and how Claude formatted it.

  **On analyst failure (any halt class A–G)**: per Hard rule #3, `/clarify` HALTS the run. Claude writes:
  - The halt-variant per-call audit at `<RUN_DIR>/<call-started>-<cli>-iter-P1-1-1.md`
  - `<RUN_DIR>/halt-classification.md` per `/cross-ai-review`'s halt-classification format (reused for consistency)
  - A diagnostic chat reply naming the analyst, the halt class, and the suggestion to retry with `--analyst <other>` if the user wants a different perspective.

  Claude does NOT silently retry with a different analyst, and does NOT write an empty packet. The user explicitly chose this analyst; if it failed, that's the user's signal to either retry or pick a different analyst.

### Construct the decision packet

For each surviving candidate (analyst-surfaced and impact-filtered per § Identify ambiguities), construct a decision packet entry in the format below. Order entries by **decreasing impact** (most consequential decisions first), not by location in the artifact. There is **no cap on entries** — write all candidates that cleared the impact filter, even if there are more than 10. The "10" in § Identify ambiguities is a floor of intent (encouraging thoroughness), not a ceiling.

Do NOT artificially expand the packet. If only 3 entries survive the impact filter, write a 3-entry packet — that's a clean, focused output. Just make sure the impact filter wasn't applied too aggressively (see the diagnostic note in § Identify ambiguities).

### Empty-packet case (0 entries surfaced)

When 0 candidates survive the impact filter, the artifact's intent is sufficiently settled that no decisions need to be made before review or implementation. The host **still writes a packet file** with a clear "no entries" status. This gives the user explicit confirmation that the cycle ran cleanly AND nothing remains to clarify — they don't have to wonder whether `/clarify` returned no questions or returned no output at all.

The empty packet's structure:

```markdown
# Clarification packet — <RUN_ID>

**Date**: <ISO 8601 UTC>
**Artifact**: <path or description>
**Run directory**: `tmp/clarify/<RUN_ID>/`
**Host**: claude (orchestrator)
**Analyst**: <claude (host as analyst) | codex (model_slug) | gemini (model_slug)>
**Total entries**: 0

## Decision packet

_No entries surfaced. From this analyst's perspective, the artifact's intent appears settled; no decisions need to be made before review or implementation can proceed._

If you expected ambiguities here and got none, that's a soft signal something may be off — usually a too-low `thinking_level` causing the model to skim, or the analyst treating /clarify as a /cross-ai-review correctness check rather than an intent-formation pass. Try increasing `thinking_level` to `deep` and re-running before concluding the artifact is settled from this analyst's perspective.

## Next steps for the user

The /clarify cycle with this analyst is complete for this artifact. Two reasonable next steps:

1. **Try a different analyst's perspective** (optional): re-run with `--analyst codex` or `--analyst gemini` — each model surfaces different ambiguities, and a fresh perspective may catch what this analyst missed. If multiple analysts each surface no further material ambiguities, the artifact is **reasonably clarified from those configured perspectives**, but the user remains the decision authority — "reasonably clarified" is a confidence signal, not a guarantee of completeness.
2. **Proceed to `/cross-ai-review <artifact>`** for governed verification of the now-settled intent — that's the natural next command in the workflow when you've decided enough.

If you want to keep iterating on intent-formation against this analyst (e.g., to re-confirm after a substantial edit you make later), you can re-run with the same analyst at any time. Each new run gets a new `<RUN_ID>` in a fresh folder; this run dir stays for audit.
```

In the chat reply for the empty case, state explicitly: "0 entries — artifact's intent appears settled; ready for /cross-ai-review". Don't bury the conclusion. Print the packet path so the user can read the diagnostic note + suggestion if they want.

### Output

The host writes **one file** in the run directory: the decision packet, which is both the host's analysis output AND the user's workspace. Each entry has a host-written analysis zone (the questions and options Claude surfaced) followed by a user-fill-in zone (where the user records their choice and any notes/follow-up questions). The user works in the same file end-to-end.

#### `<RUN_DIR>/clarify-packet.md`

```markdown
# Clarification packet — <RUN_ID>

**Date**: <ISO 8601 UTC>
**Artifact**: <path or description>
**Run directory**: `tmp/clarify/<RUN_ID>/` (relative to repo root)
**Host**: claude (orchestrator)
**Analyst**: <claude (host as analyst) | codex (gpt-5.5) | gemini (gemini-3.1-pro-preview) — whichever was selected via --analyst, with the resolved model slug in parentheses for non-claude analysts>
**Analyst call audit**: <"none — claude was the analyst (in-process)" when --analyst claude (default); OR the path to the per-call .md inside this run dir for non-claude analysts, e.g., "<call-started>-codex-iter-P1-1-1.md">
**Total entries**: <N> (target floor: 10; no upper bound)

## Decision packet

### 1) <Question phrased as a question, ≤ 80 chars>?

**Why it matters**: <one paragraph: what downstream work depends on this decision; what failure modes occur if it's left unresolved>

**Choices**:

* **A: <option name, ≤ 6 words>**
  - **Pros**:
    - <substantive pro 1>
    - <substantive pro 2>
    - <substantive pro 3 if applicable>
  - **Cons**:
    - <substantive con 1>
    - <substantive con 2>
    - <substantive con 3 if applicable>
* **B: <option name>**
  - **Pros**:
    - <pro 1>
    - <pro 2>
  - **Cons**:
    - <con 1>
    - <con 2>
* **C: <option name>** (when there are three; usually 2–4 options total)
  - **Pros**: <…>
  - **Cons**: <…>

**Recommendation**: A: <option name>
**Reason**: <one paragraph: why this option fits the apparent context of the artifact best; what assumptions the recommendation rests on. The user can override with full information.>

**Impact if left unresolved**: <one paragraph: what happens silently if the user proceeds without deciding — typically downstream consumer (reviewer, implementer, deployer) picks a default, propagating an implicit choice as if intentional>

**Suggested artifact update after the user decides**: <a paragraph or short code block describing the specific edit the user (or Claude on follow-up) should make to the artifact AFTER the decision is recorded. Concrete: name the section, name the wording, name the constraint to add. Do NOT apply this update during /clarify.>

**Source**: <claude (host as analyst) | codex (gpt-5.5) | gemini (gemini-3.1-pro-preview) — same value across all entries in a single packet; matches the packet header's **Analyst** field>

---

#### Your decision (fill in below)

**My choice**: <fill in with the option label, e.g., `A: React Native` — or leave blank to defer>

**Further comments**: <optional — notes, additional context, follow-up questions for Claude. Leave blank if none.>

---

### 2) <next question>?

… same shape …
```

Notes on the entry shape:

- **Pros and cons are inline with each choice**, not in a table. This gives room for substantive bullets per option (2–5 bullets each is typical; honest tradeoffs, not strawman comparisons). A table would constrain each cell to a phrase; inline allows a sentence.
- **Recommendation + reason flow naturally after the choices** so the user reads option-by-option then the host's call.
- **`Your decision` is the user's zone**. The user fills in `My choice` and optionally `Further comments` directly in this same packet file. That makes the file the user's complete workspace — no second file to coordinate with.
- **Leaving `My choice` blank means defer**. Claude skips deferred entries when applying.

### Next steps for the user

The packet ends with a self-contained how-to section the user reads when they're ready to act:

```markdown
## Next steps for the user

This packet is **advisory output** — Claude has surfaced what needs deciding but has NOT decided anything. The decision authority is yours. The packet doubles as your workspace: read each entry, fill in `My choice` (and optionally `Further comments`) directly in the entry's `Your decision` block, then hand the filled packet back to Claude.

### Reading and deciding

1. Read each entry top-to-bottom: question → why it matters → choices with pros/cons → recommendation + reason → impact if left unresolved → suggested artifact update.
2. For each entry, fill in **`My choice`** (e.g., `A: React Native`) directly in the `Your decision` block of that entry. Leave it blank to defer.
3. Add **`Further comments`** if helpful — your context, dissent from the recommendation, or a follow-up question for Claude (see "Asking follow-up questions" below). Optional.
4. Save the file. Your edits stay in this run folder permanently; they don't disappear if you close Claude or change sessions.

### Asking follow-up questions before deciding

If a packet entry's options or tradeoffs are unclear, you have two ways to ask Claude:

- **In chat (immediate)**: "For question 3 (backend choice), tell me more about how option B handles offline writes." Claude reads the relevant entry + the artifact and answers conversationally. The packet is unchanged.
- **In `Further comments` (async)**: write a question in the entry's `Further comments` block (e.g., "What's the operational cost difference between A and B at 100 daily users?"), save the file. When you ask Claude to apply decisions, Claude can answer any pending questions in `Further comments` blocks before applying — useful when you stop and come back later.

You don't need to commit to any decision before asking follow-ups. Decisions stay blank until you fill them in.

### Applying decisions

Once one or more entries have `My choice` filled in, ask Claude:

> Apply my decisions in `tmp/clarify/<RUN_ID>/clarify-packet.md` to `<artifact-path>`.

Claude will:

1. Read the packet.
2. For each entry with `My choice` filled in, apply the corresponding `Suggested artifact update` to the target artifact (using your chosen option).
3. For entries with `My choice` blank, skip them (deferred — they stay for next time).
4. For entries with a question in `Further comments`, answer the question first; the user then decides whether to fill in `My choice` or keep deferring.
5. Report which entries were applied vs. deferred vs. answered-but-not-applied.

The packet file itself is NOT modified by Claude during apply — only the target artifact is changed. Your `My choice` and `Further comments` edits stay in the packet as a permanent record of what was decided when.

### Quick-apply alternative (no file editing)

If you'd rather not edit the file, you can pass decisions inline in chat:

> Apply my /clarify decisions from `tmp/clarify/<RUN_ID>/clarify-packet.md` to `<artifact-path>`:
> - 1: A
> - 2: B
> - 3: defer
> - 4: A

Same outcome — Claude reads the packet, applies the entries you named with the options you chose, defers the rest.

### Deferring entries

Leave `My choice` blank in the file (or omit the entry from your inline list). Claude skips that entry in apply. The packet stays as-is. Come back any time — the same packet applies until the artifact's intent has shifted significantly or you re-run `/clarify`.

### The iterative cycle (what to expect across multiple runs)

`/clarify` is designed to **iterate until the artifact's intent is settled**. The iteration is **not optional after applying decisions** — it is the only way to verify settled intent. The convergence signal is unambiguous: `Total entries: 0` on a fresh run. Until you see that, more questions may exist that the prior packet couldn't have surfaced (because they only become reachable after earlier decisions are applied).

A typical workflow:

1. **Run `/clarify <artifact>`** → packet with at least 10 entries when that many genuine ambiguities exist (and as many more as the impact filter surfaces; no upper bound). For small or already-mostly-settled artifacts, the packet may have fewer than 10.
2. **Read the packet, fill in `My choice` per entry**, save the file. (Optional: ask follow-up questions in chat or via `Further comments` first.) For large packets (15+ entries), it's fine to decide a subset, apply, and come back for the rest.
3. **Ask Claude to apply** (`Apply my decisions in tmp/clarify/<RUN_ID>/clarify-packet.md to <artifact>`). Claude updates the artifact based on each filled-in decision; entries with `My choice` blank are deferred.
4. **MUST re-run `/clarify` on the updated artifact**, unless step 1 already returned `Total entries: 0`. Applied decisions can reveal new ambiguities downstream — e.g., picking "React Native" as the tech stack may surface a new question about navigation library; picking "OAuth with Apple + Google" may surface new questions about session-token storage. New runs get fresh `<RUN_ID>`s in fresh folders. Re-running also re-surfaces entries you deferred in the prior packet (with the same stable wording so they're recognizable). **Skipping the re-run after an apply leaves you uncertain whether intent is settled — only a `Total entries: 0` result confirms it.**
5. **Iterate steps 2–4 until `/clarify` returns `Total entries: 0`** ("no questions surfaced — artifact's intent appears settled"). That signal means the manual intent-formation cycle is complete.
6. **Move to `/cross-ai-review <artifact>`** for governed verification of the now-settled artifact.

When Claude finishes an apply step, it MUST tell the user explicitly: "Applied N decisions to `<artifact>`. To verify intent is now settled, re-run `/clarify <artifact>`. The cycle is complete only when `/clarify` returns `Total entries: 0`." Don't bury this in the apply report; it's the explicit handoff that drives convergence.

Most artifacts converge in 1–3 cycles. If you find yourself running `/clarify` more than 4 times against the same artifact and still getting 10+ questions each pass, that's a signal the artifact may be too vague even for iteration to converge — consider a structural rewrite rather than continuing to clarify in pieces.
```

#### Chat reply

After the packet is written, mirror in the chat reply:

- The same `[clarify]` config line printed at the top (including the `run-dir` path).
- A short summary: total entries, top 3 most-consequential by title.
- The full path to the packet (`<run-dir>/clarify-packet.md`).
- A one-line pointer: "**See the packet's `## Next steps for the user` section** for how to fill in decisions, ask follow-up questions, and apply."

The chat reply should stay skim-friendly (≤ 30 lines). The packet file is the source of truth and the user's workspace; the chat-reply pointer is a breadcrumb back to it when the user returns later.

### After output

Do **NOT** apply the suggested updates. Do **NOT** mark anything "decided." Do **NOT** invoke `/cross-ai-review` automatically (the artifact still has unsettled intent; running `/cross-ai-review` against it now would re-surface the same ambiguities through a more expensive cycle).

The cycle is complete when the packet is written and the chat reply is presented. The user takes it from there — possibly in a different session, possibly weeks later. The packet's `Your decision` blocks + `Further comments` fields + `## Next steps for the user` section are sufficient for the user to make decisions and hand them back without needing the original chat history.

## Decision packet entry — field-by-field reference

Each entry has two zones: the **host-written analysis** (what /clarify surfaced) and the **user-fill-in `Your decision` block**. The host writes the analysis when /clarify runs; the user fills in their choice and notes when they're ready to decide. Claude does NOT modify the analysis zone after /clarify runs; the user does NOT modify the analysis zone (they could, but the field labels and content would no longer match what /clarify originally said).

### Host-written analysis (8 fields)

1. **Question** — phrased as a question, ≤ 80 chars, with the heading shape `### N) <question>?`. Must be answerable. "Should we use iOS or Android first?" is good; "Mobile platform" is bad (not a question; not specific). Use stable wording so re-runs of `/clarify` against the evolving artifact can dedupe entries.
2. **Why it matters** — what downstream work depends on this decision. Cite specific concerns: review, implementation, deployment, performance, cost, security, compliance, accessibility.
3. **Choices** — the realistic options. Usually 2–4. Each labeled `A:`, `B:`, `C:` etc. with a short option name (≤ 6 words). If only one option is realistic, that's not a decision — it's an unstated constraint, and the entry should be reframed as a hidden assumption: "Why does the artifact assume X?"
4. **Pros and cons inline per choice** — under each option, two sub-bullets `Pros:` and `Cons:`, each containing 2–5 bullets. Substantive (not strawman). Honest tradeoffs. Pros/cons live with the choice they describe (NOT in a separate table) so the reader compares option-by-option naturally.
5. **Recommendation** — the host's judgment of which option fits best, named explicitly with the option label (e.g., `A: <name>`). Phrased as a recommendation, not a statement of fact ("I recommend A because…", not "A is correct because…"). The user can disagree.
6. **Reason** — why the recommendation fits the apparent artifact context. Surface the assumptions the recommendation rests on. If the user changes those assumptions, the recommendation changes.
7. **Impact if left unresolved** — what happens silently if the user proceeds without deciding. Typically: downstream consumer (reviewer, implementer, deployer) picks a default, the user inherits it as if intentional.
8. **Suggested artifact update after the user decides** — the specific edit the user (or Claude on follow-up) should make to the artifact once the decision is recorded. Concrete: name the section, name the wording, name the constraint to add. Per Hard rule #2, this is described, NOT applied during /clarify.

Plus a **Source** line attributing the entry to the analyst: `claude (host as analyst)`, `codex (gpt-5.5)`, `gemini (gemini-3.1-pro-preview)`, etc. The Source value matches the packet's `**Analyst**:` header field — every entry in a single packet has the same analyst (substitutive design; one analyst per run).

### User-fill-in `Your decision` block (2 fields)

1. **My choice** — the option label the user picks (e.g., `A: React Native`). Leave blank to defer.
2. **Further comments** — optional. The user's notes, additional context, dissent from the recommendation, or follow-up questions for Claude. The user can ask "why is option B better than C for offline-first scenarios?" here, save the file, and Claude will answer when next invoked. Empty if the user has nothing to add.

A complete entry — host analysis filled in by /clarify, user-decision block filled in by the user — produces a tractable decision: the user reads the question, evaluates the options against the recommendation, picks one, optionally takes notes, and Claude knows exactly what to apply to the artifact.

## Analyst selection

Each `/clarify` invocation has exactly one analyst — the entity that surfaces the candidate ambiguities. The user picks the analyst via `--analyst <name>`; no auto-substitution.

### The three options

| Flag | Analyst | When to use |
|---|---|---|
| _(none)_ — default | **claude (host as analyst)** | Default; works without external CLIs; uses Claude's reasoning directly. Most common case. |
| `--analyst codex` | **codex** (whichever model is first in `providers.codex.models` per `~/.claude/cross-ai-review-config.json`) | Fresh perspective from a different vendor; useful after claude has run and you want to see what codex notices that claude missed. |
| `--analyst gemini` | **gemini** (whichever model is first in `providers.gemini.models`) | Fresh perspective from a third vendor; useful after claude and codex have run. |

### Cross-analyst iteration

A productive workflow when you want maximum perspective:

1. Run `/clarify <artifact>` (analyst = claude). Review packet, decide, apply, **re-run /clarify** (Hard rule: re-run is required after any apply unless the prior run returned 0 entries).
2. Continue cycle until claude's `/clarify` returns `Total entries: 0`.
3. (Optional) Re-run with `--analyst codex` against the now-claude-clarified artifact. Codex may surface ambiguities claude missed. If so: decide, apply, re-run with codex until 0.
4. (Optional) Re-run with `--analyst gemini`. Same process.
5. **If multiple analysts each surface no further material ambiguities, the artifact is reasonably clarified from those configured perspectives.** This is a **confidence signal**, not a guarantee of completeness — the user remains the decision authority. There may still be ambiguities none of the configured analysts noticed; only the user knows their domain well enough to judge.

This is NOT a "convergence proof" workflow. The `/cross-ai-review` cycle has a formal convergence model (set-stable across iterations, multi-reviewer cross-check, verify pass). `/clarify` deliberately does not — it produces decision support, and "decision support quality" is judged by the user, not by an automated convergence test.

### When the analyst is not claude

The host (Claude) still:

- Creates the run dir
- Writes the prompt file
- Invokes the helper (`codex-call.sh` / `gemini-call.sh`) with `--schema none` (markdown response, not schema-enforced JSON)
- Reads the analyst's response
- Validates it parses as a sequence of `### N) ...` entry blocks
- Writes the packet (header + entries + Next-steps section) to `<RUN_DIR>/clarify-packet.md`
- Writes the raw call audit to `<RUN_DIR>/<call-started>-<cli>-iter-P1-1-1.md`
- Applies user decisions to the target artifact when the user is ready

Only the **candidate-surfacing step** is delegated to the analyst CLI. Orchestration, formatting, audit, and apply-decisions are always Claude's job.

### Cost note

A `--analyst codex` or `--analyst gemini` run consumes the named CLI's tokens for one call (the candidate-surfacing). Subsequent apply / follow-up-Q&A turns use Claude (host) only and do not touch the CLI. So cost is roughly equivalent to one `/cross-ai-review` cross-check call, not a full cycle.

## When to stop

Stop the cycle and present the packet when:

- All analyst-surfaced candidates have been impact-filtered and the survivors are constructed into entries.
- The packet file is written.
- The chat reply summary is composed.

Do not iterate within a single `/clarify` invocation. There is no in-run iteration loop. The user iterates across invocations by deciding, applying, and re-invoking `/clarify` (per Hard rule on mandatory re-run after apply). Optional cross-analyst exploration is also across-invocation — `--analyst <other>` for a fresh perspective, not within a single run.

## What `/clarify` is NOT

- **Not a review.** It does not approve, request changes, or block. The artifact at the `/clarify` stage is incompletely specified, not incorrect. **`/clarify` produces decision packets; `/cross-ai-review` produces review findings and verification artifacts** — the two outputs are distinct, and the two commands serve different stages.
- **Not an editor.** It does not apply changes. The host describes what to change AFTER the user decides; the user (or Claude on follow-up) applies.
- **Not a substitute for `/cross-ai-review`.** Once the artifact's intent is settled (the user has decided the major ambiguities), use `/cross-ai-review` to verify the artifact against its declared upstream authority.
- **Not authority-aware.** `/clarify` does not know about layered DAGs, peer-mode, primitives (P1–P6), output modes (apply / report), thinking levels, or the audit-trail formalism that `/cross-ai-review` uses. Those are properties of the cross-AI review cycle. `/clarify` is a much simpler companion.
- **Not multi-analyst within a run.** Substitution, not addition: `--analyst codex` runs codex INSTEAD of claude; it does not add codex on top of claude. To get multiple analysts' perspectives, run multiple `/clarify` invocations.
- **Not silent on failure.** If the host hits genuine surprises (artifact unreadable, repo root unresolvable, analyst halt), surface them in the chat reply. Do NOT pretend they didn't happen.

## Notes on configuration reuse

`/clarify` reuses `~/.claude/cross-ai-review-config.json` for provider/model/thinking-level choices. The same `providers.codex.models[0]` (and `gemini.models[0]`) and `providers.<name>.thinking_level` values are used when the analyst is codex or gemini. `role_preference` is NOT consulted by `/clarify` — that field is `/cross-ai-review`-specific (governs which CLI is iterating vs. cross-checking). `/clarify` is single-analyst-per-run, so role-preference doesn't apply.

There is no separate `clarify-config.json`. This is a deliberate scope-keeping decision for v1: most users will run both `/clarify` and `/cross-ai-review` against the same providers, with similar quality-vs-cost tradeoffs. If divergent settings become useful later (e.g., a `clarify.codex.thinking_level` override), a `clarify` block could be added to the existing config without changing the slash command's resolution logic.

`/clarify` also reuses the helper scripts at `~/.claude/cross-ai-review-helpers/codex-call.sh` and `gemini-call.sh`. Same read-only sandboxing, same actual-model verification (Class E protection), same halt classification — but with `--schema none` to disable JSON schema enforcement (the analyst returns markdown, not structured findings JSON). See § Analyst invocation for the exact flag set.
