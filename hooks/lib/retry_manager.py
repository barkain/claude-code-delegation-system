#!/usr/bin/env python3
"""
Retry Budget Manager

Manages retry state, exponential backoff calculations, and budget enforcement
for failed delegation phases. Provides atomic file operations with locking
to support concurrent access from parallel workflows.

Schema: .claude/schemas/retry_budgets.schema.json
State file: .claude/state/retry_budgets.json
"""

import fcntl
import json
import logging
import math
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class RetryManager:
    """Manages retry budgets and exponential backoff for delegation phases."""

    DEFAULT_MAX_ATTEMPTS = 5
    DEFAULT_BACKOFF_BASE = 1.0  # seconds
    DEFAULT_BACKOFF_MAX = 16.0  # seconds
    DEFAULT_BACKOFF_STRATEGY = "exponential"

    def __init__(self, state_file: Optional[Path] = None):
        """
        Initialize retry manager.

        Args:
            state_file: Path to retry_budgets.json (default: .claude/state/retry_budgets.json)
        """
        if state_file is None:
            # Use CLAUDE_PROJECT_DIR or current directory
            project_dir = Path(os.environ.get('CLAUDE_PROJECT_DIR', os.getcwd()))
            state_dir = project_dir / '.claude' / 'state'
            state_dir.mkdir(parents=True, exist_ok=True)
            state_file = state_dir / 'retry_budgets.json'

        self.state_file = Path(state_file)
        self._ensure_state_file()

    def _ensure_state_file(self):
        """Create state file with initial structure if it doesn't exist."""
        if not self.state_file.exists():
            initial_state = {
                "version": "1.0",
                "retries": {}
            }
            self._write_state(initial_state)

    def _read_state(self) -> dict:
        """
        Read state file with file locking.

        Returns:
            State dictionary
        """
        with open(self.state_file, 'r') as f:
            # Acquire shared lock for reading
            fcntl.flock(f.fileno(), fcntl.LOCK_SH)
            try:
                state = json.load(f)
            finally:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)
        return state

    def _write_state(self, state: dict):
        """
        Write state file atomically with file locking.

        Args:
            state: State dictionary to write
        """
        # Write to temp file first
        temp_file = self.state_file.with_suffix('.tmp')
        with open(temp_file, 'w') as f:
            # Acquire exclusive lock for writing
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            try:
                json.dump(state, f, indent=2)
                f.flush()
                os.fsync(f.fileno())
            finally:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)

        # Atomic rename
        temp_file.replace(self.state_file)

    def init_retry(
        self,
        phase_id: str,
        workflow_id: str,
        agent: str,
        max_attempts: Optional[int] = None,
        backoff_strategy: Optional[str] = None,
        backoff_base: Optional[float] = None,
        backoff_max: Optional[float] = None
    ) -> dict:
        """
        Initialize retry state for a new phase.

        Args:
            phase_id: Unique phase identifier
            workflow_id: Workflow identifier
            agent: Agent name
            max_attempts: Maximum retry attempts (default: 5)
            backoff_strategy: 'exponential', 'linear', or 'constant' (default: exponential)
            backoff_base: Base delay in seconds (default: 1.0)
            backoff_max: Max delay in seconds (default: 16.0)

        Returns:
            Initialized retry state
        """
        state = self._read_state()

        retry_state = {
            "phase_id": phase_id,
            "workflow_id": workflow_id,
            "agent": agent,
            "attempt_count": 1,
            "max_attempts": max_attempts or self.DEFAULT_MAX_ATTEMPTS,
            "backoff_strategy": backoff_strategy or self.DEFAULT_BACKOFF_STRATEGY,
            "backoff_base_seconds": backoff_base or self.DEFAULT_BACKOFF_BASE,
            "backoff_max_seconds": backoff_max or self.DEFAULT_BACKOFF_MAX,
            "error_history": [],
            "budget_exhausted": False
        }

        state['retries'][phase_id] = retry_state
        self._write_state(state)

        return retry_state

    def record_failure(
        self,
        phase_id: str,
        error_message: str,
        error_type: str = "unknown",
        exit_code: Optional[int] = None,
        duration_ms: Optional[int] = None,
        stack_trace: Optional[str] = None,
        context: Optional[dict] = None
    ) -> dict:
        """
        Record a failure for a phase and update retry state.

        Args:
            phase_id: Phase identifier
            error_message: Error message text
            error_type: 'transient', 'permanent', or 'unknown'
            exit_code: Process exit code if available
            duration_ms: Duration of failed attempt in milliseconds
            stack_trace: Stack trace if available
            context: Additional error context (cwd, environment, git_status)

        Returns:
            Updated retry state
        """
        state = self._read_state()

        if phase_id not in state['retries']:
            raise ValueError(f"Phase {phase_id} not initialized. Call init_retry() first.")

        retry_state = state['retries'][phase_id]
        now = datetime.utcnow()

        # Create error event
        error_event = {
            "timestamp": now.isoformat() + "Z",
            "attempt_number": retry_state['attempt_count'],
            "error_type": error_type,
            "error_message": error_message
        }

        if exit_code is not None:
            error_event['exit_code'] = exit_code
        if duration_ms is not None:
            error_event['duration_ms'] = duration_ms
        if stack_trace:
            error_event['stack_trace'] = stack_trace
        if context:
            error_event['context'] = context

        # Update retry state
        retry_state['error_history'].append(error_event)
        retry_state['last_failure_at'] = error_event['timestamp']

        if 'first_failure_at' not in retry_state:
            retry_state['first_failure_at'] = error_event['timestamp']

        # Increment attempt count
        retry_state['attempt_count'] += 1

        # Calculate next retry time
        if retry_state['attempt_count'] <= retry_state['max_attempts']:
            backoff_delay = self._calculate_backoff(retry_state)
            next_retry = now + timedelta(seconds=backoff_delay)
            retry_state['next_retry_at'] = next_retry.isoformat() + "Z"
        else:
            # Budget exhausted
            retry_state['budget_exhausted'] = True
            retry_state['next_retry_at'] = None

        # Save updated state
        state['retries'][phase_id] = retry_state
        self._write_state(state)

        return retry_state

    def can_retry(self, phase_id: str) -> tuple[bool, Optional[float]]:
        """
        Check if phase can be retried.

        Args:
            phase_id: Phase identifier

        Returns:
            Tuple of (can_retry: bool, wait_seconds: float or None)
            If can_retry is False, wait_seconds indicates how long to wait
            If budget exhausted, returns (False, None)
        """
        state = self._read_state()

        if phase_id not in state['retries']:
            # Not initialized - can proceed
            return True, 0.0

        retry_state = state['retries'][phase_id]

        # Check if budget exhausted
        if retry_state['budget_exhausted']:
            return False, None

        # Check if we've exceeded max attempts
        if retry_state['attempt_count'] > retry_state['max_attempts']:
            return False, None

        # Check if we need to wait for backoff
        if 'next_retry_at' in retry_state and retry_state['next_retry_at']:
            next_retry = datetime.fromisoformat(retry_state['next_retry_at'].replace('Z', '+00:00'))
            now = datetime.utcnow()

            if now < next_retry:
                wait_seconds = (next_retry - now).total_seconds()
                return False, wait_seconds

        # Can retry now
        return True, 0.0

    def get_backoff_delay(self, phase_id: str) -> float:
        """
        Get the backoff delay for the current retry attempt.

        Args:
            phase_id: Phase identifier

        Returns:
            Backoff delay in seconds
        """
        state = self._read_state()

        if phase_id not in state['retries']:
            return 0.0

        retry_state = state['retries'][phase_id]
        return self._calculate_backoff(retry_state)

    def _calculate_backoff(self, retry_state: dict) -> float:
        """
        Calculate backoff delay based on strategy and attempt count.

        Args:
            retry_state: Retry state dictionary

        Returns:
            Backoff delay in seconds
        """
        attempt = retry_state['attempt_count'] - 1  # 0-indexed for calculation
        base = retry_state['backoff_base_seconds']
        max_delay = retry_state['backoff_max_seconds']
        strategy = retry_state['backoff_strategy']

        if strategy == "exponential":
            # Exponential: base * 2^attempt (capped at max)
            delay = base * math.pow(2, attempt)
            return min(delay, max_delay)

        elif strategy == "linear":
            # Linear: base * attempt (capped at max)
            delay = base * (attempt + 1)
            return min(delay, max_delay)

        elif strategy == "constant":
            # Constant: always base delay
            return base

        else:
            # Unknown strategy - default to exponential
            delay = base * math.pow(2, attempt)
            return min(delay, max_delay)

    def reset_budget(self, phase_id: str):
        """
        Reset retry budget for a phase (clear error history, reset counters).

        Args:
            phase_id: Phase identifier
        """
        state = self._read_state()

        if phase_id in state['retries']:
            del state['retries'][phase_id]
            self._write_state(state)

    def get_retry_state(self, phase_id: str) -> Optional[dict]:
        """
        Get retry state for a phase.

        Args:
            phase_id: Phase identifier

        Returns:
            Retry state dictionary or None if not found
        """
        state = self._read_state()
        return state['retries'].get(phase_id)

    def cleanup_old_retries(self, max_age_hours: int = 24):
        """
        Remove retry state for phases older than max_age_hours.

        Args:
            max_age_hours: Maximum age in hours (default: 24)
        """
        state = self._read_state()
        now = datetime.utcnow()
        cutoff = now - timedelta(hours=max_age_hours)

        to_remove = []
        for phase_id, retry_state in state['retries'].items():
            if 'last_failure_at' in retry_state:
                last_failure = datetime.fromisoformat(
                    retry_state['last_failure_at'].replace('Z', '+00:00')
                )
                if last_failure < cutoff:
                    to_remove.append(phase_id)

        for phase_id in to_remove:
            del state['retries'][phase_id]

        if to_remove:
            self._write_state(state)


