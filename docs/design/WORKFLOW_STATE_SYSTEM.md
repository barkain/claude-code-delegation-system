# Hybrid Workflow State System - Design Document

## 1. Problem Statement

**Current State Gaps:**
- **Fragmented state:** `active_task_graph.json` (execution order), `delegated_sessions.txt` (sessions), `TodoWrite` (ephemeral UI)
- **No single source of truth:** Each component tracks different aspects, no unified view
- **No persistence for user:** TodoWrite updates disappear after session ends
- **Manual synchronization:** Agents must manually update multiple state locations
- **No workflow resumption:** If orchestration fails mid-workflow, state is lost

**Core Problem:** Users and agents lack a centralized, persistent view of what work is being done, why, and what the current status is.

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        User Request                          │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│          delegation-orchestrator (Workflow Creator)          │
│  - Writes workflow.json (phases, agents, deliverables)      │
│  - Generates initial WORKFLOW_STATUS.md                     │
│  - Initializes TodoWrite with phase list                    │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              .claude/state/workflow.json                     │
│                   (JSON Source of Truth)                     │
└─────────┬───────────────────────────────────┬───────────────┘
          │                                   │
          │ PostToolUse Hook                  │ Auto-sync
          │ (on agent completion)             │
          ▼                                   ▼
┌──────────────────────────┐      ┌──────────────────────────┐
│  TodoWrite Tool          │      │  WORKFLOW_STATUS.md      │
│  (Claude Code UI)        │      │  (Human-readable view)   │
│  - Shows current phase   │      │  - Markdown report       │
│  - Progress visualization│      │  - Phase status          │
└──────────────────────────┘      │  - Deliverables list     │
                                  └──────────────────────────┘
