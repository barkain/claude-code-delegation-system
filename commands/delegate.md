---
description: Intelligently delegate tasks to specialized agents with multi-step detection
argument-hint: [task description]
allowed-tools: Task
---

# Intelligent Task Delegation

**USER TASK:** $ARGUMENTS

---

## How This Works

> **⚠️ CRITICAL: VERBATIM PASS-THROUGH RULE**
>
> **IMMEDIATELY** use `/delegate` with the user's COMPLETE request exactly as received.
> Do NOT announce, explain, create TodoWrite tasks, or do ANY processing before delegating.
> The delegation-orchestrator handles all task analysis and decomposition.

This command uses a **two-stage delegation architecture**:

### Stage 1: Orchestration (Analysis & Planning)
The **delegation-orchestrator** agent analyzes your task to:
- Determine if single-step or multi-step workflow
- Select the most appropriate specialized agent(s)
- Construct optimized delegation prompts
- Return structured recommendation

### Stage 2: Execution (Delegation)
The **main agent** (you are reading this now) receives the orchestrator's recommendation and:
- Parses the delegation prompt from recommendation
- Executes final delegation to specialized agent(s)
- Manages multi-step context passing (if applicable)
- Reports results to user

---

## Automatic Verification Injection

**CRITICAL:** The delegation system automatically injects verification phases for ALL workflows.

### Minimum 2-Phase Structure

ALL workflows have minimum 2 phases:
- **Phase 1:** Implementation (create, build, design, refactor, etc.)
- **Phase 2:** Verification (validate implementation meets acceptance criteria)

Even simple single-file tasks like "Create calculator.py" follow this structure:
1. Implementation phase: Create the file
2. Verification phase: Validate file exists, functions work, type hints present

### How Verification Injection Works

1. Orchestrator identifies implementation phases
2. Automatically creates verification phase for each implementation
3. Verification uses task-completion-verifier or phase-validator agent
4. Verification scheduled in wave after implementation completes

### Verification Verdicts

- **PASS:** Proceed to next phase
- **FAIL:** Re-implementation with remediation steps
- **PASS_WITH_MINOR_ISSUES:** Proceed with warnings tracked

---

## Available Specialized Agents

The orchestrator has access to these specialized agents:

### 1. Code Cleanup Optimizer

Expert agent for code quality improvement, refactoring, and optimization.

**Activation Keywords:** `refactor`, `cleanup`, `optimize`, `improve code quality`, `reduce technical debt`, `modernize code`

**Key Capabilities:**
- Code refactoring and restructuring
- Performance optimization
- Technical debt reduction
- Code smell elimination
- Pattern modernization
- Dependency cleanup

**Ideal Use Cases:**
- Improving existing codebase quality
- Optimizing performance bottlenecks
- Modernizing legacy code patterns
- Reducing code complexity
- Eliminating code duplication
- Cleaning up unused dependencies

**Unique Differentiators:**
- Focus on non-breaking improvements
- Performance-aware refactoring
- Maintains backward compatibility
- Comprehensive testing validation

---

### 2. Code Reviewer

Expert code review agent providing detailed analysis and actionable feedback.

**Activation Keywords:** `review`, `code review`, `critique`, `feedback`, `assess quality`, `evaluate code`

**Key Capabilities:**
- Comprehensive code quality assessment
- Security vulnerability detection
- Performance issue identification
- Best practice validation
- Architecture evaluation
- Detailed improvement recommendations

**Ideal Use Cases:**
- Pre-merge code reviews
- Security audit requirements
- Quality assurance checks
- Architecture validation
- Learning from feedback
- Ensuring coding standards

**Unique Differentiators:**
- Expert-level critique
- Security-focused analysis
- Actionable recommendations
- Educational feedback approach

---

### 3. Codebase Context Analyzer

Read-only analysis agent for understanding existing codebases without modifications.

**Activation Keywords:** `analyze`, `explore`, `understand`, `map`, `investigate`, `examine codebase`

**Key Capabilities:**
- Architecture analysis
- Dependency mapping
- Code flow tracing
- Pattern identification
- Documentation extraction
- Impact analysis

**Ideal Use Cases:**
- Understanding unfamiliar codebases
- Planning refactoring efforts
- Identifying architectural patterns
- Mapping dependencies
- Pre-implementation research
- Knowledge transfer

**Unique Differentiators:**
- Strictly read-only operations
- No code modifications
- Comprehensive context building
- Safe exploratory analysis

---

### 4. Delegation Orchestrator

Meta-agent for analyzing tasks and routing to appropriate specialized agents.

**Activation Keywords:** `delegate`, `route`, `orchestrate`, `coordinate`, `multi-step workflow`

**Key Capabilities:**
- Task complexity analysis
- Agent selection optimization
- Multi-step workflow planning
- Context passing coordination
- Delegation prompt construction
- Workflow orchestration

