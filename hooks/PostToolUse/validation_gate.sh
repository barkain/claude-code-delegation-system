#!/bin/bash
################################################################################
# PostToolUse Hook: Validation Gate
#
# Purpose: Trigger validation checks after tool execution with workflow control
# Hook Type: PostToolUse (runs after every tool invocation)
# Exit Codes:
#   0 - CONTINUE: Phase complete, proceed to next phase
#   1 - REPEAT: Phase needs improvement, retry with feedback
#   2 - ABORT: Critical failure, halt workflow
#   3 - NOT_APPLICABLE: Validation inconclusive, continue with warning
#
# Input: JSON via stdin from Claude Code hook system
# Output: Natural language validation with decision headers
#
# Author: Claude Code Delegation System
# Version: 2.0.0-phase4 (Workflow Control Implementation)
################################################################################

set -euo pipefail

# Configuration
# Guard against readonly variable redefinition when script is sourced multiple times
if [[ -z "${SCRIPT_DIR:-}" ]]; then
    readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
fi
if [[ -z "${VALIDATION_STATE_DIR:-}" ]]; then
    readonly VALIDATION_STATE_DIR="${PROJECT_ROOT}/.claude/state/validation"
fi
if [[ -z "${LOG_FILE:-}" ]]; then
    readonly LOG_FILE="${VALIDATION_STATE_DIR}/gate_invocations.log"
fi

################################################################################
# Logging Functions
################################################################################

# Log a message with timestamp and event type
# Args:
#   $1: Event type (TRIGGER, VALIDATION, SKIP, ERROR)
#   $2: Tool name
#   $3: Details message
log_event() {
    local event_type="$1"
    local tool_name="$2"
    local details="$3"
    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    # Ensure log directory exists
    mkdir -p "${VALIDATION_STATE_DIR}"

    # Log format: [TIMESTAMP] [EVENT_TYPE] [TOOL_NAME] [DETAILS]
    echo "[${timestamp}] [${event_type}] [${tool_name}] ${details}" >> "${LOG_FILE}"
}

################################################################################
# State Persistence Functions
################################################################################

# Persist validation state to JSON file
# Implements atomic file updates using temp file pattern
# Args:
#   $1: workflow_id - Workflow identifier
#   $2: phase_id - Phase identifier
#   $3: session_id - Session identifier
#   $4: status - Validation status (PASSED/FAILED)
#   $5: rules_executed - Number of rules executed
#   $6: results_per_rule - JSON array of rule results
# Returns:
#   0 on success, 1 on error (errors are logged but don't fail the hook)
persist_validation_state() {
    local workflow_id="$1"
    local phase_id="$2"
    local session_id="$3"
    local status="$4"
    local rules_executed="$5"
    local results_per_rule="$6"

    # Validate validation_status enum before persisting
    if ! validate_validation_status "${status}"; then
        log_event "ERROR" "persist_state" "Rejected invalid validation_status: '${status}' (must be PASSED or FAILED)"
        return 1
    fi

    # Generate state file name: phase_{workflow_id}_{phase_id}_validation.json
    local state_file="${VALIDATION_STATE_DIR}/phase_${workflow_id}_${phase_id}_validation.json"

    # Create temporary file for atomic update
    local temp_file
    temp_file="$(mktemp "${VALIDATION_STATE_DIR}/validation_state_XXXXXX.tmp")"

    if [[ $? -ne 0 ]]; then
        log_event "ERROR" "persist_state" "Failed to create temporary file for state persistence"
        return 1
    fi

    # Build validation state JSON
    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    # Use jq to build JSON (ensures proper escaping and structure)
    local state_json
    state_json=$(jq -n \
        --arg workflow_id "${workflow_id}" \
        --arg phase_id "${phase_id}" \
        --arg session_id "${session_id}" \
        --arg status "${status}" \
        --arg timestamp "${timestamp}" \
        --argjson rules_executed "${rules_executed}" \
        --argjson results "${results_per_rule}" \
        '{
            workflow_id: $workflow_id,
            phase_id: $phase_id,
            session_id: $session_id,
            validation_status: $status,
            persisted_at: $timestamp,
            summary: {
                total_rules_executed: $rules_executed,
                results_count: ($results | length)
            },
            rule_results: $results
        }' 2>&1)

    if [[ $? -ne 0 ]]; then
        log_event "ERROR" "persist_state" "Failed to build state JSON: ${state_json}"
        rm -f "${temp_file}"
        return 1
    fi

    # Write JSON to temporary file
    echo "${state_json}" > "${temp_file}"

    if [[ $? -ne 0 ]]; then
        log_event "ERROR" "persist_state" "Failed to write state JSON to temporary file"
        rm -f "${temp_file}"
        return 1
    fi

    # Validate JSON syntax before committing
    if ! jq empty "${temp_file}" 2>/dev/null; then
        log_event "ERROR" "persist_state" "Generated state JSON is invalid"
        rm -f "${temp_file}"
        return 1
    fi

    # Atomic replace: mv is atomic on the same filesystem
    mv "${temp_file}" "${state_file}"

    if [[ $? -ne 0 ]]; then
        log_event "ERROR" "persist_state" "Failed to move temporary file to ${state_file}"
        rm -f "${temp_file}"
        return 1
    fi

    # Success
    log_event "VALIDATION" "persist_state" "State persisted to ${state_file} (status: ${status}, rules: ${rules_executed})"
    return 0
}