```

**Data Flow:**
1. **Orchestrator writes:** `workflow.json` + initial `WORKFLOW_STATUS.md` + `TodoWrite`
2. **Agents execute:** Complete phases, write deliverables
3. **PostToolUse hook triggers:** On agent task completion
4. **Hook updates:** `workflow.json` status → regenerates `WORKFLOW_STATUS.md` → syncs `TodoWrite`
5. **User reads:** Either file or TodoWrite UI

## 3. Minimal Schema

### workflow.json

```json
{
  "id": "wf_20250105_143022",
  "task": "Create calculator.py with tests and verify they pass",
  "status": "pending|active|completed|failed",
  "current_phase": "phase_0",
  "phases": [
    {
      "id": "phase_0",
      "title": "Create calculator module",
      "agent": "general-purpose",
      "status": "pending|active|completed|failed",
      "deliverables": [],
      "context_for_next": ""
    },
    {
      "id": "phase_1",
      "title": "Write and run tests",
      "agent": "task-completion-verifier",
      "status": "pending",
      "deliverables": [],
      "context_for_next": ""
    }
  ]
}
```

**Field Definitions:**
- `id`: Workflow identifier (format: `wf_YYYYMMDD_HHMMSS`)
- `task`: Original user request (verbatim)
- `status`: Workflow state (pending → active on first phase start → completed/failed)
- `current_phase`: Phase ID currently executing (null if not started)
- `phases[].id`: Phase identifier (format: `phase_N` where N is 0-indexed)
- `phases[].title`: Human-readable phase description
- `phases[].agent`: Agent name (matches `~/.claude/agents/{name}.md`)
- `phases[].status`: Phase state
- `phases[].deliverables`: Array of strings (file paths, outcomes)
- `phases[].context_for_next`: Context passed to next phase (empty until phase completes)

**Status Transitions:**
- Workflow: `pending` → `active` (first phase starts) → `completed|failed` (all phases done)
- Phase: `pending` → `active` (agent spawned) → `completed|failed` (agent finishes)

## 4. Implementation Components

### 4.1 Essential (Phase 1)

**P1.1: Workflow Initialization (orchestrator writes)**
- Function: `create_workflow_state(task, phases) -> workflow_id`
- Creates `.claude/state/workflow.json`
- Generates initial `WORKFLOW_STATUS.md`
- Returns workflow ID for reference

**P1.2: Phase Status Update (agents write)**
- Function: `update_phase_status(workflow_id, phase_id, status, deliverables)`
- Updates `workflow.json` phase status and deliverables
- Regenerates `WORKFLOW_STATUS.md`
- NO direct TodoWrite sync (deferred to hook)

**P1.3: PostToolUse Hook Enhancement**
- Trigger: After `Task` tool completes (agent finishes)
- Logic:
  1. Check if `.claude/state/workflow.json` exists
  2. Extract phase result from tool output
  3. Call `update_phase_status()`
  4. Sync TodoWrite with workflow phases
- File: `hooks/PostToolUse/workflow_sync.sh`

**P1.4: WORKFLOW_STATUS.md Generator**
- Function: `generate_markdown(workflow) -> str`
- Template:
  ```markdown
  # Workflow Status: {task}

  Status: {status} | Current Phase: {current_phase_title}

  ## Phases

  - [x] Phase 0: {title} → {deliverables}
  - [ ] Phase 1: {title}
  ```
- Location: `.claude/WORKFLOW_STATUS.md` (visible in project)

**P1.5: Agent Read Protocol**
- Agents use: `Read` tool on `.claude/state/workflow.json`
- Extract: `current_phase`, `phases[current_phase].context_for_next`
- Pattern: Read at phase start, write at phase end

### 4.2 Deferred (Phase 2+)

**Explicitly excluded from MVP:**
- ❌ Timestamps (started_at, completed_at, duration)
- ❌ Progress percentages (phase 2 of 5 = 40%)
- ❌ Execution metrics (time per phase, retry counts)
- ❌ Historical audit trail (change log)
- ❌ Complex validation (schema enforcement)
- ❌ Error recovery mechanisms (retry logic)
- ❌ Parallel phase tracking (assume sequential for MVP)
- ❌ Context size limits (assume context fits in string field)
- ❌ Agent performance tracking

**Rationale:** These add complexity without solving core problem (unified state). Add incrementally based on real usage patterns.

## 5. Integration Points

### 5.1 With Existing State Files

**Do NOT duplicate:**
- `active_task_graph.json` remains execution enforcer (phase dependencies, parallel waves)
- `delegated_sessions.txt` remains session registry
- `workflow.json` is **presentation layer** - what work is being done and status

**Relationship:**
```
active_task_graph.json:  "HOW to execute" (dependencies, ordering)
workflow.json:           "WHAT is happening" (current status, deliverables)
```

### 5.2 With Hooks

**PreToolUse Hook (existing):**
- No changes needed
- Continues to enforce delegation policy

**PostToolUse Hook (enhanced):**
- Current: `python_posttooluse_hook.sh` (Python validation)
- Add: `workflow_sync.sh` (workflow state sync)
- Execution: Run both hooks (independent operations)

**Hook Registration (settings.json):**
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "*.py",
        "hooks": [{"type": "command", "command": "~/.claude/hooks/PostToolUse/python_posttooluse_hook.sh"}]
      },
      {
        "matcher": "*Task*",
        "hooks": [{"type": "command", "command": "~/.claude/hooks/PostToolUse/workflow_sync.sh"}]
      }
    ]
  }
}
```

### 5.3 With TodoWrite Tool

**Sync Strategy:**
- Orchestrator: Initializes TodoWrite with phase list
- PostToolUse hook: Updates TodoWrite when phases complete
- One-way sync: `workflow.json` → `TodoWrite` (TodoWrite is write-only from code)

**TodoWrite Update Pattern:**
```python
# In workflow_sync.sh (calls Python script)
phases = load_workflow_json()["phases"]
todos = [
    {
        "content": phase["title"],
        "status": "completed" if phase["status"] == "completed" else "in_progress" if phase["status"] == "active" else "pending",
        "activeForm": f"Working on {phase['title']}"
    }
    for phase in phases
]
# Call TodoWrite tool with updated list
```

## 6. Agent Protocol

### 6.1 Orchestrator (Workflow Creator)

**Responsibilities:**
1. Parse user task into phases
2. Select agents for each phase
3. Create `workflow.json` with all phases
4. Generate initial `WORKFLOW_STATUS.md`
5. Initialize `TodoWrite` with phase list
6. Return delegation commands for main Claude

