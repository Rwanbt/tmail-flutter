# Twake Mail Flutter — mandatory pull-request gate coverage

Base fork SHA: `6787ec6a5443541e051e4383a9e3564db737dd2b`.

Previously, the Flutter/JavaScript analysis workflow excluded CI-only
changes via `paths-ignore: ".github/**"`, and unpinned GitHub Actions
were executed with default token permissions. Workflow-only pull requests
could therefore skip this main validation path.

## Deterministic regression proof

```sh
node --test ci/required-gates.test.cjs
```

The three tests were RED against the original workflow (0/3), and are GREEN
after this change. They assert:

- All pull requests including CI-only PRs invoke the Flutter module matrix.
- The analyzer, test script, generated build preflight and JavaScript tests
  exist as required steps, without `continue-on-error`.
- The PR workflow uses read-only permissions, pinned checkout commits
  and `persist-credentials: false`.

The new `.github/workflows/ci-required-policy.yaml` runs this portable
Node.js policy test on every PR and master push. The full Flutter analysis
workflow now runs on all PRs and master pushes, with pinned action revisions.

**Remaining mandatory evidence:** every module's actual Flutter tests, the
complete JS suite, Android/iOS/web binary builds, release signing isolation,
JMAP/OIDC integration with a fake tenant, HTML rendering security tests,
accessibility testing and any required secret provisioning. The static policy
test does not guarantee those gates are green; inspect CI at the exact SHA.