**Ideal Use Cases:**
- Complex multi-phase projects
- Tasks requiring multiple specialties
- Workflow coordination
- Optimal agent selection
- Context management across phases
- Strategic task routing

**Unique Differentiators:**
- Two-stage delegation architecture
- Intelligent agent matching
- Multi-step workflow support
- Context preservation

---

### 5. Dependency Manager

Specialized agent for Python dependency management and package operations.

**Activation Keywords:** `dependencies`, `packages`, `requirements`, `install`, `upgrade`, `manage packages`

**Key Capabilities:**
- Dependency installation and updates
- Version conflict resolution
- Security vulnerability scanning
- Package compatibility checking
- Requirements file management
- Virtual environment operations

**Ideal Use Cases:**
- Adding new dependencies
- Upgrading package versions
- Resolving dependency conflicts
- Security patch updates
- Requirements synchronization
- Package cleanup operations

**Unique Differentiators:**
- Python package expertise
- UV tool proficiency
- Security-aware updates
- Conflict resolution strategies

---

### 6. DevOps Experience Architect

Infrastructure and deployment expert for CI/CD, containerization, and cloud operations.

**Activation Keywords:** `deploy`, `docker`, `CI/CD`, `infrastructure`, `containerize`, `pipeline`

**Key Capabilities:**
- Docker and containerization
- CI/CD pipeline setup
- Infrastructure as Code
- Cloud platform configuration
- Deployment automation
- Monitoring and observability

**Ideal Use Cases:**
- Setting up deployment pipelines
- Containerizing applications
- Configuring cloud infrastructure
- Automating releases
- Implementing monitoring
- DevOps best practices

**Unique Differentiators:**
- Full-stack DevOps expertise
- Multi-cloud experience
- Security-first approach
- Scalability focus

---

### 7. Documentation Expert

Technical writing specialist for comprehensive documentation creation and improvement.

**Activation Keywords:** `document`, `write docs`, `README`, `explain`, `create guide`, `documentation`

**Key Capabilities:**
- API documentation generation
- README creation and improvement
- Architecture documentation
- User guide writing
- Code comment enhancement
- Tutorial development

**Ideal Use Cases:**
- Creating project documentation
- Writing API references
- Developing user guides
- Improving code comments
- Documenting architecture
- Creating tutorials

**Unique Differentiators:**
- Technical accuracy focus
- Clear communication style
- Multiple audience targeting
- Comprehensive coverage

---

### 8. Task Completion Verifier

Quality assurance agent for validation, testing, and verification.

**Activation Keywords:** `verify`, `test`, `validate`, `check`, `ensure quality`, `QA`

**Key Capabilities:**
- Implementation verification
- Test coverage validation
- Quality metrics assessment
- Requirement compliance checking
- Edge case identification
- Acceptance criteria validation

**Ideal Use Cases:**
- Pre-deployment validation
- Quality assurance checks
- Test coverage verification
- Requirement validation
- Bug prevention
- Release readiness assessment

**Unique Differentiators:**
- Systematic validation approach
- Comprehensive test coverage
- Edge case focus
- Quality metrics driven

---

### 9. Task Decomposer

Project planning specialist for breaking down complex tasks into manageable steps.

**Activation Keywords:** `plan`, `break down`, `decompose`, `outline`, `structure`, `organize tasks`

**Key Capabilities:**
- Task breakdown and sequencing
- Dependency identification
- Timeline estimation
- Resource planning
- Risk assessment
- Milestone definition

**Ideal Use Cases:**
- Planning complex projects
- Breaking down large features
- Identifying dependencies
- Creating implementation roadmaps
- Estimating project scope
- Risk management

**Unique Differentiators:**
- Systematic decomposition
- Dependency awareness
- Realistic estimation
- Risk-conscious planning

---

### 10. Tech Lead Architect

Solution design expert for architectural decisions and technology selection.

**Activation Keywords:** `design`, `architect`, `solution`, `technology choice`, `system design`, `architectural decision`

**Key Capabilities:**
- System architecture design
- Technology stack selection
- Design pattern application
- Scalability planning
- Trade-off analysis
- Technical strategy development

**Ideal Use Cases:**
- Designing new systems
- Selecting technologies
- Architectural decision making
- Scalability planning
- Pattern selection
- Technical roadmap creation

**Unique Differentiators:**
- Strategic technical thinking
- Trade-off analysis expertise
- Scalability focus
- Long-term vision

---

**Note on Progress Tracking:** When the orchestrator identifies multi-step workflows, the main agent must use TodoWrite to create a structured task list for transparent progress tracking throughout all phases.

---

## System-Internal Agents

The delegation system includes specialized internal agents that operate as part of the system's infrastructure. These agents are automatically invoked through hooks and are not directly selectable by users.

### phase-validator

Internal validation agent automatically triggered during workflow execution.

**Type:** System Agent (Hook-Triggered)

**Trigger Mechanism:** PostToolUse hook via `validation_gate.sh`

