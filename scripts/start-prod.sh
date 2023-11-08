# load .env file variables
export $(grep -v '^#' .env | xargs)

# Start the docker containers
docker compose down
docker compose up -d

# Ensure working directory is owned by sail (if user sail exists)
# THIS IS BETTER TO DO BEFORE STARTING THE SCRIPT (BY HAND)
# in this way the script can be run by non-root users
#if id "sail" >/dev/null 2>&1; then
#    sudo chown -R sail .
#fi

# Install composer packages (read container name from environment variable)
docker exec -it "${CONTAINER_NAME}" composer install

# Link storage folder
vendor/bin/sail artisan storage:link

# Check that APP_KEY is set
if [ -z "$APP_KEY" ]; then
    echo "APP_KEY is not set, generating one"
    docker exec -it "${CONTAINER_NAME}" php artisan key:generate
fi

# Install npm packages
echo "Installing npm packages"
docker exec -it "${CONTAINER_NAME}" npm install

# Compile assets
echo "Compiling assets"
docker exec -it "${CONTAINER_NAME}" npm run build


# Run the queue worker (optional)
#vendor/bin/sail artisan queue:work --timeout=0
