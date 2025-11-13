#!/usr/bin/env bash
# Block tools unless /delegate was used, but ALWAYS allow delegation tools.
# Tool name is passed via stdin as JSON.

set -euo pipefail

# --- DEBUG MODE ---
DEBUG_HOOK="${DEBUG_DELEGATION_HOOK:-0}"
DEBUG_FILE="/tmp/delegation_hook_debug.log"

# --- quick bypass for emergencies ---
if [[ "${DELEGATION_HOOK_DISABLE:-0}" == "1" ]]; then
  [[ "$DEBUG_HOOK" == "1" ]] && echo "Hook disabled via DELEGATION_HOOK_DISABLE" >> "$DEBUG_FILE"
  exit 0
fi

# --- Cleanup old delegated sessions (older than 1 hour) ---
STATE_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/state"
DELEGATED_SESSIONS_FILE="$STATE_DIR/delegated_sessions.txt"
if [[ -f "$DELEGATED_SESSIONS_FILE" ]]; then
  # Clean up if file is older than 1 hour
  if [[ $(find "$DELEGATED_SESSIONS_FILE" -mmin +60 2>/dev/null | wc -l) -gt 0 ]]; then
    rm -f "$DELEGATED_SESSIONS_FILE"
    [[ "$DEBUG_HOOK" == "1" ]] && echo "CLEANUP: Removed old delegated sessions file" >> "$DEBUG_FILE"
  fi
fi

# --- Extract tool name and session_id from stdin JSON ---
# Claude Code passes tool info via stdin as JSON: {"tool_name":"ToolName","session_id":"..."}
STDIN_DATA=$(cat)
[[ "$DEBUG_HOOK" == "1" ]] && echo "=== $(date) ===" >> "$DEBUG_FILE"
[[ "$DEBUG_HOOK" == "1" ]] && echo "Stdin: $STDIN_DATA" >> "$DEBUG_FILE"

# Extract tool_name and session_id using grep/sed (no external deps like jq)
TOOL_NAME=$(echo "$STDIN_DATA" | grep -o '"tool_name":"[^"]*"' | sed 's/"tool_name":"\([^"]*\)"/\1/' || echo "")
SESSION_ID=$(echo "$STDIN_DATA" | grep -o '"session_id":"[^"]*"' | sed 's/"session_id":"\([^"]*\)"/\1/' || echo "")

[[ "$DEBUG_HOOK" == "1" ]] && echo "Extracted TOOL_NAME: '$TOOL_NAME'" >> "$DEBUG_FILE"
[[ "$DEBUG_HOOK" == "1" ]] && echo "Extracted SESSION_ID: '$SESSION_ID'" >> "$DEBUG_FILE"

# --- allowlist ---
ALLOWED_TOOLS=(
  "AskUserQuestion"
  "TodoWrite"
  "SlashCommand"   # keep this to allow /delegate
  "Task"           # allow delegation Task tool
  "SubagentTask"
  "AgentTask"
)

# --- Check allowlist ---
shopt -s nocasematch

