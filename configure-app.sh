#!/bin/bash
# =============================================================================
# Dockerized Laravel - Installation Script
# Sets up a new or existing Laravel project with Docker configuration
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
REPO_URL="https://github.com/Murkrow02/dockerized-laravel"
VERSION="2.0.0"

# Colors and formatting
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' DIM='' NC=''
fi

# Icons
ICON_DOCKER="🐳"
ICON_CHECK="✓"
ICON_CROSS="✗"
ICON_ARROW="→"

# -----------------------------------------------------------------------------
# Default Values
# -----------------------------------------------------------------------------
APP_TYPE=""
APP_NAME=""
CONTAINER_BASE_NAME=""
REPO_URL_PROJECT=""
DB_NAME=""
NON_INTERACTIVE=false
SKIP_CONFIRM=false

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------
show_help() {
    echo ""
    echo -e "${BOLD}${ICON_DOCKER} Dockerized Laravel Installer${NC} v${VERSION}"
    echo ""
    echo -e "${BOLD}USAGE${NC}"
    echo "    ./configure-app.sh [options]"
    echo "    bash <(curl -s ${REPO_URL}/raw/main/configure-app.sh) [options]"
    echo ""
    echo -e "${BOLD}OPTIONS${NC}"
    echo "    -t, --type <new|existing>    Project type (new or existing Laravel app)"
    echo "    -n, --name <name>            Application name"
    echo "    -c, --container <name>       Container base name (e.g., 'myapp' -> 'myapp-mariadb')"
    echo "    -r, --repo <url>             Repository URL (for deployment)"
    echo "    -d, --database <name>        Database name (defaults to container name)"
    echo ""
    echo "    --non-interactive            Run without prompts (requires all options)"
    echo "    -y, --yes                    Skip confirmation prompts"
    echo "    -h, --help                   Show this help message"
    echo "    -V, --version                Show version"
    echo ""
    echo -e "${BOLD}EXAMPLES${NC}"
    echo "    # Interactive mode"
    echo "    ./configure-app.sh"
    echo ""
    echo "    # Non-interactive: new project"
    echo "    ./configure-app.sh -t new -n \"My App\" -c myapp --non-interactive"
    echo ""
    echo "    # Non-interactive: existing project"
    echo "    ./configure-app.sh -t existing -n \"My App\" -c myapp -r https://github.com/user/repo --non-interactive"
    echo ""
}

# -----------------------------------------------------------------------------
# Output Functions
# -----------------------------------------------------------------------------
print_header() {
    echo ""
    echo -e "${CYAN}╭──────────────────────────────────────────╮${NC}"
    echo -e "${CYAN}│${NC}  ${BOLD}${ICON_DOCKER} Dockerized Laravel Installer${NC}"
    echo -e "${CYAN}│${NC}  ${DIM}v${VERSION}${NC}"
    echo -e "${CYAN}╰──────────────────────────────────────────╯${NC}"
    echo ""
}

print_success() { echo -e "${GREEN}${ICON_CHECK}${NC} $*"; }
print_error() { echo -e "${RED}${ICON_CROSS}${NC} $*" >&2; }
print_info() { echo -e "${BLUE}${ICON_ARROW}${NC} $*"; }
print_warning() { echo -e "${YELLOW}!${NC} $*"; }

print_step() {
    local step=$1
    local total=$2
    local message=$3
    echo ""
    echo -e "${BOLD}[${step}/${total}]${NC} ${message}"
    echo -e "${DIM}$(printf '─%.0s' {1..40})${NC}"
}

# -----------------------------------------------------------------------------
# Validation Functions
# -----------------------------------------------------------------------------
validate_name() {
    local name="$1"
    if [[ -z "$name" ]]; then
        print_error "Name cannot be empty"
        return 1
    fi
    return 0
}

validate_container_name() {
    local name="$1"
    if [[ -z "$name" ]]; then
        print_error "Container name cannot be empty"
        return 1
    fi
    # Container names must be lowercase alphanumeric with hyphens
    if [[ ! "$name" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]] && [[ ! "$name" =~ ^[a-z0-9]$ ]]; then
        print_error "Container name must be lowercase alphanumeric (hyphens allowed)"
        return 1
    fi
    return 0
}

validate_inputs() {
    local errors=0
    
    if [[ -z "$APP_TYPE" ]]; then
        print_error "Project type is required (-t new|existing)"
        ((errors++))
    elif [[ "$APP_TYPE" != "new" ]] && [[ "$APP_TYPE" != "existing" ]]; then
        print_error "Invalid project type: $APP_TYPE (must be 'new' or 'existing')"
        ((errors++))
    fi
    
    validate_name "$APP_NAME" || ((errors++))
    validate_container_name "$CONTAINER_BASE_NAME" || ((errors++))
    
    return $errors
}

