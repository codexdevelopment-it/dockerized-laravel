#!/usr/bin/env bash
# =============================================================================
# Small, dependency-free helpers (bash 3.2 compatible: macOS default shell).
# =============================================================================

[[ -n "${_UTILS_LOADED:-}" ]] && return 0
_UTILS_LOADED=1

SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "${SCRIPT_LIB_DIR}/colors.sh"

command_exists() { command -v "$1" &>/dev/null; }

lowercase() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

# confirm "Question?" [default y|n]. Answers "no" when stdin is not a TTY,
# unless DOCK_ASSUME_YES=true.
confirm() {
    local prompt="${1:-Continue?}" default="${2:-n}" hint="[y/N]" response
    [[ "$default" == "y" ]] && hint="[Y/n]"

    if [[ "${DOCK_ASSUME_YES:-false}" == "true" ]]; then
        return 0
    fi
    if [[ ! -t 0 ]]; then
        print_warning "${prompt} (no TTY, assuming 'no'; pass -y to skip)"
        return 1
    fi

    echo -n -e "${YELLOW}${prompt}${NC} ${hint} "
    read -r response
    case "$(lowercase "$response")" in
        y|yes) return 0 ;;
        "")    [[ "$default" == "y" ]] ;;
        *)     return 1 ;;
    esac
}

# In-place sed that works with both BSD (macOS) and GNU sed.
safe_sed() {
    if sed --version &>/dev/null; then
        sed -i "$@"
    else
        sed -i '' "$@"
    fi
}

# Escape a string for use as the replacement part of a sed s||| command.
sed_escape() { printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'; }

# set_env_value <file> <KEY> <value>: replace KEY=... or append it.
set_env_value() {
    local file="$1" key="$2" value
    value="$(sed_escape "$3")"
    if grep -qE "^${key}=" "$file" 2>/dev/null; then
        safe_sed "s|^${key}=.*|${key}=${value}|" "$file"
    else
        printf '%s=%s\n' "$key" "$3" >> "$file"
    fi
}

# get_env_value <file> <KEY>: raw value of KEY from a dotenv file (quotes stripped).
get_env_value() {
    local line
    line="$(grep -E "^${2}=" "$1" 2>/dev/null | tail -n1)"
    line="${line#*=}"
    line="${line#\"}"; line="${line%\"}"
    line="${line#\'}"; line="${line%\'}"
    printf '%s' "$line"
}

# Random base64 string of N bytes without depending on openssl.
random_base64() {
    head -c "${1:-32}" /dev/urandom | base64 | tr -d '\n'
}

# abs_path <path> [base]: absolute path, relative paths resolved against base.
abs_path() {
    local path="$1" base="${2:-$(pwd)}"
    case "$path" in
        /*) ;;
        "~"/*) path="${HOME}/${path#\~/}" ;;
        *)  path="${base%/}/${path#./}" ;;
    esac
    printf '%s' "${path%/}"
}
