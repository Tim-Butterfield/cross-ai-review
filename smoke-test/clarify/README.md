# /clarify smoke test

This directory contains a deliberately under-specified sample artifact (`sample-mobile-app-requirements.md`) for verifying the `/clarify` install works end-to-end.

The artifact is a 1-page mobile-app requirements doc that names a product ("MapMyTrip"), a target user, core features, and some quality goals — but **omits or underspecifies decisions a downstream implementer would need to make before writing code**. It is the right shape of artifact for a `/clarify` invocation: well-formed at the prose level, ambiguous at the implementation-decision level.

## How to run

After completing the install (per the parent directory's `INSTALL.md`):

1. **Start a NEW Claude Code session** in this directory:
   ```sh
   cd /path/to/cross-ai-review/smoke-test/clarify
   ```
   The slash command is loaded at session start.

2. Invoke the slash command:
   ```
   /clarify sample-mobile-app-requirements.md
   ```

3. Claude will execute the cycle. You should see:
   - A `[clarify]` line on the first line of output naming the artifact, host (`claude` orchestrator), resolved analyst (`claude` for default; `codex (model_slug)` or `gemini (model_slug)` if `--analyst` was used), and the run-dir path.
   - A `tmp/clarify/<RUN_ID>/` folder created with `clarify-packet.md` inside. Each entry in the packet has a host-written analysis zone followed by a `Your decision (fill in below)` block with blank `My choice` / `Further comments` fields. If `--analyst codex` or `--analyst gemini` was passed, the analyst's single per-call audit (`<call-started>-<cli>-iter-P1-1-1.md`) is also in this folder. Default-analyst (`claude`) runs have no extra audit file (Claude is in-process).
   - A chat-reply summary listing total entries and the top 3 most-consequential decisions.

4. Open the packet file. Each entry follows the 8-field format: question, why-it-matters, options, pros/cons, recommendation, reason, impact-if-unresolved, suggested-update-after-decision.

## Deliberate ambiguities in the artifact

These decisions are intentionally absent or underspecified. A reasonable `/clarify` run should surface most of them as decision-packet entries. The exact set varies by reviewer judgment, but the well-targeted ambiguities are:

| Ambiguity | Section | What's underspecified |
|---|---|---|
| Tech stack not named | Overview / Distribution | iOS only? Android only? Cross-platform? Native? React Native / Flutter / Capacitor? Major impact on team, schedule, capabilities. |
| Auth mechanism unspecified | Security | Email+password? OAuth (Apple / Google / Facebook)? Magic link? Passkeys? Drives Security and Distribution decisions. |
| Backend / data store | (implicit, not stated) | Self-hosted? Firebase? Supabase? CloudKit? PostgreSQL on someone's VPS? Drives offline support, sharing model, export pipeline. |
| Offline storage scope | Offline support | Read-only cache? Full-create-when-offline with later sync? Conflict resolution if two collaborators edit offline? |
| Photo storage | Photo attachment | On-device only? Cloud-backed? Original-vs-thumbnail? Affects offline support, export, storage costs. |
| Sharing model | Trip sharing | Per-trip invite or per-user friend list? Read-only vs. write access? Revocable invites? |
| Performance metrics | Performance | "Fast" with no numbers — what tap-to-result latency target? What map-load target? What FPS during photo scroll? Untestable as written. |
| Distribution channel | Distribution | App Store + Play Store? Sideload? TestFlight? Public release vs. private cohort first? Affects timeline, review process, marketing. |
| Definition of Done is non-measurable | Definition of Done | "Three of us have used it on a weekend trip without crashing" is not a testable acceptance criterion in CI. What's the actual gate? |
| Privacy / data residency | Security | "Photos must not leak" — to whom? GDPR / CCPA implications? Data residency by region? |
| Accessibility | (not stated) | VoiceOver? Dynamic Type? Color contrast? Accessibility regs in target markets? |
| Internationalization | (not stated) | English-only v1? Currency / date formats by locale? RTL languages? |
| Push notifications | (not stated) | Notify collaborators when pins are added? FCM / APNs? Permission flow? |
| Map provider | (implicit) | Apple Maps / Google Maps / Mapbox / OSM? Each has cost, attribution, offline-support, and feature-set tradeoffs. |
| Cost model | (not stated) | Free? Paid? Freemium? Subscription tier? Affects backend choice, performance budget, marketing. |

**Pass / warn / fail thresholds** (use these consistently with INSTALL.md Step 9d):

- **Pass**: packet contains **≥ 10 entries** (the sample artifact has 15 deliberate ambiguities; `/clarify` aims for thoroughness with a floor of 10 and no upper bound — a healthy run surfaces all 15 or close to it). Entries have concrete options + recommendations + impacts; at least one entry is from a high-impact category (auth, tech stack, performance metric, backend, distribution).
- **Warn**: 6–9 entries — close to the floor but under it for an artifact with 15 deliberate ambiguities; investigate before declaring the run a clean pass. Likely cause: the model stopped the impact-filter walk early.
- **Fail**: < 6 entries OR no entries from the high-impact categories OR any recommendation reads as an autonomous decision rather than an advisory option.

`/clarify`'s 10 is a **target floor, not a ceiling** — see clarify.md § Identify ambiguities (§ "Aim for at least 10 entries..."). The smoke-test fixture is deliberately under-specified (15 ambiguities) so users can verify the host surfaces all of them, not just the top 10.

## What "passing" looks like for /clarify

Different from `/cross-ai-review`'s smoke test, where "passing" is "the cycle completes and finds known flaws." `/clarify`'s "passing" is:

- Output is a **decision packet** (not a review), formatted per the 8-field structure.
- Each entry is **answerable** as written (the question is specific; the options are realistic).
- Recommendations are **explicit but advisory** — the host names a recommended option but does NOT apply anything. No section of the artifact is edited.
- The run folder is real: `tmp/clarify/<RUN_ID>/` exists with `clarify-packet.md` inside (plus reviewer audits if any).
- Each entry has a host-written analysis zone (question, choices with pros/cons inline under each option, recommendation, reason, impact-if-unresolved, suggested-update, source) AND a `Your decision (fill in below)` block with blank `My choice` and `Further comments` fields.
- The packet ends with a `## Next steps for the user` section that explains how to read entries, fill in decisions, ask follow-up questions (in chat or via `Further comments`), apply filled decisions, defer entries, and when to re-run. The packet is self-documenting for a cold open later — a user who closes Claude and comes back days later has everything they need.
- If `--analyst codex` or `--analyst gemini` was used, the packet's `**Analyst**:` header field reflects that, every entry's `**Source**:` line attributes to the same analyst (substitutive design — one analyst per run), and a per-call audit file `<call-started>-<cli>-iter-P1-1-1.md` is in the run folder. If the chosen analyst halts mid-run (any halt class), `/clarify` HALTS the entire run — no packet is produced and the chat reply names the halt class. Default-analyst (claude) runs have neither the audit file nor a halt path (Claude is the in-process host; "halt" here would manifest as an artifact-unreadable error or similar surprise).

If the packet hits the **warn** or **fail** band above, that's a soft-to-strong signal something is off (likely a too-low `thinking_level` causing the model to skim, or the reviewer treating this artifact as a `/cross-ai-review` correctness check rather than a `/clarify` decision-support pass). Try increasing `thinking_level` to `deep` in `~/.claude/cross-ai-review-config.json` and re-run.

## Variations to try

- **Apply decisions from the filled packet**: open `tmp/clarify/<RUN_ID>/clarify-packet.md` in your editor; for each entry, fill in `My choice:` (e.g., `A: React Native`) and optionally `Further comments:` directly in the entry's `Your decision (fill in below)` block. Save the file. Then ask Claude: "Apply my decisions in `tmp/clarify/<RUN_ID>/clarify-packet.md` to `sample-mobile-app-requirements.md`." Claude reads the filled packet, applies entries with `My choice` filled, defers entries left blank, reports the result.

- **Quick-apply alternative (inline, no file editing)**: skip the file edits and pass picks in chat: "Apply my /clarify decisions from `tmp/clarify/<RUN_ID>/clarify-packet.md` to `sample-mobile-app-requirements.md`: 1=A, 2=B, 3=defer, 4=A, 5=A, 6=B." Claude does the same thing as the file-based path.

- **Stop-and-resume scenario**: run `/clarify`, then close Claude. In a new Claude session days later, navigate to the run folder, read the packet, fill in `My choice` / `Further comments` directly in the packet, and ask the new Claude to apply. The packet's `## Next steps for the user` section is sufficient to do all of this without the original chat history.

- **Ask a follow-up question before deciding**: after the packet appears, but before recording any decision, ask Claude in chat — "For question 3 (backend), can you tell me more about how the offline-edit scenario from the requirements would actually work under each option?" — OR write the question in the entry's `Further comments` block, save the packet, and Claude will answer when next invoked. Claude reads the relevant entry + the artifact and answers; the packet's analysis zone stays unchanged either way.

- **Drive the iteration cycle to convergence**: fill in decisions for all entries (or a subset; deferred entries re-surface next run), ask Claude to apply, then re-run `/clarify` against the (now-updated) `sample-mobile-app-requirements.md`. The next packet should have fewer entries because most ambiguities have been resolved. Iterate until `/clarify` returns `Total entries: 0` ("artifact's intent appears settled"). The chat reply for that final run will explicitly recommend `/cross-ai-review` as the next step. Convergence in 1–3 cycles is typical for an artifact this size.

- **Try a different analyst's perspective** (optional, after the default-analyst run): once Claude (default) has surfaced its packet (and you've decided + applied + re-run to 0), re-invoke with `/clarify --analyst codex sample-mobile-app-requirements.md` for Codex's view, then `/clarify --analyst gemini sample-mobile-app-requirements.md` for Gemini's. Each analyst surfaces different ambiguities — Codex may flag things Claude missed, and vice versa. If multiple analysts each return `Total entries: 0`, the artifact is reasonably clarified from those configured perspectives. The user remains the decision authority; this is a confidence signal, not a guarantee of completeness. Substitution, not addition: each run has one analyst.

