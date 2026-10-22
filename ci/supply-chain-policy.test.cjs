const assert = require('node:assert/strict')
const { readFileSync } = require('node:fs')
const { join } = require('node:path')
const { test } = require('node:test')

const dockerfile = readFileSync(
  join(__dirname, '..', 'Dockerfile'),
  'utf8'
)
const imageWorkflow = readFileSync(
  join(__dirname, '..', '.github', 'workflows', 'image.yaml'),
  'utf8'
)

test('every container base image is pinned by digest', () => {
  const baseImages = [
    ...dockerfile.matchAll(/^FROM\s+(?:--platform=\S+\s+)?(\S+)/gm),
  ].map((match) => match[1])

  assert.ok(baseImages.length >= 2, 'the Dockerfile must declare its base images')
  for (const image of baseImages) {
    assert.match(
      image,
      /@sha256:[0-9a-f]{64}$/,
      `base image is not pinned by digest: ${image}`
    )
  }
})

test('the published image carries an SBOM and a build provenance', () => {
  assert.match(imageWorkflow, /sbom: true/)
  assert.match(imageWorkflow, /provenance: mode=max/)
})

test('the published image is identified by its digest', () => {
  assert.match(imageWorkflow, /id: build/)
  assert.match(imageWorkflow, /steps\.build\.outputs\.digest/)
})
