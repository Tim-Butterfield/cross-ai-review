# Project extension template (v1)

This template adds a `## Cross-AI Review Extension` section to a project's `CLAUDE.md`. The extension is **optional** — the global cycle works without it (using the **minimal profile**: P1 only against the artifact's own merits). The extension lets you opt into the methodology's six review primitives by declaring project-specific content for each one.

## How to use this template

1. Copy the section below into your project's root `CLAUDE.md` (create the file if it doesn't exist).
2. Fill in the placeholder values (everything in `<angle brackets>`) for the primitives you want active. **Delete any subsection you don't need** — primitives are opt-in; absent declarations mean "this primitive is not configured for this project."
3. Commit the change so collaborators see the same review behavior.

The global cycle (defined in `~/.claude/cross-ai-review-methodology.md`, loaded on demand by the slash command's Step 0) reads this section automatically when you run `/cross-ai-review` in this project.

## Migration from pre-v1 extensions

If you have an existing `## Cross-AI Review Extension` written against a pre-v1 methodology (sections like `### Evaluation criteria`, `### Severity discipline`, `### Final-pass criteria`), here's how the structure maps to v1:

| Pre-v1 subsection | v1 home |
|---|---|
| `### Evaluation criteria` | Folded into per-primitive declarations (the "criteria" become the prompt content for each primitive) |
| `### Severity discipline (sharpened)` | Stays as `### Severity overrides` (project-specific overrides on top of methodology's baseline) |
| `### Final-pass criteria` | Stays as `### Final-pass criteria` (still apply-mode only; skipped in report mode) |
| `### Document growth discipline` | Folded into the methodology's growth-tracking baseline; project-specific growth rules belong in `### Severity overrides` if they affect severity |
| `### Authority documents` | Stays as `### Authority documents` (DAG declaration) |
| `### Context documents` | Stays as `### Context documents` |
| `### Audit trail` | Removed; methodology owns audit-trail location |
| `### Provider override` | Stays as `### Provider override` |

The big shift: instead of generic "evaluation criteria" prose, you now declare **per-primitive content** with structured shapes. This makes the cycle's runtime behavior more deterministic and auditable.

---

## Cross-AI Review Extension

When `/cross-ai-review` runs against artifacts in this repository, the global cycle (defined in `~/.claude/cross-ai-review-methodology.md`) is extended with the following project-specific rigor.

### Authority documents (DAG declaration — layered or peer-mode)

For multi-artifact reviews, declaring your project's review scope lets the cycle review layer-by-layer (root authority first, then derived layers, with within-layer peer-compatibility checks) or in peer mode (single-layer peers under no declared external authority). Without a declared scope, the cycle falls back to heuristic detection or interactive wizard (and offers to capture the result here for next time). See methodology § Layered review pattern → DAG identification for the canonical resolution order and § Audit artifact formats for the per-call markdown that records what was reviewed against what.

The methodology supports two canonical scope forms. Choose the one that matches your project; the optional `Scope:` line makes the choice explicit.

**Layered-DAG form** (multi-layer hierarchy with declared upstream → downstream relationships):

```markdown
Scope: layered-dag

Layer 0 (root authority): <single doc — the highest authority everything else derives from>

Layer 1 (derives from Layer 0): <doc A>, <doc B>
  Within-layer peer constraints: <none | "doc A and doc B must remain mutually compatible">

Layer 2 (derives from Layer 1): <doc C>, <doc D>, <doc E>
  Within-layer peer constraints: <e.g., "doc C (code) and doc E (tests) must remain mutually compatible">
```

Worked example (layered):

```markdown
Scope: layered-dag

Layer 0 (root authority): docs/architecture.md

Layer 1 (derives from Layer 0): docs/design.md

Layer 2 (derives from Layer 1): src/**/*.ts, tests/**/*.test.ts
  Within-layer peer constraints: src/ and tests/ must remain mutually compatible (a test must actually test the code, not just match design abstractly)
```

The `Scope: layered-dag` line is optional for layered runs (presence of `Layer 0 (root authority):` implies it); writing it explicitly is recommended for clarity. P1 in layered mode reviews each derived layer against its declared upstream authority; P1 at Layer 0 uses the no-upstream case (review for internal consistency against the artifact's own stated goals and structure).

**Peer-mode form** (single layer of peers, no declared external authority — for projects where artifacts are mutually independent or the user/project chooses not to elect one as authoritative):

```markdown
Scope: peer-mode

Layer 0 peers: <doc A>, <doc B>, <doc C>

Peer compatibility constraints: <none | "doc A and doc B must remain mutually compatible (P4 peer-compatibility rule)" | ...>
```

Peer-mode declarations have no `Layer 1+`; peer mode is a single layer of peers per methodology § Layered review pattern. The `Peer compatibility constraints:` sub-line is optional — omit when no inter-peer P4 rules are declared. Each constraint becomes a P4 peer-compatibility rule for the listed peers; if the P4 peer-compatibility rule itself declares a `Static check:` command (see the `For peer-compatibility rules` shape under § P4 — Structural rules below in this template, plus methodology § P4 — Structural rules → Tooling-conditional behavior), P4 runs mixed for that rule, otherwise semantic-only. P5 validation hooks are independent and do NOT make a P4 rule mixed (per methodology § P4 → Tooling-conditional behavior and § P5 — Validation hooks).

In peer mode, **P1 runs the no-upstream case per artifact** (per artifact internal consistency); peer-to-peer compatibility is handled by P4, not P1. If you want a global authority that promotes peer mode to layered mode, declare it as `Layer 0 (root authority): <doc>` and the peers as `Layer 1 ...` instead — the cycle will then run layered mode with that authority.

(*Optional but strongly recommended for multi-artifact projects. If a reviewer's finding contradicts an upstream authority, the authority wins. The cycle records cross-layer findings as `upstream-conflict-deferred` and surfaces them to the user without modifying upstream layers during a downstream review. Delete this subsection if your project has only a single artifact under review at a time.*)

### Per-primitive declarations

Each primitive is opt-in. Declare only the primitives this project needs. Absent declarations mean "not configured" — distinct from "failed."

#### P1 — Authority adherence

P1 is implicitly active for any layered DAG (the methodology's default). To configure additional authority pairs beyond the DAG-implied ones, list them here:

```markdown
Authority pairs:
- Derived: <path>  ← Authority: <upstream path>
- Derived: <path>  ← Authority: <upstream path>
```

(*Optional — usually not needed since the DAG declaration above already implies authority pairs. Use this only when you want a non-DAG authority relationship, e.g., a code file that should adhere to an external spec at a fixed URL.*)

#### P2 — Coverage interpretation

Declare set A → set B coverage mappings. Every item in set A must have a corresponding item in set B (1:1, 1:N, or N:1).

```markdown
Coverage mappings:
- From: <set A description, e.g. "REQ-NNN identifiers in requirements/*.md">
  To: <set B description, e.g. "REQ-NNN references in tests/**/*.spec.ts">
  Cardinality: <1:1 | 1:N | N:1>
  Match rule: <how to recognize a match, e.g. "test name contains REQ-NNN slug">
```

(*Optional — declare when your project has explicit coverage relationships you want enforced. Common cases: requirements → tests, design elements → implementations, public APIs → docs.*)

#### P3 — Linkage verification

Declare ID schemas and linkage rules. The cycle resolves references between IDs and reports orphans and danglers.

```markdown
ID schemas:
- Pattern: <regex, e.g. "REQ-\\d{4}">
  Domain: <where these IDs are defined, e.g. "requirements/*.md">
- Pattern: <regex, e.g. "ADR-\\d{4}">
  Domain: <e.g. "docs/adr/*.md">

Linkage rules:
- From schema: <e.g. "REQ-\\d{4}">
  To schema: <e.g. "ADR-\\d{4}">
  Direction: <one-way | bidirectional>
  Required: <true | false>
```

(*Optional — declare when your project has structured ID-based traceability. Common in regulated industries, large codebases, or projects with formal requirements traceability.*)

#### P4 — Structural rules

Declare structural rules the project enforces. Examples: dependency direction, naming conventions, layering, peer-compatibility.

```markdown
Structural rules:
- Name: <rule name, e.g. "no-cross-layer-imports">
  Rule: <description, e.g. "files in src/persistence/ must not import from src/presentation/">
  Severity: <info | low | medium | high | critical>
  Static check: <optional — shell command that detects violations, e.g. "your-linter --rule no-cross-layer-imports src/">
- Name: <rule name>
  Rule: <description>
  Severity: <level>
  Static check: <optional>
```

For peer-compatibility rules (within-layer "must remain mutually compatible"), use this shape:

```markdown
Peer-compatibility:
- Peers: <comma-separated list of artifact paths or patterns>
  Constraint: <e.g. "src/api/*.ts and tests/api/*.spec.ts must remain mutually compatible">
  Static check: <optional — shell command that detects violations, e.g. "your-linter --rule peer-compat src/api/ tests/api/">
```

**P4 tooling-conditional behavior** (per methodology § P4 → Tooling-conditional behavior): when a P4 structural rule (general or peer-compatibility) includes a `Static check:` command, P4 runs as a **mixed primitive** for that rule (mechanical pre-check via the linter + semantic phases on the violations). When the rule is semantic-only (no `Static check:` declared), P4 runs as a **semantic-only primitive** for that rule — mechanical phases are skipped, and the worst-case budget reduces from 24 calls to 18 (matching the P1 semantic-only shape). Mix declarations freely: a single project extension can declare some P4 rules with static checks (mixed) and others without (semantic-only).

**P4 vs. P5.** P4's `Static check:` command is the rule's own mechanical pre-check, embedded in the P4 rule declaration. P5 (Validation hooks below) is a **separate primitive** for general-purpose deterministic commands (build, test, lint, type-check) that aren't tied to a specific structural rule. Declaring a command in P5 does NOT by itself make any P4 rule "mixed" — P4's tooling-conditional behavior keys off the `Static check:` field inside the P4 rule, not on whether a similar command also appears in P5. Projects may legitimately have a linter declared in BOTH P4 (as a structural rule's static check) AND P5 (as a general validation hook for the same linter command); the cycle treats these independently.

(*Optional — declare when your project has codified structural rules. Linter-checkable rules can be declared with `Static check:` (making the P4 rule mixed) AND/OR as P5 hooks (independent mechanical validation).*)

#### P5 — Validation hooks

Declare deterministic commands that must succeed cleanly. The host runs each declared hook; non-zero exit becomes an evidence finding per methodology § Halt-signal taxonomy → Mechanical hook classes. Per the methodology's M2 rule, command-error non-zero exits are **always findings, not halts** — `required: true` raises the finding's default severity to `high`, but does NOT cause a halt by itself. Halts in P5 are reserved for **M1 (tool unavailable)** with `required: true`, and **M5 (unexpected mutation by a read-only hook)** — both per methodology § Halt-signal taxonomy.

```yaml
Validation hooks:
- name: <unique name, e.g. typecheck>
  command: <shell command, e.g. tsc --noEmit>
  side_effects: <read-only | generated-output-allowed | snapshot-updating | environment-dependent>
  required: <true | false>  # true = high-severity finding on M2 non-zero exit; halt on M1 required-tool-unavailable; false = low-severity finding
  timeout_seconds: <integer, e.g. 60>
  deterministic: <true | false>  # if true, run-twice-and-diff is enabled (M4 detection)
  output_paths: [<glob pattern>]  # required when side_effects=generated-output-allowed
  snapshot_paths: [<glob pattern>]  # required when side_effects=snapshot-updating
  worktree_paths: [<glob pattern>]  # required when side_effects=environment-dependent
```

Worked example (TypeScript project):

```yaml
Validation hooks:
- name: typecheck
  command: tsc --noEmit
  side_effects: read-only
  required: true
  timeout_seconds: 60
  deterministic: true
- name: lint
  command: eslint src/
  side_effects: read-only
  required: true
  timeout_seconds: 30
- name: test
  command: vitest run
  side_effects: snapshot-updating
  required: true
  timeout_seconds: 120
  snapshot_paths: ["src/**/__snapshots__/"]
- name: install
  command: npm ci
  side_effects: environment-dependent
  required: false
  timeout_seconds: 180
  worktree_paths: ["node_modules/", "package-lock.json"]
```

(*Optional — declare when your project has commands that produce signal about correctness. Common: build, type-check, lint, test, schema validation. The methodology's most-used primitive when present.*)

#### P6 — Checklist verification

Declare named checklist items. Each item must be addressed in the artifact (or explicitly waived with rationale via `<!-- waive: ITEM-NAME -->` markers in the artifact, or a `waivers.md` file). Per methodology § P6 → Pre-check waiver finding format, each detected waiver becomes a `kind=pass`, `severity=info`, `source=evidence` finding in the mechanical pre-check phase, with decision state `already-addressed` so it enters the addressed-context for the semantic phase that follows. The semantic reviewer therefore sees the waiver and won't raise a `kind=gap` finding for the waived item; if the waiver rationale doesn't match the item's substance, the reviewer surfaces a `kind=risk` finding instead.

```markdown
Checklist:
- name: <item name, e.g. rollback-plan>
  description: <what the item requires, e.g. "documented rollback procedure for production deploy">
  category: <e.g. delivery-readiness, security-review, on-call>
- name: <item name>
  description: <what is required>
  category: <category>
```

Worked example (delivery readiness):

```markdown
Checklist:
- name: rollback-plan
  description: Documented rollback procedure with explicit revert command and verification step
  category: delivery-readiness
- name: observability
  description: Logging / metrics / tracing covering critical paths added for new features
  category: delivery-readiness
- name: security-signoff
  description: Security review completed and signed off by the security team
  category: security-review
- name: oncall-runbook
  description: On-call runbook updated with new failure modes and recovery procedures
  category: on-call
```

(*Optional — declare for projects with operational readiness gates, security review requirements, or recurring discipline items. The methodology's home for "did you do all the things you should before shipping?"*)

### Thinking levels (per-primitive overrides)

By default, all semantic primitives use the global `thinking_level` from `~/.claude/cross-ai-review-config.json` (typically `standard`). Use this subsection to override per primitive when the project's use case warrants it.

```markdown
Thinking levels:
- P1: <fast | standard | deep>
- P2: <fast | standard | deep>
- P4: <fast | standard | deep>
- P6: <fast | standard | deep>
```

(P3 and P5 are terminally mechanical — no thinking applies.)

The cycle validates this declaration at slash-command entry: overrides for primitives not configured by this project, for terminally-mechanical primitives, or with non-canonical level values cause the run to halt with an actionable error.

(*Optional — most projects use the global default. Common override: P1 = `deep` when authority adherence is high-stakes (charter / public-API / regulated artifacts).*)

### Severity overrides

The methodology has a generic severity baseline (see methodology § Severity baseline). Use this subsection to sharpen it for project-specific concerns.

```markdown
Severity overrides:

ALWAYS-suggestion (cannot be high/critical, never blocks the gate) — additions to the methodology's baseline:
- <example: comments referring to ticket numbers — non-load-bearing>
- <example: minor naming convention deviations in test files>

Concrete-failure-required (every blocking or warning finding MUST cite a concrete failure scenario):
- <e.g. "Auto-downgrade speculative concerns about scenarios not exercised by current tests to suggestion">
```

(*Optional — these rules supplement the global severity baseline. Delete this subsection if the global baseline is sufficient.*)

### Final-pass criteria

After the cross-AI cycle settles (apply mode only — skipped in report mode), the host's per-layer final self-critique pass evaluates against the criteria in:

```markdown
Final-pass criteria:
- <criterion 1, e.g. "All exported types in changed modules have JSDoc">
- <criterion 2, e.g. "New endpoints have a corresponding integration test">
- <criterion 3, e.g. "No console.log / debugger / TODO left in committed code">
- <criterion 4, e.g. "Migration files numbered correctly and referenced in migrations/index.ts">
```

The methodology adds a generic dismissal-verification rule on top: any finding rejected as invalid earlier in the cycle must have a logged reason citing artifact content, not the host's reasoning alone.

(*Optional — this is what the host alone evaluates after the reviewers finish. Skipped in `--report` mode (where there's no post-edit state to verify against). Delete if you don't have specific final-pass criteria — the host will run a generic check.*)

### Context documents

Include in reviewer prompts as additional background:

```markdown
Context documents:
- <path/to/architecture-overview.md> — <one-line description>
- <path/to/glossary.md> — <one-line description>
```

(*Optional — context that helps reviewers understand the artifact without flooding the prompt. Reviewers will load these alongside the artifact under review. Delete if no additional context is needed.*)

### Provider override

This subsection lets the project pin a specific provider/model/role/thinking-level configuration, taking precedence over the user's global `~/.claude/cross-ai-review-config.json`. Use this when the project has a hard requirement (e.g., reproducibility for shared reviews, security policy that mandates one vendor, or a known-good model pin).

```json
{
  "schema_version": 1,
  "providers": {
    "codex":  { "models": ["gpt-5.5"], "thinking_level": "deep" },
    "gemini": { "models": ["gemini-3.1-pro-preview"], "thinking_level": "standard" }
  },
  "role_preference": ["codex", "gemini"]
}
```

**Merge semantics** are defined canonically in methodology § Configuration → Resolution order at runtime. Summary: shallow per-top-level-key replacement (NOT deep merge); if you include a `providers` block, you restate every provider you want available; auto-detection of installed CLIs still applies and unauthed providers selected as iterating halt Class A on first call.

(*Optional — most projects do NOT need this. Use it only when the project has a specific reason to pin reviewer configuration. Delete this subsection if the global config is fine for this repo.*)

---

## Worked example (delete this section before committing)

Here's how a hypothetical TypeScript backend project might fill in the template — for reference only. Yours will look different.

```markdown
## Cross-AI Review Extension

### Authority documents

Layer 0 (root authority): docs/architecture.md

Layer 1 (derives from Layer 0): docs/design.md, docs/api-spec.md
  Within-layer peer constraints: design.md and api-spec.md must remain mutually compatible

Layer 2 (derives from Layer 1): src/**/*.ts, tests/**/*.test.ts
  Within-layer peer constraints: src/ and tests/ must remain mutually compatible

### P3 — Linkage verification

ID schemas:
- Pattern: REQ-\d{4}
  Domain: requirements/*.md
- Pattern: ADR-\d{4}
  Domain: docs/adr/*.md
- Pattern: TEST-REQ-\d{4}
  Domain: tests/**/*.test.ts

Linkage rules:
- From schema: REQ-\d{4}
  To schema: TEST-REQ-\d{4}
  Direction: one-way
  Required: true

### P4 — Structural rules

Structural rules:
- Name: no-presentation-in-persistence
  Rule: files in src/persistence/ must not import from src/presentation/
  Severity: high

### P5 — Validation hooks

Validation hooks:
- name: typecheck
  command: tsc --noEmit
  side_effects: read-only
  required: true
  timeout_seconds: 60
- name: lint
  command: eslint src/
  side_effects: read-only
  required: true
- name: test
  command: vitest run
  side_effects: snapshot-updating
  required: true
  snapshot_paths: ["src/**/__snapshots__/"]

### P6 — Checklist verification

Checklist:
- name: api-contract-additive-only
  description: Any non-additive change to a public API must be flagged blocking
  category: api-contract
- name: migrations-reversible
  description: Database migrations must be reversible OR explicitly marked one-way with rollback rationale
  category: database
- name: auth-changes-security-review
  description: Authentication/authorization changes require security-review tag
  category: security-review

### Thinking levels

- P1: deep
- P4: deep
- P6: standard

### Severity overrides

ALWAYS-suggestion:
- Comment style, import ordering, variable naming preferences

Concrete-failure-required:
- Speculative concerns about scenarios not exercised by current tests → suggestion

### Final-pass criteria

- All exported types in changed modules have JSDoc
- New endpoints have a corresponding integration test
- No console.log / debugger / TODO left in committed code
- Migration files numbered correctly and referenced in migrations/index.ts
```

This is illustrative — your project's primitives, rules, hooks, checklist items, and final-pass criteria will reflect your specific work, conventions, and team agreements. Fill in only the subsections that apply to you.

---

## When NOT to use a project extension

If your project has no formal review criteria, no specific structural rules, no validation commands, no traceability IDs, and no readiness checklist: **don't bother**. The minimal profile (P1 only against the artifact's own merits) is enough for many cases. You can always add an extension later when patterns emerge.