def main():
    """CLI interface for retry manager (for testing/debugging)."""
    import argparse

    parser = argparse.ArgumentParser(description='Retry Budget Manager')
    parser.add_argument('command', choices=[
        'init', 'record-failure', 'can-retry', 'get-backoff', 'reset', 'get-state', 'cleanup'
    ])
    parser.add_argument('--phase-id', required=True)
    parser.add_argument('--workflow-id')
    parser.add_argument('--agent')
    parser.add_argument('--error-message')
    parser.add_argument('--error-type', choices=['transient', 'permanent', 'unknown'], default='unknown')
    parser.add_argument('--exit-code', type=int)
    parser.add_argument('--max-attempts', type=int, default=RetryManager.DEFAULT_MAX_ATTEMPTS)
    parser.add_argument('--state-file', type=Path)

    args = parser.parse_args()

    manager = RetryManager(state_file=args.state_file)

    if args.command == 'init':
        if not args.workflow_id or not args.agent:
            sys.stderr.write("Error: --workflow-id and --agent required for init\n")
            sys.exit(1)

        state = manager.init_retry(
            phase_id=args.phase_id,
            workflow_id=args.workflow_id,
            agent=args.agent,
            max_attempts=args.max_attempts
        )
        sys.stdout.write(json.dumps(state, indent=2) + "\n")

    elif args.command == 'record-failure':
        if not args.error_message:
            sys.stderr.write("Error: --error-message required for record-failure\n")
            sys.exit(1)

        state = manager.record_failure(
            phase_id=args.phase_id,
            error_message=args.error_message,
            error_type=args.error_type,
            exit_code=args.exit_code
        )
        sys.stdout.write(json.dumps(state, indent=2) + "\n")

    elif args.command == 'can-retry':
        can_retry, wait_seconds = manager.can_retry(args.phase_id)
        result = {
            "can_retry": can_retry,
            "wait_seconds": wait_seconds
        }
        sys.stdout.write(json.dumps(result, indent=2) + "\n")
        sys.exit(0 if can_retry else 1)

    elif args.command == 'get-backoff':
        delay = manager.get_backoff_delay(args.phase_id)
        sys.stdout.write(f"{delay:.2f}\n")

    elif args.command == 'reset':
        manager.reset_budget(args.phase_id)
        sys.stdout.write(f"Reset budget for phase {args.phase_id}\n")

    elif args.command == 'get-state':
        state = manager.get_retry_state(args.phase_id)
        if state:
            sys.stdout.write(json.dumps(state, indent=2) + "\n")
        else:
            sys.stderr.write(f"No retry state found for phase {args.phase_id}\n")
            sys.exit(1)

    elif args.command == 'cleanup':
        manager.cleanup_old_retries()
        sys.stdout.write("Cleaned up old retry states\n")


if __name__ == '__main__':
    main()
