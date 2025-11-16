#!/usr/bin/env bash
#
# execution_logger.sh - PostToolUse Hook for Execution Logging
#
# PURPOSE:
#   Logs tool execution events to .claude/state/execution_log.jsonl
#   Captures tool_name, status, session_id, workflow_id for observability
#
# USAGE:
#   Called automatically by Claude Code after each tool invocation
#   Environment variables provided by Claude Code runtime
#
# ENVIRONMENT VARIABLES (provided by Claude Code):
#   CLAUDE_SESSION_ID - Current session identifier
#   CLAUDE_TOOL_NAME - Name of tool that was executed
#   CLAUDE_TOOL_STATUS - Tool execution status (success/error)
#   CLAUDE_WORKFLOW_ID - (Optional) Workflow identifier if in workflow context
#
# EXIT CODES:
#   Always exits 0 - logging failures should not block workflow
#
# PERFORMANCE:
#   Target: <50ms execution time
#   Non-blocking: Failures logged to stderr, do not interrupt tool execution
#
# TEST COMMAND:
#   CLAUDE_SESSION_ID=test_sess_001 CLAUDE_TOOL_NAME=Read CLAUDE_TOOL_STATUS=success \
#     ./hooks/PostToolUse/execution_logger.sh
#
# DEBUG MODE:
#   export DEBUG_DELEGATION_HOOK=1
#   Logs debug output to /tmp/delegation_hook_debug.log

set -o pipefail

# ============================================================================
# STEP A.2.1: Shell initialization and header (COMPLETE)
# ============================================================================

# ============================================================================
# STEP A.2.2: Environment variable extraction and validation
# ============================================================================

# Debug logging function
debug_log() {
    if [[ "${DEBUG_DELEGATION_HOOK:-0}" == "1" ]]; then
        local log_file="/tmp/delegation_hook_debug.log"
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [execution_logger] $*" >> "$log_file"
    fi
}

debug_log "START execution_logger.sh"

# Extract required environment variables
SESSION_ID="${CLAUDE_SESSION_ID:-}"
TOOL_NAME="${CLAUDE_TOOL_NAME:-}"
TOOL_STATUS="${CLAUDE_TOOL_STATUS:-}"

# Extract optional workflow context
WORKFLOW_ID="${CLAUDE_WORKFLOW_ID:-}"

debug_log "Extracted variables: SESSION_ID=$SESSION_ID, TOOL_NAME=$TOOL_NAME, TOOL_STATUS=$TOOL_STATUS, WORKFLOW_ID=$WORKFLOW_ID"

# Validate required variables
if [[ -z "$SESSION_ID" ]]; then
    debug_log "ERROR: CLAUDE_SESSION_ID not set, skipping log"
    exit 0
fi

if [[ -z "$TOOL_NAME" ]]; then
    debug_log "ERROR: CLAUDE_TOOL_NAME not set, skipping log"
    exit 0
fi

if [[ -z "$TOOL_STATUS" ]]; then
    debug_log "ERROR: CLAUDE_TOOL_STATUS not set, skipping log"
    exit 0
fi

debug_log "Validation passed for required variables"

# ============================================================================
# STEP A.2.3: Python module invocation
# ============================================================================

# Determine project root (where this script is located relative to project)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

debug_log "Project root: $PROJECT_ROOT"

# Locate Python module
PYTHON_MODULE="$PROJECT_ROOT/hooks/lib/log_writer.py"

if [[ ! -f "$PYTHON_MODULE" ]]; then
    debug_log "ERROR: Python module not found at $PYTHON_MODULE"
    exit 0
fi

debug_log "Python module found: $PYTHON_MODULE"

# Build Python command arguments
# Python module CLI: write --workflow-id WF --event-type TYPE --status STATUS [--phase-id] [--agent]
# We use:
#   - workflow-id: Use WORKFLOW_ID if available, otherwise SESSION_ID
#   - event-type: "tool_execution"
#   - status: Pass through TOOL_STATUS
#   - agent: Use TOOL_NAME (tool name acts as "agent" that executed)
EFFECTIVE_WORKFLOW_ID="${WORKFLOW_ID:-$SESSION_ID}"

PYTHON_CMD=(
    python3
    "$PYTHON_MODULE"
    write
    --workflow-id "$EFFECTIVE_WORKFLOW_ID"
    --event-type "tool_execution"
    --status "$TOOL_STATUS"
    --agent "$TOOL_NAME"
)

debug_log "Using workflow_id: $EFFECTIVE_WORKFLOW_ID, agent: $TOOL_NAME"

debug_log "Executing Python command: ${PYTHON_CMD[*]}"

# Execute Python module and capture output
PYTHON_OUTPUT=""
PYTHON_EXIT_CODE=0

if PYTHON_OUTPUT=$("${PYTHON_CMD[@]}" 2>&1); then
    PYTHON_EXIT_CODE=0
    debug_log "Python module succeeded"
else
    PYTHON_EXIT_CODE=$?
    debug_log "ERROR: Python module failed with exit code $PYTHON_EXIT_CODE"
    debug_log "Python output: $PYTHON_OUTPUT"
    exit 0
fi

# ============================================================================
# STEP A.2.4: JSON output capture and validation
# ============================================================================

debug_log "Python output: $PYTHON_OUTPUT"

# Validate JSON output (basic check - does it start with { and end with }?)
if [[ "$PYTHON_OUTPUT" =~ ^\{.*\}$ ]]; then
    debug_log "JSON output appears valid"

    # Optional: Additional validation with python -m json.tool (if available)
    if command -v python3 &> /dev/null; then
        if echo "$PYTHON_OUTPUT" | python3 -m json.tool > /dev/null 2>&1; then
            debug_log "JSON validation passed"
        else
            debug_log "WARNING: JSON validation failed, but continuing"
        fi
    fi
else
    debug_log "WARNING: Python output does not appear to be valid JSON"
    debug_log "Output was: $PYTHON_OUTPUT"
    # Don't fail - log the issue but continue
fi

debug_log "END execution_logger.sh (success)"

# ============================================================================
# STEP A.2.5: Exit successfully
# ============================================================================

# Always exit 0 - logging failures should not block workflow
exit 0
