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

    # FrankenPHP is only baked into octane images; the tag differs so switching
    # SERVER triggers a build instead of reusing an image without the binary.
    if [[ "${SERVER:-artisan}" == "octane" ]]; then
        DOCK_WITH_FRANKENPHP=1 DOCK_IMAGE_SUFFIX="-octane"
    else
        DOCK_WITH_FRANKENPHP=0 DOCK_IMAGE_SUFFIX=""
    fi

    export DOCK_ENV DB_DRIVER RESTART_POLICY USER_ID GROUP_ID \
        STORAGE_MOUNT_PATH DB_MOUNT_PATH DOCK_WITH_FRANKENPHP DOCK_IMAGE_SUFFIX
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
    if [[ "${SERVER:-}" == "artisan" ]] && ! is_local_env; then
        print_warning "SERVER=artisan is a development server; use octane, nginx or caddy in ${APP_ENV}"
    fi
    if ! is_local_env && [[ "${APP_DEBUG:-false}" == "true" ]]; then
        print_warning "APP_DEBUG=true in ${APP_ENV}: stack traces and env values are exposed to visitors"
    fi
    if [[ "$operation" == "deploy" && "${DB_PASSWORD:-}" == "password" ]]; then
        print_warning "DB_PASSWORD is still the template default 'password'"
    fi

    return "$errors"
}

# One line under the header: env · server · db · services · container
print_env_summary() {
    _is_quiet && return 0
    local sep="${DIM} · ${NC}" services=""
    [[ -n "$(parse_services)" ]] && services="${sep}${CYAN}$(parse_services | sed 's/ /, /g')${NC}"
    echo -e "  ${BOLD}${APP_ENV:-local}${NC}${sep}${SERVER:-artisan}${sep}$(get_db_driver)${services}${sep}${DIM}${CONTAINER_NAME}${NC}"
}
