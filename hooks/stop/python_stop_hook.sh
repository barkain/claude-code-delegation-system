#!/usr/bin/env bash

# Enhanced Stop Event Hook for Claude Code
# Comprehensive code quality checks on staged Python files:
# 1. Core validation (ruff & pyright) 
# 2. Dead code detection (uvx deadcode)
# 3. Complexity analysis (uvx complexipy)
# 4. Security scanning (pattern matching)
# 5. Documentation coverage
# 6. API design quality
# 7. Error handling completeness
# 8. Performance anti-patterns
# 9. Integration smoke tests
# 10. Commit message suggestions

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="/tmp/enhanced_stop_hook_$$"
EXIT_CODE=0
REPORT_FILE="/tmp/claude_enhanced_report_$(date +%Y%m%d_%H%M%S).md"

# Configuration flags - all enabled by default
CHECK_VALIDATION=${CHECK_VALIDATION:-1}
CHECK_DEADCODE=${CHECK_DEADCODE:-1}
CHECK_COMPLEXITY=${CHECK_COMPLEXITY:-1}
CHECK_SECURITY=${CHECK_SECURITY:-1}
CHECK_DOCUMENTATION=${CHECK_DOCUMENTATION:-1}
CHECK_API_DESIGN=${CHECK_API_DESIGN:-1}
CHECK_ERROR_HANDLING=${CHECK_ERROR_HANDLING:-1}
CHECK_PERFORMANCE=${CHECK_PERFORMANCE:-1}
CHECK_INTEGRATION=${CHECK_INTEGRATION:-1}
SUGGEST_COMMIT_MSG=${SUGGEST_COMMIT_MSG:-1}

# Thresholds
MAX_COMPLEXITY=${MAX_COMPLEXITY:-15}
MAX_FUNCTION_ARGS=${MAX_FUNCTION_ARGS:-5}
MIN_DOCSTRING_COVERAGE=${MIN_DOCSTRING_COVERAGE:-80}

