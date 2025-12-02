# System Prompt Persistence - Test Plan

**Feature:** System Prompt Persistence Mechanism
**Implementation:** /tmp/prompt_persistence_implementation.md
**Test Date:** 2025-12-02
**Project:** claude-code-delegation-system

---

## Test Overview

This test plan verifies the system prompt persistence mechanism that automatically detects and re-injects the WORKFLOW_ORCHESTRATOR prompt after context compaction events.

**Core Components Tested:**
1. Signature markers in WORKFLOW_ORCHESTRATOR.md
2. PreToolUse hook script (ensure_workflow_orchestrator.sh)
3. Hook registration in settings.json
4. State flag directory structure
5. Hook script syntax and logic
6. Re-injection trigger conditions

---

## Test Categories

### Category 1: Static File Verification (No Execution)

Tests that verify files exist, have correct permissions, and contain expected content.

### Category 2: Syntax and Configuration Validation

Tests that verify script syntax is correct and configuration is properly structured.

### Category 3: Logic Verification (Mock Scenarios)

Tests that verify hook behavior with mocked inputs/states without requiring full Claude session.

### Category 4: Integration Testing (Manual)

Tests that require full Claude session and cannot be automated. Documented for manual execution.

---

## Test Scenarios

### Test 1: Signature Markers Presence
**Category:** Static File Verification
**Objective:** Verify WORKFLOW_ORCHESTRATOR.md contains both start and end signature markers

**Test Steps:**
1. Read WORKFLOW_ORCHESTRATOR.md
2. Search for start marker: `WORKFLOW_ORCHESTRATOR_PROMPT_START_MARKER_DO_NOT_REMOVE`
3. Search for start signature: `SIGNATURE: WO_v2_DELEGATION_FIRST_PROTOCOL_ACTIVE`
4. Search for end marker: `WORKFLOW_ORCHESTRATOR_PROMPT_END_MARKER_DO_NOT_REMOVE`
5. Search for end signature: `SIGNATURE: WO_v2_CONTEXT_PASSING_ENABLED`

**Expected Result:**
- All 4 signature elements found
- Start markers appear in first 10 lines
- End markers appear in last 10 lines

**Pass Criteria:**
- All 4 markers present
- Correct positioning (start markers before line 10, end markers after line 600)

**Status:** _[PENDING/PASS/FAIL]_

---

### Test 2: Hook Script Existence and Permissions
**Category:** Static File Verification
**Objective:** Verify ensure_workflow_orchestrator.sh exists and is executable

**Test Steps:**
1. Check file exists at `.claude/hooks/PreToolUse/ensure_workflow_orchestrator.sh`
2. Verify file is executable (has execute permission)
3. Verify file is owned by current user
4. Check file size is reasonable (>1KB, <20KB)

**Expected Result:**
- File exists
- Permissions include execute bit (x)
- File size approximately 4-5KB

**Pass Criteria:**
- File exists with -rwx or -r-x permissions
- File size between 1KB and 20KB

**Status:** _[PENDING/PASS/FAIL]_

---

### Test 3: Hook Registration in settings.json
**Category:** Static File Verification
**Objective:** Verify ensure_workflow_orchestrator.sh is registered in settings.json

**Test Steps:**
1. Parse settings.json
2. Navigate to `hooks.PreToolUse` array
3. Find entry with matcher: "*"
4. Verify ensure_workflow_orchestrator.sh is listed
5. Verify timeout is set to 10 seconds
6. Verify description field exists

**Expected Result:**
- Hook is first in PreToolUse array (before require_delegation.sh)
- Timeout: 10 seconds
- Description: "Validate WORKFLOW_ORCHESTRATOR prompt presence and re-inject if missing"

**Pass Criteria:**
- Hook registered with correct command path
- Timeout >= 10 seconds
- Position before require_delegation.sh

**Status:** _[PENDING/PASS/FAIL]_

---

### Test 4: State Flag Directory Structure
**Category:** Static File Verification
**Objective:** Verify .claude/state directory can be created and is writable

**Test Steps:**
1. Check if `.claude/state/` directory exists
2. If not, create it with `mkdir -p`
3. Verify directory is writable
4. Test writing a flag file: `workflow_orchestrator_active.flag`
5. Verify flag file contains Unix timestamp format

**Expected Result:**
- Directory exists or can be created
- Directory is writable
- Test flag file can be written and read

**Pass Criteria:**
- `.claude/state/` directory accessible
- Write permissions confirmed

**Status:** _[PENDING/PASS/FAIL]_

---

### Test 5: Hook Script Syntax Validation
**Category:** Syntax and Configuration Validation
**Objective:** Verify ensure_workflow_orchestrator.sh has valid bash syntax

