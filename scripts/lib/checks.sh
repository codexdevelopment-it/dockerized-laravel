#!/bin/bash
# =============================================================================
# Pre-flight checks and validation utilities
# =============================================================================

# Prevent double-sourcing
[[ -n "${_CHECKS_LOADED:-}" ]] && return 0
_CHECKS_LOADED=1

# Source dependencies
SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "${SCRIPT_LIB_DIR}/colors.sh"
source "${SCRIPT_LIB_DIR}/utils.sh"

# -----------------------------------------------------------------------------
# System Checks
# -----------------------------------------------------------------------------

# Check if Docker is installed and running
check_docker() {
    print_verbose "Checking Docker..."
    
    if ! command_exists docker; then
        print_error "Docker is not installed"
        print_info "Please install Docker: https://docs.docker.com/get-docker/"
        return 1
    fi
    
    if ! docker info &>/dev/null; then
        print_error "Docker daemon is not running"
        print_info "Please start Docker and try again"
        return 1
    fi
    
    print_verbose "Docker is running"
    return 0
}

# Check if Docker Compose is available
check_docker_compose() {
    print_verbose "Checking Docker Compose..."
    
    if ! docker compose version &>/dev/null; then
        print_error "Docker Compose is not available"
        print_info "Docker Compose V2 is required (comes with Docker Desktop)"
        return 1
    fi
    
    print_verbose "Docker Compose is available"
    return 0
}

# Check if a port is available
check_port_available() {
    local port="$1"
    local name="${2:-Port}"
    
    if lsof -Pi ":${port}" -sTCP:LISTEN -t &>/dev/null; then
        print_error "${name} ${port} is already in use"
        return 1
    fi
    
    print_verbose "Port ${port} is available"
    return 0
}

# Check if required ports are available
check_required_ports() {
    local errors=0
    
    print_verbose "Checking required ports..."
    
    # Main app port
    local app_port="${APP_PORT:-8000}"
    check_port_available "$app_port" "App port" || ((errors++))
    
    # Database port (only if local env and DB exposed)
    if is_local_env; then
        check_port_available 3306 "Database port" || ((errors++))
    fi
    
    # Check service ports
    local services
    services=$(parse_services)
    for service in $services; do
        case "$service" in
            redis)     check_port_available 6379 "Redis port" || ((errors++)) ;;
            mailpit)   check_port_available 8025 "Mailpit UI port" || ((errors++)) ;;
            meilisearch) check_port_available 7700 "Meilisearch port" || ((errors++)) ;;
            phpmyadmin) check_port_available 8080 "phpMyAdmin port" || ((errors++)) ;;
        esac
    done
    
    return $errors
}

# -----------------------------------------------------------------------------
# File System Checks
# -----------------------------------------------------------------------------

# Check if we're in a valid project directory
check_project_directory() {
    local project_root="${1:-$(pwd)}"
    
    print_verbose "Checking project directory: ${project_root}"
    
    if [[ ! -f "${project_root}/.env" ]]; then
        print_error "Not a valid project directory: .env not found"
        print_info "Please run this command from your project root"
        return 1
    fi
    
    if [[ ! -d "${project_root}/docker" ]]; then
        print_error "Docker configuration not found"
        print_info "Please run the install script first"
        return 1
    fi
    
    return 0
}

