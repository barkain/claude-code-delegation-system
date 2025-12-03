#!/usr/bin/env bash
#
# PreToolUse Hook: validate_task_graph_compliance.sh
#
# Purpose: Enforces task graph execution order by validating Task invocations
#          against the active task graph state file.
#
# Validation:
# - Checks if active_task_graph.json exists
# - Extracts phase ID from Task prompt
# - Validates phase exists in execution plan
# - Validates phase wave matches current_wave
# - BLOCKS execution if validation fails
#
# Exit Codes:
# - 0: Validation passed or no active task graph (allow execution)
# - 1: Validation failed (block execution)

set -euo pipefail

# Get project directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
STATE_DIR="$PROJECT_DIR/.claude/state"
TASK_GRAPH_FILE="$STATE_DIR/active_task_graph.json"

# Debug logging (if enabled)
if [[ "${DEBUG_TASK_GRAPH:-0}" == "1" ]]; then
    exec 2>>/tmp/task_graph_validation_debug.log
    echo "=== Task Graph Validation ===" >&2
    echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >&2
    echo "Project Dir: $PROJECT_DIR" >&2
fi

# Read tool invocation from stdin
TOOL_INPUT=$(cat)

# Extract tool name
TOOL_NAME=$(echo "$TOOL_INPUT" | jq -r '.tool_name // empty')

# Only validate Task tool invocations
if [[ "$TOOL_NAME" != "Task" ]]; then
    [[ "${DEBUG_TASK_GRAPH:-0}" == "1" ]] && echo "Tool: $TOOL_NAME (not Task, skipping validation)" >&2
    exit 0
fi

# Check if task graph enforcement is active
if [[ ! -f "$TASK_GRAPH_FILE" ]]; then
    [[ "${DEBUG_TASK_GRAPH:-0}" == "1" ]] && echo "No active task graph file, allowing execution" >&2
    exit 0
fi

# Extract prompt from Task parameters
TASK_PROMPT=$(echo "$TOOL_INPUT" | jq -r '.parameters.prompt // empty')

if [[ -z "$TASK_PROMPT" ]]; then
    echo "ERROR: Task invocation missing prompt parameter" >&2
    exit 1
fi

# Extract Phase ID from prompt using regex
# Expected format: "Phase ID: phase_X_Y" at start of prompt
PHASE_ID=""
if [[ "$TASK_PROMPT" =~ Phase\ ID:\ (phase_[0-9]+_[0-9]+) ]]; then
    PHASE_ID="${BASH_REMATCH[1]}"
else
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "ERROR: Missing Phase ID marker in Task prompt" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    echo "Task graph enforcement is ACTIVE for this workflow." >&2
    echo "EVERY Task invocation MUST include a Phase ID marker." >&2
    echo "" >&2
    echo "Required format at start of prompt:" >&2
    echo "  Phase ID: phase_X_Y" >&2
    echo "  Agent: agent-name" >&2
    echo "" >&2
    echo "  [Task description...]" >&2
    echo "" >&2
    echo "Example:" >&2
    echo "  Phase ID: phase_0_0" >&2
    echo "  Agent: codebase-context-analyzer" >&2
    echo "" >&2
    echo "  Analyze the authentication system..." >&2
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    exit 1
fi

[[ "${DEBUG_TASK_GRAPH:-0}" == "1" ]] && echo "Extracted Phase ID: $PHASE_ID" >&2

# Load task graph
if ! TASK_GRAPH=$(cat "$TASK_GRAPH_FILE" 2>/dev/null); then
    echo "ERROR: Failed to read task graph file" >&2
    exit 1
fi

# Extract current wave
CURRENT_WAVE=$(echo "$TASK_GRAPH" | jq -r '.current_wave // 0')
[[ "${DEBUG_TASK_GRAPH:-0}" == "1" ]] && echo "Current Wave: $CURRENT_WAVE" >&2

