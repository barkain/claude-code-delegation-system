#!/usr/bin/env python3
"""End-to-end test for workflow state system.

Tests:
1. Create test workflow.json with 3 phases
2. Verify WORKFLOW_STATUS.md generation
3. Test workflow_sync.sh hook
4. Verify phase status updates
"""

import json
import logging
import subprocess
import sys
from pathlib import Path

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format="%(levelname)s: %(message)s"
)
logger = logging.getLogger(__name__)

# Add scripts to path for imports
SCRIPTS_DIR = Path(__file__).parent.parent / "scripts"
sys.path.insert(0, str(SCRIPTS_DIR))

# Import workflow_state module
from workflow_state import (  # pyright: ignore[reportMissingImports]
    create_workflow_state,
    get_workflow_state,
    update_phase_status,
)

# Test artifacts
STATE_DIR = Path("../.claude/state")
WORKFLOW_JSON = STATE_DIR / "workflow.json"
WORKFLOW_STATUS_MD = Path("../.claude/WORKFLOW_STATUS.md")
HOOK_SCRIPT = Path("../hooks/PostToolUse/workflow_sync.sh")


class TestResult:
    """Test result container."""

    def __init__(self, name: str):
        self.name = name
        self.passed = False
        self.errors: list[str] = []
        self.artifacts: list[str] = []

    def fail(self, error: str) -> None:
        """Mark test as failed with error message."""
        self.passed = False
        self.errors.append(error)
        logger.error("[%s] FAIL: %s", self.name, error)

    def succeed(self, message: str = "") -> None:
        """Mark test as passed."""
        self.passed = True
        if message:
            logger.info("[%s] PASS: %s", self.name, message)
        else:
            logger.info("[%s] PASS", self.name)

    def add_artifact(self, path: str) -> None:
        """Add artifact path."""
        self.artifacts.append(path)


def cleanup_test_artifacts() -> None:
    """Clean up test artifacts before starting."""
    logger.info("Cleaning up existing test artifacts...")

    if WORKFLOW_JSON.exists():
        WORKFLOW_JSON.unlink()
        logger.info("Removed %s", WORKFLOW_JSON)

    if WORKFLOW_STATUS_MD.exists():
        WORKFLOW_STATUS_MD.unlink()
        logger.info("Removed %s", WORKFLOW_STATUS_MD)


def test_create_workflow() -> TestResult:
    """TEST 1: Create test workflow.json with 3 phases."""
    result = TestResult("TEST 1: Create workflow.json")

    logger.info("\n=== TEST 1: Create workflow.json ===")

    try:
        # Define test workflow
        task = "End-to-end test workflow"
        phases = [
            ("Setup environment", "general-purpose"),
            ("Implement feature", "general-purpose"),
            ("Run tests", "task-completion-verifier")
        ]

        # Create workflow
        workflow_id = create_workflow_state(task, phases)
        logger.info("Created workflow: %s", workflow_id)

        # Verify workflow.json exists
        if not WORKFLOW_JSON.exists():
            result.fail(f"workflow.json not created at {WORKFLOW_JSON}")
            return result

        result.add_artifact(str(WORKFLOW_JSON.resolve()))
        logger.info("Verified workflow.json created at %s", WORKFLOW_JSON.resolve())

        # Load and validate JSON structure
        with WORKFLOW_JSON.open() as f:
            workflow = json.load(f)

        # Check required fields
        required_fields = ["id", "task", "status", "current_phase", "phases"]
        missing_fields = [f for f in required_fields if f not in workflow]

        if missing_fields:
            result.fail(f"Missing required fields: {missing_fields}")
            return result

        logger.info("Validated JSON structure - all required fields present")

        # Verify workflow ID format
        if not workflow["id"].startswith("wf_"):
            result.fail(f"Invalid workflow ID format: {workflow['id']}")
            return result

        logger.info("Validated workflow ID format: %s", workflow["id"])

        # Verify phases
        if len(workflow["phases"]) != 3:
            result.fail(f"Expected 3 phases, got {len(workflow['phases'])}")
            return result

        logger.info("Validated 3 phases present")

        # Verify phase structure
        for i, phase in enumerate(workflow["phases"]):
            expected_id = f"phase_{i}"
            if phase["id"] != expected_id:
                result.fail(f"Phase {i} has incorrect ID: {phase['id']}")
                return result

            required_phase_fields = ["id", "title", "agent", "status", "deliverables", "context_for_next"]
            missing_phase_fields = [f for f in required_phase_fields if f not in phase]

            if missing_phase_fields:
                result.fail(f"Phase {i} missing fields: {missing_phase_fields}")
                return result

        logger.info("Validated all phase structures")

        # Verify initial status
        if workflow["status"] != "pending":
            result.fail(f"Expected status 'pending', got '{workflow['status']}'")
            return result

        if workflow["current_phase"] is not None:
            result.fail(f"Expected current_phase to be None, got '{workflow['current_phase']}'")
            return result

        logger.info("Validated initial workflow status")

        result.succeed("workflow.json created with correct structure")
        return result

    except Exception as e:
        result.fail(f"Exception during test: {e}")
        logger.exception("Test failed with exception")
        return result


