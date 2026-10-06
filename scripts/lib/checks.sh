#!/usr/bin/env bash
# =============================================================================
# Pre-flight checks. Errors stop the command; port conflicts only warn.
# =============================================================================

[[ -n "${_CHECKS_LOADED:-}" ]] && return 0
_CHECKS_LOADED=1

SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "${SCRIPT_LIB_DIR}/colors.sh"
source "${SCRIPT_LIB_DIR}/utils.sh"
source "${SCRIPT_LIB_DIR}/env.sh"

check_docker() {
    if ! command_exists docker; then
        print_error "Docker is not installed: https://docs.docker.com/get-docker/"
        return 1
    fi
    if ! docker info &>/dev/null; then
        print_error "Docker daemon is not running (or this user can't reach it)"
        print_info "Linux: sudo usermod -aG docker \$USER && newgrp docker"
        return 1
    fi
    if ! docker compose version &>/dev/null; then
        print_error "Docker Compose v2 is required (docker compose ...)"
        return 1
    fi
}

# port_in_use <port>: best effort, silent when no tool is available.
port_in_use() {
    if command_exists lsof; then
        lsof -nP -iTCP:"$1" -sTCP:LISTEN -t &>/dev/null
    elif command_exists ss; then
        ss -ltnH "sport = :$1" 2>/dev/null | grep -q .
    else
        return 1
    fi
}

# Host ports this configuration publishes, as "port:label" pairs.
published_ports() {
    case "${SERVER:-artisan}" in
        caddy) echo "${HTTP_PORT:-80}:HTTP ${HTTPS_PORT:-443}:HTTPS" ;;
        *)     echo "${APP_PORT:-8000}:App" ;;
    esac
    if [[ "$(get_env_compose_file)" != "production" ]]; then
        if is_postgres_driver; then echo "${FORWARD_DB_PORT:-5432}:Database"; else echo "${FORWARD_DB_PORT:-3306}:Database"; fi
    fi
    local s
    for s in $(parse_services); do
        case "$s" in
            redis)       echo "${FORWARD_REDIS_PORT:-6379}:Redis" ;;
            mailpit)     echo "${MAILPIT_UI_PORT:-8025}:Mailpit ${MAILPIT_SMTP_PORT:-1025}:Mailpit-SMTP" ;;
            meilisearch) echo "${MEILISEARCH_PORT:-7700}:Meilisearch" ;;
            phpmyadmin)  echo "${PHPMYADMIN_PORT:-8080}:phpMyAdmin" ;;
            soketi)      echo "${SOKETI_PORT:-6001}:Soketi" ;;
            gotenberg)   echo "${GOTENBERG_PORT:-3000}:Gotenberg" ;;
        esac
    done
}

# Warn about ports already taken. Skipped when our own stack is running
# (it is the one holding them).
check_ports() {
    local pair conflicts=0
    if docker ps -q --filter "label=com.docker.compose.project=${CONTAINER_NAME}" 2>/dev/null | grep -q .; then
        return 0
    fi
    for pair in $(published_ports); do
        if port_in_use "${pair%%:*}"; then
            print_warning "${pair#*:} port ${pair%%:*} is already in use"
            conflicts=$((conflicts + 1))
        fi
    done
    return "$conflicts"
}

run_preflight_checks() {
    check_docker || return 1
    if [[ ! -d "${PROJECT_ROOT}/docker/compose" ]]; then
        print_error "docker/compose not found in ${PROJECT_ROOT}: is dockerized-laravel installed?"
        return 1
    fi
    check_ports || true
}
