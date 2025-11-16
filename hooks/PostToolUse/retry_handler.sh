#!/usr/bin/env bash
#
# retry_handler.sh - PostToolUse Hook for Retry Budget Management
#
# Purpose:
#   Monitors tool execution results and manages retry budgets for failed operations.
#   Integrates with retry_manager.py to track failures, manage budgets, and provide
#   actionable feedback to users about retry limits.
#
# Hook Lifecycle:
#   - Triggered after EVERY tool execution (success or failure)
#   - Extracts tool name, status, and error details from environment
#   - Delegates budget management to Python module
#   - Non-blocking: Must complete in <100ms
#
# Environment Variables (provided by Claude Code):
#   CLAUDE_SESSION_ID - Unique session identifier
#   CLAUDE_TOOL_NAME - Name of executed tool (e.g., "Read", "Bash", "Edit")
#   CLAUDE_TOOL_STATUS - Execution result ("success" or "error")
#   CLAUDE_TOOL_ERROR - Error message (only present if status=error)
#
# Debug Mode:
#   export DEBUG_DELEGATION_HOOK=1
#   tail -f /tmp/delegation_hook_debug.log
#
# Exit Codes:
#   0 - Success (budget updated or no action needed)
#   1 - Missing required environment variables
#   2 - Python module execution failed
#   3 - Invalid tool status value

set -euo pipefail

# -----------------------------------------------------------------------------
# Step A.1.1: Shell initialization complete (shebang + header)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Step A.1.2: Environment Variable Validation
# -----------------------------------------------------------------------------

# Debug logging function
debug_log() {
    if [[ "${DEBUG_DELEGATION_HOOK:-0}" == "1" ]]; then
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[${timestamp}] [retry_handler] $*" >> /tmp/delegation_hook_debug.log
    fi
}

debug_log "=== PostToolUse Hook: retry_handler.sh START ==="

# Validate required environment variables
if [[ -z "${CLAUDE_SESSION_ID:-}" ]]; then
    debug_log "ERROR: CLAUDE_SESSION_ID not set"
    echo "Error: CLAUDE_SESSION_ID environment variable is required" >&2
    exit 1
fi

if [[ -z "${CLAUDE_TOOL_NAME:-}" ]]; then
    debug_log "ERROR: CLAUDE_TOOL_NAME not set"
    echo "Error: CLAUDE_TOOL_NAME environment variable is required" >&2
    exit 1
fi

if [[ -z "${CLAUDE_TOOL_STATUS:-}" ]]; then
    debug_log "ERROR: CLAUDE_TOOL_STATUS not set"
    echo "Error: CLAUDE_TOOL_STATUS environment variable is required" >&2
    exit 1
fi

# Validate tool status value
if [[ "${CLAUDE_TOOL_STATUS}" != "success" && "${CLAUDE_TOOL_STATUS}" != "error" ]]; then
    debug_log "ERROR: Invalid CLAUDE_TOOL_STATUS value: ${CLAUDE_TOOL_STATUS}"
    echo "Error: CLAUDE_TOOL_STATUS must be 'success' or 'error', got: ${CLAUDE_TOOL_STATUS}" >&2
    exit 3
fi

debug_log "Environment validation passed:"
debug_log "  SESSION_ID: ${CLAUDE_SESSION_ID}"
debug_log "  TOOL_NAME: ${CLAUDE_TOOL_NAME}"
debug_log "  TOOL_STATUS: ${CLAUDE_TOOL_STATUS}"

# Extract optional error message (only present on failures)
CLAUDE_TOOL_ERROR="${CLAUDE_TOOL_ERROR:-}"
if [[ -n "${CLAUDE_TOOL_ERROR}" ]]; then
    debug_log "  TOOL_ERROR: ${CLAUDE_TOOL_ERROR}"
fi

# -----------------------------------------------------------------------------
# Step A.1.3: Python Module Invocation
# -----------------------------------------------------------------------------

# Construct path to Python retry manager module
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RETRY_MANAGER="${SCRIPT_DIR}/../lib/retry_manager.py"

# Verify Python module exists
if [[ ! -f "${RETRY_MANAGER}" ]]; then
    debug_log "ERROR: Python module not found at: ${RETRY_MANAGER}"
    echo "Error: retry_manager.py not found at: ${RETRY_MANAGER}" >&2
    exit 2
fi

debug_log "Invoking Python module: ${RETRY_MANAGER}"

# Only track failures (skip successful tool executions for performance)
if [[ "${CLAUDE_TOOL_STATUS}" != "error" ]]; then
    debug_log "Tool succeeded - no retry tracking needed"
    exit 0
fi

# Construct phase_id from session and tool name
# Format: session_TOOLNAME (e.g., sess_abc123_Read)
PHASE_ID="${CLAUDE_SESSION_ID}_${CLAUDE_TOOL_NAME}"

# Add error type classification (basic heuristic)
ERROR_TYPE="unknown"
if [[ "${CLAUDE_TOOL_ERROR}" =~ "not found"|"does not exist"|"no such file" ]]; then
    ERROR_TYPE="permanent"
elif [[ "${CLAUDE_TOOL_ERROR}" =~ "timeout"|"connection"|"network"|"temporary" ]]; then
    ERROR_TYPE="transient"
fi

debug_log "Phase ID: ${PHASE_ID}"
debug_log "Error type: ${ERROR_TYPE}"

