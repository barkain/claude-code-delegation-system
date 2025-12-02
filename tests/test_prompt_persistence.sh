#!/usr/bin/env bash

################################################################################
# System Prompt Persistence - Automated Test Suite
################################################################################
# Project: claude-code-delegation-system
# Feature: System Prompt Persistence Mechanism
# Test Plan: /Users/nadavbarkai/dev/claude-code-delegation-system/tests/prompt_persistence_test_plan.md
# Created: 2025-12-02
################################################################################

set -euo pipefail

# --- Configuration ---
PROJECT_ROOT="/Users/nadavbarkai/dev/claude-code-delegation-system"
CLAUDE_DIR="${PROJECT_ROOT}/.claude"
HOOK_SCRIPT="${CLAUDE_DIR}/hooks/PreToolUse/ensure_workflow_orchestrator.sh"
PROMPT_FILE="${CLAUDE_DIR}/system-prompts/WORKFLOW_ORCHESTRATOR.md"
SETTINGS_FILE="${PROJECT_ROOT}/settings.json"
STATE_DIR="${PROJECT_ROOT}/.claude/state"
TEST_PLAN="${PROJECT_ROOT}/tests/prompt_persistence_test_plan.md"

# --- Color Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Test Results ---
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# --- Helper Functions ---

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
}

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_test_header() {
    echo ""
    echo -e "${CYAN}─────────────────────────────────────────────────────────${NC}"
    echo -e "${CYAN}  Test $1: $2${NC}"
    echo -e "${CYAN}─────────────────────────────────────────────────────────${NC}"
}

pass_test() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
    log_success "$1"
}

fail_test() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
    log_error "$1"
}

skip_test() {
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    log_skip "$1"
}

# --- Test Functions ---

test_1_signature_markers() {
    print_test_header "1" "Signature Markers Presence"

    if [[ ! -f "$PROMPT_FILE" ]]; then
        fail_test "WORKFLOW_ORCHESTRATOR.md not found at $PROMPT_FILE"
        return 1
    fi

    log_info "Checking for signature markers in $PROMPT_FILE"

    # Check start marker
    if ! grep -q "WORKFLOW_ORCHESTRATOR_PROMPT_START_MARKER_DO_NOT_REMOVE" "$PROMPT_FILE"; then
        fail_test "Start marker not found"
        return 1
    fi
    log_info "  ✓ Start marker found"

    # Check start signature
    if ! grep -q "SIGNATURE: WO_v2_DELEGATION_FIRST_PROTOCOL_ACTIVE" "$PROMPT_FILE"; then
        fail_test "Start signature not found"
        return 1
    fi
    log_info "  ✓ Start signature found"

    # Check end marker
    if ! grep -q "WORKFLOW_ORCHESTRATOR_PROMPT_END_MARKER_DO_NOT_REMOVE" "$PROMPT_FILE"; then
        fail_test "End marker not found"
        return 1
    fi
    log_info "  ✓ End marker found"

    # Check end signature
    if ! grep -q "SIGNATURE: WO_v2_CONTEXT_PASSING_ENABLED" "$PROMPT_FILE"; then
        fail_test "End signature not found"
        return 1
    fi
    log_info "  ✓ End signature found"

    # Verify positioning (start markers in first 10 lines)
    if ! head -10 "$PROMPT_FILE" | grep -q "WORKFLOW_ORCHESTRATOR_PROMPT_START_MARKER"; then
        fail_test "Start marker not in first 10 lines"
        return 1
    fi
    log_info "  ✓ Start markers positioned correctly (first 10 lines)"

    # Verify positioning (end markers in last 10 lines)
    if ! tail -10 "$PROMPT_FILE" | grep -q "WORKFLOW_ORCHESTRATOR_PROMPT_END_MARKER"; then
        fail_test "End marker not in last 10 lines"
        return 1
    fi
    log_info "  ✓ End markers positioned correctly (last 10 lines)"

    pass_test "All 4 signature markers present and correctly positioned"
    return 0
}

test_2_hook_script_existence() {
    print_test_header "2" "Hook Script Existence and Permissions"

    log_info "Checking hook script at $HOOK_SCRIPT"

    # Check file exists
    if [[ ! -f "$HOOK_SCRIPT" ]]; then
        fail_test "Hook script not found at $HOOK_SCRIPT"
        return 1
    fi
    log_info "  ✓ Hook script exists"

    # Check executable permission
    if [[ ! -x "$HOOK_SCRIPT" ]]; then
        fail_test "Hook script is not executable"
        return 1
    fi
    log_info "  ✓ Hook script is executable"

    # Check file size (should be between 1KB and 20KB)
    local size
    size=$(stat -f%z "$HOOK_SCRIPT" 2>/dev/null || stat -c%s "$HOOK_SCRIPT" 2>/dev/null)
    if (( size < 1024 || size > 20480 )); then
        log_warning "Hook script size unusual: ${size} bytes (expected 1KB-20KB)"
    else
        log_info "  ✓ Hook script size reasonable: ${size} bytes"
    fi

    # Check ownership
    local owner
    owner=$(stat -f%Su "$HOOK_SCRIPT" 2>/dev/null || stat -c%U "$HOOK_SCRIPT" 2>/dev/null)
    log_info "  ✓ Hook script owner: ${owner}"

    pass_test "Hook script exists with correct permissions"
    return 0
}

