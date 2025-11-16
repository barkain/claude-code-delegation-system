#!/usr/bin/env python3
"""
Execution Log Writer

Manages structured JSONL logging for delegation workflow execution.
Provides append-only writes with atomic operations, log rotation, and retention policies.

Schema: .claude/schemas/execution_log.schema.json
Log files: .claude/logs/execution_{workflow_id}.jsonl
"""

import fcntl
import gzip
import json
import logging
import os
import shutil
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Optional

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class LogWriter:
    """Manages structured JSONL execution logs with rotation and retention."""

    DEFAULT_MAX_SIZE_MB = 10
    DEFAULT_RETENTION_DAYS = 30
    ROTATION_SUFFIX = ".{timestamp}.jsonl.gz"

    def __init__(
        self,
        workflow_id: str,
        log_dir: Optional[Path] = None,
        max_size_mb: int = DEFAULT_MAX_SIZE_MB,
        retention_days: int = DEFAULT_RETENTION_DAYS
    ):
        """
        Initialize log writer.

        Args:
            workflow_id: Workflow identifier
            log_dir: Directory for log files (default: .claude/logs)
            max_size_mb: Max log file size before rotation (default: 10MB)
            retention_days: Days to retain old logs (default: 30)
        """
        if log_dir is None:
            project_dir = Path(os.environ.get('CLAUDE_PROJECT_DIR', os.getcwd()))
            log_dir = project_dir / '.claude' / 'logs'

        self.log_dir = Path(log_dir)
        self.log_dir.mkdir(parents=True, exist_ok=True)

        self.workflow_id = workflow_id
        self.log_file = self.log_dir / f"execution_{workflow_id}.jsonl"
        self.max_size_bytes = max_size_mb * 1024 * 1024
        self.retention_days = retention_days

    def write_event(
        self,
        event_type: str,
        status: str,
        phase_id: Optional[str] = None,
        agent: Optional[str] = None,
        duration_ms: Optional[int] = None,
        error: Optional[dict[str, Any]] = None,
        context: Optional[dict[str, Any]] = None,
        **kwargs: Any
    ) -> dict[str, Any]:
        """
        Write a log event.

        Args:
            event_type: Type of event (workflow_start, phase_start, etc.)
            status: Event status (started, completed, failed, etc.)
            phase_id: Phase identifier (optional)
            agent: Agent name (optional)
            duration_ms: Duration in milliseconds (optional)
            error: Error details if status is failed (optional)
            context: Additional context (optional)
            **kwargs: Additional fields to include in log entry

        Returns:
            Log entry dictionary
        """
        # Build log entry
        entry: dict[str, Any] = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "event_type": event_type,
            "workflow_id": self.workflow_id,
            "status": status
        }

        # Add optional fields
        if phase_id:
            entry["phase_id"] = phase_id
        if agent:
            entry["agent"] = agent
        if duration_ms is not None:
            entry["duration_ms"] = duration_ms
        if error:
            entry["error"] = error
        if context:
            entry["context"] = context

        # Add any additional kwargs
        entry.update(kwargs)

        # Write to file
        self._append_entry(entry)

        # Check if rotation needed
        self._check_rotation()

        return entry

    def _append_entry(self, entry: dict):
        """
        Append entry to log file atomically.

        Args:
            entry: Log entry dictionary
        """
        # Serialize entry
        line = json.dumps(entry, separators=(',', ':')) + '\n'

        # Write with file locking
        with open(self.log_file, 'a') as f:
            # Acquire exclusive lock
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            try:
                f.write(line)
                f.flush()
                os.fsync(f.fileno())
            finally:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)

    def _check_rotation(self):
        """Check if log file needs rotation and rotate if necessary."""
        if not self.log_file.exists():
            return

        # Check file size
        size = self.log_file.stat().st_size
        if size >= self.max_size_bytes:
            self._rotate_log()

    def _rotate_log(self):
        """Rotate current log file by compressing and renaming."""
        if not self.log_file.exists():
            return

        # Generate rotated filename with timestamp
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        rotated_name = f"execution_{self.workflow_id}.{timestamp}.jsonl.gz"
        rotated_path = self.log_dir / rotated_name

        # Compress and write to rotated file
        with open(self.log_file, 'rb') as f_in:
            with gzip.open(rotated_path, 'wb') as f_out:
                shutil.copyfileobj(f_in, f_out)

        # Remove original file
        self.log_file.unlink()

        logger.info(f"Rotated log file: {rotated_path}")

    def cleanup_old_logs(self):
        """Remove logs older than retention period."""
        cutoff = datetime.utcnow() - timedelta(days=self.retention_days)

        for log_file in self.log_dir.glob('execution_*.jsonl*'):
            # Get modification time
            mtime = datetime.fromtimestamp(log_file.stat().st_mtime)

            if mtime < cutoff:
                log_file.unlink()
                logger.info(f"Deleted old log file: {log_file}")

    def read_events(
        self,
        event_type: Optional[str] = None,
        phase_id: Optional[str] = None,
        status: Optional[str] = None,
        limit: Optional[int] = None
    ) -> list[dict]:
        """
        Read events from log file with optional filtering.

        Args:
            event_type: Filter by event type (optional)
            phase_id: Filter by phase ID (optional)
            status: Filter by status (optional)
            limit: Maximum number of events to return (optional)

        Returns:
            List of log entry dictionaries
        """
        if not self.log_file.exists():
            return []

        events = []
        with open(self.log_file, 'r') as f:
            for line in f:
                try:
                    entry = json.loads(line.strip())

                    # Apply filters
                    if event_type and entry.get('event_type') != event_type:
                        continue
                    if phase_id and entry.get('phase_id') != phase_id:
                        continue
                    if status and entry.get('status') != status:
                        continue

                    events.append(entry)

                    # Check limit
                    if limit and len(events) >= limit:
                        break

                except json.JSONDecodeError:
                    logger.warning(f"Skipped invalid JSON line in {self.log_file}")
                    continue

        return events

    def get_workflow_stats(self) -> dict:
        """
        Get statistics for the workflow.

        Returns:
            Statistics dictionary
        """
        events = self.read_events()

        stats = {
            "total_events": len(events),
            "event_types": {},
            "phases": {},
            "errors": 0,
            "retries": 0
        }

        for event in events:
            # Count event types
            event_type = event.get('event_type', 'unknown')
            stats['event_types'][event_type] = stats['event_types'].get(event_type, 0) + 1

            # Count phases
            if 'phase_id' in event:
                phase_id = event['phase_id']
                if phase_id not in stats['phases']:
                    stats['phases'][phase_id] = {
                        "events": 0,
                        "status": event.get('status'),
                        "agent": event.get('agent')
                    }
                stats['phases'][phase_id]['events'] += 1

            # Count errors and retries
            if event.get('status') == 'failed':
                stats['errors'] += 1
            if event.get('event_type') == 'retry':
                stats['retries'] += 1

        return stats


