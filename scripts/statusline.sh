#!/bin/bash
################################################################################
# Enhanced Claude Code Statusline with Accurate Token Tracking
# Fixed progress bar rendering and context tracking with better debugging
################################################################################

# Configuration
readonly SUMMARY_BASE_DIR="$HOME/.claude/sessions"
readonly DEBUG_LOG="/tmp/statusline_debug.log"

# Enable debug logging
debug_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" >> "$DEBUG_LOG" 2>/dev/null
}

# Function to create progress bar for context usage
create_progress_bar() {
    local usage_rate="$1"
    local used_tokens="$2" 
    local limit_tokens="$3"
    
    # Convert percentage to integer for calculations
    local percentage
    percentage=$(printf "%.0f" "$usage_rate" 2>/dev/null || echo "0")
    
    # Ensure percentage is within bounds
    if [[ $percentage -gt 100 ]]; then
        percentage=100
    elif [[ $percentage -lt 0 ]]; then
        percentage=0
    fi
    
    # Calculate filled blocks (20 total blocks)
    local filled_blocks=$((percentage * 20 / 100))
    local empty_blocks=$((20 - filled_blocks))
    
    # Use ASCII characters for better compatibility
    local filled_part=""
    local empty_part=""
    
    # Build filled portion using █ (U+2588)
    for ((i=0; i<filled_blocks; i++)); do
        filled_part="${filled_part}█"
    done
    
    # Build empty portion using ░ (U+2591)
    for ((i=0; i<empty_blocks; i++)); do
        empty_part="${empty_part}░"
    done
    
    # Ensure tokens are valid numbers
    [[ ! "$used_tokens" =~ ^[0-9]+$ ]] && used_tokens=0
    [[ ! "$limit_tokens" =~ ^[0-9]+$ ]] && limit_tokens=200000
    
    # Format tokens with k/M suffixes for readability
    local formatted_used formatted_limit
    if [[ $used_tokens -ge 1000000 ]]; then
        formatted_used=$(printf "%.1fM" "$(echo "scale=1; $used_tokens / 1000000" | bc -l 2>/dev/null || echo "0")")
        formatted_used=${formatted_used%.0M}M  # Remove .0 if present
    elif [[ $used_tokens -ge 1000 ]]; then
        formatted_used=$(printf "%.0fk" "$(echo "scale=0; $used_tokens / 1000" | bc -l 2>/dev/null || echo "0")")
    else
        formatted_used="$used_tokens"
    fi
    
    if [[ $limit_tokens -ge 1000000 ]]; then
        formatted_limit=$(printf "%.1fM" "$(echo "scale=1; $limit_tokens / 1000000" | bc -l 2>/dev/null || echo "0")")
        formatted_limit=${formatted_limit%.0M}M  # Remove .0 if present
    elif [[ $limit_tokens -ge 1000 ]]; then
        formatted_limit=$(printf "%.0fk" "$(echo "scale=0; $limit_tokens / 1000" | bc -l 2>/dev/null || echo "0")")
    else
        formatted_limit="$limit_tokens"
    fi
    
    # Choose color based on usage rate
    local color_code reset_code
    if [[ $percentage -ge 70 ]]; then
        color_code='\033[31m'  # Red
    elif [[ $percentage -ge 60 ]]; then
        color_code='\033[33m'  # Yellow/Orange  
    elif [[ $percentage -ge 40 ]]; then
        color_code='\033[93m'  # Bright Yellow
    else
        color_code='\033[32m'  # Green
    fi
    reset_code='\033[0m'
    
    # Format percentage to one decimal place
    local formatted_percentage
    formatted_percentage=$(printf "%.1f" "$usage_rate" 2>/dev/null || echo "0.0")
    
    # Ensure we always have valid format strings
    [[ -z "$formatted_used" ]] && formatted_used="0"
    [[ -z "$formatted_limit" ]] && formatted_limit="200k"
    
    # Return the complete progress bar
    echo -e "${color_code}[${filled_part}${empty_part}] ${formatted_percentage}% (${formatted_used}/${formatted_limit})${reset_code}"
}

