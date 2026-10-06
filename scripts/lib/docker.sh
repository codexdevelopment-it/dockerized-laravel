#!/usr/bin/env bash
# =============================================================================
# Compose assembly and container helpers.
# The compose invocation is an array (_COMPOSE_ARGS): no eval, no string
# commands, so values from .env can never be executed.
# =============================================================================

[[ -n "${_DOCKER_LOADED:-}" ]] && return 0
_DOCKER_LOADED=1

SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "${SCRIPT_LIB_DIR}/colors.sh"
source "${SCRIPT_LIB_DIR}/env.sh"

_COMPOSE_ARGS=()

# Fill _COMPOSE_ARGS with: base, database (+ env override), environment,
# server, then one file per SERVICES entry.
build_compose_args() {
    local dir="${PROJECT_ROOT}/docker/compose" env db file service
    prepare_compose_env
    env="$DOCK_ENV"
    db="$DB_DRIVER"

    _COMPOSE_ARGS=(docker compose -p "${CONTAINER_NAME}")

    for file in "base.yml" "databases/${db}.yml" "databases/${db}-${env}.yml" \
                "environments/${env}.yml" "servers/${SERVER:-artisan}.yml"; do
        if [[ -f "${dir}/${file}" ]]; then
            _COMPOSE_ARGS+=(-f "${dir}/${file}")
        elif [[ "$file" != "databases/${db}-${env}.yml" ]]; then
            print_error "Missing compose file: docker/compose/${file}"
            return 1
        fi
    done

    for service in $(parse_services); do
        file="${dir}/services/${service}.yml"
        if [[ ! -f "$file" ]]; then
            print_error "Unknown service '${service}' in SERVICES (no docker/compose/services/${service}.yml)"
            return 1
        fi
        _COMPOSE_ARGS+=(-f "$file")
    done

    print_debug "${_COMPOSE_ARGS[*]}"
}

# compose <args...>: run docker compose with the assembled file list.
compose() {
    build_compose_args || return 1
    "${_COMPOSE_ARGS[@]}" "$@"
}

# -----------------------------------------------------------------------------
# Exec helpers. Commands run as the `laravel` user by default: running artisan
# as root leaves root-owned logs/caches the app can no longer write.
# -----------------------------------------------------------------------------

# Interactive exec in the app container: -t only with a real terminal, so
# `./dock artisan ... | grep` and CI work.
# app_exec [--root] <cmd...>
app_exec() {
    local user="laravel" flags=(-i)
    if [[ "${1:-}" == "--root" ]]; then user="root"; shift; fi
    [[ -t 0 && -t 1 ]] && flags+=(-t)
    docker exec "${flags[@]}" -u "$user" "${CONTAINER_NAME}" "$@"
}

# Non-interactive exec (scripts, deploy). app_run [--root] <cmd...>
app_run() {
    local user="laravel"
    if [[ "${1:-}" == "--root" ]]; then user="root"; shift; fi
    docker exec -u "$user" "${CONTAINER_NAME}" "$@"
}

# Same, but output only shown in verbose mode and failures tolerated.
app_try() {
    local label="$1"; shift
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        app_run "$@" || print_warning "${label} failed (continuing)"
    else
        app_run "$@" >/dev/null 2>&1 || true
    fi
    return 0
}

ensure_app_running() {
    if ! is_container_running "${CONTAINER_NAME}"; then
        print_error "Container '${CONTAINER_NAME}' is not running. Start it with: ./dock start"
        return 1
    fi
}

is_container_running() {
    [[ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" == "true" ]]
}

supervisorctl_app() {
    app_run --root supervisorctl -c /etc/supervisor/conf.d/00-base.conf "$@"
}

# Restart the HTTP server program after caches/code change.
reload_app_server() {
    case "${SERVER:-artisan}" in
        octane) app_run php artisan octane:reload >/dev/null 2>&1 || supervisorctl_app restart octane >/dev/null 2>&1 ;;
        nginx|caddy|fpm) supervisorctl_app restart php-fpm >/dev/null 2>&1 ;;
        artisan) supervisorctl_app restart artisan-serve >/dev/null 2>&1 ;;
    esac
    return 0
}

# Shown at the end of start/deploy.
app_url() {
    case "${SERVER:-artisan}" in
        caddy)
            if [[ -n "${DOMAIN:-}" && "${DOMAIN}" != "localhost" ]]; then
                echo "https://${DOMAIN}"
            else
                echo "https://localhost$([[ "${HTTPS_PORT:-443}" != 443 ]] && echo ":${HTTPS_PORT}")"
            fi ;;
        fpm) echo "fastcgi://127.0.0.1:${APP_PORT:-9000}" ;;
        *)   echo "http://localhost:${APP_PORT:-8000}" ;;
    esac
}

# Image tag of the app for the current env/server.
app_image() { echo "${CONTAINER_NAME}:${DOCK_ENV:-local}${DOCK_IMAGE_SUFFIX:-}"; }

app_image_exists() { docker image inspect "$(app_image)" >/dev/null 2>&1; }

# "0.0.0.0:8000->8000/tcp, [::]:8000->8000/tcp, 9000/tcp" -> "8000" ; 127.0.0.1 kept explicit.
_compact_ports() {
    tr ',' '\n' | sed -n 's/^ *\([^ ]*\):\([0-9]*\)->\([0-9]*\).*/\1 \2/p' \
        | awk '{ if ($1 == "127.0.0.1") p = "127.0.0.1:" $2; else p = $2; if (!seen[p]++) printf "%s%s", (n++ ? ", " : ""), p }'
}

# Table of the project's containers: service, state, health, published ports.
print_container_status() {
    local rows service state health ports icon color
    rows="$(compose ps -a --format '{{.Service}}|{{.State}}|{{.Health}}|{{.Ports}}' 2>/dev/null | sort)"
    if [[ -z "$rows" ]]; then
        print_warning "No containers for project '${CONTAINER_NAME}' (./dock start)"
        return 1
    fi
    _is_quiet && return 0

    echo ""
    printf "  ${DIM}%-14s %-12s %-11s %s${NC}\n" "SERVICE" "STATE" "HEALTH" "PORTS"
    while IFS='|' read -r service state health ports; do
        case "$state:$health" in
            running:unhealthy) icon="●"; color="$YELLOW" ;;
            running:starting)  icon="●"; color="$CYAN" ;;
            running:*)         icon="●"; color="$GREEN" ;;
            restarting:*)      icon="↻"; color="$YELLOW" ;;
            *)                 icon="○"; color="$RED" ;;
        esac
        case "$health" in
            healthy)   health="${GREEN}healthy${NC}  " ;;
            unhealthy) health="${YELLOW}unhealthy${NC}" ;;
            starting)  health="${CYAN}starting${NC} " ;;
            *)         health="${DIM}-${NC}        " ;;
        esac
        ports="$(echo "$ports" | _compact_ports)"
        printf "  %-14s ${color}%s %-10s${NC} %b   %s\n" "$service" "$icon" "$state" "$health" "${ports:--}"
    done <<< "$rows"
}