**Code Pattern:**
```python
# In delegation-orchestrator agent
workflow = {
    "id": f"wf_{timestamp()}",
    "task": user_task,
    "status": "pending",
    "current_phase": None,
    "phases": [
        {
            "id": f"phase_{i}",
            "title": phase_title,
            "agent": agent_name,
            "status": "pending",
            "deliverables": [],
            "context_for_next": ""
        }
        for i, (phase_title, agent_name) in enumerate(phases)
    ]
}

# Write workflow state
write_json(".claude/state/workflow.json", workflow)

# Generate status document
generate_markdown(".claude/WORKFLOW_STATUS.md", workflow)

# Initialize TodoWrite
TodoWrite(todos=[...])
```

### 6.2 Execution Agent (Phase Worker)

**Responsibilities:**
1. Read `workflow.json` to get current phase context
2. Execute phase work
3. Update phase status and deliverables
4. Write context for next phase

**Code Pattern:**
```python
# At phase start
workflow = read_json(".claude/state/workflow.json")
my_phase = workflow["phases"][workflow["current_phase"]]
context = my_phase.get("context_for_next", "")  # From previous phase

# Do work...
deliverables = ["/path/to/calculator.py", "add, subtract, multiply, divide functions"]

# At phase end
update_phase_status(
    workflow["id"],
    my_phase["id"],
    status="completed",
    deliverables=deliverables,
    context_for_next="Created calculator.py at /path with 4 functions"
)
```

### 6.3 Phase Transition (Orchestrator or Main Claude)

**After PostToolUse hook updates workflow:**
1. Read `workflow.json`
2. Check if current phase completed
3. Move to next phase:
   - Update `current_phase` to next phase ID
   - Set next phase status to "active"
   - Spawn agent for next phase with context

**Code Pattern:**
```python
workflow = read_json(".claude/state/workflow.json")
current_idx = int(workflow["current_phase"].split("_")[1])
next_idx = current_idx + 1

if next_idx < len(workflow["phases"]):
    workflow["current_phase"] = f"phase_{next_idx}"
    workflow["phases"][next_idx]["status"] = "active"
    workflow["status"] = "active"
    write_json(".claude/state/workflow.json", workflow)

    # Spawn next agent with context
    next_phase = workflow["phases"][next_idx]
    Task(
        agent=next_phase["agent"],
        task=f"{next_phase['title']}\n\nContext: {workflow['phases'][current_idx]['context_for_next']}"
    )
else:
    # All phases complete
    workflow["status"] = "completed"
    workflow["current_phase"] = None
```

## 7. Implementation Checklist

### Phase 1: Core Workflow State (MVP)

**Files to Create:**

1. **`scripts/workflow_state.py`** - Core state management
   - `create_workflow_state(task, phases) -> workflow_id`
   - `update_phase_status(workflow_id, phase_id, status, deliverables, context)`
   - `get_workflow_state(workflow_id) -> dict`
   - `generate_markdown(workflow) -> str`

2. **`hooks/PostToolUse/workflow_sync.sh`** - Hook for state sync
   - Trigger: After Task tool completes
   - Logic: Extract phase result → update workflow.json → sync TodoWrite
   - Call: `scripts/workflow_state.py` functions

3. **`.claude/WORKFLOW_STATUS.md`** - Generated status view (created by workflow_state.py)

**Files to Modify:**

4. **`agents/delegation-orchestrator.md`** - Add workflow initialization
   - After phase analysis, create workflow state
   - Generate WORKFLOW_STATUS.md
   - Initialize TodoWrite with phases

5. **`settings.json`** - Register new PostToolUse hook
   - Add `workflow_sync.sh` to PostToolUse hooks
   - Matcher: `*Task*` (triggers on Task tool)

6. **`CLAUDE.md`** - Document agent protocol
   - Add section: "Workflow State Protocol"
   - Explain: How to read/write workflow.json
   - Pattern: Phase start (read context) → phase end (write status)

### Testing Strategy

**Test 1: Single-Phase Workflow**
- Input: Simple task (create one file)
- Expected: workflow.json created → phase completes → status updated → WORKFLOW_STATUS.md shows "completed"

**Test 2: Multi-Phase Sequential**
- Input: "Create calculator.py with tests and verify"
- Expected:
  - Phase 0 (create) → completed → deliverables recorded
  - Phase 1 (test) → active → context passed
  - Phase 1 → completed → workflow status = "completed"

