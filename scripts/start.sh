#!/bin/bash

# Load .env file variables
export $(grep -v '^#' .env | xargs)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Start containers
./scripts/containers-up.sh

# Ensure framework folders exist
docker exec "${CONTAINER_NAME}" mkdir -p storage/framework/sessions
docker exec "${CONTAINER_NAME}" mkdir -p storage/framework/views
docker exec "${CONTAINER_NAME}" mkdir -p storage/framework/cache

# Ensure project directory is readable
docker exec "${CONTAINER_NAME}" chmod 775 .

# Ensure public folder is readable
docker exec "${CONTAINER_NAME}" chmod -R 775 public
docker exec "${CONTAINER_NAME}" bash -c "setfacl -R -m d:u::rwx,d:g::rwx,d:o::rX public"

# Ensure storage public folder is readable and future created files will be readable
docker exec "${CONTAINER_NAME}" chmod +x .
docker exec "${CONTAINER_NAME}" chmod +x storage
docker exec "${CONTAINER_NAME}" mkdir -p storage/app
docker exec "${CONTAINER_NAME}" chmod +x storage/app
docker exec "${CONTAINER_NAME}" mkdir -p storage/app/public
docker exec "${CONTAINER_NAME}" chmod +x storage/app/public

# Set default permissions for storage public folder (always read for everyone) with ACL
# Not that capital X means execute only if it is a directory or already has execute permission for some user
# The X for directories is very useful to ensure that new files and directories created there will be accessible
docker exec "${CONTAINER_NAME}" setfacl -R -d -m u::rwX,g::rwX,o::rX storage/app/public/

# Install composer packages (read container name from environment variable)
COMPOSER_COMMAND="docker exec ${CONTAINER_NAME} composer install"
if [ "$APP_ENV" == "production" ]; then
    COMPOSER_COMMAND="${COMPOSER_COMMAND} --optimize-autoloader --no-dev"
fi
echo "Installing composer packages"
eval "${COMPOSER_COMMAND}"

# Check that APP_KEY is set
if [ -z "$APP_KEY" ]; then
    echo "APP_KEY is not set, generating one"
    docker exec  "${CONTAINER_NAME}" php artisan key:generate
fi

# Link storage folder
docker exec "${CONTAINER_NAME}" php artisan storage:link

# Install npm packages
echo "Installing npm packages"
docker exec "${CONTAINER_NAME}" npm install

# Compile assets
echo "Compiling assets"
docker exec  "${CONTAINER_NAME}" npm run build

# Optimize
if [ "$APP_ENV" == "production" ]; then
    echo "Optimizing for production"
    docker exec "${CONTAINER_NAME}" php artisan config:cache
    docker exec "${CONTAINER_NAME}" php artisan route:cache
    docker exec "${CONTAINER_NAME}" php artisan view:cache
    docker exec "${CONTAINER_NAME}" php artisan icons:cache
    docker exec "${CONTAINER_NAME}" php artisan optimize
    docker exec "${CONTAINER_NAME}" php artisan filament:optimize
fi

# Run the queue worker (optional)
#docker exec  "${CONTAINER_NAME}" php artisan queue:work --timeout=0

# Start the SERVER
if [ "$SERVER" == "octane" ]; then
    echo "Starting octane server"
    docker exec -d "${CONTAINER_NAME}" composer require laravel/octane
    docker exec -d "${CONTAINER_NAME}" php artisan octane:install --server=frankenphp -q
    docker exec -d "${CONTAINER_NAME}" php -d variables_order=EGPCS \
                                               artisan octane:start \
                                               --server=frankenphp \
                                               --host=0.0.0.0 \
                                               --admin-port=2019 \
                                               --port=80
fi

if [ "$SERVER" == "artisan" ]; then
docker exec -it "${CONTAINER_NAME}" php -d variables_order=EGPCS \
                                        artisan serve --host=0.0.0.0 --port=80
fi
