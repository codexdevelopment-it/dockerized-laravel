# Ask if need to create a new app or add to existing app
echo "Do you want to create a new app or add to an existing app? (new/existing)"
read -r APP_TYPE

# Remove previous dockerized-laravel directory if exists
if [ -d "dockerized-laravel" ]; then
    rm -rf dockerized-laravel
fi

# Ask user for app name
echo "Enter the name of the app"
read -r APP_NAME

# Ask user for container base name
echo "Enter the name of the container, all containers will be prefixed with this name (e.g. 'laravel' will result in 'laravel-mariadb', 'laravel-nginx', etc.)"
read -r CONTAINER_BASE_NAME

# Ask user for repo url of the project
echo "Enter the url of the repository, this will be used to deploy the project (you can skip this for now)"
read -r REPO_URL

# Ask user for database name (default to CONTAINER_BASE_NAME)
echo "Enter the name of the database (default is $CONTAINER_BASE_NAME)"
read -r DB_NAME
if [ -z "$DB_NAME" ]; then
    DB_NAME=$CONTAINER_BASE_NAME
fi

# Clone this repo inside project root directory
git clone https://github.com/Murkrow02/dockerized-laravel
cd dockerized-laravel || exit

# Create .env file
# Sed works differently on Mac and Linux
if [[ $(uname) == "Darwin" ]]; then
    sed -i '' "s/{{APP_NAME}}/$APP_NAME/g" .env
    sed -i '' "s/{{CONTAINER_NAME}}/$CONTAINER_BASE_NAME/g" .env
    sed -i '' "s/{{CONTAINER_NAME}}/$CONTAINER_BASE_NAME/g" docker/fpm.conf
    sed -i '' "s/{{CONTAINER_NAME}}/$CONTAINER_BASE_NAME/g" docker/nginx.conf
    sed -i '' "s/{{DB_NAME}}/$DB_NAME/g" .env
    sed -i '' "s|{{REPO_URL}}|$REPO_URL|g" .env
else
    sed -i "s/{{APP_NAME}}/$APP_NAME/g" .env
    sed -i "s/{{CONTAINER_NAME}}/$CONTAINER_BASE_NAME/g" .env
    sed -i "s/{{CONTAINER_NAME}}/$CONTAINER_BASE_NAME/g" docker/fpm.conf
    sed -i "s/{{CONTAINER_NAME}}/$CONTAINER_BASE_NAME/g" docker/nginx.conf
    sed -i "s/{{DB_NAME}}/$DB_NAME/g" .env
    sed -i "s|{{REPO_URL}}|$REPO_URL|g" .env
fi

# If we are creating a new app, start the docker containers and install laravel
if [ "$APP_TYPE" == "new" ]; then

    # Start the containers
    ./scripts/containers-up.sh

    # Install laravel
    docker exec "${CONTAINER_BASE_NAME}" composer global require laravel/installer
    docker exec "${CONTAINER_BASE_NAME}" "~/.composer/vendor/laravel/installer/bin/laravel new"
fi


# Copy the .env file to the root directory of the project
mv ../.env ../.env.old || true
cp .env ../.env

# Copy docker folder
cp -r docker ../docker

# Copy the scripts to the root directory of the project
cp -r scripts ../scripts

# Install packages
cd ..
#TODO

# Remove the dockerized-laravel directory
rm -rf dockerized-laravel