# -----------------------------------------------------------------------------
# Interactive Prompts
# -----------------------------------------------------------------------------
prompt_project_type() {
    echo -e "${BLUE}What type of project?${NC}"
    echo "  1) New Laravel application"
    echo "  2) Existing Laravel application"
    echo ""
    while true; do
        read -r -p "Enter choice [1-2]: " choice
        case "$choice" in
            1) APP_TYPE="new"; break ;;
            2) APP_TYPE="existing"; break ;;
            *) print_error "Invalid choice. Please enter 1 or 2." ;;
        esac
    done
}

prompt_inputs() {
    echo ""
    
    read -r -p "$(echo -e "${BLUE}Application name:${NC} ")" APP_NAME
    validate_name "$APP_NAME" || { prompt_inputs; return; }
    
    # Suggest a container name based on app name
    local suggested_container
    suggested_container=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
    
    read -r -p "$(echo -e "${BLUE}Container base name${NC} [${suggested_container}]: ")" CONTAINER_BASE_NAME
    CONTAINER_BASE_NAME="${CONTAINER_BASE_NAME:-$suggested_container}"
    validate_container_name "$CONTAINER_BASE_NAME" || { prompt_inputs; return; }
    
    read -r -p "$(echo -e "${BLUE}Repository URL${NC} (optional, for deployment): ")" REPO_URL_PROJECT
    
    read -r -p "$(echo -e "${BLUE}Database name${NC} [${CONTAINER_BASE_NAME}]: ")" DB_NAME
    DB_NAME="${DB_NAME:-$CONTAINER_BASE_NAME}"
}

# -----------------------------------------------------------------------------
# Configuration Summary
# -----------------------------------------------------------------------------
print_summary() {
    echo ""
    echo -e "${BOLD}Configuration Summary${NC}"
    echo -e "${DIM}$(printf '─%.0s' {1..40})${NC}"
    printf "  %-20s %s\n" "Project type:" "$APP_TYPE"
    printf "  %-20s %s\n" "Application name:" "$APP_NAME"
    printf "  %-20s %s\n" "Container name:" "$CONTAINER_BASE_NAME"
    printf "  %-20s %s\n" "Database name:" "$DB_NAME"
    [[ -n "$REPO_URL_PROJECT" ]] && printf "  %-20s %s\n" "Repository:" "$REPO_URL_PROJECT"
    echo ""
}

confirm_proceed() {
    if [[ "$SKIP_CONFIRM" == "true" ]]; then
        return 0
    fi
    
    read -r -p "$(echo -e "${YELLOW}Proceed with installation?${NC} [Y/n]: ")" response
    # Use tr for bash 3.x compatibility (macOS default)
    response=$(echo "$response" | tr '[:upper:]' '[:lower:]')
    case "$response" in
        n|no) return 1 ;;
        *)    return 0 ;;
    esac
}

# -----------------------------------------------------------------------------
# Installation Functions
# -----------------------------------------------------------------------------
update_config_file() {
    local file=$1
    local mac_sed_flag=""
    [[ "$(uname)" == "Darwin" ]] && mac_sed_flag=".bak"
    
    if [[ -n "$mac_sed_flag" ]]; then
        sed -i "$mac_sed_flag" "s/{{APP_NAME}}/$APP_NAME/g" "$file"
        sed -i "$mac_sed_flag" "s/{{CONTAINER_NAME}}/$CONTAINER_BASE_NAME/g" "$file"
        sed -i "$mac_sed_flag" "s/{{DB_NAME}}/$DB_NAME/g" "$file"
        sed -i "$mac_sed_flag" "s|{{REPO_URL}}|$REPO_URL_PROJECT|g" "$file"
        rm -f "${file}.bak" 2>/dev/null
    else
        sed -i "s/{{APP_NAME}}/$APP_NAME/g" "$file"
        sed -i "s/{{CONTAINER_NAME}}/$CONTAINER_BASE_NAME/g" "$file"
        sed -i "s/{{DB_NAME}}/$DB_NAME/g" "$file"
        sed -i "s|{{REPO_URL}}|$REPO_URL_PROJECT|g" "$file"
    fi
}

cleanup_on_error() {
    print_error "Installation failed. Cleaning up..."
    [[ -d "dockerized-laravel" ]] && rm -rf dockerized-laravel
}

