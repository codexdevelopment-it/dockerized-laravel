#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status.

# Create configuration for a new or existing Laravel app
read -r -p "Do you want to create a new app or add to an existing app? (new/existing) " APP_TYPE
read -r -p "Enter the name of the app: " APP_NAME
read -r -p "Enter the container base name (e.g., 'laravel' -> 'laravel-mariadb', 'laravel-nginx', etc.): " CONTAINER_BASE_NAME
read -r -p "Enter the repository URL (optional): " REPO_URL
read -r -p "Enter the database name (default: $CONTAINER_BASE_NAME): " DB_NAME
DB_NAME=${DB_NAME:-$CONTAINER_BASE_NAME}  # Use default if empty

# Cleanup previous setup if exists
[ -d "dockerized-laravel" ] && rm -rf dockerized-laravel

git clone https://github.com/Murkrow02/dockerized-laravel
cd dockerized-laravel || exit 1

chmod +x scripts/*

# Update .env and configuration files
update_config() {
    local file=$1
    local mac_sed_flag=""
    [[ $(uname) == "Darwin" ]] && mac_sed_flag="''"

    sed -i $mac_sed_flag "s/{{APP_NAME}}/$APP_NAME/g" "$file"
    sed -i $mac_sed_flag "s/{{CONTAINER_NAME}}/$CONTAINER_BASE_NAME/g" "$file"
    sed -i $mac_sed_flag "s/{{DB_NAME}}/$DB_NAME/g" "$file"
    sed -i $mac_sed_flag "s|{{REPO_URL}}|$REPO_URL|g" "$file"
}

# Update configuration files by replacing placeholders
for file in .env docker/fpm.conf docker/nginx.conf; do
    [ -f "$file" ] && update_config "$file"
done

if [ "$APP_TYPE" == "new" ]; then
    ./scripts/containers-up.sh
    docker exec "$CONTAINER_BASE_NAME" composer global require laravel/installer
    docker exec -it "$CONTAINER_BASE_NAME" sh -c "~/.composer/vendor/bin/laravel new $CONTAINER_BASE_NAME"

    # Move new project outside dockerized laravel folder
    mv "$CONTAINER_BASE_NAME" ..
    cd ..

    # Copy docker and scripts folders to the new project
    for dir in docker scripts; do
        cp -r "$dir" "$CONTAINER_BASE_NAME"
    done

    # Move .env file to the new project
    mv .env "$CONTAINER_BASE_NAME/.env"
else
    mv ../.env ../.env.old || true
    cp .env ../.env
    cp -r docker ../docker
    cp -r scripts ../scripts
    cd ..
fi

rm -rf dockerized-laravel

echo "Configuration completed successfully!"
echo "Run './scripts/start.sh' to start the app."