# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## CRITICAL: Delegation Policy

**MANDATORY IMMEDIATE DELEGATION ON TOOL BLOCK**

When ANY tool is blocked by the delegation policy hook:

1. **DO NOT try alternative approaches** (different tools, workarounds, etc.)
2. **DO NOT explain what you tried** - just delegate immediately
3. **IMMEDIATELY use `/delegate <task>`** on first tool block
4. **The entire user request must be delegated**, not just the blocked tool

**Example - WRONG:**
```
❌ Read blocked → Try Glob → Glob blocked → Try Grep → Grep blocked → Finally delegate
```

**Example - CORRECT:**
```
✅ Read blocked → Immediately use: /delegate <full task description>
```

**Recognition Pattern:**
```
Error: PreToolUse:* hook error: [...] 🚫 Tool blocked by delegation policy
```

When you see this error pattern, **stop immediately** and delegate the entire task.

## Commands

### Development Setup
I prefer to use uv for everything (uv add, uv run, etc)
Do not use old fashioned methods for package management like poetry, pip or easy_install.
Make sure that there is a pyproject.toml file in the root directory.
```bash
# Install dependencies (includes dev, test, examples groups)
uv sync --all-groups
source .venv/bin/activate
```

```bash
# Add internal package as direct dependency
uv add --editable <package_location>

# Add internal package as dev dependency
uv add --group dev --editable <package_location>
```

### Testing
```bash
# Run all tests
uv run pytest

# Run with coverage
uv run pytest --cov=my_project --cov-report=html

# Run specific test file (structured by domain)
uv run pytest tests/core/test_crypto.py -v                    # Core encryption tests
uv run pytest tests/infrastructure/test_config.py -v         # Configuration tests  
uv run pytest tests/processing/test_phi_registry.py -v       # PHI detection tests
uv run pytest tests/interface/test_cli.py -v                 # CLI interface tests

# Run async tests
uv run pytest tests/core/test_async_crypto.py -v
```

### Code Quality
```bash
# Format and lint
uv run ruff check src/ tests/ examples/
uv run ruff format src/ tests/ examples/

# Type checking
uv run pyright src/
```

### Git Commit Guidelines
- DO NOT add Claude Code attribution lines to commit messages
- Avoid: "🤖 Generated with [Claude Code]" and "Co-Authored-By: Claude" lines
- Write clean, professional commit messages focused on the actual changes
- Make sure to run linting and formatting checks before staging the files and committing the changes

### Logging Guidelines
- **NEVER use `print()` statements** for logging in production code or examples
- Always use `logger` calls instead: `logger.info()`, `logger.warning()`, `logger.error()`, etc.
- **Acceptable use of `print()`**:
  - CLI user interface output (direct user interaction)
  - Docstring examples for demonstration
  - Specific demonstration purposes (clearly documented)
- All example files should demonstrate proper logging patterns using loguru
- Use appropriate log levels: DEBUG, INFO, WARNING, ERROR, CRITICAL

### Documentation Guidelines
- README files that describe modules or sub-modules should not contain contribution sections or any sections aimed at public audiences
- These are always company internal modules, so documentation should focus on:
  - Technical implementation details
  - Usage instructions for internal teams
  - Architecture and design decisions
  - Development and testing procedures
- Avoid sections like "Contributing", "License", "Community", or other open-source conventions

### Python Version Compliance
- Always check the project's Python version requirements (pyproject.toml, setup.py, etc.)
- Use modern Python syntax features appropriate for the specified version
- For Python 3.9+: Use `list[str]` instead of `typing.List[str]`, `dict[str, int]` instead of `typing.Dict[str, int]`
- For Python 3.10+: Use `str | None` instead of `typing.Union[str, None]`, `str | int` instead of `typing.Union[str, int]`
- For Python 3.12+: Use all available modern syntax features rather than legacy compatibility patterns
- Avoid using older typing module syntax when built-in generics and union operators are available

## Python Coding Conventions

### Modern Python Syntax (3.12+)

#### Type Hints - Use Built-in Generics (PEP 585, PEP 604, PEP 695)
```python
# ✅ Correct - Modern syntax
def process_items(items: list[str]) -> dict[str, int]:
    return {item: len(item) for item in items}

def handle_optional(value: str | None) -> bool:
    return value is not None

def multi_type_param(data: str | int | float) -> str:
    return str(data)

# ❌ Avoid - Legacy typing imports
from typing import List, Dict, Union, Optional
def process_items(items: List[str]) -> Dict[str, int]:
    return {item: len(item) for item in items}
```

