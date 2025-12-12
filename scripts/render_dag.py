#!/usr/bin/env python3
"""
render_dag.py - Render task graph as beautiful ASCII DAG

Reads JSON task graph and renders a 120-char width ASCII visualization with:
- Box-style task cards with emoji, type, title, agent, goal, deliverable
- Fork-style dependency arrows between waves
- Parallel tasks shown side-by-side (max 3 columns)
- Wave headers with task counts
"""

# ruff: noqa: T201
# This is a CLI script that outputs to stdout

import json
import sys
import textwrap
from pathlib import Path

# Constants
MAX_WIDTH = 120
CARD_WIDTH = 38  # For 3-column layout with spacing
STATE_DIR = Path(__file__).parent.parent / ".claude" / "state"


def wrap_text(text: str, width: int) -> list[str]:
    """Wrap text to specified width."""
    return textwrap.wrap(text, width) or [""]


def render_task_card(task: dict, width: int = CARD_WIDTH) -> list[str]:
    """Render a single task card as list of lines."""
    emoji = task.get("emoji", "📋")
    task_type = task.get("type", "task").upper()
    title = task.get("title", "Untitled")[:width - 10]
    agent = task.get("agent", "general-purpose")
    goal_lines = wrap_text(task.get("goal", ""), width - 4)
    deliverable = task.get("deliverable", "")[:width - 4]

    # Build card
    header = f"─ {emoji} {task_type}: {title} "
    header_line = "┌" + header + "─" * max(0, width - len(header) - 1) + "┐"

    lines = [header_line]
    lines.append(f"│  Agent: {agent:<{width - 11}}│")
    lines.append(f"│  Goal: {'':<{width - 10}}│")
    # Max 2 lines for goal
    lines.extend(f"│    {gl:<{width - 6}}│" for gl in goal_lines[:2])
    lines.append(f"│  Deliverable: {deliverable:<{width - 17}}│")
    lines.append("└" + "─" * (width - 2) + "┘")

    return lines


def render_wave_header(wave: dict, total_width: int = MAX_WIDTH) -> str:
    """Render wave header line."""
    wave_id = wave.get("id", 0)
    name = wave.get("name", "")
    task_count = len(wave.get("tasks", []))
    parallel = wave.get("parallel", False)

    parallel_str = f" {task_count} PARALLEL " if parallel else f" {task_count} task "
    left = f"▸ WAVE {wave_id} "
    if name:
        left += f"─ {name} "

    right = parallel_str
    dashes = "─" * max(0, total_width - len(left) - len(right))
    return left + dashes + right


