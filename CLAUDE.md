# Python Coding Standards

This document defines the coding standards enforced by the PostToolUse hook (`hooks/PostToolUse/python_posttooluse_hook.sh`) for this project.

## Python Version

**Required:** Python 3.12+

All code must use modern Python 3.12+ syntax and features.

## Type Annotations

### Modern Type Hint Syntax (Required)

Use Python 3.10+ union syntax and built-in generics:

**✅ Correct:**
```python
def process(items: list[str]) -> dict[str, int]:
    """Process items and return counts."""
    return {item: len(item) for item in items}

def get_value(key: str) -> str | None:
    """Get value or None if not found."""
    return data.get(key)
```

**❌ Incorrect:**
```python
from typing import List, Dict, Optional, Union

def process(items: List[str]) -> Dict[str, int]:  # Don't use typing.List
    return {item: len(item) for item in items}

def get_value(key: str) -> Optional[str]:  # Use str | None instead
    return data.get(key)
```

### Enforced Rules

- **UP006:** Use `list[T]` instead of `List[T]`
- **UP007:** Use `X | Y` instead of `Union[X, Y]` or `Optional[X]`
- **UP035:** Import replacements for deprecated typing features
- **UP037:** Remove quotes from type annotations (use `from __future__ import annotations` if needed)

## Logging Standards

### No Print Statements in Production Code

Use the `logging` module for all output.

**✅ Correct:**
```python
import logging

logger = logging.getLogger(__name__)

def process_data(data: dict) -> None:
    logger.info("Processing data with %d items", len(data))
    logger.debug("Data contents: %s", data)
```

**❌ Incorrect:**
```python
def process_data(data: dict) -> None:
    print(f"Processing data with {len(data)} items")  # Blocked by T201
```

### Exceptions

Print statements are allowed in:
- Test files (`test_*.py`, `**/tests/**/*.py`)
- CLI entry points (`cli.py`, `main.py`, `__main__.py`)

## Code Quality Standards

### Import Management

- **F401:** Remove unused imports
- **F811:** No redefined imports
- **I001:** Sort imports (use `isort` or `ruff format`)

### Error Handling

- **BLE001:** Don't use bare `except Exception:` - catch specific exceptions
- **TRY002:** Use `raise ... from ...` to preserve exception context
- **TRY400:** Include `exc_info=True` when logging errors

**✅ Correct:**
```python
try:
    result = dangerous_operation()
except ValueError as e:
    logger.error("Operation failed", exc_info=True)
    raise ProcessingError("Failed to process") from e
```

**❌ Incorrect:**
```python
try:
    result = dangerous_operation()
except Exception:  # Too broad
    logger.error("Operation failed")  # Missing exc_info
    raise ProcessingError("Failed")  # Missing 'from e'
```

## Security Standards

### Critical Security Violations (Blocking)

The following patterns are **blocked** by the PostToolUse hook:

- **S102:** `exec()` usage
- **S307:** `eval()` usage
- **S105-S107:** Hardcoded passwords/secrets
- **S301-S302:** `pickle`/`marshal` usage (unsafe serialization)
- **S311:** Using `random` module for security purposes (use `secrets`)
- **S501:** `requests.get(verify=False)` - insecure TLS
- **S506:** `yaml.load()` without `Loader=` (use `safe_load`)

**✅ Correct:**
```python
import secrets
import yaml

# Generate secure random token
token = secrets.token_urlsafe(32)

# Load YAML safely
with open("config.yml") as f:
    config = yaml.safe_load(f)
```

**❌ Incorrect:**
```python
import random
import yaml

# Insecure random for security
token = ''.join(random.choices(string.ascii_letters, k=32))  # S311

# Unsafe YAML loading
with open("config.yml") as f:
    config = yaml.load(f)  # S506 - missing Loader
```

### SQL Injection Prevention

Never concatenate SQL queries with string formatting:

**✅ Correct:**
```python
cursor.execute("SELECT * FROM users WHERE id = ?", (user_id,))
```

**❌ Incorrect:**
```python
cursor.execute(f"SELECT * FROM users WHERE id = {user_id}")  # SQL injection
cursor.execute("SELECT * FROM users WHERE id = " + user_id)  # SQL injection
```

### Command Injection Prevention

Use subprocess with list arguments, never shell=True with user input:

**✅ Correct:**
```python
subprocess.run(["git", "commit", "-m", message], check=True)
```

**❌ Incorrect:**
```python
os.system(f"git commit -m {message}")  # Command injection
subprocess.run(f"git commit -m {message}", shell=True)  # Command injection
```

## Performance Standards

- **PERF102:** Use comprehensions efficiently (avoid unnecessary calls)
- **PERF401:** Use list comprehensions instead of manual loops when appropriate

## Hook Enforcement

All standards above are enforced by `hooks/PostToolUse/python_posttooluse_hook.sh` which runs:

1. **Critical Security Check:** Fast pattern matching for immediate vulnerabilities
2. **Ruff Validation:** Enforces syntax, security, and quality rules
3. **Pyright Type Checking:** Validates type annotations (basic mode)

Operations that violate these standards will be **blocked** with detailed error messages.

## Running Validation Manually

Test your code against these standards:

```bash
# Full validation
./hooks/PostToolUse/python_posttooluse_hook.sh your_file.py

# Skip specific checks
CHECK_RUFF=0 ./hooks/PostToolUse/python_posttooluse_hook.sh your_file.py
CHECK_PYRIGHT=0 ./hooks/PostToolUse/python_posttooluse_hook.sh your_file.py
```

## Automatic Deliverable Verification

This project uses automatic verification for multi-step workflows to ensure implementation quality.

### How It Works

1. **Deliverable Manifests:** The delegation orchestrator generates structured deliverable manifests for each implementation phase, specifying expected files, functions, tests, and acceptance criteria.

2. **Auto-Inserted Verification Phases:** After each implementation phase, the orchestrator automatically inserts a verification phase using the task-completion-verifier agent.

3. **Manifest-Driven Validation:** The verifier performs structured checks:
   - File existence and content validation
   - Function/class presence verification
   - Type hint validation (Python)
   - Test execution and coverage analysis
   - Acceptance criteria validation

4. **Verdict Processing:**
   - **PASS:** Workflow proceeds to next phase
   - **FAIL:** Re-implementation with remediation steps
   - **PASS_WITH_MINOR_ISSUES:** Proceed with warnings tracked

### Wave Structure

Verification phases are automatically scheduled in the wave after implementation:

```
Wave 0: Implementation phases (can be parallel)
Wave 1: Verification phases (sequential after Wave 0)
Wave 2: Next implementation phases
Wave 3: Verification phases
```

### Deliverable Manifest Example

```json
{
  "phase_id": "phase_1_1",
  "phase_objective": "Create calculator.py with add and subtract functions",
  "deliverable_manifest": {
    "files": [{
      "path": "calculator.py",
      "must_exist": true,
      "functions": ["add", "subtract"],
      "type_hints_required": true
    }],
    "tests": [{
      "test_command": "pytest test_calculator.py",
      "all_tests_must_pass": true,
      "min_coverage": 0.8
    }],
    "acceptance_criteria": [
      "Functions support int and float inputs",
      "Error handling for invalid inputs"
    ]
  }
}
```

For complete workflow orchestration documentation, see `system-prompts/WORKFLOW_ORCHESTRATOR.md`.

---

## Reference

For complete project documentation, usage, and architecture, see [README.md](README.md).
