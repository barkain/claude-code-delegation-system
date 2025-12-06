# Task Graph Enforcement Test Plan

**Project:** claude-code-delegation-system
**Test Suite:** Task Graph Enforcement Mechanism
**Version:** 1.0
**Date:** 2025-12-02

---

## Executive Summary

This test plan validates the three-layer task graph enforcement mechanism that prevents main agent simplification of delegation-orchestrator execution plans. The test suite covers:

1. **Hook Installation & Configuration Tests** - Verify hooks exist and are registered
2. **Hook Script Validation Tests** - Verify script syntax and executability
3. **Prompt Engineering Tests** - Verify MANDATORY sections in agent prompts
4. **JSON Schema Validation Tests** - Verify execution plan format compliance
5. **Wave Order Enforcement Tests** - Verify PreToolUse hook blocks violations
6. **Wave Auto-Progression Tests** - Verify PostToolUse hook advances waves
7. **Edge Case Tests** - Test missing markers, invalid phases, remediation

---

## Test Environment

**Base Directory:** `/Users/nadavbarkai/dev/claude-code-delegation-system`

**Key Paths:**
- Hooks: `/Users/nadavbarkai/dev/claude-code-delegation-system/hooks/`
- Agents: `/Users/nadavbarkai/dev/claude-code-delegation-system/agents/`
- System Prompts: `/Users/nadavbarkai/dev/claude-code-delegation-system/system-prompts/`
- Commands: `/Users/nadavbarkai/dev/claude-code-delegation-system/commands/`
- Settings: `/Users/nadavbarkai/dev/claude-code-delegation-system/settings.json`
- State Directory: `.claude/state/`

**Required Tools:**
- bash (4.0+)
- jq (JSON processor)
- grep
- Basic POSIX utilities (test, cat, chmod)

---

## Test Categories

### Category 1: Hook Installation Tests

**Purpose:** Verify hook scripts exist, are executable, and registered in settings.json

#### Test 1.1: validate_task_graph_compliance.sh Exists
- **Test ID:** HOOK-INSTALL-001
- **Description:** Verify PreToolUse hook file exists
- **Command:** `test -f hooks/PreToolUse/validate_task_graph_compliance.sh`
- **Expected Result:** Exit code 0 (file exists)
- **Pass Criteria:** File found at expected path

#### Test 1.2: validate_task_graph_compliance.sh Is Executable
- **Test ID:** HOOK-INSTALL-002
- **Description:** Verify PreToolUse hook has execute permissions
- **Command:** `test -x hooks/PreToolUse/validate_task_graph_compliance.sh`
- **Expected Result:** Exit code 0 (executable)
- **Pass Criteria:** File has execute bit set

#### Test 1.3: update_wave_state.sh Exists
- **Test ID:** HOOK-INSTALL-003
- **Description:** Verify PostToolUse hook file exists
- **Command:** `test -f hooks/PostToolUse/update_wave_state.sh`
- **Expected Result:** Exit code 0 (file exists)
- **Pass Criteria:** File found at expected path

#### Test 1.4: update_wave_state.sh Is Executable
- **Test ID:** HOOK-INSTALL-004
- **Description:** Verify PostToolUse hook has execute permissions
- **Command:** `test -x hooks/PostToolUse/update_wave_state.sh`
- **Expected Result:** Exit code 0 (executable)
- **Pass Criteria:** File has execute bit set

#### Test 1.5: PreToolUse Hook Registered in settings.json
- **Test ID:** HOOK-INSTALL-005
- **Description:** Verify validate_task_graph_compliance.sh is registered
- **Command:** `jq '.hooks.PreToolUse[] | select(.matcher == "Task") | .hooks[] | select(.command | contains("validate_task_graph_compliance.sh"))' settings.json`
- **Expected Result:** JSON object with hook configuration
- **Pass Criteria:** Hook found in settings.json under Task matcher

#### Test 1.6: PostToolUse Hook Registered in settings.json
- **Test ID:** HOOK-INSTALL-006
- **Description:** Verify update_wave_state.sh is registered
- **Command:** `jq '.hooks.PostToolUse[] | select(.matcher == "Task") | .hooks[] | select(.command | contains("update_wave_state.sh"))' settings.json`
- **Expected Result:** JSON object with hook configuration
- **Pass Criteria:** Hook found in settings.json under Task matcher

---

### Category 2: Hook Script Validation Tests

**Purpose:** Verify hook scripts have valid syntax and can run

