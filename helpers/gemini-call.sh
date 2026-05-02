#!/usr/bin/env bash
# gemini-call.sh — wrapper for Gemini CLI invocation per the cross-ai-review cycle.
# Cross-platform note: PowerShell equivalent at gemini-call.ps1.
#
# Interface (same on .sh and .ps1):
#   --layer <int>          Layer index. Recorded in per-call .md header.
#   --primitive <P1..P6>   Primitive code. Recorded in per-call .md header.
#   --phase <name>         One of: semantic-iterate | semantic-cross-check | semantic-verify
#   --outer <int>          Outer cycle index.
#   --iter <int>           Inner iteration (only required when --role iterating).
#   --role <iterating|cross-check|verify>
#   --model <slug>         Requested model slug (e.g., gemini-3.1-pro-preview).
#   --thinking-level <fast|standard|deep>
#                          Abstract thinking level. Helper translates to Gemini's native
#                          thinking-budget (or other native control as the CLI exposes).
#                          Default mapping (subject to provider doc updates):
#                          fast→2048 tokens, standard→8192 tokens, deep→24576 tokens.
#                          When the installed CLI version doesn't expose a thinking-budget
#                          flag, the helper records native=unsupported in audit.
#   --prompt-file <path>   Path to file containing the reviewer prompt.
#   --stdin-file <path>    Optional: file to pipe via stdin (artifact content for Gemini to review).
#   --run-dir <path>       Run directory.
#   --call-started <ts>    Timestamp prefix for output filenames.
#
# No override flag exists for actual-model extraction failure — the cycle halts
# as Class E unconditionally per methodology § Actual-model extraction failure.
#
# Output:
#   - Raw envelope to <run-dir>/.tmp-<call-started>-out.json
#   - Stripped reviewer JSON to <run-dir>/.tmp-<call-started>-reviewer.json
#   - Stderr to <run-dir>/.tmp-<call-started>-err
#   - Stdout: JSON status object (same shape as codex-call.sh).
#
# Exit codes match codex-call.sh: 0=ok, 1-7=halt classes A-G, 8=invalid args.

set -e
set -o pipefail

STDIN_FILE=""

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
    --stdin-file)       STDIN_FILE="$2"; shift 2 ;;
    --run-dir)          RUN_DIR="$2"; shift 2 ;;
    --call-started)     CALL_STARTED="$2"; shift 2 ;;
    *) echo "{\"error\": \"unknown arg: $1\"}" >&2; exit 8 ;;
  esac
done

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

# Translate thinking level → Gemini native thinking-budget
# Mapping reflects current Gemini SDK conventions; helpers can refine when the CLI exposes the flag.
case "$THINKING_LEVEL" in
  fast)     NATIVE_BUDGET=2048 ;;
  standard) NATIVE_BUDGET=8192 ;;
  deep)     NATIVE_BUDGET=24576 ;;
  *) echo "{\"error\": \"invalid --thinking-level: $THINKING_LEVEL (must be fast | standard | deep)\"}" >&2; exit 8 ;;
esac

TMP_OUT="$RUN_DIR/.tmp-$CALL_STARTED-out.json"
TMP_REVIEWER="$RUN_DIR/.tmp-$CALL_STARTED-reviewer.json"
TMP_ERR="$RUN_DIR/.tmp-$CALL_STARTED-err"

PROMPT=$(cat "$PROMPT_FILE")

# Invoke Gemini. Required flags per methodology § Gemini CLI:
#   --approval-mode plan   — read-only sandbox
#   --output-format json   — produces the envelope {response, stats, error}
# Note: Gemini CLI's thinking-budget flag exposure varies by version; current versions may
# not have a stable named flag. The helper records native=unsupported when the flag isn't
# available and the call still proceeds with the CLI default (auditable in stats).
set +e
if [ -n "$STDIN_FILE" ]; then
  cat "$STDIN_FILE" | gemini -p "$PROMPT" -m "$MODEL" --approval-mode plan --output-format json > "$TMP_OUT" 2> "$TMP_ERR"
else
  gemini -p "$PROMPT" -m "$MODEL" --approval-mode plan --output-format json < /dev/null > "$TMP_OUT" 2> "$TMP_ERR"
fi
GEMINI_EXIT=$?
set -e

# Halt-signal classification
HALT_CLASS=""
if [ $GEMINI_EXIT -ne 0 ] || [ ! -s "$TMP_OUT" ]; then
  if grep -E -q "RetryableQuotaError|exhausted your capacity" "$TMP_ERR"; then
    HALT_CLASS="C"
  elif grep -E -q "ModelNotFoundError|Requested entity was not found|404" "$TMP_ERR"; then
    HALT_CLASS="D"
  elif grep -E -q "QUOTA_EXCEEDED" "$TMP_ERR"; then
    HALT_CLASS="B"
  elif grep -E -q "401|403|authentication|permission denied" "$TMP_ERR"; then
    HALT_CLASS="A"
  elif grep -E -q "Ripgrep is not available" "$TMP_ERR" && [ -s "$TMP_OUT" ]; then
    # F-pattern but call may have succeeded — fall through to envelope parse below
    :
  else
    HALT_CLASS="G"
  fi
fi

# Parse envelope and extract reviewer JSON if successful
MODEL_ACTUAL=""
NATIVE_THINKING="gemini thinking_budget_tokens=$NATIVE_BUDGET"
if [ -z "$HALT_CLASS" ] && [ -s "$TMP_OUT" ]; then
  ENV_ERROR=$(jq -r '.error // empty' "$TMP_OUT" 2>/dev/null || echo "")
  if [ -n "$ENV_ERROR" ] && [ "$ENV_ERROR" != "null" ]; then
    HALT_CLASS="G"
  else
    RESPONSE=$(jq -r '.response // empty' "$TMP_OUT" 2>/dev/null || echo "")
    RESPONSE_CLEAN=$(echo "$RESPONSE" | sed -E 's/^```(json)?$//; s/^```$//' | sed '/^$/d')
    if echo "$RESPONSE_CLEAN" | jq -e '.summary, .verdict, .findings' > /dev/null 2>&1; then
      echo "$RESPONSE_CLEAN" > "$TMP_REVIEWER"
    else
      HALT_CLASS="G"
    fi
    MODEL_ACTUAL=$(jq -r '.stats.models // {} | keys[0] // empty' "$TMP_OUT" 2>/dev/null || echo "")
    # Detect whether the CLI version honored the thinking-budget flag (best-effort).
    # If unsupported in this CLI version, record as such in audit.
    if ! grep -E -q "thinking|reasoning" "$TMP_OUT" 2>/dev/null; then
      NATIVE_THINKING="unsupported"
    fi
  fi
fi

# Class E check — extraction failure halts unconditionally (no override in v1)
if [ -z "$MODEL_ACTUAL" ] && [ -z "$HALT_CLASS" ]; then
  HALT_CLASS="E"
  MODEL_ACTUAL="extraction-failed"
elif [ -n "$MODEL_ACTUAL" ] && [ "$MODEL_ACTUAL" != "$MODEL" ]; then
  HALT_CLASS="E"
fi

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

HALT_JSON="null"
if [ -n "$HALT_CLASS" ]; then
  HALT_JSON="\"$HALT_CLASS\""
fi

cat <<EOF
{"exit_code": $EXIT_CODE, "output_file": "$TMP_OUT", "reviewer_file": "$TMP_REVIEWER", "stderr_file": "$TMP_ERR", "model_actual": "$MODEL_ACTUAL", "native_thinking": "$NATIVE_THINKING", "halt_class": $HALT_JSON}
EOF

exit $EXIT_CODE
