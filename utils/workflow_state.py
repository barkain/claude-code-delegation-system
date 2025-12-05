"""Workflow state management for delegation system.

Manages workflow.json (source of truth) and WORKFLOW_STATUS.md (human-readable view).
Minimal implementation for unified workflow state tracking.
"""

import json
import logging
from datetime import datetime
from pathlib import Path

logger = logging.getLogger(__name__)


def _get_state_path() -> Path:
    """Get path to workflow state file."""
    return Path(".claude/state/workflow.json")


def _get_status_path() -> Path:
    """Get path to workflow status markdown file."""
    return Path(".claude/WORKFLOW_STATUS.md")


def _generate_workflow_id() -> str:
    """Generate workflow ID with format wf_YYYYMMDD_HHMMSS."""
    return f"wf_{datetime.now().strftime('%Y%m%d_%H%M%S')}"


def _write_workflow(workflow: dict) -> None:
    """Write workflow state to JSON file."""
    state_path = _get_state_path()
    state_path.parent.mkdir(parents=True, exist_ok=True)

    with state_path.open("w") as f:
        json.dump(workflow, f, indent=2)

    logger.info("Wrote workflow state to %s", state_path)


def create_workflow_state(task: str, phases: list[tuple[str, str]]) -> str:
    """Create new workflow state and generate status markdown.

    Args:
        task: User's task description
        phases: List of (title, agent_name) tuples

    Returns:
        Workflow ID (format: wf_YYYYMMDD_HHMMSS)
    """
    workflow_id = _generate_workflow_id()

    workflow = {
        "id": workflow_id,
        "task": task,
        "status": "pending",
        "current_phase": None,
        "phases": [
            {
                "id": f"phase_{i}",
                "title": title,
                "agent": agent,
                "status": "pending",
                "deliverables": [],
                "context_for_next": ""
            }
            for i, (title, agent) in enumerate(phases)
        ]
    }

    # Write JSON state
    _write_workflow(workflow)

    # Generate and write markdown status
    markdown = generate_markdown(workflow)
    status_path = _get_status_path()
    status_path.parent.mkdir(parents=True, exist_ok=True)
    status_path.write_text(markdown)

    logger.info("Created workflow %s with %d phases", workflow_id, len(phases))
    return workflow_id


def update_phase_status(
    phase_id: str,
    status: str,
    deliverables: list[str] | None = None,
    context_for_next: str | None = None
) -> None:
    """Update phase status and regenerate status markdown.

    Args:
        phase_id: Phase identifier (e.g., "phase_0")
        status: New status (pending|active|completed|failed)
        deliverables: Optional list of deliverable descriptions
        context_for_next: Optional context string for next phase
    """
    workflow = get_workflow_state()
    if not workflow:
        logger.error("No active workflow found")
        return

    # Find and update phase
    phase_found = False
    for phase in workflow["phases"]:
        if phase["id"] == phase_id:
            phase["status"] = status
            if deliverables is not None:
                phase["deliverables"] = deliverables
            if context_for_next is not None:
                phase["context_for_next"] = context_for_next
            phase_found = True
            break

    if not phase_found:
        logger.error("Phase %s not found in workflow", phase_id)
        return

    # Auto-advance current_phase if completed
    if status == "completed":
        current_idx = int(phase_id.split("_")[1])
        next_idx = current_idx + 1

        if next_idx < len(workflow["phases"]):
            # Move to next phase
            workflow["current_phase"] = f"phase_{next_idx}"
            workflow["phases"][next_idx]["status"] = "active"
            workflow["status"] = "active"
            logger.info("Advanced to phase_%d", next_idx)
        else:
            # All phases complete
            workflow["current_phase"] = None
            workflow["status"] = "completed"
            logger.info("Workflow completed")
    elif status == "active" and workflow["current_phase"] is None:
        # First phase starting
        workflow["current_phase"] = phase_id
        workflow["status"] = "active"
        logger.info("Workflow activated with %s", phase_id)
    elif status == "failed":
        # Mark workflow as failed
        workflow["status"] = "failed"
        logger.error("Phase %s failed, marking workflow as failed", phase_id)

    # Write updated workflow
    _write_workflow(workflow)

    # Regenerate markdown
    markdown = generate_markdown(workflow)
    _get_status_path().write_text(markdown)

    logger.info("Updated phase %s to status=%s", phase_id, status)


def get_workflow_state() -> dict | None:
    """Get current workflow state.

    Returns:
        Workflow dict or None if no active workflow
    """
    state_path = _get_state_path()
    if not state_path.exists():
        return None

    try:
        with state_path.open() as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        logger.error("Failed to load workflow state: %s", e, exc_info=True)
        return None


def generate_markdown(workflow: dict) -> str:
    """Generate markdown status report from workflow state.

    Args:
        workflow: Workflow state dictionary

    Returns:
        Markdown formatted string
    """
    lines = [
        f"# Workflow: {workflow['task']}",
        "",
        f"**Status:** {workflow['status']}",
        ""
    ]

    # Add current phase info if active
    if workflow["current_phase"]:
        current_phase = next(
            (p for p in workflow["phases"] if p["id"] == workflow["current_phase"]),
            None
        )
        if current_phase:
            lines.append(f"**Current:** {current_phase['title']}")
            lines.append("")

    lines.append("## Phases")
    lines.append("")

    # List all phases with status indicators
    for phase in workflow["phases"]:
        is_current = phase["id"] == workflow["current_phase"]

        # Status checkbox
        if phase["status"] == "completed":
            checkbox = "[x]"
            suffix = " ✓"
        else:
            checkbox = "[ ]"
            suffix = " ◀ current" if is_current else ""

        # Phase line
        phase_num = phase["id"].split("_")[1]
        lines.append(f"- {checkbox} Phase {phase_num}: {phase['title']}{suffix}")

        # Add deliverables if present
        if phase["deliverables"]:
            lines.append(f"  - **Deliverables:** {', '.join(phase['deliverables'])}")

        # Add agent info
        lines.append(f"  - **Agent:** {phase['agent']}")
        lines.append("")

    return "\n".join(lines)
