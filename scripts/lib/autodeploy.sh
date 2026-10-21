#!/usr/bin/env bash
# =============================================================================
# Continuous deployment from the host's cron: ./dock autodeploy <command>.
#
# Every AUTODEPLOY_INTERVAL minutes (default 2) cron runs `dock autodeploy run`:
# git fetch origin BRANCH; when origin/BRANCH is ahead of HEAD, run
# `dock deploy -y` (the same deploy as by hand, with the APP_ENV of .env).
# Runs with nothing new print nothing, so the log only holds deploys/errors.
#
# State lives in .git/dock/ (per checkout, never committed, never in the
# image): autodeploy.log, autodeploy-last ("<ok|failed> <sha> <UTC time>"),
# autodeploy-check (time of the last fetch), autodeploy-error (current
# problem, logged once) and deploy.lock.
# A deploy that failed is not retried for the same commit: push a fix or run
# ./dock deploy by hand.
#
# Relies on dock: require_env, require_env_light, dock_state_dir, deploy_lock,
# DOCK_BIN, ENV_FILE.
# =============================================================================

[[ -n "${_AUTODEPLOY_LOADED:-}" ]] && return 0
_AUTODEPLOY_LOADED=1

SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "${SCRIPT_LIB_DIR}/colors.sh"
source "${SCRIPT_LIB_DIR}/utils.sh"
source "${SCRIPT_LIB_DIR}/ui.sh"
source "${SCRIPT_LIB_DIR}/cron.sh"

AUTODEPLOY_DEFAULT_INTERVAL=2
AUTODEPLOY_LOG_MAX_LINES=5000

autodeploy_log()      { echo "$(dock_state_dir)/autodeploy.log"; }
autodeploy_state()    { echo "$(dock_state_dir)/autodeploy-last"; }
autodeploy_checked()  { echo "$(dock_state_dir)/autodeploy-check"; }
autodeploy_error()    { echo "$(dock_state_dir)/autodeploy-error"; }
autodeploy_interval() { echo "${AUTODEPLOY_INTERVAL:-$AUTODEPLOY_DEFAULT_INTERVAL}"; }
autodeploy_branch()   { echo "${BRANCH:-$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)}"; }

# Minutes, 1-59 (a */N cron step).
autodeploy_valid_interval() { [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 59 )); }

