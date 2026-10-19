/// Starts the integration-test app only after the dependencies and, when
/// requested, the disposable test credentials are ready.
///
/// Mounting before credential seeding lets the initial home route read empty
/// storage. Later tests can then pass by inheriting a prior browser session,
/// while the first test waits forever for the mailbox dashboard.
Future<void> bootstrapTestApp({
  required Future<void> Function() preload,
  required Future<void> Function() seedCredentials,
  required void Function() mount,
  required bool enableCredentialSeeding,
}) async {
  await preload();
  if (enableCredentialSeeding) {
    await seedCredentials();
  }
  mount();
}
