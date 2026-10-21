import 'package:core/data/network/dio_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:model/oidc/oidc_configuration.dart';
import 'package:model/oidc/request/oidc_request.dart';
import 'package:model/oidc/response/oidc_link_dto.dart';
import 'package:model/oidc/response/oidc_response.dart';
import 'package:tmail_ui_user/features/login/domain/model/base_url_oidc_response.dart';
import 'package:tmail_ui_user/features/login/data/network/interceptors/authorization_interceptors.dart';
import 'package:tmail_ui_user/features/login/data/network/oidc_error.dart';
import 'package:tmail_ui_user/features/login/data/network/oidc_http_client.dart';
import 'package:tmail_ui_user/features/login/domain/exceptions/login_exception.dart';

import 'oidc_http_client_test.mocks.dart';

@GenerateNiceMocks([MockSpec<DioClient>()])
void main() {
  final dioClient = MockDioClient();
  final oidcHttpClient = OIDCHttpClient(dioClient);
  final requestOptions = RequestOptions();
  final oidcRequest = OIDCRequest(baseUrl: '', resourceUrl: '');

  group('oidc http client test:', () {
    test(
      'should throw CanNotFoundOIDCLinks '
      'when checkOIDCIsAvailable() is called '
      'and dioClient throw DioException '
      'and status code is 404',
    () {
      // arrange
      when(dioClient.get(any, options: anyNamed('options'))).thenThrow(DioException(
        requestOptions: requestOptions,
        response: Response(requestOptions: requestOptions, statusCode: 404)));

      // assert
      expect(
        () => oidcHttpClient.checkOIDCIsAvailable(oidcRequest),
        throwsA(isA<CanNotFoundOIDCLinks>()));
    });  

    test(
      'should throw CanRetryOIDCException '
      'when checkOIDCIsAvailable() is called '
      'and dioClient throw DioException '
      'and status code is not 404',
    () {
      // arrange
      when(dioClient.get(any, options: anyNamed('options'))).thenThrow(DioException(
        requestOptions: requestOptions,
        response: Response(requestOptions: requestOptions, statusCode: 403)));

      // assert
      expect(
        () => oidcHttpClient.checkOIDCIsAvailable(oidcRequest),
        throwsA(isA<CanRetryOIDCException>()));
    });

    test(
      'should throw CanRetryOIDCException '
      'when checkOIDCIsAvailable() is called '
      'and dioClient throw exception that is not DioException',
    () {
      // arrange
      when(dioClient.get(any, options: anyNamed('options'))).thenThrow(Exception());

      // assert
      expect(
        () => oidcHttpClient.checkOIDCIsAvailable(oidcRequest),
        throwsA(isA<CanRetryOIDCException>()));
    });

    test(
      'should send the WebFinger request with skipAuthorization '
      'when checkOIDCIsAvailable() is called',
    () async {
      // arrange
      clearInteractions(dioClient);
      when(dioClient.get(any, options: anyNamed('options')))
        .thenAnswer((_) async => {'subject': '', 'links': []});

      // act
      await oidcHttpClient.checkOIDCIsAvailable(oidcRequest);

      // assert
      verify(dioClient.get(
        any,
        options: argThat(
          predicate<Options>((o) => o.extra?[AuthorizationInterceptors.skipAuthorizationKey] == true),
          named: 'options',
        ),
      )).called(1);
    });

    test('WebFinger must select OIDC issuer relation, not first arbitrary link', () async {
      final response = OIDCResponse('acct:test@example.org', [
        OIDCLinkDto(
          Uri.parse('https://example.org/other-relation'),
          Uri.parse('https://attacker.example.org/'),
        ),
        OIDCLinkDto(
          Uri.parse(OIDCRequest.relUrl),
          Uri.parse('https://sso.example.org/realms/twake'),
        ),
      ]);

      final config = await oidcHttpClient.getOIDCConfiguration(response);
      expect(config.authority, 'https://sso.example.org/realms/twake');
      expect(config.discoveryUrl, 'https://sso.example.org/realms/twake/.well-known/openid-configuration');
    });

    test('WebFinger missing issuer relation fails closed', () async {
      final response = OIDCResponse('acct:test@example.org', [
        OIDCLinkDto(
          Uri.parse('https://unrelated.example.org/type'),
          Uri.parse('https://unrelated.example.org/'),
        ),
      ]);
      await expectLater(
        oidcHttpClient.getOIDCConfiguration(response),
        throwsA(isA<CanNotFoundOIDCAuthority>()),
      );
    });

    test('WebFinger rejects unsafe or malformed issuer URLs', () async {
      for (final href in [
        'http://public-idp.example.org',
        'javascript:alert(1)',
        'https://user:password@sso.example.org',
        'https://sso.example.org/issuer?token=secret',
        'https://sso.example.org/issuer#fragment',
        '/relative-path',
      ]) {
        final response = OIDCResponse('acct:test@example.org', [
          OIDCLinkDto(Uri.parse(OIDCRequest.relUrl), Uri.parse(href)),
        ]);
        await expectLater(
          oidcHttpClient.getOIDCConfiguration(response),
          throwsA(isA<CanNotFoundOIDCAuthority>()),
          reason: 'Untrusted WebFinger issuer must fail closed: $href',
        );
      }
    });

    test('HTTPS base-URL guesses and loopback HTTP remain usable', () async {
      for (final href in [
        'https://sso.example.org',
        'http://localhost:8080',
        'http://127.0.0.1:8080',
      ]) {
        final config = await oidcHttpClient.getOIDCConfiguration(
          BaseUrlOidcResponse(Uri.parse(href)),
        );
        expect(config.authority, href);
      }
    });

    test('OIDC discovery accepts metadata only for the configured issuer', () async {
      final config = OIDCConfiguration(
        authority: 'https://sso.example.org/realms/twake',
        clientId: 'test-client',
        scopes: ['openid'],
      );
      when(dioClient.getWithNewDio(config.discoveryUrl)).thenAnswer((_) async => {
        'issuer': config.authority,
        'authorization_endpoint': 'https://sso.example.org/authorize',
        'token_endpoint': 'https://sso.example.org/token',
      });

      final metadata = await oidcHttpClient.discoverOIDC(config);
      expect(metadata.authorizationEndpoint, 'https://sso.example.org/authorize');
      expect(metadata.tokenEndpoint, 'https://sso.example.org/token');
      verify(dioClient.getWithNewDio(config.discoveryUrl)).called(1);
    });

    test('OIDC discovery rejects issuer substitution, omission and incorrect types', () async {
      final config = OIDCConfiguration(
        authority: 'https://sso.example.org/realms/twake',
        clientId: 'test-client',
        scopes: ['openid'],
      );
      final untrustedMetadata = <Map<String, dynamic>>[
        {
          'issuer': 'https://attacker.example.org',
          'authorization_endpoint': 'https://attacker.example.org/authorize',
          'token_endpoint': 'https://attacker.example.org/token',
        },
        {'authorization_endpoint': 'https://attacker.example.org/authorize'},
        {'issuer': 123},
        {'issuer': 'https://sso.example.org/realms/twake/'},
      ];
      for (final response in untrustedMetadata) {
        when(dioClient.getWithNewDio(config.discoveryUrl))
            .thenAnswer((_) async => response);
        await expectLater(
          oidcHttpClient.discoverOIDC(config),
          throwsA(isA<InvalidOIDCResponseException>()),
          reason: 'OIDC discovery must bind metadata to the exact selected issuer',
        );
      }
    });

    test('OIDC discovery verifies issuer when metadata is JSON text', () async {
      final config = OIDCConfiguration(
        authority: 'https://sso.example.org/realms/twake',
        clientId: 'test-client',
        scopes: ['openid'],
      );
      when(dioClient.getWithNewDio(config.discoveryUrl))
          .thenAnswer((_) async => '{"issuer":"https://different.example.org"}');
      await expectLater(
        oidcHttpClient.discoverOIDC(config),
        throwsA(isA<InvalidOIDCResponseException>()),
      );
    });
  });
}