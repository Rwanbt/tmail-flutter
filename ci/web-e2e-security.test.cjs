const assert = require('node:assert/strict')
const { readFileSync } = require('node:fs')
const { join } = require('node:path')
const { test } = require('node:test')

const script = readFileSync(
  join(__dirname, '..', 'scripts', 'patrol-web-integration-test-with-docker.sh'),
  'utf8'
)
const workflow = readFileSync(
  join(__dirname, '..', '.github', 'workflows', 'reusable-web-integration-test.yaml'),
  'utf8'
)

test('real Patrol browser cannot bypass origin/CORS/security for an allegedly passing E2E', () => {
  assert.match(script, /patrol test -v/)
  assert.match(script, /--web-headless=true/)
  assert.doesNotMatch(script, /--disable-web-security|--allow-running-insecure-content/)
  assert.match(script, /--dart-define=BASIC_AUTH_URL=/)
  assert.match(script, /set -euo pipefail/)
})

test('disposable James stack has bounded readiness, cleanup and no user credentials', () => {
  assert.match(script, /for attempt in \$\(seq 1 150\)/)
  assert.match(script, /backend_ready=0/)
  assert.match(script, /if \[\[ "\$backend_ready" -ne 1 \]\]/)
  assert.match(script, /trap cleanup EXIT/)
  assert.match(script, /docker compose down/)
  assert.match(script, /openssl genpkey/)
  assert.doesNotMatch(script, /\$\{\{\s*secrets\./)
})

test('fork web E2E runs with minimal GitHub authority and exact toolchain actions', () => {
  assert.match(workflow, /timeout-minutes: 50/)
  assert.match(workflow, /contents: "read"/)
  assert.doesNotMatch(workflow, /id-token: "write"/)
  assert.match(workflow, /actions\/checkout@[0-9a-f]{40}/)
  assert.match(workflow, /subosito\/flutter-action@[0-9a-f]{40}/)
  assert.match(workflow, /persist-credentials: false/)
  assert.doesNotMatch(workflow, /continue-on-error: true/)
})
