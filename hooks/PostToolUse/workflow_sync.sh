#!/usr/bin/env bash

# Workflow State Synchronization Hook
# Triggers after Task tool completes to update workflow state automatically
# Marks phases as completed and advances workflow to next phase

set -euo pipefail

# Debug mode support
DEBUG_MODE="${DEBUG_HOOK:-0}"

# Get project directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
WORKFLOW_STATE="$PROJECT_DIR/.claude/state/workflow.json"

# Debug logging function
debug_log() {
    if [ "$DEBUG_MODE" = "1" ]; then
        echo "[DEBUG workflow_sync] $1" >&2
    fi
}

# Parse JSON input from stdin
parse_json_input() {
    local json_input
    json_input=$(cat)

    debug_log "Received JSON input"

    # Extract tool_name using Python for robust JSON parsing
    local tool_name
    tool_name=$(printf '%s' "$json_input" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('tool_name', ''))
except:
    print('')
    sys.exit(1)
" 2>/dev/null)

    if [ -z "$tool_name" ]; then
        debug_log "Failed to parse JSON or no tool_name found"
        exit 0
    fi

    debug_log "Tool name: $tool_name"
    echo "$tool_name"
}

# Update workflow phase status
update_workflow_phase() {
    debug_log "Attempting to update workflow phase"

    # Check if workflow state exists
    if [ ! -f "$WORKFLOW_STATE" ]; then
        debug_log "No active workflow found at $WORKFLOW_STATE"
        exit 0
    fi

    debug_log "Found workflow state file"

    # Get current phase ID from workflow.json
    local current_phase
    current_phase=$(python3 -c "
import json, sys
try:
    with open('$WORKFLOW_STATE') as f:
        workflow = json.load(f)
        print(workflow.get('current_phase', ''))
except Exception as e:
    print('', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null)

    if [ -z "$current_phase" ] || [ "$current_phase" = "None" ]; then
        debug_log "No current phase to update"
        exit 0
    fi

    debug_log "Current phase: $current_phase"

    # Call workflow_state.py to mark phase as completed
    # The Python module handles:
    # - Marking current phase as completed
    # - Auto-advancing to next phase
    # - Updating workflow status
    # - Regenerating WORKFLOW_STATUS.md

    local utils_dir="$PROJECT_DIR/utils"
    if [ ! -f "$utils_dir/workflow_state.py" ]; then
        debug_log "Warning: workflow_state.py not found at $utils_dir"
        exit 0
    fi

    debug_log "Calling workflow_state.py to update phase"

    # Call Python module to update phase status
    python3 - <<EOF
import sys
sys.path.insert(0, '$utils_dir')

try:
    from workflow_state import update_phase_status

    # Mark current phase as completed
    # workflow_state.py handles auto-advancement
    update_phase_status(
        phase_id='$current_phase',
        status='completed',
        deliverables=None,  # Agents should write deliverables themselves
        context_for_next=None  # Agents should write context themselves
    )

except Exception as e:
    import logging
    logging.error("Failed to update workflow phase: %s", e, exc_info=True)
    sys.exit(1)
EOF

    local update_result=$?

    if [ $update_result -eq 0 ]; then
        debug_log "Successfully updated workflow phase"
    else
        debug_log "Failed to update workflow phase (exit code: $update_result)"
    fi

    exit $update_result
}

# Main function
main() {
    debug_log "Workflow sync hook started"

    # Parse JSON input from stdin
    local tool_name
    tool_name=$(parse_json_input)

    # Only process Task tool completions (agent/subagent finished)
    if [ "$tool_name" != "Task" ]; then
        debug_log "Not a Task tool, skipping (tool: $tool_name)"
        exit 0
    fi

    debug_log "Task tool completed, checking for workflow state"

    # Update workflow phase status
    update_workflow_phase
}

# Run main function
main
