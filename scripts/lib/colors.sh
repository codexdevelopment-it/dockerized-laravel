#!/usr/bin/env bash
# =============================================================================
# Colors, icons and output helpers.
# Colors are disabled when stdout is not a TTY, TERM=dumb or NO_COLOR is set.
# Everything except errors respects QUIET; verbose/debug go to stderr.
# =============================================================================

# shellcheck disable=SC2034  # variables are used by the scripts sourcing this file
[[ -n "${_COLORS_LOADED:-}" ]] && return 0
_COLORS_LOADED=1

if [[ -t 1 && "${TERM:-}" != "dumb" && -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m'
    CYAN='\033[0;36m' GRAY='\033[0;90m' BOLD='\033[1m' DIM='\033[2m' NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' GRAY='' BOLD='' DIM='' NC=''
fi

CHECKMARK="✓"
CROSSMARK="✗"
BULLET="•"
ICON_DOCKER="🐳"
ICON_GEAR="⚙️ "
ICON_PACKAGE="📦"
ICON_WARN="⚠️ "

_is_quiet() { [[ "${QUIET:-false}" == "true" ]]; }

print_msg()     { _is_quiet || echo -e "$*"; }
print_nl()      { _is_quiet || echo ""; }
print_success() { print_msg "${GREEN}${CHECKMARK}${NC} $*"; }
print_info()    { print_msg "${BLUE}${BULLET}${NC} $*"; }
print_warning() { _is_quiet || echo -e "${YELLOW}${ICON_WARN}${NC}$*" >&2; }
print_error()   { echo -e "${RED}${CROSSMARK}${NC} $*" >&2; }
print_verbose() { [[ "${VERBOSE:-false}" == "true" ]] && echo -e "${DIM}$*${NC}" >&2; return 0; }
print_debug()   { [[ "${DEBUG:-false}" == "true" ]] && echo -e "${GRAY}[debug] $*${NC}" >&2; return 0; }

print_header() {
    _is_quiet && return 0
    echo ""
    echo -e "${CYAN}╭──────────────────────────────────────────╮${NC}"
    echo -e "${CYAN}│${NC}  ${BOLD}${ICON_DOCKER} $1${NC}"
    echo -e "${CYAN}╰──────────────────────────────────────────╯${NC}"
}

print_section() {
    _is_quiet && return 0
    echo ""
    echo -e "${BOLD}${BLUE}$1${NC}"
    echo -e "${DIM}────────────────────────────────────────${NC}"
}

# print_kv <key> <value> [key_width]
print_kv() {
    _is_quiet && return 0
    printf "  ${GRAY}%-${3:-16}s${NC} %s\n" "$1" "$2"
}