if [[ -n "$TOOL_NAME" ]]; then
  # Exact allowlist check
  for t in "${ALLOWED_TOOLS[@]}"; do
    if [[ "$TOOL_NAME" == "$t" ]]; then
      [[ "$DEBUG_HOOK" == "1" ]] && echo "ALLOWED: Matched '$t'" >> "$DEBUG_FILE"

      # If this is a Task or SlashCommand tool, mark this session as delegated
      if [[ "$TOOL_NAME" == "Task" || "$TOOL_NAME" == "SubagentTask" || "$TOOL_NAME" == "AgentTask" || "$TOOL_NAME" == "SlashCommand" ]]; then
        STATE_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/state"
        mkdir -p "$STATE_DIR"
        DELEGATED_SESSIONS_FILE="$STATE_DIR/delegated_sessions.txt"
        if [[ -n "$SESSION_ID" ]]; then
          # Use a temporary file to avoid duplicates
          if [[ -f "$DELEGATED_SESSIONS_FILE" ]]; then
            if ! grep -Fxq "$SESSION_ID" "$DELEGATED_SESSIONS_FILE" 2>/dev/null; then
              echo "$SESSION_ID" >> "$DELEGATED_SESSIONS_FILE"
              [[ "$DEBUG_HOOK" == "1" ]] && echo "REGISTERED: Session '$SESSION_ID' for delegation" >> "$DEBUG_FILE"
            fi
          else
            echo "$SESSION_ID" > "$DELEGATED_SESSIONS_FILE"
            [[ "$DEBUG_HOOK" == "1" ]] && echo "REGISTERED: Session '$SESSION_ID' for delegation (new file)" >> "$DEBUG_FILE"
          fi
        fi

        # --- Parallel execution support ---
        # Register concurrent delegation in active_delegations.json if it exists
        # This enables tracking of multiple simultaneous delegations for parallel workflow execution
        ACTIVE_DELEGATIONS_FILE="$STATE_DIR/active_delegations.json"
        if [[ -f "$ACTIVE_DELEGATIONS_FILE" && -n "$SESSION_ID" ]]; then
          # Generate unique delegation ID with timestamp and counter
          TIMESTAMP=$(date +%Y%m%d_%H%M%S)

          # Count existing delegations to generate sequential counter
          DELEGATION_COUNT=$(grep -c '"delegation_id"' "$ACTIVE_DELEGATIONS_FILE" 2>/dev/null || echo "0")
          DELEGATION_COUNT=$((DELEGATION_COUNT + 1))
          DELEGATION_ID="deleg_${TIMESTAMP}_$(printf '%03d' $DELEGATION_COUNT)"

          # Check if jq is available for atomic JSON updates
          if command -v jq &> /dev/null; then
            # Use jq for atomic JSON manipulation with temporary file pattern
            # This ensures thread-safe updates to the delegation state
            CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

            jq --arg did "$DELEGATION_ID" \
               --arg sid "$SESSION_ID" \
               --arg ts "$CURRENT_TIME" \
               '.active_delegations += [{
                 "delegation_id": $did,
                 "session_id": $sid,
                 "status": "active",
                 "started_at": $ts
               }]' "$ACTIVE_DELEGATIONS_FILE" > "${ACTIVE_DELEGATIONS_FILE}.tmp"

            # Atomic replace: only update if jq succeeded
            if [[ $? -eq 0 ]]; then
              mv "${ACTIVE_DELEGATIONS_FILE}.tmp" "$ACTIVE_DELEGATIONS_FILE"
              [[ "$DEBUG_HOOK" == "1" ]] && echo "PARALLEL: Registered delegation '$DELEGATION_ID' for session '$SESSION_ID'" >> "$DEBUG_FILE"
            else
              # jq failed, remove temp file
              rm -f "${ACTIVE_DELEGATIONS_FILE}.tmp"
              [[ "$DEBUG_HOOK" == "1" ]] && echo "PARALLEL: Failed to register delegation (jq error)" >> "$DEBUG_FILE"
            fi
          else
            [[ "$DEBUG_HOOK" == "1" ]] && echo "PARALLEL: jq not available, skipping delegation registration" >> "$DEBUG_FILE"
          fi
        fi
      fi

      exit 0
    fi
  done

  # Pattern allow (delegation-related)
  if [[ "$TOOL_NAME" == *delegate* || "$TOOL_NAME" == *delegation* || "$TOOL_NAME" == Task.* ]]; then
    [[ "$DEBUG_HOOK" == "1" ]] && echo "ALLOWED: Delegation pattern" >> "$DEBUG_FILE"
    exit 0
  fi
fi

shopt -u nocasematch

# --- Check delegation flag file ---
STATE_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/state"
FLAG_FILE="$STATE_DIR/delegated.once"

if [[ -f "$FLAG_FILE" ]]; then
  [[ "$DEBUG_HOOK" == "1" ]] && echo "ALLOWED: Delegation flag found" >> "$DEBUG_FILE"
  rm -f -- "$FLAG_FILE" || true
  exit 0
fi

# --- Check if current session is delegated ---
# If a Task tool was previously invoked in this session, allow nested tools
DELEGATED_SESSIONS_FILE="$STATE_DIR/delegated_sessions.txt"
if [[ -f "$DELEGATED_SESSIONS_FILE" && -n "$SESSION_ID" ]]; then
  if grep -Fxq "$SESSION_ID" "$DELEGATED_SESSIONS_FILE" 2>/dev/null; then
    [[ "$DEBUG_HOOK" == "1" ]] && echo "ALLOWED: Session '$SESSION_ID' is delegated" >> "$DEBUG_FILE"
    exit 0
  fi
fi

# --- Block unknown or non-allowlisted tools ---
[[ "$DEBUG_HOOK" == "1" ]] && echo "BLOCKED: Tool '$TOOL_NAME'" >> "$DEBUG_FILE"

if [[ -z "$TOOL_NAME" ]]; then
  {
    echo "🚫 Tool blocked by delegation policy"
    echo "Tool: <unknown - failed to parse>"
    echo ""
    echo "⚠️ STOP: Do NOT try alternative tools."
    echo "✅ REQUIRED: Use /delegate command immediately:"
    echo "   /delegate <full task description>"
    echo ""
    echo "Debug: export DEBUG_DELEGATION_HOOK=1"
  } >&2
else
  {
    echo "🚫 Tool blocked by delegation policy"
    echo "Tool: $TOOL_NAME"
    echo ""
    echo "⚠️ STOP: Do NOT try alternative tools."
    echo "✅ REQUIRED: Use /delegate command immediately:"
    echo "   /delegate <full task description>"
  } >&2
fi

exit 2
