# Smoke tests

This directory contains install-verification fixtures for the pack's two slash commands. Each subdirectory has its own deliberately-imperfect artifact + a `README.md` describing how to run that command's smoke test and what "passing" looks like.

| Subdirectory | Smoke test for | What it verifies |
|---|---|---|
| `cross-ai-review/` | `/cross-ai-review` (governed verification cycle) | The cycle completes end-to-end; iterating reviewer surfaces ≥4 known flaws; the `tmp/cross-ai-review/<RUN_ID>/` audit trail is well-formed; `[config]` line resolves correctly. |
| `clarify/` | `/clarify` (intent-formation companion) | The decision-packet workflow produces a well-formed packet; analyst surfaces ≥10 entries against a deliberately-under-specified fixture; `tmp/clarify/<RUN_ID>/clarify-packet.md` includes both host-analysis and user-fill-in zones; no autonomous edits to the artifact. |

Run either smoke test independently after install. INSTALL.md Step 9 walks through both:

- **Step 9c** (required): `/cross-ai-review` smoke test against `cross-ai-review/sample-artifact.md`
- **Step 9d** (optional): `/clarify` smoke test against `clarify/sample-mobile-app-requirements.md`

Each subdirectory's README has command-specific details, expected outputs, pass/warn/fail thresholds, and variations to try.