#### Generic Type Aliases (Python 3.12+)
```python
# ✅ Modern generic syntax
type DatabaseRecord[T] = dict[str, T]
type ProcessingResult[T] = tuple[bool, T | None, str]

# ✅ Function generics
def safe_get[T](items: list[T], index: int) -> T | None:
    return items[index] if 0 <= index < len(items) else None
```

### Structured Logging Standards (PEP 282)

#### Always Use Logger with Context
```python
import logging

# ✅ Correct - Use logger with structured context
logger = logging.getLogger(__name__)

def process_patient_data(patient_id: str, practice_id: str) -> None:
    logger.info("Processing patient data", extra={
        'patient_id': patient_id,
        'practice_id': practice_id,
        'operation': 'fhir_processing'
    })
    
    try:
        result = parse_fhir_data(patient_id)
        logger.info("FHIR processing completed successfully")
    except ValidationError as e:
        logger.error("FHIR validation failed", extra={
            'error': str(e),
            'patient_id': patient_id
        })
        raise
    except Exception as e:
        logger.critical("Unexpected processing error", extra={
            'error': str(e),
            'patient_id': patient_id
        })
        raise

# ❌ Never use print() in production code
def bad_example():
    print("This should be a log message")  # DON'T DO THIS
```

#### Log Levels Usage
```python
# ✅ Appropriate log level usage
logger.debug("Detailed diagnostic info for developers")
logger.info("General operational information")
logger.warning("Something unexpected but recoverable happened")
logger.error("Serious problem occurred, but app continues")
logger.critical("Very serious error, app may not continue")
```

### Error Handling (PEP 8, PEP 282)

#### Structured Exception Handling
```python
# ✅ Correct - Specific exceptions with context
def process_medical_data(data: dict[str, any]) -> dict[str, any]:
    try:
        validated_data = validate_fhir_data(data)
        processed_result = apply_clinical_rules(validated_data)
        return processed_result
        
    except ValidationError as e:
        logger.error("Data validation failed", extra={
            'validation_error': str(e),
            'data_keys': list(data.keys())
        })
        raise ProcessingError(f"Invalid medical data: {e}") from e
        
    except APITimeoutError as e:
        logger.warning("External API timeout", extra={
            'timeout_duration': e.duration,
            'api_endpoint': e.endpoint
        })
        raise
        
    except Exception as e:
        logger.critical("Unexpected error in medical data processing", extra={
            'error_type': type(e).__name__,
            'error_message': str(e)
        })
        raise

# ❌ Avoid bare except clauses
def bad_error_handling():
    try:
        risky_operation()
    except:  # DON'T DO THIS
        pass
```

### Multi-Tenant Architecture

#### Database Context Switching
```python
# ✅ Clear practice isolation
def with_practice_context[T](practice_id: str, operation: callable[[], T]) -> T:
    """Execute operation in practice-specific database context."""
    original_context = get_current_db_context()
    
    try:
        logger.debug("Switching database context", extra={
            'practice_id': practice_id,
            'operation': operation.__name__
        })
        
        switch_database_context(practice_id)
        result = operation()
        
        logger.debug("Operation completed in practice context", extra={
            'practice_id': practice_id,
            'operation': operation.__name__
        })
        
        return result
        
    finally:
        switch_database_context(original_context)

# ✅ Practice-specific message channels
def get_notification_channel(practice_id: str, channel_type: str) -> str:
    return f"practice:{practice_id}:{channel_type}"

def publish_patient_update(
    practice_id: str, 
    patient_id: str, 
    update_data: dict[str, any],
    message_client: any
) -> None:
    import json
    from datetime import datetime
    
    channel = get_notification_channel(practice_id, "patient_updates")
    
    message = {
        'patient_id': patient_id,
        'timestamp': datetime.utcnow().isoformat(),
        'data': update_data
    }
    
    message_client.publish(channel, json.dumps(message))
    
    logger.info("Patient update published", extra={
        'practice_id': practice_id,
        'patient_id': patient_id,
        'channel': channel
    })
```

### ML Integration Patterns

