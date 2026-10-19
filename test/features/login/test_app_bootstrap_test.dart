import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/base/test_app_bootstrap.dart';

void main() {
  test('cold start waits for credentials before mounting the app', () async {
    final phases = <String>[];
    final credentialsReady = Completer<void>();

    final startup = bootstrapTestApp(
      preload: () async => phases.add('preload'),
      seedCredentials: () async {
        phases.add('seed-start');
        await credentialsReady.future;
        phases.add('seed-complete');
      },
      mount: () => phases.add('mount'),
      enableCredentialSeeding: true,
    );

    await Future<void>.delayed(Duration.zero);
    expect(phases, ['preload', 'seed-start']);

    credentialsReady.complete();
    await startup;
    expect(phases, ['preload', 'seed-start', 'seed-complete', 'mount']);
  });

  test('manual login starts without seeded credentials', () async {
    final phases = <String>[];
    await bootstrapTestApp(
      preload: () async => phases.add('preload'),
      seedCredentials: () async => phases.add('seed'),
      mount: () => phases.add('mount'),
      enableCredentialSeeding: false,
    );
    expect(phases, ['preload', 'mount']);
  });

  test('failed credential seeding never mounts the app', () async {
    var mounted = false;
    await expectLater(
      bootstrapTestApp(
        preload: () async {},
        seedCredentials: () async => throw StateError('seed failed'),
        mount: () => mounted = true,
        enableCredentialSeeding: true,
      ),
      throwsStateError,
    );
    expect(mounted, isFalse);
  });
}