**Test Steps:**
1. Run `bash -n ensure_workflow_orchestrator.sh`
2. Check exit code (0 = valid syntax)
3. Capture any syntax error messages

**Expected Result:**
- Exit code: 0
- No syntax errors reported

**Pass Criteria:**
- `bash -n` returns exit code 0
- No error output

**Status:** _[PENDING/PASS/FAIL]_

---

### Test 6: Hook Script Shellcheck Validation
**Category:** Syntax and Configuration Validation
**Objective:** Verify hook script follows bash best practices (if shellcheck available)

**Test Steps:**
1. Check if shellcheck is installed
2. If available, run `shellcheck ensure_workflow_orchestrator.sh`
3. Categorize issues: errors vs warnings vs info

**Expected Result:**
- No critical errors
- Warnings acceptable if documented in implementation

**Pass Criteria:**
- No SC errors (shellcheck error level)
- SC warnings/info acceptable

**Status:** _[PENDING/PASS/FAIL/SKIPPED]_

---

### Test 7: Tool Criticality Check Logic
**Category:** Logic Verification (Mock)
**Objective:** Verify hook correctly identifies critical vs non-critical tools

**Test Steps:**
1. Read hook script to extract tool criticality logic
2. Verify critical tools list includes:
   - TodoWrite
   - Task
   - SubagentTask
   - AgentTask
   - SlashCommand
3. Test with non-critical tool name (e.g., "Read")
4. Test with critical tool name (e.g., "TodoWrite")

**Mock Test:**
```bash
# Simulate environment
export TOOL_NAME="Read"
# Run hook (should exit 0 immediately)

export TOOL_NAME="TodoWrite"
# Run hook (should proceed to validation)
```

**Expected Result:**
- Non-critical tools: immediate exit (exit 0)
- Critical tools: proceed to state flag check

**Pass Criteria:**
- Hook logic correctly filters tool names
- Critical tools proceed to validation path

**Status:** _[PENDING/PASS/FAIL]_

---

### Test 8: State Flag Age Calculation
**Category:** Logic Verification (Mock)
**Objective:** Verify state flag TTL logic (5-minute threshold)

**Test Steps:**
1. Create test state flag with known timestamp
2. Test Case A: Recent flag (30 seconds old) → Should skip Haiku query
3. Test Case B: Expired flag (10 minutes old) → Should trigger verification
4. Verify age calculation uses Unix timestamps correctly

**Mock Test:**
```bash
# Create recent flag (30 seconds ago)
echo "$(($(date +%s) - 30))" > test_flag.flag

# Create expired flag (10 minutes ago)
echo "$(($(date +%s) - 600))" > test_flag.flag
```

**Expected Result:**
- Recent flag (< 300 seconds): Fast path
- Expired flag (>= 300 seconds): Verification path

**Pass Criteria:**
- Age calculation mathematically correct
- 300-second threshold applied correctly

**Status:** _[PENDING/PASS/FAIL]_

---

### Test 9: Prompt File Location Discovery
**Category:** Logic Verification (Mock)
**Objective:** Verify hook searches correct locations for WORKFLOW_ORCHESTRATOR.md

**Test Steps:**
1. Read hook script to extract file location logic
2. Verify primary location: `~/.claude/system-prompts/WORKFLOW_ORCHESTRATOR.md`
3. Verify fallback location: `<project>/system-prompts/WORKFLOW_ORCHESTRATOR.md`
4. Test with file in primary location
5. Test with file only in fallback location

**Expected Result:**
- Primary location checked first
- Fallback location used if primary missing
- Error if both missing

**Pass Criteria:**
- Correct location search order
- File found in either location

**Status:** _[PENDING/PASS/FAIL]_

---

### Test 10: Emergency Disable Flag
**Category:** Logic Verification (Mock)
**Objective:** Verify PROMPT_PERSISTENCE_DISABLE=1 bypasses all validation

**Test Steps:**
1. Set `export PROMPT_PERSISTENCE_DISABLE=1`
2. Run hook script with critical tool
3. Verify immediate exit (exit 0)
4. Verify no state flag check
5. Verify no Haiku query

**Expected Result:**
- Hook exits immediately with exit code 0
- No validation performed
- No debug logs written (if debug enabled)

**Pass Criteria:**
- Exit code 0 within <0.01 seconds
- No validation logic executed

**Status:** _[PENDING/PASS/FAIL]_

---

### Test 11: Debug Logging Output
**Category:** Logic Verification (Mock)
**Objective:** Verify DEBUG_PROMPT_PERSISTENCE=1 produces debug logs

