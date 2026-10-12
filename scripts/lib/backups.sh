#!/usr/bin/env bash
# =============================================================================
# Off-site database backups: ./dock backups <command>.
#
# run:  db_dump_sql | gzip | openssl enc  ->  backups/pending/<stamp>.sql.gz.enc
#       upload everything in backups/pending/ (failed uploads are retried by
#       the next run), delete remote backups older than BACKUP_KEEP_DAYS.
#
# Remote objects: s3://BACKUP_S3_BUCKET/BACKUP_S3_PATH/2026-01-31T03-00-00Z.sql.gz.enc
# Names are UTC timestamps, so they sort chronologically and retention works
# on names alone. Objects with other names are never listed or deleted.
#
# The AWS CLI runs from a pinned image (host needs docker, openssl and cron);
# credentials reach it through the environment, never argv.
#
# Relies on dock: db_require, db_dump_sql, cmd_db_restore, env_path, short_path,
# ENV_FILE.
# =============================================================================

[[ -n "${_BACKUPS_LOADED:-}" ]] && return 0
_BACKUPS_LOADED=1

SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "${SCRIPT_LIB_DIR}/colors.sh"
source "${SCRIPT_LIB_DIR}/utils.sh"
source "${SCRIPT_LIB_DIR}/ui.sh"

BACKUP_DEFAULT_SCHEDULE="0 3 * * *"
BACKUP_DEFAULT_KEEP_DAYS=30
BACKUP_DEFAULT_AWS_CLI_IMAGE="amazon/aws-cli:2.27.50"
BACKUP_STAMP_FORMAT="%Y-%m-%dT%H-%M-%SZ"
BACKUP_NAME_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}Z\.sql\.gz\.enc$'
BACKUP_LOG_MAX_LINES=5000
# Explicit KDF parameters: decryption must not depend on openssl defaults.
BACKUP_CIPHER=(-aes-256-cbc -pbkdf2 -iter 200000 -md sha256)

backup_dir()       { echo "${PROJECT_ROOT}/backups"; }
backup_pending()   { echo "${PROJECT_ROOT}/backups/pending"; }
backup_log()       { echo "${PROJECT_ROOT}/backups/backup.log"; }
backup_state()     { echo "${PROJECT_ROOT}/backups/last-run"; }
backup_keep_days() { echo "${BACKUP_KEEP_DAYS:-$BACKUP_DEFAULT_KEEP_DAYS}"; }

# Folder inside the bucket ("" = bucket root). Default: CONTAINER_NAME.
backup_prefix() {
    local p="${BACKUP_S3_PATH-$CONTAINER_NAME}"
    p="${p#/}"
    p="${p%/}"
    [[ -n "$p" ]] && p="${p}/"
    printf '%s' "$p"
}

backup_url() { printf 's3://%s/%s%s' "$BACKUP_S3_BUCKET" "$(backup_prefix)" "${1:-}"; }

# Stamp of an epoch in UTC (GNU or BSD date).
backup_stamp() {
    date -u -d "@$1" "+${BACKUP_STAMP_FORMAT}" 2>/dev/null || date -u -r "$1" "+${BACKUP_STAMP_FORMAT}"
}