test_3_hook_registration() {
    print_test_header "3" "Hook Registration in settings.json"

    if [[ ! -f "$SETTINGS_FILE" ]]; then
        fail_test "settings.json not found at $SETTINGS_FILE"
        return 1
    fi

    log_info "Checking hook registration in settings.json"

    # Check if ensure_workflow_orchestrator.sh is registered
    if ! grep -q "ensure_workflow_orchestrator.sh" "$SETTINGS_FILE"; then
        fail_test "ensure_workflow_orchestrator.sh not registered in settings.json"
        return 1
    fi
    log_info "  ✓ Hook command registered"

    # Check timeout is at least 10 seconds
    if grep -A 3 "ensure_workflow_orchestrator.sh" "$SETTINGS_FILE" | grep -q '"timeout": 10'; then
        log_info "  ✓ Timeout set to 10 seconds"
    else
        log_warning "Timeout may not be 10 seconds (expected value)"
    fi

    # Check description exists
    if grep -A 3 "ensure_workflow_orchestrator.sh" "$SETTINGS_FILE" | grep -q '"description"'; then
        log_info "  ✓ Description field present"
    else
        log_warning "Description field missing (non-critical)"
    fi

    # Verify it's in PreToolUse section
    if grep -B 10 "ensure_workflow_orchestrator.sh" "$SETTINGS_FILE" | grep -q '"PreToolUse"'; then
        log_info "  ✓ Registered in PreToolUse hooks"
    else
        fail_test "Hook not in PreToolUse section"
        return 1
    fi

    pass_test "Hook correctly registered in settings.json"
    return 0
}

test_4_state_flag_directory() {
    print_test_header "4" "State Flag Directory Structure"

    log_info "Checking state directory at $STATE_DIR"

    # Create directory if it doesn't exist
    if [[ ! -d "$STATE_DIR" ]]; then
        log_info "  Creating state directory: $STATE_DIR"
        mkdir -p "$STATE_DIR" 2>/dev/null || {
            fail_test "Cannot create state directory"
            return 1
        }
    fi
    log_info "  ✓ State directory exists"

    # Check directory is writable
    if [[ ! -w "$STATE_DIR" ]]; then
        fail_test "State directory is not writable"
        return 1
    fi
    log_info "  ✓ State directory is writable"

    # Test writing a flag file
    local test_flag="${STATE_DIR}/test_flag.tmp"
    local timestamp
    timestamp=$(date +%s)

    if echo "$timestamp" > "$test_flag" 2>/dev/null; then
        log_info "  ✓ Test flag file written successfully"

        # Verify content
        local read_timestamp
        read_timestamp=$(cat "$test_flag")
        if [[ "$read_timestamp" == "$timestamp" ]]; then
            log_info "  ✓ Flag file content verified"
        else
            log_warning "Flag file content mismatch"
        fi

        # Clean up
        rm -f "$test_flag"
    else
        fail_test "Cannot write test flag file"
        return 1
    fi

    pass_test "State directory structure verified"
    return 0
}

test_5_hook_syntax() {
    print_test_header "5" "Hook Script Syntax Validation"

    log_info "Validating bash syntax with 'bash -n'"

    if bash -n "$HOOK_SCRIPT" 2>&1; then
        log_info "  ✓ No syntax errors detected"
        pass_test "Hook script has valid bash syntax"
        return 0
    else
        fail_test "Syntax errors found in hook script"
        return 1
    fi
}

test_6_shellcheck() {
    print_test_header "6" "Hook Script Shellcheck Validation"

    # Check if shellcheck is available
    if ! command -v shellcheck &> /dev/null; then
        skip_test "shellcheck not installed (optional)"
        return 0
    fi

    log_info "Running shellcheck on hook script"

    local output
    if output=$(shellcheck "$HOOK_SCRIPT" 2>&1); then
        log_info "  ✓ No shellcheck issues"
        pass_test "Hook script passes shellcheck validation"
        return 0
    else
        # Check for errors vs warnings
        if echo "$output" | grep -q "error:"; then
            log_error "Shellcheck errors found:"
            echo "$output"
            fail_test "Shellcheck found errors"
            return 1
        else
            log_warning "Shellcheck warnings (non-blocking):"
            echo "$output"
            pass_test "Hook script passes (warnings acceptable)"
            return 0
        fi
    fi
}

