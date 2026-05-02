#!/usr/bin/env bash
# codex-call.sh — wrapper for Codex CLI invocation per the cross-ai-review cycle.
# Cross-platform note: this is the bash version; the PowerShell equivalent
# (codex-call.ps1) implements the same interface for Windows-native shells.
#
# Interface (same on .sh and .ps1):
#   --layer <int>          Layer index (0, 1, ...). Recorded in per-call .md header.
#   --primitive <P1..P6>   Primitive code. Recorded in per-call .md header.
#   --phase <name>         One of: semantic-iterate | semantic-cross-check | semantic-verify
#                          (mechanical phases run by host directly, not via this helper)
#   --outer <int>          Outer cycle index (1, 2, 3).
#   --iter <int>           Inner iteration index (1, 2, 3, 4). Required for --role iterating; omitted for cross-check/verify.
#   --role <iterating|cross-check|verify>
#                          Determines audit metadata.
#   --model <slug>         Requested model slug (e.g., gpt-5.5).
#   --thinking-level <fast|standard|deep>
#                          Abstract thinking level. Helper translates to Codex's native model_reasoning_effort:
#                          fast→low, standard→medium, deep→high.
#   --prompt-file <path>   Path to file containing the reviewer prompt (host writes this beforehand).
#   --schema <path>        Path to JSON schema (default: ~/.claude/cross-ai-review-schema.json).
#   --run-dir <path>       Run directory (e.g., tmp/cross-ai-review/<RUN_ID>/). Output written here.
#   --call-started <ts>    Timestamp prefix for output filenames (e.g., 20260430T223050).
#
# No override flag exists for actual-model extraction failure — the cycle halts
# as Class E unconditionally per methodology § Actual-model extraction failure.
#
# Output:
#   - Writes raw CLI output to <run-dir>/.tmp-<call-started>-out.json
#   - Writes raw CLI stderr to <run-dir>/.tmp-<call-started>-err
#   - Prints to stdout a JSON status object: {exit_code, output_file, stderr_file, model_actual, native_thinking, halt_class|null}
#
# Exit codes:
#   0  — success (output produced, schema-valid, model_actual verified)
#   1  — Class A halt (auth/permission)
#   2  — Class B halt (account quota exhausted)
#   3  — Class C halt (server-side capacity, fallback chain exhausted)
#   4  — Class D halt (model not on account)
#   5  — Class E halt (silent fallback or extraction failure)
#   6  — Class F halt (suspected transient bug, retry exhausted)
#   7  — Class G halt (unclassified)
#   8  — Invalid arguments

set -e
set -o pipefail

# Default values
SCHEMA="$HOME/.claude/cross-ai-review-schema.json"

# Parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --layer)            LAYER="$2"; shift 2 ;;
    --primitive)        PRIMITIVE="$2"; shift 2 ;;
    --phase)            PHASE="$2"; shift 2 ;;
    --outer)            OUTER="$2"; shift 2 ;;
    --iter)             ITER="$2"; shift 2 ;;
    --role)             ROLE="$2"; shift 2 ;;
    --model)            MODEL="$2"; shift 2 ;;
    --thinking-level)   THINKING_LEVEL="$2"; shift 2 ;;
    --prompt-file)      PROMPT_FILE="$2"; shift 2 ;;
    --schema)           SCHEMA="$2"; shift 2 ;;
    --run-dir)          RUN_DIR="$2"; shift 2 ;;
    --call-started)     CALL_STARTED="$2"; shift 2 ;;
    *) echo "{\"error\": \"unknown arg: $1\"}" >&2; exit 8 ;;
  esac
done

# Validate required args
for required in LAYER PRIMITIVE PHASE OUTER ROLE MODEL THINKING_LEVEL PROMPT_FILE RUN_DIR CALL_STARTED; do
  if [ -z "${!required:-}" ]; then
    echo "{\"error\": \"missing required arg: --$(echo $required | tr '[:upper:]' '[:lower:]' | tr '_' '-')\"}" >&2
    exit 8
  fi
done

if [ "$ROLE" = "iterating" ] && [ -z "${ITER:-}" ]; then
  echo "{\"error\": \"--iter required for --role iterating\"}" >&2
  exit 8
fi

# Translate thinking level → Codex native model_reasoning_effort
case "$THINKING_LEVEL" in
  fast)     NATIVE_REASONING="low" ;;
  standard) NATIVE_REASONING="medium" ;;
  deep)     NATIVE_REASONING="high" ;;
  *) echo "{\"error\": \"invalid --thinking-level: $THINKING_LEVEL (must be fast | standard | deep)\"}" >&2; exit 8 ;;
esac