# 2026-01-31T03-00-00Z.sql.gz.enc -> 2026-01-31 03:00 UTC
backup_label() {
    local s="${1%%Z*}"
    printf '%s %s UTC' "${s%%T*}" "$(echo "${s#*T}" | cut -d- -f1,2 | tr - :)"
}


# -----------------------------------------------------------------------------
# S3
# -----------------------------------------------------------------------------

# backup_s3 [-i] <aws args...>: aws CLI in a throwaway container; -i forwards stdin.
# The checksum settings keep current CLIs working with Spaces, R2, MinIO, ...
backup_s3() {
    local flags=(--rm) endpoint=()
    if [[ "${1:-}" == "-i" ]]; then flags+=(-i); shift; fi
    [[ -n "${BACKUP_S3_ENDPOINT:-}" ]] && endpoint=(--endpoint-url "$BACKUP_S3_ENDPOINT")
    print_debug "aws $*"
    AWS_ACCESS_KEY_ID="${BACKUP_S3_ACCESS_KEY:-}" \
    AWS_SECRET_ACCESS_KEY="${BACKUP_S3_SECRET_KEY:-}" \
    AWS_DEFAULT_REGION="${BACKUP_S3_REGION:-us-east-1}" \
        docker run "${flags[@]}" \
            -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION \
            -e AWS_REQUEST_CHECKSUM_CALCULATION=when_required \
            -e AWS_RESPONSE_CHECKSUM_VALIDATION=when_required \
            "${BACKUP_AWS_CLI_IMAGE:-$BACKUP_DEFAULT_AWS_CLI_IMAGE}" "${endpoint[@]}" "$@"
}

# Remote backups as "<name> <bytes>", newest first. Paginated by the CLI.
backup_remote_list() {
    local out
    if ! out="$(backup_s3 s3api list-objects-v2 --bucket "$BACKUP_S3_BUCKET" --prefix "$(backup_prefix)" \
            --query 'Contents[].[Key, Size]' --output text 2>&1 </dev/null)"; then
        print_error "Listing $(backup_url) failed:"
        echo "$out" | tail -n 5 | sed 's/^/    /' >&2
        return 1
    fi
    # Keys under sub-folders keep a '/' after the prefix and fail the regex.
    printf '%s\n' "$out" | awk -F '\t' -v p="$(backup_prefix)" 'p == "" || index($1, p) == 1 { print substr($1, length(p) + 1), $2 }' \
        | grep -E "${BACKUP_NAME_RE%$} [0-9]+$" | sort -r
    return 0
}

# backup_resolve <latest|N|name>: remote backup name (N: position in list, 1 = newest).
backup_resolve() {
    local list name
    list="$(backup_remote_list)" || return 1
    if [[ -z "$list" ]]; then
        print_error "No backups in $(backup_url)"
        return 1
    fi
    case "$1" in
        latest)       name="$(echo "$list" | head -n1 | cut -d' ' -f1)" ;;
        *[!0-9]*|"")  name="$(echo "$list" | cut -d' ' -f1 | grep -xF -- "${1##*/}")" ;;
        0)            name="" ;;
        *)            name="$(echo "$list" | sed -n "${1}p" | cut -d' ' -f1)" ;;
    esac
    if [[ -z "$name" ]]; then
        print_error "No backup '${1}' (./dock backups list)"
        return 1
    fi
    echo "$name"
}

# backup_choose [selection]: resolve it, or show the list and ask (terminal only).
backup_choose() {
    local answer
    if [[ -n "${1:-}" ]]; then
        backup_resolve "$1"
        return
    fi
    if [[ ! -t 0 ]]; then
        print_error "Which backup? Pass latest, a number from ./dock backups list, or a file name"
        return 1
    fi
    backup_print_list 15 >&2 || return 1
    echo -n -e "${YELLOW}Backup number${NC} [1] " >&2
    read -r answer
    backup_resolve "${answer:-1}"
}

backup_print_list() {
    local limit="${1:-0}" list count n=0 name size
    list="$(backup_remote_list)" || return 1
    if [[ -z "$list" ]]; then
        print_info "No backups in $(backup_url)"
        return 0
    fi
    count="$(echo "$list" | wc -l | tr -d ' ')"
    echo ""
    printf "  ${DIM}%-4s %-22s %10s   %s${NC}\n" "#" "DATE" "SIZE" "FILE"
    while read -r name size; do
        n=$((n + 1))
        if [[ "$limit" -gt 0 && $n -gt $limit ]]; then
            echo -e "  ${DIM}… $((count - limit)) more (./dock backups list)${NC}"
            break
        fi
        printf "  %-4s %-22s %10s   ${DIM}%s${NC}\n" "$n" "$(backup_label "$name")" "$(human_size "$size")" "$name"
    done <<< "$list"
    echo ""
}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

BACKUP_REQUIRED_VARS="BACKUP_S3_BUCKET BACKUP_S3_ACCESS_KEY BACKUP_S3_SECRET_KEY BACKUP_PASSWORD"

backup_missing_vars() {
    local var missing=""
    for var in $BACKUP_REQUIRED_VARS; do
        [[ -z "${!var:-}" ]] && missing="${missing} ${var}"
    done
    echo "${missing# }"
}