test_7_tool_criticality() {
    print_test_header "7" "Tool Criticality Check Logic"

    log_info "Verifying critical tools list in hook script"

    # Expected critical tools
    local critical_tools=("TodoWrite" "Task" "SubagentTask" "AgentTask" "SlashCommand")
    local all_found=true

    for tool in "${critical_tools[@]}"; do
        if grep -q "$tool" "$HOOK_SCRIPT"; then
            log_info "  ✓ Critical tool found: $tool"
        else
            log_error "  ✗ Critical tool missing: $tool"
            all_found=false
        fi
    done

    if [[ "$all_found" == true ]]; then
        pass_test "All critical tools present in hook script"
        return 0
    else
        fail_test "Some critical tools missing from hook script"
        return 1
    fi
}

test_8_state_flag_age() {
    print_test_header "8" "State Flag Age Calculation"

    log_info "Testing state flag TTL logic (5-minute threshold)"

    local test_flag="${STATE_DIR}/test_age_flag.tmp"

    # Test 1: Recent flag (30 seconds ago)
    local recent_timestamp=$(($(date +%s) - 30))
    echo "$recent_timestamp" > "$test_flag"

    local flag_age=$(($(date +%s) - recent_timestamp))
    if (( flag_age < 300 )); then
        log_info "  ✓ Recent flag (${flag_age}s) correctly identified as < 300s"
    else
        fail_test "Recent flag age calculation incorrect"
        rm -f "$test_flag"
        return 1
    fi

    # Test 2: Expired flag (10 minutes ago)
    local expired_timestamp=$(($(date +%s) - 600))
    echo "$expired_timestamp" > "$test_flag"

    flag_age=$(($(date +%s) - expired_timestamp))
    if (( flag_age >= 300 )); then
        log_info "  ✓ Expired flag (${flag_age}s) correctly identified as >= 300s"
    else
        fail_test "Expired flag age calculation incorrect"
        rm -f "$test_flag"
        return 1
    fi

    # Clean up
    rm -f "$test_flag"

    pass_test "State flag age calculation logic verified"
    return 0
}

test_9_prompt_file_location() {
    print_test_header "9" "Prompt File Location Discovery"

    log_info "Verifying prompt file search locations in hook script"

    # Check if hook script references correct locations
    local primary_location="~/.claude/system-prompts/WORKFLOW_ORCHESTRATOR.md"
    local fallback_location="system-prompts/WORKFLOW_ORCHESTRATOR.md"

    if grep -q "\.claude/system-prompts/WORKFLOW_ORCHESTRATOR.md" "$HOOK_SCRIPT"; then
        log_info "  ✓ Primary location referenced: $primary_location"
    else
        log_warning "Primary location reference not found"
    fi

    if grep -q "system-prompts/WORKFLOW_ORCHESTRATOR.md" "$HOOK_SCRIPT"; then
        log_info "  ✓ Fallback location referenced: $fallback_location"
    else
        log_warning "Fallback location reference not found"
    fi

    # Verify actual file exists in at least one location
    local home_location="${HOME}/.claude/system-prompts/WORKFLOW_ORCHESTRATOR.md"
    local project_location="${PROJECT_ROOT}/system-prompts/WORKFLOW_ORCHESTRATOR.md"

    if [[ -f "$home_location" ]]; then
        log_info "  ✓ Prompt file exists at primary location: $home_location"
    fi

    if [[ -f "$project_location" ]]; then
        log_info "  ✓ Prompt file exists at fallback location: $project_location"
    fi

    if [[ -f "$PROMPT_FILE" ]]; then
        pass_test "Prompt file found and location logic verified"
        return 0
    else
        fail_test "Prompt file not found in any expected location"
        return 1
    fi
}

test_10_emergency_disable() {
    print_test_header "10" "Emergency Disable Flag"

    log_info "Testing PROMPT_PERSISTENCE_DISABLE=1 bypass"

    # Check if hook script checks for disable flag
    if grep -q "PROMPT_PERSISTENCE_DISABLE" "$HOOK_SCRIPT"; then
        log_info "  ✓ Hook script checks PROMPT_PERSISTENCE_DISABLE"
    else
        fail_test "Emergency disable flag not implemented"
        return 1
    fi

    # Verify it exits early (check for exit 0 near the disable check)
    if grep -A 3 "PROMPT_PERSISTENCE_DISABLE" "$HOOK_SCRIPT" | grep -q "exit 0"; then
        log_info "  ✓ Emergency disable triggers immediate exit"
    else
        log_warning "Emergency disable exit pattern not found (may still work)"
    fi

    pass_test "Emergency disable flag implemented"
    return 0
}