install_dockerized_laravel() {
    trap cleanup_on_error ERR
    
    local total_steps=5
    local current_step=0
    
    # Step 1: Clone repository
    ((current_step++))
    print_step $current_step $total_steps "Downloading dockerized-laravel"
    
    [[ -d "dockerized-laravel" ]] && rm -rf dockerized-laravel
    
    if ! git clone --depth 1 "$REPO_URL" dockerized-laravel 2>&1 | grep -v "^$"; then
        print_error "Failed to clone repository"
        return 1
    fi
    print_success "Repository cloned"
    
    cd dockerized-laravel || exit 1
    
    # Step 2: Make scripts executable
    ((current_step++))
    print_step $current_step $total_steps "Setting up scripts"
    
    chmod +x dock scripts/*.sh scripts/lib/*.sh 2>/dev/null || true
    print_success "Scripts configured"
    
    # Step 3: Update configuration files
    ((current_step++))
    print_step $current_step $total_steps "Configuring project"
    
    local config_files=(".env" "docker/config/nginx/default.conf" "docker/config/caddy/Caddyfile")
    for file in "${config_files[@]}"; do
        if [[ -f "$file" ]]; then
            update_config_file "$file"
            print_success "Updated $file"
        fi
    done
    
    # Step 4: Handle project type
    ((current_step++))
    if [[ "$APP_TYPE" == "new" ]]; then
        print_step $current_step $total_steps "Creating new Laravel project"
        
        ./dock start --build
        docker exec "$CONTAINER_BASE_NAME" composer global require laravel/installer
        docker exec -it "$CONTAINER_BASE_NAME" sh -c "~/.composer/vendor/bin/laravel new $CONTAINER_BASE_NAME"
        
        # Move new project outside dockerized-laravel folder
        mv "$CONTAINER_BASE_NAME" ..
        cd ..
        
        # Copy docker and scripts to the new project
        for dir in dockerized-laravel/docker dockerized-laravel/scripts; do
            cp -r "$dir" "$CONTAINER_BASE_NAME/"
        done
        
        # Copy dock CLI
        cp dockerized-laravel/dock "$CONTAINER_BASE_NAME/"
        
        # Move .env file
        rm -f "$CONTAINER_BASE_NAME/.env"
        mv dockerized-laravel/.env "$CONTAINER_BASE_NAME/.env"
        
        print_success "Laravel project created"
    else
        print_step $current_step $total_steps "Installing in existing project"
        
        # Backup existing .env if present
        if [[ -f "../.env" ]]; then
            mv "../.env" "../.env.backup"
            print_info "Backed up existing .env to .env.backup"
        fi
        
        # Copy files to parent directory
        cp .env ../
        cp dock ../
        cp -r docker ../
        cp -r scripts ../
        cd ..
        
        print_success "Docker configuration installed"
    fi
    
    # Step 5: Cleanup
    ((current_step++))
    print_step $current_step $total_steps "Finalizing"
    
    rm -rf dockerized-laravel
    print_success "Cleanup complete"
    
    # Final message
    echo ""
    echo -e "${GREEN}╭──────────────────────────────────────────╮${NC}"
    echo -e "${GREEN}│${NC}  ${BOLD}${ICON_CHECK} Installation Complete!${NC}"
    echo -e "${GREEN}╰──────────────────────────────────────────╯${NC}"
    echo ""
    echo -e "  ${BOLD}Next steps:${NC}"
    echo -e "  ${DIM}1.${NC} cd ${CONTAINER_BASE_NAME:-$(pwd)}"
    echo -e "  ${DIM}2.${NC} Review and edit .env file"
    echo -e "  ${DIM}3.${NC} ./dock start"
    echo ""
    echo -e "  ${BOLD}Useful commands:${NC}"
    echo -e "  ${DIM}${ICON_ARROW}${NC} ./dock --help         Show all commands"
    echo -e "  ${DIM}${ICON_ARROW}${NC} ./dock start          Start containers"
    echo -e "  ${DIM}${ICON_ARROW}${NC} ./dock artisan <cmd>  Run artisan command"
    echo -e "  ${DIM}${ICON_ARROW}${NC} ./dock logs -f        Follow container logs"
    echo ""
}

# -----------------------------------------------------------------------------
# Argument Parsing
# -----------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--type)
                APP_TYPE="$2"
                shift 2
                ;;
            -n|--name)
                APP_NAME="$2"
                shift 2
                ;;
            -c|--container)
                CONTAINER_BASE_NAME="$2"
                shift 2
                ;;
            -r|--repo)
                REPO_URL_PROJECT="$2"
                shift 2
                ;;
            -d|--database)
                DB_NAME="$2"
                shift 2
                ;;
            --non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRM=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -V|--version)
                echo "dockerized-laravel installer v${VERSION}"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Run './configure-app.sh --help' for usage"
                exit 1
                ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    parse_args "$@"
    
    print_header
    
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        # Non-interactive mode: validate all inputs
        validate_inputs || exit 1
        DB_NAME="${DB_NAME:-$CONTAINER_BASE_NAME}"
    else
        # Interactive mode: prompt for inputs
        prompt_project_type
        prompt_inputs
    fi
    
    print_summary
    
    if ! confirm_proceed; then
        print_info "Installation cancelled"
        exit 0
    fi
    
    install_dockerized_laravel
}

main "$@"