backup_require_config() {
    local missing
    missing="$(backup_missing_vars)"
    if [[ -n "$missing" ]]; then
        print_error "Backups are not configured. Missing in .env: ${missing}"
        print_info "Run ./dock backups enable in a terminal, or set them in .env"
        return 1
    fi
    if [[ ! "$(backup_keep_days)" =~ ^[0-9]+$ ]]; then
        print_error "BACKUP_KEEP_DAYS must be a number of days (0 keeps everything)"
        return 1
    fi
    command_exists openssl || { print_error "openssl is required on the host"; return 1; }
    check_docker
}

# backup_save <KEY> <value>: single-quoted in .env (literal for dock and
# phpdotenv alike) and exported for the rest of this run.
backup_save() {
    local file
    file="$(env_path)"
    grep -qE '^BACKUP_' "$file" || printf '\n# Backups (./dock backups)\n' >> "$file"
    set_env_value "$file" "$1" "'$2'"
    export "$1=$2"
}

# backup_ask <KEY> <question> [default] [opts]: prompt and save.
# opts: "required" re-asks on an empty answer, "secret" hides the input.
backup_ask() {
    local key="$1" question="$2" default="${3:-}" opts=" ${4:-} " value hint=""
    [[ -n "$default" ]] && hint=" ${DIM}[${default}]${NC}"
    while :; do
        echo -n -e "  ${question}${hint}: "
        if [[ "$opts" == *" secret "* ]]; then read -r -s value; echo; else read -r value; fi
        value="${value:-$default}"
        if [[ "$value" == *"'"* ]]; then
            print_warning "Single quotes are not supported"
        elif [[ -z "$value" && "$opts" == *" required "* ]]; then
            print_warning "Required"
        else
            break
        fi
    done
    backup_save "$key" "$value"
}

# backup_should_ask <all> <unset|empty> <VAR>: ask everything with --reconfigure,
# otherwise only unset variables (empty is a valid answer) or empty ones.
backup_should_ask() {
    [[ "$1" == "true" ]] && return 0
    if [[ "$2" == "unset" ]]; then [[ -z "${!3+x}" ]]; else [[ -z "${!3:-}" ]]; fi
}

# Interactive setup of whatever .env is missing (everything with --reconfigure).
backup_configure() {
    local all="$1"

    print_section "Storage (S3-compatible: AWS, DigitalOcean Spaces, Cloudflare R2, MinIO, ...)"
    print_msg "  ${DIM}Saved to $(short_path "$(env_path)"). Enter keeps the value in brackets.${NC}"
    backup_should_ask "$all" unset BACKUP_S3_ENDPOINT && backup_ask BACKUP_S3_ENDPOINT "Endpoint URL, empty for AWS (e.g. https://fra1.digitaloceanspaces.com)" "${BACKUP_S3_ENDPOINT:-}"
    backup_should_ask "$all" empty BACKUP_S3_REGION && backup_ask BACKUP_S3_REGION "Region" "${BACKUP_S3_REGION:-us-east-1}"
    backup_should_ask "$all" empty BACKUP_S3_BUCKET && backup_ask BACKUP_S3_BUCKET "Bucket" "${BACKUP_S3_BUCKET:-}" required
    backup_should_ask "$all" unset BACKUP_S3_PATH && backup_ask BACKUP_S3_PATH "Folder in the bucket" "${BACKUP_S3_PATH:-$CONTAINER_NAME}"
    backup_should_ask "$all" empty BACKUP_S3_ACCESS_KEY && backup_ask BACKUP_S3_ACCESS_KEY "Access key" "${BACKUP_S3_ACCESS_KEY:-}" required
    if [[ -z "${BACKUP_S3_SECRET_KEY:-}" ]]; then
        backup_ask BACKUP_S3_SECRET_KEY "Secret key" "" "secret required"
    elif [[ "$all" == "true" ]]; then
        backup_ask BACKUP_S3_SECRET_KEY "Secret key (empty keeps the current one)" "$BACKUP_S3_SECRET_KEY" secret
    fi
    # Never re-asked: changing it makes older backups need the old password.
    if [[ -z "${BACKUP_PASSWORD:-}" ]]; then
        backup_ask BACKUP_PASSWORD "Encryption password (empty generates one)" "" secret
        if [[ -z "$BACKUP_PASSWORD" ]]; then
            backup_save BACKUP_PASSWORD "$(random_base64 32)"
            print_warning "Generated BACKUP_PASSWORD. Store a copy outside this server (password manager): without it the backups can't be decrypted"
        fi
    fi
    backup_should_ask "$all" empty BACKUP_KEEP_DAYS && backup_ask BACKUP_KEEP_DAYS "Keep backups for how many days (0 = forever)" "$(backup_keep_days)"
    backup_should_ask "$all" empty BACKUP_SCHEDULE && backup_ask BACKUP_SCHEDULE "Schedule, cron syntax in server time" "${BACKUP_SCHEDULE:-$BACKUP_DEFAULT_SCHEDULE}"
}

