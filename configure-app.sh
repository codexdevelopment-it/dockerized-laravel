# Remove previous dockerized-laravel directory
rm -rf dockerized-laravel

# Ask user for app name
echo "Enter the name of the app"
read -r APP_NAME

# Ask user for container base name
echo "Enter the name of the container, all containers will be prefixed with this name (e.g. 'laravel' will result in 'laravel-app', 'laravel-db', etc)"
read -r CONTAINER_BASE_NAME

# Ask user for repo url of the project
echo "Enter the url of the repository, this will be used to deploy the project"
read -r REPO_URL


## Ask user for database name
#echo "Enter the name of the database"
#read -r DB_NAME

# Set the database name to the container base name
DB_NAME=$CONTAINER_BASE_NAME

# Clone this repo inside project root directory
git clone https://github.com/Murkrow02/dockerized-laravel
cd dockerized-laravel || exit

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