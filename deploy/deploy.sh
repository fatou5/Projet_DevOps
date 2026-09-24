#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

STATE_FILE="$ROOT_DIR/deploy/active_color"
NGINX_CONFIG="$ROOT_DIR/starter-app/nginx-conf/default.conf"
COMPOSE_FILE="$ROOT_DIR/starter-app/docker-compose.yml"

MAX_ATTEMPTS=12
SLEEP_SECONDS=5

if [[ ! -f "$STATE_FILE" ]]; then
    echo "ERROR: state file not found: $STATE_FILE"
    exit 1
fi

ACTIVE_COLOR="$(tr -d '[:space:]' < "$STATE_FILE")"

case "$ACTIVE_COLOR" in
    blue)
        INACTIVE_COLOR="green"
        ;;
    green)
        INACTIVE_COLOR="blue"
        ;;
    *)
        echo "ERROR: invalid active color: $ACTIVE_COLOR"
        exit 1
        ;;
esac

NEW_CONTAINER="projet-devops-app-$INACTIVE_COLOR"

echo "Active color: $ACTIVE_COLOR"
echo "Inactive color: $INACTIVE_COLOR"

echo "Starting $INACTIVE_COLOR..."

docker compose \
    -f "$COMPOSE_FILE" \
    --profile "$INACTIVE_COLOR" \
    up -d "app-$INACTIVE_COLOR"

echo "Waiting for $INACTIVE_COLOR to become ready..."

attempt=1

while (( attempt <= MAX_ATTEMPTS )); do
    if docker exec "$NEW_CONTAINER" \
        python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/health', timeout=2)" \
        >/dev/null 2>&1; then

        echo "Health check succeeded."
        break
    fi

    echo "Attempt $attempt/$MAX_ATTEMPTS failed. Retrying in ${SLEEP_SECONDS}s..."
    sleep "$SLEEP_SECONDS"
    ((attempt++))
done

if (( attempt > MAX_ATTEMPTS )); then
    echo "ERROR: $INACTIVE_COLOR did not become ready."
    echo "Stopping failed deployment..."

    docker compose \
        -f "$COMPOSE_FILE" \
        --profile "$INACTIVE_COLOR" \
        stop "app-$INACTIVE_COLOR" || true

    exit 1
fi

echo "Running application smoke test..."

STATUS="$(
    docker exec "$NEW_CONTAINER" \
        python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:5000/status', timeout=5).read().decode())"
)"

if [[ "$STATUS" != *"\"color\":\"$INACTIVE_COLOR\""* ]]; then
    echo "ERROR: application smoke test failed."
    echo "Expected color: $INACTIVE_COLOR"
    echo "Response: $STATUS"

    echo "Stopping failed deployment..."

    docker compose \
        -f "$COMPOSE_FILE" \
        --profile "$INACTIVE_COLOR" \
        stop "app-$INACTIVE_COLOR" || true

    exit 1
fi

echo "Application smoke test succeeded: $STATUS"

BACKUP_CONFIG="$(mktemp)"
cp "$NGINX_CONFIG" "$BACKUP_CONFIG"

restore_old_version() {
    echo "Restoring Nginx configuration..."

    cat "$BACKUP_CONFIG" > "$NGINX_CONFIG"

    if docker exec projet-devops-nginx nginx -t >/dev/null 2>&1; then
        docker compose \
            -f "$COMPOSE_FILE" \
            exec -T nginx nginx -s reload >/dev/null 2>&1 || true
    fi

    docker compose \
        -f "$COMPOSE_FILE" \
        --profile "$INACTIVE_COLOR" \
        stop "app-$INACTIVE_COLOR" >/dev/null 2>&1 || true
}

trap 'rm -f "$BACKUP_CONFIG"' EXIT

echo "Switching Nginx to $INACTIVE_COLOR..."

sed \
    "s|proxy_pass http://app-${ACTIVE_COLOR}:5000;|proxy_pass http://app-${INACTIVE_COLOR}:5000;|" \
    "$NGINX_CONFIG" > "${NGINX_CONFIG}.tmp"

cat "${NGINX_CONFIG}.tmp" > "$NGINX_CONFIG"
rm -f "${NGINX_CONFIG}.tmp"

echo "Testing Nginx configuration..."

if ! docker exec projet-devops-nginx nginx -t; then
    echo "ERROR: Nginx configuration test failed."
    restore_old_version
    exit 1
fi

echo "Reloading Nginx..."

if ! docker compose \
    -f "$COMPOSE_FILE" \
    exec -T nginx nginx -s reload; then

    echo "ERROR: Nginx reload failed."
    restore_old_version
    exit 1
fi

echo "Testing traffic through Nginx..."

TRAFFIC_OK=false
TRAFFIC_STATUS=""

attempt=1

while (( attempt <= MAX_ATTEMPTS )); do

    if TRAFFIC_STATUS="$(
        curl \
            --fail \
            --silent \
            --show-error \
            --max-time 10 \
            http://localhost:8080/status
    )"; then

        if [[ "$TRAFFIC_STATUS" == *"\"color\":\"$INACTIVE_COLOR\""* ]]; then
            TRAFFIC_OK=true
            break
        fi
    fi

    echo "Traffic attempt $attempt/$MAX_ATTEMPTS failed."
    echo "Expected color: $INACTIVE_COLOR"
    echo "Response: $TRAFFIC_STATUS"
    echo "Retrying in ${SLEEP_SECONDS}s..."

    sleep "$SLEEP_SECONDS"
    ((attempt++))
done

if [[ "$TRAFFIC_OK" != true ]]; then
    echo "ERROR: Nginx traffic smoke test failed."
    echo "The active color remains: $ACTIVE_COLOR"

    restore_old_version
    exit 1
fi

echo "Traffic smoke test succeeded: $TRAFFIC_STATUS"

echo "Stopping old $ACTIVE_COLOR application..."

docker compose \
    -f "$COMPOSE_FILE" \
    --profile "$ACTIVE_COLOR" \
    stop "app-$ACTIVE_COLOR"

printf '%s\n' "$INACTIVE_COLOR" > "$STATE_FILE"

echo "Deployment successful."
echo "Active color: $INACTIVE_COLOR"