#### Test 2.1: validate_task_graph_compliance.sh Syntax Check
- **Test ID:** HOOK-SYNTAX-001
- **Description:** Verify PreToolUse hook has valid bash syntax
- **Command:** `bash -n hooks/PreToolUse/validate_task_graph_compliance.sh`
- **Expected Result:** Exit code 0 (no syntax errors)
- **Pass Criteria:** Script passes bash syntax check

#### Test 2.2: update_wave_state.sh Syntax Check
- **Test ID:** HOOK-SYNTAX-002
- **Description:** Verify PostToolUse hook has valid bash syntax
- **Command:** `bash -n hooks/PostToolUse/update_wave_state.sh`
- **Expected Result:** Exit code 0 (no syntax errors)
- **Pass Criteria:** Script passes bash syntax check

#### Test 2.3: validate_task_graph_compliance.sh Runs Without State File
- **Test ID:** HOOK-RUNTIME-001
- **Description:** Verify PreToolUse hook exits gracefully when no state file exists
- **Setup:** Remove .claude/state/active_task_graph.json if exists
- **Command:** `hooks/PreToolUse/validate_task_graph_compliance.sh Task "test prompt"`
- **Expected Result:** Exit code 0 (enforcement disabled, allow execution)
- **Pass Criteria:** Script exits successfully without blocking

#### Test 2.4: validate_task_graph_compliance.sh Detects Missing Phase ID
- **Test ID:** HOOK-RUNTIME-002
- **Description:** Verify PreToolUse hook blocks Task without Phase ID marker
- **Setup:** Create minimal active_task_graph.json with one phase
- **Command:** `hooks/PreToolUse/validate_task_graph_compliance.sh Task "test prompt without marker"`
- **Expected Result:** Exit code 1, error message "Missing Phase ID marker"
- **Pass Criteria:** Script blocks execution with clear error

---

### Category 3: Prompt Engineering Tests

**Purpose:** Verify MANDATORY/CRITICAL sections exist in agent prompts

#### Test 3.1: WORKFLOW_ORCHESTRATOR.md Has Compliance Section
- **Test ID:** PROMPT-MANDATORY-001
- **Description:** Verify Task Graph Execution Compliance section exists
- **Command:** `grep -q "⚠️ MANDATORY: Task Graph Execution Compliance" system-prompts/WORKFLOW_ORCHESTRATOR.md`
- **Expected Result:** Exit code 0 (section found)
- **Pass Criteria:** MANDATORY section heading exists

#### Test 3.2: WORKFLOW_ORCHESTRATOR.md Has Critical Rules
- **Test ID:** PROMPT-MANDATORY-002
- **Description:** Verify CRITICAL RULES - NO EXCEPTIONS section exists
- **Command:** `grep -q "CRITICAL RULES - NO EXCEPTIONS" system-prompts/WORKFLOW_ORCHESTRATOR.md`
- **Expected Result:** Exit code 0 (section found)
- **Pass Criteria:** Critical rules section exists

#### Test 3.3: WORKFLOW_ORCHESTRATOR.md Has All 5 Rules
- **Test ID:** PROMPT-MANDATORY-003
- **Description:** Verify all 5 critical rules are documented
- **Commands:**
  - `grep -q "1\. PARSE JSON EXECUTION PLAN IMMEDIATELY" system-prompts/WORKFLOW_ORCHESTRATOR.md`
  - `grep -q "2\. PROHIBITED ACTIONS" system-prompts/WORKFLOW_ORCHESTRATOR.md`
  - `grep -q "3\. EXACT WAVE EXECUTION REQUIRED" system-prompts/WORKFLOW_ORCHESTRATOR.md`
  - `grep -q "4\. PHASE ID MARKERS MANDATORY" system-prompts/WORKFLOW_ORCHESTRATOR.md`
  - `grep -q "5\. ESCAPE HATCH" system-prompts/WORKFLOW_ORCHESTRATOR.md`
- **Expected Result:** Exit code 0 for all (all rules found)
- **Pass Criteria:** All 5 rules are documented

#### Test 3.4: delegation-orchestrator.md Has JSON Output Section
- **Test ID:** PROMPT-JSON-001
- **Description:** Verify MANDATORY: JSON Execution Plan Output section exists
- **Command:** `grep -q "MANDATORY: JSON Execution Plan Output" agents/delegation-orchestrator.md`
- **Expected Result:** Exit code 0 (section found)
- **Pass Criteria:** JSON output section exists