autodeploy_schedule() {
    local n
    autodeploy_valid_interval "$(autodeploy_interval)" || { echo "invalid"; return 1; }
    n=$((10#$(autodeploy_interval)))
    if [[ $n -eq 1 ]]; then echo "* * * * *"; else echo "*/${n} * * * *"; fi
}

# AUTODEPLOY=false in .env silences the hint shown by ./dock deploy.
autodeploy_hint_wanted() { ! _is_false "${AUTODEPLOY:-}"; }

# -----------------------------------------------------------------------------
# cron
# -----------------------------------------------------------------------------

autodeploy_cron_entry() { cron_entry autodeploy; }

# git may live outside cron's PATH (/usr/local/bin, /usr/bin, /bin).
autodeploy_cron_line() {
    local git_dir
    git_dir="$(dirname "$(command -v git)")"
    case "$git_dir" in /usr/local/bin|/usr/bin|/bin) git_dir="" ;; esac
    printf '%s %s >> .git/dock/autodeploy.log 2>&1 %s' \
        "$(autodeploy_schedule)" "$(cron_dock_command "$git_dir" autodeploy run)" "$(cron_marker autodeploy)"
}

# Same check cron will do: no ssh-agent, no prompts.
autodeploy_check_fetch() {
    local ssh_cmd
    ssh_cmd="${GIT_SSH_COMMAND:-$(git config core.sshCommand 2>/dev/null || echo ssh)} -o BatchMode=yes"
    env -u SSH_AUTH_SOCK GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="$ssh_cmd" \
        git fetch --quiet origin "$(autodeploy_branch)"
}

autodeploy_trim_log() {
    local log
    log="$(autodeploy_log)"
    [[ -f "$log" ]] || return 0
    if [[ "$(wc -l < "$log")" -gt "$AUTODEPLOY_LOG_MAX_LINES" ]]; then
        tail -n $((AUTODEPLOY_LOG_MAX_LINES / 2)) "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"
    fi
}

# autodeploy_record <ok|failed> <sha> [detail]. deploy records its successes
# too, so a manual deploy clears a failed auto-deploy.
autodeploy_record() {
    mkdir -p "$(dock_state_dir)" || return 0
    printf '%s %s %s %s\n' "$1" "$2" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${3:-}" > "$(autodeploy_state)"
}

autodeploy_say() { echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $*"; }

# Problems that repeat every run (fetch failing, diverged checkout) are
# logged once, and their end is logged too.
autodeploy_problem() {
    [[ "$(cat "$(autodeploy_error)" 2>/dev/null)" == "$1" ]] && return 1
    echo "$1" > "$(autodeploy_error)"
    autodeploy_say "$1"
    return 1
}

autodeploy_no_problem() {
    [[ -f "$(autodeploy_error)" ]] || return 0
    autodeploy_say "Resolved: $(cat "$(autodeploy_error)")"
    rm -f "$(autodeploy_error)"
}

# -----------------------------------------------------------------------------
# Commands
# -----------------------------------------------------------------------------

cmd_autodeploy_run() {
    local branch head target last rc
    require_env_light || return 1
    if is_local_env; then
        print_error "APP_ENV=${APP_ENV}: auto-deploy only runs in staging/production"
        return 1
    fi
    cd "$PROJECT_ROOT" || return 1
    mkdir -p "$(dock_state_dir)"
    # A deploy (by hand or from an earlier run) is still going: next time.
    lock_is_held "$(deploy_lock)" && return 0
    autodeploy_trim_log

    branch="$(autodeploy_branch)"
    export GIT_TERMINAL_PROMPT=0
    if ! git fetch --quiet origin "$branch" 2>/dev/null; then
        autodeploy_problem "git fetch origin ${branch} failed: check the deploy key (./dock autodeploy enable tests it)"
        return 1
    fi
    date -u +%Y-%m-%dT%H:%M:%SZ > "$(autodeploy_checked)"

    head="$(git rev-parse HEAD)"
    target="$(git rev-parse "origin/${branch}")"
    # Up to date, or local commits not on origin: nothing to deploy.
    if [[ "$head" == "$target" ]] || git merge-base --is-ancestor "$target" HEAD 2>/dev/null; then
        autodeploy_no_problem
        return 0
    fi
    if ! git merge-base --is-ancestor HEAD "$target" 2>/dev/null; then
        autodeploy_problem "HEAD diverged from origin/${branch}: fix the checkout by hand (git status), nothing is deployed until then"
        return 1
    fi
    autodeploy_no_problem

    # Failed already: wait for a new commit or a manual deploy.
    last="$(cut -d' ' -f1,2 "$(autodeploy_state)" 2>/dev/null)"
    [[ "$last" == "failed ${target}" ]] && return 0

    echo ""
    autodeploy_say "Deploying ${branch} ${head:0:7} -> ${target:0:7}"
    DOCK_AUTODEPLOY=1 "$DOCK_BIN" -e "$ENV_FILE" deploy --yes
    rc=$?
    if [[ $rc -ne 0 ]]; then
        autodeploy_record failed "$target" "deploy exited with ${rc}"
        autodeploy_say "Deploy failed (exit ${rc}): not retried for ${target:0:7}. Push a fix or run ./dock deploy"
    fi
    return $rc
}

cmd_autodeploy_enable() {
    local interval=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --every)   interval="${2:-}"; shift ;;
            -h|--help) show_command_help autodeploy; return 0 ;;
            *)         print_error "Unknown option for autodeploy enable: $1"; return 1 ;;
        esac
        shift
    done
    if [[ ! -d "${PROJECT_ROOT}/.git" ]]; then
        print_error "${PROJECT_ROOT} is not a git checkout: auto-deploy pulls from origin"
        return 1
    fi
    require_env deploy || return 1
    if is_local_env; then
        print_error "APP_ENV=${APP_ENV}: auto-deploy is for staging/production servers"
        return 1
    fi
    command_exists crontab || { print_error "crontab not found: install cron (Debian/Ubuntu: apt install cron)"; return 1; }
    cron_require_safe_paths || return 1
    cd "$PROJECT_ROOT" || return 1

    if [[ -n "$interval" ]]; then
        autodeploy_valid_interval "$interval" || { print_error "--every takes minutes, 1-59"; return 1; }
        set_env_value "$(env_path)" AUTODEPLOY_INTERVAL "$interval"
        export AUTODEPLOY_INTERVAL="$interval"
    fi
    if ! autodeploy_valid_interval "$(autodeploy_interval)"; then
        print_error "AUTODEPLOY_INTERVAL must be minutes, 1-59 (got '$(autodeploy_interval)')"
        return 1
    fi
    if [[ "$(git rev-parse --abbrev-ref HEAD)" != "$(autodeploy_branch)" ]]; then
        print_error "Checked out '$(git rev-parse --abbrev-ref HEAD)' but BRANCH=$(autodeploy_branch). Run: git checkout $(autodeploy_branch)"
        return 1
    fi

    print_header "Auto-deploy · ${APP_NAME:-$CONTAINER_NAME}"
    steps_begin 2
    if ! run_step "Fetching origin/$(autodeploy_branch) without a terminal (as cron will)" autodeploy_check_fetch; then
        print_info "cron has no ssh-agent and can't type passphrases: use a deploy key without passphrase (~/.ssh/config)"
        return 1
    fi
    mkdir -p "$(dock_state_dir)"
    run_step "Installing cron job" cron_install autodeploy "$(autodeploy_cron_line)" || return 1

    print_nl
    autodeploy_print_settings
    print_nl
    print_warning "Every push to $(autodeploy_branch) goes live in ${APP_ENV} within $(autodeploy_interval) min, migrations included. Protect the branch."
    print_info "Follow it: ./dock autodeploy logs -f · stop it: ./dock autodeploy disable"
}

