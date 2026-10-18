import 'package:core/data/network/dio_client.dart';
import 'package:core/presentation/utils/html_transformer/base/dom_transformer.dart';
import 'package:core/presentation/utils/html_transformer/sanitize_url.dart';
import 'package:core/utils/external_link_policy.dart';
import 'package:core/utils/app_logger.dart';
import 'package:html/dom.dart';

class SanitizeHyperLinkTagInHtmlTransformer extends DomTransformer {
  final _sanitizeUrl = SanitizeUrl();

  SanitizeHyperLinkTagInHtmlTransformer();

  @override
  Future<void> process({
    required Document document,
    required DioClient dioClient,
    Map<String, String>? mapUrlDownloadCID,
  }) async {
    try {
      final elements = document.querySelectorAll('a[href]');

      if (elements.isEmpty) return;

      await Future.wait(elements.map((element) async {
        _sanitizeUrlResource(element);
        _addBlankForTargetProperty(element);
        _addNoReferrerForRelProperty(element);
      }));
    } catch (e) {
      logWarning('$runtimeType::process:Exception = $e');
    }
  }

  void _sanitizeUrlResource(Element element) {
    final rawUrl = element.attributes['href'] ?? '';
    final url = _withDefaultScheme(rawUrl);

    if (_isRelativeUrl(url)) {
      // Relative links cannot be resolved against a trusted base (the email
      // <base> is stripped), so make them inert rather than guessing a host.
      element.attributes.remove('href');
      return;
    }

    final urlSanitized = _sanitizeUrl.process(url);
    final decoded = _tryDecode(url);
    if (decoded == null) {
      element.attributes.remove('href');
    } else if (urlSanitized.isNotEmpty) {
      final parsed = Uri.tryParse(urlSanitized);
      if (parsed == null ||
          !ExternalLinkPolicy.canLaunchFromContent(parsed) ||
          ((parsed.scheme == 'http' || parsed.scheme == 'https') &&
              parsed.host.isEmpty)) {
        element.attributes.remove('href');
        return;
      }
      element.attributes['href'] = urlSanitized;
    } else {
      // Keep legitimate non-web links (mailto/tel/etc.) that the shared
      // external-link policy allows. Reject all other raw hrefs: leaving
      // the original DOM attribute unchanged is a fail-open behavior.
      final parsed = Uri.tryParse(decoded);
      if (parsed == null ||
          !parsed.hasScheme ||
          !ExternalLinkPolicy.canLaunchFromContent(parsed)) {
        element.attributes.remove('href');
      }
    }
  }

  /// Only scheme-less hrefs that unambiguously name a host get `https`.
  /// A "looks like a domain" check would turn `setup.zip` into a real host.
  String _withDefaultScheme(String url) {
    final trimmedUrl = url.trim();
    if (trimmedUrl.startsWith('//')) return 'https:$trimmedUrl';
    if (trimmedUrl.toLowerCase().startsWith('www.')) return 'https://$trimmedUrl';
    return url;
  }

  bool _isRelativeUrl(String url) {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty || trimmedUrl.startsWith('#')) {
      return false;
    }
    final uri = Uri.tryParse(_tryDecode(trimmedUrl) ?? trimmedUrl);
    return uri == null || !uri.hasScheme;
  }

  String? _tryDecode(String url) {
    try {
      return Uri.decodeFull(url);
    } catch (_) {
      return null;
    }
  }

  void _addBlankForTargetProperty(Element element) {
    element.attributes['target'] = '_blank';
  }

  void _addNoReferrerForRelProperty(Element element) {
    final tokens = (element.attributes['rel'] ?? '')
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty && token.toLowerCase() != 'opener')
        .toSet();
    tokens.addAll({'noopener', 'noreferrer'});
    element.attributes['rel'] = tokens.join(' ');
  }
}
