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

# -----------------------------------------------------------------------------
# Docker Compose Command Building
# -----------------------------------------------------------------------------

# Build the docker compose command with all necessary files
# Usage: compose_cmd=$(build_compose_command)
build_compose_command() {
    local project_root="${PROJECT_ROOT:-$(get_project_root)}"
    local compose_dir="${project_root}/docker/compose"
    local env_file
    env_file=$(get_env_compose_file)
    
    print_verbose "Project root: ${project_root}"
    print_verbose "Compose dir: ${compose_dir}"
    
    # Start with base compose file
    local cmd="docker compose"
    
    local base_compose="${compose_dir}/base.yml"
    if [[ ! -f "$base_compose" ]]; then
        print_error "Base compose file not found: ${base_compose}"
        return 1
    fi
    cmd+=" -f ${base_compose}"
    
    # Add environment-specific compose file (try new location first)
    local env_compose="${compose_dir}/environments/${env_file}.yml"
    if [[ ! -f "$env_compose" ]]; then
        # Fallback to old location during migration
        env_compose="${compose_dir}/${env_file}.yml"
    fi
    
    if [[ -f "$env_compose" ]]; then
        cmd+=" -f ${env_compose}"
    else
        print_warning "Environment compose file not found: ${env_compose}"
    fi
    
    # Add server compose file (try new location first)
    local server="${SERVER:-artisan}"
    local server_compose="${compose_dir}/servers/${server}.yml"
    if [[ ! -f "$server_compose" ]]; then
        # Fallback to old location during migration
        server_compose="${compose_dir}/server/${server}.yml"
    fi
    
    if [[ -f "$server_compose" ]]; then
        cmd+=" -f ${server_compose}"
    else
        print_error "Server compose file not found: ${server_compose}"
        return 1
    fi
    
    # Add service compose files
    local services
    services=$(parse_services)
    for service in $services; do
        local service_compose="${compose_dir}/services/${service}.yml"
        if [[ -f "$service_compose" ]]; then
            cmd+=" -f ${service_compose}"
        else
            print_warning "Service compose file not found: ${service_compose}"
        fi
    done
    
    # Add project name
    cmd+=" -p ${CONTAINER_NAME:-app}"
    
    echo "$cmd"
}

# -----------------------------------------------------------------------------
# Container Operations
# -----------------------------------------------------------------------------

# Start all containers
docker_up() {
    local build="${1:-false}"
    local compose_cmd
    compose_cmd=$(build_compose_command) || return 1
    
    # Export restart policy for compose files
    export RESTART_POLICY
    RESTART_POLICY=$(get_restart_policy)
    
    print_verbose "Compose command: ${compose_cmd}"
    print_verbose "Restart policy: ${RESTART_POLICY}"
    
    local up_cmd="${compose_cmd} up -d --remove-orphans"
    
    if [[ "$build" == "true" ]] || [[ "${SERVER:-artisan}" == "octane" ]]; then
        up_cmd+=" --build"
    fi
    
    print_verbose "Running: ${up_cmd}"
    
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        eval "$up_cmd"
    else
        eval "$up_cmd" 2>&1 | head -20 || true
    fi
}

# Stop all containers
docker_down() {
    local compose_cmd
    compose_cmd=$(build_compose_command) || return 1
    
    # Export restart policy for compose files
    export RESTART_POLICY
    RESTART_POLICY=$(get_restart_policy)
    
    print_verbose "Running: ${compose_cmd} down"
    
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        eval "${compose_cmd} down"
    else
        eval "${compose_cmd} down" 2>&1 | head -10 || true
    fi
}

# Restart containers
docker_restart() {
    docker_down
    docker_up "${1:-false}"
}

# Get container status
docker_status() {
    local compose_cmd
    compose_cmd=$(build_compose_command) || return 1
    
    # Export restart policy for compose files
    export RESTART_POLICY
    RESTART_POLICY=$(get_restart_policy)
    
    eval "${compose_cmd} ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}'"
}

# Get container logs
docker_logs() {
    local service="${1:-}"
    local follow="${2:-false}"
    local tail="${3:-100}"
    local compose_cmd
    compose_cmd=$(build_compose_command) || return 1
    
    # Export restart policy for compose files
    export RESTART_POLICY
    RESTART_POLICY=$(get_restart_policy)
    
    local cmd="${compose_cmd} logs --tail=${tail}"
    
    [[ "$follow" == "true" ]] && cmd+=" -f"
    [[ -n "$service" ]] && cmd+=" ${service}"
    
    eval "$cmd"
}

# Execute command in container
docker_exec() {
    local container="${1:-${CONTAINER_NAME}}"
    shift
    local cmd="$*"
    
    if [[ -z "$cmd" ]]; then
        # Interactive shell
        docker exec -it "$container" bash
    else
        docker exec -it "$container" $cmd
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
        
        # Strip project name prefix for cleaner display
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
    local compose_cmd
    compose_cmd=$(build_compose_command) || return 1
    
    # Export restart policy for compose files
    export RESTART_POLICY
    RESTART_POLICY=$(get_restart_policy)
    
    print_info "Building containers..."
    eval "${compose_cmd} build"
}

# Pull latest images
docker_pull() {
    local compose_cmd
    compose_cmd=$(build_compose_command) || return 1
    
    # Export restart policy for compose files
    export RESTART_POLICY
    RESTART_POLICY=$(get_restart_policy)
    
    print_info "Pulling images..."
    eval "${compose_cmd} pull"
}
