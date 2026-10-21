#!/usr/bin/env bash
# =============================================================================
# .env loading, validation and the derived variables compose files rely on.
# =============================================================================

[[ -n "${_ENV_LOADED:-}" ]] && return 0
_ENV_LOADED=1

SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "${SCRIPT_LIB_DIR}/colors.sh"
source "${SCRIPT_LIB_DIR}/utils.sh"

VALID_ENVS="local development staging production"
VALID_SERVERS="artisan octane fpm nginx caddy"
VALID_DB_DRIVERS="mariadb postgres pgvector"

# -----------------------------------------------------------------------------
# Loading
# -----------------------------------------------------------------------------

# load_env <file>: export every KEY=VALUE of a dotenv file.
# Variables already set in the shell win (like docker compose and phpdotenv),
# so `APP_PORT=8080 ./dock start` works. Supports `export KEY=`, single/double
# quotes and trailing ` # comments` on unquoted values.
load_env() {
    local env_file="${1:-.env}" line key value

    if [[ ! -f "$env_file" ]]; then
        print_error "Environment file not found: ${env_file}"
        return 1
    fi
    print_verbose "Loading environment from ${env_file}"
    DOCK_ENV_FILE="$env_file"

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
        key="${BASH_REMATCH[2]}"
        value="${BASH_REMATCH[3]}"

        if [[ "$value" =~ ^\"(.*)\"[[:space:]]*(#.*)?$ ]]; then
            value="${BASH_REMATCH[1]}"
        elif [[ "$value" =~ ^\'(.*)\'[[:space:]]*(#.*)?$ ]]; then
            value="${BASH_REMATCH[1]}"
        else
            value="${value%%[[:space:]]#*}"
            value="${value%"${value##*[![:space:]]}"}"
        fi

        [[ -n "${!key+x}" ]] && continue
        export "${key}=${value}"
    done < "$env_file"
}

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

is_local_env()      { [[ "${APP_ENV:-local}" == "local" || "${APP_ENV:-local}" == "development" ]]; }
is_production_env() { [[ "${APP_ENV:-local}" == "production" ]]; }

# local | staging | production: selects compose overrides, PHP ini, workers,
# and the Dockerfile target.
get_env_compose_file() {
    case "${APP_ENV:-local}" in
        staging)    echo "staging" ;;
        production) echo "production" ;;
        *)          echo "local" ;;
    esac
}

get_db_driver() {
    local driver="${DB_DRIVER:-mariadb}"
    [[ "$driver" == "postgresql" ]] && driver="postgres"
    echo "$driver"
}

# Host port publishing toggles: on in local, off in staging/production unless
# PUBLISH_DB_PORT / PUBLISH_REDIS_PORT is set to true.
_is_false() { case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in false|0|no|off) return 0 ;; *) return 1 ;; esac; }
_is_true() { case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in true|1|yes|on) return 0 ;; *) return 1 ;; esac; }

publish_db_port() {
    if [[ -n "${PUBLISH_DB_PORT:-}" ]]; then _is_true "$PUBLISH_DB_PORT"; return; fi
    [[ "$(get_env_compose_file)" == "local" ]]
}

publish_redis_port() {
    if [[ -n "${PUBLISH_REDIS_PORT:-}" ]]; then _is_true "$PUBLISH_REDIS_PORT"; return; fi
    [[ "$(get_env_compose_file)" == "local" ]]
}

is_postgres_driver() { [[ "$(get_db_driver)" == "postgres" || "$(get_db_driver)" == "pgvector" ]]; }

# SERVICES="redis, mailpit" -> "redis mailpit"
parse_services() {
    local s="${SERVICES:-}"
    s="${s//,/ }"
    # shellcheck disable=SC2086  # unquoted on purpose: collapses whitespace
    echo $s
}

has_service() { [[ " $(parse_services) " == *" $1 "* ]]; }