# Validate validation_status enum value
# Checks if status value is exactly "PASSED" or "FAILED" (case-sensitive)
# Args:
#   $1: validation_status - Status value to validate
# Returns:
#   0 if valid (PASSED or FAILED), 1 if invalid
# Notes:
#   - Case-sensitive validation (only "PASSED" and "FAILED" are valid)
#   - Logs invalid values as errors with details
#   - Used by persist_validation_state() and read_validation_state()
validate_validation_status() {
    local validation_status="$1"

    # Check for empty or null values
    if [[ -z "${validation_status}" ]]; then
        log_event "VALIDATION" "validate_status" "Invalid validation_status: empty value (expected: PASSED or FAILED)"
        return 1
    fi

    # Validate enum values (case-sensitive)
    case "${validation_status}" in
        "PASSED"|"FAILED")
            # Valid status
            return 0
            ;;
        *)
            # Invalid status value
            log_event "VALIDATION" "validate_status" "Invalid validation_status: '${validation_status}' (expected: PASSED or FAILED)"
            return 1
            ;;
    esac
}

# Read validation state from persisted JSON file
# Implements atomic read pattern with graceful error handling
# Args:
#   $1: workflow_id - Workflow identifier
#   $2: phase_id - Phase identifier
# Returns:
#   Validation status: "PASSED", "FAILED", or "UNKNOWN" (on error/missing file)
#   Exit code: Always 0 (fail-open behavior for missing files)
# Notes:
#   - Missing files return "UNKNOWN" (INFO log, not ERROR)
#   - Invalid JSON returns "UNKNOWN" (ERROR log)
#   - Missing validation_status field returns "UNKNOWN" (WARNING log)
#   - All read operations are logged for debugging
read_validation_state() {
    local workflow_id="$1"
    local phase_id="$2"

    # Construct state file path: phase_{workflow_id}_{phase_id}_validation.json
    local state_file="${VALIDATION_STATE_DIR}/phase_${workflow_id}_${phase_id}_validation.json"

    # Check if state file exists
    if [[ ! -f "${state_file}" ]]; then
        # Missing file is normal - return UNKNOWN with INFO log (fail-open)
        log_event "INFO" "read_state" "State file not found: ${state_file} (returning UNKNOWN)"
        echo "UNKNOWN"
        return 0  # Fail-open (missing file is normal)
    fi

    # Check file is readable
    if [[ ! -r "${state_file}" ]]; then
        log_event "ERROR" "read_state" "Permission denied reading state file: ${state_file} (returning UNKNOWN)"
        echo "UNKNOWN"
        return 0  # Fail-open (permission denied)
    fi

    # Validate JSON syntax using jq
    if ! jq empty "${state_file}" 2>/dev/null; then
        log_event "ERROR" "read_state" "Invalid JSON in state file: ${state_file} (returning UNKNOWN)"
        echo "UNKNOWN"
        return 0  # Fail-open (invalid JSON)
    fi

    # Read validation_status field from JSON
    # Path: .validation_status (based on persist_validation_state schema)
    local validation_status
    validation_status=$(jq -r '.validation_status // empty' "${state_file}" 2>/dev/null)

    # Check if validation_status field exists
    if [[ -z "${validation_status}" ]]; then
        log_event "WARNING" "read_state" "Missing validation_status field in ${state_file} (returning UNKNOWN)"
        echo "UNKNOWN"
        return 0
    fi

    # Validate status value using validate_validation_status function
    if validate_validation_status "${validation_status}"; then
        # Valid status (PASSED or FAILED) - log success and return value
        log_event "INFO" "read_state" "State read from ${state_file}: ${validation_status}"
        echo "${validation_status}"
        return 0
    else
        # Invalid status value - log error and return UNKNOWN (fail-open)
        log_event "ERROR" "read_state" "Invalid validation_status value '${validation_status}' in ${state_file} (returning UNKNOWN)"
        echo "UNKNOWN"
        return 0  # Fail-open (invalid validation_status)
    fi
}

