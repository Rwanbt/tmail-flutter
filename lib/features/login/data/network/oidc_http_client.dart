
import 'dart:convert';
import 'dart:io';

import 'package:core/data/model/query/query_parameter.dart';
import 'package:core/data/network/dio_client.dart';
import 'package:core/utils/app_logger.dart';
import 'package:dio/dio.dart' show DioException, Options;
import 'package:get/get_connect/http/src/exceptions/exceptions.dart';
import 'package:model/oidc/oidc_configuration.dart';
import 'package:model/oidc/request/oidc_request.dart';
import 'package:model/oidc/response/oidc_discovery_response.dart';
import 'package:model/oidc/response/oidc_response.dart';
import 'package:model/oidc/response/oidc_user_info.dart';
import 'package:tmail_ui_user/features/login/data/extensions/service_path_extension.dart';
import 'package:tmail_ui_user/features/login/data/network/config/oidc_constant.dart';
import 'package:tmail_ui_user/features/login/data/network/endpoint.dart';
import 'package:tmail_ui_user/features/login/data/network/interceptors/authorization_interceptors.dart';
import 'package:tmail_ui_user/features/login/data/network/oidc_error.dart';
import 'package:tmail_ui_user/features/login/domain/model/base_url_oidc_response.dart';
import 'package:tmail_ui_user/features/login/domain/exceptions/login_exception.dart';
import 'package:tmail_ui_user/main/utils/app_config.dart';

class OIDCHttpClient {

  final DioClient _dioClient;

  OIDCHttpClient(this._dioClient);

  Future<OIDCResponse> checkOIDCIsAvailable(OIDCRequest oidcRequest) async {
    try {
      final result = await _dioClient.get(
        Endpoint.webFinger
          .usingBaseUrl(oidcRequest.baseUrl)
          .withQueryParameters([
            StringQueryParameter('resource', oidcRequest.resourceUrl),
            StringQueryParameter('rel', OIDCRequest.relUrl),
          ])
          .generateEndpointPath(),
        // WebFinger is public discovery, possibly sent to hosts guessed from
        // the email address domain: never attach the user's credentials.
        options: Options(
          extra: {AuthorizationInterceptors.skipAuthorizationKey: true},
        ),
      );
      log('OIDCHttpClient::checkOIDCIsAvailable(): discovery response received');
      if (result is Map<String, dynamic>) {
        return OIDCResponse.fromJson(result);
      } else {
        return OIDCResponse.fromJson(jsonDecode(result));
      }
    } on FormatException {
      logWarning('OIDCHttpClient::checkOIDCIsAvailable(): invalid discovery response');
      throw InvalidOIDCResponseException();
    } on DioException catch (exception) {
      if (exception.error is HandshakeException) {
        throw exception.error!;
      } else if (exception.error is SocketException) {
        throw exception.error!;
      } else if (exception.response?.statusCode == 401) {
        throw UnauthorizedException();
      } else if (exception.response?.statusCode == 404) {
        throw CanNotFoundOIDCLinks();
      }
      throw CanRetryOIDCException();
    } catch (_) {
      throw CanRetryOIDCException();
    }
  }

  Future<OIDCConfiguration> getOIDCConfiguration(OIDCResponse oidcResponse) async {
    // WebFinger can advertise multiple unrelated link relations. An attacker-
    // controlled first link is not an OIDC issuer; accept only the issuer rel.
    // Base-URL discovery is a separate guessed flow with a synthetic link.
    final issuerLinks = oidcResponse is BaseUrlOidcResponse
        ? oidcResponse.links
        : oidcResponse.links.where(
            (link) => link.rel.toString() == OIDCRequest.relUrl,
          );
    if (issuerLinks.isEmpty) {
      throw CanNotFoundOIDCAuthority();
    }
    final issuer = issuerLinks.first.href;
    final isLocalHttp = issuer.scheme == 'http' &&
        {'localhost', '127.0.0.1', '::1'}.contains(issuer.host);
    // OIDC issuer discovery and token exchanges must not use plaintext on
    // public hosts. Query/fragment/userinfo are not issuer identifiers.
    if ((!issuer.hasAuthority || issuer.host.isEmpty) ||
        (issuer.scheme != 'https' && !isLocalHttp) ||
        issuer.userInfo.isNotEmpty ||
        issuer.hasQuery ||
        issuer.hasFragment) {
      throw CanNotFoundOIDCAuthority();
    }
    final authority = issuer.toString();
    final isTWP = authority == AppConfig.saasRegistrationUrl;
    log('OIDCHttpClient::getOIDCConfiguration(): authority selected');
    return OIDCConfiguration(
      authority: authority,
      clientId: OIDCConstant.clientId,
      scopes: AppConfig.oidcScopes,
      isTWP: isTWP,
    );
  }

  Future<OIDCDiscoveryResponse> discoverOIDC(OIDCConfiguration configuration) async {
    final result = await _dioClient.getWithNewDio(configuration.discoveryUrl);
    log('OIDCHttpClient::discoverOIDC(): provider metadata received');
    if (result is Map<String, dynamic>) {
      return OIDCDiscoveryResponse.fromJson(result);
    } else {
      return OIDCDiscoveryResponse.fromJson(jsonDecode(result));
    }
  }

  Future<OidcUserInfo> fetchUserInfo(String userInfoEndpoint) async {
    final result = await _dioClient.get(userInfoEndpoint);

    if (result is Map<String, dynamic>) {
      return OidcUserInfo.fromJson(result);
    } else {
      return OidcUserInfo.fromJson(jsonDecode(result));
    }
  }
}
