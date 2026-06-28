#!/bin/bash
set -euo pipefail

# Resets the application database on the HOST postgres, then re-runs
# migrations inside the app container. DESTROYS ALL DATA in the database.
# Uploaded files on the host volume are NOT touched (remove them separately).
#
# Usage (run on the server):
#   bash reset_db_at_server.sh DB_NAME DOCKER_CONTAINER_NAME [-y]
#
# Pass -y (or set FORCE=1) to skip the confirmation prompt.

DB_NAME=${1:-}
DOCKER_CONTAINER_NAME=${2:-}
CONFIRM_FLAG=${3:-}

if [ -z "$DB_NAME" ] || [ -z "$DOCKER_CONTAINER_NAME" ]; then
    echo "Usage: $0 DB_NAME DOCKER_CONTAINER_NAME [-y]"
    exit 1
fi

if [ "${FORCE:-0}" != "1" ] && [ "$CONFIRM_FLAG" != "-y" ]; then
    echo "WARNING: this will DROP and recreate database '$DB_NAME', destroying ALL data."
    read -r -p "Type the database name ($DB_NAME) to confirm: " REPLY
    if [ "$REPLY" != "$DB_NAME" ]; then
        echo "Aborted."
        exit 1
    fi
fi

echo "Stopping container $DOCKER_CONTAINER_NAME..."
docker stop "$DOCKER_CONTAINER_NAME" >/dev/null 2>&1 || echo "Container not running; continuing."

echo "Terminating active connections to $DB_NAME..."
sudo -u postgres psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$DB_NAME' AND pid <> pg_backend_pid();" >/dev/null

echo "Dropping database $DB_NAME..."
sudo -u postgres psql -c "DROP DATABASE IF EXISTS $DB_NAME;"

echo "Creating database $DB_NAME..."
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME;"

echo "Recreating extensions..."
sudo -u postgres psql -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;"
sudo -u postgres psql -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"
sudo -u postgres psql -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS citext;"

echo "Starting container $DOCKER_CONTAINER_NAME..."
docker start "$DOCKER_CONTAINER_NAME" >/dev/null

echo "Running migrations for $DOCKER_CONTAINER_NAME..."
docker exec "$DOCKER_CONTAINER_NAME" ./bin/migrate

echo "Database reset completed."
