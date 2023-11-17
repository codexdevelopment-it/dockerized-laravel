# Load .env file into environment variables
export $(grep -v '^#' .env | xargs)

# Start container
docker compose -f docker-compose.yml -f docker-compose-local.yml  up -d

# Install composer packages in container
docker exec -it "${CONTAINER_NAME}" composer install

# Install npm packages
echo "Installing npm packages"
docker exec -it "${CONTAINER_NAME}" npm install

# Compile assets and watch for changes
echo "Compiling assets"
docker exec -it "${CONTAINER_NAME}" npm run build #can be replaced with watch if add "scripts": { "watch": "vite build --watch" } to package.json