# resolve_mount_path <value> <default>: absolute host path for a bind mount.
# Relative paths are relative to the project root. Compose would resolve them
# from docker/compose/, which earlier versions accidentally did: if data only
# exists at that legacy location, keep using it and say so.
resolve_mount_path() {
    local value="${1:-$2}" target legacy
    target="$(abs_path "$value" "$PROJECT_ROOT")"
    case "$value" in
        /*|"~"/*) ;;
        *)
            legacy="$(abs_path "$value" "${PROJECT_ROOT}/docker/compose")"
            if [[ ! -e "$target" && -d "$legacy" && -n "$(ls -A "$legacy" 2>/dev/null)" ]]; then
                print_warning "Using legacy data dir ${legacy#"${PROJECT_ROOT}"/} (move it to ${value} when convenient)"
                target="$legacy"
            fi
            ;;
    esac
    printf '%s' "$target"
}

# Export everything compose files expect. Idempotent.
prepare_compose_env() {
    DOCK_ENV="$(get_env_compose_file)"
    DB_DRIVER="$(get_db_driver)"

    if is_local_env; then RESTART_POLICY="no"; else RESTART_POLICY="unless-stopped"; fi

    # Container user mirrors the host user so bind-mounted files keep their
    # owner. Never root: fall back to 1000.
    USER_ID="${USER_ID:-$(id -u)}"
    GROUP_ID="${GROUP_ID:-$(id -g)}"
    [[ "$USER_ID" == "0" ]] && USER_ID=1000
    [[ "$GROUP_ID" == "0" ]] && GROUP_ID=1000

    STORAGE_MOUNT_PATH="$(resolve_mount_path "${STORAGE_MOUNT_PATH:-}" storage)"
    DB_MOUNT_PATH="$(resolve_mount_path "${DB_MOUNT_PATH:-}" db-data)"

    # Octane images build on FrankenPHP's image for the same PHP version (ZTS);
    # the tag differs so switching SERVER triggers a build instead of reusing
    # an image without FrankenPHP.
    if [[ "${SERVER:-artisan}" == "octane" ]]; then
        DOCK_WITH_FRANKENPHP=1 DOCK_IMAGE_SUFFIX="-octane"
        DOCK_PHP_BASE_IMAGE="dunglas/frankenphp:${FRANKENPHP_VERSION:-1.13.0}-php${PHP_VERSION:-8.5.12}-trixie"
    else
        DOCK_WITH_FRANKENPHP=0 DOCK_IMAGE_SUFFIX=""
        DOCK_PHP_BASE_IMAGE="php:${PHP_VERSION:-8.5.12}-fpm-trixie"
    fi

    # "127.0.0.1:" prefix for the app's host port when APP_BIND is set (e.g.
    # behind a reverse proxy on the host); empty publishes on every interface.
    DOCK_APP_BIND="${APP_BIND:+${APP_BIND}:}"

    export DOCK_ENV DB_DRIVER RESTART_POLICY USER_ID GROUP_ID DOCK_APP_BIND \
        STORAGE_MOUNT_PATH DB_MOUNT_PATH DOCK_WITH_FRANKENPHP DOCK_IMAGE_SUFFIX DOCK_PHP_BASE_IMAGE
}

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------

_in_list() { [[ " $2 " == *" $1 "* ]]; }

# validate_full_env [start|deploy]
validate_full_env() {
    local operation="${1:-start}" errors=0 var required="CONTAINER_NAME APP_ENV SERVER"
    [[ "$operation" == "deploy" ]] && required="$required DB_DATABASE DB_USERNAME DB_PASSWORD"

    for var in $required; do
        if [[ -z "${!var:-}" ]]; then
            print_error "Missing required .env variable: ${var}"
            errors=$((errors + 1))
        fi
    done

    if [[ "${CONTAINER_NAME:-}" == *"{{"* ]]; then
        print_error "CONTAINER_NAME still holds the installer placeholder: ${CONTAINER_NAME}"
        errors=$((errors + 1))
    elif [[ -n "${CONTAINER_NAME:-}" && ! "$CONTAINER_NAME" =~ ^[a-z0-9][a-z0-9_.-]+$ ]]; then
        print_error "CONTAINER_NAME must be 2+ chars, lowercase letters, digits, '-', '_' or '.'"
        errors=$((errors + 1))
    fi
    if ! _in_list "${APP_ENV:-local}" "$VALID_ENVS"; then
        print_error "Invalid APP_ENV '${APP_ENV}'. Valid: ${VALID_ENVS}"
        errors=$((errors + 1))
    fi
    if ! _in_list "${SERVER:-artisan}" "$VALID_SERVERS"; then
        print_error "Invalid SERVER '${SERVER}'. Valid: ${VALID_SERVERS}"
        errors=$((errors + 1))
    fi
    if ! _in_list "$(get_db_driver)" "$VALID_DB_DRIVERS"; then
        print_error "Invalid DB_DRIVER '${DB_DRIVER}'. Valid: ${VALID_DB_DRIVERS}"
        errors=$((errors + 1))
    fi
    if has_service phpmyadmin && is_postgres_driver; then
        print_error "phpmyadmin only works with DB_DRIVER=mariadb (remove it from SERVICES)"
        errors=$((errors + 1))
    fi
    _validate_mount_paths || errors=$((errors + 1))

    # Printed once per run: deploy re-executes itself after pulling.
    if [[ -z "${DOCK_CONFIG_WARNED:-}" ]]; then
        print_config_risks
        DOCK_CONFIG_WARNED=1
        export DOCK_CONFIG_WARNED
    fi

    return "$errors"
}

# Bind mounts are chowned recursively by deploy and the DB writes its files
# there: refuse system directories, the project itself and overlapping paths.
_validate_mount_paths() {
    local storage db p bad=0
    storage="$(abs_path "${STORAGE_MOUNT_PATH:-storage}" "$PROJECT_ROOT")"
    db="$(abs_path "${DB_MOUNT_PATH:-db-data}" "$PROJECT_ROOT")"
    for p in "$storage" "$db"; do
        case "$p" in
            ""|/|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/mnt|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var|/var/lib|/Users|"${HOME%/}"|"$PROJECT_ROOT")
                print_error "Unsafe mount path '${p}' (STORAGE_MOUNT_PATH / DB_MOUNT_PATH): use a dedicated directory"
                bad=1 ;;
        esac
    done
    if [[ "$storage" == "$db" || "$db" == "$storage"/* || "$storage" == "$db"/* ]]; then
        print_error "STORAGE_MOUNT_PATH and DB_MOUNT_PATH must not contain each other (${storage}, ${db})"
        bad=1
    fi
    return "$bad"
}

_is_loopback() { case "$1" in 127.*|localhost|::1|"[::1]") return 0 ;; *) return 1 ;; esac; }

# config_risks: one "<high|warn>|<message>" line per suspicious setting.
# high: exposes data or allows code execution; warn: probably a mistake.
# Printed by start/deploy (print_config_risks) and doctor.
config_risks() {
    local bind="${SERVICES_BIND:-127.0.0.1}" level=high raw
    is_local_env && level=warn

    if ! _is_loopback "$bind"; then
        [[ "${SERVER:-}" == "fpm" ]] \
            && echo "${level}|SERVER=fpm publishes FastCGI on ${bind}:${APP_PORT:-9000}: anyone reaching it can run PHP code. Keep SERVICES_BIND=127.0.0.1"
        publish_db_port \
            && echo "${level}|The database port is published on ${bind} (Docker bypasses ufw). Set PUBLISH_DB_PORT=false or SERVICES_BIND=127.0.0.1"
        has_service redis && publish_redis_port \
            && echo "${level}|Redis (no password) is published on ${bind}. Set PUBLISH_REDIS_PORT=false or SERVICES_BIND=127.0.0.1"
        has_service phpmyadmin \
            && echo "${level}|phpMyAdmin logs in by itself and is published on ${bind}: anyone reaching it can read the database. Keep SERVICES_BIND=127.0.0.1 (SSH tunnel)"
        is_local_env || echo "warn|SERVICES_BIND=${bind} publishes service ports on that interface (Docker bypasses ufw)"
    fi

    # phpdotenv expands ${VAR} in double-quoted and unquoted values; docker
    # compose and dock don't, so the app and the DB would disagree.
    raw="$(get_env_value "${DOCK_ENV_FILE:-/dev/null}" DB_PASSWORD)"
    if [[ "$raw" == *"\${"* ]] &&! grep -qE "^DB_PASSWORD='" "${DOCK_ENV_FILE:-/dev/null}" 2>/dev/null; then
        echo "warn|DB_PASSWORD contains '\${': Laravel expands it, the database doesn't. Single-quote the value"
    fi

    is_local_env && return 0

    _is_true "${APP_DEBUG:-false}" \
        && echo "high|APP_DEBUG=true in ${APP_ENV}: stack traces and env values are shown to visitors"
    case "${DB_PASSWORD:-}" in
        ""|password|secret|root|"{{"*) echo "high|DB_PASSWORD is empty or a well-known default" ;;
        *) (( ${#DB_PASSWORD} < 12 )) && echo "warn|DB_PASSWORD is short (${#DB_PASSWORD} chars): use 16+ random characters" ;;
    esac
    [[ "${DB_USERNAME:-}" == "root" ]] && echo "warn|DB_USERNAME=root: use a dedicated user (e.g. app)"
    if has_service meilisearch; then
        if [[ "${MEILISEARCH_KEY:-masterkey}" == "masterkey" || ${#MEILISEARCH_KEY} -lt 16 ]]; then
            echo "high|MEILISEARCH_KEY is the default or shorter than 16 chars"
        fi
        [[ "${MEILI_ENV:-development}" != "production" ]] \
            && echo "warn|MEILI_ENV is not production: Meilisearch serves its search preview UI"
    fi
    if has_service soketi; then
        case "${PUSHER_APP_SECRET:-some-app-secret}" in
            some-app-secret|app-secret)
                echo "high|Soketi is public with the default PUSHER_APP_SECRET: anyone can sign private channel subscriptions" ;;
        esac
    fi
    [[ "${SERVER:-artisan}" == "artisan" ]] \
        && echo "warn|SERVER=artisan is a development server: use octane, nginx or caddy in ${APP_ENV}"
    if [[ "${SERVER:-}" == "caddy" && ( -z "${DOMAIN:-}" || "${DOMAIN}" == "localhost" ) ]]; then
        echo "warn|SERVER=caddy without DOMAIN: Caddy serves a self-signed certificate for localhost"
    fi
    case "${APP_URL:-}" in
        ""|http://localhost*|http://127.0.0.1*)
            echo "warn|APP_URL is '${APP_URL:-}': generated links and redirects point there" ;;
    esac
    [[ "${MAIL_HOST:-}" == "mailpit" ]] \
        && echo "warn|MAIL_HOST=mailpit in ${APP_ENV}: emails are caught by Mailpit, never delivered"
    if is_production_env && [[ "${LOG_LEVEL:-}" == "debug" ]]; then
        echo "warn|LOG_LEVEL=debug in production: logs grow fast and may hold sensitive data"
    fi
    return 0
}

print_config_risks() {
    local line
    while IFS= read -r line; do
        case "$line" in
            "")      ;;
            high\|*) print_warning "${RED}${BOLD}Insecure:${NC} ${line#*|}" ;;
            *)       print_warning "${line#*|}" ;;
        esac
    done < <(config_risks)
}

# One line under the header: env · server · db · services · container
print_env_summary() {
    _is_quiet && return 0
    local sep="${DIM} · ${NC}" services=""
    [[ -n "$(parse_services)" ]] && services="${sep}${CYAN}$(parse_services | sed 's/ /, /g')${NC}"
    echo -e "  ${BOLD}${APP_ENV:-local}${NC}${sep}${SERVER:-artisan}${sep}$(get_db_driver)${services}${sep}${DIM}${CONTAINER_NAME}${NC}"
}
