# Check if .env.prod exists
if [ ! -f .env.prod ]; then
    echo "skipping prod env file (.env.prod does not exist)"
else
    # Copy .env.prod to .env
    rm .env
    cp .env.prod .env
fi

# load .env file variables
export $(grep -v '^#' .env | xargs)

# Start the docker containers
docker compose down
docker compose up -d

# Ensure working directory is owned by sail (if user sail exists)
if id "sail" >/dev/null 2>&1; then
    sudo chown -R sail .
fi

# Install composer packages (read container name from environment variable)
docker exec -it ${CONTAINER_NAME} composer install

# Link storage folder
vendor/bin/sail artisan storage:link

# Install npm packages
vendor/bin/sail npm install

# Compile assets
vendor/bin/sail npm run build

# Run the queue worker (optional)
#vendor/bin/sail artisan queue:work --timeout=0