#### Test 3.5: delegation-orchestrator.md Has Binding Contract Language
- **Test ID:** PROMPT-JSON-002
- **Description:** Verify BINDING CONTRACT language exists
- **Command:** `grep -q "BINDING CONTRACT" agents/delegation-orchestrator.md`
- **Expected Result:** Exit code 0 (language found)
- **Pass Criteria:** Contract language emphasizes mandatory adherence

#### Test 3.6: delegation-orchestrator.md Has JSON Schema
- **Test ID:** PROMPT-JSON-003
- **Description:** Verify JSON schema with required fields is documented
- **Commands:**
  - `grep -q "schema_version" agents/delegation-orchestrator.md`
  - `grep -q "task_graph_id" agents/delegation-orchestrator.md`
  - `grep -q "execution_mode" agents/delegation-orchestrator.md`
  - `grep -q "total_waves" agents/delegation-orchestrator.md`
  - `grep -q "phase_id" agents/delegation-orchestrator.md`
- **Expected Result:** Exit code 0 for all (all fields found)
- **Pass Criteria:** Complete JSON schema is documented

#### Test 3.7: delegate.md Has State Initialization Section
- **Test ID:** PROMPT-DELEGATE-001
- **Description:** Verify Step 2.5: Initialize Task Graph State section exists
- **Command:** `grep -q "Step 2.5: Initialize Task Graph State" commands/delegate.md`
- **Expected Result:** Exit code 0 (section found)
- **Pass Criteria:** State initialization instructions exist

#### Test 3.8: delegate.md Has Wave Execution Protocol
- **Test ID:** PROMPT-DELEGATE-002
- **Description:** Verify Step 3: Execute According to Wave Structure section exists
- **Command:** `grep -q "Step 3: Execute According to Wave Structure" commands/delegate.md`
- **Expected Result:** Exit code 0 (section found)
- **Pass Criteria:** Wave execution protocol documented

#### Test 3.9: delegate.md Has Phase ID Format Requirement
- **Test ID:** PROMPT-DELEGATE-003
- **Description:** Verify Phase Invocation Format (MANDATORY) is specified
- **Command:** `grep -q "Phase Invocation Format (MANDATORY)" commands/delegate.md`
- **Expected Result:** Exit code 0 (section found)
- **Pass Criteria:** Phase ID format requirement documented

---

### Category 4: JSON Schema Validation Tests

**Purpose:** Verify state file schema compliance

#### Test 4.1: Create Valid State File
- **Test ID:** SCHEMA-VALID-001
- **Description:** Create minimal valid active_task_graph.json
- **Command:** Create JSON with required fields (schema_version, task_graph_id, status, current_wave, total_waves, execution_plan, phase_status, wave_status, compliance_log)
- **Expected Result:** jq validation passes
- **Pass Criteria:** File is valid JSON with all required top-level fields

#### Test 4.2: Validate Execution Plan Schema
- **Test ID:** SCHEMA-VALID-002
- **Description:** Verify execution_plan has required structure
- **Command:** `jq '.execution_plan | has("schema_version") and has("task_graph_id") and has("execution_mode") and has("total_waves") and has("total_phases") and has("waves") and has("dependency_graph")' state_file.json`
- **Expected Result:** true
- **Pass Criteria:** All required execution_plan fields present

#### Test 4.3: Validate Wave Structure
- **Test ID:** SCHEMA-VALID-003
- **Description:** Verify waves array has correct structure
- **Command:** `jq '.execution_plan.waves[0] | has("wave_id") and has("parallel_execution") and has("phases")' state_file.json`
- **Expected Result:** true
- **Pass Criteria:** Wave objects have required fields

#### Test 4.4: Validate Phase Structure
- **Test ID:** SCHEMA-VALID-004
- **Description:** Verify phases have correct structure
- **Command:** `jq '.execution_plan.waves[0].phases[0] | has("phase_id") and has("description") and has("agent") and has("dependencies")' state_file.json`
- **Expected Result:** true
- **Pass Criteria:** Phase objects have required fields

#### Test 4.5: Validate Phase ID Format
- **Test ID:** SCHEMA-VALID-005
- **Description:** Verify phase_id follows pattern phase_{wave_id}_{phase_index}
- **Command:** `jq -r '.execution_plan.waves[0].phases[0].phase_id' state_file.json | grep -qE '^phase_[0-9]+_[0-9]+$'`
- **Expected Result:** Exit code 0 (pattern matches)
- **Pass Criteria:** Phase IDs match expected format

---

### Category 5: Wave Order Enforcement Tests