# Find phase in execution plan
PHASE_WAVE=$(echo "$TASK_GRAPH" | jq -r --arg phase_id "$PHASE_ID" '
  .execution_plan.waves[] |
  select(.phases[] | .phase_id == $phase_id) |
  .wave_id
' | head -n1)

if [[ -z "$PHASE_WAVE" ]]; then
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "ERROR: Phase not found in execution plan" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    echo "Phase ID: $PHASE_ID" >&2
    echo "" >&2
    echo "This phase ID does not exist in the orchestrator's execution plan." >&2
    echo "" >&2
    echo "Valid phase IDs in current task graph:" >&2
    echo "$TASK_GRAPH" | jq -r '.execution_plan.waves[].phases[].phase_id' | sed 's/^/  - /' >&2
    echo "" >&2
    echo "Please use one of the valid phase IDs from the execution plan." >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    exit 1
fi

[[ "${DEBUG_TASK_GRAPH:-0}" == "1" ]] && echo "Phase Wave: $PHASE_WAVE" >&2

# Validate wave order
if [[ "$PHASE_WAVE" -gt "$CURRENT_WAVE" ]]; then
    # Get wave status
    WAVE_STATUS=$(echo "$TASK_GRAPH" | jq -r --arg wave "$CURRENT_WAVE" '.wave_status[$wave].status // "unknown"')

    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "ERROR: Wave order violation detected" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    echo "Current wave: $CURRENT_WAVE (status: $WAVE_STATUS)" >&2
    echo "Attempted phase: $PHASE_ID (wave $PHASE_WAVE)" >&2
    echo "" >&2
    echo "Cannot start Wave $PHASE_WAVE tasks while Wave $CURRENT_WAVE is incomplete." >&2
    echo "" >&2
    echo "You MUST:" >&2
    echo "  1. Complete ALL phases in Wave $CURRENT_WAVE" >&2
    echo "  2. Wait for automatic wave progression" >&2
    echo "  3. Then execute Wave $PHASE_WAVE phases" >&2
    echo "" >&2
    echo "Wave $CURRENT_WAVE phases:" >&2
    echo "$TASK_GRAPH" | jq -r --arg wave "$CURRENT_WAVE" '
      .execution_plan.waves[] |
      select(.wave_id == ($wave | tonumber)) |
      .phases[] |
      "  - \(.phase_id): \(.description) (status: \($status // "pending"))"
    ' >&2
    echo "" >&2
    echo "Check .claude/state/active_task_graph.json for full wave status." >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    exit 1
fi

if [[ "$PHASE_WAVE" -lt "$CURRENT_WAVE" ]]; then
    # Attempting to execute past wave phase - allow with warning
    echo "" >&2
    echo "⚠️  WARNING: Executing phase from past wave" >&2
    echo "" >&2
    echo "Current wave: $CURRENT_WAVE" >&2
    echo "Phase: $PHASE_ID (wave $PHASE_WAVE)" >&2
    echo "" >&2
    echo "This may be a retry or remediation. Allowing execution." >&2
    echo "Compliance will be logged as non-compliant." >&2
    echo "" >&2
fi

# Validation passed
[[ "${DEBUG_TASK_GRAPH:-0}" == "1" ]] && echo "Validation PASSED - allowing execution" >&2

# Log compliance event
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
COMPLIANT=$( [[ "$PHASE_WAVE" -eq "$CURRENT_WAVE" ]] && echo "true" || echo "false" )

# Update compliance log in task graph
TEMP_FILE=$(mktemp)
jq --arg timestamp "$TIMESTAMP" \
   --arg phase_id "$PHASE_ID" \
   --arg wave_id "$PHASE_WAVE" \
   --argjson compliant "$COMPLIANT" \
   '.compliance_log += [{
     timestamp: $timestamp,
     event: "phase_validation",
     phase_id: $phase_id,
     wave_id: ($wave_id | tonumber),
     compliant: $compliant
   }]' "$TASK_GRAPH_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$TASK_GRAPH_FILE"

exit 0