def test_workflow_status_md() -> TestResult:
    """TEST 2: Verify WORKFLOW_STATUS.md generation."""
    result = TestResult("TEST 2: WORKFLOW_STATUS.md generation")

    logger.info("\n=== TEST 2: WORKFLOW_STATUS.md generation ===")

    try:
        # Verify file exists
        if not WORKFLOW_STATUS_MD.exists():
            result.fail(f"WORKFLOW_STATUS.md not created at {WORKFLOW_STATUS_MD}")
            return result

        result.add_artifact(str(WORKFLOW_STATUS_MD.resolve()))
        logger.info("Verified WORKFLOW_STATUS.md created at %s", WORKFLOW_STATUS_MD.resolve())

        # Read markdown content
        markdown_content = WORKFLOW_STATUS_MD.read_text()

        # Verify markdown formatting
        if not markdown_content.startswith("# Workflow:"):
            result.fail("Missing workflow title header")
            return result

        logger.info("Validated workflow title header present")

        # Verify sections
        required_sections = ["**Status:**", "## Phases"]
        for section in required_sections:
            if section not in markdown_content:
                result.fail(f"Missing required section: {section}")
                return result

        logger.info("Validated required sections present")

        # Verify all 3 phases listed
        phase_markers = [
            "Phase 0: Setup environment",
            "Phase 1: Implement feature",
            "Phase 2: Run tests"
        ]

        for marker in phase_markers:
            if marker not in markdown_content:
                result.fail(f"Missing phase: {marker}")
                return result

        logger.info("Validated all 3 phases listed in markdown")

        # Verify checkbox formatting
        if "- [ ]" not in markdown_content:
            result.fail("Missing checkbox formatting")
            return result

        logger.info("Validated checkbox formatting present")

        # Verify agent info for each phase
        agent_markers = [
            "**Agent:** general-purpose",
            "**Agent:** task-completion-verifier"
        ]

        for marker in agent_markers:
            if marker not in markdown_content:
                result.fail(f"Missing agent info: {marker}")
                return result

        logger.info("Validated agent information present")

        result.succeed("WORKFLOW_STATUS.md correctly formatted with all phases")
        return result

    except Exception as e:
        result.fail(f"Exception during test: {e}")
        logger.exception("Test failed with exception")
        return result