def render_fork_arrows(count: int, total_width: int = MAX_WIDTH) -> list[str]:
    """Render fork arrows for parallel tasks."""
    if count <= 1:
        return [" " * (total_width // 2) + "│"]

    # Calculate positions for arrows
    spacing = total_width // (count + 1)
    positions = [spacing * (i + 1) for i in range(count)]

    lines = []

    # Single line down from center
    center = total_width // 2
    line1 = " " * center + "│"
    lines.append(line1)

    # Fork line
    fork_line = list(" " * total_width)
    for i, pos in enumerate(positions):
        if i == 0:
            fork_line[pos] = "┌"
        elif i == count - 1:
            fork_line[pos] = "┐"
        else:
            fork_line[pos] = "┬"
    # Connect with dashes
    for i in range(positions[0], positions[-1] + 1):
        if fork_line[i] == " ":
            fork_line[i] = "─"
    # Center connector
    fork_line[center] = "┼" if count > 1 else "│"
    lines.append("".join(fork_line))

    # Down arrows
    arrow_line = list(" " * total_width)
    for pos in positions:
        arrow_line[pos] = "▼"
    lines.append("".join(arrow_line))

    return lines


def render_merge_arrows(count: int, total_width: int = MAX_WIDTH) -> list[str]:
    """Render merge arrows from parallel tasks."""
    if count <= 1:
        return [" " * (total_width // 2) + "│"]

    spacing = total_width // (count + 1)
    positions = [spacing * (i + 1) for i in range(count)]
    center = total_width // 2

    lines = []

    # Down lines from each card
    down_line = list(" " * total_width)
    for pos in positions:
        down_line[pos] = "│"
    lines.append("".join(down_line))

    # Merge line
    merge_line = list(" " * total_width)
    for i, pos in enumerate(positions):
        if i == 0:
            merge_line[pos] = "└"
        elif i == count - 1:
            merge_line[pos] = "┘"
        else:
            merge_line[pos] = "┴"
    for i in range(positions[0], positions[-1] + 1):
        if merge_line[i] == " ":
            merge_line[i] = "─"
    merge_line[center] = "┼" if count > 1 else "│"
    lines.append("".join(merge_line))

    # Single line down
    lines.append(" " * center + "│")

    return lines


def render_cards_side_by_side(tasks: list[dict], total_width: int = MAX_WIDTH) -> list[str]:
    """Render multiple task cards side by side."""
    if not tasks:
        return []

    count = len(tasks)
    card_width = (total_width - (count - 1) * 2) // count  # 2 char spacing between

    # Render each card
    card_lines_list = [render_task_card(t, card_width) for t in tasks]

    # Find max height
    max_height = max(len(cl) for cl in card_lines_list)

    # Pad shorter cards
    for cl in card_lines_list:
        while len(cl) < max_height:
            cl.append(" " * card_width)

    # Combine side by side
    combined = []
    for i in range(max_height):
        row = "  ".join(cl[i] for cl in card_lines_list)
        combined.append(row)

    return combined


def render_single_card_centered(task: dict, total_width: int = MAX_WIDTH) -> list[str]:
    """Render a single card with full width."""
    card_width = total_width - 4  # Some margin
    card_lines = render_task_card(task, card_width)

    # Center the card
    margin = 2
    return [" " * margin + line for line in card_lines]


def render_workflow_header(workflow: dict, total_width: int = MAX_WIDTH) -> list[str]:
    """Render workflow header."""
    name = workflow.get("name", "Workflow")
    phases = workflow.get("total_phases", 0)
    waves = workflow.get("total_waves", 0)

    border = "═" * total_width
    title_line = f" WORKFLOW: {name}"
    stats_line = f" Phases: {phases}  │  Waves: {waves}"

    return [
        border,
        title_line
        + " " * (total_width - len(title_line) - len(f"│ {phases} phases │ {waves} waves")),
        stats_line,
        border,
        "",
    ]


def render_dag(graph: dict) -> str:
    """Main rendering function."""
    lines = []

    # Header
    workflow = graph.get("workflow", {})
    lines.extend(render_workflow_header(workflow))

    waves = graph.get("waves", [])

    for i, wave in enumerate(waves):
        # Wave header
        lines.append(render_wave_header(wave))
        lines.append("")

        tasks = wave.get("tasks", [])

        if not tasks:
            continue

        # Render tasks
        if len(tasks) == 1:
            lines.extend(render_single_card_centered(tasks[0]))
        else:
            lines.extend(render_cards_side_by_side(tasks))

        # Connection to next wave
        if i < len(waves) - 1:
            next_wave = waves[i + 1]
            next_count = len(next_wave.get("tasks", []))
            current_count = len(tasks)

            if current_count == 1 and next_count > 1:
                # Fork
                lines.extend(render_fork_arrows(next_count))
            elif current_count > 1 and next_count == 1:
                # Merge
                lines.extend(render_merge_arrows(current_count))
            elif current_count > 1 and next_count > 1:
                # Merge then fork
                lines.extend(render_merge_arrows(current_count))
                lines.extend(render_fork_arrows(next_count))
            else:
                # Simple connection
                center = MAX_WIDTH // 2
                lines.append(" " * center + "│")
                lines.append(" " * center + "▼")

        lines.append("")

    # Footer
    lines.append(" " * max(0, MAX_WIDTH // 2 - 7) + "═══════ COMPLETE ═══════")

    return "\n".join(lines)


def main():
    # Determine input source
    if len(sys.argv) > 1:
        input_file = Path(sys.argv[1])
    else:
        input_file = STATE_DIR / "current_task_graph.json"

    # Read JSON
    if input_file.exists():
        with open(input_file) as f:
            graph = json.load(f)
    elif not sys.stdin.isatty():
        graph = json.load(sys.stdin)
    else:
        print(f"Error: No input file found at {input_file}", file=sys.stderr)
        print("Usage: render_dag.py [input.json]", file=sys.stderr)
        sys.exit(1)

    # Render
    output = render_dag(graph)

    # Output to stdout
    print(output)

    # Save to file
    output_file = STATE_DIR / "task_graph_rendered.txt"
    output_file.parent.mkdir(parents=True, exist_ok=True)
    with open(output_file, "w") as f:
        f.write(output)

    print(f"\n[Saved to {output_file}]", file=sys.stderr)


if __name__ == "__main__":
    main()
