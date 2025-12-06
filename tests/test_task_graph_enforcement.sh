#!/usr/bin/env bash

# Task Graph Enforcement Test Suite
# Project: claude-code-delegation-system
# Version: 1.0

set -uo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
CRITICAL_TESTS=0
CRITICAL_PASSED=0

# Project paths
PROJECT_DIR="/Users/nadavbarkai/dev/claude-code-delegation-system"
HOOKS_DIR="${PROJECT_DIR}/hooks"
AGENTS_DIR="${PROJECT_DIR}/agents"
SYSTEM_PROMPTS_DIR="${PROJECT_DIR}/system-prompts"
COMMANDS_DIR="${PROJECT_DIR}/commands"
SETTINGS_FILE="${PROJECT_DIR}/settings.json"
STATE_DIR="${PROJECT_DIR}/.claude/state"
TEST_STATE_FILE="${STATE_DIR}/test_active_task_graph.json"

# Test utilities
pass_test() {
    local test_id="$1"
    local description="$2"
    echo -e "${GREEN}[PASS]${NC} ${test_id}: ${description}"
    ((PASSED_TESTS++))
    ((TOTAL_TESTS++))
}

fail_test() {
    local test_id="$1"
    local description="$2"
    local error="${3:-}"
    echo -e "${RED}[FAIL]${NC} ${test_id}: ${description}"
    if [[ -n "$error" ]]; then
        echo -e "       ${YELLOW}Error: ${error}${NC}"
    fi
    ((FAILED_TESTS++))
    ((TOTAL_TESTS++))
}

skip_test() {
    local test_id="$1"
    local description="$2"
    local reason="${3:-}"
    echo -e "${YELLOW}[SKIP]${NC} ${test_id}: ${description}"
    if [[ -n "$reason" ]]; then
        echo -e "       ${YELLOW}Reason: ${reason}${NC}"
    fi
    ((TOTAL_TESTS++))
}

critical_test() {
    ((CRITICAL_TESTS++))
}

critical_pass() {
    ((CRITICAL_PASSED++))
}

header() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
}

# Cleanup function
cleanup() {
    if [[ -f "$TEST_STATE_FILE" ]]; then
        rm -f "$TEST_STATE_FILE"
    fi
}

# Setup function
setup() {
    # Create state directory if it doesn't exist
    mkdir -p "$STATE_DIR"

    # Clean up any existing test state files
    cleanup
}

# Trap cleanup on exit
trap cleanup EXIT

