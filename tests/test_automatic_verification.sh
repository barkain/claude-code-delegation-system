#!/bin/bash
#
# Comprehensive Test Suite for Automatic Deliverable Verification Mechanism
# Tests all components of the verification system including:
# - Deliverable manifest generation sections
# - Manifest-driven verification protocol
# - Verification phase handling
# - Verdict processing logic
# - Documentation completeness
#
# Usage: ./tests/test_automatic_verification.sh
# Exit Codes: 0 = All tests passed, 1 = One or more tests failed

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test result counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_RUN=0

# Project root directory
PROJECT_ROOT="/Users/nadavbarkai/dev/claude-code-delegation-system"

# Test output file
TEST_OUTPUT="${PROJECT_ROOT}/tests/output/automatic_verification_test_results.txt"
mkdir -p "${PROJECT_ROOT}/tests/output"

# Log functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >> "$TEST_OUTPUT"
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1" >> "$TEST_OUTPUT"
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
    ((TESTS_RUN++))
}

log_failure() {
    echo -e "${RED}[FAIL]${NC} $1" >> "$TEST_OUTPUT"
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
    ((TESTS_RUN++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1" >> "$TEST_OUTPUT"
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_section() {
    echo "" >> "$TEST_OUTPUT"
    echo -e "${BLUE}================================================${NC}" >> "$TEST_OUTPUT"
    echo -e "${BLUE}$1${NC}" >> "$TEST_OUTPUT"
    echo -e "${BLUE}================================================${NC}" >> "$TEST_OUTPUT"
    echo ""
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

# Initialize test output file
echo "Automatic Verification Test Results" > "$TEST_OUTPUT"
echo "Test Run: $(date)" >> "$TEST_OUTPUT"
echo "Project: ${PROJECT_ROOT}" >> "$TEST_OUTPUT"
echo "" >> "$TEST_OUTPUT"

log_section "TEST SUITE: Automatic Deliverable Verification"

# ============================================================================
# Test Group 1: Infrastructure Tests
# ============================================================================

log_section "Test Group 1: Infrastructure Tests"

# Test 1.1: Deliverables directory exists
log_info "Test 1.1: Verify deliverables state directory exists"
if [ -d "${PROJECT_ROOT}/.claude/state/deliverables" ]; then
    log_success "Deliverables directory exists at ${PROJECT_ROOT}/.claude/state/deliverables"
else
    log_failure "Deliverables directory NOT found at ${PROJECT_ROOT}/.claude/state/deliverables"
fi

# Test 1.2: .gitkeep file exists
log_info "Test 1.2: Verify .gitkeep file in deliverables directory"
if [ -f "${PROJECT_ROOT}/.claude/state/deliverables/.gitkeep" ]; then
    log_success ".gitkeep file exists in deliverables directory"
else
    log_failure ".gitkeep file NOT found in deliverables directory"
fi

# ============================================================================
# Test Group 2: delegation-orchestrator.md Tests
# ============================================================================

log_section "Test Group 2: delegation-orchestrator.md Configuration Tests"

ORCHESTRATOR_FILE="${PROJECT_ROOT}/agents/delegation-orchestrator.md"

# Test 2.1: File exists
log_info "Test 2.1: Verify delegation-orchestrator.md exists"
if [ -f "$ORCHESTRATOR_FILE" ]; then
    log_success "delegation-orchestrator.md file exists"
else
    log_failure "delegation-orchestrator.md file NOT found at $ORCHESTRATOR_FILE"
fi

# Test 2.2: DELIVERABLE MANIFEST GENERATION section exists
log_info "Test 2.2: Verify DELIVERABLE MANIFEST GENERATION section exists"
if grep -q "## DELIVERABLE MANIFEST GENERATION" "$ORCHESTRATOR_FILE"; then
    log_success "DELIVERABLE MANIFEST GENERATION section found"
else
    log_failure "DELIVERABLE MANIFEST GENERATION section NOT found"
fi

# Test 2.3: Manifest generation protocol documented
log_info "Test 2.3: Verify manifest generation protocol documented"
if grep -q "Manifest Generation Protocol" "$ORCHESTRATOR_FILE"; then
    log_success "Manifest generation protocol documented"
else
    log_failure "Manifest generation protocol NOT documented"
fi

# Test 2.4: Manifest output format specified
log_info "Test 2.4: Verify manifest output format specified"
if grep -q "deliverable_manifest" "$ORCHESTRATOR_FILE"; then
    log_success "Manifest output format specified"
else
    log_failure "Manifest output format NOT specified"
fi

# Test 2.5: AUTO-INSERT VERIFICATION PHASES section exists
log_info "Test 2.5: Verify AUTO-INSERT VERIFICATION PHASES section exists"
if grep -q "## AUTO-INSERT VERIFICATION PHASES" "$ORCHESTRATOR_FILE"; then
    log_success "AUTO-INSERT VERIFICATION PHASES section found"
else
    log_failure "AUTO-INSERT VERIFICATION PHASES section NOT found"
fi

# Test 2.6: Verification phase insertion protocol documented
log_info "Test 2.6: Verify verification phase insertion protocol documented"
if grep -q "Verification Phase Insertion Protocol" "$ORCHESTRATOR_FILE"; then
    log_success "Verification phase insertion protocol documented"
else
    log_failure "Verification phase insertion protocol NOT documented"
fi

# Test 2.7: Verification phase template includes manifest
log_info "Test 2.7: Verify verification phase template includes manifest"
if grep -q "task-completion-verifier" "$ORCHESTRATOR_FILE"; then
    log_success "Verification phase template references task-completion-verifier"
else
    log_failure "Verification phase template does NOT reference task-completion-verifier"
fi

# Test 2.8: MANIFEST STORAGE section exists
log_info "Test 2.8: Verify MANIFEST STORAGE section exists"
if grep -q "## MANIFEST STORAGE" "$ORCHESTRATOR_FILE"; then
    log_success "MANIFEST STORAGE section found"
else
    log_failure "MANIFEST STORAGE section NOT found"
fi

# Test 2.9: Key deliverable types documented (files, tests, APIs)
log_info "Test 2.9: Verify key deliverable types documented"
FILES_FOUND=false
TESTS_FOUND=false
APIS_FOUND=false

if grep -q '"files":' "$ORCHESTRATOR_FILE"; then
    FILES_FOUND=true
fi
if grep -q '"tests":' "$ORCHESTRATOR_FILE"; then
    TESTS_FOUND=true
fi
if grep -q '"apis":' "$ORCHESTRATOR_FILE"; then
    APIS_FOUND=true
fi

if [ "$FILES_FOUND" = true ] && [ "$TESTS_FOUND" = true ] && [ "$APIS_FOUND" = true ]; then
    log_success "All deliverable types (files, tests, APIs) documented"
else
    log_failure "Missing deliverable types: files=$FILES_FOUND, tests=$TESTS_FOUND, APIs=$APIS_FOUND"
fi

# Test 2.10: Acceptance criteria field documented
log_info "Test 2.10: Verify acceptance criteria field documented"
if grep -q "acceptance_criteria" "$ORCHESTRATOR_FILE"; then
    log_success "Acceptance criteria field documented"
else
    log_failure "Acceptance criteria field NOT documented"
fi

# ============================================================================
# Test Group 3: task-completion-verifier.md Tests
# ============================================================================

log_section "Test Group 3: task-completion-verifier.md Configuration Tests"

VERIFIER_FILE="${PROJECT_ROOT}/agents/task-completion-verifier.md"

# Test 3.1: File exists
log_info "Test 3.1: Verify task-completion-verifier.md exists"
if [ -f "$VERIFIER_FILE" ]; then
    log_success "task-completion-verifier.md file exists"
else
    log_failure "task-completion-verifier.md file NOT found at $VERIFIER_FILE"
fi

# Test 3.2: MANIFEST-DRIVEN VERIFICATION PROTOCOL section exists
log_info "Test 3.2: Verify MANIFEST-DRIVEN VERIFICATION PROTOCOL section exists"
if grep -q "## MANIFEST-DRIVEN VERIFICATION PROTOCOL" "$VERIFIER_FILE"; then
    log_success "MANIFEST-DRIVEN VERIFICATION PROTOCOL section found"
else
    log_failure "MANIFEST-DRIVEN VERIFICATION PROTOCOL section NOT found"
fi

# Test 3.3: Load deliverable manifest step documented
log_info "Test 3.3: Verify load deliverable manifest step documented"
if grep -q "### 1. Load Deliverable Manifest" "$VERIFIER_FILE"; then
    log_success "Load deliverable manifest step documented"
else
    log_failure "Load deliverable manifest step NOT documented"
fi

# Test 3.4: Validate manifest structure step documented
log_info "Test 3.4: Verify validate manifest structure step documented"
if grep -q "### 2. Validate Manifest Structure" "$VERIFIER_FILE"; then
    log_success "Validate manifest structure step documented"
else
    log_failure "Validate manifest structure step NOT documented"
fi

# Test 3.5: File validation step documented
log_info "Test 3.5: Verify file validation step documented"
if grep -q "### 3. File Validation" "$VERIFIER_FILE"; then
    log_success "File validation step documented"
else
    log_failure "File validation step NOT documented"
fi

# Test 3.6: Test validation step documented
log_info "Test 3.6: Verify test validation step documented"
if grep -q "### 4. Test Validation" "$VERIFIER_FILE"; then
    log_success "Test validation step documented"
else
    log_failure "Test validation step NOT documented"
fi

# Test 3.7: API validation step documented
log_info "Test 3.7: Verify API validation step documented"
if grep -q "### 5. API Validation" "$VERIFIER_FILE"; then
    log_success "API validation step documented"
else
    log_failure "API validation step NOT documented"
fi

# Test 3.8: Acceptance criteria validation step documented
log_info "Test 3.8: Verify acceptance criteria validation step documented"
if grep -q "### 6. Acceptance Criteria Validation" "$VERIFIER_FILE"; then
    log_success "Acceptance criteria validation step documented"
else
    log_failure "Acceptance criteria validation step NOT documented"
fi

# Test 3.9: Verification report format documented
log_info "Test 3.9: Verify verification report format documented"
if grep -q "verification report" "$VERIFIER_FILE" || grep -q "VERIFICATION REPORT" "$VERIFIER_FILE"; then
    log_success "Verification report format documented"
else
    log_failure "Verification report format NOT documented"
fi

# Test 3.10: Verdict types documented (PASS/FAIL/PASS_WITH_MINOR_ISSUES)
log_info "Test 3.10: Verify verdict types documented"
PASS_FOUND=false
FAIL_FOUND=false
MINOR_FOUND=false

if grep -q "PASS" "$VERIFIER_FILE"; then
    PASS_FOUND=true
fi
if grep -q "FAIL" "$VERIFIER_FILE"; then
    FAIL_FOUND=true
fi
if grep -q "PASS_WITH_MINOR_ISSUES" "$VERIFIER_FILE"; then
    MINOR_FOUND=true
fi

if [ "$PASS_FOUND" = true ] && [ "$FAIL_FOUND" = true ] && [ "$MINOR_FOUND" = true ]; then
    log_success "All verdict types (PASS, FAIL, PASS_WITH_MINOR_ISSUES) documented"
else
    log_failure "Missing verdict types: PASS=$PASS_FOUND, FAIL=$FAIL_FOUND, MINOR=$MINOR_FOUND"
fi

# Test 3.11: Remediation guidance documented
log_info "Test 3.11: Verify remediation guidance documented"
if grep -q "remediation" "$VERIFIER_FILE" || grep -q "Remediation" "$VERIFIER_FILE"; then
    log_success "Remediation guidance documented"
else
    log_failure "Remediation guidance NOT documented"
fi

# ============================================================================
# Test Group 4: WORKFLOW_ORCHESTRATOR.md Tests
# ============================================================================

log_section "Test Group 4: WORKFLOW_ORCHESTRATOR.md Configuration Tests"

WORKFLOW_FILE="${PROJECT_ROOT}/system-prompts/WORKFLOW_ORCHESTRATOR.md"

# Test 4.1: File exists
log_info "Test 4.1: Verify WORKFLOW_ORCHESTRATOR.md exists"
if [ -f "$WORKFLOW_FILE" ]; then
    log_success "WORKFLOW_ORCHESTRATOR.md file exists"
else
    log_failure "WORKFLOW_ORCHESTRATOR.md file NOT found at $WORKFLOW_FILE"
fi

# Test 4.2: VERIFICATION PHASE HANDLING section exists
log_info "Test 4.2: Verify VERIFICATION PHASE HANDLING section exists"
if grep -q "## VERIFICATION PHASE HANDLING" "$WORKFLOW_FILE"; then
    log_success "VERIFICATION PHASE HANDLING section found"
else
    log_failure "VERIFICATION PHASE HANDLING section NOT found"
fi

# Test 4.3: Recognize verification phases step documented
log_info "Test 4.3: Verify recognize verification phases step documented"
if grep -q "### 1. Recognize Verification Phases" "$WORKFLOW_FILE"; then
    log_success "Recognize verification phases step documented"
else
    log_failure "Recognize verification phases step NOT documented"
fi

# Test 4.4: Prepare verification context step documented
log_info "Test 4.4: Verify prepare verification context step documented"
if grep -q "### 2. Prepare Verification Context" "$WORKFLOW_FILE"; then
    log_success "Prepare verification context step documented"
else
    log_failure "Prepare verification context step NOT documented"
fi

# Test 4.5: Execute verification phase step documented
log_info "Test 4.5: Verify execute verification phase step documented"
if grep -q "### 3. Execute Verification Phase" "$WORKFLOW_FILE"; then
    log_success "Execute verification phase step documented"
else
    log_failure "Execute verification phase step NOT documented"
fi

# Test 4.6: Process verification results step documented
log_info "Test 4.6: Verify process verification results step documented"
if grep -q "### 4. Process Verification Results" "$WORKFLOW_FILE"; then
    log_success "Process verification results step documented"
else
    log_failure "Process verification results step NOT documented"
fi

# Test 4.7: PASS verdict handling documented
log_info "Test 4.7: Verify PASS verdict handling documented"
if grep -q "Handle PASS Verdict" "$WORKFLOW_FILE"; then
    log_success "PASS verdict handling documented"
else
    log_failure "PASS verdict handling NOT documented"
fi

# Test 4.8: FAIL verdict handling documented
log_info "Test 4.8: Verify FAIL verdict handling documented"
if grep -q "Handle FAIL Verdict" "$WORKFLOW_FILE"; then
    log_success "FAIL verdict handling documented"
else
    log_failure "FAIL verdict handling NOT documented"
fi

# Test 4.9: PASS_WITH_MINOR_ISSUES verdict handling documented
log_info "Test 4.9: Verify PASS_WITH_MINOR_ISSUES verdict handling documented"
if grep -q "Handle PASS_WITH_MINOR_ISSUES Verdict" "$WORKFLOW_FILE"; then
    log_success "PASS_WITH_MINOR_ISSUES verdict handling documented"
else
    log_failure "PASS_WITH_MINOR_ISSUES verdict handling NOT documented"
fi

# Test 4.10: Verification retry logic documented
log_info "Test 4.10: Verify verification retry logic documented"
if grep -q "### 5. Verification Retry Logic" "$WORKFLOW_FILE"; then
    log_success "Verification retry logic documented"
else
    log_failure "Verification retry logic NOT documented"
fi

# Test 4.11: TodoWrite updates for verification phases documented
log_info "Test 4.11: Verify TodoWrite updates for verification phases documented"
if grep -q "### 6. TodoWrite Updates for Verification Phases" "$WORKFLOW_FILE"; then
    log_success "TodoWrite updates for verification phases documented"
else
    log_failure "TodoWrite updates for verification phases NOT documented"
fi

# Test 4.12: Remediation re-delegation documented
log_info "Test 4.12: Verify remediation re-delegation documented"
if grep -q "Re-delegate implementation phase" "$WORKFLOW_FILE" || grep -q "re-delegate" "$WORKFLOW_FILE"; then
    log_success "Remediation re-delegation documented"
else
    log_failure "Remediation re-delegation NOT documented"
fi

# ============================================================================
# Test Group 5: CLAUDE.md Documentation Tests
# ============================================================================

log_section "Test Group 5: CLAUDE.md User Documentation Tests"

CLAUDE_MD_FILE="${PROJECT_ROOT}/CLAUDE.md"

# Test 5.1: File exists
log_info "Test 5.1: Verify CLAUDE.md exists"
if [ -f "$CLAUDE_MD_FILE" ]; then
    log_success "CLAUDE.md file exists"
else
    log_failure "CLAUDE.md file NOT found at $CLAUDE_MD_FILE"
fi

# Test 5.2: Automatic Deliverable Verification section exists
log_info "Test 5.2: Verify Automatic Deliverable Verification section exists"
if grep -q "## Automatic Deliverable Verification" "$CLAUDE_MD_FILE"; then
    log_success "Automatic Deliverable Verification section found"
else
    log_failure "Automatic Deliverable Verification section NOT found"
fi

# Test 5.3: How It Works subsection documented
log_info "Test 5.3: Verify How It Works subsection documented"
if grep -q "### How It Works" "$CLAUDE_MD_FILE"; then
    log_success "How It Works subsection documented"
else
    log_failure "How It Works subsection NOT documented"
fi

# Test 5.4: Wave Structure subsection documented
log_info "Test 5.4: Verify Wave Structure subsection documented"
if grep -q "### Wave Structure" "$CLAUDE_MD_FILE"; then
    log_success "Wave Structure subsection documented"
else
    log_failure "Wave Structure subsection NOT documented"
fi

# Test 5.5: Deliverable Manifest Example provided
log_info "Test 5.5: Verify Deliverable Manifest Example provided"
if grep -q "### Deliverable Manifest Example" "$CLAUDE_MD_FILE"; then
    log_success "Deliverable Manifest Example provided"
else
    log_failure "Deliverable Manifest Example NOT provided"
fi

# Test 5.6: Four-step process explained
log_info "Test 5.6: Verify four-step process explained"
STEP_COUNT=$(grep -c "^\s*[0-9]\." "$CLAUDE_MD_FILE" | head -1 || echo "0")
if [ "$STEP_COUNT" -ge 4 ]; then
    log_success "Four-step process documented (found $STEP_COUNT numbered steps)"
else
    log_warning "Numbered steps count may be less than 4 (found $STEP_COUNT)"
fi

# Test 5.7: Verdict types explained for users
log_info "Test 5.7: Verify verdict types explained for users"
if grep -q "PASS:" "$CLAUDE_MD_FILE" && grep -q "FAIL:" "$CLAUDE_MD_FILE" && grep -q "PASS_WITH_MINOR_ISSUES:" "$CLAUDE_MD_FILE"; then
    log_success "All verdict types explained for users"
else
    log_failure "Not all verdict types explained in user documentation"
fi

# Test 5.8: Reference to WORKFLOW_ORCHESTRATOR.md
log_info "Test 5.8: Verify reference to WORKFLOW_ORCHESTRATOR.md"
if grep -q "WORKFLOW_ORCHESTRATOR" "$CLAUDE_MD_FILE"; then
    log_success "Reference to WORKFLOW_ORCHESTRATOR.md found"
else
    log_failure "Reference to WORKFLOW_ORCHESTRATOR.md NOT found"
fi

# ============================================================================
# Test Group 6: Integration Tests - Content Validation
# ============================================================================

log_section "Test Group 6: Integration Tests - Content Validation"

# Test 6.1: Orchestrator generates manifests with required fields
log_info "Test 6.1: Verify orchestrator manifest includes all required fields"
REQUIRED_FIELDS=("phase_id" "phase_objective" "deliverable_manifest" "files" "acceptance_criteria")
ALL_FIELDS_FOUND=true

for field in "${REQUIRED_FIELDS[@]}"; do
    if ! grep -q "\"$field\"" "$ORCHESTRATOR_FILE"; then
        log_warning "Required field '$field' not found in orchestrator examples"
        ALL_FIELDS_FOUND=false
    fi
done

if [ "$ALL_FIELDS_FOUND" = true ]; then
    log_success "All required manifest fields documented in orchestrator"
else
    log_failure "Some required manifest fields missing from orchestrator documentation"
fi

# Test 6.2: Verifier protocol matches orchestrator manifest format
log_info "Test 6.2: Verify verifier protocol matches orchestrator manifest format"
VERIFIER_CHECKS_FILES=false
VERIFIER_CHECKS_TESTS=false
VERIFIER_CHECKS_APIS=false
VERIFIER_CHECKS_CRITERIA=false

if grep -q "File Validation" "$VERIFIER_FILE"; then
    VERIFIER_CHECKS_FILES=true
fi
if grep -q "Test Validation" "$VERIFIER_FILE"; then
    VERIFIER_CHECKS_TESTS=true
fi
if grep -q "API Validation" "$VERIFIER_FILE"; then
    VERIFIER_CHECKS_APIS=true
fi
if grep -q "Acceptance Criteria Validation" "$VERIFIER_FILE"; then
    VERIFIER_CHECKS_CRITERIA=true
fi

if [ "$VERIFIER_CHECKS_FILES" = true ] && [ "$VERIFIER_CHECKS_TESTS" = true ] && \
   [ "$VERIFIER_CHECKS_APIS" = true ] && [ "$VERIFIER_CHECKS_CRITERIA" = true ]; then
    log_success "Verifier protocol covers all manifest deliverable types"
else
    log_failure "Verifier protocol missing coverage: files=$VERIFIER_CHECKS_FILES, tests=$VERIFIER_CHECKS_TESTS, APIs=$VERIFIER_CHECKS_APIS, criteria=$VERIFIER_CHECKS_CRITERIA"
fi

# Test 6.3: Workflow orchestrator references correct agent
log_info "Test 6.3: Verify workflow orchestrator references task-completion-verifier"
if grep -q "task-completion-verifier" "$WORKFLOW_FILE"; then
    log_success "Workflow orchestrator correctly references task-completion-verifier agent"
else
    log_failure "Workflow orchestrator does NOT reference task-completion-verifier agent"
fi

# Test 6.4: Wave scheduling documented for verification phases
log_info "Test 6.4: Verify wave scheduling for verification phases documented"
if grep -q "Wave" "$ORCHESTRATOR_FILE" && grep -q "wave N+1" "$ORCHESTRATOR_FILE"; then
    log_success "Wave scheduling for verification phases documented"
else
    log_failure "Wave scheduling for verification phases NOT properly documented"
fi

# Test 6.5: Tools mentioned in verification protocol (Read, Grep, Bash)
log_info "Test 6.5: Verify required tools mentioned in verification protocol"
TOOLS_FOUND=true

if ! grep -q "Read tool" "$VERIFIER_FILE"; then
    log_warning "Read tool not mentioned in verifier protocol"
    TOOLS_FOUND=false
fi
if ! grep -q "Grep" "$VERIFIER_FILE"; then
    log_warning "Grep tool not mentioned in verifier protocol"
    TOOLS_FOUND=false
fi
if ! grep -q "Bash" "$VERIFIER_FILE"; then
    log_warning "Bash tool not mentioned in verifier protocol"
    TOOLS_FOUND=false
fi

if [ "$TOOLS_FOUND" = true ]; then
    log_success "All required tools (Read, Grep, Bash) mentioned in verification protocol"
else
    log_failure "Some required tools missing from verification protocol documentation"
fi

# Test 6.6: Type hints validation for Python documented
log_info "Test 6.6: Verify type hints validation for Python documented"
if grep -q "type_hints_required" "$ORCHESTRATOR_FILE" && grep -q "Type Hints Validation" "$VERIFIER_FILE"; then
    log_success "Type hints validation documented in both orchestrator and verifier"
else
    log_failure "Type hints validation NOT consistently documented"
fi

# Test 6.7: Content patterns validation documented
log_info "Test 6.7: Verify content patterns validation documented"
if grep -q "content_patterns" "$ORCHESTRATOR_FILE" && grep -q "Content Pattern Validation" "$VERIFIER_FILE"; then
    log_success "Content patterns validation documented"
else
    log_failure "Content patterns validation NOT documented"
fi

# Test 6.8: Test execution and coverage documented
log_info "Test 6.8: Verify test execution and coverage documented"
if grep -q "test_command" "$ORCHESTRATOR_FILE" && grep -q "Coverage Analysis" "$VERIFIER_FILE"; then
    log_success "Test execution and coverage analysis documented"
else
    log_failure "Test execution and coverage analysis NOT fully documented"
fi

# Test 6.9: Maximum retry limit documented
log_info "Test 6.9: Verify maximum retry limit documented"
if grep -q "Maximum retries: 2" "$WORKFLOW_FILE" || grep -q "max 2 retries" "$WORKFLOW_FILE"; then
    log_success "Maximum retry limit (2) documented"
else
    log_failure "Maximum retry limit NOT documented or different from 2"
fi

# Test 6.10: User escalation on multiple failures documented
log_info "Test 6.10: Verify user escalation on multiple failures documented"
if grep -q "Escalate to user" "$WORKFLOW_FILE" || grep -q "manual intervention" "$WORKFLOW_FILE"; then
    log_success "User escalation on failures documented"
else
    log_failure "User escalation mechanism NOT documented"
fi

# ============================================================================
# Test Summary
# ============================================================================

log_section "Test Summary"

echo "" >> "$TEST_OUTPUT"
echo "Total Tests Run: $TESTS_RUN" >> "$TEST_OUTPUT"
echo -e "${GREEN}Tests Passed: $TESTS_PASSED${NC}" >> "$TEST_OUTPUT"
echo -e "${RED}Tests Failed: $TESTS_FAILED${NC}" >> "$TEST_OUTPUT"
echo "" >> "$TEST_OUTPUT"

echo ""
echo "Total Tests Run: $TESTS_RUN"
echo -e "${GREEN}Tests Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Tests Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}========================================${NC}" >> "$TEST_OUTPUT"
    echo -e "${GREEN}ALL TESTS PASSED ✓${NC}" >> "$TEST_OUTPUT"
    echo -e "${GREEN}========================================${NC}" >> "$TEST_OUTPUT"
    echo "" >> "$TEST_OUTPUT"

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}ALL TESTS PASSED ✓${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    log_info "Test results saved to: $TEST_OUTPUT"
    exit 0
else
    echo -e "${RED}========================================${NC}" >> "$TEST_OUTPUT"
    echo -e "${RED}TESTS FAILED: $TESTS_FAILED test(s)${NC}" >> "$TEST_OUTPUT"
    echo -e "${RED}========================================${NC}" >> "$TEST_OUTPUT"
    echo "" >> "$TEST_OUTPUT"

    echo -e "${RED}========================================${NC}"
    echo -e "${RED}TESTS FAILED: $TESTS_FAILED test(s)${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    log_info "Test results saved to: $TEST_OUTPUT"
    log_warning "Review failures above and check implementation"
    exit 1
fi
