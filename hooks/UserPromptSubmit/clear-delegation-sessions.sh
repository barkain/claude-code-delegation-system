#!/usr/bin/env bash
# ============================================================================
# UserPromptSubmit Hook: Clear Delegation Sessions
# ============================================================================
# Purpose: Clear stale delegation session state on every user prompt
#
# This hook ensures that delegation state doesn't persist across user
# interactions, forcing explicit /delegate usage for each workflow.
#
# Timing: Fires BEFORE each user message is processed by Claude Code
# ============================================================================

set -euo pipefail

# --- Configuration ---
STATE_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/state"
DELEGATED_SESSIONS_FILE="$STATE_DIR/delegated_sessions.txt"
DEBUG_HOOK="${DEBUG_DELEGATION_HOOK:-0}"
DEBUG_FILE="/tmp/delegation_hook_debug.log"

# --- Debug logging function ---
debug_log() {
  if [[ "$DEBUG_HOOK" == "1" ]]; then
    echo "[UserPromptSubmit] $(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$DEBUG_FILE"
  fi
}

# --- Emergency bypass (for troubleshooting) ---
if [[ "${DELEGATION_HOOK_DISABLE:-0}" == "1" ]]; then
  debug_log "Hook disabled via DELEGATION_HOOK_DISABLE=1"
  exit 0
fi

# --- Main logic: Clear delegation sessions ---
debug_log "Starting session cleanup"

if [[ -f "$DELEGATED_SESSIONS_FILE" ]]; then
  # Attempt to remove the file
  if rm -f "$DELEGATED_SESSIONS_FILE" 2>/dev/null; then
    debug_log "SUCCESS: Cleared delegation sessions file: $DELEGATED_SESSIONS_FILE"
  else
    # Log error but don't fail the hook - Claude Code should continue
    debug_log "WARNING: Failed to remove file (permissions?): $DELEGATED_SESSIONS_FILE"
    # Exit 0 to not block Claude Code
    exit 0
  fi
else
  debug_log "INFO: No delegation sessions file to clear (already clean)"
fi

# --- Clean exit ---
debug_log "Session cleanup completed successfully"
exit 0
