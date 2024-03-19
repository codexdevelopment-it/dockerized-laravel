# Load .env file
export $(cat .env | grep -v ^# | xargs)
export COMPOSE_PROJECT_NAME="${CONTAINER_NAME}"

# Ensure right permissions in project if windows
if [[ "$OSTYPE" == "msys" ]]; then
    echo "We need password to set permissions to write in local, just in case"
    sudo chmod -R 777 .
fi

# Load .env file into environment variables
export $(grep -v '^#' .env | xargs)

# Start container
docker compose down
docker compose -f docker-compose.yml -f docker-compose-local.yml  up -d

# Check if --fast or -f argument is passed
if [ "$1" = "--fast" ] || [ "$1" = "-f" ]; then
    echo "Skipping composer and npm install"
else
    # Install composer packages in container
    docker exec -it "${CONTAINER_NAME}" composer install

    #    # Set application key if not set
    #    echo "Setting application key"
    #    docker exec -it "${CONTAINER_NAME}" php artisan key:generate

    # Install npm packages
    echo "Installing npm packages"
    docker exec -it "${CONTAINER_NAME}" npm install

    # Compile assets and watch for changes
    echo "Compiling assets"
    docker exec -it "${CONTAINER_NAME}" npm run build #can be replaced with watch if add "scripts": { "watch": "vite build --watch" } to package.json
fi


# Start the server
echo "Starting the server"
docker exec -it "${CONTAINER_NAME}" php -d variables_order=EGPCS \
                                        /var/www/artisan serve --host=0.0.0.0 --port=80
