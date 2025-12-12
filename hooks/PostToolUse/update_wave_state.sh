#!/usr/bin/env bash
#
# PostToolUse Hook: update_wave_state.sh
#
# Purpose: Automatically advances waves when all phases in current wave complete
#
# Actions:
# - Extracts phase ID from Task result
# - Marks phase as "completed" with timestamp
# - Counts completed phases in current wave
# - If ALL wave phases complete:
#   - Marks wave as "completed"
#   - Increments current_wave
#   - Outputs success message
# - If workflow complete (current_wave == total_waves):
#   - Marks status = "completed"
#
# Exit Code: Always 0 (informational only)

set -euo pipefail

# Get project directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
STATE_DIR="$PROJECT_DIR/.claude/state"
TASK_GRAPH_FILE="$STATE_DIR/active_task_graph.json"
LOCK_FILE="$STATE_DIR/.update_wave.lock"

# Debug logging (if enabled)
if [[ "${DEBUG_TASK_GRAPH:-0}" == "1" ]]; then
    exec 2>>/tmp/task_graph_validation_debug.log
    echo "=== Wave State Update ===" >&2
    echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >&2
fi

# Ensure lock file directory exists
mkdir -p "$STATE_DIR"

# Cleanup trap for lock file
trap 'rm -f "$LOCK_FILE"' EXIT

# Read tool result from stdin
TOOL_RESULT=$(cat)

# Extract tool name (try .tool_name first, fallback to .tool)
TOOL_NAME=$(echo "$TOOL_RESULT" | jq -r '.tool_name // .tool // empty')

# Only process Task tool results
if [[ "$TOOL_NAME" != "Task" ]]; then
    [[ "${DEBUG_TASK_GRAPH:-0}" == "1" ]] && echo "Tool: $TOOL_NAME (not Task, skipping)" >&2
    exit 0
fi

# Check if task graph enforcement is active
if [[ ! -f "$TASK_GRAPH_FILE" ]]; then
    [[ "${DEBUG_TASK_GRAPH:-0}" == "1" ]] && echo "No active task graph file" >&2
    exit 0
fi

# Extract parameters from tool result
TASK_PARAMS=$(echo "$TOOL_RESULT" | jq -r '.parameters // {}')
TASK_PROMPT=$(echo "$TASK_PARAMS" | jq -r '.prompt // empty')

if [[ -z "$TASK_PROMPT" ]]; then
    [[ "${DEBUG_TASK_GRAPH:-0}" == "1" ]] && echo "No prompt in Task result" >&2
    exit 0
fi

# Extract Phase ID from prompt
PHASE_ID=""
if [[ "$TASK_PROMPT" =~ Phase\ ID:\ (phase_[0-9]+_[0-9]+) ]]; then
    PHASE_ID="${BASH_REMATCH[1]}"
else
    [[ "${DEBUG_TASK_GRAPH:-0}" == "1" ]] && echo "No Phase ID marker in prompt" >&2
    exit 0
fi

[[ "${DEBUG_TASK_GRAPH:-0}" == "1" ]] && echo "Processing Phase ID: $PHASE_ID" >&2