# Function to find session file
find_session_file() {
    local session_id="$1"
    local current_dir="$2"
    
    debug_log "Looking for session: $session_id in dir: $current_dir"
    
    # Method 1: Direct lookup in .claude/sessions
    local direct_file="$HOME/.claude/sessions/${session_id}.jsonl"
    if [[ -f "$direct_file" ]]; then
        debug_log "Found session file (direct): $direct_file"
        echo "$direct_file"
        return 0
    fi
    
    # Method 2: Project-based lookup (with tilde)
    local project_dir=$(echo "$current_dir" | sed "s|$HOME|~|g" | sed 's|/|-|g' | sed 's|^-||')
    local project_file="$HOME/.claude/projects/-${project_dir}/${session_id}.jsonl"
    if [[ -f "$project_file" ]]; then
        debug_log "Found session file (project with tilde): $project_file"
        echo "$project_file"
        return 0
    fi
    
    # Method 3: Project-based lookup (without tilde)
    local alt_project_dir=$(echo "$current_dir" | sed 's|/|-|g' | sed 's|^-||')
    local alt_project_file="$HOME/.claude/projects/-${alt_project_dir}/${session_id}.jsonl"
    if [[ -f "$alt_project_file" ]]; then
        debug_log "Found session file (project without tilde): $alt_project_file"
        echo "$alt_project_file"
        return 0
    fi
    
    # Method 4: Search in all .claude subdirectories
    local found_file=$(find "$HOME/.claude" -name "${session_id}.jsonl" -type f 2>/dev/null | head -1)
    if [[ -n "$found_file" ]]; then
        debug_log "Found session file (search): $found_file"
        echo "$found_file"
        return 0
    fi
    
    debug_log "No session file found for $session_id"
    return 1
}

