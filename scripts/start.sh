#!/bin/bash
set -e

# Load .env file variables
export $(grep -v '^#' .env | xargs)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Starting Containers...${NC}"
./scripts/containers-up.sh

# Give Supervisor 2 seconds to initialize the socket file
sleep 2

# --- OCTANE PRE-FLIGHT CHECK ---
if [ "$SERVER" == "octane" ]; then
    # 1. Check if the Octane command exists
    if ! docker exec "${CONTAINER_NAME}" php artisan list | grep -q "octane:"; then
        echo -e "${YELLOW}Octane package not found. Installing now...${NC}"
        docker exec "${CONTAINER_NAME}" composer require laravel/octane
        docker exec "${CONTAINER_NAME}" php artisan octane:install --server=frankenphp -q
    fi

    # 2. Ensure binary link
    echo -e "${BLUE}Linking FrankenPHP binary...${NC}"
    docker exec "${CONTAINER_NAME}" mkdir -p vendor/laravel/octane/bin
    docker exec "${CONTAINER_NAME}" ln -sf /usr/local/bin/frankenphp vendor/laravel/octane/bin/frankenphp-linux-x86_64

    # 3. Restart with --nowait to prevent terminal hanging
    echo -e "${BLUE}Restarting Octane service...${NC}"
    docker exec "${CONTAINER_NAME}" supervisorctl -c /etc/supervisor/conf.d/supervisord.conf restart octane > /dev/null 2>&1 || true
fi

# --- STANDARD PROVISIONING ---
echo -e "${BLUE}Setting up Directories and Permissions...${NC}"
docker exec "${CONTAINER_NAME}" mkdir -p storage/framework/sessions storage/framework/views storage/framework/cache storage/app/public
docker exec "${CONTAINER_NAME}" chmod -R 775 storage bootstrap/cache public
docker exec "${CONTAINER_NAME}" setfacl -R -d -m u::rwX,g::rwX,o::rX storage/app/public/ 2>/dev/null || true
docker exec "${CONTAINER_NAME}" setfacl -R -d -m u::rwX,g::rwX,o::rX public/ 2>/dev/null || true

if [ -z "$APP_KEY" ]; then
    docker exec "${CONTAINER_NAME}" php artisan key:generate
fi

docker exec "${CONTAINER_NAME}" php artisan storage:link --force || true

if [ "$SERVER" == "artisan" ]; then
    echo -e "${YELLOW}Starting Artisan Serve...${NC}"
    docker exec -it "${CONTAINER_NAME}" php artisan serve --host=0.0.0.0 --port=80
fi

echo -e "${GREEN}🚀 Application ready at http://localhost:${APP_PORT:-8000}${NC}"
