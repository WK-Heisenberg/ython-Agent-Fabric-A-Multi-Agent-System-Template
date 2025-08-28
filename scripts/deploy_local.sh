#!/bin/bash

# Script to build Docker containers locally and run tests against the running services.
# Prompts the user to enable debug mode (disables 'set -e' and automatic cleanup).

# Exit immediately if a command exits with a non-zero status.
# Controlled by the DEBUG_MODE flag below.
# set -e # Will be set conditionally

DEBUG_MODE=false # Default: run in strict mode with cleanup

# --- Configuration ---
# Adjust these variables based on your project setup

# The name of your docker-compose file
# <<< Verify this is the correct file name >>>
COMPOSE_FILE="docker-compose.yml"

# The script containing the test commands to run against the services
# <<< Verify this is the correct file name >>>
# Path is relative to the project root where this script is expected to be run from
TEST_SCRIPT="scripts/test_prompts.sh"

# --- Script Logic ---

# Function to ensure containers are stopped and removed on exit
cleanup() {
    echo "--- Cleaning up ---"
    # Use --volumes to remove volumes defined in the compose file
    # Use --rmi 'local' to remove images built by compose (use with caution)
    docker-compose -f "$COMPOSE_FILE" down --volumes || echo "docker-compose down failed, continuing cleanup..."
}
# Register the cleanup function to run on script exit (normal or error) or interrupt
# Controlled by the DEBUG_MODE flag below.
# trap cleanup EXIT SIGINT SIGTERM # Will be set conditionally

# --- Interactive Debug Mode Prompt ---
read -p "Run in DEBUG mode? (Disables exit-on-error and auto-cleanup) [y/N]: " debug_choice
# Convert to lowercase
debug_choice_lower=$(echo "$debug_choice" | tr '[:upper:]' '[:lower:]')

if [[ "$debug_choice_lower" == "y" || "$debug_choice_lower" == "yes" ]]; then
    echo "--- Running in DEBUG mode: 'set -e' and automatic cleanup are disabled. ---"
    DEBUG_MODE=true
else
    echo "--- Running in standard mode: 'set -e' and automatic cleanup are enabled. ---"
    DEBUG_MODE=false
fi

# --- Apply Strict Mode & Cleanup based on DEBUG_MODE ---
if [ "$DEBUG_MODE" = false ]; then
    set -e
    trap cleanup EXIT SIGINT SIGTERM
fi

echo "--- Starting Local Build and Test ---"

# 1a. Check for docker-compose file
if [ ! -f "$COMPOSE_FILE" ]; then
    echo "Error: $COMPOSE_FILE not found in the current directory."
    echo "Please ensure the COMPOSE_FILE variable is set correctly."
    exit 1
fi

# 1b. Check for test script file
if [ ! -f "$TEST_SCRIPT" ]; then
    echo "Error: Test script '$TEST_SCRIPT' not found. Ensure it exists at this path relative to the project root."
    exit 1
fi

# 2. Build the Docker images using docker-compose
#    Using --no-cache can be useful sometimes for a clean build, but slower.
echo "Building Docker images using $COMPOSE_FILE..."
# Build all services defined in the compose file
docker-compose -f "$COMPOSE_FILE" build

# 3. Start all services (including dependencies) in detached mode
echo "Starting services in detached mode..."
# Ensure dependent services (like databases) are ready before running tests if needed.
# The 'depends_on: condition: service_healthy' in docker-compose.yml handles waiting.
docker-compose -f "$COMPOSE_FILE" up -d
UP_EXIT_CODE=$? # Capture the exit code of docker-compose up

# 4. Run tests from the test script against the running services
echo "Running tests from '$TEST_SCRIPT' against the services..."
# Execute the test script using bash.
# Ensure curl and jq are installed on the host machine where this script runs.
# The 'depends_on: condition: service_healthy' in docker-compose.yml handles waiting.
# We now check the exit code of 'docker-compose up -d'.

# Check if 'docker-compose up -d' succeeded.
# If it failed, services likely didn't become healthy in time according to docker-compose.
if [ $UP_EXIT_CODE -ne 0 ]; then
    echo "Error: 'docker-compose up -d' failed with exit code $UP_EXIT_CODE."
    echo "Services may not have started correctly or become healthy within the expected time."
    echo "Skipping tests. Check container logs for details: docker-compose -f \"$COMPOSE_FILE\" logs"
    # In standard mode (set -e), the script would have already exited here.
    # In debug mode, we explicitly skip the tests.
    if [ "$DEBUG_MODE" = false ]; then
         # This part might be redundant due to 'set -e', but ensures exit if 'set -e' somehow failed.
         exit 1
    fi
else
    # Only run tests if docker-compose up succeeded
    bash "$TEST_SCRIPT"
fi

if [ "$DEBUG_MODE" = false ]; then
    echo "--- Local Build and Test Completed Successfully (Cleanup will run automatically) ---"
else
    echo "--- Local Build and Test Finished (DEBUG mode: Manual cleanup might be needed) ---"
    echo "Run 'docker-compose -f $COMPOSE_FILE down --volumes' to stop and remove containers/volumes."
fi
