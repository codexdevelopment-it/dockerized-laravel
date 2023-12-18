# load .env file variables
export $(grep -v '^#' .env | xargs)

# Start the docker containers
docker compose down
docker compose -f docker-compose.yml -f docker-compose-prod.yml  up -d

# Ensure framework folders exist
docker exec "${CONTAINER_NAME}" mkdir -p /var/www/storage/framework/sessions
docker exec "${CONTAINER_NAME}" mkdir -p /var/www/storage/framework/views
docker exec "${CONTAINER_NAME}" mkdir -p /var/www/storage/framework/cache

# Ensure project directory is readable
docker exec "${CONTAINER_NAME}" chmod 775 /var/www

# Ensure public folder is readable
docker exec "${CONTAINER_NAME}" chmod -R 775 public
docker exec "${CONTAINER_NAME}" bash -c "setfacl -R -m d:u::rwx,d:g::rwx,d:o::rX /var/www/public"

# Ensure storage public folder is readable and future created files will be readable
# Ensure storage public folder is readable and future created files will be readable
docker exec "${CONTAINER_NAME}" chmod +x /var/www
docker exec "${CONTAINER_NAME}" chmod +x /var/www/storage
docker exec "${CONTAINER_NAME}" mkdir -p /var/www/storage/app
docker exec "${CONTAINER_NAME}" chmod +x /var/www/storage/app
docker exec "${CONTAINER_NAME}" mkdir -p /var/www/storage/app/public
docker exec "${CONTAINER_NAME}" chmod +x /var/www/storage/app/public
docker exec "${CONTAINER_NAME}" bash -c "setfacl -Rm d:u::rwx,d:g::rwx,d:o::rX /var/www/storage/app/public/"

# Ensure working directory is owned by sail (if user sail exists)
# THIS IS BETTER TO DO BEFORE STARTING THE SCRIPT (BY HAND)
# in this way the script can be run by non-root users
#if id "sail" >/dev/null 2>&1; then
#    sudo chown -R sail .
#fi

# Install composer packages (read container name from environment variable)
docker exec  "${CONTAINER_NAME}" composer install --optimize-autoloader --no-dev

# Link storage folder
docker exec  "${CONTAINER_NAME}" php artisan storage:link

# Set default permissions for storage public folder (always read for everyone) with ACL
# Not that capital X means execute only if it is a directory or already has execute permission for some user
# The X for directories is very useful to ensure that new files and directories created there will be accessible
docker exec  "${CONTAINER_NAME}" setfacl -R -d -m u::rwX,g::rwX,o::rX /var/www/storage/app/public/

# Check that APP_KEY is set
if [ -z "$APP_KEY" ]; then
    echo "APP_KEY is not set, generating one"
    docker exec  "${CONTAINER_NAME}" php artisan key:generate
fi

# Install npm packages
echo "Installing npm packages"
docker exec "${CONTAINER_NAME}" npm install

# Compile assets
echo "Compiling assets"
docker exec  "${CONTAINER_NAME}" npm run build

## Optimize
#echo "Optimizing"
#docker exec  "${CONTAINER_NAME}" php artisan optimize

# Run the queue worker (optional)
#docker exec  "${CONTAINER_NAME}" php artisan queue:work --timeout=0