def test_workflow_sync_hook() -> TestResult:
    """TEST 3: Test workflow_sync.sh hook."""
    result = TestResult("TEST 3: workflow_sync.sh hook")

    logger.info("\n=== TEST 3: workflow_sync.sh hook ===")

    try:
        # Verify hook script exists
        if not HOOK_SCRIPT.exists():
            result.fail(f"Hook script not found at {HOOK_SCRIPT}")
            return result

        logger.info("Verified hook script exists at %s", HOOK_SCRIPT.resolve())

        # Verify hook is executable
        if not HOOK_SCRIPT.stat().st_mode & 0o111:
            result.fail("Hook script is not executable")
            return result

        logger.info("Verified hook script is executable")

        # Create mock PostToolUse JSON input
        mock_input = {"tool_name": "Task"}
        mock_json = json.dumps(mock_input)

        logger.info("Created mock JSON input: %s", mock_json)

        # Execute hook with mock input
        try:
            proc = subprocess.run(
                [str(HOOK_SCRIPT.resolve())],
                input=mock_json,
                capture_output=True,
                text=True,
                timeout=10,
                check=True
            )

            logger.info("Hook executed successfully (exit code: 0)")

            if proc.stdout:
                logger.info("Hook stdout: %s", proc.stdout.strip())
            if proc.stderr:
                logger.info("Hook stderr: %s", proc.stderr.strip())

        except subprocess.CalledProcessError as e:
            result.fail(f"Hook execution failed with exit code {e.returncode}: {e.stderr}")
            return result
        except subprocess.TimeoutExpired:
            result.fail("Hook execution timed out after 10 seconds")
            return result

        # Verify workflow.json still exists (hook should recognize active workflow)
        if not WORKFLOW_JSON.exists():
            result.fail("workflow.json was deleted by hook")
            return result

        logger.info("Verified workflow.json still exists after hook execution")

        result.succeed("Hook executed successfully and recognized active workflow")
        return result

    except Exception as e:
        result.fail(f"Exception during test: {e}")
        logger.exception("Test failed with exception")
        return result


def test_phase_status_updates() -> TestResult:
    """TEST 4: Verify phase status updates."""
    result = TestResult("TEST 4: Phase status updates")

    logger.info("\n=== TEST 4: Phase status updates ===")

    try:
        # Load initial workflow state
        initial_workflow = get_workflow_state()
        if not initial_workflow:
            result.fail("Could not load workflow state")
            return result

        logger.info("Loaded initial workflow state")

        # Verify initial state
        if initial_workflow["status"] != "pending":
            result.fail(f"Expected initial status 'pending', got '{initial_workflow['status']}'")
            return result

        if initial_workflow["current_phase"] is not None:
            result.fail(f"Expected initial current_phase to be None, got '{initial_workflow['current_phase']}'")
            return result

        logger.info("Verified initial state: status=pending, current_phase=None")

        # Mark phase_0 as active first
        logger.info("Marking phase_0 as active...")
        update_phase_status("phase_0", "active")

        workflow_after_active = get_workflow_state()
        if not workflow_after_active:
            result.fail("Could not load workflow state after marking phase_0 active")
            return result

        if workflow_after_active["current_phase"] != "phase_0":
            result.fail(f"Expected current_phase 'phase_0', got '{workflow_after_active['current_phase']}'")
            return result

        if workflow_after_active["status"] != "active":
            result.fail(f"Expected workflow status 'active', got '{workflow_after_active['status']}'")
            return result

        logger.info("Verified phase_0 marked as active, workflow activated")

        # Mark phase_0 as completed
        logger.info("Marking phase_0 as completed with deliverables...")
        update_phase_status(
            "phase_0",
            "completed",
            deliverables=["Setup complete", "Environment configured"],
            context_for_next="Environment ready for implementation"
        )

        # Load updated workflow state
        updated_workflow = get_workflow_state()
        if not updated_workflow:
            result.fail("Could not load workflow state after update")
            return result

        logger.info("Loaded updated workflow state")

        # Verify phase_0 is completed
        phase_0 = next((p for p in updated_workflow["phases"] if p["id"] == "phase_0"), None)
        if not phase_0:
            result.fail("phase_0 not found in updated workflow")
            return result

        if phase_0["status"] != "completed":
            result.fail(f"Expected phase_0 status 'completed', got '{phase_0['status']}'")
            return result

        logger.info("Verified phase_0 status = 'completed'")

        # Verify deliverables were saved
        if phase_0["deliverables"] != ["Setup complete", "Environment configured"]:
            result.fail(f"Deliverables mismatch: {phase_0['deliverables']}")
            return result

        logger.info("Verified phase_0 deliverables saved")

        # Verify context_for_next was saved
        if phase_0["context_for_next"] != "Environment ready for implementation":
            result.fail(f"Context mismatch: {phase_0['context_for_next']}")
            return result

        logger.info("Verified phase_0 context_for_next saved")

        # Verify current_phase advanced to phase_1
        if updated_workflow["current_phase"] != "phase_1":
            result.fail(f"Expected current_phase 'phase_1', got '{updated_workflow['current_phase']}'")
            return result

        logger.info("Verified current_phase advanced to 'phase_1'")

        # Verify phase_1 status changed to active
        phase_1 = next((p for p in updated_workflow["phases"] if p["id"] == "phase_1"), None)
        if not phase_1:
            result.fail("phase_1 not found in updated workflow")
            return result

        if phase_1["status"] != "active":
            result.fail(f"Expected phase_1 status 'active', got '{phase_1['status']}'")
            return result

        logger.info("Verified phase_1 status changed to 'active'")

        # Verify WORKFLOW_STATUS.md was updated
        updated_markdown = WORKFLOW_STATUS_MD.read_text()

        # Check for completed checkbox for phase 0
        if "[x] Phase 0: Setup environment ✓" not in updated_markdown:
            result.fail("WORKFLOW_STATUS.md not updated with completed phase_0")
            return result

        logger.info("Verified WORKFLOW_STATUS.md shows phase_0 completed")

        # Check for current indicator on phase 1
        if "Phase 1: Implement feature ◀ current" not in updated_markdown:
            result.fail("WORKFLOW_STATUS.md not updated with current phase_1")
            return result

        logger.info("Verified WORKFLOW_STATUS.md shows phase_1 as current")

        # Check for deliverables in markdown
        if "**Deliverables:** Setup complete, Environment configured" not in updated_markdown:
            result.fail("WORKFLOW_STATUS.md missing deliverables")
            return result

        logger.info("Verified WORKFLOW_STATUS.md includes deliverables")

        result.succeed("Phase status updates work correctly with auto-advancement")
        return result

    except Exception as e:
        result.fail(f"Exception during test: {e}")
        logger.exception("Test failed with exception")
        return result