**Test Steps:**
1. Set `export DEBUG_PROMPT_PERSISTENCE=1`
2. Run hook script with critical tool
3. Check `/tmp/prompt_persistence_debug.log` exists
4. Verify log contains:
   - Timestamp
   - Session ID
   - Tool name
   - Decision path (fast path / verification path)

**Expected Result:**
- Debug log file created
- Entries contain structured information
- Log format is parseable

**Pass Criteria:**
- Log file created at `/tmp/prompt_persistence_debug.log`
- Log entries include required fields

**Status:** _[PENDING/PASS/FAIL]_

---

### Test 12: Missing Prompt File Error Handling
**Category:** Logic Verification (Mock)
**Objective:** Verify graceful error when prompt file not found

**Test Steps:**
1. Temporarily rename/move WORKFLOW_ORCHESTRATOR.md
2. Run hook script with critical tool
3. Verify exit code 1 (failure)
4. Verify error message includes expected file locations
5. Restore prompt file

**Expected Result:**
- Exit code: 1
- Error message: "Cannot re-inject WORKFLOW_ORCHESTRATOR prompt - file not found"
- Lists expected locations in error message

**Pass Criteria:**
- Tool execution blocked (exit 1)
- Clear error message with troubleshooting info

**Status:** _[PENDING/PASS/FAIL]_

---

### Test 13: SessionStart Hook State Flag Creation
**Category:** Integration Testing (Manual)
**Objective:** Verify SessionStart hook creates state flag on session initialization

**Manual Test Steps:**
1. Delete existing state flag: `rm .claude/state/workflow_orchestrator_active.flag`
2. Start new Claude session
3. Verify state flag created
4. Verify flag contains Unix timestamp
5. Verify timestamp is recent (within last 60 seconds)

**Expected Result:**
- State flag file exists after session start
- Contains valid Unix timestamp
- Timestamp matches session start time

**Pass Criteria:**
- Flag file created automatically
- Timestamp format correct

**Manual Execution Required:** YES
**Status:** _[PENDING/PASS/FAIL]_

---

### Test 14: Haiku Query Signature Detection (End-to-End)
**Category:** Integration Testing (Manual)
**Objective:** Verify Haiku query correctly detects signature markers

**Manual Test Steps:**
1. Start Claude session with WORKFLOW_ORCHESTRATOR prompt
2. Enable debug logging: `export DEBUG_PROMPT_PERSISTENCE=1`
3. Delete state flag to force verification path
4. Trigger critical tool (e.g., TodoWrite)
5. Check debug log for Haiku query
6. Verify Haiku response: "PRESENT"

**Expected Result:**
- Haiku query executed
- Response: "PRESENT"
- Hook allows tool to proceed (exit 0)
- State flag updated

**Pass Criteria:**
- Haiku query successful
- Correct detection of prompt presence

**Manual Execution Required:** YES
**Status:** _[PENDING/PASS/FAIL]_

---

### Test 15: Prompt Re-injection on Missing Signature
**Category:** Integration Testing (Manual)
**Objective:** Verify prompt automatically re-injected when missing

**Manual Test Steps:**
1. Start Claude session
2. Enable debug logging
3. Simulate missing prompt (modify markers or force compaction)
4. Trigger critical tool
5. Verify full prompt output to conversation
6. Verify state flag updated
7. Confirm workflow capabilities restored

**Expected Result:**
- Haiku query returns "MISSING"
- Hook outputs full prompt content
- Prompt appears in conversation context
- State flag timestamp updated
- Tool proceeds after re-injection

**Pass Criteria:**
- Automatic re-injection without user intervention
- Workflow capabilities restored

**Manual Execution Required:** YES
**Status:** _[PENDING/PASS/FAIL]_

---

### Test 16: Long Workflow Context Compaction (End-to-End)
**Category:** Integration Testing (Manual)
**Objective:** Verify persistence mechanism works during natural context compaction

**Manual Test Steps:**
1. Create multi-step workflow (15+ phases)
2. Generate large context (multiple file reads, long outputs)
3. Monitor for natural context compaction event
4. Continue workflow after compaction
5. Verify prompt automatically re-injected
6. Confirm workflow completes successfully

**Expected Result:**
- Natural compaction occurs (context window pressure)
- Prompt absence detected before tool execution
- Automatic re-injection
- Workflow continues without errors

**Pass Criteria:**
- No user intervention required
- Workflow orchestration capabilities maintained throughout
- All phases complete successfully

**Manual Execution Required:** YES
**Estimated Duration:** 2-4 hours
**Status:** _[PENDING/PASS/FAIL]_

---

## Test Execution Summary