# Check if docker compose files exist
check_compose_files() {
    local project_root="${1:-$(pwd)}"
    local compose_dir="${project_root}/docker/compose"
    local errors=0
    
    print_verbose "Checking compose files..."
    
    # Check base.yml
    if [[ ! -f "${compose_dir}/base.yml" ]]; then
        print_error "Missing: docker/compose/base.yml"
        ((errors++))
    fi
    
    # Check environment file
    local env_file
    env_file=$(get_env_compose_file)
    local env_compose="${compose_dir}/environments/${env_file}.yml"
    
    # Try old location as fallback
    if [[ ! -f "$env_compose" ]]; then
        env_compose="${compose_dir}/${env_file}.yml"
    fi
    
    if [[ ! -f "$env_compose" ]]; then
        print_error "Missing environment compose: ${env_file}.yml"
        ((errors++))
    fi
    
    # Check server file
    local server="${SERVER:-artisan}"
    local server_compose="${compose_dir}/servers/${server}.yml"
    
    # Try old location as fallback
    if [[ ! -f "$server_compose" ]]; then
        server_compose="${compose_dir}/server/${server}.yml"
    fi
    
    if [[ ! -f "$server_compose" ]]; then
        print_error "Missing server compose: ${server}.yml"
        ((errors++))
    fi
    
    return $errors
}

# Check file permissions
check_permissions() {
    local project_root="${1:-$(pwd)}"
    local errors=0
    
    print_verbose "Checking permissions..."
    
    # Check if scripts are executable
    for script in "${project_root}"/scripts/*.sh; do
        if [[ -f "$script" ]] && [[ ! -x "$script" ]]; then
            print_warning "Script not executable: $(basename "$script")"
            chmod +x "$script" 2>/dev/null && print_verbose "Fixed: $script"
        fi
    done
    
    # Check lib scripts
    for script in "${project_root}"/scripts/lib/*.sh; do
        if [[ -f "$script" ]] && [[ ! -x "$script" ]]; then
            chmod +x "$script" 2>/dev/null
        fi
    done
    
    return $errors
}

# -----------------------------------------------------------------------------
# Pre-flight Check Runner
# -----------------------------------------------------------------------------

# Run all pre-flight checks
# Usage: run_preflight_checks [operation]
run_preflight_checks() {
    local operation="${1:-start}"
    local project_root="${2:-$(pwd)}"
    local errors=0
    local warnings=0
    
    print_verbose "Running pre-flight checks for: ${operation}"
    
    # Always check Docker
    check_docker || ((errors++))
    check_docker_compose || ((errors++))
    
    # Stop early if Docker isn't available
    if [[ $errors -gt 0 ]]; then
        print_error "Pre-flight checks failed (${errors} errors)"
        return 1
    fi
    
    case "$operation" in
        start|up)
            check_project_directory "$project_root" || ((errors++))
            check_compose_files "$project_root" || ((errors++))
            check_permissions "$project_root"
            # Port checks are warnings, not errors
            check_required_ports || ((warnings++))
            ;;
        stop|down)
            check_project_directory "$project_root" || ((errors++))
            ;;
        deploy)
            check_project_directory "$project_root" || ((errors++))
            check_compose_files "$project_root" || ((errors++))
            ;;
        status|logs)
            check_project_directory "$project_root" || ((errors++))
            ;;
    esac
    
    if [[ $errors -gt 0 ]]; then
        print_error "Pre-flight checks failed (${errors} errors)"
        return 1
    fi
    
    if [[ $warnings -gt 0 ]]; then
        print_warning "Pre-flight checks passed with ${warnings} warning(s)"
    else
        print_verbose "All pre-flight checks passed"
    fi
    
    return 0
}

# -----------------------------------------------------------------------------
# Laravel-specific Checks
# -----------------------------------------------------------------------------

# Check if Laravel is properly installed in the container
check_laravel_installed() {
    local container="${CONTAINER_NAME:-app}"
    
    if ! docker exec "$container" test -f artisan 2>/dev/null; then
        print_warning "Laravel not detected in container"
        return 1
    fi
    
    return 0
}

# Check if Octane is installed (for octane server)
check_octane_installed() {
    local container="${CONTAINER_NAME:-app}"
    
    if ! docker exec "$container" php artisan list 2>/dev/null | grep -q "octane:"; then
        return 1
    fi
    
    return 0
}

# Check storage permissions inside container
check_storage_permissions() {
    local container="${CONTAINER_NAME:-app}"
    
    docker exec "$container" test -w storage 2>/dev/null
}
