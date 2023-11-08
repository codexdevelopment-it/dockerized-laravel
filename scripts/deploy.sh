#!/bin/bash

# Define your repository URL and branch (change as needed)
REPO_URL=""
BRANCH="master"

# Define your deployment directory (change as needed)
DEPLOY_DIR="/var/www/laravel-dockerized/sites/XXXX"

# Create a temporary directory for the clone
TMP_DIR=$(mktemp -d)

# Clone the repository into the temporary directory
git clone -b "$BRANCH" "$REPO_URL" "$TMP_DIR"

# Perform rsync to update the deployment directory NOTE THE / AT THE END MEANS TO COPY ALL FILES FROM DIR AND NOT THE DIR
rsync -av --delete "$TMP_DIR" "$DEPLOY_DIR"

# Remove (if exists) the .env file from the deployment directory (backup it first)
if [ -f "$DEPLOY_DIR/.env" ]; then
    mv "$DEPLOY_DIR/.env" "$DEPLOY_DIR/.env.bak"
fi

# Copy production env file
cp ./prod_env "$DEPLOY_DIR/.env"

# Change to the deployment directory
cd "$DEPLOY_DIR" || exit 1

# Run start script (add error handling if needed)
./scripts/start-prod.sh

# Clean up temporary directory
rm -rf "$TMP_DIR"