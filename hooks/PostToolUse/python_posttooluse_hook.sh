#!/usr/bin/env bash

# Enhanced Universal Python Code Validator - PreToolUse Hook & Standalone Mode
# Blocks operations with CLAUDE.md violations + performance/security red flags
# Fast, focused checks that prevent immediate problems

set -euo pipefail

# Color codes (disabled in hook mode)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="/tmp/enhanced_validation_$$"
EXIT_CODE=0
ERROR_MESSAGES=""
ERROR_FILE=""

# Detection mode
HOOK_MODE=0
STANDALONE_MODE=0

# Validation flags
CHECK_RUFF=${CHECK_RUFF:-1}
CHECK_PYRIGHT=${CHECK_PYRIGHT:-1}
CHECK_CRITICAL_SECURITY=${CHECK_CRITICAL_SECURITY:-1}

# Color output functions (disabled in hook mode)
print_color() {
    if [ "$HOOK_MODE" -eq 0 ]; then
        echo -e "$1"
    fi
}

print_header() {
    print_color "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    print_color "${BOLD}${CYAN}  $1${NC}"
    print_color "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_success() { print_color "${GREEN}✅ $1${NC}"; }
print_error() { print_color "${RED}❌ $1${NC}"; }
print_warning() { print_color "${YELLOW}⚠️  $1${NC}"; }
print_info() { print_color "${CYAN}ℹ️  $1${NC}"; }

# Hook mode error output (to stderr for Claude)
hook_error() {
    echo "$1" >&2
}

# Collect error messages for final output
collect_error() {
    local message="$1"
    echo "$message" >> "$ERROR_FILE"
}

# Setup temporary directory
setup_temp_dir() {
    mkdir -p "$TEMP_DIR"
    ERROR_FILE="$TEMP_DIR/errors.txt"
    touch "$ERROR_FILE"
    trap cleanup EXIT
}

cleanup() {
    rm -rf "$TEMP_DIR"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Create temporary Python file from content
create_temp_file() {
    local content="$1"
    local file_path="$2"
    
    local extension="${file_path##*.}"
    if [ "$extension" = "$file_path" ]; then
        extension="py"
    fi
    
    local temp_file="$TEMP_DIR/validation_temp.$extension"
    echo "$content" > "$temp_file"
    echo "$temp_file"
}

# Function to detect and find project configuration
find_project_config() {
    local file_path="$1"
    local config_type="$2"
    
    local check_dir
    if [ -f "$file_path" ]; then
        check_dir=$(dirname "$file_path")
    else
        check_dir="$file_path"
    fi
    
    if [ -d "$check_dir" ]; then
        check_dir=$(cd "$check_dir" && pwd)
    else
        return 1
    fi
    
    # Walk up directory tree
    while [ "$check_dir" != "/" ]; do
        if [ -f "$check_dir/pyproject.toml" ]; then
            if [ "$config_type" = "ruff" ]; then
                if grep -q '^\[tool\.ruff\]' "$check_dir/pyproject.toml" 2>/dev/null; then
                    echo "$check_dir/pyproject.toml"
                    return 0
                fi
            elif [ "$config_type" = "pyright" ]; then
                if grep -q '^\[tool\.pyright\]' "$check_dir/pyproject.toml" 2>/dev/null; then
                    echo "$check_dir/pyproject.toml"
                    return 0
                fi
            fi
        fi
        
        if [ "$config_type" = "ruff" ]; then
            for config in "ruff.toml" ".ruff.toml"; do
                if [ -f "$check_dir/$config" ]; then
                    echo "$check_dir/$config"
                    return 0
                fi
            done
        elif [ "$config_type" = "pyright" ]; then
            if [ -f "$check_dir/pyrightconfig.json" ]; then
                echo "$check_dir/pyrightconfig.json"
                return 0
            fi
        fi
        
        check_dir=$(dirname "$check_dir")
    done
    
    return 1
}

# Create enhanced CLAUDE.md + critical security ruff configuration
create_enhanced_ruff_config() {
    cat > "$TEMP_DIR/ruff.toml" << 'EOF'
# Enhanced CLAUDE.md + Critical Security Ruff Configuration
target-version = "py312"
line-length = 127

[lint]
select = [
    # Core quality (BLOCKING)
    "F",     # pyflakes - import errors, undefined vars
    "E711", "E712", "E713", "E714",  # None/bool/not comparisons
    
    # CLAUDE.md compliance (BLOCKING)
    "UP006", # Use `list` instead of `List` for type annotations
    "UP007", # Use `X | Y` for union type annotations  
    "UP035", # Import replacements for deprecated typing features
    "UP037", # Remove quotes from type annotations
    
    # Critical logging violations (BLOCKING)
    "T201",  # print() statements (blocking in preToolUse)
    
    # Critical security issues (BLOCKING)
    "S102",  # exec() usage
    "S103",  # os.chmod with bad permissions  
    "S104",  # Binding to all interfaces
    "S105",  # Hardcoded password string
    "S106",  # Hardcoded password func arg
    "S107",  # Hardcoded password default
    "S108",  # Temp file without secure delete
    "S110",  # try/except pass
    "S112",  # try/except continue
    "S113",  # Request without timeout
    "S301",  # pickle usage
    "S302",  # marshal usage
    "S303",  # insecure MD5/SHA1
    "S304",  # insecure cipher
    "S305",  # insecure cipher mode
    "S306",  # mktemp usage
    "S307",  # eval() usage
    "S308",  # mark_safe usage
    "S310",  # URL open without HTTPS
    "S311",  # random for crypto
    "S312",  # telnet usage
    "S313",  # XML vulnerabilities
    "S314", "S315", "S316",  # XML/ElementTree vulnerabilities
    "S317",  # XML/lxml vulnerabilities
    "S318",  # XML/xmlrpc vulnerabilities
    "S319",  # XML/minidom vulnerabilities
    "S321",  # FTP without TLS
    "S323",  # Unverified context
    "S324",  # hashlib without usedforsecurity
    "S501",  # request verify=False
    "S506",  # unsafe YAML load
    "S508",  # SNS publish without encryption
    "S509",  # paramiko auto_add_policy
    
    # Critical performance issues (BLOCKING)
    "PERF102", # Inefficient comprehensions
    "PERF401", # Manual list comprehension
    
    # Critical error handling (BLOCKING)
    "BLE001", # Blind except Exception
    "TRY002", # raise without from
    "TRY400", # error logging without exc_info
    
    # Import issues (BLOCKING)
    "F401",  # unused imports
    "F811",  # redefined imports
    "I001",  # import block unsorted
]

ignore = [
    "E501",  # line too long (handled by formatter)
]

fixable = ["ALL"]
unfixable = []

[lint.pyupgrade]
keep-runtime-typing = false

[lint.per-file-ignores]
# More lenient for test files in preToolUse
"test_*.py" = ["T201"]  # Allow print in tests
"**/tests/**/*.py" = ["T201"]
"**/test/**/*.py" = ["T201"]
# CLI files can use print for user interaction
"**/cli.py" = ["T201"]
"**/main.py" = ["T201"]
"__main__.py" = ["T201"]

[format]
quote-style = "double"
indent-style = "space"
EOF
}

# Create enhanced Pyright configuration
create_enhanced_pyright_config() {
    cat > "$TEMP_DIR/pyrightconfig.json" << 'EOF'
{
    "pythonVersion": "3.12",
    "typeCheckingMode": "basic",
    "useLibraryCodeForTypes": true,
    "reportUnnecessaryTypeIgnoreComment": "error",
    "reportImportCycles": "error",
    "reportUnnecessaryComparison": "warning",
    "reportMissingImports": true,
    "reportMissingTypeStubs": false,
    "reportUnknownMemberType": false,
    "reportUnknownVariableType": false,
    "reportUnknownArgumentType": false,
    "stubPath": ""
}
EOF
}

# Enhanced critical security check (fast pattern matching)
run_critical_security_check() {
    local content="$1"
    local file_path="$2"
    local violations=()
    
    # SQL Injection patterns
    if echo "$content" | grep -qE "cursor\.execute\(.*%.*\)|\.execute\(.*\+.*\)"; then
        violations+=("Potential SQL injection vulnerability")
    fi
    
    # Command injection patterns
    if echo "$content" | grep -qE "os\.system\(.*\+.*\)|subprocess\.(call|run)\(.*\+.*\)"; then
        violations+=("Potential command injection vulnerability")
    fi
    
    # Hardcoded secrets (more specific patterns)
    if echo "$content" | grep -qiE "(password|secret|token|api_key)\s*=\s*['\"][A-Za-z0-9]{16,}['\"]"; then
        violations+=("Hardcoded secret/credential detected")
    fi
    
    # Insecure random for security purposes
    if echo "$content" | grep -qE "import random" && echo "$content" | grep -qiE "(password|token|secret|key)"; then
        violations+=("Using insecure random module for security purposes")
    fi
    
    # Dangerous eval/exec usage
    if echo "$content" | grep -qE "\b(eval|exec)\s*\("; then
        violations+=("Dangerous eval/exec usage detected")
    fi
    
    # Insecure SSL/TLS
    if echo "$content" | grep -qE "ssl.*PROTOCOL_TLS|verify=False|check_hostname=False"; then
        violations+=("Insecure SSL/TLS configuration")
    fi
    
    if [ ${#violations[@]} -gt 0 ]; then
        if [ "$HOOK_MODE" -eq 1 ]; then
            for v in "${violations[@]}"; do
                echo "CRITICAL SECURITY: $v" >> "$ERROR_FILE"
            done
        else
            print_error "Critical security vulnerabilities detected:"
            for v in "${violations[@]}"; do
                echo "  - $v"
            done
        fi
        return 1
    fi
    return 0
}

# Run enhanced Ruff with critical rule focus
run_enhanced_ruff_check() {
    local target_file="$1"
    local original_path="$2"
    
    # Check for project config
    local config_args=""
    if project_config=$(find_project_config "$original_path" "ruff"); then
        [ "$HOOK_MODE" -eq 0 ] && print_info "Using project Ruff config: $project_config"
        if [[ "$project_config" != *"pyproject.toml" ]]; then
            config_args="--config $project_config"
        fi
    else
        [ "$HOOK_MODE" -eq 0 ] && print_info "Using enhanced CLAUDE.md + security Ruff config"
        create_enhanced_ruff_config
        config_args="--config $TEMP_DIR/ruff.toml"
    fi
    
    # Run ruff with enhanced rule selection
    local ruff_output
    if ruff_output=$(uvx ruff check $config_args "$target_file" 2>&1); then
        [ "$HOOK_MODE" -eq 0 ] && print_success "Enhanced Ruff validation passed"
        return 0
    else
        if [ "$HOOK_MODE" -eq 1 ]; then
            # Parse ruff output for hook mode - handle both temp file and original file paths
            echo "$ruff_output" | grep -E "^(S[0-9]{3}|BLE001|TRY002|UP006|UP007|UP035|UP037|T201|F[0-9]{3}|E999|I[0-9]{3}|PERF[0-9]{3})" | while IFS= read -r line; do
                if echo "$line" | grep -qE "^(S[0-9]{3}|BLE001|TRY002)"; then
                    echo "CRITICAL SECURITY: $line" >> "$ERROR_FILE"
                elif echo "$line" | grep -qE "^(UP006|UP007|UP035|UP037)"; then
                    echo "CLAUDE.md Syntax: $line" >> "$ERROR_FILE"
                elif echo "$line" | grep -qE "^(T201)"; then
                    echo "Logging Standard: $line" >> "$ERROR_FILE"
                elif echo "$line" | grep -qE "^(F[0-9]{3}|E999)"; then
                    echo "Code Error: $line" >> "$ERROR_FILE"
                else
                    echo "Quality Issue: $line" >> "$ERROR_FILE"
                fi
            done
        else
            print_error "Enhanced Ruff found critical violations:"
            echo "$ruff_output"
            
            # Highlight critical issues
            if echo "$ruff_output" | grep -qE "(S[0-9]{3})"; then
                print_error "🚨 CRITICAL SECURITY VIOLATIONS DETECTED"
            fi
            if echo "$ruff_output" | grep -qE "(UP006|UP007|UP035|UP037)"; then
                print_warning "CLAUDE.md syntax violations detected"
            fi
            if echo "$ruff_output" | grep -qE "(T201)"; then
                print_warning "Logging standard violations detected"
            fi
        fi
        return 1
    fi
}

# Enhanced Pyright type checking with stricter rules  
run_enhanced_pyright_check() {
    local target_file="$1"
    local original_path="$2"
    
    # Check for project config
    local config_args=""
    if project_config=$(find_project_config "$original_path" "pyright"); then
        [ "$HOOK_MODE" -eq 0 ] && print_info "Using project Pyright config: $project_config"
    else
        [ "$HOOK_MODE" -eq 0 ] && print_info "Using enhanced Pyright config"
        create_enhanced_pyright_config
        config_args="--project $TEMP_DIR"
    fi
    
    # Run pyright with enhanced checking - change to project directory if needed
    local pyright_output pyright_exit_code
    local project_dir=""
    
    # Find the project directory (look for pyproject.toml)
    if [ -f "$original_path" ]; then
        project_dir=$(dirname "$original_path")
        while [ "$project_dir" != "/" ]; do
            if [ -f "$project_dir/pyproject.toml" ]; then
                break
            fi
            project_dir=$(dirname "$project_dir")
        done
        if [ "$project_dir" = "/" ]; then
            project_dir=""
        fi
    fi
    
    # Run pyright from project directory if found
    if [ -n "$project_dir" ] && [ -d "$project_dir" ]; then
        pyright_output=$(cd "$project_dir" && uvx pyright $config_args "$target_file" 2>&1)
        pyright_exit_code=$?
    else
        pyright_output=$(uvx pyright $config_args "$target_file" 2>&1)
        pyright_exit_code=$?
    fi
    
    # Check for errors - only fail if there are actual errors (not "0 errors")
    local error_count=0
    if echo "$pyright_output" | grep -qE "[1-9][0-9]* error"; then
        error_count=1
    elif echo "$pyright_output" | grep -qE "error:" || echo "$pyright_output" | grep -qE "could not be resolved"; then
        error_count=1
    fi
    
    if [ "$error_count" -eq 1 ]; then
        if [ "$HOOK_MODE" -eq 1 ]; then
            # Extract specific error lines for hook mode - handle both temp and original file paths
            if echo "$pyright_output" | grep -qE "error:"; then
                echo "$pyright_output" | grep -E "error:" | head -5 | while IFS= read -r line; do
                    # Clean up file paths in error messages
                    clean_line=$(echo "$line" | sed "s|$target_file:||" | sed "s|$original_path:||")
                    echo "Type Error: $clean_line" >> "$ERROR_FILE"
                done
            else
                # If no specific error lines, collect the summary  
                echo "$pyright_output" | head -5 | while IFS= read -r line; do
                    if [[ "$line" =~ error|Error|could.not.be.resolved ]]; then
                        echo "Type Error: $line" >> "$ERROR_FILE"
                    fi
                done
            fi
        else
            print_error "Enhanced type checking failed:"
            echo "$pyright_output"
        fi
        return 1
    else
        [ "$HOOK_MODE" -eq 0 ] && print_success "Enhanced type checking passed"
        return 0
    fi
}

# Process hook mode input
process_hook_input() {
    local json_input
    json_input=$(cat)
    
    # Parse JSON directly using Python (handles newlines properly)
    local tool_name file_path content
    
    # Extract tool_name and validate JSON in one go
    local parse_result
    parse_result=$(printf '%s' "$json_input" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    tool_name = data.get('tool_name', '')
    print(f'{tool_name}')
except:
    print('INVALID')
    sys.exit(1)
")
    
    if [ "$parse_result" = "INVALID" ]; then
        exit 0
    fi
    
    tool_name="$parse_result"
    
    case "$tool_name" in
        "Edit")
            local extraction_result
            extraction_result=$(printf '%s' "$json_input" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    file_path = data.get('tool_input', {}).get('file_path', '')
    content = data.get('tool_input', {}).get('new_string', '')
    print(f'{file_path}|||{content}')
except:
    print('INVALID')
")
            if [ "$extraction_result" = "INVALID" ]; then exit 0; fi
            file_path="${extraction_result%%|||*}"
            content="${extraction_result#*|||}"
            ;;
        "Write")
            local extraction_result
            extraction_result=$(printf '%s' "$json_input" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    file_path = data.get('tool_input', {}).get('file_path', '')
    content = data.get('tool_input', {}).get('content', '')
    print(f'{file_path}|||{content}')
except:
    print('INVALID')
")
            if [ "$extraction_result" = "INVALID" ]; then exit 0; fi
            file_path="${extraction_result%%|||*}"
            content="${extraction_result#*|||}"
            ;;
        "MultiEdit")
            local extraction_result
            extraction_result=$(printf '%s' "$json_input" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    file_path = data.get('tool_input', {}).get('file_path', '')
    edits = data.get('tool_input', {}).get('edits', [])
    content = '\\n'.join(edit.get('new_string', '') for edit in edits)
    print(f'{file_path}|||{content}')
except:
    print('INVALID')
")
            if [ "$extraction_result" = "INVALID" ]; then exit 0; fi
            file_path="${extraction_result%%|||*}"
            content="${extraction_result#*|||}"
            ;;
        *)
            exit 0
            ;;
    esac
    
    # Only validate Python files
    if [[ "$file_path" != *.py ]]; then
        exit 0
    fi
    
    # Validate the content
    validate_content "$content" "$file_path"
}

# Main validation function
validate_content() {
    local content="$1"
    local file_path="$2"
    
    # Determine if we should use the original file or create a temp file
    local validation_file
    if [ "$HOOK_MODE" -eq 1 ] && [ -f "$file_path" ]; then
        # In hook mode with existing file, create temp file but also try original
        validation_file=$(create_temp_file "$content" "$file_path")
        local original_file="$file_path"
    elif [ "$HOOK_MODE" -eq 0 ] && [ -f "$file_path" ]; then
        # In standalone mode, use the actual file
        validation_file="$file_path"
        local original_file="$file_path"
    else
        # Create temp file as fallback
        validation_file=$(create_temp_file "$content" "$file_path")
        local original_file=""
    fi
    
    # Run critical security check first (fastest) - always use content for security
    if [ "$CHECK_CRITICAL_SECURITY" -eq 1 ]; then
        [ "$HOOK_MODE" -eq 0 ] && print_header "🔒 Critical Security Check"
        run_critical_security_check "$content" "$file_path" || EXIT_CODE=1
    fi
    
    # Run enhanced Ruff validation - prefer original file if available
    if [ "$CHECK_RUFF" -eq 1 ]; then
        [ "$HOOK_MODE" -eq 0 ] && print_header "🔍 Enhanced Ruff Validation"
        local ruff_target="$validation_file"
        if [ -n "$original_file" ] && [ -f "$original_file" ]; then
            ruff_target="$original_file"
        fi
        if ! run_enhanced_ruff_check "$ruff_target" "$file_path"; then
            EXIT_CODE=1
        fi
    fi
    
    # Run enhanced Pyright type checking - prefer original file if available
    if [ "$CHECK_PYRIGHT" -eq 1 ]; then
        [ "$HOOK_MODE" -eq 0 ] && print_header "🔍 Enhanced Type Checking"
        local pyright_target="$validation_file"
        if [ -n "$original_file" ] && [ -f "$original_file" ]; then
            pyright_target="$original_file"
        fi
        if ! run_enhanced_pyright_check "$pyright_target" "$file_path"; then
            EXIT_CODE=1
        fi
    fi
}

# Main function
main() {
    setup_temp_dir
    
    # Detect mode based on stdin availability and arguments
    if [ -t 0 ] || [ $# -gt 0 ]; then
        # Terminal mode or arguments provided - standalone
        STANDALONE_MODE=1
        HOOK_MODE=0
        
        # Parse command line arguments
        if [ $# -eq 0 ]; then
            echo "Usage: $0 [OPTIONS] <file>"
            echo ""
            echo "Enhanced Python Code Validator for CLAUDE.md + Security Standards"
            echo ""
            echo "Options:"
            echo "  --no-ruff         Skip enhanced Ruff checks"
            echo "  --no-pyright      Skip enhanced Pyright type checks"
            echo "  --no-security     Skip critical security checks"
            echo "  -h, --help        Show this help"
            exit 0
        fi
        
        while [[ $# -gt 0 ]]; do
            case $1 in
                --no-ruff) CHECK_RUFF=0; shift ;;
                --no-pyright) CHECK_PYRIGHT=0; shift ;;
                --no-security) CHECK_CRITICAL_SECURITY=0; shift ;;
                -h|--help)
                    echo "Enhanced validator with CLAUDE.md compliance + critical security checks"
                    echo "Blocks operations on violations to prevent immediate problems"
                    exit 0
                    ;;
                *)
                    if [ -f "$1" ]; then
                        content=$(cat "$1")
                        print_header "🐍 Enhanced CLAUDE.md + Security Validation"
                        print_info "File: $1"
                        validate_content "$content" "$1"
                    else
                        echo "Error: File not found: $1"
                        exit 1
                    fi
                    shift
                    ;;
            esac
        done
    else
        # Pipe mode - hook
        HOOK_MODE=1
        STANDALONE_MODE=0
        process_hook_input
    fi
    
    # Handle exit codes
    if [ "$HOOK_MODE" -eq 1 ]; then
        
        if [ "$EXIT_CODE" -ne 0 ]; then
            hook_error ""
            hook_error "🚫 CRITICAL VIOLATIONS DETECTED"
            hook_error ""
            if [ -s "$ERROR_FILE" ]; then
                hook_error "Specific violations found:"
                while IFS= read -r error_line; do
                    hook_error "  $error_line"
                done < "$ERROR_FILE"
                hook_error ""
            else
                hook_error "No specific error messages collected (this indicates an internal issue)"
            fi
            hook_error "⚠️  CLAUDE.md standards and/or security violations found"
            hook_error "🔒 Critical security issues MUST be fixed before proceeding"
            hook_error "📋 Fix all violations and retry the operation"
            hook_error "💡 Run standalone for detailed report: $0 <file>"
            exit 2  # Block the operation
        else
            echo "✅ All critical validations passed"
            hook_error ""
            hook_error "📝 REMINDER: Update the todo list"
            hook_error ""
            exit 0
        fi
    else
        # Standalone mode
        if [ "$EXIT_CODE" -eq 0 ]; then
            print_success "All enhanced validations passed! 🎉"
        else
            print_error "Critical violations detected. Review output above."
        fi
        exit "$EXIT_CODE"
    fi
}

# Run main function
main "$@"