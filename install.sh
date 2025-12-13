#!/usr/bin/env bash

# Claude Code Delegation System - Installation Script
# This script installs the delegation system to the specified directory

set -euo pipefail

# Get the directory where this script is located
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Directories and files to copy
readonly DIRS_TO_COPY=("agents" "commands" "hooks" "output-styles" "scripts" "system-prompts")
readonly FILES_TO_COPY=("settings.json")

# Hooks that need to be made executable
readonly EXECUTABLE_HOOKS=(
    "hooks/PreToolUse/require_delegation.sh"
    "hooks/UserPromptSubmit/clear-delegation-sessions.sh"
    "hooks/PostToolUse/python_posttooluse_hook.sh"
    "hooks/stop/python_stop_hook.sh"
    "scripts/statusline.sh"
)

# Print colored message
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_success() { print_message "$GREEN" "✓ $1"; }
print_error() { print_message "$RED" "✗ $1"; }
print_info() { print_message "$BLUE" "ℹ $1"; }
print_warning() { print_message "$YELLOW" "⚠ $1"; }

# Print usage information
print_usage() {
    cat << EOF
Usage: $0 [TARGET_DIR]

Install the Claude Code Delegation System.

Arguments:
  TARGET_DIR    Target directory for installation (default: ~)
                System will be installed to TARGET_DIR/.claude/

Examples:
  $0              # Install to ~/.claude/
  $0 /opt/claude  # Install to /opt/claude/.claude/

EOF
}

# Validate source directory
validate_source() {
    print_info "Validating source files..."

    local missing_items=()

    # Check directories
    for dir in "${DIRS_TO_COPY[@]}"; do
        if [[ ! -d "$SCRIPT_DIR/$dir" ]]; then
            missing_items+=("directory: $dir")
        fi
    done

    # Check files
    for file in "${FILES_TO_COPY[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$file" ]]; then
            missing_items+=("file: $file")
        fi
    done

    if [[ ${#missing_items[@]} -gt 0 ]]; then
        print_error "Missing source files or directories:"
        for item in "${missing_items[@]}"; do
            echo "  - $item"
        done
        return 1
    fi

    print_success "All source files found"
    return 0
}

# Validate target directory
validate_target() {
    local target_dir=$1

    print_info "Validating target directory: $target_dir"

    # Expand tilde
    target_dir="${target_dir/#\~/$HOME}"

    # Check if target directory exists or can be created
    if [[ ! -d "$target_dir" ]]; then
        print_error "Target directory does not exist: $target_dir"
        return 1
    fi

    # Check write permissions
    if [[ ! -w "$target_dir" ]]; then
        print_error "No write permission for target directory: $target_dir"
        return 1
    fi

    print_success "Target directory is valid and writable"
    return 0
}

# Create directory structure
create_directory_structure() {
    local claude_dir=$1

    print_info "Creating directory structure..."

    if [[ ! -d "$claude_dir" ]]; then
        if mkdir -p "$claude_dir"; then
            print_success "Created directory: $claude_dir"
        else
            print_error "Failed to create directory: $claude_dir"
            return 1
        fi
    else
        print_info "Directory already exists: $claude_dir"
    fi

    # Create subdirectories
    for dir in "${DIRS_TO_COPY[@]}"; do
        local target_subdir="$claude_dir/$dir"
        if [[ ! -d "$target_subdir" ]]; then
            if mkdir -p "$target_subdir"; then
                print_success "Created subdirectory: $dir"
            else
                print_error "Failed to create subdirectory: $dir"
                return 1
            fi
        fi
    done

    return 0
}

# Copy files and directories
copy_files() {
    local claude_dir=$1

    print_info "Copying delegation system files..."

    # Copy directories
    for dir in "${DIRS_TO_COPY[@]}"; do
        print_info "Copying $dir/..."
        if cp -r "$SCRIPT_DIR/$dir"/* "$claude_dir/$dir/" 2>/dev/null; then
            print_success "Copied $dir/"
        else
            print_warning "No files found in $dir/ or copy failed"
        fi
    done

    # Copy individual files
    for file in "${FILES_TO_COPY[@]}"; do
        print_info "Copying $file..."
        if cp "$SCRIPT_DIR/$file" "$claude_dir/$file"; then
            print_success "Copied $file"
        else
            print_error "Failed to copy $file"
            return 1
        fi
    done

    return 0
}

# Make hook scripts executable
make_hooks_executable() {
    local claude_dir=$1

    print_info "Making hook scripts executable..."

    local failed_hooks=()

    for hook in "${EXECUTABLE_HOOKS[@]}"; do
        local hook_path="$claude_dir/$hook"
        if [[ -f "$hook_path" ]]; then
            if chmod +x "$hook_path"; then
                print_success "Made executable: $hook"
            else
                print_error "Failed to chmod: $hook"
                failed_hooks+=("$hook")
            fi
        else
            print_warning "Hook not found: $hook"
        fi
    done

    if [[ ${#failed_hooks[@]} -gt 0 ]]; then
        print_error "Failed to make some hooks executable"
        return 1
    fi

    return 0
}

# Main installation function
main() {
    # Parse arguments
    local target_dir="${1:-~}"

    # Show help if requested
    if [[ "$target_dir" == "-h" || "$target_dir" == "--help" ]]; then
        print_usage
        exit 0
    fi

    # Expand tilde
    target_dir="${target_dir/#\~/$HOME}"
    local claude_dir="$target_dir/.claude"

    print_info "=========================================="
    print_info "Claude Code Delegation System Installer"
    print_info "=========================================="
    echo
    print_info "Installation target: $claude_dir"
    echo

    # Validate source files
    if ! validate_source; then
        print_error "Installation aborted: Source validation failed"
        exit 1
    fi
    echo

    # Validate target directory
    if ! validate_target "$target_dir"; then
        print_error "Installation aborted: Target validation failed"
        exit 1
    fi
    echo

    # Create directory structure
    if ! create_directory_structure "$claude_dir"; then
        print_error "Installation aborted: Failed to create directory structure"
        exit 1
    fi
    echo

    # Copy files
    if ! copy_files "$claude_dir"; then
        print_error "Installation aborted: Failed to copy files"
        exit 1
    fi
    echo

    # Make hooks executable
    if ! make_hooks_executable "$claude_dir"; then
        print_error "Installation aborted: Failed to make hooks executable"
        exit 1
    fi
    echo

    # Print success summary
    print_success "=========================================="
    print_success "Installation completed successfully!"
    print_success "=========================================="
    echo
    print_info "Installation location: $claude_dir"
    echo
    print_info "Next steps:"
    echo "  1. Verify installation: ls -la $claude_dir"
    echo "  2. Test delegation: claude '/delegate test task'"
    echo "  3. Read documentation: cat $claude_dir/../CLAUDE.md"
    echo
    print_info "For debug mode, run:"
    echo "  export DEBUG_DELEGATION_HOOK=1"
    echo "  tail -f /tmp/delegation_hook_debug.log"
    echo

    exit 0
}

# Run main function
main "$@"
