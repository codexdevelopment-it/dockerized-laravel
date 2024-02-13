# Ask user for app name
echo "Enter the name of the app"
read -r APP_NAME

# Ask user for container base name
echo "Enter the name of the container, all containers will be prefixed with this name (e.g. 'laravel' will result in 'laravel-app', 'laravel-db', etc)"
read -r CONTAINER_BASE_NAME

# Ask user for database name
echo "Enter the name of the database"
read -r DB_NAME

# Clone this repo inside project root directory
git clone https://github.com/Murkrow02/dockerized-laravel
cd dockerized-laravel || exit
#cp -r /Users/murkrow/Desktop/Repos/dockerized-laravel ./

# Replace .env values with user input
# Check if the operating system is macOS
if [[ $(uname) == "Darwin" ]]; then
    sed -i '' "s/{{APP_NAME}}/$APP_NAME/g" .env
    sed -i '' "s/{{CONTAINER_NAME}}/$CONTAINER_BASE_NAME/g" .env
    sed -i '' "s/{{DB_NAME}}/$DB_NAME/g" .env
else
    sed -i "s/{{APP_NAME}}/$APP_NAME/g" .env
    sed -i "s/{{CONTAINER_NAME}}/$CONTAINER_BASE_NAME/g" .env
    sed -i "s/{{DB_NAME}}/$DB_NAME/g" .env
fi


# Copy the .env file to the root directory of the project
mv .env ../.env.old || true
cp .env ../.env

# Copy the docker-compose files to the root directory of the project
cp docker-compose.yml ../docker-compose.yml
cp docker-compose-local.yml ../docker-compose-local.yml
cp docker-compose-prod.yml ../docker-compose-prod.yml

# Copy the scripts to the root directory of the project excluding the configure-app.sh file
cp -r scripts ../scripts && rm -f ../scripts/configure-app.sh