# Evaluate blocking rules based on validation state
# Implements blocking logic: FAILED validation blocks workflow, PASSED/UNKNOWN allow continuation
# Args:
#   $1: workflow_id - Workflow identifier
#   $2: phase_id - Phase identifier
# Returns:
#   0 if workflow should continue (PASSED or UNKNOWN status, fail-open)
#   1 if workflow should be blocked (FAILED status)
# Notes:
#   - FAILED validation → return 1 (block workflow)
#   - PASSED validation → return 0 (allow continuation)
#   - UNKNOWN validation → return 0 (fail-open, allow continuation)
#   - Function is idempotent (same inputs always produce same output)
#   - All decisions are logged for debugging and audit trail
#   - PHASE 4: This function is used for rule-based validation only
#   - Semantic validation (CONTINUE/REPEAT/ABORT) handles exit codes directly in main()
evaluate_blocking_rules() {
    local workflow_id="$1"
    local phase_id="$2"

    # Read current validation state
    local validation_status
    validation_status=$(read_validation_state "${workflow_id}" "${phase_id}")
    local read_exit_code=$?

    # Log the validation status that was read
    log_event "VALIDATION" "evaluate_blocking" "Read validation status for workflow ${workflow_id}, phase ${phase_id}: ${validation_status}"

    # Evaluate blocking logic based on validation status
    case "${validation_status}" in
        "FAILED")
            # Validation FAILED → BLOCK workflow (exit 1)
            log_event "VALIDATION" "evaluate_blocking" "BLOCK: Validation status is FAILED for workflow ${workflow_id}, phase ${phase_id}"
            return 1
            ;;
        "PASSED")
            # Validation PASSED → ALLOW continuation (exit 0)
            log_event "VALIDATION" "evaluate_blocking" "ALLOW: Validation status is PASSED for workflow ${workflow_id}, phase ${phase_id}"
            return 0
            ;;
        "UNKNOWN")
            # Validation UNKNOWN → ALLOW continuation (fail-open behavior, exit 0)
            log_event "VALIDATION" "evaluate_blocking" "ALLOW: Validation status is UNKNOWN (fail-open) for workflow ${workflow_id}, phase ${phase_id}"
            return 0
            ;;
        *)
            # Unexpected status → ALLOW continuation (conservative fail-open, exit 0)
            log_event "WARNING" "evaluate_blocking" "ALLOW: Unexpected validation status '${validation_status}' (fail-open) for workflow ${workflow_id}, phase ${phase_id}"
            return 0
            ;;
    esac
}

################################################################################
# Semantic Validation Functions
################################################################################

