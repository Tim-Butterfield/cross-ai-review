# Smoke test

This directory contains a deliberately flawed sample artifact (`sample-artifact.md`) for verifying the cross-AI review install works end-to-end.

The smoke test exercises the cycle's **single-artifact / Layer 0 implicit / minimal profile / P1-only** path. It does NOT exercise layered-DAG, peer-mode, output-mode `--report`, mechanical primitives (P3/P5), or upstream-conflict restart — those are validated separately. If you also want to try those, see the alternative invocations below.

## How to run

After completing the install (per the parent directory's `INSTALL.md`):

1. **Start a NEW Claude Code session** in this directory:
   ```sh
   cd /path/to/cross-ai-review/smoke-test/cross-ai-review
   ```
   The slash command is loaded at session start. If you installed the pack in your current session, the `/cross-ai-review` command will not be recognized until you start a fresh session.

2. Invoke the slash command:
   ```
   /cross-ai-review sample-artifact.md
   ```

3. **First-run permission prompt**: the first time the host invokes a reviewer helper, Claude Code shows a permission prompt for either `~/.claude/cross-ai-review-helpers/codex-call.sh *` or `~/.claude/cross-ai-review-helpers/gemini-call.sh *` (depending on which CLI is iterating). **Choose "always allow" to grant session-long approval scoped to the helper path.** Do this once per helper. If the prompt offers an overbroad pattern like `bash *`, refuse — that would grant any-bash-command rights for the session. (See methodology § Hard rule 5 for why the helper path is the safe scope.)

4. Claude will execute the cycle. You should see:
   - A `[config]` line on the first line of output naming the loaded config path, the resolved iterating + cross-check role assignments, the resolved scope (`scope=single-artifact`), and `output_mode=apply` (default; this confirms the runtime config-load is working).
   - A `tmp/cross-ai-review/<RUN_ID>/` directory created (located at `smoke-test/tmp/cross-ai-review/<RUN_ID>/` if running outside a git worktree, or at the git repo root's `tmp/cross-ai-review/<RUN_ID>/` if `smoke-test/` is inside a git repo — per methodology § Persistence to canonical run directory).
   - A consolidated per-call markdown file matching the unified grammar `<call-started>-<cli>-iter-P1-1-1.md` (e.g., `20260501T220000-codex-iter-P1-1-1.md` if Codex is iterating; `*-gemini-iter-P1-1-1.md` if Gemini is iterating). The file contains the call metadata (Layer + Primitive=P1 + Phase=semantic-iterate + Role=iterating + Output mode=apply + Thinking level), reviewer's findings, the host's per-finding decisions, the addressed context that was sent (N/A on the first call), the halt event (None), and the raw stderr capture — all in one human-readable file.
   - The iterating reviewer producing 3-5+ findings (visible in the markdown file's `## Findings` section).
   - A verdict of `request_changes` or `block` (not `approve`).

5. **Cost expectation**: a full smoke-test run uses real reviewer-CLI credits. With both Codex and Gemini installed, expect 6-12 reviewer calls in the worst case (4 inner iterations + 1 cross-check + 1 verify, possibly more if outer cycle 2 triggers). Each call uses ~50-100k input tokens for this small artifact. Total: a few cents to a quarter on each provider, depending on your account tier and the chosen `thinking_level`. Set `thinking_level: fast` in `~/.claude/cross-ai-review-config.json` for a cheaper trial.

## Alternative invocations to exercise more of v1

- **Report mode**: `/cross-ai-review --report sample-artifact.md` runs single-pass (no edits applied) and writes findings to `findings-summary.md` instead of `review-summary.md`. Useful for confirming the report-mode pipeline works without consuming the iteration budget.
- **Peer mode**: copy the sample artifact to `sample-artifact-twin.md` (or any other content) and invoke with both: `/cross-ai-review sample-artifact.md sample-artifact-twin.md`. With no declared upstream and no confident hierarchy, the cycle should resolve `scope=peer-mode` and run P1 no-upstream per artifact.

## Deliberate flaws in the artifact

The sample-artifact contains the following issues, which any reasonable AI reviewer should surface:

| Flaw | Section | Expected finding kind |
|---|---|---|
| Vague Purpose ("maybe", "possibly", "probably") | Purpose | `ambiguity` |
| Placeholder text (`TBD`, `(fill in)`) | Inputs | `fail` or `gap` (no-placeholders criterion) |
| Duplicate Output entries (two `frobnicator` outputs without distinction) | Outputs | `inconsistency` or `ambiguity` |
| Contradictory error handling (throws AND returns null on same condition) | Error Handling | `inconsistency` |
| Vague performance target ("fast", "reasonable limits") | Performance | `ambiguity` or `gap` |
| Vague verification ("eyeball the logs") | Verification | `ambiguity` (no concrete check) |
| Missing definition of "wuzzle" | Inputs | `gap` (undefined term) |
| DoD without measurable criteria | Definition of Done | `gap` |
| Duplicate logging-to-stderr-and-file in error handling without explicit policy | Error Handling | `risk` or `inconsistency` |

A passing smoke test surfaces **at least 4 of these 9** flaws. If the configured iterating reviewer returns only 1-2 findings or returns `approve`, that's a soft signal something is off (e.g., a too-low `thinking_level` causing the model to skim, an unusually-cached prompt, or the artifact having been pre-fixed by a prior run). It is NOT a sign of silent model fallback — silent fallback halts as Class E unconditionally per the methodology, surfacing as a Class E halt event in `tmp/cross-ai-review/<RUN_ID>/halt-classification.md` rather than a quiet finding-count drop.

If you do see fewer than expected findings: try increasing `thinking_level` in `~/.claude/cross-ai-review-config.json` to `deep`, or re-run with a freshly-copied sample-artifact.md (in case prior fixes were applied). If the cycle halts on the first call instead of producing findings, see the parent `INSTALL.md` Step 9 (smoke test) and § Halt-signal taxonomy in the methodology.

## Stopping the smoke test

You only need the first iterating-reviewer call to complete successfully to validate the install. After the first iteration produces results, you can:
- Let the cycle continue (it will likely apply some fixes and iterate further; the methodology caps the cycle at 3 outer cycles × 4 inner iterations per primitive, so it cannot run forever)
- Or interrupt Claude and abandon the run — the install is already validated

The sample-artifact has so many flaws that the cycle would not realistically clear them all within the 3-outer-cycle cap. That's fine — the smoke test is about plumbing, not artifact quality. If the cycle reaches the cap and escalates, that itself is valid plumbing output (escalation entries appear in `review-summary.md` under "Unresolved (escalation)").

## Cleanup after smoke test

The run directory created by the smoke test (`tmp/cross-ai-review/<RUN_ID>/`) can be deleted after you've verified the install:

```sh
rm -rf tmp/cross-ai-review/
```

Or leave it — it's a useful reference for what the audit trail looks like in a real run.
