#!/bin/bash
#
# CI integration test script for the Android app.
#
# The Patrol tests run on the Android emulator the workflow boots: the app
# reaches the backend of the runner through 10.0.2.2, the QEMU alias of the
# host. No remote tunnel and no cloud test lab are involved, so the job is
# re-runnable and its result does not depend on a third party service.
#
# The former cloud test lab flow (a public tunnel to the backend, then the
# tests on a remote device) is kept in scripts/patrol-integration-test-with-docker.sh
# for the Jenkins pipeline, which owns the Google Cloud credentials.
#
# Usage:
#   ./scripts/patrol-mobile-integration-test-with-docker.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STACK_DIR="$REPO_DIR/backend-docker"
# The host, as the Android emulator sees it.
EMULATOR_HOST="10.0.2.2"
RESET_PORT=9999

echo "Installing patrol CLI..."
dart pub global activate patrol_cli 4.3.1
export PATH="$PATH:$HOME/.pub-cache/bin"

# The stack and its provisioned accounts belong to this disposable runner:
# always clean it up, even when the provisioning, the readiness check or the
# tests themselves fail.
RESET_SERVER_PID=""
cleanup() {
    if [[ -n "$RESET_SERVER_PID" ]]; then
        kill "$RESET_SERVER_PID" 2>/dev/null || true
    fi
    ( cd "$STACK_DIR" && docker compose down --remove-orphans ) || true
}
trap cleanup EXIT

cd "$STACK_DIR"
# Stop a previous environment, if any.
docker compose down --remove-orphans || true

echo "Generating keys for tmail-backend..."
openssl genpkey -algorithm rsa -pkeyopt rsa_keygen_bits:4096 -out jwt_privatekey
openssl rsa -in jwt_privatekey -pubout -out jwt_publickey

# James reports these URLs in its JMAP session: the app uses them for every
# later request, so they have to be the ones the emulator can reach.
sed -i.bak "s|url.prefix=.*|url.prefix=http://${EMULATOR_HOST}|" jmap.properties
sed -i.bak "s|websocket.url.prefix=.*|websocket.url.prefix=ws://${EMULATOR_HOST}|" jmap.properties

echo "Starting tmail-backend..."
docker compose up -d tmail-backend
# Never allow a broken James container to stall the job forever.
backend_ready=0
for attempt in $(seq 1 150); do
    backend_logs="$(docker compose logs --no-color tmail-backend 2>&1 || true)"
    if grep -qi "JAMES server started" <<<"$backend_logs"; then
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

docker exec tmail-backend /root/conf/integration_test/provisioning.sh

cd "$REPO_DIR"

RESET_SERVER_LOG="/tmp/backend-reset-server.log"
echo "Starting backend reset server on port $RESET_PORT (logs: $RESET_SERVER_LOG)..."
RESET_PORT="$RESET_PORT" python3 scripts/backend-reset-server.py > "$RESET_SERVER_LOG" 2>&1 &
RESET_SERVER_PID=$!

echo "Running the Android Patrol tests on the emulator..."
patrol test -v \
    --tags=android \
    --dart-define=USERNAME="$BOB" \
    --dart-define=PASSWORD="$BOB" \
    --dart-define=ADDITIONAL_MAIL_RECIPIENT="$ALICE@$DOMAIN" \
    --dart-define=BASIC_AUTH_EMAIL="$BOB@$DOMAIN" \
    --dart-define=BASIC_AUTH_URL="http://${EMULATOR_HOST}" \
    --dart-define=RESET_SERVER_URL="http://${EMULATOR_HOST}:${RESET_PORT}"
