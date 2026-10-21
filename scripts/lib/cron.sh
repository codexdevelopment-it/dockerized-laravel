#!/usr/bin/env bash
# =============================================================================
# Host crontab entries owned by dock (backups, autodeploy).
#
# Each entry ends with a marker comment "# dock-<kind>:<PROJECT_ROOT>:" that
# identifies it; the trailing ':' keeps /srv/app from matching /srv/app2.
# The current crontab is always read completely before `crontab -` replaces it.
# =============================================================================

[[ -n "${_CRON_LOADED:-}" ]] && return 0
_CRON_LOADED=1

SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "${SCRIPT_LIB_DIR}/colors.sh"
source "${SCRIPT_LIB_DIR}/utils.sh"

cron_marker() { printf '# dock-%s:%s:' "$1" "$PROJECT_ROOT"; }

cron_read() { crontab -l 2>/dev/null; }

# cron_entry <kind>: the installed line, empty when there is none.
cron_entry() { command_exists crontab && cron_read | grep -F -- "$(cron_marker "$1")"; }

cron_without() { cron_read | grep -vF -- "$(cron_marker "$1")"; }

# cron_install <kind> <line>: replace this project's <kind> entry with <line>.
cron_install() {
    local others
    others="$(cron_without "$1")"
    { [[ -n "$others" ]] && printf '%s\n' "$others"; printf '%s\n' "$2"; } | crontab -
}

cron_remove() {
    local others
    others="$(cron_without "$1")"
    { [[ -n "$others" ]] && printf '%s\n' "$others"; } | crontab -
}

# Paths end up single-quoted in a crontab line, where ' would break the
# quoting and % means newline.
cron_require_safe_paths() {
    local p
    for p in "$PROJECT_ROOT" "$ENV_FILE"; do
        if [[ "$p" == *[\'%]* ]]; then
            print_error "Paths used by cron can't contain ' or %: ${p}"
            return 1
        fi
    done
}

# cron_dock_command <extra PATH dir|""> <dock args...>: shell command for a
# crontab line. cron runs with a minimal PATH: docker's directory goes first.
cron_dock_command() {
    local extra="$1" path env_flag=""
    shift
    path="$(dirname "$(command -v docker)")"
    [[ -n "$extra" ]] && path="${path}:${extra}"
    [[ "$ENV_FILE" != ".env" ]] && env_flag="-e '${ENV_FILE}' "
    printf "cd '%s' && PATH='%s:/usr/local/bin:/usr/bin:/bin' NO_COLOR=1 ./dock %s%s" \
        "$PROJECT_ROOT" "$path" "$env_flag" "$*"
}