**Purpose:**
Validates phase completion requirements before allowing workflow progression to subsequent phases. Enforces quality gates and verification standards across all multi-step workflows.

**Key Responsibilities:**
- Validates that all phase deliverables meet acceptance criteria
- Verifies file creation/modification as specified in phase objectives
- Ensures test execution and pass requirements are met
- Validates documentation completeness when required
- Checks that key decisions and configurations are properly documented
- Blocks progression to next phase if validation fails

**Validation Capabilities:**
- File existence and content validation
- Test execution verification (pass/fail status, coverage thresholds)
- Documentation completeness checks
- Configuration validation
- Dependency verification
- Error detection and reporting

**Integration Points:**
- Triggered automatically by PostToolUse hook after specialized agents complete phase work
- Reads validation criteria from `.claude/state/validation/` directory
- Updates validation status in state files
- Blocks workflow progression via hook error returns
- Provides detailed failure messages for remediation

**User Visibility:**
Users do not directly invoke this agent. It operates transparently as part of the system's quality assurance infrastructure, surfacing only when validation failures block workflow progression.

---

## Execution Process

---

**VISUAL OUTPUT REQUIREMENTS:**

When executing delegation, provide clear visual feedback at each stage using the formats below. This ensures users can track progress through the two-stage architecture and understand which agents are handling their tasks.

---

### STAGE 1: ORCHESTRATION (Analysis & Planning)

**Display Format:**
```
═══════════════════════════════════════════════════════════════
  STAGE 1: ORCHESTRATION - Analysis & Planning
═══════════════════════════════════════════════════════════════

Status: IN PROGRESS
Agent: delegation-orchestrator

Task Analysis:
- Evaluating task complexity (single-step vs multi-step)
- Identifying appropriate specialized agent(s)
- Constructing optimized delegation prompts

[Spawn delegation-orchestrator agent and await recommendation...]
```

**After receiving orchestrator recommendation, display:**

