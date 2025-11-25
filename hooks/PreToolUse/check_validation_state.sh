#!/bin/bash
# check_validation_state.sh - PreToolUse hook to enforce validation decisions
# Blocks delegation tools if previous phase validation FAILED

set -euo pipefail

# Configuration
VALIDATION_STATE_DIR=".claude/state/validation"
DELEGATION_TOOLS=("Task" "SubagentTask" "AgentTask")

# Parse hook input (JSON from stdin)
INPUT_JSON=$(cat)
TOOL_NAME=$(echo "${INPUT_JSON}" | jq -r '.tool_name // .tool.name // ""')

# Only check for delegation tools
is_delegation_tool() {
    local tool="$1"
    for dt in "${DELEGATION_TOOLS[@]}"; do
        [[ "${tool}" == "${dt}" ]] && return 0
    done
    return 1
}

# Check bypass
if [[ "${VALIDATION_GATE_BYPASS:-0}" == "1" ]]; then
    echo "⚠️  Validation gate bypassed via VALIDATION_GATE_BYPASS=1" >&2
    exit 0
fi

# Skip if not a delegation tool
if ! is_delegation_tool "${TOOL_NAME}"; then
    exit 0
fi

# Find most recent validation state file
find_latest_validation() {
    if [[ ! -d "${VALIDATION_STATE_DIR}" ]]; then
        echo ""
        return
    fi

    # Find most recent phase_*.json file
    local latest=$(find "${VALIDATION_STATE_DIR}" -name "phase_*.json" -type f 2>/dev/null | \
        xargs ls -t 2>/dev/null | head -n 1)
    echo "${latest}"
}

# Main validation check
main() {
    local latest_file=$(find_latest_validation)

    # No validation state = allow (first phase)
    if [[ -z "${latest_file}" ]]; then
        exit 0
    fi

    # Check file age (only consider recent validations, < 1 hour)
    local file_age=$(($(date +%s) - $(stat -f %m "${latest_file}" 2>/dev/null || stat -c %Y "${latest_file}" 2>/dev/null || echo 0)))
    if [[ ${file_age} -gt 3600 ]]; then
        # Stale validation, ignore
        exit 0
    fi

    # Parse validation state
    local validation_status=$(jq -r '.validation_status // "UNKNOWN"' "${latest_file}" 2>/dev/null)
    local decision=$(jq -r '.rule_results[0].details.natural_language_decision // .rule_results[0].details.validation_decision // "UNKNOWN"' "${latest_file}" 2>/dev/null)
    local reason=$(jq -r '.rule_results[0].message // "No details available"' "${latest_file}" 2>/dev/null)
    local phase_id=$(jq -r '.phase_id // "unknown"' "${latest_file}" 2>/dev/null)

    # Check if validation passed
    if [[ "${validation_status}" == "PASSED" ]] || [[ "${decision}" == "CONTINUE" ]]; then
        # Clear the validation file after successful check (one-time gate)
        # This prevents blocking subsequent independent delegations
        rm -f "${latest_file}" 2>/dev/null || true
        exit 0
    fi

    # Validation FAILED - block execution
    cat >&2 <<EOF

🚫 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   VALIDATION GATE: Previous phase validation FAILED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Phase:    ${phase_id}
Decision: ${decision}
Status:   ${validation_status}

Reason:
${reason}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Action required:
  • Review the validation feedback above
  • Fix the issues identified in the previous phase
  • Re-run the failed phase before proceeding

To clear this gate after fixing:
  rm ${latest_file}

To bypass (not recommended):
  export VALIDATION_GATE_BYPASS=1

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

    exit 1
}

main
