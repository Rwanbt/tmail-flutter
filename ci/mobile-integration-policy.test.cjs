const assert = require('node:assert/strict')
const { readFileSync } = require('node:fs')
const { join } = require('node:path')
const { test } = require('node:test')

const workflow = readFileSync(
  join(__dirname, '..', '.github', 'workflows', 'patrol-integration-test.yaml'),
  'utf8'
)
const script = readFileSync(
  join(__dirname, '..', 'scripts', 'patrol-mobile-integration-test-with-docker.sh'),
  'utf8'
)

test('the mobile integration job runs the real Patrol scenario on the emulator', () => {
  assert.match(script, /patrol test -v/)
  assert.match(script, /--tags=android/)
  assert.match(script, /set -euo pipefail/)
  assert.match(script, /--dart-define=BASIC_AUTH_URL=/)
  assert.match(script, /--dart-define=RESET_SERVER_URL=/)
})

test('the mobile integration job needs neither a remote tunnel nor a cloud test lab', () => {
  // A remote tunnel to a public relay made the job depend on a binary that is
  // not in the runner image and on a third party service to reach the backend.
  assert.doesNotMatch(script, /\bbore\b/)
  assert.doesNotMatch(script, /firebase test/i)
  assert.doesNotMatch(script, /gcloud/)
  assert.doesNotMatch(workflow, /secrets\./)
})

test('the mobile integration job cannot hide a failure', () => {
  assert.doesNotMatch(workflow, /continue-on-error/)
  assert.doesNotMatch(workflow, /if: always\(\)/)
  assert.doesNotMatch(script, /continue-on-error/)
  assert.match(script, /patrol test -v/)
})

test('the disposable backend stack is bounded and always cleaned up', () => {
  assert.match(script, /for attempt in \$\(seq 1 150\)/)
  assert.match(script, /backend_ready=0/)
  assert.match(script, /if \[\[ "\$backend_ready" -ne 1 \]\]/)
  assert.match(script, /trap cleanup EXIT/)
  assert.match(script, /docker compose down/)
  assert.match(script, /openssl genpkey/)
})

test('the mobile integration job has minimal authority, pinned actions and a bounded runtime', () => {
  assert.match(workflow, /timeout-minutes: \d+/)
  assert.match(workflow, /contents: "read"/)
  const checkouts = [...workflow.matchAll(/uses: actions\/checkout@([^\s]+)/g)]
  assert.ok(checkouts.length >= 1)
  for (const [, sha] of checkouts) assert.match(sha, /^[0-9a-f]{40}$/)
  assert.match(workflow, /persist-credentials: false/)
  assert.doesNotMatch(workflow, /continue-on-error: true/)
})

test('the mobile integration job does not depend on the GitHub cache service', () => {
  // The cache service answered 400 ("Our services aren't available right now")
  // during the 2026-10-22 run: the job has to stay re-runnable without it.
  assert.match(workflow, /cache-disabled: true/)
})
