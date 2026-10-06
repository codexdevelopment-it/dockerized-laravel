#!/usr/bin/env bash
# =============================================================================
# Dockerized Laravel - installer
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/Murkrow02/dockerized-laravel/main/configure-app.sh)
#
# existing: run from the Laravel project root; adds dock, scripts/, docker/
#           and merges the dock settings into the existing .env.
# new:      creates ./<container-name>/ with a fresh Laravel app (composer
#           create-project inside the dock image, nothing needed on the host).
# =============================================================================

set -eu

VERSION="3.0.0"
REPO_URL="${DOCKERIZED_LARAVEL_REPO:-https://github.com/Murkrow02/dockerized-laravel}"
REPO_BRANCH="${DOCKERIZED_LARAVEL_BRANCH:-main}"

if [[ -t 1 && "${TERM:-}" != "dumb" && -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m'
    CYAN='\033[0;36m' BOLD='\033[1m' DIM='\033[2m' NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' DIM='' NC=''
fi

APP_TYPE=""
APP_NAME=""
CONTAINER_BASE_NAME=""
DB_NAME=""
DB_DRIVER="mariadb"
SERVER="artisan"
NON_INTERACTIVE=false
SKIP_CONFIRM=false
TMP_DIR=""

# -----------------------------------------------------------------------------
# Output
# -----------------------------------------------------------------------------
print_success() { echo -e "${GREEN}✓${NC} $*"; }
print_error()   { echo -e "${RED}✗${NC} $*" >&2; }
print_info()    { echo -e "${BLUE}→${NC} $*"; }
print_warning() { echo -e "${YELLOW}!${NC} $*"; }
print_step()    { echo ""; echo -e "${BOLD}[$1/$2]${NC} $3"; echo -e "${DIM}────────────────────────────────────────${NC}"; }

print_header() {
    echo ""
    echo -e "${CYAN}╭──────────────────────────────────────────╮${NC}"
    echo -e "${CYAN}│${NC}  ${BOLD}🐳 Dockerized Laravel Installer${NC} ${DIM}v${VERSION}${NC}"
    echo -e "${CYAN}╰──────────────────────────────────────────╯${NC}"
}

show_help() {
    cat <<EOF
Dockerized Laravel installer v${VERSION}

USAGE
    bash <(curl -fsSL ${REPO_URL}/raw/${REPO_BRANCH}/configure-app.sh) [options]

OPTIONS
    -t, --type <new|existing>   New Laravel app, or add Docker to the current project
    -n, --name <name>           Application name
    -c, --container <name>      Container prefix, lowercase (myapp -> myapp, myapp-db, ...)
    -d, --database <name>       Database name (default: container name, '-' -> '_')
    --db-driver <driver>        mariadb (default) | postgres | pgvector
    --server <server>           artisan (default) | octane | nginx | caddy | fpm
    --non-interactive           No prompts (needs -t, -n, -c)
    -y, --yes                   Don't ask for confirmation
    -h, --help | -V, --version

ENVIRONMENT
    DOCKERIZED_LARAVEL_REPO, DOCKERIZED_LARAVEL_BRANCH   Install from a fork/branch

EXAMPLES
    ./configure-app.sh
    ./configure-app.sh -t new -n "My App" -c myapp --non-interactive
    ./configure-app.sh -t existing -n "My App" -c myapp --db-driver postgres -y
EOF
}

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
safe_sed() { if sed --version &>/dev/null; then sed -i "$@"; else sed -i '' "$@"; fi; }
sed_escape() { printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'; }

# set_env_value <file> <KEY> <value>: replace an uncommented KEY= or append.
set_env_value() {
    if grep -qE "^$2=" "$1"; then
        safe_sed "s|^$2=.*|$2=$(sed_escape "$3")|" "$1"
    else
        printf '%s=%s\n' "$2" "$3" >> "$1"
    fi
}

get_env_value() {
    local v
    v="$(grep -E "^$2=" "$1" 2>/dev/null | tail -n1 | cut -d= -f2-)" || true
    v="${v#\"}"; v="${v%\"}"
    printf '%s' "$v"
}

random_password() { head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24; }

slugify() { echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' _' '--' | tr -cd 'a-z0-9-' | sed 's/^-*//; s/-*$//'; }

# append_missing_lines <source> <target>: add lines of source missing from target.
append_missing_lines() {
    local line added=false
    touch "$2"
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        if ! grep -qxF "$line" "$2"; then
            if [[ "$added" == false ]]; then
                [[ -s "$2" && -n "$(tail -c1 "$2")" ]] && echo "" >> "$2"
                printf '\n# dockerized-laravel\n' >> "$2"
                added=true
            fi
            echo "$line" >> "$2"
        fi
    done < "$1"
}

cleanup() { [[ -n "$TMP_DIR" ]] && rm -rf "$TMP_DIR"; return 0; }
trap cleanup EXIT

# -----------------------------------------------------------------------------
# Validation and prompts
# -----------------------------------------------------------------------------
validate_container_name() {
    if [[ ! "$1" =~ ^[a-z0-9][a-z0-9_.-]+$ ]]; then
        print_error "Container name: 2+ chars, lowercase letters, digits, '-', '_', '.'"
        return 1
    fi
}

validate_inputs() {
    local ok=true
    case "$APP_TYPE" in
        new|existing) ;;
        *) print_error "Project type must be 'new' or 'existing' (-t)"; ok=false ;;
    esac
    [[ -n "$APP_NAME" ]] || { print_error "Application name is required (-n)"; ok=false; }
    validate_container_name "$CONTAINER_BASE_NAME" || ok=false
    case "$DB_DRIVER" in mariadb|postgres|pgvector) ;; *) print_error "Invalid --db-driver: $DB_DRIVER"; ok=false ;; esac
    case "$SERVER" in artisan|octane|nginx|caddy|fpm) ;; *) print_error "Invalid --server: $SERVER"; ok=false ;; esac
    [[ "$ok" == true ]]
}

