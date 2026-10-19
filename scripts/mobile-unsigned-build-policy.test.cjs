const { readFileSync } = require('node:fs')
const { join } = require('node:path')
const { test } = require('node:test')
const assert = require('node:assert/strict')

const workflow = readFileSync(
  join(__dirname, '..', '.github', 'workflows', 'mobile-unsigned-build.yaml'),
  'utf8'
)

test('native mobile smoke builds run on pull requests and dev without release permissions', () => {
  assert.match(workflow, /pull_request:/)
  assert.match(workflow, /branches:\s*\[dev\]/)
  assert.match(workflow, /permissions:\s*\n\s*contents: read/)
  assert.doesNotMatch(workflow, /secrets\.|environment:\s*prod|workflow_dispatch:/)
})

test('Android debug and iOS simulator are built without release signing or deployment', () => {
  assert.match(workflow, /flutter build apk --debug --no-pub/)
  assert.match(workflow, /flutter build ios --simulator --debug --no-pub/)
  assert.match(workflow, /ubuntu-latest/)
  assert.match(workflow, /macos-15/)
  assert.doesNotMatch(workflow, /fastlane|cozyPublish|build-release|PLAY_STORE|MATCH_PASSWORD/)
})
