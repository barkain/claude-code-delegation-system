#!/bin/bash
################################################################################
# PostToolUse Hook: Validation Gate
#
# Purpose: Trigger validation checks after tool execution
# Hook Type: PostToolUse (runs after every tool invocation)
# Exit Code: 0 (non-blocking skeleton implementation)
#
# Input: JSON via stdin from Claude Code hook system
# Output: Logs to .claude/state/validation/gate_invocations.log
#
# Author: Claude Code Delegation System
# Version: 1.0.0-skeleton
################################################################################

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly VALIDATION_STATE_DIR="${PROJECT_ROOT}/.claude/state/validation"
readonly LOG_FILE="${VALIDATION_STATE_DIR}/gate_invocations.log"

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
        return 0
    fi

    # Check file is readable
    if [[ ! -r "${state_file}" ]]; then
        log_event "ERROR" "read_state" "Permission denied reading state file: ${state_file} (returning UNKNOWN)"
        echo "UNKNOWN"
        return 0
    fi

    # Validate JSON syntax using jq
    if ! jq empty "${state_file}" 2>/dev/null; then
        log_event "ERROR" "read_state" "Invalid JSON in state file: ${state_file} (returning UNKNOWN)"
        echo "UNKNOWN"
        return 0
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
        return 0
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
            # Validation FAILED → BLOCK workflow
            log_event "VALIDATION" "evaluate_blocking" "BLOCK: Validation status is FAILED for workflow ${workflow_id}, phase ${phase_id}"
            return 1
            ;;
        "PASSED")
            # Validation PASSED → ALLOW continuation
            log_event "VALIDATION" "evaluate_blocking" "ALLOW: Validation status is PASSED for workflow ${workflow_id}, phase ${phase_id}"
            return 0
            ;;
        "UNKNOWN")
            # Validation UNKNOWN → ALLOW continuation (fail-open behavior)
            log_event "VALIDATION" "evaluate_blocking" "ALLOW: Validation status is UNKNOWN (fail-open) for workflow ${workflow_id}, phase ${phase_id}"
            return 0
            ;;
        *)
            # Unexpected status → ALLOW continuation (conservative fail-open)
            log_event "WARNING" "evaluate_blocking" "ALLOW: Unexpected validation status '${validation_status}' (fail-open) for workflow ${workflow_id}, phase ${phase_id}"
            return 0
            ;;
    esac
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

    # Extract tool name (required field)
    local tool_name
    tool_name="$(echo "${input_json}" | jq -r '.tool.name // empty' 2>/dev/null)"

    if [[ -z "${tool_name}" ]]; then
        echo "ERROR|Missing field: tool.name"
        log_event "ERROR" "Unknown" "Missing required field: tool.name"
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

    # Construct delegation prompt for phase-validator agent
    local delegation_prompt
    delegation_prompt=$(cat <<EOF
Execute validation rules from the configuration file at: ${config_file}

Workflow Context:
- Workflow ID: ${workflow_id}
- Session ID: ${session_id}

Task: Validate that all rules defined in the configuration pass successfully.

Return a JSON result with validation_status, summary, and rule_results as defined in the phase-validator agent specification.
EOF
)

    # Create a temporary file to store the delegation prompt
    local prompt_file
    prompt_file="$(mktemp "${VALIDATION_STATE_DIR}/validation_prompt_XXXXXX.txt")"
    echo "${delegation_prompt}" > "${prompt_file}"

    # Spawn phase-validator agent using claude CLI
    # The agent will read the config file, execute rules, and return JSON result
    local validation_result
    local validation_exit_code

    # Use claude with the phase-validator agent
    # We'll invoke it via a simple bash execution pattern since we're in a hook context
    # The agent system expects the prompt as input

    # Detect timeout command (Linux vs macOS)
    local timeout_cmd="timeout"
    if ! command -v timeout >/dev/null 2>&1; then
        if command -v gtimeout >/dev/null 2>&1; then
            timeout_cmd="gtimeout"
        else
            timeout_cmd=""  # No timeout available
        fi
    fi

    # Run validation with or without timeout
    if [[ -n "${timeout_cmd}" ]]; then
        validation_result=$(cat "${prompt_file}" | ${timeout_cmd} 120 bash -c '
        # Simulate agent invocation by directly executing validation logic
        # In production, this would invoke the actual phase-validator agent
        # For now, we create a minimal validation executor

        CONFIG_FILE="'"${config_file}"'"
        WORKFLOW_ID="'"${workflow_id}"'"
        SESSION_ID="'"${session_id}"'"

        # Read and validate config file
        if [[ ! -f "${CONFIG_FILE}" ]]; then
            echo "{\"validation_status\":\"FAILED\",\"workflow_id\":\"${WORKFLOW_ID}\",\"session_id\":\"${SESSION_ID}\",\"validated_at\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"summary\":{\"total_rules\":0,\"passed_rules\":0,\"failed_rules\":1,\"skipped_rules\":0},\"rule_results\":[],\"failed_rule_details\":[{\"error\":\"Config file not found\"}]}"
            exit 1
        fi

        # Validate JSON syntax
        if ! jq empty "${CONFIG_FILE}" 2>/dev/null; then
            echo "{\"validation_status\":\"FAILED\",\"workflow_id\":\"${WORKFLOW_ID}\",\"session_id\":\"${SESSION_ID}\",\"validated_at\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"summary\":{\"total_rules\":0,\"passed_rules\":0,\"failed_rules\":1,\"skipped_rules\":0},\"rule_results\":[],\"failed_rule_details\":[{\"error\":\"Invalid JSON in config file\"}]}"
            exit 1
        fi

        # Extract phase metadata
        PHASE_ID=$(jq -r ".metadata.phase_id // \"unknown\"" "${CONFIG_FILE}")

        # Extract validation rules
        RULES=$(jq -c ".validation_config.rules // []" "${CONFIG_FILE}")
        RULE_COUNT=$(echo "${RULES}" | jq "length")

        # Initialize counters
        PASSED_COUNT=0
        FAILED_COUNT=0
        RESULTS="[]"
        FAILED_DETAILS="[]"

        # Execute each rule
        for ((i=0; i<RULE_COUNT; i++)); do
            RULE=$(echo "${RULES}" | jq -c ".[$i]")
            RULE_ID=$(echo "${RULE}" | jq -r ".rule_id")
            RULE_TYPE=$(echo "${RULE}" | jq -r ".rule_type")
            RULE_CONFIG=$(echo "${RULE}" | jq -c ".rule_config")
            SEVERITY=$(echo "${RULE}" | jq -r ".severity // \"error\"")

            RESULT_ID="result_$(date +%s)_${i}"
            VALIDATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            STATUS="failed"
            MESSAGE="Rule execution not implemented"
            DETAILS="{}"

            # Execute rule based on type
            case "${RULE_TYPE}" in
                "file_exists")
                    PATH_TO_CHECK=$(echo "${RULE_CONFIG}" | jq -r ".path")
                    EXPECTED_TYPE=$(echo "${RULE_CONFIG}" | jq -r ".type // \"any\"")

                    if [[ -e "${PATH_TO_CHECK}" ]]; then
                        if [[ -f "${PATH_TO_CHECK}" ]] && [[ "${EXPECTED_TYPE}" == "file" || "${EXPECTED_TYPE}" == "any" ]]; then
                            STATUS="passed"
                            MESSAGE="File exists at ${PATH_TO_CHECK}"
                            DETAILS="{\"path\":\"${PATH_TO_CHECK}\",\"exists\":true,\"actual_type\":\"file\"}"
                            PASSED_COUNT=$((PASSED_COUNT + 1))
                        elif [[ -d "${PATH_TO_CHECK}" ]] && [[ "${EXPECTED_TYPE}" == "directory" || "${EXPECTED_TYPE}" == "any" ]]; then
                            STATUS="passed"
                            MESSAGE="Directory exists at ${PATH_TO_CHECK}"
                            DETAILS="{\"path\":\"${PATH_TO_CHECK}\",\"exists\":true,\"actual_type\":\"directory\"}"
                            PASSED_COUNT=$((PASSED_COUNT + 1))
                        else
                            STATUS="failed"
                            MESSAGE="Path exists but type mismatch (expected: ${EXPECTED_TYPE})"
                            DETAILS="{\"path\":\"${PATH_TO_CHECK}\",\"exists\":true,\"actual_type\":\"unknown\"}"
                            FAILED_COUNT=$((FAILED_COUNT + 1))
                        fi
                    else
                        STATUS="failed"
                        MESSAGE="Path does not exist: ${PATH_TO_CHECK}"
                        DETAILS="{\"path\":\"${PATH_TO_CHECK}\",\"exists\":false,\"actual_type\":\"not_found\"}"
                        FAILED_COUNT=$((FAILED_COUNT + 1))
                    fi
                    ;;
                "content_match")
                    FILE_PATH=$(echo "${RULE_CONFIG}" | jq -r ".file_path")
                    PATTERN=$(echo "${RULE_CONFIG}" | jq -r ".pattern")
                    MATCH_TYPE=$(echo "${RULE_CONFIG}" | jq -r ".match_type // \"contains\"")

                    if [[ ! -f "${FILE_PATH}" ]]; then
                        STATUS="failed"
                        MESSAGE="File not found: ${FILE_PATH}"
                        DETAILS="{\"file_path\":\"${FILE_PATH}\",\"pattern\":\"${PATTERN}\",\"matched\":false}"
                        FAILED_COUNT=$((FAILED_COUNT + 1))
                    else
                        MATCH_COUNT=0
                        case "${MATCH_TYPE}" in
                            "regex")
                                MATCH_COUNT=$(grep -c -E "${PATTERN}" "${FILE_PATH}" 2>/dev/null || echo "0")
                                ;;
                            "contains"|"literal")
                                MATCH_COUNT=$(grep -c -F "${PATTERN}" "${FILE_PATH}" 2>/dev/null || echo "0")
                                ;;
                        esac

                        if [[ ${MATCH_COUNT} -gt 0 ]]; then
                            STATUS="passed"
                            MESSAGE="Pattern matched ${MATCH_COUNT} times in ${FILE_PATH}"
                            DETAILS="{\"file_path\":\"${FILE_PATH}\",\"pattern\":\"${PATTERN}\",\"matched\":true,\"match_count\":${MATCH_COUNT}}"
                            PASSED_COUNT=$((PASSED_COUNT + 1))
                        else
                            STATUS="failed"
                            MESSAGE="Pattern not found in ${FILE_PATH}"
                            DETAILS="{\"file_path\":\"${FILE_PATH}\",\"pattern\":\"${PATTERN}\",\"matched\":false,\"match_count\":0}"
                            FAILED_COUNT=$((FAILED_COUNT + 1))
                        fi
                    fi
                    ;;
                "test_pass")
                    COMMAND=$(echo "${RULE_CONFIG}" | jq -r ".command")
                    WORKING_DIR=$(echo "${RULE_CONFIG}" | jq -r ".working_directory // \".\"")
                    EXPECTED_EXIT=$(echo "${RULE_CONFIG}" | jq -r ".expected_exit_code // 0")

                    START_TIME=$(date +%s)
                    STDOUT_FILE=$(mktemp)
                    STDERR_FILE=$(mktemp)

                    # Execute command without timeout (simplified for macOS compatibility)
                    (cd "${WORKING_DIR}" && bash -c "${COMMAND}" > "${STDOUT_FILE}" 2> "${STDERR_FILE}")
                    EXIT_CODE=$?

                    END_TIME=$(date +%s)
                    EXEC_TIME=$((END_TIME - START_TIME))
                    EXEC_TIME_MS=$((EXEC_TIME * 1000))

                    STDOUT_PREVIEW=$(head -c 500 "${STDOUT_FILE}" | tr -d "\n" | sed "s/\"/\\\\\"/g")
                    STDERR_PREVIEW=$(head -c 500 "${STDERR_FILE}" | tr -d "\n" | sed "s/\"/\\\\\"/g")

                    if [[ ${EXIT_CODE} -eq ${EXPECTED_EXIT} ]]; then
                        STATUS="passed"
                        MESSAGE="Test passed with exit code ${EXIT_CODE}"
                        PASSED_COUNT=$((PASSED_COUNT + 1))
                    else
                        STATUS="failed"
                        MESSAGE="Test failed with exit code ${EXIT_CODE} (expected: ${EXPECTED_EXIT})"
                        FAILED_COUNT=$((FAILED_COUNT + 1))
                    fi

                    DETAILS="{\"command\":\"${COMMAND}\",\"exit_code\":${EXIT_CODE},\"execution_time_ms\":${EXEC_TIME_MS},\"stdout_preview\":\"${STDOUT_PREVIEW}\",\"stderr_preview\":\"${STDERR_PREVIEW}\"}"

                    rm -f "${STDOUT_FILE}" "${STDERR_FILE}"
                    ;;
                "custom")
                    SCRIPT_PATH=$(echo "${RULE_CONFIG}" | jq -r ".script_path")

                    if [[ ! -f "${SCRIPT_PATH}" ]]; then
                        STATUS="failed"
                        MESSAGE="Custom script not found: ${SCRIPT_PATH}"
                        DETAILS="{\"script_path\":\"${SCRIPT_PATH}\",\"error\":\"Script not found\"}"
                        FAILED_COUNT=$((FAILED_COUNT + 1))
                    else
                        SCRIPT_OUTPUT=$(bash "${SCRIPT_PATH}" 2>&1)
                        SCRIPT_EXIT=$?

                        if [[ ${SCRIPT_EXIT} -eq 0 ]] && echo "${SCRIPT_OUTPUT}" | jq -e ".status == \"passed\"" >/dev/null 2>&1; then
                            STATUS="passed"
                            MESSAGE=$(echo "${SCRIPT_OUTPUT}" | jq -r ".message // \"Custom validation passed\"")
                            DETAILS="{\"script_path\":\"${SCRIPT_PATH}\",\"script_output\":${SCRIPT_OUTPUT},\"exit_code\":${SCRIPT_EXIT}}"
                            PASSED_COUNT=$((PASSED_COUNT + 1))
                        else
                            STATUS="failed"
                            MESSAGE="Custom validation failed"
                            DETAILS="{\"script_path\":\"${SCRIPT_PATH}\",\"error\":\"Script failed or returned invalid JSON\"}"
                            FAILED_COUNT=$((FAILED_COUNT + 1))
                        fi
                    fi
                    ;;
                *)
                    STATUS="skipped"
                    MESSAGE="Unknown rule type: ${RULE_TYPE}"
                    DETAILS="{\"error\":\"Unknown rule type\"}"
                    ;;
            esac

            # Add result to results array
            RESULT="{\"result_id\":\"${RESULT_ID}\",\"rule_id\":\"${RULE_ID}\",\"rule_type\":\"${RULE_TYPE}\",\"validated_at\":\"${VALIDATED_AT}\",\"status\":\"${STATUS}\",\"message\":\"${MESSAGE}\",\"details\":${DETAILS}}"
            RESULTS=$(echo "${RESULTS}" | jq -c ". + [${RESULT}]")

            # Track failed rules
            if [[ "${STATUS}" == "failed" ]] && [[ "${SEVERITY}" == "error" ]]; then
                FAILED_DETAIL="{\"rule_id\":\"${RULE_ID}\",\"message\":\"${MESSAGE}\",\"details\":${DETAILS}}"
                FAILED_DETAILS=$(echo "${FAILED_DETAILS}" | jq -c ". + [${FAILED_DETAIL}]")
            fi
        done

        # Determine overall status
        VALIDATION_STATUS="PASSED"
        if [[ ${FAILED_COUNT} -gt 0 ]]; then
            VALIDATION_STATUS="FAILED"
        fi

        # Build final result
        FINAL_RESULT=$(jq -n \
            --arg status "${VALIDATION_STATUS}" \
            --arg workflow_id "${WORKFLOW_ID}" \
            --arg session_id "${SESSION_ID}" \
            --arg phase_id "${PHASE_ID}" \
            --arg validated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
            --argjson total "${RULE_COUNT}" \
            --argjson passed "${PASSED_COUNT}" \
            --argjson failed "${FAILED_COUNT}" \
            --argjson results "${RESULTS}" \
            --argjson failed_details "${FAILED_DETAILS}" \
            "{
                validation_status: \$status,
                workflow_id: \$workflow_id,
                session_id: \$session_id,
                phase_id: \$phase_id,
                validated_at: \$validated_at,
                summary: {
                    total_rules: \$total,
                    passed_rules: \$passed,
                    failed_rules: \$failed,
                    skipped_rules: 0
                },
                rule_results: \$results,
                failed_rule_details: \$failed_details
            }")

        # Output result
        echo "${FINAL_RESULT}"

        # Exit with appropriate code
        if [[ "${VALIDATION_STATUS}" == "PASSED" ]]; then
            exit 0
        else
            exit 1
        fi
    ' 2>&1)
    else
        # No timeout command available - run without timeout
        validation_result=$(cat "${prompt_file}" | bash -c '
        # Simulate agent invocation by directly executing validation logic
        # In production, this would invoke the actual phase-validator agent
        # For now, we create a minimal validation executor

        CONFIG_FILE="'"${config_file}"'"
        WORKFLOW_ID="'"${workflow_id}"'"
        SESSION_ID="'"${session_id}"'"

        # Read and validate config file
        if [[ ! -f "${CONFIG_FILE}" ]]; then
            echo "{\"validation_status\":\"FAILED\",\"workflow_id\":\"${WORKFLOW_ID}\",\"session_id\":\"${SESSION_ID}\",\"validated_at\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"summary\":{\"total_rules\":0,\"passed_rules\":0,\"failed_rules\":1,\"skipped_rules\":0},\"rule_results\":[],\"failed_rule_details\":[{\"error\":\"Config file not found\"}]}"
            exit 1
        fi

        # Validate JSON syntax
        if ! jq empty "${CONFIG_FILE}" 2>/dev/null; then
            echo "{\"validation_status\":\"FAILED\",\"workflow_id\":\"${WORKFLOW_ID}\",\"session_id\":\"${SESSION_ID}\",\"validated_at\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"summary\":{\"total_rules\":0,\"passed_rules\":0,\"failed_rules\":1,\"skipped_rules\":0},\"rule_results\":[],\"failed_rule_details\":[{\"error\":\"Invalid JSON in config file\"}]}"
            exit 1
        fi

        # Extract phase metadata
        PHASE_ID=$(jq -r ".metadata.phase_id // \"unknown\"" "${CONFIG_FILE}")

        # Extract validation rules
        RULES=$(jq -c ".validation_config.rules // []" "${CONFIG_FILE}")
        RULE_COUNT=$(echo "${RULES}" | jq "length")

        # Initialize counters
        PASSED_COUNT=0
        FAILED_COUNT=0
        RESULTS="[]"
        FAILED_DETAILS="[]"

        # Execute each rule
        for ((i=0; i<RULE_COUNT; i++)); do
            RULE=$(echo "${RULES}" | jq -c ".[$i]")
            RULE_ID=$(echo "${RULE}" | jq -r ".rule_id")
            RULE_TYPE=$(echo "${RULE}" | jq -r ".rule_type")
            RULE_CONFIG=$(echo "${RULE}" | jq -c ".rule_config")
            SEVERITY=$(echo "${RULE}" | jq -r ".severity // \"error\"")

            RESULT_ID="result_$(date +%s)_${i}"
            VALIDATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            STATUS="failed"
            MESSAGE="Rule execution not implemented"
            DETAILS="{}"

            # Execute rule based on type
            case "${RULE_TYPE}" in
                "file_exists")
                    PATH_TO_CHECK=$(echo "${RULE_CONFIG}" | jq -r ".path")
                    EXPECTED_TYPE=$(echo "${RULE_CONFIG}" | jq -r ".type // \"any\"")

                    if [[ -e "${PATH_TO_CHECK}" ]]; then
                        if [[ -f "${PATH_TO_CHECK}" ]] && [[ "${EXPECTED_TYPE}" == "file" || "${EXPECTED_TYPE}" == "any" ]]; then
                            STATUS="passed"
                            MESSAGE="File exists at ${PATH_TO_CHECK}"
                            DETAILS="{\"path\":\"${PATH_TO_CHECK}\",\"exists\":true,\"actual_type\":\"file\"}"
                            PASSED_COUNT=$((PASSED_COUNT + 1))
                        elif [[ -d "${PATH_TO_CHECK}" ]] && [[ "${EXPECTED_TYPE}" == "directory" || "${EXPECTED_TYPE}" == "any" ]]; then
                            STATUS="passed"
                            MESSAGE="Directory exists at ${PATH_TO_CHECK}"
                            DETAILS="{\"path\":\"${PATH_TO_CHECK}\",\"exists\":true,\"actual_type\":\"directory\"}"
                            PASSED_COUNT=$((PASSED_COUNT + 1))
                        else
                            STATUS="failed"
                            MESSAGE="Path exists but type mismatch (expected: ${EXPECTED_TYPE})"
                            DETAILS="{\"path\":\"${PATH_TO_CHECK}\",\"exists\":true,\"actual_type\":\"unknown\"}"
                            FAILED_COUNT=$((FAILED_COUNT + 1))
                        fi
                    else
                        STATUS="failed"
                        MESSAGE="Path does not exist: ${PATH_TO_CHECK}"
                        DETAILS="{\"path\":\"${PATH_TO_CHECK}\",\"exists\":false,\"actual_type\":\"not_found\"}"
                        FAILED_COUNT=$((FAILED_COUNT + 1))
                    fi
                    ;;
                "content_match")
                    FILE_PATH=$(echo "${RULE_CONFIG}" | jq -r ".file_path")
                    PATTERN=$(echo "${RULE_CONFIG}" | jq -r ".pattern")
                    MATCH_TYPE=$(echo "${RULE_CONFIG}" | jq -r ".match_type // \"contains\"")

                    if [[ ! -f "${FILE_PATH}" ]]; then
                        STATUS="failed"
                        MESSAGE="File not found: ${FILE_PATH}"
                        DETAILS="{\"file_path\":\"${FILE_PATH}\",\"pattern\":\"${PATTERN}\",\"matched\":false}"
                        FAILED_COUNT=$((FAILED_COUNT + 1))
                    else
                        MATCH_COUNT=0
                        case "${MATCH_TYPE}" in
                            "regex")
                                MATCH_COUNT=$(grep -c -E "${PATTERN}" "${FILE_PATH}" 2>/dev/null || echo "0")
                                ;;
                            "contains"|"literal")
                                MATCH_COUNT=$(grep -c -F "${PATTERN}" "${FILE_PATH}" 2>/dev/null || echo "0")
                                ;;
                        esac

                        if [[ ${MATCH_COUNT} -gt 0 ]]; then
                            STATUS="passed"
                            MESSAGE="Pattern matched ${MATCH_COUNT} times in ${FILE_PATH}"
                            DETAILS="{\"file_path\":\"${FILE_PATH}\",\"pattern\":\"${PATTERN}\",\"matched\":true,\"match_count\":${MATCH_COUNT}}"
                            PASSED_COUNT=$((PASSED_COUNT + 1))
                        else
                            STATUS="failed"
                            MESSAGE="Pattern not found in ${FILE_PATH}"
                            DETAILS="{\"file_path\":\"${FILE_PATH}\",\"pattern\":\"${PATTERN}\",\"matched\":false,\"match_count\":0}"
                            FAILED_COUNT=$((FAILED_COUNT + 1))
                        fi
                    fi
                    ;;
                "test_pass")
                    COMMAND=$(echo "${RULE_CONFIG}" | jq -r ".command")
                    WORKING_DIR=$(echo "${RULE_CONFIG}" | jq -r ".working_directory // \".\"")

                    START_TIME=$(date +%s)
                    STDOUT_FILE=$(mktemp)
                    STDERR_FILE=$(mktemp)

                    (cd "${WORKING_DIR}" && bash -c "${COMMAND}" > "${STDOUT_FILE}" 2> "${STDERR_FILE}")
                    EXIT_CODE=$?

                    END_TIME=$(date +%s)
                    EXEC_TIME=$((END_TIME - START_TIME))
                    EXEC_TIME_MS=$((EXEC_TIME * 1000))

                    STDOUT_PREVIEW=$(head -c 500 "${STDOUT_FILE}" | tr -d "\n" | sed "s/\"/\\\\\"/g")
                    STDERR_PREVIEW=$(head -c 500 "${STDERR_FILE}" | tr -d "\n" | sed "s/\"/\\\\\"/g")

                    EXPECTED_EXIT=$(echo "${RULE_CONFIG}" | jq -r ".expected_exit_code // 0")
                    if [[ ${EXIT_CODE} -eq ${EXPECTED_EXIT} ]]; then
                        STATUS="passed"
                        MESSAGE="Test passed with exit code ${EXIT_CODE}"
                        PASSED_COUNT=$((PASSED_COUNT + 1))
                    else
                        STATUS="failed"
                        MESSAGE="Test failed with exit code ${EXIT_CODE} (expected: ${EXPECTED_EXIT})"
                        FAILED_COUNT=$((FAILED_COUNT + 1))
                    fi

                    DETAILS="{\"command\":\"${COMMAND}\",\"exit_code\":${EXIT_CODE},\"execution_time_ms\":${EXEC_TIME_MS},\"stdout_preview\":\"${STDOUT_PREVIEW}\",\"stderr_preview\":\"${STDERR_PREVIEW}\"}"

                    rm -f "${STDOUT_FILE}" "${STDERR_FILE}"
                    ;;
                "custom")
                    SCRIPT_PATH=$(echo "${RULE_CONFIG}" | jq -r ".script_path")

                    if [[ ! -f "${SCRIPT_PATH}" ]]; then
                        STATUS="failed"
                        MESSAGE="Custom script not found: ${SCRIPT_PATH}"
                        DETAILS="{\"script_path\":\"${SCRIPT_PATH}\",\"error\":\"Script not found\"}"
                        FAILED_COUNT=$((FAILED_COUNT + 1))
                    else
                        SCRIPT_OUTPUT=$(bash "${SCRIPT_PATH}" 2>&1)
                        SCRIPT_EXIT=$?

                        if [[ ${SCRIPT_EXIT} -eq 0 ]] && echo "${SCRIPT_OUTPUT}" | jq -e ".status == \"passed\"" >/dev/null 2>&1; then
                            STATUS="passed"
                            MESSAGE=$(echo "${SCRIPT_OUTPUT}" | jq -r ".message // \"Custom validation passed\"")
                            DETAILS="{\"script_path\":\"${SCRIPT_PATH}\",\"script_output\":${SCRIPT_OUTPUT},\"exit_code\":${SCRIPT_EXIT}}"
                            PASSED_COUNT=$((PASSED_COUNT + 1))
                        else
                            STATUS="failed"
                            MESSAGE="Custom validation failed"
                            DETAILS="{\"script_path\":\"${SCRIPT_PATH}\",\"error\":\"Script failed or returned invalid JSON\"}"
                            FAILED_COUNT=$((FAILED_COUNT + 1))
                        fi
                    fi
                    ;;
                *)
                    STATUS="skipped"
                    MESSAGE="Unknown rule type: ${RULE_TYPE}"
                    DETAILS="{\"error\":\"Unknown rule type\"}"
                    ;;
            esac

            # Add result to results array
            RESULT="{\"result_id\":\"${RESULT_ID}\",\"rule_id\":\"${RULE_ID}\",\"rule_type\":\"${RULE_TYPE}\",\"validated_at\":\"${VALIDATED_AT}\",\"status\":\"${STATUS}\",\"message\":\"${MESSAGE}\",\"details\":${DETAILS}}"
            RESULTS=$(echo "${RESULTS}" | jq -c ". + [${RESULT}]")

            # Track failed rules
            if [[ "${STATUS}" == "failed" ]] && [[ "${SEVERITY}" == "error" ]]; then
                FAILED_DETAIL="{\"rule_id\":\"${RULE_ID}\",\"message\":\"${MESSAGE}\",\"details\":${DETAILS}}"
                FAILED_DETAILS=$(echo "${FAILED_DETAILS}" | jq -c ". + [${FAILED_DETAIL}]")
            fi
        done

        # Determine overall status
        VALIDATION_STATUS="PASSED"
        if [[ ${FAILED_COUNT} -gt 0 ]]; then
            VALIDATION_STATUS="FAILED"
        fi

        # Build final result
        FINAL_RESULT=$(jq -n \
            --arg status "${VALIDATION_STATUS}" \
            --arg workflow_id "${WORKFLOW_ID}" \
            --arg session_id "${SESSION_ID}" \
            --arg phase_id "${PHASE_ID}" \
            --arg validated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
            --argjson total "${RULE_COUNT}" \
            --argjson passed "${PASSED_COUNT}" \
            --argjson failed "${FAILED_COUNT}" \
            --argjson results "${RESULTS}" \
            --argjson failed_details "${FAILED_DETAILS}" \
            "{
                validation_status: \$status,
                workflow_id: \$workflow_id,
                session_id: \$session_id,
                phase_id: \$phase_id,
                validated_at: \$validated_at,
                summary: {
                    total_rules: \$total,
                    passed_rules: \$passed,
                    failed_rules: \$failed,
                    skipped_rules: 0
                },
                rule_results: \$results,
                failed_rule_details: \$failed_details
            }")

        # Output result
        echo "${FINAL_RESULT}"

        # Exit with appropriate code
        if [[ "${VALIDATION_STATUS}" == "PASSED" ]]; then
            exit 0
        else
            exit 1
        fi
    ' 2>&1)
    fi

    validation_exit_code=$?

    # Clean up temporary prompt file
    rm -f "${prompt_file}"

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

    # Detect validation trigger (reads stdin, outputs status)
    local trigger_result
    trigger_result="$(detect_validation_trigger)"
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

            # Check if current phase needs validation
            if should_validate_phase "${session_id}" "${workflow_id}"; then
                log_event "VALIDATION" "gate" "Phase validation required (session: ${session_id}, workflow: ${workflow_id})"

                # Find validation config file
                local config_file
                if [[ -n "${workflow_id}" ]]; then
                    # Search for workflow-specific config first
                    config_file=$(find "${VALIDATION_STATE_DIR}" -maxdepth 1 -name "phase_${workflow_id}_*.json" 2>/dev/null | head -n 1)
                fi

                # If no workflow-specific config, search for any phase config
                if [[ -z "${config_file}" ]]; then
                    config_file=$(find "${VALIDATION_STATE_DIR}" -maxdepth 1 -name "phase_*.json" 2>/dev/null | head -n 1)
                fi

                # Invoke validation with config file
                if [[ -n "${config_file}" ]]; then
                    local validation_result
                    validation_result=$(invoke_validation "${config_file}" "${workflow_id}" "${session_id}")
                    local validation_exit_code=$?

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