# choose <var> <prompt> <default-index> <options...>
choose() {
    local var="$1" prompt="$2" def="$3" i=1 choice opt
    shift 3
    echo ""
    echo -e "${BLUE}${prompt}${NC}"
    for opt in "$@"; do echo "  $i) $opt"; i=$((i + 1)); done
    while true; do
        read -r -p "Choice [${def}]: " choice
        choice="${choice:-$def}"
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= $# )); then
            eval "$var=\"\${$choice%% *}\""
            return
        fi
        print_error "Enter a number between 1 and $#"
    done
}

prompt_inputs() {
    local suggested answer
    if [[ -z "$APP_TYPE" ]]; then
        choose APP_TYPE "Project type?" 2 "new       (create a new Laravel app)" "existing  (add Docker to this project)"
    fi
    echo ""
    while [[ -z "$APP_NAME" ]]; do
        read -r -p "$(echo -e "${BLUE}Application name:${NC} ")" APP_NAME
    done
    suggested="$(slugify "$APP_NAME")"
    while true; do
        read -r -p "$(echo -e "${BLUE}Container name${NC} [${suggested}]: ")" answer
        CONTAINER_BASE_NAME="${answer:-$suggested}"
        validate_container_name "$CONTAINER_BASE_NAME" && break
    done
    suggested="$(echo "$CONTAINER_BASE_NAME" | tr '.-' '__')"
    read -r -p "$(echo -e "${BLUE}Database name${NC} [${suggested}]: ")" answer
    DB_NAME="${answer:-$suggested}"
    choose DB_DRIVER "Database?" 1 "mariadb   (MariaDB 11.4 LTS)" "postgres  (PostgreSQL 16)" "pgvector  (PostgreSQL + pgvector)"
    choose SERVER "Server?" 1 "artisan   (php artisan serve, simplest for dev)" "octane    (FrankenPHP, needs laravel/octane)" "nginx     (nginx + php-fpm)" "caddy     (caddy + php-fpm, automatic HTTPS)" "fpm       (php-fpm only)"
}

print_summary() {
    echo ""
    echo -e "${BOLD}Summary${NC}"
    printf "  %-16s %s\n" "Type" "$APP_TYPE" "App name" "$APP_NAME" "Container" "$CONTAINER_BASE_NAME" \
        "Database" "$DB_NAME ($DB_DRIVER)" "Server" "$SERVER" "Directory" "$TARGET_DIR"
    echo ""
}

confirm_proceed() {
    [[ "$SKIP_CONFIRM" == true ]] && return 0
    local response
    read -r -p "$(echo -e "${YELLOW}Proceed?${NC} [Y/n]: ")" response
    case "$response" in n|N|no|NO) return 1 ;; *) return 0 ;; esac
}

# -----------------------------------------------------------------------------
# Installation steps
# -----------------------------------------------------------------------------
download_toolkit() {
    TMP_DIR="$(mktemp -d)"
    if [[ -f "$(dirname "$0")/dock" && -d "$(dirname "$0")/docker/compose" ]]; then
        # Running from a checkout of this repo: use it as-is.
        cp -R "$(cd "$(dirname "$0")" && pwd)/." "${TMP_DIR}/"
        rm -rf "${TMP_DIR}/.git"
        print_success "Using local toolkit $(cd "$(dirname "$0")" && pwd)"
        return
    fi
    git clone --quiet --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$TMP_DIR" \
        || { print_error "Failed to clone ${REPO_URL}"; exit 1; }
    rm -rf "${TMP_DIR}/.git"
    print_success "Downloaded ${REPO_URL}@${REPO_BRANCH}"
}