backup_valid_schedule() {
    local fields
    [[ "$1" != *%* && "$1" != *"'"* ]] || return 1
    fields="$(printf '%s\n' "$1" | awk '{ print NF }')"
    [[ "$fields" == 5 || ( "$fields" == 1 && "$1" == @* ) ]]
}

# -----------------------------------------------------------------------------
# cron
# -----------------------------------------------------------------------------

# Identifies this project's entry; the trailing ':' keeps /srv/app from
# matching /srv/app2.
backup_cron_marker() { printf '# dock-backups:%s:' "$PROJECT_ROOT"; }

backup_crontab_read() { crontab -l 2>/dev/null; }

backup_cron_entry() { command_exists crontab && backup_crontab_read | grep -F -- "$(backup_cron_marker)"; }

# cron runs with a minimal PATH: put docker's directory first.
backup_cron_line() {
    local env_flag=""
    [[ "$ENV_FILE" != ".env" ]] && env_flag="-e '${ENV_FILE}' "
    printf "%s cd '%s' && PATH='%s:/usr/local/bin:/usr/bin:/bin' NO_COLOR=1 ./dock %sbackups run >> backups/backup.log 2>&1 %s" \
        "$BACKUP_SCHEDULE" "$PROJECT_ROOT" "$(dirname "$(command -v docker)")" "$env_flag" "$(backup_cron_marker)"
}

# The current crontab is read completely before `crontab -` replaces it.
backup_crontab_without_entry() { backup_crontab_read | grep -vF -- "$(backup_cron_marker)"; }

backup_cron_install() {
    local others
    others="$(backup_crontab_without_entry)"
    { [[ -n "$others" ]] && printf '%s\n' "$others"; backup_cron_line; echo; } | crontab -
}

backup_cron_remove() {
    local others
    others="$(backup_crontab_without_entry)"
    { [[ -n "$others" ]] && printf '%s\n' "$others"; } | crontab -
}

# -----------------------------------------------------------------------------
# Run state: backups/last-run holds "<ok|failed> <UTC time> <detail>"
# -----------------------------------------------------------------------------

backup_record() {
    mkdir -p "$(backup_dir)"
    printf '%s %s %s\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$2" > "$(backup_state)"
}

# Only one run at a time: a lock dir holding the owner's pid (stale locks of
# dead processes are taken over).
backup_lock() {
    local lock pid
    lock="$(backup_dir)/.lock"
    mkdir -p "$(backup_dir)"
    if ! mkdir "$lock" 2>/dev/null; then
        pid="$(cat "${lock}/pid" 2>/dev/null)"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            print_error "Another backup is running (pid ${pid})"
            return 1
        fi
        rm -rf "$lock" && mkdir "$lock" || return 1
    fi
    echo $$ > "${lock}/pid"
    # shellcheck disable=SC2064  # expand now: the path is fixed
    trap "rm -rf '${lock}'" EXIT
}

# Keep the cron log bounded.
backup_trim_log() {
    local log
    log="$(backup_log)"
    [[ -f "$log" ]] || return 0
    if [[ "$(wc -l < "$log")" -gt "$BACKUP_LOG_MAX_LINES" ]]; then
        tail -n $((BACKUP_LOG_MAX_LINES / 2)) "$log" > "${log}.tmp" && mv "${log}.tmp" "$log"
    fi
}

# -----------------------------------------------------------------------------
# Steps (run inside run_step: no prompts)
# -----------------------------------------------------------------------------

backup_step_dump() {
    local file="$1"
    mkdir -p "$(dirname "$file")" || return 1
    if ! (
        umask 077
        set -o pipefail
        db_dump_sql | gzip | openssl enc "${BACKUP_CIPHER[@]}" -salt -pass env:BACKUP_PASSWORD -out "$file"
    ); then
        rm -f "$file"
        return 1
    fi
    step_note "$(basename "$file") ($(human_size "$(wc -c < "$file")"))"
}

