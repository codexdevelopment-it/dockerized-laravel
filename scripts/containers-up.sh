# Load .env file variables
export $(grep -v '^#' .env | xargs)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get SERVER and SERVICES from .env
if [ -z "$SERVER" ]; then
    echo -e "${RED}SERVER is not set in .env file${NC}"
    exit 1
fi

# Convert SERVICES string to array
IFS=',' read -r -a SERVICES_ARRAY <<< "$SERVICES"

# Dump output in color and nice format
echo -e "${GREEN}Starting the application with the following configuration:${NC}"
echo -e "${BLUE}Server:${NC} $SERVER"
echo -e "${BLUE}Services:${NC} ${SERVICES_ARRAY[@]}"
echo -e "${BLUE}Environment:${NC} $APP_ENV"

# Set ENV variable to restart always if APP_ENV != local
if [ "$APP_ENV" != "local" ]; then
    export RESTART_POLICY=always
else
    export RESTART_POLICY=no
fi

# Create the command to launch the chain of compose files
COMPOSE_COMMAND="docker compose -f docker/compose/base.yml -f docker/compose/${APP_ENV}.yml"

# Add the SERVER compose file
COMPOSE_COMMAND="${COMPOSE_COMMAND} -f docker/compose/server/${SERVER}.yml"

# Add the SERVICES compose files
for service in "${SERVICES_ARRAY[@]}"; do
    COMPOSE_COMMAND="${COMPOSE_COMMAND} -f docker/compose/services/${service}.yml"
done

# Create final command
DOWN_COMMAND="${COMPOSE_COMMAND} -p ${CONTAINER_NAME} down"
UP_COMMAND="${COMPOSE_COMMAND} -p ${CONTAINER_NAME} up -d --remove-orphans"

# Run the command
echo -e "${GREEN}Final compose command:${NC}"
echo -e "${BLUE}${COMPOSE_COMMAND}${NC}"
eval "${DOWN_COMMAND}"
eval "${UP_COMMAND}"
