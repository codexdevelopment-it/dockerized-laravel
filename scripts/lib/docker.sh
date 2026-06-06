#!/bin/bash
# =============================================================================
# Docker compose building and execution utilities
# =============================================================================

# Prevent double-sourcing
[[ -n "${_DOCKER_LOADED:-}" ]] && return 0
_DOCKER_LOADED=1

# Source dependencies
SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "${SCRIPT_LIB_DIR}/colors.sh"
source "${SCRIPT_LIB_DIR}/env.sh"
source "${SCRIPT_LIB_DIR}/utils.sh"

# Global compose args array — populated by build_compose_args(), consumed as "${_COMPOSE_ARGS[@]}"
_COMPOSE_ARGS=()

# -----------------------------------------------------------------------------
# Docker Compose Command Building
# -----------------------------------------------------------------------------

# Populate _COMPOSE_ARGS with the full docker compose invocation for the current
# environment. Uses an array to avoid eval and shell-injection via env vars.
build_compose_args() {
    local project_root="${PROJECT_ROOT:-$(get_project_root)}"
    local compose_dir="${project_root}/docker/compose"

    print_verbose "Project root: ${project_root}"
    print_verbose "Compose dir: ${compose_dir}"

    _COMPOSE_ARGS=(docker compose)

    # --- Base ---
    local base_compose="${compose_dir}/base.yml"
    if [[ ! -f "$base_compose" ]]; then
        print_error "Base compose file not found: ${base_compose}"
        return 1
    fi
    _COMPOSE_ARGS+=(-f "$base_compose")

    # --- Database ---
    local db_driver="${DB_DRIVER:-mariadb}"
    [[ "$db_driver" == "postgresql" ]] && db_driver="postgres"
    local db_compose="${compose_dir}/databases/${db_driver}.yml"
    if [[ -f "$db_compose" ]]; then
        _COMPOSE_ARGS+=(-f "$db_compose")
    else
        print_warning "Database compose file not found: ${db_compose}"
    fi

    # Database env-specific overrides (e.g. databases/mariadb-local.yml)
    local env_type
    env_type=$(get_env_compose_file)
    local db_env_compose="${compose_dir}/databases/${db_driver}-${env_type}.yml"
    if [[ -f "$db_env_compose" ]]; then
        _COMPOSE_ARGS+=(-f "$db_env_compose")
    fi

    # --- Environment ---
    local env_compose="${compose_dir}/environments/${env_type}.yml"
    # Fallback to old flat location during migration
    [[ ! -f "$env_compose" ]] && env_compose="${compose_dir}/${env_type}.yml"
    if [[ -f "$env_compose" ]]; then
        _COMPOSE_ARGS+=(-f "$env_compose")
    else
        print_warning "Environment compose file not found: ${env_compose}"
    fi

    # --- Server ---
    local server="${SERVER:-artisan}"
    local server_compose="${compose_dir}/servers/${server}.yml"
    [[ ! -f "$server_compose" ]] && server_compose="${compose_dir}/server/${server}.yml"
    if [[ -f "$server_compose" ]]; then
        _COMPOSE_ARGS+=(-f "$server_compose")
    else
        print_error "Server compose file not found: ${server}.yml"
        return 1
    fi

    # --- Optional services ---
    local services
    services=$(parse_services)
    for service in $services; do
        local service_compose="${compose_dir}/services/${service}.yml"
        if [[ -f "$service_compose" ]]; then
            _COMPOSE_ARGS+=(-f "$service_compose")
        else
            print_warning "Service compose file not found: ${service_compose}"
        fi
    done

    # --- Project name ---
    _COMPOSE_ARGS+=(-p "${CONTAINER_NAME:-app}")

    print_verbose "Compose command: ${_COMPOSE_ARGS[*]}"
    return 0
}

# -----------------------------------------------------------------------------
# Container Operations
# -----------------------------------------------------------------------------