**Purpose:** Verify PreToolUse hook blocks out-of-order execution

#### Test 5.1: Allow Current Wave Execution
- **Test ID:** ENFORCE-WAVE-001
- **Description:** Verify hook allows phase in current wave
- **Setup:** Create state file with current_wave=0, one phase in wave 0
- **Command:** `hooks/PreToolUse/validate_task_graph_compliance.sh Task "Phase ID: phase_0_0\nTest prompt"`
- **Expected Result:** Exit code 0 (allow execution)
- **Pass Criteria:** Hook allows execution without error

#### Test 5.2: Block Future Wave Execution
- **Test ID:** ENFORCE-WAVE-002
- **Description:** Verify hook blocks phase in future wave
- **Setup:** Create state file with current_wave=0, phase in wave 1
- **Command:** `hooks/PreToolUse/validate_task_graph_compliance.sh Task "Phase ID: phase_1_0\nTest prompt"`
- **Expected Result:** Exit code 1, error "Wave order violation detected"
- **Pass Criteria:** Hook blocks with clear error message

#### Test 5.3: Allow Past Wave Execution (Remediation)
- **Test ID:** ENFORCE-WAVE-003
- **Description:** Verify hook allows past wave execution with warning
- **Setup:** Create state file with current_wave=1, phase in wave 0
- **Command:** `hooks/PreToolUse/validate_task_graph_compliance.sh Task "Phase ID: phase_0_0\nTest prompt"`
- **Expected Result:** Exit code 0, warning message about past wave
- **Pass Criteria:** Hook allows execution but logs warning

#### Test 5.4: Block Invalid Phase ID
- **Test ID:** ENFORCE-PHASE-001
- **Description:** Verify hook blocks non-existent phase
- **Setup:** Create state file with phase_0_0
- **Command:** `hooks/PreToolUse/validate_task_graph_compliance.sh Task "Phase ID: phase_0_99\nTest prompt"`
- **Expected Result:** Exit code 1, error "Phase not found in execution plan"
- **Pass Criteria:** Hook blocks with clear error

#### Test 5.5: Block Missing Phase ID Marker
- **Test ID:** ENFORCE-PHASE-002
- **Description:** Verify hook blocks Task without Phase ID
- **Setup:** Create valid state file
- **Command:** `hooks/PreToolUse/validate_task_graph_compliance.sh Task "Test prompt without phase ID"`
- **Expected Result:** Exit code 1, error "Missing Phase ID marker"
- **Pass Criteria:** Hook blocks with clear error

---

### Category 6: Wave Auto-Progression Tests

**Purpose:** Verify PostToolUse hook advances waves when complete

#### Test 6.1: Mark Single Phase Complete
- **Test ID:** PROGRESS-PHASE-001
- **Description:** Verify hook marks phase as completed
- **Setup:** Create state file with one pending phase
- **Command:** `hooks/PostToolUse/update_wave_state.sh Task "Phase ID: phase_0_0\nResult: success" 0`
- **Expected Result:** Exit code 0, phase_status updated to "completed"
- **Pass Criteria:** State file shows phase_0_0 status = "completed"

#### Test 6.2: Advance Wave When All Phases Complete
- **Test ID:** PROGRESS-WAVE-001
- **Description:** Verify hook advances to next wave
- **Setup:** Create state file with 2 phases in wave 0, mark first complete, then run hook for second
- **Command:** `hooks/PostToolUse/update_wave_state.sh Task "Phase ID: phase_0_1\nResult: success" 0`
- **Expected Result:** Exit code 0, current_wave incremented to 1, wave 0 marked complete
- **Pass Criteria:** State file shows current_wave=1, wave_status["0"] = "completed"

#### Test 6.3: Mark Workflow Complete
- **Test ID:** PROGRESS-WORKFLOW-001
- **Description:** Verify hook marks workflow complete on final wave
- **Setup:** Create state file with 1 wave, 1 phase, mark phase complete
- **Command:** `hooks/PostToolUse/update_wave_state.sh Task "Phase ID: phase_0_0\nResult: success" 0`
- **Expected Result:** Exit code 0, status = "completed", message "Workflow complete"
- **Pass Criteria:** State file shows status="completed"

#### Test 6.4: Update Compliance Log
- **Test ID:** PROGRESS-LOG-001
- **Description:** Verify hook updates compliance_log
- **Setup:** Create state file with one phase
- **Command:** `hooks/PostToolUse/update_wave_state.sh Task "Phase ID: phase_0_0\nResult: success" 0`
- **Expected Result:** Exit code 0, compliance_log has new entry
- **Pass Criteria:** Compliance log contains phase completion event

