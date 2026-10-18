import 'dart:io';

import 'package:dio/dio.dart';
import 'package:core/utils/logging/app_logger_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmap_dart_client/jmap/core/user_name.dart';
import 'package:model/account/password.dart';
import 'package:tmail_ui_user/features/login/data/local/account_cache_manager.dart';
import 'package:tmail_ui_user/features/login/data/local/token_oidc_cache_manager.dart';
import 'package:tmail_ui_user/features/login/data/network/authentication_client/authentication_client_base.dart';
import 'package:tmail_ui_user/features/login/data/network/interceptors/authorization_interceptors.dart';
import 'package:tmail_ui_user/main/utils/ios_sharing_manager.dart';

import '../../../../../fixtures/oidc_fixtures.dart';
import '../../../../../fixtures/capturing_log_handler.dart';

class _FakeAuthenticationClient extends Fake implements AuthenticationClientBase {}

class _FakeTokenOidcCacheManager extends Fake implements TokenOidcCacheManager {}

class _FakeAccountCacheManager extends Fake implements AccountCacheManager {}

class _FakeIOSSharingManager extends Fake implements IOSSharingManager {}

void main() {
  late AuthorizationInterceptors interceptors;

  setUp(() {
    interceptors = AuthorizationInterceptors(
      Dio(),
      _FakeAuthenticationClient(),
      _FakeTokenOidcCacheManager(),
      _FakeAccountCacheManager(),
      _FakeIOSSharingManager(),
    );
    interceptors.setBasicAuthorization(UserName('alice'), Password('secret'));
  });

  RequestOptions intercept(RequestOptions options) {
    interceptors.onRequest(options, RequestInterceptorHandler());
    return options;
  }

  test('SHOULD attach credentials to regular requests', () {
    final options = intercept(RequestOptions(path: 'https://jmap.example.com/jmap'));

    expect(options.headers[HttpHeaders.authorizationHeader], startsWith('Basic '));
  });

  test('SHOULD NOT attach credentials when the request opts out', () {
    final options = intercept(RequestOptions(
      path: 'https://guessed.example.org/.well-known/webfinger',
      extra: {AuthorizationInterceptors.skipAuthorizationKey: true},
    ));

    expect(options.headers.containsKey(HttpHeaders.authorizationHeader), isFalse);
  });

  test('SHOULD strip a preset Authorization header when the request opts out', () {
    final options = intercept(RequestOptions(
      path: 'https://guessed.example.org/.well-known/webfinger',
      headers: {HttpHeaders.authorizationHeader: 'Bearer leaked'},
      extra: {AuthorizationInterceptors.skipAuthorizationKey: true},
    ));

    expect(options.headers.containsKey(HttpHeaders.authorizationHeader), isFalse);
  });

  test('SHOULD strip all casings of Authorization on an opted-out request', () {
    final options = intercept(RequestOptions(
      path: 'https://guessed.example.org/.well-known/webfinger',
      headers: {'Authorization': 'Bearer token-a', 'AUTHORIZATION': 'Bearer token-b'},
      extra: {AuthorizationInterceptors.skipAuthorizationKey: true},
    ));

    expect(
      options.headers.keys.where((key) => key.toLowerCase() == HttpHeaders.authorizationHeader),
      isEmpty,
    );
  });

  test('SHOULD never log a draft body, credentials or URL query parameter', () {
    final handler = CapturingLogHandler();
    final registry = AppLoggerRegistry.instance;
    registry.resetForTesting();
    registry.registerHandler(handler);
    try {
      final options = intercept(RequestOptions(
        path: 'https://jmap.example.com/jmap?secret=token-in-query',
        method: 'POST',
        data: {'htmlBody': '<p>private-draft-text</p>'},
      ));

      expect(options.headers[HttpHeaders.authorizationHeader], startsWith('Basic '));
      expect(handler.records, isNotEmpty);
      final logs = handler.records.map((record) => record.rawMessage).join(' ');
      expect(logs, contains('METHOD = POST'));
      expect(logs, isNot(contains('private-draft-text')));
      expect(logs, isNot(contains('token-in-query')));
      expect(logs, isNot(contains('secret')));
    } finally {
      registry.resetForTesting();
    }
  });

  group('WHEN authenticated with a valid OIDC token', () {
    setUp(() {
      interceptors.setTokenAndAuthorityOidc(
        newToken: OIDCFixtures.tokenOidcNotExpiredYet,
        newConfig: OIDCFixtures.oidcConfiguration,
      );
    });

    test('SHOULD attach the Bearer token to regular requests', () {
      final options = intercept(RequestOptions(path: 'https://jmap.example.com/jmap'));

      expect(options.headers[HttpHeaders.authorizationHeader], startsWith('Bearer '));
    });

    test('SHOULD NOT attach the Bearer token when the request opts out', () {
      final options = intercept(RequestOptions(
        path: 'https://guessed.example.org/.well-known/webfinger',
        extra: {AuthorizationInterceptors.skipAuthorizationKey: true},
      ));

      expect(options.headers.containsKey(HttpHeaders.authorizationHeader), isFalse);
    });
  });
}