# Start all containers.
# Docker output is always streamed — builds can take minutes and a silent terminal
# looks frozen. The --verbose flag controls dock's own chatter, not Docker's.
docker_up() {
    local build="${1:-false}"

    export RESTART_POLICY
    RESTART_POLICY=$(get_restart_policy)

    build_compose_args || return 1

    print_verbose "Restart policy: ${RESTART_POLICY}"

    local up_args=(up -d --remove-orphans)
    if [[ "$build" == "true" ]] || [[ "${SERVER:-artisan}" == "octane" ]]; then
        up_args+=(--build)
    fi

    "${_COMPOSE_ARGS[@]}" "${up_args[@]}"
}

# Stop all containers
docker_down() {
    export RESTART_POLICY
    RESTART_POLICY=$(get_restart_policy)

    build_compose_args || return 1

    print_verbose "Stopping containers..."

    if [[ "${VERBOSE:-false}" == "true" ]]; then
        "${_COMPOSE_ARGS[@]}" down
    else
        "${_COMPOSE_ARGS[@]}" down >/dev/null 2>&1
    fi
}

# Restart containers
docker_restart() {
    docker_down
    docker_up "${1:-false}"
}

# Get container status
docker_status() {
    export RESTART_POLICY
    RESTART_POLICY=$(get_restart_policy)

    build_compose_args || return 1
    "${_COMPOSE_ARGS[@]}" ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}'
}

# Get container logs
docker_logs() {
    local service="${1:-}"
    local follow="${2:-false}"
    local tail="${3:-100}"

    export RESTART_POLICY
    RESTART_POLICY=$(get_restart_policy)

    build_compose_args || return 1

    local log_args=(logs "--tail=${tail}")
    [[ "$follow" == "true" ]] && log_args+=(-f)
    [[ -n "$service" ]] && log_args+=("$service")

    "${_COMPOSE_ARGS[@]}" "${log_args[@]}"
}

# Execute command in container
docker_exec() {
    local container="${1:-${CONTAINER_NAME}}"
    shift

    if [[ $# -eq 0 ]]; then
        docker exec -it "$container" bash
    else
        docker exec -it "$container" "$@"
    fi
}

# -----------------------------------------------------------------------------
# Container Health & Status
# -----------------------------------------------------------------------------

# Check if a container is running
is_container_running() {
    local container="$1"
    docker ps --format '{{.Names}}' | grep -q "^${container}$"
}

# Wait for container to be healthy
wait_for_container() {
    local container="$1"
    local timeout="${2:-60}"
    local elapsed=0

    while (( elapsed < timeout )); do
        if is_container_running "$container"; then
            return 0
        fi
        sleep 1
        ((elapsed++))
    done

    return 1
}

# Get running container names for current project
get_running_containers() {
    local project="${CONTAINER_NAME:-app}"
    docker ps --filter "label=com.docker.compose.project=${project}" --format '{{.Names}}'
}

# Print container status in a nice format
print_container_status() {
    local containers
    containers=$(get_running_containers)

    if [[ -z "$containers" ]]; then
        print_warning "No containers running"
        return 1
    fi

    print_section "${ICON_PACKAGE} Container Status"

    local count=0
    local total
    total=$(echo "$containers" | wc -l | tr -d ' ')

    while IFS= read -r container; do
        ((count++))
        local status
        status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null)

        local status_icon
        case "$status" in
            running) status_icon="${GREEN}${CHECKMARK} running${NC}" ;;
            exited)  status_icon="${RED}${CROSSMARK} exited${NC}" ;;
            *)       status_icon="${YELLOW}● ${status}${NC}" ;;
        esac

        local is_last="false"
        [[ $count -eq $total ]] && is_last="true"

        local display_name="${container#${CONTAINER_NAME}-}"
        [[ "$display_name" == "$CONTAINER_NAME" ]] && display_name="app"

        print_tree_item "$display_name" "$status_icon" "$is_last"
    done <<< "$containers"
}

# -----------------------------------------------------------------------------
# Build Operations
# -----------------------------------------------------------------------------

# Build containers
docker_build() {
    export RESTART_POLICY
    RESTART_POLICY=$(get_restart_policy)

    build_compose_args || return 1

    print_info "Building containers..."
    "${_COMPOSE_ARGS[@]}" build
}

# Pull latest images
docker_pull() {
    export RESTART_POLICY
    RESTART_POLICY=$(get_restart_policy)

    build_compose_args || return 1

    print_info "Pulling images..."
    "${_COMPOSE_ARGS[@]}" pull
}
