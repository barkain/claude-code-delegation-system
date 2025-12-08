#!/usr/bin/env bash
set -euo pipefail

# Get agent info from environment
AGENT_TYPE="${AGENT_TYPE:-unknown}"
AGENT_STATUS="${AGENT_STATUS:-completed}"

# Only trigger on successful completion
[[ "$AGENT_STATUS" != "completed" ]] && exit 0

# Skip for specific agents to avoid recursion
[[ "$AGENT_TYPE" == "task-completion-verifier" ]] && exit 0
[[ "$AGENT_TYPE" == "delegation-orchestrator" ]] && exit 0

# Output brief verification instruction
echo "🔍 Spawn task-completion-verifier to verify the work completed by $AGENT_TYPE"

exit 0