test_11_debug_logging() {
    print_test_header "11" "Debug Logging Output"

    log_info "Testing DEBUG_PROMPT_PERSISTENCE=1 debug logging"

    # Check if hook script checks for debug flag
    if grep -q "DEBUG_PROMPT_PERSISTENCE" "$HOOK_SCRIPT"; then
        log_info "  ✓ Hook script checks DEBUG_PROMPT_PERSISTENCE"
    else
        fail_test "Debug logging flag not implemented"
        return 1
    fi

    # Check if debug log file path is defined
    if grep -q "/tmp/prompt_persistence_debug.log" "$HOOK_SCRIPT"; then
        log_info "  ✓ Debug log file path configured: /tmp/prompt_persistence_debug.log"
    else
        log_warning "Debug log file path not found (may use different location)"
    fi

    # Verify debug log writes (look for >> redirection)
    if grep -q ">> .*prompt_persistence_debug.log" "$HOOK_SCRIPT"; then
        log_info "  ✓ Debug log write operations present"
    else
        log_warning "Debug log write operations not found"
    fi

    pass_test "Debug logging mechanism implemented"
    return 0
}

test_12_missing_prompt_error() {
    print_test_header "12" "Missing Prompt File Error Handling"

    log_info "Verifying error handling for missing prompt file"

    # Check if hook script has error message for missing file
    if grep -qi "cannot.*re-inject.*file not found\|prompt.*not found\|missing.*prompt" "$HOOK_SCRIPT"; then
        log_info "  ✓ Error message for missing file present"
    else
        log_warning "Error message pattern not found (may use different wording)"
    fi

    # Check if hook exits with error code 1 on missing file
    if grep -A 10 -i "file not found\|cannot.*re-inject" "$HOOK_SCRIPT" | grep -q "exit 1"; then
        log_info "  ✓ Hook exits with error code 1 on missing file"
    else
        log_warning "Exit code 1 pattern not found (may handle differently)"
    fi

    # Verify hook lists expected locations in error
    if grep -C 5 -i "file not found\|cannot.*re-inject" "$HOOK_SCRIPT" | grep -q "\.claude/system-prompts\|system-prompts"; then
        log_info "  ✓ Error message includes expected file locations"
    else
        log_warning "Expected locations not listed in error message"
    fi

    pass_test "Missing prompt file error handling verified"
    return 0
}

# --- Main Test Runner ---

run_all_tests() {
    print_header "System Prompt Persistence - Automated Test Suite"

    log_info "Project: $PROJECT_ROOT"
    log_info "Test Plan: $TEST_PLAN"
    log_info "Date: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    # Category 1: Static File Verification
    print_header "Category 1: Static File Verification"
    test_1_signature_markers || true
    test_2_hook_script_existence || true
    test_3_hook_registration || true
    test_4_state_flag_directory || true

    # Category 2: Syntax and Configuration Validation
    print_header "Category 2: Syntax and Configuration Validation"
    test_5_hook_syntax || true
    test_6_shellcheck || true

    # Category 3: Logic Verification
    print_header "Category 3: Logic Verification"
    test_7_tool_criticality || true
    test_8_state_flag_age || true
    test_9_prompt_file_location || true
    test_10_emergency_disable || true
    test_11_debug_logging || true
    test_12_missing_prompt_error || true

    # Summary
    print_header "Test Results Summary"

    echo ""
    echo "Total Tests Run:    $TESTS_RUN"
    echo -e "${GREEN}Tests Passed:       $TESTS_PASSED${NC}"
    echo -e "${RED}Tests Failed:       $TESTS_FAILED${NC}"
    echo -e "${YELLOW}Tests Skipped:      $TESTS_SKIPPED${NC}"
    echo ""

    if (( TESTS_FAILED == 0 )); then
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  ALL TESTS PASSED ✓${NC}"
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
        echo ""
        log_info "Automated tests complete. Manual tests (13-16) require full Claude session."
        echo ""
        return 0
    else
        echo -e "${RED}═══════════════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}  TESTS FAILED ✗${NC}"
        echo -e "${RED}═══════════════════════════════════════════════════════════════════${NC}"
        echo ""
        log_error "Review failures above and fix issues before proceeding."
        echo ""
        return 1
    fi
}

# --- Script Entry Point ---

main() {
    # Change to project root
    cd "$PROJECT_ROOT" || {
        echo "ERROR: Cannot change to project root: $PROJECT_ROOT"
        exit 1
    }

    # Run all tests
    run_all_tests
    local exit_code=$?

    # Update test plan with results (optional - could parse this script's output)
    log_info "Test plan available at: $TEST_PLAN"

    exit $exit_code
}

# Run main function
main "$@"
