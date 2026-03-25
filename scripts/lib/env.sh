#!/bin/bash
# =============================================================================
# Environment loading and validation utilities
# =============================================================================

# Prevent double-sourcing
[[ -n "${_ENV_LOADED:-}" ]] && return 0
_ENV_LOADED=1

# Source dependencies
SCRIPT_LIB_DIR="${SCRIPT_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "${SCRIPT_LIB_DIR}/colors.sh"

# -----------------------------------------------------------------------------
# Environment Loading
# -----------------------------------------------------------------------------

# Load environment variables from a file
# Usage: load_env [path_to_env_file]
load_env() {
    local env_file="${1:-.env}"
    
    if [[ ! -f "$env_file" ]]; then
        print_error "Environment file not found: ${env_file}"
        return 1
    fi
    
    print_verbose "Loading environment from: ${env_file}"
    
    # Export variables from .env file
    # Read line by line to handle comments and empty lines
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Only process lines that look like VAR=value
        if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local var_value="${BASH_REMATCH[2]}"
            
            # Remove surrounding quotes if present
            var_value="${var_value#\"}"
            var_value="${var_value%\"}"
            var_value="${var_value#\'}"
            var_value="${var_value%\'}"
            
            # Export the variable
            export "$var_name=$var_value"
        fi
    done < "$env_file"
    
    return 0
}

# Get the project root directory (where .env lives)
get_project_root() {
    local current_dir
    current_dir="$(pwd)"
    
    # Walk up the directory tree looking for .env
    while [[ "$current_dir" != "/" ]]; do
        if [[ -f "${current_dir}/.env" ]] && [[ -d "${current_dir}/docker" ]]; then
            echo "$current_dir"
            return 0
        fi
        current_dir="$(dirname "$current_dir")"
    done
    
    # Fallback to current directory
    echo "$(pwd)"
}

# -----------------------------------------------------------------------------
# Environment Validation
# -----------------------------------------------------------------------------

# Required environment variables for different operations
readonly REQUIRED_VARS_START="CONTAINER_NAME APP_ENV SERVER"
readonly REQUIRED_VARS_DEPLOY="REPO_URL BRANCH DEPLOY_DIR"

# Validate that required environment variables are set
# Usage: validate_env <operation>
validate_env() {
    local operation="${1:-start}"
    local required_vars
    local missing_vars=()
    
    case "$operation" in
        start)  required_vars=$REQUIRED_VARS_START ;;
        deploy) required_vars="$REQUIRED_VARS_START $REQUIRED_VARS_DEPLOY" ;;
        *)      required_vars=$REQUIRED_VARS_START ;;
    esac
    
    for var in $required_vars; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        print_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var" >&2
        done
        return 1
    fi
    
    return 0
}

# Validate APP_ENV value
validate_app_env() {
    local env="${APP_ENV:-local}"
    
    case "$env" in
        local|development|staging|production)
            return 0
            ;;
        *)
            print_error "Invalid APP_ENV value: ${env}"
            print_info "Valid values: local, development, staging, production"
            return 1
            ;;
    esac
}

# Validate SERVER value
validate_server() {
    local server="${SERVER:-artisan}"
    local valid_servers="artisan octane fpm nginx caddy"
    
    if [[ ! " $valid_servers " =~ " $server " ]]; then
        print_error "Invalid SERVER value: ${server}"
        print_info "Valid values: ${valid_servers}"
        return 1
    fi
    
    return 0
}

# Full environment validation
validate_full_env() {
    local operation="${1:-start}"
    local errors=0
    
    validate_env "$operation" || ((errors++))
    validate_app_env || ((errors++))
    validate_server || ((errors++))
    
    return $errors
}

# -----------------------------------------------------------------------------
# Environment Helpers
# -----------------------------------------------------------------------------

# Check if we're in a local/development environment
is_local_env() {
    [[ "${APP_ENV:-local}" == "local" ]] || [[ "${APP_ENV:-local}" == "development" ]]
}

# Check if we're in a production environment
is_production_env() {
    [[ "${APP_ENV:-local}" == "production" ]]
}

# Check if we're in a staging environment
is_staging_env() {
    [[ "${APP_ENV:-local}" == "staging" ]]
}

# Get the restart policy based on environment
get_restart_policy() {
    if is_local_env; then
        echo "no"
    else
        echo "always"
    fi
}

# Get the environment file for compose (local, staging, or production)
get_env_compose_file() {
    local env="${APP_ENV:-local}"
    
    case "$env" in
        local|development) echo "local" ;;
        staging)           echo "staging" ;;
        production)        echo "production" ;;
        *)                 echo "local" ;;
    esac
}

# Convert SERVICES comma-separated string to array
parse_services() {
    local services_str="${SERVICES:-}"
    
    if [[ -z "$services_str" ]]; then
        echo ""
        return 0
    fi
    
    # Convert comma-separated to space-separated
    echo "${services_str//,/ }"
}

# Print environment summary
print_env_summary() {
    local services
    services=$(parse_services)
    
    print_section "${ICON_GEAR} Configuration"
    print_kv "Environment" "${APP_ENV:-local}"
    print_kv "Server" "${SERVER:-artisan}"
    print_kv "Container" "${CONTAINER_NAME:-unknown}"
    print_kv "Port" "${APP_PORT:-8000}"
    
    if [[ -n "$services" ]]; then
        print_kv "Services" "$services"
    fi
    
    print_nl
}
