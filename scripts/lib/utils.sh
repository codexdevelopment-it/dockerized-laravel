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

# EXIT handler shared by dock: releases the lock taken by acquire_lock and
# shows the cursor again (steps hide it).
_HELD_LOCK=""
on_exit() {
    [[ -n "$_HELD_LOCK" ]] && rm -rf "$_HELD_LOCK"
    declare -F ui_cursor_show >/dev/null && ui_cursor_show
    return 0
}

# acquire_lock <dir> <what>: one process at a time, via a lock dir holding the
# owner's pid. Stale locks of dead processes are taken over; a lock already
# owned by this pid (after `exec`) is kept. Released on exit.
acquire_lock() {
    local lock="$1" pid
    mkdir -p "$(dirname "$lock")" || return 1
    if ! mkdir "$lock" 2>/dev/null; then
        pid="$(cat "${lock}/pid" 2>/dev/null)"
        if [[ -n "$pid" && "$pid" != "$$" ]] && kill -0 "$pid" 2>/dev/null; then
            print_error "Another ${2} is running (pid ${pid})"
            return 1
        fi
        rm -rf "$lock" && mkdir "$lock" || return 1
    fi
    echo $$ > "${lock}/pid"
    _HELD_LOCK="$lock"
    trap on_exit EXIT
}

# lock_is_held <dir>: a live process owns the lock.
lock_is_held() {
    local pid
    pid="$(cat "${1}/pid" 2>/dev/null)"
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

# human_size <bytes> -> 512 B | 1.4 MB
human_size() {
    awk -v b="${1:-0}" 'BEGIN { split("B KB MB GB TB", u, " "); i = 1
        while (b >= 1024 && i < 5) { b /= 1024; i++ }
        printf (i == 1 ? "%d %s" : "%.1f %s"), b, u[i] }'
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