---

### Category 7: Edge Case Tests

**Purpose:** Test boundary conditions and error scenarios

#### Test 7.1: Empty Execution Plan
- **Test ID:** EDGE-EMPTY-001
- **Description:** Verify hook handles empty waves array
- **Setup:** Create state file with empty waves: []
- **Command:** `hooks/PreToolUse/validate_task_graph_compliance.sh Task "Phase ID: phase_0_0\nTest"`
- **Expected Result:** Exit code 1, error "Phase not found"
- **Pass Criteria:** Hook handles empty plan gracefully

#### Test 7.2: Malformed Phase ID
- **Test ID:** EDGE-MALFORMED-001
- **Description:** Verify hook handles incorrect phase ID format
- **Setup:** Create valid state file
- **Command:** `hooks/PreToolUse/validate_task_graph_compliance.sh Task "Phase ID: invalidformat\nTest"`
- **Expected Result:** Exit code 1, error message about phase not found
- **Pass Criteria:** Hook rejects malformed phase IDs

#### Test 7.3: Concurrent Phase Completion
- **Test ID:** EDGE-CONCURRENT-001
- **Description:** Verify hook handles multiple phases completing in parallel wave
- **Setup:** Create state file with 3 parallel phases in wave 0
- **Command:** Run update_wave_state.sh for each phase sequentially
- **Expected Result:** Wave advances only after 3rd phase completes
- **Pass Criteria:** Wave advancement happens at correct count

#### Test 7.4: State File Corruption
- **Test ID:** EDGE-CORRUPT-001
- **Description:** Verify hook handles invalid JSON in state file
- **Setup:** Create file with invalid JSON syntax
- **Command:** `hooks/PreToolUse/validate_task_graph_compliance.sh Task "Phase ID: phase_0_0\nTest"`
- **Expected Result:** Exit code 1, error about JSON parsing
- **Pass Criteria:** Hook fails gracefully with clear error

#### Test 7.5: Missing Required Fields
- **Test ID:** EDGE-MISSING-001
- **Description:** Verify hook handles state file missing required fields
- **Setup:** Create JSON missing current_wave field
- **Command:** `hooks/PreToolUse/validate_task_graph_compliance.sh Task "Phase ID: phase_0_0\nTest"`
- **Expected Result:** Exit code 1, error about missing fields
- **Pass Criteria:** Hook validates required fields exist

---

## Pass/Fail Criteria

### Overall Test Suite

**PASS:** All critical tests pass (Categories 1-5)
**PASS WITH WARNINGS:** Critical tests pass, some edge case tests fail
**FAIL:** Any critical test fails (hook installation, syntax, or enforcement tests)

### Critical Tests (Must Pass)

- All Category 1 tests (Hook Installation)
- All Category 2 tests (Hook Script Validation)
- All Category 3 tests (Prompt Engineering)
- Test 5.1, 5.2, 5.4, 5.5 (Wave Order Enforcement)
- Test 6.1, 6.2, 6.3 (Wave Auto-Progression)

### Non-Critical Tests (Should Pass)

- Category 4 tests (JSON Schema Validation)
- Category 7 tests (Edge Cases)
- Test 5.3, 6.4 (Logging and warnings)

---

## Test Execution Summary

**Total Tests:** 43

**Breakdown:**
- Category 1 (Hook Installation): 6 tests
- Category 2 (Hook Validation): 4 tests
- Category 3 (Prompt Engineering): 9 tests
- Category 4 (JSON Schema): 5 tests
- Category 5 (Wave Enforcement): 5 tests
- Category 6 (Wave Progression): 4 tests
- Category 7 (Edge Cases): 5 tests
- Integration Tests: 5 tests (from implementation report)

**Estimated Runtime:** 2-5 minutes

**Manual Verification Required:**
- Test 5.3 (warning message content)
- Test 6.4 (compliance log format)
- Integration tests (end-to-end workflows)

---

## Test Results Template