# === BEGIN CRITICAL SECTION (flock protected) ===
(
    # Acquire exclusive lock with 5 second timeout
    if ! flock -x -w 5 200; then
        echo "ERROR: Failed to acquire lock on $LOCK_FILE (timeout after 5s)" >&2
        exit 1
    fi

    # Load current task graph
    TASK_GRAPH=$(cat "$TASK_GRAPH_FILE")
    CURRENT_WAVE=$(echo "$TASK_GRAPH" | jq -r '.current_wave // 0')
    TOTAL_WAVES=$(echo "$TASK_GRAPH" | jq -r '.execution_plan.total_waves // 0')

# Get phase wave
PHASE_WAVE=$(echo "$TASK_GRAPH" | jq -r --arg phase_id "$PHASE_ID" '
  .execution_plan.waves[] |
  select(.phases[] | .phase_id == $phase_id) |
  .wave_id
' | head -n1)

if [[ -z "$PHASE_WAVE" ]]; then
    [[ "${DEBUG_TASK_GRAPH:-0}" == "1" ]] && echo "Phase not found in execution plan" >&2
    exit 0
fi

# Update phase status
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TEMP_FILE=$(mktemp)

jq --arg phase_id "$PHASE_ID" \
   --arg timestamp "$TIMESTAMP" \
   '
   # Initialize phase_status if not exists
   if .phase_status == null then .phase_status = {} else . end |

   # Update phase status
   .phase_status[$phase_id] = {
     status: "completed",
     completed_at: $timestamp
   } |

   # Add compliance log entry
   .compliance_log += [{
     timestamp: $timestamp,
     event: "phase_completed",
     phase_id: $phase_id,
     compliant: true
   }]
   ' "$TASK_GRAPH_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$TASK_GRAPH_FILE"

[[ "${DEBUG_TASK_GRAPH:-0}" == "1" ]] && echo "Marked phase $PHASE_ID as completed" >&2

# Reload task graph to get updated state
TASK_GRAPH=$(cat "$TASK_GRAPH_FILE")

# Count completed phases in current wave
WAVE_PHASES=$(echo "$TASK_GRAPH" | jq --arg wave "$CURRENT_WAVE" '
  [.execution_plan.waves[] | select(.wave_id == ($wave | tonumber)) | .phases[].phase_id]
' )

COMPLETED_COUNT=$(echo "$TASK_GRAPH" | jq --argjson wave_phases "$WAVE_PHASES" '
  [.phase_status | to_entries[] |
   select(.key as $pid | $wave_phases | map(. == $pid) | any) |
   select(.value.status == "completed")
  ] | length
')

TOTAL_PHASES=$(echo "$WAVE_PHASES" | jq 'length')

[[ "${DEBUG_TASK_GRAPH:-0}" == "1" ]] && echo "Wave $CURRENT_WAVE: $COMPLETED_COUNT/$TOTAL_PHASES phases completed" >&2

# Check if all wave phases are complete
if [[ "$COMPLETED_COUNT" -eq "$TOTAL_PHASES" ]]; then
    echo "" >&2
    echo "✅ Wave $CURRENT_WAVE complete. All $TOTAL_PHASES phases finished." >&2

    # Update wave status and advance to next wave
    NEXT_WAVE=$((CURRENT_WAVE + 1))

    jq --arg wave "$CURRENT_WAVE" \
       --arg next_wave "$NEXT_WAVE" \
       --arg timestamp "$TIMESTAMP" \
       '
       # Initialize wave_status if not exists
       if .wave_status == null then .wave_status = {} else . end |

       # Mark current wave as completed
       .wave_status[$wave] = {
         status: "completed",
         completed_at: $timestamp
       } |

       # Advance to next wave if not at end
       if ($next_wave | tonumber) < .execution_plan.total_waves then
         .current_wave = ($next_wave | tonumber) |
         .wave_status[$next_wave] = {
           status: "in_progress",
           started_at: $timestamp
         }
       else
         # Workflow complete
         .status = "completed" |
         .completed_at = $timestamp
       end
       ' "$TASK_GRAPH_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$TASK_GRAPH_FILE"

    if [[ "$NEXT_WAVE" -lt "$TOTAL_WAVES" ]]; then
        echo "📊 Advanced to Wave $NEXT_WAVE." >&2
        echo "" >&2

        # Show next wave phases
        NEXT_WAVE_PHASES=$(echo "$TASK_GRAPH" | jq -r --arg wave "$NEXT_WAVE" '
          .execution_plan.waves[] |
          select(.wave_id == ($wave | tonumber)) |
          .phases[] |
          "  - \(.phase_id): \(.description)"
        ')

        echo "Next Wave Phases:" >&2
        echo "$NEXT_WAVE_PHASES" >&2
        echo "" >&2
    else
        echo "🎉 Workflow complete! All waves finished." >&2
        echo "" >&2
    fi
fi

) 200>"$LOCK_FILE"
# === END CRITICAL SECTION ===

exit 0