#### Timeout and Error Handling for LLM Classification
```python
import asyncio
from typing import Protocol

class LLMClassifier(Protocol):
    async def classify(self, text: str) -> dict[str, any]:
        ...

async def classify_with_timeout(
    classifier: LLMClassifier,
    text: str,
    timeout_seconds: int = 30
) -> dict[str, any]:
    """Classify text with timeout and comprehensive error handling."""
    
    logger.debug("Starting LLM classification", extra={
        'text_length': len(text),
        'timeout_seconds': timeout_seconds
    })
    
    try:
        result = await asyncio.wait_for(
            classifier.classify(text),
            timeout=timeout_seconds
        )
        
        # Validate result structure
        required_fields = ['classification', 'confidence']
        for field in required_fields:
            if field not in result:
                raise ValueError(f"Missing required field in LLM response: {field}")
        
        logger.info("LLM classification completed", extra={
            'classification': result['classification'],
            'confidence': result['confidence'],
            'processing_time': result.get('processing_time')
        })
        
        return result
        
    except asyncio.TimeoutError:
        logger.error("LLM classification timeout", extra={
            'timeout_seconds': timeout_seconds,
            'text_length': len(text)
        })
        raise ClassificationTimeoutError(f"Classification timeout after {timeout_seconds}s")
        
    except Exception as e:
        logger.error("LLM classification failed", extra={
            'error_type': type(e).__name__,
            'error_message': str(e),
            'text_length': len(text)
        })
        raise ClassificationError(f"Classification failed: {e}") from e
```

### Code Organization (PEP 8)

#### Function Design
```python
# ✅ Single responsibility, clear interfaces
def validate_lab_result(
    lab_data: dict[str, any],
    loinc_code: str
) -> tuple[bool, list[str]]:
    """Validate a single lab result against LOINC standards.
    
    Returns:
        Tuple of (is_valid, validation_errors)
    """
    errors = []
    
    # Specific validation logic
    if not lab_data.get('value'):
        errors.append("Missing lab value")
    
    if not lab_data.get('unit'):
        errors.append("Missing unit of measurement")
        
    # LOINC-specific validation
    if not validate_loinc_code(loinc_code):
        errors.append(f"Invalid LOINC code: {loinc_code}")
    
    return len(errors) == 0, errors

# ✅ Descriptive naming
def calculate_egfr_from_creatinine(
    creatinine_mg_dl: float,
    age_years: int,
    is_female: bool,
    is_african_american: bool = False
) -> float:
    """Calculate eGFR using CKD-EPI equation."""
    # Implementation
    pass
```

### Never Do These

```python
# ❌ Don't use print() in production
print("Debug message")  # Use logger.debug() instead

# ❌ Don't use bare except
try:
    operation()
except:  # Use specific exceptions
    pass

# ❌ Don't use legacy typing
from typing import List, Dict, Optional, Union
def func(items: List[str]) -> Optional[Dict[str, int]]:  # Use list[str], dict[str, int] | None
    pass

# ❌ Don't ignore errors silently
def process_data():
    try:
        risky_operation()
    except SomeError:
        pass  # Don't ignore - log and handle appropriately

# ❌ Don't mix concerns
def process_and_save_and_notify(data):  # Split into separate functions
    # Too many responsibilities
    pass
```

### Summary Checklist

- [ ] Use `list[T]`, `dict[K, V]` instead of `typing.List[T]`, `typing.Dict[K, V]`
- [ ] Use `X | Y` instead of `typing.Union[X, Y]`
- [ ] Use `X | None` instead of `typing.Optional[X]`
- [ ] Use `logger` instead of `print()` for all output
- [ ] Include structured context in log messages
- [ ] Handle specific exceptions with appropriate logging
- [ ] Maintain practice isolation in multi-tenant code
- [ ] Use timeout and error handling for ML operations
- [ ] Follow single responsibility principle for functions
- [ ] Use descriptive names for variables and functions
- [ ] Include confidence scoring for medical data matching

## Mermaid Flowchart Fix Rules

- Remove HTML (<br/>) and markdown (===) - not supported
- Remove emojis from node IDs (can break parsing)
- Avoid special characters (/, :) in node names
- Use simple quoted text in nodes: ["Simple description"]
- Decision nodes: {"Simple question?"}
- Keep comments (%%) and styling, remove unsupported class targets

## Code Philosophy

### Dependency and Imports

- Do not use `sys.path.insert` statements