autodeploy_print_settings() {
    print_kv "Branch" "origin/$(autodeploy_branch)"
    print_kv "Environment" "$APP_ENV"
    print_kv "Every" "$(autodeploy_interval) min ($(autodeploy_schedule))"
    print_kv "Log" "$(short_path "$(autodeploy_log)")"
}

cmd_autodeploy_disable() {
    require_env_light || return 1
    if [[ -z "$(autodeploy_cron_entry)" ]]; then
        print_info "Auto-deploy is not enabled for this project"
        return 0
    fi
    cron_remove autodeploy || return 1
    print_success "Auto-deploy disabled (cron job removed). Deploy by hand with ./dock deploy"
}

cmd_autodeploy_status() {
    local entry state
    require_env_light || return 1
    print_header "Auto-deploy · ${APP_NAME:-$CONTAINER_NAME}"
    entry="$(autodeploy_cron_entry)"
    if [[ -z "$entry" ]]; then
        print_kv "Cron" "not installed (./dock autodeploy enable)"
    elif [[ "$entry" != "$(autodeploy_cron_line)" ]]; then
        print_kv "Cron" "installed, out of date with .env (./dock autodeploy enable)"
    else
        print_kv "Cron" "installed"
    fi
    autodeploy_print_settings
    print_kv "Last check" "$(cat "$(autodeploy_checked)" 2>/dev/null || echo never)"
    state="$(cat "$(autodeploy_state)" 2>/dev/null)"
    if [[ -z "$state" ]]; then
        print_kv "Last deploy" "none recorded"
    else
        print_kv "Last deploy" "$(echo "$state" | awk '{ r = $1; c = substr($2, 1, 7); t = $3; $1 = $2 = $3 = ""; sub(/^ +/, ""); print r, c, "at", t, ($0 != "" ? "- " $0 : "") }')"
    fi
    [[ -f "$(autodeploy_error)" ]] && print_warning "$(cat "$(autodeploy_error)")"
    lock_is_held "$(deploy_lock)" && print_info "A deploy is running now"
    return 0
}

cmd_autodeploy_logs() {
    local follow=false lines=50
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--follow) follow=true ;;
            -n|--tail)   lines="${2:-50}"; shift ;;
            *)           print_error "Unknown option for autodeploy logs: $1"; return 1 ;;
        esac
        shift
    done
    if [[ ! -f "$(autodeploy_log)" ]]; then
        print_info "No log yet: the cron job writes $(short_path "$(autodeploy_log)") when it deploys"
        return 0
    fi
    if [[ "$follow" == "true" ]]; then
        tail -n "$lines" -f "$(autodeploy_log)"
    else
        tail -n "$lines" "$(autodeploy_log)"
    fi
}

cmd_autodeploy() {
    local sub="${1:-status}"
    [[ $# -gt 0 ]] && shift
    case "$sub" in
        enable)         cmd_autodeploy_enable "$@" ;;
        disable)        cmd_autodeploy_disable "$@" ;;
        status)         cmd_autodeploy_status "$@" ;;
        run)            cmd_autodeploy_run "$@" ;;
        logs|log)       cmd_autodeploy_logs "$@" ;;
        help|-h|--help) show_command_help autodeploy ;;
        *)
            print_error "Unknown autodeploy command: ${sub}"
            print_info "./dock help autodeploy"
            return 1 ;;
    esac
}