# Utility functions
print_header() {
    echo -e "\n${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_info() { echo -e "${CYAN}ℹ️  $1${NC}"; }
print_security() { echo -e "${MAGENTA}🔒 $1${NC}"; }

# Setup and cleanup
setup_temp_dir() {
    mkdir -p "$TEMP_DIR"
}

cleanup() {
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get staged Python files that are not deleted
get_staged_python_files() {
    git diff --cached --name-status 2>/dev/null | \
        grep -E '^[AM]\s+.*\.py$' | \
        awk '{print $2}' | \
        while read -r file; do
            if [ -f "$file" ]; then
                echo "$file"
            fi
        done
}

# Check if we're in a git repository
is_git_repo() {
    git rev-parse --git-dir >/dev/null 2>&1
}

# Enhanced validation with better ruff rules
run_enhanced_validation() {
    local files=("$@")
    
    print_header "🔍 Enhanced Code Validation"
    
    if [ ${#files[@]} -eq 0 ]; then
        print_info "No files to validate"
        return 0
    fi
    
    # Create enhanced ruff config
    cat > "$TEMP_DIR/enhanced_ruff.toml" << 'EOF'
target-version = "py312"
line-length = 127

[lint]
select = [
    # Core quality
    "F", "E", "W",     # pyflakes, pycodestyle
    
    # Python 3.12+ syntax (CLAUDE.md)
    "UP006", "UP007", "UP035", "UP037",
    
    # Logging standards
    "T20", "LOG",
    
    # Import organization  
    "I", "F401", "E401",
    
    # Performance optimizations
    "PERF",            # Performance anti-patterns
    "C419",            # Unnecessary comprehension
    
    # Code simplification
    "SIM",             # Simplify complex code
    "RET",             # Return statement issues
    "ARG",             # Unused arguments
    "PTH",             # Use pathlib over os.path
    
    # Error handling
    "BLE",             # Blind except
    "TRY",             # Exception handling best practices
    
    # API design
    "PIE",             # Unnecessary pass statements
    "COM",             # Comma handling
    
    # Documentation
    "TD", "FIX",       # TODO/FIXME formatting
    
    # Import conventions
    "TID", "ICN",      # Tidy imports, import conventions
    
    # Additional quality
    "B", "C4",         # Bugbear, comprehensions
]

ignore = [
    "E501",            # Line too long (handled by formatter)
    "TRY003",          # Long exception messages
    "COM812",          # Trailing comma (handled by formatter)
]

[lint.per-file-ignores]
"__init__.py" = ["F401"]                    # Allow unused imports
"test_*.py" = ["ARG001", "ARG002"]         # Allow unused args in tests
"**/tests/**/*.py" = ["ARG001", "ARG002"]  # Allow unused args in test dirs

[lint.pyupgrade]
keep-runtime-typing = false

[lint.pylint]
max-args = 5
max-returns = 3
max-branches = 12
EOF
    
    local validation_failed=0
    
    for file in "${files[@]}"; do
        print_info "Validating: $file"
        
        if command_exists ruff; then
            local ruff_output
            if ruff_output=$(uvx ruff check --config "$TEMP_DIR/enhanced_ruff.toml" "$file" 2>&1); then
                print_success "  ✓ $file"
            else
                print_error "  ✗ $file - validation failed"
                echo "$ruff_output" | head -10 | sed 's/^/    /'
                validation_failed=1
                
                # Add to report
                {
                    echo "### Validation Issues in $file"
                    echo '```'
                    echo "$ruff_output"
                    echo '```'
                    echo ""
                } >> "$REPORT_FILE"
            fi
        else
            print_warning "Ruff not available"
        fi
    done
    
    if [ $validation_failed -eq 0 ]; then
        print_success "Enhanced validation passed"
        return 0
    else
        print_error "Validation issues detected"
        return 1
    fi
}

# Security scanning
run_security_check() {
    local files=("$@")
    
    print_header "🔒 Security Analysis"
    
    if [ ${#files[@]} -eq 0 ]; then
        print_info "No files to scan"
        return 0
    fi
    
    local security_issues=0
    
    # Check for hardcoded secrets/credentials
    for file in "${files[@]}"; do
        local issues_found=""
        
        # Common secret patterns
        if grep -nHE "(password|secret|token|key|api_key)\s*=\s*['\"][^'\"]{8,}" "$file" 2>/dev/null; then
            issues_found="Potential hardcoded credentials"
        fi
        
        # SQL injection patterns
        if grep -nHE "cursor\.execute\(.*%.*\)" "$file" 2>/dev/null; then
            issues_found="${issues_found:+$issues_found; }Potential SQL injection"
        fi
        
        # Command injection patterns
        if grep -nHE "(os\.system|subprocess\.call).*\+.*" "$file" 2>/dev/null; then
            issues_found="${issues_found:+$issues_found; }Potential command injection"
        fi
        
        # Insecure random
        if grep -nHE "import random" "$file" 2>/dev/null && grep -qE "password|token|secret" "$file" 2>/dev/null; then
            issues_found="${issues_found:+$issues_found; }Insecure random for secrets"
        fi
        
        if [ -n "$issues_found" ]; then
            print_security "Security issues in $file: $issues_found"
            security_issues=1
            
            # Add to report
            {
                echo "### Security Issues in $file"
                echo "- $issues_found"
                echo ""
            } >> "$REPORT_FILE"
        fi
    done
    
    
    if [ $security_issues -eq 0 ]; then
        print_success "No security issues detected"
        return 0
    else
        print_warning "Security issues require review"
        return 1
    fi
}

# Documentation coverage analysis
run_documentation_check() {
    local files=("$@")
    
    print_header "📚 Documentation Coverage"
    
    if [ ${#files[@]} -eq 0 ]; then
        print_info "No files to check"
        return 0
    fi
    
    local total_functions=0
    local documented_functions=0
    local missing_docs=()
    
    for file in "${files[@]}"; do
        local file_stats
        file_stats=$(uv run python3 - "$file" << 'EOF'
import ast
import sys

file_path = sys.argv[1]
with open(file_path) as f:
    try:
        tree = ast.parse(f.read())
    except SyntaxError:
        print("0,0")  # Skip files with syntax errors
        exit()

total = 0
documented = 0
missing = []

for node in ast.walk(tree):
    if isinstance(node, ast.FunctionDef):
        # Skip private functions and test functions
        if not node.name.startswith('_') and not node.name.startswith('test_'):
            total += 1
            if ast.get_docstring(node):
                documented += 1
            else:
                missing.append(f"{file_path}:{node.lineno}: {node.name}")

print(f"{total},{documented}")
for item in missing:
    print(f"MISSING: {item}")
EOF
)
        
        local file_total file_documented
        file_total=$(echo "$file_stats" | head -1 | cut -d, -f1)
        file_documented=$(echo "$file_stats" | head -1 | cut -d, -f2)
        
        total_functions=$((total_functions + file_total))
        documented_functions=$((documented_functions + file_documented))
        
        # Collect missing documentation
        echo "$file_stats" | grep "MISSING:" | while read -r line; do
            missing_docs+=("${line#MISSING: }")
        done
    done
    
    local coverage=0
    if [ $total_functions -gt 0 ]; then
        coverage=$((documented_functions * 100 / total_functions))
    fi
    
    print_info "Documentation coverage: $documented_functions/$total_functions functions ($coverage%)"
    
    if [ $coverage -lt $MIN_DOCSTRING_COVERAGE ]; then
        print_warning "Documentation coverage below threshold ($MIN_DOCSTRING_COVERAGE%)"
        
        # Show missing docs
        echo "$file_stats" | grep "MISSING:" | head -10 | sed 's/MISSING: /  Missing: /'
        
        # Add to report
        {
            echo "## Documentation Coverage"
            echo "Coverage: $coverage% ($documented_functions/$total_functions functions)"
            echo "Missing docstrings:"
            echo '```'
            echo "$file_stats" | grep "MISSING:" | sed 's/MISSING: //'
            echo '```'
            echo ""
        } >> "$REPORT_FILE"
        
        return 1
    else
        print_success "Documentation coverage meets threshold"
        return 0
    fi
}

# API design quality checks
run_api_design_check() {
    local files=("$@")
    
    print_header "🎯 API Design Analysis"
    
    if [ ${#files[@]} -eq 0 ]; then
        print_info "No files to analyze"
        return 0
    fi
    
    local design_issues=0
    
    for file in "${files[@]}"; do
        local issues
        issues=$(uv run python3 - "$file" << EOF
import ast
import sys

file_path = sys.argv[1]
with open(file_path) as f:
    try:
        tree = ast.parse(f.read())
    except SyntaxError:
        exit()  # Skip files with syntax errors

issues = []

for node in ast.walk(tree):
    if isinstance(node, ast.FunctionDef):
        # Skip private and test functions
        if node.name.startswith('_') or node.name.startswith('test_'):
            continue
            
        # Check parameter count
        param_count = len(node.args.args)
        if param_count > $MAX_FUNCTION_ARGS:
            issues.append(f"{file_path}:{node.lineno}: Function '{node.name}' has {param_count} parameters (max recommended: $MAX_FUNCTION_ARGS)")
        
        # Check for missing return type hints on public functions
        if not node.returns and not node.name.startswith('_'):
            issues.append(f"{file_path}:{node.lineno}: Public function '{node.name}' missing return type hint")
        
        # Check for boolean trap (multiple boolean parameters)
        bool_params = sum(1 for arg in node.args.args if 
                         hasattr(arg, 'annotation') and 
                         arg.annotation and 
                         (getattr(arg.annotation, 'id', None) == 'bool' or 
                          str(arg.annotation) == 'bool'))
        if bool_params > 1:
            issues.append(f"{file_path}:{node.lineno}: Function '{node.name}' has {bool_params} boolean parameters (consider using enum/dataclass)")

for issue in issues:
    print(issue)
EOF
)
        
        if [ -n "$issues" ]; then
            print_warning "API design issues in $file:"
            echo "$issues" | sed 's/^/  /'
            design_issues=1
            
            # Add to report
            {
                echo "### API Design Issues in $file"
                echo '```'
                echo "$issues"
                echo '```'
                echo ""
            } >> "$REPORT_FILE"
        fi
    done
    
    if [ $design_issues -eq 0 ]; then
        print_success "API design analysis passed"
        return 0
    else
        print_warning "API design improvements recommended"
        return 1
    fi
}

# Error handling completeness
run_error_handling_check() {
    local files=("$@")
    
    print_header "⚠️ Error Handling Analysis"
    
    if [ ${#files[@]} -eq 0 ]; then
        print_info "No files to check"
        return 0
    fi
    
    local error_issues=0
    
    for file in "${files[@]}"; do
        local issues=""
        
        # Check for bare except clauses
        if grep -n "except:" "$file" 2>/dev/null; then
            issues="${issues}Bare except clause found; "
        fi
        
        # Check for missing logging in exception handlers
        local missing_logging
        missing_logging=$(uv run python3 - "$file" << 'EOF'
import ast
import re
import sys

file_path = sys.argv[1]
with open(file_path) as f:
    try:
        content = f.read()
        tree = ast.parse(content)
    except SyntaxError:
        exit()

issues = []

for node in ast.walk(tree):
    if isinstance(node, ast.ExceptHandler):
        # Get the source code of the except block
        try:
            except_lines = content.split('\n')[node.lineno-1:node.end_lineno]
            except_code = '\n'.join(except_lines)
            
            # Check if logging is present
            if not re.search(r'logger\.|logging\.', except_code):
                issues.append(f"{file_path}:{node.lineno}: Exception handler without logging")
        except:
            pass  # Skip if we can't analyze the block

for issue in issues:
    print(issue)
EOF
)
        
        if [ -n "$missing_logging" ]; then
            issues="${issues}Missing logging in exception handlers; "
        fi
        
        # Check for overly broad exception catching
        if grep -nE "except (Exception|BaseException):" "$file" 2>/dev/null; then
            issues="${issues}Overly broad exception catching; "
        fi
        
        if [ -n "$issues" ]; then
            print_warning "Error handling issues in $file: ${issues%; }"
            error_issues=1
            
            # Add to report
            {
                echo "### Error Handling Issues in $file"
                echo "- ${issues%; }"
                if [ -n "$missing_logging" ]; then
                    echo '```'
                    echo "$missing_logging"
                    echo '```'
                fi
                echo ""
            } >> "$REPORT_FILE"
        fi
    done
    
    if [ $error_issues -eq 0 ]; then
        print_success "Error handling analysis passed"
        return 0
    else
        print_warning "Error handling improvements needed"
        return 1
    fi
}

# Integration smoke tests
run_integration_check() {
    local files=("$@")
    
    print_header "🔥 Integration Smoke Tests"
    
    if [ ${#files[@]} -eq 0 ]; then
        print_info "No files to test"
        return 0
    fi
    
    local integration_issues=0
    
    for file in "${files[@]}"; do
        # Test syntax compilation
        if ! python3 -m py_compile "$file" 2>/dev/null; then
            print_error "Syntax compilation failed: $file"
            integration_issues=1
            continue
        fi
        
        # Test import capability
        local module_name
        module_name=$(echo "$file" | sed 's/\.py$//' | sed 's/\//./g')
        
        if python3 -c "import sys; sys.path.insert(0, '.'); import $module_name" 2>/dev/null; then
            print_info "Import test passed: $file"
        else
            print_warning "Import test failed: $file (may have dependencies)"
        fi
        
        # Test if __main__ block exists and is executable
        if grep -q "if __name__ == '__main__':" "$file" 2>/dev/null; then
            print_info "Executable script detected: $file"
            # Could add more sophisticated testing here
        fi
    done
    
    if [ $integration_issues -eq 0 ]; then
        print_success "Integration tests passed"
        return 0
    else
        print_error "Integration issues detected"
        return 1
    fi
}

# Existing functions (deadcode, complexity) - keeping them as they are
run_deadcode_check() {
    local files=("$@")
    
    print_header "💀 Dead Code Detection"
    
    if [ ${#files[@]} -eq 0 ]; then
        print_info "No files to check for dead code"
        return 0
    fi
    
    if ! command_exists uvx; then
        print_warning "uvx not found - skipping dead code check"
        return 0
    fi
    
    local only_pattern=""
    for file in "${files[@]}"; do
        if [ -z "$only_pattern" ]; then
            only_pattern="$file"
        else
            only_pattern="$only_pattern $file"
        fi
    done
    
    local deadcode_output
    deadcode_output=$(uvx deadcode . \
        --only $only_pattern \
        --exclude "**/test_*.py" \
        --exclude "**/*_test.py" \
        --exclude "**/tests/**/*.py" \
        --exclude "**/test/**/*.py" \
        --quiet --count 2>&1 || true)
    
    if [ -z "$deadcode_output" ] || [ "$deadcode_output" = "0" ]; then
        print_success "No dead code detected"
        return 0
    else
        print_warning "Dead code found: $deadcode_output unused items"
        
        {
            echo "## Dead Code Detection"
            echo "Found $deadcode_output unused code items"
            echo '```'
            uvx deadcode . --only $only_pattern \
                --exclude "**/test_*.py" \
                --exclude "**/*_test.py" \
                --exclude "**/tests/**/*.py" \
                --exclude "**/test/**/*.py" \
                2>&1 | head -20 || true
            echo '```'
            echo ""
        } >> "$REPORT_FILE"
        
        return 1
    fi
}

run_complexity_check() {
    local files=("$@")
    
    print_header "📊 Complexity Analysis"
    
    if [ ${#files[@]} -eq 0 ]; then
        print_info "No files to check for complexity"
        return 0
    fi
    
    if ! command_exists uvx; then
        print_warning "uvx not found - skipping complexity check"
        return 0
    fi
    
    local complexity_output
    complexity_output=$(uvx complexipy "${files[@]}" --max-complexity-allowed "$MAX_COMPLEXITY" --quiet 2>&1 || true)
    
    if [ -z "$complexity_output" ]; then
        print_success "All functions within complexity limit ($MAX_COMPLEXITY)"
        return 0
    else
        print_warning "High complexity functions detected"
        uvx complexipy "${files[@]}" --max-complexity-allowed "$MAX_COMPLEXITY" --sort desc 2>&1 | head -10 | sed 's/^/  /'
        
        {
            echo "## Complexity Analysis"
            echo "Functions exceeding complexity threshold of $MAX_COMPLEXITY:"
            echo '```'
            uvx complexipy "${files[@]}" --max-complexity-allowed "$MAX_COMPLEXITY" --sort desc 2>&1 | head -20 || true
            echo '```'
            echo ""
        } >> "$REPORT_FILE"
        
        return 1
    fi
}

# Smart commit message suggestions
suggest_commit_message() {
    print_header "💬 Commit Message Suggestions"
    
    # Analyze staged changes
    local changes_summary has_new_functions has_refactoring has_fixes has_docs
    changes_summary=$(git diff --cached --stat | tail -1 || echo "No changes")
    has_new_functions=$(git diff --cached | grep -c "^+def " || true)
    has_refactoring=$(git diff --cached | grep -c "^-def " || true)
    has_fixes=$(git diff --cached | grep -ic "fix\|bug\|error" || true)
    has_docs=$(git diff --cached | grep -c "^+.*\"\"\"" || true)
    
    local suggested_type suggested_message
    
    # Determine commit type and message
    if [ "$has_new_functions" -gt 0 ] && [ "$has_refactoring" -eq 0 ]; then
        suggested_type="feat"
        suggested_message="add $has_new_functions new functions"
    elif [ "$has_refactoring" -gt 0 ] && [ "$has_new_functions" -eq 0 ]; then
        suggested_type="refactor"
        suggested_message="restructure functions for better maintainability"
    elif [ "$has_fixes" -gt 0 ]; then
        suggested_type="fix"
        suggested_message="resolve issues in code quality and error handling"
    elif [ "$has_docs" -gt 0 ]; then
        suggested_type="docs"
        suggested_message="improve documentation coverage"
    else
        suggested_type="improve"
        suggested_message="enhance code quality and standards compliance"
    fi
    
    local full_message="$suggested_type: $suggested_message"
    
    print_info "Suggested commit message:"
    echo "  $full_message"
    
    # Add to report
    {
        echo "## Suggested Commit Message"
        echo '```'
        echo "$full_message"
        echo '```'
        echo ""
        echo "### Change Analysis"
        echo "- New functions: $has_new_functions"
        echo "- Refactored functions: $has_refactoring"  
        echo "- Bug fixes: $has_fixes"
        echo "- Documentation additions: $has_docs"
        echo ""
    } >> "$REPORT_FILE"
}

# Generate comprehensive summary
generate_enhanced_summary() {
    local validation_result="$1"
    local deadcode_result="$2"  
    local complexity_result="$3"
    local security_result="$4"
    local docs_result="$5"
    local api_result="$6"
    local error_result="$7"
    local integration_result="$8"
    
    print_header "📋 Enhanced Quality Report"
    
    # Start report file
    {
        echo "# Claude Code Enhanced Quality Report"
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Directory: $(pwd)"
        echo "Scope: Staged Python files only"
        echo ""
        echo "## Executive Summary"
    } > "$REPORT_FILE"
    
    local total_checks=8
    local passed_checks=0
    
    # Add results to report
    for check in "validation:$validation_result:Code Validation" \
                 "deadcode:$deadcode_result:Dead Code Check" \
                 "complexity:$complexity_result:Complexity Analysis" \
                 "security:$security_result:Security Scan" \
                 "docs:$docs_result:Documentation Coverage" \
                 "api:$api_result:API Design" \
                 "error:$error_result:Error Handling" \
                 "integration:$integration_result:Integration Tests"; do
        
        local name result label
        name=$(echo "$check" | cut -d: -f1)
        result=$(echo "$check" | cut -d: -f2)
        label=$(echo "$check" | cut -d: -f3)
        
        if [ "$result" -eq 0 ]; then
            echo "- ✅ $label: PASSED" >> "$REPORT_FILE"
            print_success "$label: PASSED"
            passed_checks=$((passed_checks + 1))
        else
            echo "- ⚠️  $label: ISSUES" >> "$REPORT_FILE"
            print_warning "$label: ISSUES"
        fi
    done
    
    local score=$((passed_checks * 100 / total_checks))
    
    {
        echo ""
        echo "**Quality Score: $score% ($passed_checks/$total_checks checks passed)**"
        echo ""
    } >> "$REPORT_FILE"
    
    print_info "Overall Quality Score: $score% ($passed_checks/$total_checks)"
    print_info "Full report saved to: $REPORT_FILE"
    
    # Return 0 if score is acceptable (>= 75%), 1 otherwise
    if [ $score -ge 75 ]; then
        return 0
    else
        return 1
    fi
}

# Main function
main() {
    setup_temp_dir
    
    print_header "🚀 Claude Code Enhanced Quality Analysis"
    print_info "Comprehensive quality checks on staged Python files..."
    
    # Check if we're in a git repository
    if ! is_git_repo; then
        print_warning "Not in a git repository - skipping checks"
        exit 0
    fi
    
    # Get staged Python files
    staged_files=()
    while IFS= read -r file; do
        staged_files+=("$file")
    done < <(get_staged_python_files)
    
    if [ ${#staged_files[@]} -eq 0 ]; then
        print_info "No staged Python files to analyze"
        exit 0
    fi
    
    print_info "Found ${#staged_files[@]} staged Python file(s):"
    for file in "${staged_files[@]}"; do
        echo "  • $file"
    done
    echo
    
    # Track all results
    local validation_result=0 deadcode_result=0 complexity_result=0
    local security_result=0 docs_result=0 api_result=0
    local error_result=0 integration_result=0
    
    # Run all checks
    [ "$CHECK_VALIDATION" -eq 1 ] && { run_enhanced_validation "${staged_files[@]}" || validation_result=$?; }
    [ "$CHECK_DEADCODE" -eq 1 ] && { run_deadcode_check "${staged_files[@]}" || deadcode_result=$?; }
    [ "$CHECK_COMPLEXITY" -eq 1 ] && { run_complexity_check "${staged_files[@]}" || complexity_result=$?; }
    [ "$CHECK_SECURITY" -eq 1 ] && { run_security_check "${staged_files[@]}" || security_result=$?; }
    [ "$CHECK_DOCUMENTATION" -eq 1 ] && { run_documentation_check "${staged_files[@]}" || docs_result=$?; }
    [ "$CHECK_API_DESIGN" -eq 1 ] && { run_api_design_check "${staged_files[@]}" || api_result=$?; }
    [ "$CHECK_ERROR_HANDLING" -eq 1 ] && { run_error_handling_check "${staged_files[@]}" || error_result=$?; }
    [ "$CHECK_INTEGRATION" -eq 1 ] && { run_integration_check "${staged_files[@]}" || integration_result=$?; }
    
    # Generate commit message suggestions
    [ "$SUGGEST_COMMIT_MSG" -eq 1 ] && suggest_commit_message
    
    # Generate comprehensive summary
    generate_enhanced_summary "$validation_result" "$deadcode_result" "$complexity_result" \
                             "$security_result" "$docs_result" "$api_result" \
                             "$error_result" "$integration_result"
    
    # Always exit 0 for stop hooks (informational only)
    exit 0
}

# Run main function
main "$@"