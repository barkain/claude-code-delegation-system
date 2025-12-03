#!/bin/bash
# test_utils.sh - Helper functions for integration tests

# Color codes for test output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test statistics
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Setup function - creates test directories
setup_test_env() {
    local test_dir="${1:-.claude/state/test_$$}"
    export TEST_STATE_DIR="$test_dir"
    export TEST_LOG_DIR="$test_dir/logs"

    mkdir -p "$TEST_STATE_DIR"
    mkdir -p "$TEST_LOG_DIR"

    echo "[SETUP] Test environment initialized: $TEST_STATE_DIR"
}

# Teardown function - cleans up test directories
teardown_test_env() {
    if [[ -n "$TEST_STATE_DIR" && "$TEST_STATE_DIR" =~ test_ ]]; then
        rm -rf "$TEST_STATE_DIR"
        echo "[TEARDOWN] Test environment cleaned up"
    fi
}

# Assert function - checks condition and reports result
assert() {
    local description="$1"
    local condition="$2"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if eval "$condition"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} PASS: $description"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} FAIL: $description"
        echo -e "${YELLOW}  Condition: $condition${NC}"
        return 1
    fi
}

# Assert equality
assert_equals() {
    local description="$1"
    local expected="$2"
    local actual="$3"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [[ "$expected" == "$actual" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} PASS: $description"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} FAIL: $description"
        echo -e "${YELLOW}  Expected: $expected${NC}"
        echo -e "${YELLOW}  Actual:   $actual${NC}"
        return 1
    fi
}

# Assert file exists
assert_file_exists() {
    local description="$1"
    local filepath="$2"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [[ -f "$filepath" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} PASS: $description"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} FAIL: $description"
        echo -e "${YELLOW}  File not found: $filepath${NC}"
        return 1
    fi
}

# Assert JSON valid
assert_json_valid() {
    local description="$1"
    local filepath="$2"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if python3 -m json.tool "$filepath" > /dev/null 2>&1; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} PASS: $description"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} FAIL: $description"
        echo -e "${YELLOW}  Invalid JSON in: $filepath${NC}"
        return 1
    fi
}

# Assert JSON contains key
assert_json_key() {
    local description="$1"
    local filepath="$2"
    local key="$3"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if python3 -c "import json; data=json.load(open('$filepath')); assert '$key' in data" 2>/dev/null; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} PASS: $description"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} FAIL: $description"
        echo -e "${YELLOW}  Key not found: $key in $filepath${NC}"
        return 1
    fi
}

# Assert JSON value equals
assert_json_value() {
    local description="$1"
    local filepath="$2"
    local key="$3"
    local expected="$4"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    local actual=$(python3 -c "import json; data=json.load(open('$filepath')); print(data.get('$key', ''))" 2>/dev/null)

    if [[ "$expected" == "$actual" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} PASS: $description"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} FAIL: $description"
        echo -e "${YELLOW}  Key: $key${NC}"
        echo -e "${YELLOW}  Expected: $expected${NC}"
        echo -e "${YELLOW}  Actual:   $actual${NC}"
        return 1
    fi
}

# Assert string contains substring
assert_contains() {
    local description="$1"
    local haystack="$2"
    local needle="$3"

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [[ "$haystack" == *"$needle"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} PASS: $description"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} FAIL: $description"
        echo -e "${YELLOW}  Expected to find: $needle${NC}"
        echo -e "${YELLOW}  In: $haystack${NC}"
        return 1
    fi
}

# Print test summary
print_test_summary() {
    echo ""
    echo "========================================="
    echo "TEST SUMMARY"
    echo "========================================="
    echo -e "Total:  ${BLUE}$TESTS_TOTAL${NC}"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo "========================================="

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}ALL TESTS PASSED${NC}"
        return 0
    else
        echo -e "${RED}SOME TESTS FAILED${NC}"
        return 1
    fi
}

# Create mock tool execution result
create_mock_tool_result() {
    local tool_name="$1"
    local status="$2"  # success or error
    local session_id="${3:-sess_test_$$}"
    local workflow_id="${4:-wf_test_$$}"

    cat <<EOF
{
  "tool_name": "$tool_name",
  "status": "$status",
  "session_id": "$session_id",
  "workflow_id": "$workflow_id",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "parameters": {}
}
EOF
}

# Wait for file to exist (with timeout)
wait_for_file() {
    local filepath="$1"
    local timeout="${2:-5}"
    local elapsed=0

    while [[ ! -f "$filepath" && $elapsed -lt $timeout ]]; do
        sleep 0.1
        elapsed=$((elapsed + 1))
    done

    [[ -f "$filepath" ]]
}

# Generate unique test ID
generate_test_id() {
    echo "test_$(date +%s)_$$_$RANDOM"
}
