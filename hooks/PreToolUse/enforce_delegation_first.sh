#!/usr/bin/env bash
# Enforce delegation-first protocol: Block TodoWrite until after first delegation.
# Tool name is passed via stdin as JSON.

set -euo pipefail

# --- DEBUG MODE ---
DEBUG_HOOK="${DEBUG_DELEGATION_HOOK:-0}"
DEBUG_FILE="/tmp/delegation_hook_debug.log"

# --- quick bypass for emergencies ---
if [[ "${DELEGATION_HOOK_DISABLE:-0}" == "1" ]]; then
  [[ "$DEBUG_HOOK" == "1" ]] && echo "[enforce_delegation_first] Hook disabled via DELEGATION_HOOK_DISABLE" >> "$DEBUG_FILE"
  exit 0
fi

# --- Extract tool name and session_id from stdin JSON ---
# Claude Code passes tool info via stdin as JSON: {"tool_name":"ToolName","session_id":"..."}
STDIN_DATA=$(cat)
[[ "$DEBUG_HOOK" == "1" ]] && echo "[enforce_delegation_first] === $(date) ===" >> "$DEBUG_FILE"
[[ "$DEBUG_HOOK" == "1" ]] && echo "[enforce_delegation_first] Stdin: $STDIN_DATA" >> "$DEBUG_FILE"

# Extract tool_name and session_id using grep/sed (no external deps like jq)
TOOL_NAME=$(echo "$STDIN_DATA" | grep -o '"tool_name":"[^"]*"' | sed 's/"tool_name":"\([^"]*\)"/\1/' || echo "")
SESSION_ID=$(echo "$STDIN_DATA" | grep -o '"session_id":"[^"]*"' | sed 's/"session_id":"\([^"]*\)"/\1/' || echo "")

[[ "$DEBUG_HOOK" == "1" ]] && echo "[enforce_delegation_first] Extracted TOOL_NAME: '$TOOL_NAME'" >> "$DEBUG_FILE"
[[ "$DEBUG_HOOK" == "1" ]] && echo "[enforce_delegation_first] Extracted SESSION_ID: '$SESSION_ID'" >> "$DEBUG_FILE"

# --- Only check if tool is TodoWrite ---
if [[ "$TOOL_NAME" != "TodoWrite" ]]; then
  [[ "$DEBUG_HOOK" == "1" ]] && echo "[enforce_delegation_first] Not TodoWrite, skipping check" >> "$DEBUG_FILE"
  exit 0
fi

[[ "$DEBUG_HOOK" == "1" ]] && echo "[enforce_delegation_first] TodoWrite detected, checking delegation state" >> "$DEBUG_FILE"

# --- Check if delegation has occurred ---
STATE_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/state"
DELEGATED_SESSIONS_FILE="$STATE_DIR/delegated_sessions.txt"
DELEGATION_FLAG="$STATE_DIR/delegation_active"

# Allow TodoWrite if:
# 1. Session is in delegated_sessions.txt (delegation occurred)
# 2. delegation_active flag exists (delegation in progress)

# Check delegation flag file
if [[ -f "$DELEGATION_FLAG" ]]; then
  [[ "$DEBUG_HOOK" == "1" ]] && echo "[enforce_delegation_first] ALLOWED: Delegation active flag exists" >> "$DEBUG_FILE"
  exit 0
fi

# Check if current session is delegated
if [[ -f "$DELEGATED_SESSIONS_FILE" && -n "$SESSION_ID" ]]; then
  if grep -Fxq "$SESSION_ID" "$DELEGATED_SESSIONS_FILE" 2>/dev/null; then
    [[ "$DEBUG_HOOK" == "1" ]] && echo "[enforce_delegation_first] ALLOWED: Session '$SESSION_ID' is delegated" >> "$DEBUG_FILE"
    exit 0
  fi
fi

# --- Block TodoWrite before delegation ---
[[ "$DEBUG_HOOK" == "1" ]] && echo "[enforce_delegation_first] BLOCKED: TodoWrite attempted before delegation" >> "$DEBUG_FILE"

{
  echo "⚠️ DELEGATION-FIRST PROTOCOL VIOLATION"
  echo ""
  echo "You attempted to create a TodoWrite task list BEFORE delegating."
  echo ""
  echo "🚫 BLOCKED: TodoWrite"
  echo ""
  echo "✅ REQUIRED: Use /delegate <task> first, THEN TodoWrite after orchestrator responds."
  echo ""
  echo "Correct sequence:"
  echo "  1. User provides task request"
  echo "  2. /delegate <full task description>"
  echo "  3. Orchestrator analyzes and responds"
  echo "  4. TodoWrite to track orchestrator's execution plan"
  echo ""
  echo "Debug: export DEBUG_DELEGATION_HOOK=1"
} >&2

exit 2