# Step 1: Check if phase exists in state file
# We need to initialize before recording failures
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_FILE="${PROJECT_DIR}/.claude/state/retry_budgets.json"
PHASE_EXISTS=false

debug_log "State file location: ${STATE_FILE}"

if [[ -f "${STATE_FILE}" ]]; then
    # Check if phase_id exists in the retries object
    if grep -q "\"${PHASE_ID}\"" "${STATE_FILE}" 2>/dev/null; then
        PHASE_EXISTS=true
        debug_log "Phase exists in state file"
    fi
fi

# Step 2: Initialize phase if it doesn't exist
if [[ "${PHASE_EXISTS}" == "false" ]]; then
    debug_log "Initializing new phase: ${PHASE_ID}"

    # Extract workflow_id and agent from environment
    # CLAUDE_WORKFLOW_ID may be set by orchestrator, fallback to session ID
    WORKFLOW_ID="${CLAUDE_WORKFLOW_ID:-${CLAUDE_SESSION_ID}}"

    # CLAUDE_AGENT_NAME may be set by orchestrator, fallback to "main"
    AGENT_NAME="${CLAUDE_AGENT_NAME:-main}"

    debug_log "Workflow ID: ${WORKFLOW_ID}"
    debug_log "Agent name: ${AGENT_NAME}"

    INIT_OUTPUT=""
    if INIT_OUTPUT=$(python3 "${RETRY_MANAGER}" init \
        --phase-id "${PHASE_ID}" \
        --workflow-id "${WORKFLOW_ID}" \
        --agent "${AGENT_NAME}" 2>&1); then
        debug_log "Phase initialized successfully"
    else
        debug_log "ERROR: Failed to initialize phase: ${INIT_OUTPUT}"
        echo "Warning: Failed to initialize retry tracking for ${PHASE_ID}" >&2
        exit 2
    fi
fi

# Step 3: Record the failure
PYTHON_ARGS=(
    "record-failure"
    "--phase-id" "${PHASE_ID}"
    "--error-type" "${ERROR_TYPE}"
)

# Add optional error message if present
if [[ -n "${CLAUDE_TOOL_ERROR}" ]]; then
    PYTHON_ARGS+=("--error-message" "${CLAUDE_TOOL_ERROR}")
fi

debug_log "Recording failure with args: ${PYTHON_ARGS[*]}"

# -----------------------------------------------------------------------------
# Step A.1.4: Error Logging and Debugging
# -----------------------------------------------------------------------------

# Execute Python module and capture output
PYTHON_EXIT_CODE=0
PYTHON_STDERR=""

if PYTHON_STDERR=$(python3 "${RETRY_MANAGER}" "${PYTHON_ARGS[@]}" 2>&1 >/dev/null); then
    debug_log "Python module executed successfully"
else
    PYTHON_EXIT_CODE=$?
    debug_log "ERROR: Python module failed with exit code: ${PYTHON_EXIT_CODE}"
    debug_log "STDERR: ${PYTHON_STDERR}"

    # Log error but don't block hook execution (graceful degradation)
    echo "Warning: retry_manager.py failed (exit code ${PYTHON_EXIT_CODE})" >&2
    if [[ -n "${PYTHON_STDERR}" ]]; then
        echo "Details: ${PYTHON_STDERR}" >&2
    fi

    # Exit with error code for monitoring/alerting
    exit 2
fi

# Log any warnings/info from Python module
if [[ -n "${PYTHON_STDERR}" ]]; then
    debug_log "Python module output: ${PYTHON_STDERR}"
fi

debug_log "=== PostToolUse Hook: retry_handler.sh END (success) ==="

# -----------------------------------------------------------------------------
# Step A.1.5: Executable and Self-Test Documentation
# -----------------------------------------------------------------------------

# Self-test commands (run manually for verification):
#
# Test 1: Failed tool execution (should record failure)
#   export CLAUDE_SESSION_ID="test_session_123"
#   export CLAUDE_TOOL_NAME="Read"
#   export CLAUDE_TOOL_STATUS="error"
#   export CLAUDE_TOOL_ERROR="File not found: /nonexistent/path"
#   export DEBUG_DELEGATION_HOOK=1
#   ./hooks/PostToolUse/retry_handler.sh
#   echo "Exit code: $?"
#   tail -20 /tmp/delegation_hook_debug.log
#   cat .claude/state/retry_budgets.json
#
# Test 2: Successful tool execution (should skip tracking)
#   export CLAUDE_SESSION_ID="test_session_456"
#   export CLAUDE_TOOL_NAME="Write"
#   export CLAUDE_TOOL_STATUS="success"
#   unset CLAUDE_TOOL_ERROR
#   export DEBUG_DELEGATION_HOOK=1
#   ./hooks/PostToolUse/retry_handler.sh
#   echo "Exit code: $?"
#
# Expected behavior:
#   Test 1:
#     - Exit code 0 (success)
#     - Debug log shows environment validation, Python invocation, error classification
#     - Budget file updated at .claude/state/retry_budgets.json
#     - Phase entry: test_session_123_Read with attempt_count=1, error_type=permanent
#   Test 2:
#     - Exit code 0 (success)
#     - Debug log shows "Tool succeeded - no retry tracking needed"
#     - No Python module invocation (performance optimization)
#
# Shellcheck validation:
#   shellcheck hooks/PostToolUse/retry_handler.sh
#

exit 0