**Test 3: TodoWrite Sync**
- Input: Multi-phase task
- Expected: TodoWrite UI shows phase list, updates as phases complete

**Test 4: Hook Trigger**
- Input: Manual Task tool invocation
- Expected: PostToolUse hook triggers → workflow.json updated

### Rollout Plan

**Day 1: Core Infrastructure**
- Create `scripts/workflow_state.py` with core functions
- Write unit tests for state management
- Verify JSON read/write operations

**Day 2: Hook Integration**
- Create `workflow_sync.sh` hook
- Register in settings.json
- Test hook triggering with dummy Task calls

**Day 3: Orchestrator Integration**
- Modify delegation-orchestrator to create workflow state
- Test workflow initialization
- Verify WORKFLOW_STATUS.md generation

**Day 4: End-to-End Testing**
- Run complete workflows (single and multi-phase)
- Verify state transitions
- Check TodoWrite synchronization

**Day 5: Documentation & Refinement**
- Update CLAUDE.md with agent protocol
- Add troubleshooting guide
- Performance tuning (if needed)

## 8. Design Rationale

### Why JSON + Markdown (not just one)?

**JSON (workflow.json):**
- Machine-readable: Agents parse and update programmatically
- Structured queries: Easy to extract specific fields
- Atomic updates: Single file write operation

**Markdown (WORKFLOW_STATUS.md):**
- Human-readable: Users can `cat` or view in editor
- Portable: No special tools needed
- Git-friendly: Diffs show meaningful changes

**Both:** Serve different audiences (agents vs users) without compromise.

### Why PostToolUse Hook (not manual agent updates)?

**Hook Advantages:**
- **Automatic:** No agent code changes needed
- **Consistent:** Same sync logic for all agents
- **Reliable:** Can't forget to update state
- **Decoupled:** Agents don't need workflow awareness

**Trade-off:** Slight delay (runs after tool completes), but acceptable for status updates.

### Why Minimal Schema?

**Principles:**
- **YAGNI:** Only add fields when actually needed
- **Fast iterations:** Simpler schema = faster to change
- **Clarity:** Fewer fields = easier to understand

**Example:** Timestamps deferred because:
- Not required for MVP (status is sufficient)
- Easy to add later (non-breaking change)
- Adds complexity (timezone handling, formatting)

### Why Keep active_task_graph.json?

**Separation of concerns:**
- `active_task_graph.json`: Execution model (dependencies, ordering, parallel waves)
- `workflow.json`: Presentation model (what's happening, current status)

**Analogy:**
- Task graph = blueprint (structure, relationships)
- Workflow state = progress report (status, deliverables)

**Both needed:** Task graph for orchestration logic, workflow state for visibility.

## 9. Future Enhancements (Post-MVP)

**Phase 2 Candidates:**
- Timestamps (started_at, completed_at per phase)
- Duration tracking (time per phase, total workflow time)
- Error details (capture error messages in failed phases)
- Retry tracking (attempt count per phase)

**Phase 3 Candidates:**
- Parallel phase support (multiple current_phase values)
- Progress percentages (2 of 5 phases = 40%)
- Historical workflows (archive completed workflows)
- Workflow templates (reusable phase patterns)

**Decision Rule:** Add features only when real usage demonstrates clear need. Resist complexity creep.

---

## Summary

**Core Insight:** Unified state creates clarity. One JSON file + one Markdown view + automated sync = single source of truth without manual overhead.

**Key Design Choices:**
1. **JSON source, Markdown view:** Machine + human needs both satisfied
2. **PostToolUse hook sync:** Automatic, consistent, decoupled
3. **Minimal schema:** Only essential fields, defer nice-to-haves
4. **Reuse existing:** Complement task graph, don't duplicate

**Success Criteria:**
- Users can view workflow status at any time (cat WORKFLOW_STATUS.md)
- Agents update state automatically (via hook)
- TodoWrite stays synchronized (via hook)
- Workflow state persists across sessions (JSON file)
- Implementation < 500 lines of Python (excluding tests)

**Next Steps:** Follow implementation checklist (Section 7) in order. Start with `scripts/workflow_state.py`, test thoroughly, then integrate hooks and orchestrator.