# Function to calculate actual context usage from session file
calculate_actual_context_usage() {
    local input="$1"
    local session_id current_dir session_file
    
    # Get session info from input JSON
    session_id=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null)
    current_dir=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null)
    
    debug_log "Session ID: $session_id, Current Dir: $current_dir"
    
    if [[ -n "$session_id" ]] && command -v jq >/dev/null 2>&1; then
        # Determine max context based on model
        local model_name=$(echo "$input" | jq -r '.model.display_name // .model.id // ""' 2>/dev/null)
        local max_context=200000  # Default to 200k
        
        debug_log "Model: $model_name"
        
        # Check for different model context sizes
        if [[ "$model_name" == *"with 1M token context"* ]] || [[ "$model_name" == *"1M"* ]]; then
            max_context=1000000  # 1M tokens
        elif [[ "$model_name" == *"opus"* ]] || [[ "$model_name" == *"Opus"* ]]; then
            max_context=200000  # 200k for Opus
        elif [[ "$model_name" == *"sonnet"* ]] || [[ "$model_name" == *"Sonnet"* ]]; then
            max_context=200000  # 200k for older Sonnet
        fi
        
        debug_log "Max context: $max_context"
        
        # Find the session file
        session_file=$(find_session_file "$session_id" "$current_dir")
        
        if [[ -f "$session_file" ]]; then
            debug_log "Processing session file: $session_file"
            
            # Check for context reset events
            local last_reset_line=0
            local reset_lines=$(grep -n '"content":\s*"/\(clear\|compact\)"' "$session_file" 2>/dev/null | tail -1 | cut -d: -f1)
            if [[ -n "$reset_lines" ]]; then
                last_reset_line=$reset_lines
                debug_log "Found reset at line: $last_reset_line"
            fi
            
            # Get all token usage entries
            local token_entries
            if [[ $last_reset_line -gt 0 ]]; then
                # Get entries after the reset
                token_entries=$(tail -n +$((last_reset_line + 1)) "$session_file" | \
                    jq -r 'select(.message.usage) | 
                    "\(.message.usage.input_tokens // 0):\(.message.usage.cache_read_input_tokens // 0):\(.message.usage.cache_creation_input_tokens // 0):\(.message.usage.output_tokens // 0)"' 2>/dev/null)
            else
                # Get all entries
                token_entries=$(jq -r 'select(.message.usage) | 
                    "\(.message.usage.input_tokens // 0):\(.message.usage.cache_read_input_tokens // 0):\(.message.usage.cache_creation_input_tokens // 0):\(.message.usage.output_tokens // 0)"' "$session_file" 2>/dev/null)
            fi
            
            debug_log "Token entries found: $(echo "$token_entries" | wc -l)"
            
            # Get the last entry (most recent tokens)
            if [[ -n "$token_entries" ]]; then
                local last_entry=$(echo "$token_entries" | tail -1)
                debug_log "Last token entry: $last_entry"
                
                if [[ -n "$last_entry" ]]; then
                    IFS=':' read -r input_tokens cache_read_tokens cache_create_tokens output_tokens <<< "$last_entry"
                    
                    # Total input tokens = regular input + cache read + cache creation
                    local total_input_tokens=$((input_tokens + cache_read_tokens + cache_create_tokens))
                    
                    debug_log "Tokens - Input: $input_tokens, Cache Read: $cache_read_tokens, Cache Create: $cache_create_tokens, Total: $total_input_tokens"
                    
                    if [[ $total_input_tokens -gt 0 ]]; then
                        # Calculate context usage percentage
                        local context_used_rate
                        context_used_rate=$(echo "scale=1; $total_input_tokens * 100 / $max_context" | bc -l 2>/dev/null || echo "0")
                        
                        # Create progress bar
                        local progress_bar
                        progress_bar=$(create_progress_bar "$context_used_rate" "$total_input_tokens" "$max_context")
                        
                        echo "🧠 $progress_bar"
                        return 0
                    fi
                fi
            else
                debug_log "No token entries found in session file"
            fi
        else
            debug_log "Session file not found"
        fi
    fi
    
    debug_log "Failed to calculate context usage"
    return 1
}

# Clear debug log at start (keep it manageable)
echo "=== Statusline run at $(date) ===" > "$DEBUG_LOG" 2>/dev/null

# Get today's date for cost tracking
TODAY=$(date +%Y%m%d)

# Get today's usage data from ccusage
DAILY_DATA=$(bunx ccusage daily --json --since $TODAY 2>/dev/null)

# Initialize variables
LAST_PROMPT=""

if [ -n "$DAILY_DATA" ] && [ "$DAILY_DATA" != "null" ]; then
    # Extract today's cost from JSON and round to 2 decimal places
    TODAY_COST_RAW=$(echo "$DAILY_DATA" | jq -r '.totals.totalCost // 0' 2>/dev/null)
    TODAY_COST=$(printf "%.2f" $TODAY_COST_RAW 2>/dev/null || echo "0.00")
    
    # Read JSON input from stdin if available
    if [ -t 0 ]; then
        # No stdin input, fallback to defaults
        debug_log "No stdin input, using defaults"
        RAW_MODEL="claude-sonnet-4"
        OUTPUT_STYLE="default"
        CONTEXT_INFO=""
    else
        # Read JSON from stdin
        input=$(cat)
        
        # Debug: save input for troubleshooting
        echo "$input" > /tmp/statusline_input.json 2>/dev/null
        
        RAW_MODEL=$(echo "$input" | jq -r '.model.display_name // .model.id // "Unknown"' 2>/dev/null)
        OUTPUT_STYLE=$(echo "$input" | jq -r '.output_style.name // "default"' 2>/dev/null)
        
        # Get session info from input JSON
        session_id=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null)
        current_dir=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null)
        session_file=$(find_session_file "$session_id" "$current_dir")

        # Then extract the prompt if file exists
        if [[ -f "$session_file" ]]; then
            # Extract user messages with string content (not array content)
            # Use jq without -r to get quoted strings, then remove quotes and convert escape sequences
            PROMPTS=$(jq 'select(.type == "user" and .message.role == "user" and (.message.content | type == "string")) | .message.content' "$session_file" 2>/dev/null | \
                  grep -v '^null$' | \
                  grep -v '^$' | \
                  sed 's/^"//; s/"$//' | \
                  sed 's/\\n/ /g; s/\\t/ /g; s/\\"/"/g' | \
                  grep -v '^MultiEdit operation feedback: - \[/Users/user/\.claude/scripts/python_posttooluse_hook\.sh\]' | \
                  grep -v '^Edit operation feedback: - \[/Users/user/\.claude/scripts/python_posttooluse_hook\.sh\]' | \
                  grep -v '^Caveat: The messages below were generated by the user while running local commands' | \
                  tail -3 | \
                  awk '{a[NR]=$0} END {for(i=NR; i>=1; i--) print a[i]}')  # Reverse to show most recent first
            
            debug_log "Raw prompts: $PROMPTS"
            
            if [[ -n "$PROMPTS" ]]; then
                # Process line by line and build multiline formatted output (already reversed)
                LAST_PROMPT=""
                num=1
                while IFS= read -r prompt; do
                    debug_log "Processing prompt $num: ${prompt:0:250}"
                    
                    # Convert multiline prompts to single line
                    prompt=$(echo "$prompt" | tr '\n' ' ' | sed 's/  */ /g')
                    
                    # Truncate if needed
                    if [[ ${#prompt} -gt 150 ]]; then
                        prompt="${prompt:0:150}..."
                    fi
                    
                    # Add to output with newlines for multiline display
                    if [[ -z "$LAST_PROMPT" ]]; then
                        LAST_PROMPT="[$num] $prompt"
                    else
                        LAST_PROMPT="${LAST_PROMPT}\n[$num] $prompt"
                    fi
                    ((num++))
                done <<< "$PROMPTS"
                
                debug_log "Final formatted: $LAST_PROMPT"
            else
                LAST_PROMPT=""
                debug_log "No prompts found"
            fi
        fi
        
        debug_log "Model from input: $RAW_MODEL, Style: $OUTPUT_STYLE"
        debug_log "Last prompt: ${LAST_PROMPT:0:250}..."
        debug_log "session id: ${session_id}"
        debug_log "current dir: ${current_dir}"
        debug_log "session file: ${session_file}"
        
        # Try to get actual context usage
        CONTEXT_INFO=$(calculate_actual_context_usage "$input")
        
        # If context calculation failed, show minimal indicator
        if [[ -z "$CONTEXT_INFO" ]]; then
            debug_log "Context calculation failed, using fallback"
            # Get model to determine max context
            model_name=$(echo "$input" | jq -r '.model.display_name // .model.id // ""' 2>/dev/null)
            max_context=200000  # Default
            
            if [[ "$model_name" == *"with 1M token context"* ]] || [[ "$model_name" == *"1M"* ]]; then
                max_context=1000000
            fi
            
            # Show empty progress bar
            progress_bar=$(create_progress_bar "0" "0" "$max_context")
            CONTEXT_INFO="🧠 $progress_bar"
        fi
    fi
    
    MODEL="🤖 $RAW_MODEL"
    DAILY_COST="\$${TODAY_COST} today"
else
    # Fallback if ccusage fails
    MODEL="🤖 Unknown"
    DAILY_COST="\$0.00 today"
fi

# Function to shorten CWD path
shorten_cwd() {
    local full_path="$1"
    
    # Check if path contains /dev/
    if [[ "$full_path" == */dev/* ]]; then
        # Extract everything after /dev/
        local after_dev="${full_path#*/dev/}"
        
        # If the result is too long, show last 2-3 components
        local components=(${after_dev//\// })
        local num_components=${#components[@]}
        
        if [[ $num_components -gt 2 ]]; then
            # Show first component and last two
            echo "${components[0]}/.../${components[$((num_components-1))]}"
        else
            echo "$after_dev"
        fi
    else
        # If no /dev/ in path, try other common patterns
        if [[ "$full_path" == */Projects/* ]]; then
            echo "${full_path#*/Projects/}"
        elif [[ "$full_path" == */projects/* ]]; then
            echo "${full_path#*/projects/}"
        elif [[ "$full_path" == "$HOME"/* ]]; then
            # Show path relative to home with ~ and truncate if needed
            local rel_path="${full_path#$HOME/}"
            local components=(${rel_path//\// })
            if [[ ${#components[@]} -gt 3 ]]; then
                echo "~/${components[0]}/.../${components[-1]}"
            else
                echo "~/$rel_path"
            fi
        else
            # Default: show last 2 components
            echo ".../${full_path##*/}"
        fi
    fi
}

# Get git branch
GIT_BRANCH=$(git branch --show-current 2>/dev/null)
if [ -n "$GIT_BRANCH" ]; then
    # Truncate long branch names
    if [ ${#GIT_BRANCH} -gt 60 ]; then
        GIT_BRANCH="${GIT_BRANCH:0:60}..."
    fi
    
    # Add dirty indicator
    if ! git diff --quiet 2>/dev/null; then
        GIT_STATUS="🌿 $GIT_BRANCH ⚡"
    else
        GIT_STATUS="🌿 $GIT_BRANCH ⚡"
    fi
else
    GIT_STATUS="🌿 no-git"
fi

CWD=$(shorten_cwd "$PWD")

# Color codes
# Bright color codes
CYAN='\033[96m'
SHINY_AQUA='\033[38;2;0;255;255m'
ORANGE='\033[93m'
GREEN='\033[92m'
YELLOW='\033[93m'
BLUE='\033[94m'
MAGENTA='\033[95m'
FUCHSIA='\033[38;2;255;0;255m'
HOT_PINK='\033[38;2;255;105;180m'
WHITE='\033[97m'
BG_DARK_PURPLE='\033[48;2;64;32;96m'  # RGB background
FG_BRIGHT_WHITE='\033[97m'
BG_LIGHT_BLUE='\x1b[104m'
BG_PROMPT='\033[48;2;180;50;180m'  # Brighter purple background 
FG_WHITE='\033[97m'                # Bright white text
RESET='\033[0m'

# Original display (no Rich integration)
if [[ -n "$CONTEXT_INFO" ]]; then
    echo -e "${SHINY_AQUA}$MODEL${RESET} | ${BLUE}🎨 $OUTPUT_STYLE${RESET} | ${GREEN}💰 $DAILY_COST${RESET} | $CONTEXT_INFO"
    echo -e "${YELLOW}$GIT_STATUS${RESET} | ${WHITE}📁 $CWD${RESET}"
    # if [[ -n "$LAST_PROMPT" ]]; then
    #      echo -e "💬 ${BG_PROMPT}${FG_WHITE}Recent:"
    #      printf "%b$LAST_PROMPT"
    # fi
else
    echo -e "${SHINY_AQUA}$MODEL${RESET} | ${GREEN}💰 $DAILY_COST${RESET} | ${YELLOW}$GIT_STATUS${RESET} | ${BLUE}🎨 $OUTPUT_STYLE${RESET} | ${WHITE}📁 $CWD${RESET}"
fi