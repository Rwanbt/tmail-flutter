#!/bin/bash
set -euo pipefail

## Pre-requisites
# Install patrol CLI
echo "Installing patrol CLI..."
dart pub global activate patrol_cli 4.3.1

# The stack and its provisioned accounts belong to this disposable runner.
# Always clean it if provisioning, readiness or Patrol itself fails.
STACK_DIR="$(pwd)/backend-docker"
RESET_SERVER_PID=""
cleanup() {
    if [[ -n "$RESET_SERVER_PID" ]]; then
        kill "$RESET_SERVER_PID" 2>/dev/null || true
    fi
    ( cd "$STACK_DIR" && docker compose down ) || true
}
trap cleanup EXIT

# Stop previous environment if any
cd backend-docker
docker compose down || true

# Forward traffic to tmail-backend
export BASIC_AUTH_URL="http://localhost"
export WEBSOCKET_URL="ws://localhost"

# Generate keys for tmail backend
echo "Generating keys for tmail-backend..."
openssl genpkey -algorithm rsa -pkeyopt rsa_keygen_bits:4096 -out jwt_privatekey
openssl rsa -in jwt_privatekey -pubout -out jwt_publickey

# Replace jmap.properties URLs so James reports the correct public base URL
# in its JMAP session responses (the app uses these URLs for subsequent requests).
sed -i.bak "s|url.prefix=.*|url.prefix=$BASIC_AUTH_URL|" jmap.properties
sed -i.bak "s|websocket.url.prefix=.*|websocket.url.prefix=$WEBSOCKET_URL|" jmap.properties

echo "Starting services and adding users..."
docker compose up -d
# Never allow a broken James container to stall a mandatory E2E gate forever.
backend_ready=0
for attempt in $(seq 1 150); do
    if docker compose logs tmail-backend 2>&1 | grep -qi "JAMES server started"; then
        backend_ready=1
        break
    fi
    echo "Waiting for tmail-backend to start ($attempt/150)..."
    sleep 2
done
if [[ "$backend_ready" -ne 1 ]]; then
    echo "TMail backend did not become ready within 5 minutes" >&2
    docker compose ps || true
    docker compose logs --tail 80 tmail-backend || true
    exit 1
fi
export BOB="bob"
export ALICE="alice"
export DOMAIN="example.com"

docker exec tmail-backend ./root/conf/integration_test/provisioning.sh

cd ..

export RESET_PORT=9999

RESET_SERVER_LOG="/tmp/backend-reset-server.log"
echo "Starting backend reset server on port $RESET_PORT (logs: $RESET_SERVER_LOG)..."
RESET_PORT="$RESET_PORT" python3 scripts/backend-reset-server.py > "$RESET_SERVER_LOG" 2>&1 &
RESET_SERVER_PID=$!

echo "Copying integration_test/integration_test_env.file to env.file..."
cp integration_test/integration_test_env.file env.file

echo "Building the app and running tests..."
patrol test -v \
    --tags=web \
    --device=chrome \
    --web-port=3000 \
    --web-headless=true \
    --web-server-timeout=300 \
    --web-browser-args='["--disable-dev-shm-usage","--disable-gpu","--lang=en-US","--accept-lang=en-US,en"]' \
    --dart-define=USERNAME="$BOB" \
    --dart-define=PASSWORD="$BOB" \
    --dart-define=ADDITIONAL_MAIL_RECIPIENT="$ALICE@$DOMAIN" \
    --dart-define=BASIC_AUTH_EMAIL="$BOB@$DOMAIN" \
    --dart-define=BASIC_AUTH_URL="$BASIC_AUTH_URL" \
    --dart-define=RESET_SERVER_URL="http://localhost:$RESET_PORT"