# Resolve output paths
TMP_OUT="$RUN_DIR/.tmp-$CALL_STARTED-out.json"
TMP_ERR="$RUN_DIR/.tmp-$CALL_STARTED-err"

# Read prompt
if [ ! -f "$PROMPT_FILE" ]; then
  echo "{\"error\": \"prompt file not found: $PROMPT_FILE\"}" >&2
  exit 8
fi

# Invoke Codex
# Non-negotiable flags per methodology § Codex CLI:
#   -s read-only             — sandbox prevents file modification
#   --skip-git-repo-check    — required for non-git directories
#   < /dev/null              — close stdin so codex doesn't hang
#
# Schema mode (default): --output-schema enforces JSON shape; codex writes
# validated JSON to -o "$TMP_OUT". Used by /cross-ai-review.
#
# No-schema mode (--schema none): --output-schema flag is omitted; codex
# writes the model's raw text response (typically markdown) to -o "$TMP_OUT".
# Used by /clarify when the analyst is codex (the analyst returns a packet's
# entry-block markdown directly, not schema-enforced JSON).
PROMPT=$(cat "$PROMPT_FILE")
set +e
if [ "$SCHEMA" = "none" ]; then
  codex exec -s read-only --skip-git-repo-check \
    -m "$MODEL" -c model_reasoning_effort="$NATIVE_REASONING" \
    -o "$TMP_OUT" \
    "$PROMPT" \
    < /dev/null 2> "$TMP_ERR"
else
  codex exec -s read-only --skip-git-repo-check \
    -m "$MODEL" -c model_reasoning_effort="$NATIVE_REASONING" \
    --output-schema "$SCHEMA" \
    -o "$TMP_OUT" \
    "$PROMPT" \
    < /dev/null 2> "$TMP_ERR"
fi
CODEX_EXIT=$?
set -e

# Halt-signal classification
HALT_CLASS=""
if [ $CODEX_EXIT -ne 0 ] || [ ! -s "$TMP_OUT" ]; then
  if grep -E -q -i "payment required|usage limit|monthly quota|daily quota" "$TMP_ERR"; then
    HALT_CLASS="B"
  elif grep -E -q -i "service overloaded|try again later" "$TMP_ERR" || grep -E -q "503|529" "$TMP_ERR"; then
    HALT_CLASS="C"
  elif grep -E -q -i "Requested entity was not found|ModelNotFoundError|404" "$TMP_ERR"; then
    HALT_CLASS="D"
  elif grep -E -q -i "401|403|authentication|permission denied" "$TMP_ERR"; then
    HALT_CLASS="A"
  elif grep -E -q "invalid_json_schema|invalid_request_error|\"status\": ?400" "$TMP_ERR"; then
    HALT_CLASS="A"
  else
    HALT_CLASS="G"
  fi
fi

# Actual-model extraction (Class E check)
MODEL_ACTUAL=""
if [ -s "$TMP_ERR" ]; then
  # Codex stderr contains a model identifier in its tool-use trace.
  MODEL_ACTUAL=$(grep -oE 'model[ =:"]*[a-z0-9.-]+' "$TMP_ERR" | head -1 | grep -oE '[a-z0-9.-]+$' || echo "")
fi

if [ -z "$MODEL_ACTUAL" ] && [ -z "$HALT_CLASS" ]; then
  # Extraction failed — halt as Class E unconditionally (no override flag in v1)
  HALT_CLASS="E"
  MODEL_ACTUAL="extraction-failed"
elif [ -n "$MODEL_ACTUAL" ] && [ "$MODEL_ACTUAL" != "$MODEL" ]; then
  # Silent fallback detected — halt as Class E
  HALT_CLASS="E"
fi

# Map halt class to exit code
case "$HALT_CLASS" in
  A) EXIT_CODE=1 ;;
  B) EXIT_CODE=2 ;;
  C) EXIT_CODE=3 ;;
  D) EXIT_CODE=4 ;;
  E) EXIT_CODE=5 ;;
  F) EXIT_CODE=6 ;;
  G) EXIT_CODE=7 ;;
  *) EXIT_CODE=0 ;;
esac

# Output structured status
HALT_JSON="null"
if [ -n "$HALT_CLASS" ]; then
  HALT_JSON="\"$HALT_CLASS\""
fi

NATIVE_THINKING="codex model_reasoning_effort=$NATIVE_REASONING"

cat <<EOF
{"exit_code": $EXIT_CODE, "output_file": "$TMP_OUT", "stderr_file": "$TMP_ERR", "model_actual": "$MODEL_ACTUAL", "native_thinking": "$NATIVE_THINKING", "halt_class": $HALT_JSON}
EOF

exit $EXIT_CODE