create_laravel_app() {
    local image="dockerized-laravel-installer:local"
    command -v docker >/dev/null || { print_error "Docker is required"; exit 1; }
    print_info "Building the PHP image (first time takes a few minutes)..."
    docker build --quiet --target local -t "$image" \
        --build-arg USER_ID=1000 --build-arg GROUP_ID=1000 \
        -f "${TMP_DIR}/docker/Dockerfile" "${TMP_DIR}" >/dev/null
    print_info "composer create-project laravel/laravel ${CONTAINER_BASE_NAME}..."
    docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e COMPOSER_HOME=/tmp/composer \
        -v "$(pwd):/work" -w /work "$image" \
        composer create-project --prefer-dist --no-interaction laravel/laravel "$CONTAINER_BASE_NAME"
    docker image rm "$image" >/dev/null 2>&1 || true
    print_success "Laravel app created in ./${CONTAINER_BASE_NAME}"
}

copy_toolkit() {
    cp "${TMP_DIR}/dock" "${TARGET_DIR}/dock"
    chmod +x "${TARGET_DIR}/dock"
    mkdir -p "${TARGET_DIR}/scripts" "${TARGET_DIR}/docker"
    cp -R "${TMP_DIR}/scripts/lib" "${TARGET_DIR}/scripts/"
    cp -R "${TMP_DIR}/docker/." "${TARGET_DIR}/docker/"
    append_missing_lines "${TMP_DIR}/.dockerignore" "${TARGET_DIR}/.dockerignore"
    printf '/db-data\n/backups\n' > "${TMP_DIR}/gitignore.add"
    append_missing_lines "${TMP_DIR}/gitignore.add" "${TARGET_DIR}/.gitignore"
    print_success "Copied dock, scripts/, docker/ and updated .dockerignore / .gitignore"
}

configure_env() {
    local env="${TARGET_DIR}/.env" key line db_password
    if [[ -f "$env" ]]; then
        cp "$env" "${env}.backup-$(date +%Y%m%d%H%M%S)"
        print_info "Existing .env kept (backup: $(basename "$(ls -t "${env}".backup-* | head -n1)"))"
        # Add the dock section for keys the project doesn't have yet.
        while IFS= read -r line; do
            [[ "$line" =~ ^([A-Z_]+)= ]] || continue
            key="${BASH_REMATCH[1]}"
            case "$key" in
                CONTAINER_NAME|SERVER|SERVICES|APP_PORT|BRANCH|DOMAIN|STORAGE_MOUNT_PATH|DB_MOUNT_PATH|DB_DRIVER)
                    grep -qE "^${key}=" "$env" || printf '%s\n' "$line" >> "$env.dock" ;;
            esac
        done < "${TMP_DIR}/.env"
        if [[ -s "$env.dock" ]]; then
            printf '\n# Docker (./dock)\n' >> "$env"
            cat "$env.dock" >> "$env"
        fi
        rm -f "$env.dock"
    else
        cp "${TMP_DIR}/.env" "$env"
    fi

    db_password="$(get_env_value "$env" DB_PASSWORD)"
    if [[ -z "$db_password" || "$db_password" == "{{DB_PASSWORD}}" || "$db_password" == "password" ]]; then
        db_password="$(random_password)"
    fi

    safe_sed -e "s|{{APP_NAME}}|$(sed_escape "$APP_NAME")|g" \
             -e "s|{{CONTAINER_NAME}}|$(sed_escape "$CONTAINER_BASE_NAME")|g" \
             -e "s|{{DB_NAME}}|$(sed_escape "$DB_NAME")|g" "$env"
    [[ "$APP_TYPE" == "new" ]] && set_env_value "$env" APP_NAME "\"${APP_NAME}\""
    set_env_value "$env" CONTAINER_NAME "$CONTAINER_BASE_NAME"
    set_env_value "$env" SERVER "$SERVER"
    set_env_value "$env" DB_DRIVER "$DB_DRIVER"
    if [[ "$DB_DRIVER" == "mariadb" ]]; then
        set_env_value "$env" DB_CONNECTION mysql
        set_env_value "$env" DB_HOST mariadb
        set_env_value "$env" DB_PORT 3306
    else
        set_env_value "$env" DB_CONNECTION pgsql
        set_env_value "$env" DB_HOST postgres
        set_env_value "$env" DB_PORT 5432
    fi
    set_env_value "$env" DB_DATABASE "$DB_NAME"
    [[ -n "$(get_env_value "$env" DB_USERNAME)" && "$(get_env_value "$env" DB_USERNAME)" != "root" ]] \
        || set_env_value "$env" DB_USERNAME app
    set_env_value "$env" DB_PASSWORD "\"${db_password}\""
    chmod 600 "$env"
    print_success "Configured .env (DB_HOST, DB_* and dock settings; random DB_PASSWORD)"
}

