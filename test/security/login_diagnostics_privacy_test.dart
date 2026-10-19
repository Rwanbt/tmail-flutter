import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('login diagnostics never serialize credentials or OIDC links', () {
    // Log statements are intentionally constants: a previous implementation
    // serialized usernames, deep-link authorization data and login hints.
    // This executable contract prevents accidentally reintroducing dynamic
    // secret-bearing objects into any LoginController log invocation.
    final source = File(
      'lib/features/login/presentation/login_controller.dart',
    ).readAsStringSync();
    final logCalls = <String>[];
    for (final match in RegExp(r'\blog\(').allMatches(source)) {
      final end = source.indexOf(');', match.end);
      expect(end, greaterThan(match.end));
      logCalls.add(source.substring(match.start, end + 2));
    }

    expect(logCalls.length, greaterThanOrEqualTo(10));
    for (final call in logCalls) {
      expect(
        call,
        isNot(contains(r'$')),
        reason: 'Login log interpolates a secret-bearing value: $call',
      );
      expect(
        call,
        isNot(contains('toString()')),
        reason: 'Do not serialize credential-bearing objects into logs',
      );
    }
  });
}
