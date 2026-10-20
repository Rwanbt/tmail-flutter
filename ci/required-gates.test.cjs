const assert = require('node:assert/strict')
const { readFileSync } = require('node:fs')
const { join } = require('node:path')
const { test } = require('node:test')

const workflow = readFileSync(
  join(__dirname, '..', '.github', 'workflows', 'analyze-test.yaml'),
  'utf8'
)

test('Flutter tests are triggered by all pull request changes, including CI-only patches', () => {
  assert.match(workflow, /^on:\s*\r?\n  pull_request:\s*\r?\n/m)
  assert.doesNotMatch(workflow, /paths-ignore:|\bpaths:/)
  assert.match(workflow, /modules: \$\{\{ fromJSON\(needs\.discover-tests\.outputs\.modules\) \}\}/)
  assert.match(workflow, /fail-fast: false/)
})

test('PR analysis and JavaScript tests cannot silently succeed without running', () => {
  assert.match(workflow, /run: \.\/scripts\/test\.sh/)
  assert.match(workflow, /run: node --test/)
  assert.match(workflow, /run: \.\/scripts\/prebuild\.sh/)
  assert.match(workflow, /uses: zgosalvez\/github-actions-analyze-dart@[0-9a-f]{40}/)
  assert.doesNotMatch(workflow, /continue-on-error: true/)
  assert.doesNotMatch(workflow, /\bif: false\b/)
})

test('untrusted PR jobs have read-only token and pinned checkout without credentials', () => {
  assert.match(workflow, /^permissions:\s*\r?\n  contents: read\s*$/m)
  const checkouts = [...workflow.matchAll(/uses: actions\/checkout@([^\s]+)/g)]
  assert.ok(checkouts.length >= 3)
  for (const [, sha] of checkouts) assert.match(sha, /^[0-9a-f]{40}$/)
  const persistOptions = [...workflow.matchAll(/persist-credentials: false/g)]
  assert.equal(persistOptions.length, checkouts.length)
  assert.doesNotMatch(workflow, /\bsecrets\.SSH_KEY\b/)
})

test('pull-request analyzer and test code cannot read deployment Firebase secrets', () => {
  assert.doesNotMatch(workflow, /\$\{\{\s*secrets\./)
  assert.match(workflow, /FIREBASE_ENV: ''/)
  assert.match(workflow, /run: \.\/scripts\/setup-firebase\.sh/)
})
