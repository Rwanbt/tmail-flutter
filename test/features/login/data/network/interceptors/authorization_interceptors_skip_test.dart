import 'dart:io';
import 'dart:typed_data';

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

/// A deterministic transport boundary for the entire Dio interceptor chain.
/// Flutter widget tests override dart:io HttpClient, so a loopback HttpServer
/// would not reliably exercise the request without replacing that override.
class _RecordingJmapAdapter implements HttpClientAdapter {
  final int jmapStatusCode;
  final requests = <RequestOptions>[];

  _RecordingJmapAdapter({this.jmapStatusCode = 200});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '',
      options.uri.path == '/jmap' ? jmapStatusCode : 401,
    );
  }

  @override
  void close({bool force = false}) {}
}

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

  test('Dio JMAP and discovery transport enforces the auth boundary', () async {
    // Use the real Dio chain through the HTTP-adapter boundary. No network,
    // accounts or real credentials are used by this regression test.
    final seen = <String, List<String?>>{};

    final registry = AppLoggerRegistry.instance;
    final logs = CapturingLogHandler();
    registry.resetForTesting();
    registry.registerHandler(logs);
    try {
      for (final useOidc in [false, true]) {
        final dio = Dio();
        final adapter = _RecordingJmapAdapter();
        dio.httpClientAdapter = adapter;
        final interceptor = AuthorizationInterceptors(
          dio,
          _FakeAuthenticationClient(),
          _FakeTokenOidcCacheManager(),
          _FakeAccountCacheManager(),
          _FakeIOSSharingManager(),
        );
        if (useOidc) {
          interceptor.setTokenAndAuthorityOidc(
            newToken: OIDCFixtures.tokenOidcNotExpiredYet,
            newConfig: OIDCFixtures.oidcConfiguration,
          );
        } else {
          interceptor.setBasicAuthorization(UserName('fixture-user'), Password('fixture-password'));
        }
        dio.interceptors.add(interceptor);

        const baseUrl = 'https://fixture.invalid';
        final response = await dio.get<void>('$baseUrl/jmap');
        expect(response.statusCode, 200);

        // A guessed host may already carry preset mixed-case auth headers.
        // Its opt-out must strip them even when the server responds with 401,
        // without attempting a token refresh or sending a second request.
        await expectLater(
          dio.get<void>(
            '$baseUrl/.well-known/webfinger?secret=private-discovery-query',
            options: Options(
              headers: {'Authorization': 'Bearer should-never-reach-network'},
              extra: {AuthorizationInterceptors.skipAuthorizationKey: true},
            ),
          ),
          throwsA(isA<DioException>()),
        );
        for (final request in adapter.requests) {
          seen.putIfAbsent(request.uri.path, () => []).add(
            request.headers.entries
                .where((entry) => entry.key.toLowerCase() == HttpHeaders.authorizationHeader)
                .map((entry) => entry.value.toString())
                .firstOrNull,
          );
        }
        dio.close(force: true);
      }

      expect(seen['/jmap'], hasLength(2));
      expect(seen['/jmap']![0], startsWith('Basic '));
      expect(seen['/jmap']![1], startsWith('Bearer '));
      expect(seen['/.well-known/webfinger'], [null, null]);
      final recorded = logs.records.map((entry) => entry.rawMessage).join(' ');
      expect(recorded, isNot(contains('private-discovery-query')));
      expect(recorded, isNot(contains('should-never-reach-network')));
      expect(recorded, isNot(contains('fixture-password')));
    } finally {
      registry.resetForTesting();
    }
  });

  test('a JMAP 401 does not log the full URL, token query or request body', () async {
    final registry = AppLoggerRegistry.instance;
    final logs = CapturingLogHandler();
    final dio = Dio();
    final adapter = _RecordingJmapAdapter(jmapStatusCode: 401);
    dio.httpClientAdapter = adapter;
    final interceptor = AuthorizationInterceptors(
      dio,
      _FakeAuthenticationClient(),
      _FakeTokenOidcCacheManager(),
      _FakeAccountCacheManager(),
      _FakeIOSSharingManager(),
    )..setBasicAuthorization(UserName('alice'), Password('secret'));
    dio.interceptors.add(interceptor);
    registry.resetForTesting();
    registry.registerHandler(logs);
    try {
      // Drive the actual Dio request/error pipeline. Directly invoking
      // onError with an unattached ErrorInterceptorHandler leaves its
      // rejected Future unobserved and fails the VM test asynchronously.
      await expectLater(
        dio.post<void>(
          'https://jmap.example.org/jmap?secret=never-log-this',
          data: {'body': 'private-draft-message'},
        ),
        throwsA(
          isA<DioException>().having(
            (error) => error.response?.statusCode,
            'JMAP response status',
            401,
          ),
        ),
      );

      expect(adapter.requests, hasLength(1),
          reason: 'A basic-auth 401 must not silently retry or refresh');
      expect(adapter.requests.single.uri.query, 'secret=never-log-this');
      expect(adapter.requests.single.data, {'body': 'private-draft-message'});
      final recorded = logs.records.map((entry) => entry.rawMessage).join(' ');
      expect(recorded, contains('statusCode=401'));
      expect(recorded, isNot(contains('never-log-this')));
      expect(recorded, isNot(contains('private-draft-message')));
      expect(recorded, isNot(contains('jmap.example.org')));
    } finally {
      dio.close(force: true);
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