def main():
    """CLI interface for log writer (for testing/debugging)."""
    import argparse
    import sys

    parser = argparse.ArgumentParser(description='Execution Log Writer')
    parser.add_argument('command', choices=['write', 'read', 'stats', 'cleanup', 'rotate'])
    parser.add_argument('--workflow-id', required=True)
    parser.add_argument('--event-type')
    parser.add_argument('--status')
    parser.add_argument('--phase-id')
    parser.add_argument('--agent')
    parser.add_argument('--duration-ms', type=int)
    parser.add_argument('--error-message')
    parser.add_argument('--log-dir', type=Path)
    parser.add_argument('--limit', type=int)

    args = parser.parse_args()

    writer = LogWriter(
        workflow_id=args.workflow_id,
        log_dir=args.log_dir
    )

    if args.command == 'write':
        if not args.event_type or not args.status:
            sys.stderr.write("Error: --event-type and --status required for write\n")
            sys.exit(1)

        error = None
        if args.error_message:
            error = {"message": args.error_message}

        entry = writer.write_event(
            event_type=args.event_type,
            status=args.status,
            phase_id=args.phase_id,
            agent=args.agent,
            duration_ms=args.duration_ms,
            error=error
        )
        sys.stdout.write(json.dumps(entry, indent=2) + "\n")

    elif args.command == 'read':
        events = writer.read_events(
            event_type=args.event_type,
            phase_id=args.phase_id,
            status=args.status,
            limit=args.limit
        )
        sys.stdout.write(json.dumps(events, indent=2) + "\n")

    elif args.command == 'stats':
        stats = writer.get_workflow_stats()
        sys.stdout.write(json.dumps(stats, indent=2) + "\n")

    elif args.command == 'cleanup':
        writer.cleanup_old_logs()
        sys.stdout.write("Cleaned up old log files\n")

    elif args.command == 'rotate':
        writer._rotate_log()
        sys.stdout.write(f"Rotated log for workflow {args.workflow_id}\n")


if __name__ == '__main__':
    main()
