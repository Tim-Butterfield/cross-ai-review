# INSTALL — Cross-AI Review starter pack

You (Claude Code) are installing this pack on the user's system. Follow these steps in order. Adapt every shell command to the user's platform — bash/zsh on macOS/Linux, PowerShell or WSL bash on Windows. State briefly what you are about to do before running each command, and pause if anything looks unexpected.

If a step fails, **stop and report** rather than guessing. "Report" means: tell the user what command failed, what you expected versus what you got, and what they should do (install a missing prerequisite, fix permissions, re-authenticate, etc.). Then wait for the user to respond before continuing.

## Step 0a — Locate the starter pack

You need to know where this starter pack lives on the user's filesystem (the directory containing this `INSTALL.md` file). If you don't already know it from how the user invoked you, ask them: **"Where did you unzip / clone the cross-ai-review directory? I need the absolute path."** Wait for the answer. Use that path everywhere this guide says `<path-to-starter-pack>`.

---

## Step 0 — Identify the platform and shell

Run a platform check and tell the user what you detect. Examples:
- macOS: `uname -s` returns `Darwin`
- Linux: `uname -s` returns `Linux`
- Windows: `$PSVersionTable.PSVersion` (PowerShell) or `uname -s` returns `MINGW*` / `MSYS*` (Git Bash) / `Linux` (WSL)

Note the shell — bash, zsh, PowerShell, cmd. All commands below use POSIX shell syntax; translate to PowerShell where needed (e.g., `mkdir -p` → `New-Item -ItemType Directory -Force`, `>>` for append works in PowerShell, `cat` becomes `Get-Content`).

---

## Step 1 — Detect available AI providers

The pack supports two AI provider CLIs (Codex and Gemini). **At least one must be installed for the install to proceed; auth is verified eagerly for Codex (`codex login status`) and lazily for Gemini (the first `gemini -p` call in the smoke test).** Using both providers is recommended (true cross-AI review needs two reviewers); one works in degraded single-reviewer mode (still gets the structured iteration loop, validity judgment, and audit trail — just without the cross-vendor second opinion). Step 9 (smoke test) is where any deferred auth issue surfaces concretely as a Class A halt.

Tell the user you're going to check what's installed and proceed based on what you find — you will NOT require them to install both.

Track availability of each provider as you check. You'll use this in Step 5 to write the config and to decide whether to ask the user about role preference.

### 1a. Codex CLI (optional but recommended)

```sh
codex --version
codex login status
```

- Expect a version string (e.g., `codex-cli 0.125.0` or similar) and a logged-in account → mark Codex as **available**.
- If `codex --version` fails: Codex is not installed. Tell the user that's fine — the cycle will work without it as long as Gemini is available — and offer the install link (`npm install -g @openai/codex` or https://github.com/openai/codex) for if they want it later. Mark Codex **not available**.
- If `codex --version` succeeds but `codex login status` shows not-logged-in: tell the user to run `codex login` and authenticate against their account. Mark Codex **not available** until they auth (they can re-run install later, or the slash command will detect the auth at next invocation).

If Codex is available, also confirm the recommended model interface:
```sh
codex exec --help | head -20
```
Verify the help text mentions `-m, --model`. If not, the version may be too old; ask the user to update.

### 1b. Gemini CLI (optional but recommended)

