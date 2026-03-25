#!/bin/bash
# =============================================================================
# Common utility functions
# =============================================================================

# Prevent double-sourcing
[[ -n "${_UTILS_LOADED:-}" ]] && return 0
_UTILS_LOADED=1

# Source dependencies
SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "${SCRIPT_LIB_DIR}/colors.sh"

# -----------------------------------------------------------------------------
# Spinner / Progress Indicators
# -----------------------------------------------------------------------------

# Global spinner PID tracker
_SPINNER_PID=""

# Start a spinner with a message
# Usage: start_spinner "Loading..."
start_spinner() {
    local message="${1:-Working...}"
    
    # Don't show spinner in quiet mode or non-interactive terminals
    [[ "${QUIET:-false}" == "true" ]] && return 0
    [[ ! -t 1 ]] && return 0
    
    # Kill any existing spinner
    stop_spinner 2>/dev/null
    
    (
        local i=0
        local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
        local len=${#chars}
        
        while true; do
            printf "\r${BLUE}%s${NC} %s" "${chars:$i:1}" "$message"
            i=$(( (i + 1) % len ))
            sleep 0.1
        done
    ) &
    _SPINNER_PID=$!
    
    # Disable job control messages
    disown $_SPINNER_PID 2>/dev/null
}

# Stop the spinner and optionally print a status
# Usage: stop_spinner [status_message]
stop_spinner() {
    local status="${1:-}"
    
    if [[ -n "$_SPINNER_PID" ]]; then
        kill "$_SPINNER_PID" 2>/dev/null
        wait "$_SPINNER_PID" 2>/dev/null
        _SPINNER_PID=""
        
        # Clear the line
        printf "\r\033[K"
    fi
    
    [[ -n "$status" ]] && echo -e "$status"
}

# Run a command with a spinner
# Usage: run_with_spinner "message" command args...
run_with_spinner() {
    local message="$1"
    shift
    
    start_spinner "$message"
    
    local output
    local exit_code
    
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        stop_spinner
        print_info "$message"
        "$@"
        exit_code=$?
    else
        output=$("$@" 2>&1)
        exit_code=$?
    fi
    
    if [[ $exit_code -eq 0 ]]; then
        stop_spinner
        print_success "$message"
    else
        stop_spinner
        print_error "$message"
        [[ -n "$output" ]] && echo "$output" >&2
    fi
    
    return $exit_code
}

# -----------------------------------------------------------------------------
# User Interaction
# -----------------------------------------------------------------------------

# Ask for confirmation
# Usage: confirm "Are you sure?" && do_something
confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-n}"  # y or n
    
    local yn_prompt
    if [[ "$default" == "y" ]]; then
        yn_prompt="[Y/n]"
    else
        yn_prompt="[y/N]"
    fi
    
    echo -n -e "${YELLOW}${prompt}${NC} ${yn_prompt} "
    read -r response
    
    case "${response,,}" in
        y|yes) return 0 ;;
        n|no)  return 1 ;;
        "")
            [[ "$default" == "y" ]] && return 0
            return 1
            ;;
        *)     return 1 ;;
    esac
}

# Prompt for input with a default value
# Usage: value=$(prompt "Enter value" "default")
prompt() {
    local message="$1"
    local default="${2:-}"
    local response
    
    if [[ -n "$default" ]]; then
        echo -n -e "${BLUE}${message}${NC} [${default}]: "
    else
        echo -n -e "${BLUE}${message}${NC}: "
    fi
    
    read -r response
    echo "${response:-$default}"
}

# Select from a list of options
# Usage: choice=$(select_option "Choose one" "option1" "option2" "option3")
select_option() {
    local prompt="$1"
    shift
    local options=("$@")
    local i=1
    
    echo -e "${BLUE}${prompt}${NC}"
    for opt in "${options[@]}"; do
        echo "  $i) $opt"
        ((i++))
    done
    
    while true; do
        echo -n "Enter choice [1-${#options[@]}]: "
        read -r choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
            echo "${options[$((choice-1))]}"
            return 0
        fi
        
        print_error "Invalid selection. Please enter a number between 1 and ${#options[@]}"
    done
}

# -----------------------------------------------------------------------------
# String Utilities
# -----------------------------------------------------------------------------

# Convert string to lowercase
lowercase() {
    echo "${1,,}"
}

# Convert string to uppercase
uppercase() {
    echo "${1^^}"
}

# Trim whitespace from string
trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "$var"
}

# Check if string contains substring
contains() {
    local string="$1"
    local substring="$2"
    [[ "$string" == *"$substring"* ]]
}

# Join array elements with delimiter
# Usage: joined=$(join_by "," "${array[@]}")
join_by() {
    local delimiter="$1"
    shift
    local first="$1"
    shift
    printf '%s' "$first" "${@/#/$delimiter}"
}

# -----------------------------------------------------------------------------
# File Utilities
# -----------------------------------------------------------------------------

# Check if a command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Create directory if it doesn't exist
ensure_dir() {
    local dir="$1"
    [[ -d "$dir" ]] || mkdir -p "$dir"
}

# Get the absolute path of a file/directory
abs_path() {
    local path="$1"
    
    if [[ -d "$path" ]]; then
        (cd "$path" && pwd)
    elif [[ -f "$path" ]]; then
        local dir
        dir=$(dirname "$path")
        echo "$(cd "$dir" && pwd)/$(basename "$path")"
    else
        echo "$path"
    fi
}

# Safe sed for both macOS and Linux
safe_sed() {
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------

# Register cleanup function to be called on exit
_CLEANUP_FUNCTIONS=()

register_cleanup() {
    _CLEANUP_FUNCTIONS+=("$1")
}

# Run all registered cleanup functions
run_cleanup() {
    stop_spinner 2>/dev/null
    
    for func in "${_CLEANUP_FUNCTIONS[@]}"; do
        $func 2>/dev/null
    done
}

# Set trap for cleanup
trap run_cleanup EXIT INT TERM