# Helper: Create minimal valid state file
create_valid_state_file() {
    local current_wave="${1:-0}"
    local total_waves="${2:-2}"

    cat > "$TEST_STATE_FILE" <<EOF
{
  "schema_version": "1.0",
  "task_graph_id": "tg_test_$(date +%s)",
  "status": "in_progress",
  "current_wave": $current_wave,
  "total_waves": $total_waves,
  "execution_plan": {
    "schema_version": "1.0",
    "task_graph_id": "tg_test_$(date +%s)",
    "execution_mode": "parallel",
    "total_waves": $total_waves,
    "total_phases": 2,
    "waves": [
      {
        "wave_id": 0,
        "parallel_execution": true,
        "phases": [
          {
            "phase_id": "phase_0_0",
            "description": "Test phase 0",
            "agent": "test-agent",
            "dependencies": []
          },
          {
            "phase_id": "phase_0_1",
            "description": "Test phase 1",
            "agent": "test-agent",
            "dependencies": []
          }
        ]
      },
      {
        "wave_id": 1,
        "parallel_execution": false,
        "phases": [
          {
            "phase_id": "phase_1_0",
            "description": "Test phase 2",
            "agent": "test-agent",
            "dependencies": ["phase_0_0", "phase_0_1"]
          }
        ]
      }
    ],
    "dependency_graph": {
      "phase_0_0": [],
      "phase_0_1": [],
      "phase_1_0": ["phase_0_0", "phase_0_1"]
    }
  },
  "phase_status": {},
  "wave_status": {
    "0": {
      "status": "in_progress",
      "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    }
  },
  "compliance_log": []
}
EOF
}

# Helper: Run PreToolUse hook
run_pretooluse_hook() {
    local prompt="$1"
    local state_file="${2:-$TEST_STATE_FILE}"

    # Export state file location for hook to find
    export CLAUDE_PROJECT_DIR="$PROJECT_DIR"

    # Temporarily move test state to expected location
    if [[ -f "$state_file" ]]; then
        cp "$state_file" "${STATE_DIR}/active_task_graph.json"
    fi

    # Run hook
    local exit_code=0
    "${HOOKS_DIR}/PreToolUse/validate_task_graph_compliance.sh" "Task" "$prompt" 2>&1 || exit_code=$?

    # Clean up
    if [[ -f "${STATE_DIR}/active_task_graph.json" ]]; then
        rm -f "${STATE_DIR}/active_task_graph.json"
    fi

    return $exit_code
}

# Helper: Run PostToolUse hook
run_posttooluse_hook() {
    local result="$1"
    local exit_code="${2:-0}"
    local state_file="${3:-$TEST_STATE_FILE}"

    export CLAUDE_PROJECT_DIR="$PROJECT_DIR"

    if [[ -f "$state_file" ]]; then
        cp "$state_file" "${STATE_DIR}/active_task_graph.json"
    fi

    local hook_exit=0
    "${HOOKS_DIR}/PostToolUse/update_wave_state.sh" "Task" "$result" "$exit_code" 2>&1 || hook_exit=$?

    # Copy back for inspection
    if [[ -f "${STATE_DIR}/active_task_graph.json" ]]; then
        cp "${STATE_DIR}/active_task_graph.json" "$state_file"
        rm -f "${STATE_DIR}/active_task_graph.json"
    fi

    return $hook_exit
}

# Start tests
echo -e "${BLUE}"
echo "======================================"
echo "Task Graph Enforcement Test Suite"
echo "======================================"
echo -e "${NC}"
echo "Project: $PROJECT_DIR"
echo "Date: $(date)"
echo ""

setup

# ==========================================
# Category 1: Hook Installation Tests
# ==========================================
header "Category 1: Hook Installation Tests"

# Test 1.1
critical_test
if [[ -f "${HOOKS_DIR}/PreToolUse/validate_task_graph_compliance.sh" ]]; then
    pass_test "HOOK-INSTALL-001" "validate_task_graph_compliance.sh exists"
    critical_pass
else
    fail_test "HOOK-INSTALL-001" "validate_task_graph_compliance.sh exists" "File not found"
fi

# Test 1.2
critical_test
if [[ -x "${HOOKS_DIR}/PreToolUse/validate_task_graph_compliance.sh" ]]; then
    pass_test "HOOK-INSTALL-002" "validate_task_graph_compliance.sh is executable"
    critical_pass
else
    fail_test "HOOK-INSTALL-002" "validate_task_graph_compliance.sh is executable" "Execute permission missing"
fi

# Test 1.3
critical_test
if [[ -f "${HOOKS_DIR}/PostToolUse/update_wave_state.sh" ]]; then
    pass_test "HOOK-INSTALL-003" "update_wave_state.sh exists"
    critical_pass
else
    fail_test "HOOK-INSTALL-003" "update_wave_state.sh exists" "File not found"
fi

# Test 1.4
critical_test
if [[ -x "${HOOKS_DIR}/PostToolUse/update_wave_state.sh" ]]; then
    pass_test "HOOK-INSTALL-004" "update_wave_state.sh is executable"
    critical_pass
else
    fail_test "HOOK-INSTALL-004" "update_wave_state.sh is executable" "Execute permission missing"
fi

# Test 1.5
critical_test
if jq -e '.hooks.PreToolUse[] | select(.matcher == "Task") | .hooks[] | select(.command | contains("validate_task_graph_compliance.sh"))' "$SETTINGS_FILE" >/dev/null 2>&1; then
    pass_test "HOOK-INSTALL-005" "PreToolUse hook registered in settings.json"
    critical_pass
else
    fail_test "HOOK-INSTALL-005" "PreToolUse hook registered in settings.json" "Hook not found in settings"
fi

# Test 1.6
critical_test
if jq -e '.hooks.PostToolUse[] | select(.matcher == "Task") | .hooks[] | select(.command | contains("update_wave_state.sh"))' "$SETTINGS_FILE" >/dev/null 2>&1; then
    pass_test "HOOK-INSTALL-006" "PostToolUse hook registered in settings.json"
    critical_pass
else
    fail_test "HOOK-INSTALL-006" "PostToolUse hook registered in settings.json" "Hook not found in settings"
fi

# ==========================================
# Category 2: Hook Script Validation Tests
# ==========================================
header "Category 2: Hook Script Validation Tests"

# Test 2.1
critical_test
if bash -n "${HOOKS_DIR}/PreToolUse/validate_task_graph_compliance.sh" 2>/dev/null; then
    pass_test "HOOK-SYNTAX-001" "validate_task_graph_compliance.sh syntax check"
    critical_pass
else
    fail_test "HOOK-SYNTAX-001" "validate_task_graph_compliance.sh syntax check" "Bash syntax errors detected"
fi

# Test 2.2
critical_test
if bash -n "${HOOKS_DIR}/PostToolUse/update_wave_state.sh" 2>/dev/null; then
    pass_test "HOOK-SYNTAX-002" "update_wave_state.sh syntax check"
    critical_pass
else
    fail_test "HOOK-SYNTAX-002" "update_wave_state.sh syntax check" "Bash syntax errors detected"
fi

# Test 2.3
critical_test
# Ensure no state file exists
rm -f "${STATE_DIR}/active_task_graph.json"
if run_pretooluse_hook "test prompt" "/dev/null" >/dev/null 2>&1; then
    pass_test "HOOK-RUNTIME-001" "validate_task_graph_compliance.sh runs without state file"
    critical_pass
else
    fail_test "HOOK-RUNTIME-001" "validate_task_graph_compliance.sh runs without state file" "Hook failed without state file"
fi

# Test 2.4
critical_test
create_valid_state_file 0 2
output=$(run_pretooluse_hook "test prompt without marker" 2>&1 || true)
if [[ $? -ne 0 ]] && echo "$output" | grep -q "Missing Phase ID marker"; then
    pass_test "HOOK-RUNTIME-002" "validate_task_graph_compliance.sh detects missing Phase ID"
    critical_pass
else
    fail_test "HOOK-RUNTIME-002" "validate_task_graph_compliance.sh detects missing Phase ID" "Expected error not found"
fi

# ==========================================
# Category 3: Prompt Engineering Tests
# ==========================================
header "Category 3: Prompt Engineering Tests"

# Test 3.1
critical_test
if grep -q "⚠️ MANDATORY: Task Graph Execution Compliance" "${SYSTEM_PROMPTS_DIR}/WORKFLOW_ORCHESTRATOR.md"; then
    pass_test "PROMPT-MANDATORY-001" "WORKFLOW_ORCHESTRATOR.md has compliance section"
    critical_pass
else
    fail_test "PROMPT-MANDATORY-001" "WORKFLOW_ORCHESTRATOR.md has compliance section" "Section not found"
fi

# Test 3.2
critical_test
if grep -q "CRITICAL RULES - NO EXCEPTIONS" "${SYSTEM_PROMPTS_DIR}/WORKFLOW_ORCHESTRATOR.md"; then
    pass_test "PROMPT-MANDATORY-002" "WORKFLOW_ORCHESTRATOR.md has critical rules section"
    critical_pass
else
    fail_test "PROMPT-MANDATORY-002" "WORKFLOW_ORCHESTRATOR.md has critical rules section" "Section not found"
fi

# Test 3.3
critical_test
rule_count=0
grep -q "1\. PARSE JSON EXECUTION PLAN IMMEDIATELY" "${SYSTEM_PROMPTS_DIR}/WORKFLOW_ORCHESTRATOR.md" && ((rule_count++))
grep -q "2\. PROHIBITED ACTIONS" "${SYSTEM_PROMPTS_DIR}/WORKFLOW_ORCHESTRATOR.md" && ((rule_count++))
grep -q "3\. EXACT WAVE EXECUTION REQUIRED" "${SYSTEM_PROMPTS_DIR}/WORKFLOW_ORCHESTRATOR.md" && ((rule_count++))
grep -q "4\. PHASE ID MARKERS MANDATORY" "${SYSTEM_PROMPTS_DIR}/WORKFLOW_ORCHESTRATOR.md" && ((rule_count++))
grep -q "5\. ESCAPE HATCH" "${SYSTEM_PROMPTS_DIR}/WORKFLOW_ORCHESTRATOR.md" && ((rule_count++))

if [[ $rule_count -eq 5 ]]; then
    pass_test "PROMPT-MANDATORY-003" "WORKFLOW_ORCHESTRATOR.md has all 5 critical rules"
    critical_pass
else
    fail_test "PROMPT-MANDATORY-003" "WORKFLOW_ORCHESTRATOR.md has all 5 critical rules" "Only found $rule_count/5 rules"
fi

# Test 3.4
critical_test
if grep -q "MANDATORY: JSON Execution Plan Output" "${AGENTS_DIR}/delegation-orchestrator.md"; then
    pass_test "PROMPT-JSON-001" "delegation-orchestrator.md has JSON output section"
    critical_pass
else
    fail_test "PROMPT-JSON-001" "delegation-orchestrator.md has JSON output section" "Section not found"
fi

# Test 3.5
critical_test
if grep -q "BINDING CONTRACT" "${AGENTS_DIR}/delegation-orchestrator.md"; then
    pass_test "PROMPT-JSON-002" "delegation-orchestrator.md has binding contract language"
    critical_pass
else
    fail_test "PROMPT-JSON-002" "delegation-orchestrator.md has binding contract language" "Language not found"
fi

# Test 3.6
critical_test
field_count=0
grep -q "schema_version" "${AGENTS_DIR}/delegation-orchestrator.md" && ((field_count++))
grep -q "task_graph_id" "${AGENTS_DIR}/delegation-orchestrator.md" && ((field_count++))
grep -q "execution_mode" "${AGENTS_DIR}/delegation-orchestrator.md" && ((field_count++))
grep -q "total_waves" "${AGENTS_DIR}/delegation-orchestrator.md" && ((field_count++))
grep -q "phase_id" "${AGENTS_DIR}/delegation-orchestrator.md" && ((field_count++))

if [[ $field_count -eq 5 ]]; then
    pass_test "PROMPT-JSON-003" "delegation-orchestrator.md has JSON schema"
    critical_pass
else
    fail_test "PROMPT-JSON-003" "delegation-orchestrator.md has JSON schema" "Only found $field_count/5 fields"
fi

# Test 3.7
critical_test
if grep -q "Step 2.5: Initialize Task Graph State" "${COMMANDS_DIR}/delegate.md"; then
    pass_test "PROMPT-DELEGATE-001" "delegate.md has state initialization section"
    critical_pass
else
    fail_test "PROMPT-DELEGATE-001" "delegate.md has state initialization section" "Section not found"
fi

# Test 3.8
critical_test
if grep -q "Step 3: Execute According to Wave Structure" "${COMMANDS_DIR}/delegate.md"; then
    pass_test "PROMPT-DELEGATE-002" "delegate.md has wave execution protocol"
    critical_pass
else
    fail_test "PROMPT-DELEGATE-002" "delegate.md has wave execution protocol" "Section not found"
fi

# Test 3.9
critical_test
if grep -q "Phase Invocation Format (MANDATORY)" "${COMMANDS_DIR}/delegate.md"; then
    pass_test "PROMPT-DELEGATE-003" "delegate.md has phase ID format requirement"
    critical_pass
else
    fail_test "PROMPT-DELEGATE-003" "delegate.md has phase ID format requirement" "Requirement not found"
fi

# ==========================================
# Category 4: JSON Schema Validation Tests
# ==========================================
header "Category 4: JSON Schema Validation Tests"

# Test 4.1
create_valid_state_file 0 2
if jq empty "$TEST_STATE_FILE" 2>/dev/null && \
   jq -e 'has("schema_version") and has("task_graph_id") and has("status") and has("current_wave") and has("total_waves") and has("execution_plan") and has("phase_status") and has("wave_status") and has("compliance_log")' "$TEST_STATE_FILE" >/dev/null 2>&1; then
    pass_test "SCHEMA-VALID-001" "Create valid state file with all required fields"
else
    fail_test "SCHEMA-VALID-001" "Create valid state file with all required fields" "Missing required top-level fields"
fi

# Test 4.2
if jq -e '.execution_plan | has("schema_version") and has("task_graph_id") and has("execution_mode") and has("total_waves") and has("total_phases") and has("waves") and has("dependency_graph")' "$TEST_STATE_FILE" >/dev/null 2>&1; then
    pass_test "SCHEMA-VALID-002" "Execution plan has required structure"
else
    fail_test "SCHEMA-VALID-002" "Execution plan has required structure" "Missing required execution_plan fields"
fi

# Test 4.3
if jq -e '.execution_plan.waves[0] | has("wave_id") and has("parallel_execution") and has("phases")' "$TEST_STATE_FILE" >/dev/null 2>&1; then
    pass_test "SCHEMA-VALID-003" "Wave structure is valid"
else
    fail_test "SCHEMA-VALID-003" "Wave structure is valid" "Missing required wave fields"
fi

# Test 4.4
if jq -e '.execution_plan.waves[0].phases[0] | has("phase_id") and has("description") and has("agent") and has("dependencies")' "$TEST_STATE_FILE" >/dev/null 2>&1; then
    pass_test "SCHEMA-VALID-004" "Phase structure is valid"
else
    fail_test "SCHEMA-VALID-004" "Phase structure is valid" "Missing required phase fields"
fi

# Test 4.5
phase_id=$(jq -r '.execution_plan.waves[0].phases[0].phase_id' "$TEST_STATE_FILE")
if echo "$phase_id" | grep -qE '^phase_[0-9]+_[0-9]+$'; then
    pass_test "SCHEMA-VALID-005" "Phase ID format is correct (phase_X_Y)"
else
    fail_test "SCHEMA-VALID-005" "Phase ID format is correct (phase_X_Y)" "Invalid format: $phase_id"
fi

# ==========================================
# Category 5: Wave Order Enforcement Tests
# ==========================================
header "Category 5: Wave Order Enforcement Tests"

# Test 5.1
critical_test
create_valid_state_file 0 2
if run_pretooluse_hook "Phase ID: phase_0_0\nTest prompt for current wave" >/dev/null 2>&1; then
    pass_test "ENFORCE-WAVE-001" "Allow current wave execution (wave 0, phase_0_0)"
    critical_pass
else
    fail_test "ENFORCE-WAVE-001" "Allow current wave execution (wave 0, phase_0_0)" "Hook blocked valid phase"
fi

# Test 5.2
critical_test
create_valid_state_file 0 2
output=$(run_pretooluse_hook "Phase ID: phase_1_0\nTest prompt for future wave" 2>&1 || true)
if [[ $? -ne 0 ]] && echo "$output" | grep -q "Wave order violation"; then
    pass_test "ENFORCE-WAVE-002" "Block future wave execution (wave 0 → phase_1_0)"
    critical_pass
else
    fail_test "ENFORCE-WAVE-002" "Block future wave execution (wave 0 → phase_1_0)" "Hook did not block future wave"
fi

# Test 5.3
create_valid_state_file 1 2
output=$(run_pretooluse_hook "Phase ID: phase_0_0\nTest prompt for past wave" 2>&1 || true)
if [[ $? -eq 0 ]] && echo "$output" | grep -qi "warning\|remediation\|past wave"; then
    pass_test "ENFORCE-WAVE-003" "Allow past wave execution with warning (wave 1 → phase_0_0)"
else
    fail_test "ENFORCE-WAVE-003" "Allow past wave execution with warning (wave 1 → phase_0_0)" "Hook blocked or no warning"
fi

# Test 5.4
critical_test
create_valid_state_file 0 2
output=$(run_pretooluse_hook "Phase ID: phase_0_99\nTest prompt with invalid phase" 2>&1 || true)
if [[ $? -ne 0 ]] && echo "$output" | grep -q "Phase not found"; then
    pass_test "ENFORCE-PHASE-001" "Block invalid phase ID (phase_0_99)"
    critical_pass
else
    fail_test "ENFORCE-PHASE-001" "Block invalid phase ID (phase_0_99)" "Hook did not block invalid phase"
fi

# Test 5.5
critical_test
create_valid_state_file 0 2
output=$(run_pretooluse_hook "Test prompt without Phase ID marker" 2>&1 || true)
if [[ $? -ne 0 ]] && echo "$output" | grep -q "Missing Phase ID marker"; then
    pass_test "ENFORCE-PHASE-002" "Block missing Phase ID marker"
    critical_pass
else
    fail_test "ENFORCE-PHASE-002" "Block missing Phase ID marker" "Hook did not block missing marker"
fi

# ==========================================
# Category 6: Wave Auto-Progression Tests
# ==========================================
header "Category 6: Wave Auto-Progression Tests"

# Test 6.1
critical_test
create_valid_state_file 0 2
if run_posttooluse_hook "Phase ID: phase_0_0\nResult: success" 0 >/dev/null 2>&1; then
    # Check if phase was marked complete
    status=$(jq -r '.phase_status.phase_0_0.status' "$TEST_STATE_FILE" 2>/dev/null || echo "missing")
    if [[ "$status" == "completed" ]]; then
        pass_test "PROGRESS-PHASE-001" "Mark single phase complete (phase_0_0)"
        critical_pass
    else
        fail_test "PROGRESS-PHASE-001" "Mark single phase complete (phase_0_0)" "Phase status not updated: $status"
    fi
else
    fail_test "PROGRESS-PHASE-001" "Mark single phase complete (phase_0_0)" "Hook execution failed"
fi

# Test 6.2
critical_test
create_valid_state_file 0 2
# Mark first phase complete
run_posttooluse_hook "Phase ID: phase_0_0\nResult: success" 0 >/dev/null 2>&1
# Mark second phase complete (should advance wave)
if run_posttooluse_hook "Phase ID: phase_0_1\nResult: success" 0 >/dev/null 2>&1; then
    current_wave=$(jq -r '.current_wave' "$TEST_STATE_FILE" 2>/dev/null || echo "-1")
    wave0_status=$(jq -r '.wave_status["0"].status' "$TEST_STATE_FILE" 2>/dev/null || echo "missing")
    if [[ "$current_wave" == "1" ]] && [[ "$wave0_status" == "completed" ]]; then
        pass_test "PROGRESS-WAVE-001" "Advance wave when all phases complete (0 → 1)"
        critical_pass
    else
        fail_test "PROGRESS-WAVE-001" "Advance wave when all phases complete (0 → 1)" "Wave not advanced: current=$current_wave, status=$wave0_status"
    fi
else
    fail_test "PROGRESS-WAVE-001" "Advance wave when all phases complete (0 → 1)" "Hook execution failed"
fi

# Test 6.3
critical_test
# Create single-wave workflow
create_valid_state_file 0 1
# Update to single phase in wave 0
jq '.execution_plan.waves = [.execution_plan.waves[0]] | .execution_plan.waves[0].phases = [.execution_plan.waves[0].phases[0]] | .total_waves = 1 | .execution_plan.total_waves = 1 | .execution_plan.total_phases = 1' "$TEST_STATE_FILE" > "${TEST_STATE_FILE}.tmp" && mv "${TEST_STATE_FILE}.tmp" "$TEST_STATE_FILE"

if run_posttooluse_hook "Phase ID: phase_0_0\nResult: success" 0 >/dev/null 2>&1; then
    workflow_status=$(jq -r '.status' "$TEST_STATE_FILE" 2>/dev/null || echo "missing")
    if [[ "$workflow_status" == "completed" ]]; then
        pass_test "PROGRESS-WORKFLOW-001" "Mark workflow complete on final wave"
        critical_pass
    else
        fail_test "PROGRESS-WORKFLOW-001" "Mark workflow complete on final wave" "Workflow status not updated: $workflow_status"
    fi
else
    fail_test "PROGRESS-WORKFLOW-001" "Mark workflow complete on final wave" "Hook execution failed"
fi

# Test 6.4
create_valid_state_file 0 2
if run_posttooluse_hook "Phase ID: phase_0_0\nResult: success" 0 >/dev/null 2>&1; then
    log_count=$(jq '.compliance_log | length' "$TEST_STATE_FILE" 2>/dev/null || echo "0")
    if [[ "$log_count" -gt 0 ]]; then
        pass_test "PROGRESS-LOG-001" "Update compliance log on phase completion"
    else
        fail_test "PROGRESS-LOG-001" "Update compliance log on phase completion" "No compliance log entries found"
    fi
else
    fail_test "PROGRESS-LOG-001" "Update compliance log on phase completion" "Hook execution failed"
fi

# ==========================================
# Category 7: Edge Case Tests
# ==========================================
header "Category 7: Edge Case Tests"

# Test 7.1
cat > "$TEST_STATE_FILE" <<EOF
{
  "schema_version": "1.0",
  "task_graph_id": "tg_test_empty",
  "status": "in_progress",
  "current_wave": 0,
  "total_waves": 0,
  "execution_plan": {
    "schema_version": "1.0",
    "task_graph_id": "tg_test_empty",
    "execution_mode": "sequential",
    "total_waves": 0,
    "total_phases": 0,
    "waves": [],
    "dependency_graph": {}
  },
  "phase_status": {},
  "wave_status": {},
  "compliance_log": []
}
EOF

output=$(run_pretooluse_hook "Phase ID: phase_0_0\nTest empty plan" 2>&1 || true)
if [[ $? -ne 0 ]] && echo "$output" | grep -q "Phase not found"; then
    pass_test "EDGE-EMPTY-001" "Handle empty execution plan gracefully"
else
    fail_test "EDGE-EMPTY-001" "Handle empty execution plan gracefully" "Hook did not reject correctly"
fi

# Test 7.2
create_valid_state_file 0 2
output=$(run_pretooluse_hook "Phase ID: invalid-format-no-underscores\nTest malformed ID" 2>&1 || true)
if [[ $? -ne 0 ]]; then
    pass_test "EDGE-MALFORMED-001" "Handle malformed phase ID format"
else
    fail_test "EDGE-MALFORMED-001" "Handle malformed phase ID format" "Hook did not reject malformed ID"
fi

# Test 7.3
# Create state with 3 parallel phases
cat > "$TEST_STATE_FILE" <<EOF
{
  "schema_version": "1.0",
  "task_graph_id": "tg_test_parallel",
  "status": "in_progress",
  "current_wave": 0,
  "total_waves": 1,
  "execution_plan": {
    "schema_version": "1.0",
    "task_graph_id": "tg_test_parallel",
    "execution_mode": "parallel",
    "total_waves": 1,
    "total_phases": 3,
    "waves": [
      {
        "wave_id": 0,
        "parallel_execution": true,
        "phases": [
          {"phase_id": "phase_0_0", "description": "P1", "agent": "test", "dependencies": []},
          {"phase_id": "phase_0_1", "description": "P2", "agent": "test", "dependencies": []},
          {"phase_id": "phase_0_2", "description": "P3", "agent": "test", "dependencies": []}
        ]
      }
    ],
    "dependency_graph": {"phase_0_0": [], "phase_0_1": [], "phase_0_2": []}
  },
  "phase_status": {},
  "wave_status": {"0": {"status": "in_progress", "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"}},
  "compliance_log": []
}
EOF

# Complete phases 1 and 2
run_posttooluse_hook "Phase ID: phase_0_0\nResult: success" 0 >/dev/null 2>&1
run_posttooluse_hook "Phase ID: phase_0_1\nResult: success" 0 >/dev/null 2>&1

# Wave should NOT advance yet
current_wave=$(jq -r '.current_wave' "$TEST_STATE_FILE")
if [[ "$current_wave" == "0" ]]; then
    # Complete third phase
    run_posttooluse_hook "Phase ID: phase_0_2\nResult: success" 0 >/dev/null 2>&1
    current_wave=$(jq -r '.current_wave' "$TEST_STATE_FILE")
    if [[ "$current_wave" == "1" ]]; then
        pass_test "EDGE-CONCURRENT-001" "Handle concurrent phase completion correctly"
    else
        fail_test "EDGE-CONCURRENT-001" "Handle concurrent phase completion correctly" "Wave advanced incorrectly"
    fi
else
    fail_test "EDGE-CONCURRENT-001" "Handle concurrent phase completion correctly" "Wave advanced too early"
fi

# Test 7.4
echo "invalid json {{{" > "$TEST_STATE_FILE"
output=$(run_pretooluse_hook "Phase ID: phase_0_0\nTest corrupt JSON" 2>&1 || true)
if [[ $? -ne 0 ]]; then
    pass_test "EDGE-CORRUPT-001" "Handle corrupted state file gracefully"
else
    fail_test "EDGE-CORRUPT-001" "Handle corrupted state file gracefully" "Hook did not handle corruption"
fi

# Test 7.5
cat > "$TEST_STATE_FILE" <<EOF
{
  "schema_version": "1.0",
  "task_graph_id": "tg_test_missing",
  "status": "in_progress"
}
EOF

output=$(run_pretooluse_hook "Phase ID: phase_0_0\nTest missing fields" 2>&1 || true)
if [[ $? -ne 0 ]]; then
    pass_test "EDGE-MISSING-001" "Handle missing required fields gracefully"
else
    fail_test "EDGE-MISSING-001" "Handle missing required fields gracefully" "Hook did not validate required fields"
fi

# ==========================================
# Summary
# ==========================================
echo ""
header "Test Summary"

echo ""
echo "Total Tests:    $TOTAL_TESTS"
echo -e "Passed:         ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed:         ${RED}$FAILED_TESTS${NC}"
echo ""
echo "Critical Tests: $CRITICAL_TESTS"
echo -e "Critical Pass:  ${GREEN}$CRITICAL_PASSED${NC}"
echo -e "Critical Fail:  ${RED}$((CRITICAL_TESTS - CRITICAL_PASSED))${NC}"
echo ""

# Overall result
if [[ $FAILED_TESTS -eq 0 ]]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}OVERALL RESULT: PASS${NC}"
    echo -e "${GREEN}========================================${NC}"
    exit 0
elif [[ $CRITICAL_PASSED -eq $CRITICAL_TESTS ]]; then
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}OVERALL RESULT: PASS WITH WARNINGS${NC}"
    echo -e "${YELLOW}All critical tests passed${NC}"
    echo -e "${YELLOW}========================================${NC}"
    exit 0
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}OVERALL RESULT: FAIL${NC}"
    echo -e "${RED}Critical tests failed: $((CRITICAL_TESTS - CRITICAL_PASSED))/$CRITICAL_TESTS${NC}"
    echo -e "${RED}========================================${NC}"
    exit 1
fi