# Uploads this run's dump and anything left by earlier failed runs.
backup_step_upload() {
    local f name uploaded=0 failed=0
    for f in "$(backup_pending)"/*.sql.gz.enc; do
        [[ -f "$f" ]] || continue
        name="$(basename "$f")"
        echo "Uploading ${name}"
        if backup_s3 -i s3 cp --only-show-errors --expected-size "$(wc -c < "$f" | tr -d ' ')" - "$(backup_url "$name")" < "$f"; then
            rm -f "$f"
            uploaded=$((uploaded + 1))
        else
            failed=$((failed + 1))
        fi
    done
    if [[ $failed -gt 0 ]]; then
        print_error "${failed} upload(s) failed: kept in backups/pending/, retried by the next run"
        return 1
    fi
    [[ $uploaded -gt 1 ]] && step_note "${uploaded} files, including earlier failed uploads"
    return 0
}

# Deletes backups older than BACKUP_KEEP_DAYS, never the newest one. One
# delete-objects call per run (max 1000 keys: a backlog shrinks over runs).
backup_step_prune() {
    local days cutoff list old json errors
    days="$(backup_keep_days)"
    cutoff="$(backup_stamp $(( $(date +%s) - days * 86400 )))"
    list="$(backup_remote_list)" || return 1
    old="$(echo "$list" | sed 1d | cut -d' ' -f1 | awk -v c="$cutoff" 'NF && $0 < c' | head -n 1000)"
    if [[ -z "$old" ]]; then
        step_note "nothing older than ${days} days ($(echo "$list" | grep -c .) kept)"
        return 0
    fi
    json="$(echo "$old" | awk -v p="$(backup_prefix)" '{ printf "%s{\"Key\":\"%s%s\"}", (NR > 1 ? "," : ""), p, $0 }')"
    if ! errors="$(backup_s3 s3api delete-objects --bucket "$BACKUP_S3_BUCKET" \
            --delete "{\"Objects\":[${json}],\"Quiet\":true}" \
            --query 'Errors[].[Key, Message]' --output text 2>&1 </dev/null)"; then
        echo "$errors"
        return 1
    fi
    errors="$(echo "$errors" | grep -v '^None$')"
    if [[ -n "$errors" ]]; then
        print_error "Some deletions failed:"
        echo "$errors"
        return 1
    fi
    step_note "$(echo "$old" | wc -l | tr -d ' ') deleted, $(( $(echo "$list" | grep -c .) - $(echo "$old" | wc -l) )) kept"
}

backup_step_fetch() {
    local name="$1" out="$2"
    mkdir -p "$(dirname "$out")" || return 1
    if ! ( umask 077; backup_s3 s3 cp --only-show-errors "$(backup_url "$name")" - > "${out}.enc" ); then
        rm -f "${out}.enc"
        return 1
    fi
    if ! ( umask 077; openssl enc -d "${BACKUP_CIPHER[@]}" -pass env:BACKUP_PASSWORD -in "${out}.enc" -out "$out" 2>/dev/null ) \
        || ! gzip -t "$out" 2>/dev/null; then
        rm -f "${out}.enc" "$out"
        print_error "Decryption failed: wrong BACKUP_PASSWORD?"
        return 1
    fi
    rm -f "${out}.enc"
    step_note "$(short_path "$out") ($(human_size "$(wc -c < "$out")"))"
}

# -----------------------------------------------------------------------------
# Commands
# -----------------------------------------------------------------------------

cmd_backups_enable() {
    local reconfigure=false run_now="" schedule="" keep_days=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --schedule)    schedule="${2:-}"; shift ;;
            --keep-days)   keep_days="${2:-}"; shift ;;
            --reconfigure) reconfigure=true ;;
            --now)         run_now=true ;;
            --no-run)      run_now=false ;;
            -h|--help)     show_command_help backups; return 0 ;;
            *)             print_error "Unknown option for backups enable: $1"; return 1 ;;
        esac
        shift
    done
    require_env_light || return 1
    command_exists crontab || { print_error "crontab not found: install cron (Debian/Ubuntu: apt install cron)"; return 1; }
    if [[ "$PROJECT_ROOT" == *[\'%]* ]]; then
        print_error "The project path can't contain ' or % (cron): ${PROJECT_ROOT}"
        return 1
    fi

    print_header "Backups · ${APP_NAME:-$CONTAINER_NAME}"
    [[ -n "$schedule" ]] && backup_save BACKUP_SCHEDULE "$schedule"
    [[ -n "$keep_days" ]] && backup_save BACKUP_KEEP_DAYS "$keep_days"
    if [[ -t 0 ]] && [[ "$reconfigure" == "true" || -n "$(backup_missing_vars)" ]]; then
        backup_configure "$reconfigure"
    fi
    backup_require_config || return 1
    [[ -n "${BACKUP_KEEP_DAYS:-}" ]] || backup_save BACKUP_KEEP_DAYS "$BACKUP_DEFAULT_KEEP_DAYS"
    [[ -n "${BACKUP_SCHEDULE:-}" ]] || backup_save BACKUP_SCHEDULE "$BACKUP_DEFAULT_SCHEDULE"
    if ! backup_valid_schedule "$BACKUP_SCHEDULE"; then
        print_error "BACKUP_SCHEDULE '${BACKUP_SCHEDULE}' is not a cron expression (5 fields like \"0 3 * * *\", or @daily)"
        return 1
    fi

    print_nl
    steps_begin 2
    if ! run_step "Checking access to ${BACKUP_S3_BUCKET}" backup_s3 s3api head-bucket --bucket "$BACKUP_S3_BUCKET"; then
        print_info "Check BACKUP_S3_ENDPOINT, BACKUP_S3_REGION, BACKUP_S3_BUCKET and the keys (./dock backups enable --reconfigure)"
        return 1
    fi
    mkdir -p "$(backup_dir)"
    run_step "Installing cron job" backup_cron_install || return 1

    print_nl
    backup_print_settings

    if [[ -z "$run_now" ]]; then
        print_nl
        confirm "Run a first backup now?" y && run_now=true
    fi
    [[ "$run_now" == "true" ]] || return 0
    print_nl
    cmd_backups_run
}

backup_print_settings() {
    local days
    days="$(backup_keep_days)"
    print_kv "Destination" "$(backup_url)"
    [[ -n "${BACKUP_S3_ENDPOINT:-}" ]] && print_kv "Endpoint" "$BACKUP_S3_ENDPOINT"
    print_kv "Schedule" "${BACKUP_SCHEDULE:-$BACKUP_DEFAULT_SCHEDULE} (server time, $(date +%Z))"
    print_kv "Retention" "$([[ "$days" == 0 ]] && echo forever || echo "${days} days")"
}

cmd_backups_disable() {
    require_env_light || return 1
    if [[ -z "$(backup_cron_entry)" ]]; then
        print_info "No backup cron job for this project"
        return 0
    fi
    backup_cron_remove || return 1
    print_success "Cron job removed (settings in .env and remote backups are kept)"
}

cmd_backups_status() {
    local entry state list pending
    require_env_light || return 1
    print_header "Backups · ${APP_NAME:-$CONTAINER_NAME}"
    if [[ -n "$(backup_missing_vars)" ]]; then
        print_info "Not configured: ./dock backups enable"
        return 0
    fi

    print_section "Settings"
    backup_print_settings
    entry="$(backup_cron_entry)"
    if [[ -z "$entry" ]]; then
        print_kv "Cron" "not installed (./dock backups enable)"
    elif [[ "$entry" != "$(backup_cron_line)" ]]; then
        print_kv "Cron" "installed, out of date with .env (./dock backups enable)"
    else
        print_kv "Cron" "installed"
    fi

    print_section "Runs"
    state="$(cat "$(backup_state)" 2>/dev/null)"
    if [[ -z "$state" ]]; then
        print_kv "Last run" "never"
    else
        print_kv "Last run" "$(echo "$state" | awk '{ r = $1; t = $2; $1 = $2 = ""; sub(/^ +/, ""); print r, "at", t, "-", $0 }')"
    fi
    pending="$(find "$(backup_pending)" -name '*.sql.gz.enc' 2>/dev/null | wc -l | tr -d ' ')"
    [[ "$pending" -gt 0 ]] && print_warning "${pending} backup(s) waiting in backups/pending/ for upload"

    backup_require_config >/dev/null 2>&1 || return 0
    list="$(backup_remote_list)" || return 1
    print_kv "Stored" "$(echo "$list" | grep -c .) backup(s)"
    if [[ -n "$list" ]]; then
        print_kv "Newest" "$(backup_label "$(echo "$list" | head -n1 | cut -d' ' -f1)")"
        print_kv "Oldest" "$(backup_label "$(echo "$list" | tail -n1 | cut -d' ' -f1)")"
    fi
}

cmd_backups_run() {
    local name days steps=2 rc=0
    db_require && backup_require_config || return 1
    backup_lock || return 1
    backup_trim_log

    days="$(backup_keep_days)"
    [[ "$days" -gt 0 ]] && steps=3
    name="$(backup_stamp "$(date +%s)").sql.gz.enc"
    print_msg "${BOLD}Backup ${DB_DATABASE}${NC} ${DIM}$(date '+%Y-%m-%d %H:%M:%S %Z') → $(backup_url)${NC}"

    steps_begin "$steps"
    if ! run_step "Dumping and encrypting ${DB_DATABASE}" backup_step_dump "$(backup_pending)/${name}"; then
        backup_record failed "dump"
        return 1
    fi
    if ! run_step "Uploading" backup_step_upload; then
        backup_record failed "upload (${name} kept in backups/pending/)"
        return 1
    fi
    if [[ $steps -eq 3 ]] && ! run_step "Deleting backups older than ${days} days" backup_step_prune; then
        rc=1
    fi
    backup_record ok "$name"
    return $rc
}

cmd_backups_list() {
    require_env_light && backup_require_config || return 1
    print_info "$(backup_url)"
    backup_print_list
}

cmd_backups_download() {
    local name out
    require_env_light && backup_require_config || return 1
    name="$(backup_choose "${1:-}")" || return 1
    out="$(backup_dir)/downloads/${CONTAINER_NAME}-${name%.enc}"
    steps_begin 0
    run_step "Downloading ${name}" backup_step_fetch "$name" "$out" || return 1
    print_info "Restore with: ./dock db:restore $(short_path "$out")"
}

cmd_backups_restore() {
    local name out rc
    db_require && backup_require_config || return 1
    name="$(backup_choose "${1:-}")" || return 1
    out="$(backup_dir)/downloads/${CONTAINER_NAME}-${name%.enc}"
    steps_begin 0
    run_step "Downloading ${name}" backup_step_fetch "$name" "$out" || return 1
    cmd_db_restore "$out"
    rc=$?
    rm -f "$out"
    return $rc
}

cmd_backups_prune() {
    require_env_light && backup_require_config || return 1
    if [[ "$(backup_keep_days)" -eq 0 ]]; then
        print_info "BACKUP_KEEP_DAYS=0: backups are kept forever"
        return 0
    fi
    steps_begin 0
    run_step "Deleting backups older than $(backup_keep_days) days" backup_step_prune
}

cmd_backups_logs() {
    local follow=false lines=50
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--follow) follow=true ;;
            -n|--tail)   lines="${2:-50}"; shift ;;
            *)           print_error "Unknown option for backups logs: $1"; return 1 ;;
        esac
        shift
    done
    if [[ ! -f "$(backup_log)" ]]; then
        print_info "No log yet: backups/backup.log is written by the cron job"
        return 0
    fi
    if [[ "$follow" == "true" ]]; then
        tail -n "$lines" -f "$(backup_log)"
    else
        tail -n "$lines" "$(backup_log)"
    fi
}

cmd_backups() {
    local sub="${1:-status}"
    [[ $# -gt 0 ]] && shift
    case "$sub" in
        enable)         cmd_backups_enable "$@" ;;
        disable)        cmd_backups_disable "$@" ;;
        status)         cmd_backups_status "$@" ;;
        run|now)        cmd_backups_run "$@" ;;
        list|ls)        cmd_backups_list "$@" ;;
        download)       cmd_backups_download "$@" ;;
        restore)        cmd_backups_restore "$@" ;;
        prune)          cmd_backups_prune "$@" ;;
        logs|log)       cmd_backups_logs "$@" ;;
        help|-h|--help) show_command_help backups ;;
        *)
            print_error "Unknown backups command: ${sub}"
            print_info "./dock help backups"
            return 1 ;;
    esac
}
