import 'package:core/utils/app_logger.dart';
import 'package:get/get.dart';

class SanitizeUrl {

  final bool defaultToHttps;

  SanitizeUrl({this.defaultToHttps = true});

  final _protocolIdentifierRegex = RegExp(
    r'^(https?://)',
    caseSensitive: false,
  );

  String process(String inputText) {
    try {
      var originalUrl = Uri.decodeFull(inputText);
      if (GetUtils.isURL(originalUrl)) {
        originalUrl = !originalUrl.startsWith(_protocolIdentifierRegex)
          ? (defaultToHttps ? "https://" : "http://") + originalUrl
          : originalUrl;
      } else {
        originalUrl = '';
      }
      if (originalUrl.isNotEmpty) {
        final parsed = Uri.tryParse(originalUrl);
        // Links with credentials in the authority can display a trusted
        // looking hostname while navigating to an attacker-controlled host.
        // Auto-linked content must always have an unambiguous HTTP(S) host.
        if (parsed == null ||
            (parsed.scheme != 'http' && parsed.scheme != 'https') ||
            parsed.host.isEmpty ||
            parsed.userInfo.isNotEmpty) {
          return '';
        }
      }
      return originalUrl;
    } catch (_) {
      // Decoder exceptions can include fragments of the untrusted email body,
      // including embedded URLs with private query parameters. Do not log it.
      logWarning('SanitizeUrl::process: rejected malformed URL');
      // Never turn a decoder failure into an approved link: the caller
      // renders untrusted email HTML and may otherwise preserve a hostile href.
      return '';
    }
  }
}