# Point AI coding agents at docker/AGENTS.md. The note is prepended: Laravel's
# own AGENTS.md tells agents to install PHP on the host, which we override.
configure_ai_docs() {
    local f found=false note
    note="$(cat <<'EOF'
<!-- dockerized-laravel -->
> **Docker project.** PHP, Composer, Node and the database run in containers via `./dock`.
> Never install or run `php`, `composer`, `npm` or `artisan` on the host: prefix them with `./dock`
> (e.g. `./dock composer require laravel/boost --dev`, `./dock artisan boost:install`).
> Full guide: @docker/AGENTS.md
EOF
)"
    for f in AGENTS.md CLAUDE.md; do
        [[ -f "${TARGET_DIR}/$f" ]] || continue
        found=true
        grep -qF "dockerized-laravel -->" "${TARGET_DIR}/$f" && continue
        { printf '%s\n\n' "$note"; cat "${TARGET_DIR}/$f"; } > "${TARGET_DIR}/$f.tmp"
        mv "${TARGET_DIR}/$f.tmp" "${TARGET_DIR}/$f"
    done
    if [[ "$found" == false ]]; then
        printf '%s\n' "$note" > "${TARGET_DIR}/AGENTS.md"
        printf '@AGENTS.md\n' > "${TARGET_DIR}/CLAUDE.md"
    fi
    print_success "AI agent guide: docker/AGENTS.md (linked from AGENTS.md / CLAUDE.md)"
}

install() {
    local total=4 step=1
    print_step $step $total "Downloading dockerized-laravel"; step=$((step + 1))
    download_toolkit

    if [[ "$APP_TYPE" == "new" ]]; then
        print_step $step $total "Creating Laravel app"; step=$((step + 1))
        create_laravel_app
    else
        print_step $step $total "Checking project"; step=$((step + 1))
        [[ -f "${TARGET_DIR}/artisan" ]] || print_warning "No artisan file here: is this a Laravel project root?"
        [[ ! -d "${TARGET_DIR}/docker" ]] || print_warning "docker/ exists: matching files will be overwritten (tip: ./dock update next time)"
    fi

    print_step $step $total "Installing Docker setup"; step=$((step + 1))
    copy_toolkit
    configure_env
    configure_ai_docs

    print_step $step $total "Done"
    echo ""
    echo -e "  ${BOLD}Next steps${NC}"
    [[ "$APP_TYPE" == "new" ]] && echo -e "  ${DIM}\$${NC} cd ${CONTAINER_BASE_NAME}"
    echo -e "  ${DIM}\$${NC} ./dock start          ${DIM}# build + start + provision${NC}"
    echo -e "  ${DIM}\$${NC} ./dock help           ${DIM}# all commands${NC}"
    [[ "$SERVER" == "octane" ]] && echo -e "  ${DIM}laravel/octane is installed automatically on first start${NC}"
    echo ""
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--type)        APP_TYPE="${2:-}"; shift 2 ;;
            -n|--name)        APP_NAME="${2:-}"; shift 2 ;;
            -c|--container)   CONTAINER_BASE_NAME="${2:-}"; shift 2 ;;
            -d|--database)    DB_NAME="${2:-}"; shift 2 ;;
            --db-driver)      DB_DRIVER="${2:-}"; shift 2 ;;
            --server)         SERVER="${2:-}"; shift 2 ;;
            -r|--repo)        print_warning "--repo is no longer used (deploys run from the app's own clone)"; shift 2 ;;
            --non-interactive) NON_INTERACTIVE=true; shift ;;
            -y|--yes)         SKIP_CONFIRM=true; shift ;;
            -h|--help)        show_help; exit 0 ;;
            -V|--version)     echo "dockerized-laravel installer v${VERSION}"; exit 0 ;;
            *) print_error "Unknown option: $1 (see --help)"; exit 1 ;;
        esac
    done
}

main() {
    parse_args "$@"
    print_header
    if [[ "$NON_INTERACTIVE" == false ]]; then
        prompt_inputs
    fi
    [[ -n "$DB_NAME" ]] || DB_NAME="$(echo "$CONTAINER_BASE_NAME" | tr '.-' '__')"
    validate_inputs || exit 1

    if [[ "$APP_TYPE" == "new" ]]; then
        TARGET_DIR="$(pwd)/${CONTAINER_BASE_NAME}"
        if [[ -e "$TARGET_DIR" ]]; then
            print_error "${TARGET_DIR} already exists"
            exit 1
        fi
    else
        TARGET_DIR="$(pwd)"
    fi

    print_summary
    confirm_proceed || { print_info "Cancelled"; exit 0; }
    install
}

main "$@"