```
═══════════════════════════════════════════════════════════════
  STAGE 1: ORCHESTRATION - COMPLETE
═══════════════════════════════════════════════════════════════

Task Type: [Single-step / Multi-step]
Execution Mode: [Direct delegation / Sequential workflow / Parallel workflow]

[For Single-Step:]
Selected Agent: [agent-name]
Selection Rationale: [keyword matches, e.g., "refactor + optimize + improve"]

[For Multi-Step:]

**DEPENDENCY GRAPH (REQUIRED - Extract from Orchestrator Output):**

```
[Extract and display the complete ASCII dependency graph from the orchestrator's recommendation.
Look for the "### Dependency Graph" or "DEPENDENCY GRAPH & EXECUTION PLAN" section in the
orchestrator's output and copy the entire ASCII visualization here, preserving all formatting.]
```

**If orchestrator provided ASCII graph:** Display it above in the code fence exactly as generated.
**If graph is missing:** Use the phase breakdown below as fallback and note the missing graph.

Total Phases: [N]
Total Waves: [M] (for parallel workflows)
Parallel Opportunities: [X tasks can run concurrently] (for parallel workflows)

Phase Breakdown:
  Phase 1: [Phase objective] → Agent: [agent-name]
  Phase 2: [Phase objective] → Agent: [agent-name]
  [...]

Next: Proceeding to Stage 2 (Execution)
```

---

### Step 1: Get Orchestration Recommendation

Spawn the delegation-orchestrator agent directly with clear visual header as shown above.

The orchestrator agent will automatically load its system prompt and:
- Analyze task complexity (multi-step vs single-step)
- Select the most appropriate specialized agent(s)
- Construct optimized delegation prompts
- Return structured recommendation

The recommendation will be in this format:
```markdown
## ORCHESTRATION RECOMMENDATION

### Task Analysis
- Type: [Single-step / Multi-step]
- Complexity: [description]

### Agent Selection (for single-step) OR Phase Breakdown (for multi-step)
...

### Delegation Prompt
```
[Complete prompt ready for delegation]
```

### Execution Instructions for Main Agent
[Natural language instructions for spawning the appropriate agent]
```

### Step 2: Parse Recommendation

Extract from orchestrator's output:

**For Single-Step Tasks:**
- Look for "### Delegation Prompt" section
- Extract the complete prompt between the code fence markers
- This is the prompt to provide when spawning the specialized agent

**For Multi-Step Tasks:**
- Look for "#### Phase 1:" section
- Find "**Phase 1 Delegation Prompt:**" subsection
- Extract the complete prompt between the code fence markers
- Note the context passing requirements for subsequent phases

**Important:** For multi-step workflows, immediately create a TodoWrite task list capturing all phases from the orchestrator's recommendation. This ensures systematic progress tracking and transparent communication with the user throughout the workflow execution.

---

### Step 2.5: Initialize Task Graph State (Multi-Step Only)

**For Multi-Step Workflows with JSON Execution Plan:**

1. **Locate JSON Execution Plan:**
   - Find section titled "REQUIRED: Execution Plan (Machine-Parsable)"
   - Extract complete JSON between code fence markers

2. **Parse and Validate:**
   - Parse JSON to verify valid structure
   - Validate schema_version == "1.0"
   - Verify all required fields present

3. **Initialize State File:**
   - Create `.claude/state/active_task_graph.json`
   - Include: execution_plan, phase_status (all "pending"), wave_status, current_wave=0

4. **Verify Enforcement Active:**
   - State file presence signals hooks to enforce compliance
   - PreToolUse hook will validate all Task invocations against this plan

**CRITICAL:** If JSON execution plan is present, you MUST initialize state file before executing any phases.

---

### Step 3: Execute According to Wave Structure

**Phase Invocation Format (MANDATORY):**

Every Task tool invocation MUST include phase ID marker:

```
Phase ID: phase_0_0
Agent: codebase-context-analyzer

[Delegation prompt from orchestrator for this phase]
```

**Wave Execution Protocol:**

**For Sequential Waves:**
- Execute one phase at a time
- Wait for completion before next phase

**For Parallel Waves (`wave.parallel_execution == true`):**
- Invoke ALL wave phases in SINGLE message
- Do NOT wait between individual invocations

**Wave Transition:**
- PostToolUse hook automatically advances current_wave when all phases complete
- You will see message: "✅ Wave N complete. Advanced to Wave N+1."
- Proceed to next wave's phases

---

### STAGE 2: EXECUTION (Delegation to Specialized Agents)

**Display Format for Single-Step Tasks:**
```
═══════════════════════════════════════════════════════════════
  STAGE 2: EXECUTION - Single-Step Delegation
═══════════════════════════════════════════════════════════════

Agent: [agent-name]
Type: [Specialized / General-purpose]
Task: [Brief task description]

Status: DELEGATING

[Spawn specialized agent with delegation prompt...]
```

**Display Format for Multi-Step Tasks:**
```
═══════════════════════════════════════════════════════════════
  STAGE 2: EXECUTION - Multi-Step Workflow
═══════════════════════════════════════════════════════════════

Workflow Mode: [Sequential / Parallel]
Total Phases: [N]

Progress Tracking:
  [✓] Phase 1: [Phase objective] - COMPLETED
  [▶] Phase 2: [Phase objective] - IN PROGRESS
  [ ] Phase 3: [Phase objective] - PENDING
  [ ] Phase N: [Phase objective] - PENDING

Current Phase Details:
  Phase: 2
  Agent: [agent-name]
  Objective: [Phase objective description]
  Dependencies: Context from Phase 1

[Spawn phase agent with delegation prompt...]
```

**Display Format for Parallel Execution (Waves):**
```
═══════════════════════════════════════════════════════════════
  STAGE 2: EXECUTION - Parallel Workflow (Wave-based)
═══════════════════════════════════════════════════════════════

Workflow Mode: Parallel
Total Waves: [N]
Max Concurrent: 4

Wave 1 Progress:
  [▶] Phase A: [Objective] → Agent: [agent-name] - IN PROGRESS
  [▶] Phase B: [Objective] → Agent: [agent-name] - IN PROGRESS

Wave 2 (Pending Wave 1 completion):
  [ ] Phase C: [Objective] → Agent: [agent-name] - PENDING

Expected Time Savings: ~[percentage]% vs sequential execution

[Spawning Wave 1 agents concurrently...]
```

**Phase Completion Display:**
```
───────────────────────────────────────────────────────────────
  Phase [N] COMPLETE
───────────────────────────────────────────────────────────────

Agent: [agent-name]
Status: SUCCESS

Key Outputs:
  - Created files: [absolute paths]
  - Key decisions: [summary]
  - Configurations: [summary]

Context captured for next phase:
  [Context details for Phase N+1...]

Next: [Proceeding to Phase N+1 / Workflow complete]
```

---

### Step 3: Execute Delegation

**For Single-Step Tasks:**

Display the Stage 2 header for single-step tasks as shown above, then spawn the appropriate specialized agent directly using the extracted delegation prompt. Simply provide the delegation prompt from the orchestrator's recommendation to the main agent, which will automatically interpret and spawn the correct subagent using Claude's built-in subagent system.

**For Multi-Step Tasks:**

1. **Display Stage 2 header** with complete workflow overview as shown above
2. **Use TodoWrite** to create a task list with all phases identified by the orchestrator, ensuring each phase has both content and activeForm descriptions for clear progress tracking
3. **Execute Phase 1** by spawning the appropriate specialized agent directly with the Phase 1 delegation prompt. The main agent will automatically interpret and spawn the correct subagent using Claude's built-in subagent system
4. **Update visual progress** after each phase completion using the Phase Completion Display format

After Phase 1 completes:

1. **Capture context** from Phase 1 results:
   - File paths created/modified (absolute paths)
   - Key decisions made
   - Configurations determined
   - Issues encountered
   - Specific artifacts to reference

2. **Go back to orchestrator** for Phase 2 guidance:
   - Spawn the delegation-orchestrator agent directly
   - Provide user task + context from Phase 1
   - Request Phase 2 recommendation

   **Example: Re-invoking Orchestrator for Phase 2**

   After Phase 1 completes, invoke the orchestrator again by spawning the delegation-orchestrator agent directly with the following prompt structure:

   ```
   **ORIGINAL USER TASK:** $ARGUMENTS

   **COMPLETED PHASES:**

   Phase 1: [Phase name, e.g., 'Research & Analysis']
   Agent Used: [Agent name, e.g., 'tech-lead-architect']
   Results:
   - Created file: /absolute/path/to/file.ext
   - Key decisions: [List decisions made, e.g., 'Selected FastAPI framework', 'Chose PostgreSQL database']
   - Implementation approach: [Describe approach used, e.g., 'Layered architecture with service pattern']
   - Configurations determined: [List any configs, e.g., 'Python 3.12+, async/await patterns']
   - Issues encountered: [Note any blockers/resolutions, e.g., 'None' or 'Resolved dependency conflict']

   **REQUEST:**

   Please provide Phase 2 recommendation based on the completed Phase 1 context above. Use the Phase 2 template from your multi-step breakdown and fill in the specific context from Phase 1 results.
   ```

   This prompt includes:
   - The original user task for reference
   - Complete context from Phase 1 (files created, decisions, approach)
   - Clear request for Phase 2 guidance with Phase 1 context

   **Key Points:**
   - Always use **absolute file paths** when referencing files created in previous phases
   - Capture **specific decisions** (framework choices, architectural patterns, etc.)
   - Note any **blockers or issues** encountered and how they were resolved
   - Include **configuration details** that affect subsequent phases

3. **Parse Phase 2 recommendation** and execute

4. **Repeat** for all remaining phases

### Step 4: Report Results

**Display Format for Single-Step Completion:**
```
═══════════════════════════════════════════════════════════════
  DELEGATION COMPLETE
═══════════════════════════════════════════════════════════════

Task Type: Single-step
Agent: [agent-name]
Status: SUCCESS

Deliverables:
  - [List of deliverables with absolute paths]

Key Decisions:
  - [Notable decisions made during execution]

Next Steps:
  - [Recommended next steps, if applicable]
```

**Display Format for Multi-Step Workflow Completion:**
```
═══════════════════════════════════════════════════════════════
  WORKFLOW COMPLETE
═══════════════════════════════════════════════════════════════

Workflow Type: Multi-step [Sequential / Parallel]
Total Phases: [N]
Execution Time: [Estimated time]

Phase Summary:
  [✓] Phase 1: [Objective]
      Agent: [agent-name]
      Deliverables: [file paths or outputs]

  [✓] Phase 2: [Objective]
      Agent: [agent-name]
      Deliverables: [file paths or outputs]

  [✓] Phase N: [Objective]
      Agent: [agent-name]
      Deliverables: [file paths or outputs]

Final Deliverables:
  - [Consolidated list of all deliverables with absolute paths]

Key Context Flow:
  Phase 1 → Phase 2: [Context passed]
  Phase 2 → Phase 3: [Context passed]

Overall Status: SUCCESS

Next Steps:
  - [Recommended next steps based on workflow completion]
```

**Display Format for Wave-Based Parallel Completion:**
```
═══════════════════════════════════════════════════════════════
  PARALLEL WORKFLOW COMPLETE
═══════════════════════════════════════════════════════════════

Workflow Type: Parallel (Wave-based)
Total Waves: [N]
Total Phases: [M]
Time Savings: ~[percentage]% vs sequential execution

Wave Execution Summary:
  Wave 1 (Completed):
    [✓] Phase A: [Objective] → Agent: [agent-name]
    [✓] Phase B: [Objective] → Agent: [agent-name]

  Wave 2 (Completed):
    [✓] Phase C: [Objective] → Agent: [agent-name]

Aggregated Deliverables:
  From Phase A:
    - [Deliverables with absolute paths]
    - Key decisions: [summary]

  From Phase B:
    - [Deliverables with absolute paths]
    - Key decisions: [summary]

  From Phase C:
    - [Deliverables with absolute paths]
    - Key decisions: [summary]

Overall Status: SUCCESS

Next Steps:
  - [Recommended next steps based on all phase outputs]
```

---

Provide the user with the appropriate completion display format based on task type:

**For Single-Step Tasks:**
- Summary of what agent handled the task
- Key outcomes and deliverables
- Any notable decisions made
- Next steps (if applicable)

**For Multi-Step Tasks:**
- Summary of each completed phase
- Context passed between phases
- Final deliverables across all phases
- Overall workflow completion status

---

## Multi-Step Context Passing Protocol

When executing multi-step workflows, always capture and pass this context between phases:

**Required Context:**
- **File paths** created or modified (use absolute paths)
- **Key decisions** made during the phase
- **Configurations** or settings determined
- **Issues** encountered and how resolved
- **Specific artifacts** to reference in next phase

**Example Context Format:**
```
Context from Phase 1 (Research):
- Analyzed documentation at https://example.com/docs
- Key finding: Plugin system uses event-driven architecture
- Identified 3 core extension points: hooks, filters, middleware
- Created research notes: /tmp/research_notes.md
```

This context gets included in the next orchestrator call to inform Phase 2 planning.

---

## Error Handling

### If Orchestrator Recommendation Parsing Fails
- Look for delegation instructions in the recommendation
- Use those as fallback guidance
- If no clear instructions, ask user for clarification

### If Orchestrator Agent Fails to Load
- Claude Code will report the error
- Fall back to manual agent selection if needed
- Ask user for clarification on how to proceed

### If Multi-Step Phase Fails
- Stop the workflow at the failing phase
- Report which phase failed and why
- Ask user whether to retry the phase or abort workflow
- Do not proceed to next phase without user confirmation

---

## Visual Output Examples

### Example 1: Single-Step Task Flow

**User Request:** `/delegate Refactor the authentication module to improve maintainability`

**Visual Output:**
```
═══════════════════════════════════════════════════════════════
  STAGE 1: ORCHESTRATION - Analysis & Planning
═══════════════════════════════════════════════════════════════

Status: IN PROGRESS
Agent: delegation-orchestrator

Task Analysis:
- Evaluating task complexity (single-step vs multi-step)
- Identifying appropriate specialized agent(s)
- Constructing optimized delegation prompts

[Orchestrator analyzing task...]

═══════════════════════════════════════════════════════════════
  STAGE 1: ORCHESTRATION - COMPLETE
═══════════════════════════════════════════════════════════════

Task Type: Single-step
Execution Mode: Direct delegation

Selected Agent: code-cleanup-optimizer
Selection Rationale: Keywords matched - "refactor" + "improve" + "maintainability" (3 matches)

Next: Proceeding to Stage 2 (Execution)

═══════════════════════════════════════════════════════════════
  STAGE 2: EXECUTION - Single-Step Delegation
═══════════════════════════════════════════════════════════════

Agent: code-cleanup-optimizer
Type: Specialized
Task: Refactor authentication module for improved maintainability

Status: DELEGATING

[Executing refactoring...]

═══════════════════════════════════════════════════════════════
  DELEGATION COMPLETE
═══════════════════════════════════════════════════════════════

Task Type: Single-step
Agent: code-cleanup-optimizer
Status: SUCCESS

Deliverables:
  - Refactored: /Users/user/project/auth/authentication.py
  - Refactored: /Users/user/project/auth/session_manager.py

Key Decisions:
  - Extracted session validation logic into separate class
  - Applied dependency injection for database connections
  - Reduced cyclomatic complexity from 15 to 6

Next Steps:
  - Run tests to verify refactoring preserved functionality
  - Consider adding integration tests for session management
```

### Example 2: Multi-Step Sequential Workflow

**User Request:** `/delegate Create calculator.py with tests and verify they pass`

**Visual Output:**
```
═══════════════════════════════════════════════════════════════
  STAGE 1: ORCHESTRATION - Analysis & Planning
═══════════════════════════════════════════════════════════════

Status: IN PROGRESS
Agent: delegation-orchestrator

Task Analysis:
- Evaluating task complexity (single-step vs multi-step)
- Identifying appropriate specialized agent(s)
- Constructing optimized delegation prompts

[Orchestrator analyzing task...]

═══════════════════════════════════════════════════════════════
  STAGE 1: ORCHESTRATION - COMPLETE
═══════════════════════════════════════════════════════════════

Task Type: Multi-step
Execution Mode: Sequential workflow

Total Phases: 3
Phase Breakdown:
  Phase 1: Create calculator.py → Agent: general-purpose
  Phase 2: Write comprehensive tests → Agent: task-completion-verifier
  Phase 3: Run tests and verify → Agent: task-completion-verifier

Next: Proceeding to Stage 2 (Execution)

═══════════════════════════════════════════════════════════════
  STAGE 2: EXECUTION - Multi-Step Workflow
═══════════════════════════════════════════════════════════════

Workflow Mode: Sequential
Total Phases: 3

Progress Tracking:
  [▶] Phase 1: Create calculator.py - IN PROGRESS
  [ ] Phase 2: Write comprehensive tests - PENDING
  [ ] Phase 3: Run tests and verify - PENDING

Current Phase Details:
  Phase: 1
  Agent: general-purpose
  Objective: Create calculator.py with basic operations

[Executing Phase 1...]

───────────────────────────────────────────────────────────────
  Phase 1 COMPLETE
───────────────────────────────────────────────────────────────

Agent: general-purpose
Status: SUCCESS

Key Outputs:
  - Created files: /Users/user/project/calculator.py

Context captured for next phase:
  - File location: /Users/user/project/calculator.py
  - Functions implemented: add, subtract, multiply, divide
  - Type hints: Python 3.12+ style

Next: Proceeding to Phase 2

Progress Tracking:
  [✓] Phase 1: Create calculator.py - COMPLETED
  [▶] Phase 2: Write comprehensive tests - IN PROGRESS
  [ ] Phase 3: Run tests and verify - PENDING

Current Phase Details:
  Phase: 2
  Agent: task-completion-verifier
  Objective: Write comprehensive tests for calculator.py
  Dependencies: Context from Phase 1

[Executing Phase 2...]

───────────────────────────────────────────────────────────────
  Phase 2 COMPLETE
───────────────────────────────────────────────────────────────

Agent: task-completion-verifier
Status: SUCCESS

Key Outputs:
  - Created files: /Users/user/project/test_calculator.py

Context captured for next phase:
  - Test file: /Users/user/project/test_calculator.py
  - Coverage: 100% of calculator.py functions

Next: Proceeding to Phase 3

Progress Tracking:
  [✓] Phase 1: Create calculator.py - COMPLETED
  [✓] Phase 2: Write comprehensive tests - COMPLETED
  [▶] Phase 3: Run tests and verify - IN PROGRESS

Current Phase Details:
  Phase: 3
  Agent: task-completion-verifier
  Objective: Run tests and verify they pass
  Dependencies: Context from Phase 2

[Executing Phase 3...]

───────────────────────────────────────────────────────────────
  Phase 3 COMPLETE
───────────────────────────────────────────────────────────────

Agent: task-completion-verifier
Status: SUCCESS

Key Outputs:
  - All tests passed (8/8)
  - Coverage: 100%

═══════════════════════════════════════════════════════════════
  WORKFLOW COMPLETE
═══════════════════════════════════════════════════════════════

Workflow Type: Multi-step Sequential
Total Phases: 3
Execution Time: ~3 minutes

Phase Summary:
  [✓] Phase 1: Create calculator.py
      Agent: general-purpose
      Deliverables: /Users/user/project/calculator.py

  [✓] Phase 2: Write comprehensive tests
      Agent: task-completion-verifier
      Deliverables: /Users/user/project/test_calculator.py

  [✓] Phase 3: Run tests and verify
      Agent: task-completion-verifier
      Deliverables: Test results (8/8 passed)

Final Deliverables:
  - /Users/user/project/calculator.py
  - /Users/user/project/test_calculator.py

Key Context Flow:
  Phase 1 → Phase 2: Calculator file path and function signatures
  Phase 2 → Phase 3: Test file path and coverage requirements

Overall Status: SUCCESS

Next Steps:
  - Consider adding edge case tests (division by zero, etc.)
  - Ready for integration into main project
```

### Example 3: Parallel Workflow (Wave-based)

**User Request:** `/delegate Analyze authentication system AND design payment API`

**Visual Output:**
```
═══════════════════════════════════════════════════════════════
  STAGE 1: ORCHESTRATION - Analysis & Planning
═══════════════════════════════════════════════════════════════

Status: IN PROGRESS
Agent: delegation-orchestrator

Task Analysis:
- Evaluating task complexity (single-step vs multi-step)
- Identifying appropriate specialized agent(s)
- Constructing optimized delegation prompts

[Orchestrator analyzing task...]

═══════════════════════════════════════════════════════════════
  STAGE 1: ORCHESTRATION - COMPLETE
═══════════════════════════════════════════════════════════════

Task Type: Multi-step
Execution Mode: Parallel workflow

Total Phases: 2
Phase Breakdown:
  Wave 1 (Parallel):
    Phase A: Analyze authentication system → Agent: codebase-context-analyzer
    Phase B: Design payment API → Agent: tech-lead-architect

Next: Proceeding to Stage 2 (Execution)

═══════════════════════════════════════════════════════════════
  STAGE 2: EXECUTION - Parallel Workflow (Wave-based)
═══════════════════════════════════════════════════════════════

Workflow Mode: Parallel
Total Waves: 1
Max Concurrent: 4

Wave 1 Progress:
  [▶] Phase A: Analyze authentication system → Agent: codebase-context-analyzer - IN PROGRESS
  [▶] Phase B: Design payment API → Agent: tech-lead-architect - IN PROGRESS

Expected Time Savings: ~50% vs sequential execution

[Spawning Wave 1 agents concurrently...]

───────────────────────────────────────────────────────────────
  Wave 1 COMPLETE
───────────────────────────────────────────────────────────────

Phase A Status: SUCCESS
Phase B Status: SUCCESS

═══════════════════════════════════════════════════════════════
  PARALLEL WORKFLOW COMPLETE
═══════════════════════════════════════════════════════════════

Workflow Type: Parallel (Wave-based)
Total Waves: 1
Total Phases: 2
Time Savings: ~50% vs sequential execution

Wave Execution Summary:
  Wave 1 (Completed):
    [✓] Phase A: Analyze authentication system → Agent: codebase-context-analyzer
    [✓] Phase B: Design payment API → Agent: tech-lead-architect

Aggregated Deliverables:
  From Phase A:
    - /Users/user/project/auth_analysis.md
    - Key findings: JWT-based authentication, session management patterns
    - Security requirements: OAuth 2.0 integration needed

  From Phase B:
    - /Users/user/project/payment_api_design.md
    - Key decisions: RESTful API, Stripe integration
    - API endpoints: /payments/create, /payments/verify, /payments/refund

Overall Status: SUCCESS

Next Steps:
  - Review both documents for integration points
  - Consider security implications of payment/auth integration
  - Plan implementation phase
```

---

## Best Practices

1. **Always parse carefully** - Extract exact prompt from recommendation code fences
2. **Preserve prompt structure** - Use delegation prompt exactly as provided by orchestrator
3. **Track context diligently** - In multi-step workflows, capture comprehensive context
4. **Report transparently** - Let user know which agents handled which parts using visual displays
5. **Handle errors gracefully** - Stop and ask user before proceeding after failures
6. **Use TodoWrite for multi-step workflows** - Create task lists immediately after receiving orchestrator recommendations for multi-step tasks, updating status as each phase completes to maintain transparency
7. **Display visual progress** - Use the visual output formats defined above at each stage to keep users informed of delegation progress
8. **Show agent selection rationale** - Always display keyword matches and agent selection reasoning in Stage 1 completion display
9. **Update phase progress in real-time** - Display current phase status before spawning agents and completion status after each phase
10. **Aggregate results clearly** - For parallel workflows, show aggregated deliverables from all phases in the final completion display

---

## Begin Delegation

Execute the delegation process now using Steps 1-4 above.

**Important Reminders:**
- You will spawn agents twice in the process:
  1. First spawn the delegation-orchestrator agent directly (get recommendation)
  2. Then spawn the specialized agent directly (execute delegation)
- For multi-step: Spawn the orchestrator agent again for each subsequent phase
- Parse the delegation prompt from orchestrator's structured output
- Use the extracted prompt verbatim when spawning the specialized agent
- The main agent will automatically interpret your instructions and spawn the correct subagents using Claude's built-in subagent system

---

## ⚠️ TASK GRAPH COMPLIANCE - BINDING CONTRACT

When the delegation-orchestrator returns an execution plan with a JSON task graph, the main agent MUST treat it as a **BINDING CONTRACT**.

### CRITICAL RULES - NO EXCEPTIONS

1. **PARSE JSON EXECUTION PLAN IMMEDIATELY**
   - Extract JSON from "Execution Plan JSON" code fence
   - Write to `.claude/state/active_task_graph.json`
   - This JSON is a **BINDING CONTRACT** you MUST follow exactly

2. **PROHIBITED ACTIONS**
   - ❌ PROHIBITED: Simplifying the execution plan
   - ❌ PROHIBITED: Collapsing parallel waves to sequential
   - ❌ PROHIBITED: Changing agent assignments
   - ❌ PROHIBITED: Reordering phases
   - ❌ PROHIBITED: Skipping phases
   - ❌ PROHIBITED: Adding phases not in plan
   - ❌ PROHIBITED: Deciding "this is simple enough to do in one step"
   - ❌ PROHIBITED: Summarizing or condensing the orchestrator's breakdown

3. **EXACT WAVE EXECUTION REQUIRED**
   - Execute Wave 0 before Wave 1, Wave 1 before Wave 2
   - For parallel waves (`wave.parallel_execution == true`):
     - Spawn ALL phase Tasks in SINGLE message (concurrent execution)
     - Do NOT wait between individual spawns
   - For sequential waves:
     - Execute phases in order, waiting for completion

4. **PHASE ID MARKERS MANDATORY**
   - EVERY Task invocation MUST include phase ID in prompt:
     ```
     Phase ID: phase_0_0
     Agent: [agent-name]

     [Task description...]
     ```

5. **ESCAPE HATCH (Legitimate Exceptions Only)**
   - If execution plan appears genuinely impractical:
     1. Do NOT simplify
     2. Use `/ask` to notify user of concern
     3. Wait for user decision to override or proceed
   - Legitimate concerns:
     - Orchestrator assigned non-existent agent
     - Phase dependencies form circular loop
     - Resource constraints make parallel execution unsafe
   - NOT legitimate: "Plan seems complex" or "Sequential feels safer"

### Why This Matters

The orchestrator has analyzed task dependencies, selected specialized agents, and planned optimal execution order. Overriding this analysis:
- Loses the benefit of specialized agent expertise
- Breaks dependency management
- Defeats the purpose of the delegation system

**Trust the orchestrator. Execute the plan exactly as specified.**