def print_summary(results: list[TestResult]) -> None:
    """Print test summary."""
    logger.info("\n" + "="*70)
    logger.info("END-TO-END TEST SUMMARY")
    logger.info("="*70)

    total_tests = len(results)
    passed_tests = sum(1 for r in results if r.passed)
    failed_tests = total_tests - passed_tests

    for result in results:
        status = "PASS" if result.passed else "FAIL"
        logger.info(f"\n{result.name}: {status}")

        if result.artifacts:
            logger.info("  Artifacts:")
            for artifact in result.artifacts:
                logger.info(f"    - {artifact}")

        if result.errors:
            logger.info("  Errors:")
            for error in result.errors:
                logger.info(f"    - {error}")

    logger.info("\n" + "="*70)
    logger.info(f"RESULTS: {passed_tests}/{total_tests} tests passed")

    if failed_tests > 0:
        logger.error(f"{failed_tests} test(s) FAILED")
    else:
        logger.info("All tests PASSED ✓")

    logger.info("="*70)

    # Print cleanup info
    logger.info("\nTest artifacts created:")
    logger.info(f"  - {WORKFLOW_JSON.resolve()}")
    logger.info(f"  - {WORKFLOW_STATUS_MD.resolve()}")
    logger.info("\nTo clean up test artifacts, run:")
    logger.info(f"  rm -f {WORKFLOW_JSON}")
    logger.info(f"  rm -f {WORKFLOW_STATUS_MD}")


def main() -> int:
    """Run all end-to-end tests."""
    logger.info("Starting end-to-end workflow state system tests...")

    # Cleanup before starting
    cleanup_test_artifacts()

    # Run tests in order
    results: list[TestResult] = []

    # TEST 1: Create workflow
    result1 = test_create_workflow()
    results.append(result1)

    if not result1.passed:
        logger.error("TEST 1 failed, skipping remaining tests")
        print_summary(results)
        return 1

    # TEST 2: Verify markdown
    result2 = test_workflow_status_md()
    results.append(result2)

    # TEST 3: Test hook (can run even if TEST 2 fails)
    result3 = test_workflow_sync_hook()
    results.append(result3)

    # TEST 4: Phase updates (needs TEST 1 to pass)
    result4 = test_phase_status_updates()
    results.append(result4)

    # Print summary
    print_summary(results)

    # Return exit code (0 = all passed, 1 = any failed)
    return 0 if all(r.passed for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
