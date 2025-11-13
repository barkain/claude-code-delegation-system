#!/usr/bin/env bash
  # ~/.claude/hooks/SubagentStop/remind_todo_update.sh
  # Triggers when a subagent completes execution

  set -euo pipefail

  # Get subagent info from environment
  SUBAGENT_TYPE="${SUBAGENT_TYPE:-unknown}"
  SUBAGENT_STATUS="${SUBAGENT_STATUS:-completed}"

  # Only remind on successful completion
  if [[ "$SUBAGENT_STATUS" == "completed" ]]; then
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "📋 REMINDER: Update TodoWrite task list"
      echo "   Subagent ($SUBAGENT_TYPE) completed successfully"
      echo "   Mark current task as 'completed'"
      echo "   Update next task to 'in_progress' (if multi-step)"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
  fi

  exit 0
  