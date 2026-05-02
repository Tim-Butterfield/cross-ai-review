# Cross-AI Review helper scripts

These wrapper scripts handle the actual reviewer-CLI invocation per the cross-ai-review cycle. They exist to:

1. **Reduce permission-prompt friction** — without wrappers, every reviewer call surfaces to Claude Code as a wall-of-text Bash command (the entire reviewer prompt embedded as a single argument). With wrappers, the call is short and parameterized. The runtime permission prompt offers an "always allow" pattern scoped to the helper's path; user accepts at the prompt and the entry is written to `~/.claude/settings.local.json`. **The install does NOT pre-populate any allowlist** — granting must be the user's action at the prompt.

2. **Centralize the non-negotiable invocation flags** — the wrappers always pass the read-only sandboxing flags (`-s read-only` for Codex, `--approval-mode plan` for Gemini), the stdin-handling fix for Codex (`< /dev/null` to prevent the stdin-hang bug), and `--skip-git-repo-check` for Codex in non-git directories.

3. **Translate abstract thinking levels to provider-native values** — the methodology specifies thinking effort as `fast | standard | deep`. Each helper translates internally to its provider's native form. Codex: fast=low, standard=medium, deep=high (passed via `-c model_reasoning_effort`). Gemini: fast=2048, standard=8192, deep=24576 (passed as thinking-budget tokens, when the installed CLI version exposes the flag; otherwise recorded as `native=unsupported`).

4. **Implement the halt-signal classification** — wrappers parse stderr per the halt-signal taxonomy (Class A through G) and return a structured exit code so the calling host can branch.

5. **Enforce the Class E (silent fallback) check** — wrappers extract the actual responding model identifier from CLI output and compare to the requested model. Both **mismatch** and **extraction failure** halt as Class E unconditionally — there is no override flag in v1.

6. **Parse the Gemini envelope** — Gemini's `--output-format json` returns a wrapper object `{response, stats, error}`; the gemini wrapper extracts `.response`, strips markdown code fences, and validates against the reviewer schema.

## Files

| Platform | Codex helper | Gemini helper |
|---|---|---|
| macOS / Linux / WSL / Git Bash | `codex-call.sh` | `gemini-call.sh` |
| Windows native PowerShell | `codex-call.ps1` | `gemini-call.ps1` |

INSTALL.md detects the platform and copies only the matching pair to `~/.claude/cross-ai-review-helpers/`. Both shell forms implement the same interface and produce the same output shape, so the slash command's invocation logic doesn't depend on which form is installed.

## Interface

All helpers take the same arguments (with platform-appropriate flag style):

| Argument | Required | Description |
|---|---|---|
| `--layer <int>` / `-Layer <int>` | yes | Layer index (recorded in per-call `.md` header) |
| `--primitive <P1..P6>` / `-Primitive <P1..P6>` | yes | Which review primitive this call serves |
| `--phase <name>` / `-Phase <name>` | yes | One of `semantic-iterate`, `semantic-cross-check`, `semantic-verify` |
| `--outer <int>` / `-Outer <int>` | yes | Outer cycle index (1, 2, 3) |
| `--iter <int>` / `-Iter <int>` | only for `--role iterating` | Inner iteration index (1, 2, 3, 4) |
| `--role <name>` / `-Role <name>` | yes | One of `iterating`, `cross-check`, `verify` |
| `--model <slug>` / `-Model <slug>` | yes | Requested model slug (e.g., `gpt-5.5`, `gemini-3.1-pro-preview`) |
| `--thinking-level <level>` / `-ThinkingLevel <level>` | yes | Abstract level: `fast`, `standard`, or `deep` |
| `--prompt-file <path>` / `-PromptFile <path>` | yes | File containing the reviewer prompt |
| `--stdin-file <path>` / `-StdinFile <path>` | Gemini only, optional | File to pipe via stdin (artifact content) |
| `--schema <path>` / `-Schema <path>` | Codex only, optional | JSON schema file (default `~/.claude/cross-ai-review-schema.json`) |
| `--run-dir <path>` / `-RunDir <path>` | yes | Run directory for output |
| `--call-started <ts>` / `-CallStarted <ts>` | yes | Timestamp prefix for output filenames (e.g., `20260430T223050`) |

**Mechanical phases (`mechanical-pre`, `mechanical-post`) are NOT invoked through these helpers** — they are run by the host directly (running declared validation hooks, scanning IDs, etc.). These helpers are for semantic phases only.

## Output

Each helper writes (paths relative to `--run-dir`):
- `.tmp-<call-started>-out.json` — raw CLI output (Codex: schema-enforced reviewer JSON; Gemini: envelope `{response, stats, error}`)
- `.tmp-<call-started>-err` — full stderr capture
- For Gemini only: `.tmp-<call-started>-reviewer.json` — extracted and parsed reviewer JSON (envelope's `.response` after fence-stripping)

To stdout, each helper prints a single JSON status object:
```json
{
  "exit_code": 0,
  "output_file": "<path>",
  "reviewer_file": "<path>",  // Gemini only
  "stderr_file": "<path>",
  "model_actual": "<slug | 'extraction-failed'>",
  "native_thinking": "<provider-specific native value, e.g. 'codex model_reasoning_effort=medium' or 'gemini thinking_budget_tokens=8192' or 'unsupported'>",
  "halt_class": null  // or "A" / "B" / "C" / "D" / "E" / "F" / "G"
}
```

The host writes both abstract and native thinking values into the per-call `.md` audit header per methodology § Audit header format:

```
**Thinking level**: standard (native: codex model_reasoning_effort=medium)
```

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success — output produced, schema-valid, model_actual verified |
| 1 | Class A halt — auth/permission |
| 2 | Class B halt — account quota exhausted |
| 3 | Class C halt — server-side capacity (fallback chain exhausted at the call level) |
| 4 | Class D halt — model not on account |
| 5 | Class E halt — silent fallback OR extraction failure (no override in v1) |
| 6 | Class F halt — suspected transient bug (after retry) |
| 7 | Class G halt — unclassified |
| 8 | Invalid arguments |

The calling host branches on exit code per the halt taxonomy in the methodology.

## Why two shell forms (.sh and .ps1)?

Native bash isn't available on Windows without WSL or Git Bash. Native PowerShell isn't available on macOS/Linux without `pwsh`. Each platform's shell handles process management, stdin redirection, and JSON parsing differently. Two scripts (one per shell) is simpler than one script trying to be polyglot, and INSTALL.md only installs the matching pair so users don't see the irrelevant form.

## Updating helpers

If the helper logic changes (e.g., a new halt class, a CLI version with different stderr patterns, an updated thinking-budget mapping), update **both** `.sh` and `.ps1` together. Drift between them is a real risk; in any future cross-AI review of the pack, the helpers should be in their own layer with `.sh` and `.ps1` declared as within-layer peer-compatibility constraints.

## Why no helper-edit escape hatch

Earlier methodology drafts considered allowing users to edit helpers directly to override native values (e.g., set a custom Codex reasoning effort outside the abstract `fast/standard/deep` mapping). This is **explicitly forbidden in v1**: configuration must remain schema-governed and auditable. Local helper edits would bypass the audit trail and break reproducibility. If native overrides become genuinely needed, they will be added as a v2 schema extension with full audit support — not as a local-edit escape.
