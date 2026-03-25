#!/bin/bash
# =============================================================================
# Color definitions and output formatting utilities
# =============================================================================

# Prevent double-sourcing
[[ -n "${_COLORS_LOADED:-}" ]] && return 0
_COLORS_LOADED=1

# -----------------------------------------------------------------------------
# Color Definitions
# -----------------------------------------------------------------------------
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    # Standard colors
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly MAGENTA='\033[0;35m'
    readonly CYAN='\033[0;36m'
    readonly WHITE='\033[1;37m'
    readonly GRAY='\033[0;90m'
    
    # Formatting
    readonly BOLD='\033[1m'
    readonly DIM='\033[2m'
    readonly UNDERLINE='\033[4m'
    readonly NC='\033[0m'  # No Color / Reset
    
    # Status colors
    readonly SUCCESS="${GREEN}"
    readonly WARNING="${YELLOW}"
    readonly ERROR="${RED}"
    readonly INFO="${BLUE}"
else
    # No color support
    readonly RED='' GREEN='' YELLOW='' BLUE='' MAGENTA='' CYAN='' WHITE='' GRAY=''
    readonly BOLD='' DIM='' UNDERLINE='' NC=''
    readonly SUCCESS='' WARNING='' ERROR='' INFO=''
fi

# -----------------------------------------------------------------------------
# Emoji/Symbols (with fallbacks)
# -----------------------------------------------------------------------------
readonly CHECKMARK="✓"
readonly CROSSMARK="✗"
readonly ARROW="→"
readonly BULLET="•"
readonly SPINNER_CHARS="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"

# Emoji icons
readonly ICON_DOCKER="🐳"
readonly ICON_ROCKET="🚀"
readonly ICON_GEAR="⚙️"
readonly ICON_FOLDER="📁"
readonly ICON_CHECK="✅"
readonly ICON_WARN="⚠️"
readonly ICON_ERROR="❌"
readonly ICON_INFO="ℹ️"
readonly ICON_PACKAGE="📦"
readonly ICON_DATABASE="🗄️"
readonly ICON_GLOBE="🌐"
readonly ICON_SUCCESS="✓"
readonly ICON_BULLET="•"

# -----------------------------------------------------------------------------
# Output Functions
# -----------------------------------------------------------------------------

# Print a message (respects quiet mode)
print_msg() {
    [[ "${QUIET:-false}" == "true" ]] && return 0
    echo -e "$*"
}

# Print only in verbose mode (to stderr so it doesn't interfere with command capture)
print_verbose() {
    [[ "${VERBOSE:-false}" == "true" ]] && echo -e "${DIM}$*${NC}" >&2
}

# Print a debug message (only when DEBUG=true)
print_debug() {
    [[ "${DEBUG:-false}" == "true" ]] && echo -e "${GRAY}[DEBUG] $*${NC}" >&2
}

# Standard status messages
print_success() {
    print_msg "${GREEN}${CHECKMARK}${NC} $*"
}

print_error() {
    echo -e "${RED}${CROSSMARK}${NC} $*" >&2
}

print_warning() {
    print_msg "${YELLOW}${ICON_WARN}${NC} $*"
}

print_info() {
    print_msg "${BLUE}${BULLET}${NC} $*"
}

# Print a header box
print_header() {
    local title="$1"
    
    [[ "${QUIET:-false}" == "true" ]] && return 0
    
    echo ""
    echo -e "${CYAN}╭──────────────────────────────────────────╮${NC}"
    echo -e "${CYAN}│${NC}  ${BOLD}${ICON_DOCKER} ${title}${NC}"
    echo -e "${CYAN}╰──────────────────────────────────────────╯${NC}"
    echo ""
}

# Print a section header
print_section() {
    [[ "${QUIET:-false}" == "true" ]] && return 0
    echo ""
    echo -e "${BOLD}${BLUE}$1${NC}"
    echo -e "${DIM}$( printf '─%.0s' $(seq 1 40) )${NC}"
}

# Print a key-value pair
print_kv() {
    local key="$1"
    local value="$2"
    local key_width=${3:-20}
    
    [[ "${QUIET:-false}" == "true" ]] && return 0
    printf "${GRAY}%-${key_width}s${NC} %s\n" "$key:" "$value"
}

# Print a tree-style item
print_tree_item() {
    local item="$1"
    local status="$2"
    local is_last="${3:-false}"
    local prefix="${4:-}"
    
    [[ "${QUIET:-false}" == "true" ]] && return 0
    
    if [[ "$is_last" == "true" ]]; then
        echo -e "${prefix}  └── ${item} ${status}"
    else
        echo -e "${prefix}  ├── ${item} ${status}"
    fi
}

# Print a status line with result
print_status() {
    local message="$1"
    local status="$2"  # success, error, warning, running
    local width=50
    local msg_len=${#message}
    local dots=$(( width - msg_len ))
    
    [[ "${QUIET:-false}" == "true" ]] && return 0
    
    printf "%s" "$message"
    printf "${DIM}%s${NC}" "$(printf '.%.0s' $(seq 1 $dots))"
    
    case "$status" in
        success) echo -e " ${GREEN}${CHECKMARK} done${NC}" ;;
        error)   echo -e " ${RED}${CROSSMARK} failed${NC}" ;;
        warning) echo -e " ${YELLOW}! warning${NC}" ;;
        running) echo -e " ${BLUE}● running${NC}" ;;
        skipped) echo -e " ${GRAY}- skipped${NC}" ;;
        *)       echo -e " $status" ;;
    esac
}

# Print final ready message
print_ready() {
    local url="${1:-http://localhost:8000}"
    
    [[ "${QUIET:-false}" == "true" ]] && return 0
    
    echo ""
    echo -e "${GREEN}${ICON_ROCKET} Application ready at ${BOLD}${url}${NC}"
    echo ""
}

# Print a newline (respects quiet)
print_nl() {
    [[ "${QUIET:-false}" == "true" ]] && return 0
    echo ""
}