- **Empty-packet path (settled artifact)**: copy `sample-mobile-app-requirements.md` to a separate file and **fill in all 15 decisions yourself** before running `/clarify`. Then run `/clarify <your-pre-filled-file>`. The expected outcome is a packet with **`Total entries: 0`** and a chat reply pointing at `/cross-ai-review`. Useful for verifying the empty-packet path works on your install (Step 9d of INSTALL focuses on the under-specified path; this variation tests the converged-out path).

- **Run /cross-ai-review on the post-decision artifact**: after the requirements doc has absorbed the user's decisions, run `/cross-ai-review sample-mobile-app-requirements.md`. The cycle should now find few or no `kind=ambiguity` findings — it found the original ambiguities resolved into intent. This is the natural handoff between the two commands.

- **Verify the halt-on-missing-analyst behavior**: invoke `/clarify --analyst codex sample-mobile-app-requirements.md` while Codex is uninstalled or unauthed. The expected outcome is a HALT — `/clarify` should refuse to produce a packet, instead writing halt artifacts to the run folder and reporting the halt in the chat reply. It must NOT silently fall back to claude (which would change the packet character without user consent — substitutive design + no autonomous decision-making). Restore Codex auth afterward to verify the success path.

## Cleanup

The run folder (`tmp/clarify/<RUN_ID>/`) can be deleted after you've reviewed it. To delete just one run:

```sh
rm -rf tmp/clarify/<RUN_ID>/
```

To delete all /clarify runs in this directory:

```sh
rm -rf tmp/clarify/
```

Or leave it — like `/cross-ai-review`'s run dirs, it's a useful reference for what the output looks like in a real run.