```
=== TASK GRAPH ENFORCEMENT TEST RESULTS ===
Date: YYYY-MM-DD
Tester: [Name]

Category 1: Hook Installation
  [PASS/FAIL] HOOK-INSTALL-001: validate_task_graph_compliance.sh exists
  [PASS/FAIL] HOOK-INSTALL-002: validate_task_graph_compliance.sh executable
  [PASS/FAIL] HOOK-INSTALL-003: update_wave_state.sh exists
  [PASS/FAIL] HOOK-INSTALL-004: update_wave_state.sh executable
  [PASS/FAIL] HOOK-INSTALL-005: PreToolUse hook registered
  [PASS/FAIL] HOOK-INSTALL-006: PostToolUse hook registered

Category 2: Hook Script Validation
  [PASS/FAIL] HOOK-SYNTAX-001: PreToolUse syntax check
  [PASS/FAIL] HOOK-SYNTAX-002: PostToolUse syntax check
  [PASS/FAIL] HOOK-RUNTIME-001: PreToolUse no state file
  [PASS/FAIL] HOOK-RUNTIME-002: PreToolUse missing phase ID

Category 3: Prompt Engineering
  [PASS/FAIL] PROMPT-MANDATORY-001: WORKFLOW_ORCHESTRATOR compliance section
  [PASS/FAIL] PROMPT-MANDATORY-002: Critical rules section
  [PASS/FAIL] PROMPT-MANDATORY-003: All 5 rules documented
  [PASS/FAIL] PROMPT-JSON-001: JSON output section
  [PASS/FAIL] PROMPT-JSON-002: Binding contract language
  [PASS/FAIL] PROMPT-JSON-003: JSON schema
  [PASS/FAIL] PROMPT-DELEGATE-001: State initialization
  [PASS/FAIL] PROMPT-DELEGATE-002: Wave execution protocol
  [PASS/FAIL] PROMPT-DELEGATE-003: Phase ID format

Category 4: JSON Schema Validation
  [PASS/FAIL] SCHEMA-VALID-001: Valid state file creation
  [PASS/FAIL] SCHEMA-VALID-002: Execution plan schema
  [PASS/FAIL] SCHEMA-VALID-003: Wave structure
  [PASS/FAIL] SCHEMA-VALID-004: Phase structure
  [PASS/FAIL] SCHEMA-VALID-005: Phase ID format

Category 5: Wave Order Enforcement
  [PASS/FAIL] ENFORCE-WAVE-001: Allow current wave
  [PASS/FAIL] ENFORCE-WAVE-002: Block future wave
  [PASS/FAIL] ENFORCE-WAVE-003: Allow past wave
  [PASS/FAIL] ENFORCE-PHASE-001: Block invalid phase
  [PASS/FAIL] ENFORCE-PHASE-002: Block missing marker

Category 6: Wave Auto-Progression
  [PASS/FAIL] PROGRESS-PHASE-001: Mark phase complete
  [PASS/FAIL] PROGRESS-WAVE-001: Advance wave
  [PASS/FAIL] PROGRESS-WORKFLOW-001: Mark workflow complete
  [PASS/FAIL] PROGRESS-LOG-001: Update compliance log

Category 7: Edge Cases
  [PASS/FAIL] EDGE-EMPTY-001: Empty execution plan
  [PASS/FAIL] EDGE-MALFORMED-001: Malformed phase ID
  [PASS/FAIL] EDGE-CONCURRENT-001: Concurrent completion
  [PASS/FAIL] EDGE-CORRUPT-001: State file corruption
  [PASS/FAIL] EDGE-MISSING-001: Missing required fields

OVERALL RESULT: [PASS/FAIL/PASS WITH WARNINGS]
CRITICAL TESTS: [X/28] passed
TOTAL TESTS: [X/43] passed
```

---

## Recommendations

### If Tests Fail

1. **Hook Installation Failures:**
   - Run: `cp -r hooks ~/.claude/`
   - Run: `chmod +x ~/.claude/hooks/PreToolUse/validate_task_graph_compliance.sh`
   - Run: `chmod +x ~/.claude/hooks/PostToolUse/update_wave_state.sh`

2. **Hook Syntax Failures:**
   - Review bash syntax errors
   - Check shebang line: `#!/usr/bin/env bash`
   - Verify jq commands are valid

3. **Prompt Engineering Failures:**
   - Verify git branch is current
   - Check file modifications were committed
   - Search for MANDATORY sections manually

4. **Enforcement Failures:**
   - Enable debug logging: `export DEBUG_TASK_GRAPH=1`
   - Review hook execution in debug log
   - Test hooks manually with sample state files

### Next Steps After Testing

1. Document all test results in this file
2. Address any critical failures before deployment
3. Create issue tickets for non-critical failures
4. Run integration tests with real workflows
5. Monitor compliance logs in production

---

**End of Test Plan**