# Perform semantic validation comparing task objectives with subagent deliverables
# This function uses natural language validation with Haiku to determine if phase objectives were met.
#
# SIMPLIFIED IMPLEMENTATION (Phase 4.5 Refactoring):
# - Removed all complex parsing logic (border stripping, decision extraction, regex patterns)
# - Outputs full Haiku response directly to stderr for transparency
# - Returns simple VALIDATION_RESPONSE format: VALIDATION_RESPONSE|<raw_haiku_response>
# - Decision extraction happens in main() using natural language parsing
# - More resilient to Haiku output format changes
#
# Args:
#   $1: input_json - Full JSON input from hook system
# Outputs:
#   VALIDATION_RESPONSE format (to stdout):
#     VALIDATION_RESPONSE|<raw_haiku_response>
#   Where raw_haiku_response is the complete Haiku output without any processing
# Returns:
#   0 always (main() handles exit codes based on decision extracted from response)
semantic_validation() {
    local input_json="$1"

    # Extract tool name to ensure it's a delegation tool
    local tool_name
    tool_name="$(echo "${input_json}" | jq -r '.tool.name // empty' 2>/dev/null)"

    # Only apply semantic validation to delegation tools
    case "${tool_name}" in
        "Task"|"SubagentTask"|"AgentTask")
            # Continue with semantic validation
            ;;
        *)
            # Not applicable for non-delegation tools
            echo "VALIDATION_RESPONSE|NOT_APPLICABLE|Not a delegation tool: ${tool_name}"
            log_event "SKIP" "semantic_validation" "Skipping semantic validation for non-delegation tool: ${tool_name}"
            return 0
            ;;
    esac

    # Extract task objective from tool parameters (prompt field)
    local task_objective
    task_objective="$(echo "${input_json}" | jq -r '.tool.parameters.prompt // empty' 2>/dev/null)"

    if [[ -z "${task_objective}" ]]; then
        echo "VALIDATION_RESPONSE|NOT_APPLICABLE|No task objective found in tool parameters"
        log_event "SKIP" "semantic_validation" "No task objective found in tool parameters"
        return 0
    fi

    # Extract subagent deliverables from tool result
    local tool_result
    tool_result="$(echo "${input_json}" | jq -r '.tool.result // empty' 2>/dev/null)"

    if [[ -z "${tool_result}" ]]; then
        echo "VALIDATION_RESPONSE|NOT_APPLICABLE|No tool result available"
        log_event "SKIP" "semantic_validation" "No tool result available for semantic validation"
        return 0
    fi

    # Truncate inputs if they exceed reasonable length (prevent token overflow)
    local max_chars=10000
    if [[ ${#task_objective} -gt ${max_chars} ]]; then
        task_objective="${task_objective:0:${max_chars}}... [truncated]"
    fi
    if [[ ${#tool_result} -gt ${max_chars} ]]; then
        tool_result="${tool_result:0:${max_chars}}... [truncated]"
    fi

    # Check if claude command is available
    if ! command -v claude >/dev/null 2>&1; then
        echo "VALIDATION_RESPONSE|NOT_APPLICABLE|claude command not available"
        log_event "SKIP" "semantic_validation" "claude command not available"
        return 0
    fi

    # Construct Haiku validation prompt for natural language validation
    local haiku_prompt
    haiku_prompt="You are a validation agent analyzing workflow phase completion.

TASK OBJECTIVE:
${task_objective}

SUBAGENT DELIVERABLES:
${tool_result}

YOUR TASK:
Analyze whether the subagent accomplished the task objective. Provide a clear validation decision.

Start your response with one of these exact phrases:
- \"VALIDATION DECISION: CONTINUE\" - if objective was met and work is complete
- \"VALIDATION DECISION: REPEAT\" - if work needs improvement before proceeding
- \"VALIDATION DECISION: ABORT\" - if critical failures prevent workflow continuation

After the decision, explain your reasoning in natural language."

    # Invoke Haiku for semantic validation
    local validation_response
    local haiku_exit_code

    log_event "VALIDATION" "semantic_validation" "Invoking Haiku for semantic validation (objective: ${#task_objective} chars, result: ${#tool_result} chars)"

    # Detect timeout command (Linux vs macOS)
    local timeout_cmd="timeout"
    if ! command -v timeout >/dev/null 2>&1; then
        if command -v gtimeout >/dev/null 2>&1; then
            timeout_cmd="gtimeout"
        else
            timeout_cmd=""
        fi
    fi

    # Invoke claude haiku with timeout
    if [[ -n "${timeout_cmd}" ]]; then
        validation_response=$(${timeout_cmd} 60 claude --model haiku -p "${haiku_prompt}" 2>&1)
    else
        validation_response=$(claude --model haiku -p "${haiku_prompt}" 2>&1)
    fi

    haiku_exit_code=$?

    # Check if Haiku invocation succeeded
    if [[ ${haiku_exit_code} -ne 0 ]]; then
        echo "VALIDATION_RESPONSE|NOT_APPLICABLE|Haiku invocation failed (exit code: ${haiku_exit_code})"
        log_event "ERROR" "semantic_validation" "Haiku invocation failed with exit code ${haiku_exit_code}"
        return 0
    fi

    # Display full Haiku response to user (transparency)
    # Extract decision for icon display
    local display_decision
    display_decision=$(echo "${validation_response}" | grep -oE 'VALIDATION DECISION: (CONTINUE|REPEAT|ABORT)' | grep -oE 'CONTINUE|REPEAT|ABORT' | head -n 1 || echo "NOT_APPLICABLE")

    # Map decision to icon for user visibility
    local decision_icon
    case "${display_decision}" in
        "CONTINUE") decision_icon="✅" ;;
        "REPEAT") decision_icon="🔄" ;;
        "ABORT") decision_icon="🚫" ;;
        *) decision_icon="⚠️" ;;
    esac

    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "${decision_icon} Validation Analysis:" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "${validation_response}" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2

    # Output simplified VALIDATION_RESPONSE format with raw LLM output
    # Format: VALIDATION_RESPONSE|<raw_haiku_response>
    # main() will extract the decision using natural language parsing
    echo "VALIDATION_RESPONSE|${validation_response}"
    log_event "VALIDATION" "semantic_validation" "Returned raw validation response to main() (${#validation_response} chars)"

    # Always return 0 - main() handles exit codes based on decision
    return 0
}

################################################################################
# Detection Functions
################################################################################

# Detect if validation gate should be triggered
# Reads JSON from stdin, extracts tool name and workflow context
# Outputs: TRIGGER|session_id|workflow_id OR SKIP|reason OR ERROR|message
# Returns: 0 on success (output written), 1 on error
detect_validation_trigger() {
    # Read stdin JSON (expected from hook system)
    local input_json
    input_json="$(cat)"

    # Validate JSON syntax using jq
    if ! echo "${input_json}" | jq empty 2>/dev/null; then
        echo "ERROR|Invalid JSON input"
        log_event "ERROR" "Unknown" "Invalid JSON input received by detect_validation_trigger"
        return 1
    fi

    # Check if 'tool' object exists in JSON
    local tool_exists
    tool_exists="$(echo "${input_json}" | jq -r 'has("tool")' 2>/dev/null)"

    if [[ "${tool_exists}" != "true" ]]; then
        # Log the entire input for malformed JSON diagnosis
        local available_fields
        available_fields="$(echo "${input_json}" | jq -r 'keys | join(", ")' 2>/dev/null || echo "unable to parse")"

        # Truncate input for logging (500 chars max)
        local truncated_for_log
        if [[ ${#input_json} -gt 500 ]]; then
            truncated_for_log="${input_json:0:500}... [truncated]"
        else
            truncated_for_log="${input_json}"
        fi

        echo "SKIP|Missing 'tool' object in hook input"
        log_event "WARN" "malformed_input" "Missing 'tool' object in hook input. Available fields: ${available_fields}. Input: ${truncated_for_log}"
        return 0
    fi

    # Extract tool name (required field)
    local tool_name
    tool_name="$(echo "${input_json}" | jq -r '.tool.name // empty' 2>/dev/null)"

    if [[ -z "${tool_name}" ]]; then
        # Enhanced error logging: capture what fields ARE present
        local tool_fields
        tool_fields="$(echo "${input_json}" | jq -r '.tool | keys | join(", ")' 2>/dev/null || echo "unable to parse .tool")"

        # Truncate tool object for logging
        local tool_object
        tool_object="$(echo "${input_json}" | jq -c '.tool' 2>/dev/null || echo "{}")"
        if [[ ${#tool_object} -gt 500 ]]; then
            tool_object="${tool_object:0:500}... [truncated]"
        fi

        echo "ERROR|Missing field: tool.name"
        log_event "ERROR" "malformed_input" "Missing 'tool.name' field. Available tool fields: ${tool_fields}. Tool object: ${tool_object}"
        return 1
    fi

    # Extract session ID (required field)
    local session_id
    session_id="$(echo "${input_json}" | jq -r '.sessionId // empty' 2>/dev/null)"

    if [[ -z "${session_id}" ]]; then
        echo "ERROR|Missing field: sessionId"
        log_event "ERROR" "${tool_name}" "Missing required field: sessionId"
        return 1
    fi

    # Extract workflow ID (optional field)
    local workflow_id
    workflow_id="$(echo "${input_json}" | jq -r '.workflowId // empty' 2>/dev/null)"

    # Detect delegation tools that trigger validation
    case "${tool_name}" in
        "SlashCommand")
            # SlashCommand indicates /delegate command - register but don't validate yet
            echo "TRIGGER|${session_id}|${workflow_id}"
            log_event "TRIGGER" "${tool_name}" "Delegation command detected (session: ${session_id})"
            return 0
            ;;
        "Task"|"SubagentTask"|"AgentTask")
            # Task tools indicate phase completion - trigger validation check
            echo "TRIGGER|${session_id}|${workflow_id}"
            log_event "TRIGGER" "${tool_name}" "Phase completion detected (session: ${session_id}, workflow: ${workflow_id})"
            return 0
            ;;
        *)
            # Non-delegation tools - skip validation
            echo "SKIP|non-delegation tool: ${tool_name}"
            return 0
            ;;
    esac
}

# Check if current phase needs validation
# Searches for validation config files matching the workflow/session context
# Args:
#   $1: Session ID
#   $2: Workflow ID (may be empty)
# Returns:
#   0 if validation config found, 1 otherwise
should_validate_phase() {
    local session_id="$1"
    local workflow_id="$2"

    # Ensure validation state directory exists
    if [[ ! -d "${VALIDATION_STATE_DIR}" ]]; then
        log_event "SKIP" "validation_check" "Validation state directory does not exist: ${VALIDATION_STATE_DIR}"
        return 1
    fi

    # Check directory permissions
    if [[ ! -r "${VALIDATION_STATE_DIR}" ]]; then
        log_event "ERROR" "validation_check" "Permission denied on validation state directory: ${VALIDATION_STATE_DIR}"
        return 1
    fi

    # Search for validation config files
    # Pattern: phase_*.json OR phase_{workflow_id}_*.json
    local config_files
    local found_config=""

    if [[ -n "${workflow_id}" ]]; then
        # Search for workflow-specific configs first
        config_files=$(find "${VALIDATION_STATE_DIR}" -maxdepth 1 -name "phase_${workflow_id}_*.json" 2>/dev/null || true)

        if [[ -n "${config_files}" ]]; then
            found_config="$(echo "${config_files}" | head -n 1)"
        fi
    fi

    # If no workflow-specific config, search for any phase config
    if [[ -z "${found_config}" ]]; then
        config_files=$(find "${VALIDATION_STATE_DIR}" -maxdepth 1 -name "phase_*.json" 2>/dev/null || true)

        if [[ -n "${config_files}" ]]; then
            found_config="$(echo "${config_files}" | head -n 1)"
        fi
    fi

    # Return result
    if [[ -n "${found_config}" ]]; then
        log_event "VALIDATION" "config_check" "Validation config found: ${found_config}"
        return 0
    else
        log_event "SKIP" "config_check" "No validation config found for session: ${session_id}, workflow: ${workflow_id}"
        return 1
    fi
}

# Invoke validation for current phase
# Args:
#   $1: Validation config file path
#   $2: Workflow ID
#   $3: Session ID
# Outputs:
#   VALIDATION_RESULT|PASSED|<summary> OR VALIDATION_RESULT|FAILED|<summary>
# Returns:
#   0 on validation passed, 1 on validation failed
invoke_validation() {
    local config_file="$1"
    local workflow_id="$2"
    local session_id="$3"

    # Validate inputs
    if [[ ! -f "${config_file}" ]]; then
        log_event "ERROR" "validation" "Config file not found: ${config_file}"
        echo "VALIDATION_RESULT|FAILED|Config file not found: ${config_file}"
        return 1
    fi

    # Log validation start
    log_event "VALIDATION" "invoke" "Starting validation (workflow: ${workflow_id}, session: ${session_id}, config: ${config_file})"

    # Declare result variables
    local validation_result
    local validation_exit_code

    # Detect timeout command (Linux vs macOS)
    local timeout_cmd="timeout"
    if ! command -v timeout >/dev/null 2>&1; then
        if command -v gtimeout >/dev/null 2>&1; then
            timeout_cmd="gtimeout"
        else
            timeout_cmd=""  # No timeout available
        fi
    fi

    # Check if claude command is available
    if ! command -v claude >/dev/null 2>&1; then
        log_event "ERROR" "validation" "claude command not found"
        validation_status="FAILED"
        summary_message="Validation execution failed: claude command not available"
        echo "SKIP|claude command not available" >&2
        return 1
    fi

    # Invoke validation using claude haiku (memory-safe, no embedded scripts)
    # Construct minimal prompt (target: <1KB)
    local haiku_prompt="You are a validation executor. Read the validation config at ${config_file}. Execute all validation rules defined in the config. Return JSON with: validation_status (PASSED/FAILED), workflow_id (${workflow_id}), session_id (${session_id}), validated_at (ISO8601), summary (total_rules, passed_rules, failed_rules, skipped_rules), rule_results (array of result objects), failed_rule_details (array). Each rule_result must include: result_id, rule_id, rule_type, validated_at, status, message, details."

    # Invoke claude with haiku model (single subprocess, no heredoc, no bash -c wrapper)
    if [[ -n "${timeout_cmd}" ]]; then
        validation_result=$(${timeout_cmd} 120 claude --model haiku -p "${haiku_prompt}" 2>&1)
    else
        validation_result=$(claude --model haiku -p "${haiku_prompt}" 2>&1)
    fi

    validation_exit_code=$?

    # Parse validation result
    local validation_status
    local summary_message

    if [[ ${validation_exit_code} -eq 0 ]]; then
        # Extract status from JSON result
        validation_status=$(echo "${validation_result}" | jq -r '.validation_status // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")

        # Build summary from result
        local passed_count failed_count total_count
        passed_count=$(echo "${validation_result}" | jq -r '.summary.passed_rules // 0' 2>/dev/null || echo "0")
        failed_count=$(echo "${validation_result}" | jq -r '.summary.failed_rules // 0' 2>/dev/null || echo "0")
        total_count=$(echo "${validation_result}" | jq -r '.summary.total_rules // 0' 2>/dev/null || echo "0")

        summary_message="Validation ${validation_status}: ${passed_count}/${total_count} rules passed"

        # Extract phase_id from validation result
        local phase_id
        phase_id=$(echo "${validation_result}" | jq -r '.phase_id // "unknown"' 2>/dev/null || echo "unknown")

        # Extract rule_results array from validation result
        local rule_results
        rule_results=$(echo "${validation_result}" | jq -c '.rule_results // []' 2>/dev/null || echo "[]")

        # Persist validation state
        persist_validation_state "${workflow_id}" "${phase_id}" "${session_id}" "${validation_status}" "${total_count}" "${rule_results}"

        # Note: persist_validation_state errors are logged but don't fail the hook

        # Log validation completion
        log_event "VALIDATION" "validation" "${summary_message} (workflow: ${workflow_id})"

        # Return result
        echo "VALIDATION_RESULT|${validation_status}|${summary_message}"

        if [[ "${validation_status}" == "PASSED" ]]; then
            return 0
        else
            return 1
        fi
    else
        # Validation execution failed
        validation_status="FAILED"
        summary_message="Validation execution failed (exit code: ${validation_exit_code})"

        # Extract phase_id if possible (may fail if validation_result is not valid JSON)
        local phase_id
        phase_id=$(echo "${validation_result}" | jq -r '.phase_id // "unknown"' 2>/dev/null || echo "unknown")

        # Create minimal error result for persistence
        local error_results
        error_results='[{"result_id":"error_validation_execution","rule_id":"validation_execution","rule_type":"execution","validated_at":"'"$(date -u +"%Y-%m-%dT%H:%M:%SZ")"'","status":"failed","message":"'"${summary_message}"'","details":{"exit_code":'"${validation_exit_code}"'}}]'

        # Persist validation state (failure case)
        persist_validation_state "${workflow_id}" "${phase_id}" "${session_id}" "${validation_status}" "0" "${error_results}"

        # Log validation execution failure
        log_event "ERROR" "validation" "${summary_message} (workflow: ${workflow_id})"

        echo "VALIDATION_RESULT|FAILED|${summary_message}"
        return 1
    fi
}

################################################################################
# Main Hook Logic
################################################################################

main() {
    # Ensure validation state directory exists
    mkdir -p "${VALIDATION_STATE_DIR}"
    # Ensure deliverables directory exists
    mkdir -p "${PROJECT_ROOT}/.claude/state/deliverables"

    # Read stdin once and store for reuse
    local input_json
    input_json="$(cat)"

    # Debug logging: Capture raw input for malformed JSON diagnosis
    # Truncate to 500 chars to prevent log flooding
    local truncated_input
    if [[ ${#input_json} -gt 500 ]]; then
        truncated_input="${input_json:0:500}... [truncated from ${#input_json} chars]"
    else
        truncated_input="${input_json}"
    fi
    log_event "DEBUG" "hook_input" "Raw JSON received (length: ${#input_json}): ${truncated_input}"

    # Detect validation trigger (uses stored input_json)
    local trigger_result
    trigger_result="$(echo "${input_json}" | detect_validation_trigger)"
    local trigger_exit_code=$?

    # Parse trigger result: TRIGGER|session_id|workflow_id OR SKIP|reason OR ERROR|message
    local trigger_status
    trigger_status="$(echo "${trigger_result}" | cut -d'|' -f1)"

    case "${trigger_status}" in
        "TRIGGER")
            # Extract session_id and workflow_id from result
            local session_id workflow_id
            session_id="$(echo "${trigger_result}" | cut -d'|' -f2)"
            workflow_id="$(echo "${trigger_result}" | cut -d'|' -f3)"

            # Try semantic validation first
            log_event "VALIDATION" "gate" "Attempting semantic validation (session: ${session_id}, workflow: ${workflow_id})"
            local validation_response
            validation_response=$(semantic_validation "${input_json}")
            local validation_exit_code=$?

            # Parse VALIDATION_RESPONSE format: VALIDATION_RESPONSE|<full_haiku_response>
            local response_type
            response_type=$(echo "${validation_response}" | cut -d'|' -f1)

            # Check if response is VALIDATION_RESPONSE format
            if [[ "${response_type}" != "VALIDATION_RESPONSE" ]]; then
                log_event "ERROR" "gate" "Unexpected response format from semantic_validation: ${response_type}"
                # Fail-open: continue with warning
                exit 3
            fi

            # Extract full Haiku response (everything after first |)
            local haiku_response
            haiku_response=$(echo "${validation_response}" | cut -d'|' -f2-)

            # Check for NOT_APPLICABLE status (appears in haiku_response for non-delegation tools)
            case "${haiku_response}" in
                "NOT_APPLICABLE|"*)
                    # Semantic validation not applicable - fall back to rule-based validation
                    local not_applicable_reason
                    not_applicable_reason=$(echo "${haiku_response}" | cut -d'|' -f2-)
                    log_event "VALIDATION" "gate" "Semantic validation not applicable: ${not_applicable_reason}. Falling back to rule-based validation."

                    # Check if current phase needs rule-based validation
                    if should_validate_phase "${session_id}" "${workflow_id}"; then
                        log_event "VALIDATION" "gate" "Phase validation required (session: ${session_id}, workflow: ${workflow_id})"

                        # Find validation config file
                        local config_file=""
                        if [[ -n "${workflow_id}" ]]; then
                            # Search for workflow-specific config first
                            config_file=$(find "${VALIDATION_STATE_DIR}" -maxdepth 1 -name "phase_${workflow_id}_*.json" 2>/dev/null | head -n 1)
                        fi

                        # If no workflow-specific config, search for any phase config
                        if [[ -z "${config_file}" ]]; then
                            config_file=$(find "${VALIDATION_STATE_DIR}" -maxdepth 1 -name "phase_*.json" 2>/dev/null | head -n 1)
                        fi

                        # Invoke rule-based validation with config file
                        if [[ -n "${config_file}" ]]; then
                            local validation_result
                            validation_result=$(invoke_validation "${config_file}" "${workflow_id}" "${session_id}")
                            local invoke_exit_code=$?

                            # Parse validation result: VALIDATION_RESULT|PASSED|summary OR VALIDATION_RESULT|FAILED|summary
                            local result_status
                            result_status=$(echo "${validation_result}" | cut -d'|' -f2)

                            # Extract phase_id from config file metadata for blocking evaluation
                            local phase_id
                            if [[ -f "${config_file}" ]]; then
                                phase_id=$(jq -r '.metadata.phase_id // "unknown"' "${config_file}" 2>/dev/null || echo "unknown")
                                if [[ -z "${phase_id}" || "${phase_id}" == "null" ]]; then
                                    phase_id="unknown"
                                    log_event "DEBUG" "gate" "Failed to extract phase_id from config file, using 'unknown'"
                                fi
                            else
                                phase_id="unknown"
                                log_event "ERROR" "gate" "Config file not found for phase_id extraction"
                            fi

                            # Evaluate blocking rules based on validation status
                            log_event "DEBUG" "gate" "Evaluating blocking rules (workflow: ${workflow_id}, phase: ${phase_id}, status: ${result_status})"

                            if evaluate_blocking_rules "${workflow_id}" "${phase_id}"; then
                                # Blocking evaluation returned 0 (allow)
                                log_event "VALIDATION" "gate" "Validation ${result_status} - workflow may continue (blocking: allow)"
                                # Continue normal execution (exit 0 at end of hook)
                            else
                                # Blocking evaluation returned 1 (block)
                                log_event "ERROR" "gate" "Validation ${result_status} - BLOCKING workflow execution (workflow: ${workflow_id}, phase: ${phase_id})"
                                # Exit hook with non-zero code to block subsequent execution
                                exit 1
                            fi
                        else
                            log_event "ERROR" "gate" "Config file not found despite should_validate_phase returning true"
                        fi
                    else
                        log_event "SKIP" "gate" "No validation config found for this phase"
                    fi
                    ;;
                *)
                    # Haiku provided a validation decision - extract it using natural language parsing
                    # Expected format: "VALIDATION DECISION: CONTINUE\n\nReasoning..."
                    local validation_decision
                    validation_decision=$(echo "${haiku_response}" | grep -oE 'VALIDATION DECISION: (CONTINUE|REPEAT|ABORT)' | grep -oE 'CONTINUE|REPEAT|ABORT' | head -n 1 || echo "")

                    if [[ -z "${validation_decision}" ]]; then
                        log_event "WARNING" "gate" "Could not extract decision from Haiku response - failing open (exit 3)"
                        exit 3
                    fi

                    # Extract full reasoning (for logging and state persistence)
                    # Skip first line (decision header) and capture remaining content
                    local reasoning
                    reasoning=$(echo "${haiku_response}" | tail -n +2)

                    log_event "VALIDATION" "gate" "Extracted validation decision: ${validation_decision}"

                    # Create synthetic phase_id for semantic validation (no config file)
                    local tool_name
                    tool_name="$(echo "${input_json}" | jq -r '.tool.name // "unknown"' 2>/dev/null)"
                    local phase_id="semantic_${tool_name}_${session_id:0:8}"

                    # Map decision to persistence status (CONTINUE=PASSED, REPEAT/ABORT=FAILED)
                    local persistence_status
                    case "${validation_decision}" in
                        "CONTINUE")
                            persistence_status="PASSED"
                            ;;
                        "REPEAT"|"ABORT")
                            persistence_status="FAILED"
                            ;;
                        *)
                            persistence_status="FAILED"
                            ;;
                    esac

                    # Build synthetic rule_results for state persistence
                    local timestamp
                    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
                    local semantic_rule_results
                    semantic_rule_results=$(jq -n \
                        --arg result_id "semantic_validation_${timestamp}" \
                        --arg rule_id "semantic_objective_match" \
                        --arg validated_at "${timestamp}" \
                        --arg status "$(echo "${persistence_status}" | tr '[:upper:]' '[:lower:]')" \
                        --arg message "${reasoning}" \
                        --arg decision "${validation_decision}" \
                        '[{
                            result_id: $result_id,
                            rule_id: $rule_id,
                            rule_type: "semantic",
                            validated_at: $validated_at,
                            status: $status,
                            message: $message,
                            details: {
                                validation_type: "semantic",
                                model: "haiku",
                                natural_language_decision: $decision
                            }
                        }]' 2>/dev/null || echo '[]')

                    # Persist validation state
                    persist_validation_state "${workflow_id}" "${phase_id}" "${session_id}" "${persistence_status}" "1" "${semantic_rule_results}"

                    # Map decision to exit code for workflow control
                    log_event "DEBUG" "gate" "Mapping decision to exit code (workflow: ${workflow_id}, phase: ${phase_id}, decision: ${validation_decision})"

                    case "${validation_decision}" in
                        "CONTINUE")
                            log_event "VALIDATION" "semantic_validation" "CONTINUE: Semantic validation passed - proceeding to next phase (exit 0)"
                            exit 0
                            ;;
                        "REPEAT")
                            log_event "VALIDATION" "semantic_validation" "REPEAT: Validation requires retry with improvements (exit 1)"
                            exit 1
                            ;;
                        "ABORT")
                            log_event "VALIDATION" "semantic_validation" "ABORT: Critical failure - halting workflow (exit 2)"
                            exit 2
                            ;;
                        "NOT_APPLICABLE")
                            log_event "WARNING" "gate" "DECISION: NOT_APPLICABLE - Semantic validation NOT_APPLICABLE - fail-open (exit 3)"
                            exit 3
                            ;;
                        *)
                            log_event "WARNING" "gate" "Unexpected decision '${validation_decision}' - fail-open (exit 3)"
                            exit 3
                            ;;
                    esac
                    ;;
            esac
            ;;
        "SKIP")
            # Non-delegation tool, skip validation
            local skip_reason
            skip_reason="$(echo "${trigger_result}" | cut -d'|' -f2-)"
            ;;
        "ERROR")
            # Error in trigger detection
            local error_msg
            error_msg="$(echo "${trigger_result}" | cut -d'|' -f2-)"
            log_event "ERROR" "gate" "Trigger detection error: ${error_msg}"
            ;;
        *)
            log_event "ERROR" "gate" "Unknown trigger status: ${trigger_status}"
            ;;
    esac

    # Exit with code 0 (non-blocking hook)
    exit 0
}

# Execute main function only if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
