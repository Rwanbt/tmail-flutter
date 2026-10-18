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
      return originalUrl;
    } catch (e) {
      logWarning('SanitizeUrl::process:Exception = $e');
      // Never turn a decoder failure into an approved link: the caller
      // renders untrusted email HTML and may otherwise preserve a hostile href.
      return '';
    }
  }
}
