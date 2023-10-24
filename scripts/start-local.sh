# Check that vendor directory exists
if [ ! -d "vendor" ]; then

    # Vendor does not exist, run composer install
    echo "Vendor directory does not exist, running composer install"
    composer install
fi

# Run app
vendor/bin/sail -f docker-compose.yml -f docker-compose-local.yml up -d

# Install npm packages
echo "Installing npm packages"
vendor/bin/sail npm install

# Compile assets
echo "Compiling assets"
vendor/bin/sail npm run build