```sh
gemini --version
```
- If a version string is returned → mark Gemini as **available** (auth check is deferred — Gemini typically prompts for auth on first interactive use, and the slash command's halt taxonomy classifies any auth failure cleanly).
- If `gemini --version` fails: Gemini is not installed. Tell the user that's fine — the cycle will work without it as long as Codex is available — and offer the install link (`npm install -g @google/gemini-cli` or https://github.com/google-gemini/gemini-cli) for if they want it later. Mark Gemini **not available**.

For auth confirmation, run:
```sh
gemini --help | head -5
```
If the user has not yet authenticated, the first `gemini -p "test"` call will prompt them. You can defer this to the smoke test (Step 9) — if the smoke test reports an auth-required error, walk the user through `gemini` interactive auth.

### 1c. Verify at least one provider is available

If **neither** Codex nor Gemini is available, stop and tell the user they must install and auth at least one before continuing. The cycle cannot run with zero providers.

### 1d. Optional utilities

```sh
jq --version
rg --version
```
Both are recommended but not strictly required. If missing, suggest install paths but proceed.

### 1e. Claude config directory

The Claude Code config directory is at `~/.claude/` (bash/zsh tilde expansion) or `$HOME/.claude/` (more portable). On Windows, this resolves to `C:\Users\<username>\.claude\`.

Tilde expansion works in bash, zsh, and modern PowerShell, but NOT in cmd. If the user is on cmd, prefer the explicit `$env:USERPROFILE\.claude\` (PowerShell) or `%USERPROFILE%\.claude\` (cmd). For bash/zsh on macOS/Linux, `~/.claude/` works fine.

Verify it exists and is writable:

```sh
test -d ~/.claude && test -w ~/.claude && echo "ok" || echo "missing or not writable"
```

If missing, create it (with the `commands/` subdirectory you'll need in Step 3):
```sh
mkdir -p ~/.claude/commands
```

If `~/.claude/` exists but isn't writable, stop and ask the user to fix permissions before continuing.

---

## Step 2 — Backup before changes

Make a timestamped backup of any files you might overwrite. Use a portable timestamp format (`YYYYMMDDTHHMMSS`).

```sh
TS=$(date +%Y%m%dT%H%M%S)
[ -f ~/.claude/CLAUDE.md ] && cp ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md.backup-$TS
[ -f ~/.claude/cross-ai-review-methodology.md ] && cp ~/.claude/cross-ai-review-methodology.md ~/.claude/cross-ai-review-methodology.md.backup-$TS
[ -f ~/.claude/commands/cross-ai-review.md ] && cp ~/.claude/commands/cross-ai-review.md ~/.claude/commands/cross-ai-review.md.backup-$TS
[ -f ~/.claude/commands/clarify.md ] && cp ~/.claude/commands/clarify.md ~/.claude/commands/clarify.md.backup-$TS
[ -f ~/.claude/cross-ai-review-config.json ] && cp ~/.claude/cross-ai-review-config.json ~/.claude/cross-ai-review-config.json.backup-$TS
[ -f ~/.claude/cross-ai-review-schema.json ] && cp ~/.claude/cross-ai-review-schema.json ~/.claude/cross-ai-review-schema.json.backup-$TS
```

Tell the user where the backups are. They can restore by `mv backup-file original-file`.

---

## Step 3 — Install the slash commands

The pack ships **two slash commands**: `/cross-ai-review` (the governed-verification cycle) and `/clarify` (the intent-formation companion that surfaces ambiguities for the user to decide). Install both — they share the same provider config and reviewer helpers, so installing one without the other leaves a coherent gap.

### Step 3a — Install `/cross-ai-review`

Copy `cross-ai-review.md` from the starter pack into `~/.claude/commands/`. Use the absolute path from Step 0a:

```sh
cp <path-to-starter-pack>/cross-ai-review.md ~/.claude/commands/cross-ai-review.md
```

Verify:
```sh
ls -la ~/.claude/commands/cross-ai-review.md
head -5 ~/.claude/commands/cross-ai-review.md
```

The file should start with `---` (YAML frontmatter) and contain a `description:` line on line 2.

### Step 3b — Install `/clarify`

Copy `clarify.md` from the starter pack into `~/.claude/commands/`:

```sh
cp <path-to-starter-pack>/clarify.md ~/.claude/commands/clarify.md
```

Verify:
```sh
ls -la ~/.claude/commands/clarify.md
head -5 ~/.claude/commands/clarify.md
```

Same shape as Step 3a — `---` frontmatter + `description:` line.

`/clarify` reuses `~/.claude/cross-ai-review-config.json` (Step 6 below) and the helper scripts at `~/.claude/cross-ai-review-helpers/` (Step 7) when the analyst is codex or gemini (per `--analyst` flag; default analyst is claude/host, which uses neither). There is no separate config or helper directory for `/clarify`.

**Important**: Claude Code loads slash commands at session start. The newly-installed commands WILL NOT be recognized in the current Claude session — the user will need to **start a new Claude Code session** before they can run `/cross-ai-review` or `/clarify`. You'll handle this in Step 9 (smoke test).

---

## Step 4 — Install the CLAUDE.md stub and the methodology file

The cross-AI review setup splits across two files:

- **`~/.claude/CLAUDE.md`** gets a thin stub (~2.9k chars): when-to-offer trigger, read-only + output-modes summary, pointer to the methodology. This is what's auto-loaded into every Claude session.
- **`~/.claude/cross-ai-review-methodology.md`** is the canonical methodology (~145k chars, v1): halt taxonomy, configuration semantics, layered review pattern, iteration cycle, six review primitives (P1-P6), pipeline structure (mechanical-pre → semantic → mechanical-post), output modes (apply / report), thinking levels, audit formats, per-CLI recipes. It is NOT auto-loaded — the slash command reads it as Step 0 of every invocation.

This split exists so the always-loaded CLAUDE.md stays well under Claude Code's large-file warning threshold.

### Step 4a — Install or merge the CLAUDE.md stub

The cross-AI review stub goes into `~/.claude/CLAUDE.md`. Three cases:

#### Case A: User has no `~/.claude/CLAUDE.md`

Copy the stub as-is to become the file:

```sh
cp <path-to-starter-pack>/cross-ai-review-claude-section.md ~/.claude/CLAUDE.md
```

#### Case B: User has a `~/.claude/CLAUDE.md` without a `# Cross-AI review` heading

Append the stub. Add a blank line separator first:

```sh
printf "\n\n" >> ~/.claude/CLAUDE.md
cat <path-to-starter-pack>/cross-ai-review-claude-section.md >> ~/.claude/CLAUDE.md
```

#### Case C: User has a `~/.claude/CLAUDE.md` that already contains a `# Cross-AI review` section

Detect this case with a case-insensitive search:
```sh
grep -in "^# cross-ai review" ~/.claude/CLAUDE.md
```

If matches are found, **stop and ask the user.** They may have a customized version, OR (very likely if they installed this pack before the methodology-extraction split) they have the previous monolithic version that's now ~130k chars and warrants migration to the slim stub. Show them where their existing section starts and ask whether to:
- (a) leave their existing section alone (skip this step — but if their existing section is the pre-split monolithic version, they will NOT benefit from the smaller CLAUDE.md until they replace)
- (b) replace it with the starter-pack stub (back up and replace the matching section — this is the recommended action for users upgrading from the pre-split version)
- (c) append the starter-pack stub anyway (results in duplicate sections — usually not what they want)

Default to (a) unless the user picks (b) or (c) explicitly. If the user's existing section is byte-identical or near-identical to the prior monolithic `cross-ai-review-claude-section.md` (a `wc -c` of >40k chars on just the section is a strong indicator), recommend (b) explicitly to capture the size benefit.

#### Verify

After install, confirm the stub is in place:
```sh
grep -ic "^# cross-ai review" ~/.claude/CLAUDE.md
```
Should report at least 1.

### Step 4b — Install the methodology file

The methodology file is wholly owned by the starter pack — no merge logic needed. If a previous methodology file exists, the Step 2 backup already captured it; overwrite is safe.

```sh
cp <path-to-starter-pack>/cross-ai-review-methodology.md ~/.claude/cross-ai-review-methodology.md
```

(If the user is on a system where Step 2 didn't back this file up because it didn't exist yet, that's fine — first install.)

#### Verify

```sh
test -r ~/.claude/cross-ai-review-methodology.md && head -1 ~/.claude/cross-ai-review-methodology.md
```

Should print: `# Cross-AI review — methodology`

Also, the slash command's Step 0 will fail loudly if this file is missing, so the smoke test in Step 9 is the final functional check.

---

## Step 5 — Initialize the schema file

The cross-AI review cycle expects a JSON schema at `~/.claude/cross-ai-review-schema.json`. The schema content is in `cross-ai-review-methodology.md` under the `## Findings schema` heading, but you don't need to extract from there — it's reproduced verbatim below. Write it:

```sh
cat > ~/.claude/cross-ai-review-schema.json <<'SCHEMA'
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
SCHEMA
```

Verify with `jq` if available:
```sh
jq . ~/.claude/cross-ai-review-schema.json > /dev/null && echo "schema valid"
```

---

## Step 6 — Write the provider config

The provider config (`~/.claude/cross-ai-review-config.json`) tells the slash command which AI providers to use, which models to prefer for each, and which provider fills the iterating-reviewer role (mandatory) versus the cross-check-reviewer role (optional). This file is the user's source of truth for these choices — they edit it later when models or preferences change, no reinstall required.

### 6a. Decide role preference

If only one provider was marked **available** in Step 1, role assignment is trivial: that provider is the iterating reviewer, no cross-check reviewer, cycle runs in single-reviewer mode. Skip to 6b.

If both providers were marked available, ask the user:

> **"Which provider would you like as the iterating reviewer (the one that hammers on the artifact across multiple iterations)? Codex (default — its `--output-schema` enforces JSON shape, making set-based stability detection more reliable) or Gemini (works, but the iterating loop has weaker output-shape enforcement, so parsing is slightly more fragile)?"**

Default to Codex if the user has no preference. Whatever they pick, the other becomes the cross-check reviewer. Record the decision.

### 6b. Write the config

Use the recommended model chains as defaults with abstract `thinking_level: "standard"` (the methodology's recommended default for semantic primitives — projects can override per primitive in their project extension). Write to `~/.claude/cross-ai-review-config.json`:

```sh
cat > ~/.claude/cross-ai-review-config.json <<'CONFIG'
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
CONFIG
```

The `thinking_level` field is the abstract level (`fast | standard | deep`) that helpers translate to provider-native form internally. See `cross-ai-review-methodology.md` § Thinking levels for the full semantics.

The `layer_aggregate_cap` is optional — it bounds total reviewer calls per layer regardless of per-primitive caps. Default `null` means per-primitive caps apply only.

There is no `allow_unverified_actual_model` field in v1 — the cycle halts unconditionally on Class E (silent fallback) and on actual-model extraction failure, with no override.

If the user chose **Gemini as iterating reviewer**, swap `role_preference` to `["gemini", "codex"]` before writing:

```sh
# (only if user picked Gemini as iterating reviewer)
# edit role_preference line: "role_preference": ["gemini", "codex"]
```

You may write provider blocks for providers that aren't currently installed — the slash command auto-detects availability at runtime via `which <cli>`, so an unused block is harmless. Leaving both blocks in is recommended even when only one CLI is installed today, so the user can install the second later without editing config.

### 6c. Verify

```sh
jq . ~/.claude/cross-ai-review-config.json > /dev/null && echo "config valid"
jq -r '.role_preference | join(" -> ")' ~/.claude/cross-ai-review-config.json
```

Tell the user the path (`~/.claude/cross-ai-review-config.json`) and what they'd edit later for common changes:
- **New model arrives** (e.g., `gpt-5.6`, `gemini-4.0-pro`): prepend it to the relevant `providers.<name>.models` list.
- **Swap iterating / cross-check assignment**: swap the order of `role_preference`.
- **Drop a provider permanently**: delete its block (or just uninstall the CLI).
- **Add a provider later**: install/auth its CLI; add a block here if it isn't already; ensure it appears in `role_preference` if you want it used.

Edits take effect on the next `/cross-ai-review` invocation — no Claude restart, no reinstall.

---

## Step 7 — Install reviewer helper scripts

Reviewer calls (Codex, Gemini) are invoked through small wrapper scripts that handle the non-negotiable invocation flags, output capture, halt classification, and Class E (silent fallback) actual-model verification. The wrappers exist in two forms — `.sh` (bash) for Unix-like systems and `.ps1` (PowerShell) for Windows — and the install copies the platform-appropriate pair.

Without wrapper scripts, every reviewer call would surface to Claude Code as a wall-of-text Bash command (the entire reviewer prompt embedded as a single argument) requiring manual approval. With the wrappers, the bash command Claude assembles to invoke a helper is short and prefix-allowlistable: on the first invocation per Claude Code session you see a permission prompt, and "always allow" at that prompt grants the helper for the rest of the session.

**The install does NOT pre-populate `~/.claude/settings.json` with allowlist patterns.** The runtime permission prompt is the intended consent moment. Granting must be the user's action at the prompt, not a silent install-time decision. The slash command's Hard rule #4 mirrors this on its side — every helper invocation is constructed with literal parameter values (no shell variable expansion) so that "always allow" is offered at the prompt.

### 7a. Detect platform

Use the platform identification from Step 0. The install proceeds with `.sh` helpers on macOS/Linux/WSL/Git-Bash, and `.ps1` helpers on native Windows PowerShell. (If the user is on cmd, suggest they switch to PowerShell or install Git Bash before continuing — the helpers do not have a `.cmd` form.)

### 7b. Copy the matching helper pair

Create the helpers directory and copy only the platform-appropriate scripts:

```sh
# macOS / Linux / WSL / Git Bash:
mkdir -p ~/.claude/cross-ai-review-helpers
cp <path-to-starter-pack>/helpers/codex-call.sh ~/.claude/cross-ai-review-helpers/
cp <path-to-starter-pack>/helpers/gemini-call.sh ~/.claude/cross-ai-review-helpers/
chmod +x ~/.claude/cross-ai-review-helpers/*.sh
```

```powershell
# Windows native PowerShell:
$dest = "$env:USERPROFILE\.claude\cross-ai-review-helpers"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item "<path-to-starter-pack>\helpers\codex-call.ps1" $dest
Copy-Item "<path-to-starter-pack>\helpers\gemini-call.ps1" $dest
```

Verify the files exist and (on Unix) are executable.

### 7c. Brief the user on the runtime permission prompt

Tell the user:

- The first time Claude Code invokes `codex-call.sh` (or `.ps1`) in a session, a permission prompt appears naming the script and its arguments.
- **"Always allow"** at that prompt is the recommended response — it grants the helper a session-long allowlist entry that survives across calls. (Claude Code writes the entry to `~/.claude/settings.local.json` or, if scoped wider, `~/.claude/settings.json` — driven by the user's choice at the prompt.)
- Allowing is safe because the helper itself enforces read-only sandboxing on the reviewer CLI (`-s read-only` for Codex, `--approval-mode plan` for Gemini), so even with the helper allowlisted the reviewer cannot modify your artifacts.
- Same prompt and same response apply to `gemini-call.sh` (or `.ps1`) on its first invocation.
- **The allowlist is shared across slash commands.** Both `/cross-ai-review` and `/clarify` (with `--analyst codex` or `--analyst gemini`) invoke the same helper paths — so granting `~/.claude/cross-ai-review-helpers/codex-call.sh *` once via "always allow" covers BOTH commands. Users do not need to re-allow per command. If a re-prompt happens on a second command, the original grant was likely "allow once" rather than "always allow", or scoped to specific args rather than the helper-path-prefix pattern.
- "Just once" / "deny" remain available if the user wants per-call confirmation or wants to abort.

The slash command (Hard rule #4) constructs every helper invocation with literal parameter values so the prompt always exposes the "always allow" option. If you ever see a prompt that lacks "always allow" because the command "contains expansion," that's a slash-command bug — surface it rather than working around it.

Similarly (Hard rule #5), the slash command invokes each helper **directly** — the first token of the bash command is the helper's own path (e.g., `~/.claude/cross-ai-review-helpers/codex-call.sh ...`), NOT a wrapping interpreter. If you ever see a permission prompt offering an "always allow" pattern that starts with `bash`, `sh`, `pwsh`, `python`, or any other general-purpose interpreter (rather than the helper script's own path), that's also a slash-command bug — refuse the overbroad pattern and surface it. Allow-listing `bash *` (or any interpreter wildcard) would grant the right to run any command through that interpreter for the rest of the session, which is far broader than the helper-only grant the user intended.

---

## Step 8 — (Optional) Wire up project-specific rigor

This is opt-in. Ask the user: **"Do you want to enable project-specific review criteria for any project right now? You can always add this later."**

If yes:
1. Ask which project's directory to set up
2. Open `<path-to-starter-pack>/project-extension-template.md`
3. Walk the user through filling in the placeholders (criteria docs they want reviewers to load, severity rules, authority documents, etc.). The template includes an optional **Provider override** subsection if this project needs different providers/models/role preference than the global config.
4. Write the customized section to that project's `CLAUDE.md`. If the project has no `CLAUDE.md`, create one.
5. Confirm the section is appended (search for `## Cross-AI Review Extension`)

If no: skip this step and tell the user they can run this anytime by re-reading the template and adding it manually.

Without a project extension, the cycle still works — it just uses generic rigor (the global severity baseline). Project extensions sharpen the rules for specific kinds of artifacts.

---

## Step 9 — Smoke test

Run the cross-AI review against the smoke-test artifact to confirm everything works end-to-end. The test artifact has deliberate flaws the configured iterating reviewer should catch.

### 9a. Start a fresh Claude Code session

The slash command was installed in Step 3, but the current Claude Code session loaded its commands at startup and won't see the new one. **Tell the user to exit this Claude Code session and start a new one in the smoke-test directory:**

```sh
cd <path-to-starter-pack>/smoke-test/cross-ai-review
# user exits this Claude session, then starts a fresh one in this directory
```

When the user is in a fresh session, ask them to point you back at this `INSTALL.md` (or just continue from Step 9b directly). The smoke test runs in the new session.

### 9b. Invoke the slash command

In the fresh Claude Code session, run:

```
/cross-ai-review sample-artifact.md
```

Claude (you, in the new session) will execute the cycle per the instructions in the slash command and the methodology file (which the slash command's Step 0 loads). The first lines it should print are a `[config]` line naming the loaded config path, the resolved host + iterating + cross-check role assignments, the resolved scope (`scope=single-artifact` for this test), and `output_mode=apply` (default). Both confirm setup loaded correctly.

### 9c. Verify expected behavior

The smoke test artifact has 9 deliberate flaws (vague language, placeholders, contradictions, duplicates, vague performance targets, vague verification, missing definitions, weak DoD, ambiguous error handling — see `smoke-test/cross-ai-review/README.md` for the full list).

After the first iterating-reviewer iteration, you should see:
- A `tmp/cross-ai-review/<RUN_ID>/` directory created in the smoke-test directory
- A consolidated per-call markdown file matching the unified grammar `<call-started>-<cli>-iter-P1-1-1.md` (e.g., `20260501T220000-codex-iter-P1-1-1.md` if Codex is iterating). The file contains everything for that call: header metadata (Layer + Primitive=P1 + Phase=semantic-iterate + Role=iterating + Output mode=apply + Mode + Thinking level), reviewer's verdict and findings, host's per-finding decisions, the addressed context that was sent (N/A on the first call), the halt event (None), and the raw stderr capture.
- **At least 4 findings** (ideally 5-9) in the file's `## Findings` section, mostly `kind=ambiguity`, `kind=gap`, or `kind=fail`
- A verdict of `request_changes` or `block` (NOT `approve`) in the snapshot block at the top of the file

If the iterating reviewer returns fewer than 4 findings or returns `approve`, that's a soft signal something is off — investigate. Likely causes: a too-low `thinking_level` causing the model to skim, a prior smoke-test run having pre-fixed parts of the artifact (re-copy from the starter pack to reset), or an unusually-cached prompt. It is NOT a sign of silent model fallback — silent fallback halts unconditionally as Class E per the methodology, surfacing as a Class E halt event in `tmp/cross-ai-review/<RUN_ID>/halt-classification.md` rather than a quiet finding-count drop. (The smoke test is also affected by account quota, which surfaces as Class B halt — distinct from a low-count finding.)

If you see this: **install confirmed working**. The cycle may continue past N=1 — that's fine; the smoke test only needs the first iteration to validate.

If the first iterating-reviewer call fails:
- Classify the error per the halt-signal taxonomy in `cross-ai-review-methodology.md`
- Class A or D (auth/model) → install/auth issue, fix and retry
- Class B (account quota exhausted) → user is past their account's quota for that provider; smoke test will need to wait for the quota window to reset
- Class C (server-side capacity) → wait 10-30 min and retry once
- Class E (silent model fallback OR extraction failure) → install issue or CLI version mismatch; investigate. The CLI may not expose model identifiers; if so, consider a different reviewer CLI for that role.
- M-class halts (mechanical) shouldn't appear in the smoke test (no P5 hooks declared); if seen, investigate hook configuration

Stop the smoke test after the first iterating-reviewer call succeeds — no need to run a full cycle for install verification.

### 9d. (Optional) `/clarify` smoke test

`/clarify` has its own smoke-test fixture at `<path-to-starter-pack>/smoke-test/clarify/sample-mobile-app-requirements.md` — a deliberately under-specified mobile-app spec.

The `/cross-ai-review` smoke test in 9b started a fresh Claude Code session in `<path-to-starter-pack>/smoke-test/cross-ai-review/`. For the `/clarify` smoke test, change directory into the `/clarify` smoke-test subfolder so the run dir lands cleanly under it (parallel to the `/cross-ai-review` smoke-test layout):

```sh
cd <path-to-starter-pack>/smoke-test/clarify
```
```
/clarify sample-mobile-app-requirements.md
```

If the user prefers to stay in their current cwd from Step 9b (`<path-to-starter-pack>/smoke-test/cross-ai-review/`), they can invoke with a relative path: `/clarify ../clarify/sample-mobile-app-requirements.md`. From the pack root: `/clarify smoke-test/clarify/sample-mobile-app-requirements.md`. The `cd smoke-test/clarify` form is recommended — it keeps the `tmp/clarify/<RUN_ID>/` run dir under that subfolder.

You should see:

- A `[clarify]` line on the first line of output naming the artifact, host (`claude`), **resolved analyst** (`claude` for the default smoke test; `codex (model_slug)` or `gemini (model_slug)` if `--analyst` was used), and output path.
- A run folder at `tmp/clarify/<RUN_ID>/` (under the cwd the user invoked from) containing the decision packet at `tmp/clarify/<RUN_ID>/clarify-packet.md`. Each entry in the packet has a host-written analysis zone (question, choices with pros/cons inline, recommendation, reason, impact, suggested update) followed by a `#### Your decision (fill in below)` block with blank `My choice` and `Further comments` fields for the user to fill in. The packet doubles as the user's workspace — one file end-to-end. If the analyst was codex or gemini, the analyst's single per-call audit (`<call-started>-<cli>-iter-P1-1-1.md`) is also in the same folder.
- A short chat summary listing total entries and the top 3 most-consequential decisions.
- The artifact `sample-mobile-app-requirements.md` is **unchanged** (per `/clarify`'s read-only-by-default rule).

**Pass / warn / fail thresholds** (use these consistently):

- **Pass**: packet contains **≥ 10 entries** (the sample artifact has 15 deliberate ambiguities; `/clarify`'s 10-entry target floor encourages thoroughness, with no upper bound — a healthy run surfaces all genuine ambiguities). Entries have concrete options + recommendations + impacts; at least one entry is from a high-impact category (tech stack, auth, backend, performance metric, distribution).
- **Warn**: 6–9 entries — close to the floor but under it for an artifact this under-specified; investigate before declaring the install verified by 9d. Likely cause: a too-low `thinking_level` or the model stopping the impact-filter walk early. Try increasing `thinking_level` to `deep` and re-running.
- **Fail**: < 6 entries OR any recommendation reads as an autonomous decision rather than an advisory option the user can override. The model is skimming or misinterpreting the run — try `thinking_level: deep` and re-run.

**No graceful degradation for analyst halts.** Per `/clarify` Hard rule #3, if `--analyst codex` or `--analyst gemini` is selected and the chosen CLI is missing/unauthed/halts mid-run, `/clarify` HALTS the run with halt artifacts in the run dir; it does NOT silently fall back to claude or write a partial packet. The default-analyst smoke-test path (`/clarify sample-mobile-app-requirements.md`, no flag) uses claude (host) and does not trigger the halt path; the halt path applies only to user-selected non-claude analysts.

**The iteration cycle**: `/clarify` is designed to iterate. After this smoke-test run, you (or the user) can fill in decisions in the packet, ask Claude to apply them to `sample-mobile-app-requirements.md`, then re-run `/clarify` to see what new ambiguities surface (or get `Total entries: 0` if the artifact is now settled). For large packets, it's fine to decide a subset, apply, and come back for the rest — deferred entries re-surface in the next run with stable wording. Most artifacts converge in 1–3 cycles. Reaching `Total entries: 0` is the explicit "manual cycle complete" signal — the chat reply will recommend proceeding to `/cross-ai-review`.

**Optional — multi-analyst variation**: after Claude returns 0 entries, the user can OPTIONALLY re-run with `/clarify --analyst codex sample-mobile-app-requirements.md` (or `--analyst gemini`) for a fresh perspective from a different model. Each analyst surfaces different ambiguities; if both/all return 0, the artifact is reasonably clarified from the configured perspectives (the user remains the decision authority — this is a confidence signal, not a guarantee of completeness). Substitution, not addition: each `/clarify` run has one analyst. See `~/.claude/commands/clarify.md` § Analyst selection for full details.

The `/clarify` smoke test is **optional** — install of `/cross-ai-review` is verified by 9c above. Running 9d additionally confirms the second slash command loaded and that the host's `/clarify` workflow produces a well-formed packet (including the thoroughness expectation: aim for ≥ 10 entries when the artifact has them). Even when 9d is skipped, Step 10 should report the `/clarify` install status (file present at `~/.claude/commands/clarify.md`) explicitly.

---

## Step 10 — Final report to the user

Tell the user:

1. **Where files were installed**:
   - `~/.claude/commands/cross-ai-review.md` (slash command — governed verification)
   - `~/.claude/commands/clarify.md` (slash command — intent formation / decision support; companion to `/cross-ai-review`)
   - `~/.claude/CLAUDE.md` (cross-AI review stub — when-to-offer triggers for both commands, read-only summary, pointer)
   - `~/.claude/cross-ai-review-methodology.md` (canonical methodology for `/cross-ai-review` — loaded on demand by its Step 0; **do not delete or move this file**)
   - `~/.claude/cross-ai-review-schema.json` (findings schema for `/cross-ai-review`)
   - `~/.claude/cross-ai-review-config.json` (provider/model/role/thinking-level config — shared by both commands; **this is the file to edit when you want to change providers, models, role assignment, or thinking level**)

2. **Where backups are** (from Step 2): paths and timestamps

3. **Resolved provider configuration**: which CLI is the iterating reviewer, which is the cross-check reviewer (or "single-reviewer mode" if only one is available), and the model preference chain + resolved thinking level for each. Mention that the slash command auto-detects installed CLIs at runtime, so installing/uninstalling a CLI doesn't require a config edit.

4. **Whether the smoke tests passed**:
   - `/cross-ai-review` smoke test (9c): yes/no, and what the first iterating-reviewer call produced.
   - `/clarify` smoke test (9d): pass / warn / fail per the 9d thresholds, OR "skipped (file present at `~/.claude/commands/clarify.md`)" if 9d was not run. The user should know the second command is installed and loadable even if its smoke test wasn't exercised.

5. **What's next**: they can now run `/cross-ai-review <path-to-artifact>` in any project to verify a settled artifact, or `/clarify <path-to-artifact-or-description>` to surface ambiguities BEFORE the artifact is settled. For `/cross-ai-review` the argument can be a single file, multiple files, a git commit SHA, or `uncommitted`; for `/clarify` it is a file (or files) OR a free-form description — `/clarify` does NOT accept SHA / `uncommitted` (those imply the artifact has past intent formation, which is the `/cross-ai-review` case). If the project doesn't have `tmp/` gitignored, the run directory will still be created but won't be ignored — recommend adding `tmp/` to `.gitignore`. To run `/cross-ai-review` in **report mode** (single-pass; findings written to file; no edits applied), prepend `--report`: `/cross-ai-review --report <path-to-artifact>`. Useful for "tell me what's wrong; I'll decide what to fix" workflows or for artifacts you don't want Claude editing autonomously. (`/clarify` is always read-only-by-default — it never edits the artifact regardless of mode.)

6. **Reference**: `~/.claude/cross-ai-review-methodology.md` is the **methodology authority** — it documents the cycle's rules, halt taxonomy, validity rubric, severity baseline, layered review pattern (for multi-artifact reviews), audit artifact formats, configuration semantics, and per-CLI recipes. The slash command file (`~/.claude/commands/cross-ai-review.md`) is the **execution authority** — short procedural script that orchestrates the cycle by referencing methodology sections. The CLAUDE.md stub is just a trigger for when to *offer* a review and a pointer to the methodology. The README.md is the user-facing overview.

If the user has questions about specific cases (sustained Class C, project extension setup, fallback chains, swapping iterating/cross-check role assignment, thinking-level semantics, the `--report` mode, the six review primitives), refer them to `~/.claude/cross-ai-review-methodology.md` — it has the canonical reference.

---

## Troubleshooting

**Codex returns 401 / unauthorized**: re-run `codex login`.

**Gemini returns "Requested entity was not found" (404)**: the requested model isn't available on the user's plan. Check `gemini --help` for available models. The fallback chain documented in `cross-ai-review-methodology.md` handles this automatically when the cycle runs, but if it fails on the first model AND the second fails AND the third fails, the user's account may not have any of the recommended models.

**Gemini returns "exhausted your capacity"**: classify per the halt-signal taxonomy — usually Class C (Google service-side capacity, not your account's quota). Wait 10-30 minutes and retry. If sustained beyond 30 minutes (C2), suggest waiting until next day.

**Codex hangs or takes too long**: deep-thinking Codex calls can take 1-3 minutes. If a call exceeds 10 minutes, kill it and reduce thinking level — edit `~/.claude/cross-ai-review-config.json` to set `providers.codex.thinking_level` to `standard` or `fast`.

**Schema validation fails**: re-run Step 5; the heredoc may have been corrupted by the shell.

**Codex first call halts with HTTP 400 `invalid_json_schema` / `invalid_request_error`**: the installed schema at `~/.claude/cross-ai-review-schema.json` is from a pre-v1 install (where `primitive` and `source` were declared optional under `additionalProperties: false` — a shape OpenAI's Structured Outputs API rejects). Re-run Step 5 above to overwrite with the v1 schema (`primitive` and `source` are now required-but-nullable). Backup of the prior schema is in `~/.claude/cross-ai-review-schema.json.backup-<TS>` from Step 2.

**Codex first call halts as Class A from helper despite no schema/auth issue**: Class A also covers helper-arg validation failures (helper exit 8) where the host invoked the helper with missing or malformed arguments. This is a slash-command-implementation bug, not a user issue. Inspect the per-call `.md` for the failed call's `## Halt event` block — it will say `Class: A (helper-arg validation failure; helper exit=8)` to disambiguate from API-side Class A. Report the bug rather than working around it.

**Config validation fails**: re-run Step 6; check that the heredoc closed properly and that `role_preference` is a JSON array of strings matching keys in `providers`.

**`/cross-ai-review` not recognized as a command**: confirm `~/.claude/commands/cross-ai-review.md` exists and is readable. Restart Claude Code if needed.

**Slash command says "no available providers"**: the slash command auto-detects installed CLIs via `which codex` / `which gemini`. If neither resolves, install at least one and auth it; the next invocation will pick it up automatically.

**Slash command picked the wrong iterating reviewer**: the resolved iterating reviewer is the first entry in `role_preference` that's actually installed and authed. To swap, edit `~/.claude/cross-ai-review-config.json` and reorder `role_preference`. Edit takes effect on the next invocation; no restart.

---

## What you (Claude) should NOT do

- Do not bypass the read-only flags (`-s read-only` for Codex, `--approval-mode plan` for Gemini). The cycle's integrity depends on reviewers being unable to modify the artifact.
- Do not silently accept model fallback. If a CLI returns a different model than requested, halt.
- Do not pre-populate `~/.claude/settings.json` (or `settings.local.json`) with helper allowlist patterns from this install. The runtime permission prompt is the intended consent moment; granting must be the user's action at the prompt. (Slash command Hard rule #4 mirrors this — every helper invocation uses literal parameter values so "always allow" is offered cleanly.)
- Do not wrap helper invocations in `bash`, `sh`, `pwsh`, `python`, or any other interpreter. The first token of every helper invocation must be the helper's own path. Wrapping in an interpreter would cause Claude Code to offer an overbroad `bash *` (or equivalent) "always allow" pattern instead of the helper-scoped pattern. (Slash command Hard rule #5.)
- Do not edit the user's existing `~/.claude/CLAUDE.md` content beyond appending the cross-AI stub. They may have customizations you don't see. The methodology file is wholly starter-owned and may be overwritten (with backup).
- Do not push or commit anything from the smoke test or install process.

---

When all steps complete successfully, the user can run `/cross-ai-review` in any project. The setup is done.