### Automated Tests (Can Run via Script)
- Test 1: Signature Markers Presence
- Test 2: Hook Script Existence and Permissions
- Test 3: Hook Registration in settings.json
- Test 4: State Flag Directory Structure
- Test 5: Hook Script Syntax Validation
- Test 6: Hook Script Shellcheck Validation
- Test 7: Tool Criticality Check Logic (partial)
- Test 8: State Flag Age Calculation (partial)
- Test 9: Prompt File Location Discovery
- Test 10: Emergency Disable Flag (partial)
- Test 11: Debug Logging Output (partial)
- Test 12: Missing Prompt File Error Handling

**Total Automated:** 12 tests

### Manual Tests (Require Full Claude Session)
- Test 13: SessionStart Hook State Flag Creation
- Test 14: Haiku Query Signature Detection
- Test 15: Prompt Re-injection on Missing Signature
- Test 16: Long Workflow Context Compaction

**Total Manual:** 4 tests

### Total Tests: 16

---

## Pass/Fail Criteria

### Overall Pass Criteria
- All automated tests pass
- Critical manual tests (13, 14, 15) pass
- Test 16 (long workflow) can be deferred but documented

### Blocking Failures
- Test 1 (signatures missing) → BLOCKING
- Test 2 (hook not executable) → BLOCKING
- Test 3 (hook not registered) → BLOCKING
- Test 5 (syntax errors) → BLOCKING
- Test 12 (error handling broken) → BLOCKING

### Non-Blocking Failures
- Test 6 (shellcheck warnings) → Non-blocking if documented
- Test 8 (age calculation edge cases) → Non-blocking if logic sound
- Test 16 (long workflow) → Non-blocking if Tests 14-15 pass

---

## Test Results

### Test Execution Date: _[YYYY-MM-DD]_
### Executed By: _[Agent/Human]_
### Environment:
- OS: macOS (Darwin)
- Project Path: /Users/nadavbarkai/dev/claude-code-delegation-system
- Claude Version: _[TBD]_

### Results Summary

| Test # | Test Name | Category | Status | Notes |
|--------|-----------|----------|--------|-------|
| 1 | Signature Markers Presence | Static | _[PENDING]_ | |
| 2 | Hook Script Existence | Static | _[PENDING]_ | |
| 3 | Hook Registration | Static | _[PENDING]_ | |
| 4 | State Flag Directory | Static | _[PENDING]_ | |
| 5 | Hook Script Syntax | Syntax | _[PENDING]_ | |
| 6 | Shellcheck Validation | Syntax | _[PENDING]_ | |
| 7 | Tool Criticality Logic | Logic | _[PENDING]_ | |
| 8 | State Flag Age Calculation | Logic | _[PENDING]_ | |
| 9 | Prompt File Location | Logic | _[PENDING]_ | |
| 10 | Emergency Disable Flag | Logic | _[PENDING]_ | |
| 11 | Debug Logging Output | Logic | _[PENDING]_ | |
| 12 | Missing Prompt Error | Logic | _[PENDING]_ | |
| 13 | SessionStart State Flag | Integration | _[MANUAL]_ | |
| 14 | Haiku Query Detection | Integration | _[MANUAL]_ | |
| 15 | Prompt Re-injection | Integration | _[MANUAL]_ | |
| 16 | Long Workflow Compaction | Integration | _[MANUAL]_ | |

**Total:** 0 Passed, 0 Failed, 12 Pending, 4 Manual

---

## Issues Found

### Critical Issues
_[None identified yet]_

### Non-Critical Issues
_[None identified yet]_

### Recommendations
_[To be populated after test execution]_

---

## Appendix A: Test Environment Setup

### Prerequisites
```bash
# Ensure project is in correct location
cd /Users/nadavbarkai/dev/claude-code-delegation-system

# Verify bash version
bash --version  # Should be 3.2+

# Optional: Install shellcheck for Test 6
brew install shellcheck  # macOS
```

### Environment Variables for Testing
```bash
# Enable debug logging
export DEBUG_PROMPT_PERSISTENCE=1

# Emergency disable (for testing)
export PROMPT_PERSISTENCE_DISABLE=1

# Project directory override (if needed)
export CLAUDE_PROJECT_DIR=/Users/nadavbarkai/dev/claude-code-delegation-system
```

---

## Appendix B: Test Script Usage

### Running All Automated Tests
```bash
cd /Users/nadavbarkai/dev/claude-code-delegation-system/tests
./test_prompt_persistence.sh
```

### Running Specific Test Category
```bash
./test_prompt_persistence.sh --category static
./test_prompt_persistence.sh --category syntax
./test_prompt_persistence.sh --category logic
```

### Running Single Test
```bash
./test_prompt_persistence.sh --test 1
./test_prompt_persistence.sh --test 5
```

### Verbose Output
```bash
./test_prompt_persistence.sh --verbose
```

---

**End of Test Plan**
