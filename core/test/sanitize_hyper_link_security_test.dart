import 'package:core/data/network/dio_client.dart';
import 'package:core/presentation/utils/html_transformer/dom/sanitize_hyper_link_tag_in_html_transformers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:mockito/mockito.dart';

class _UnusedDioClient extends Mock implements DioClient {}

void main() {
  final transformer = SanitizeHyperLinkTagInHtmlTransformer();

  Future<Map<String, String>> processLink(String href, {String? rel}) async {
    final extra = rel == null ? '' : ' rel="$rel"';
    // Use real parsed HTML nodes instead of a mocked sanitizer response.
    final escaped = href.replaceAll('&', '&amp;').replaceAll('"', '&quot;');
    final doc = html.parse('<a href="$escaped"$extra>Go</a>');
    await transformer.process(document: doc, dioClient: _UnusedDioClient());
    return Map<String, String>.from(
      doc.querySelector('a')!.attributes.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );
  }

  group('untrusted email HTML link security', () {
    for (final href in [
      'javascript:alert(1)',
      'data:text/html,evil',
      'file:///etc/passwd',
      'about:blank',
      'intent://host/#Intent;scheme=https;end',
      '//www.bank.com@evil.com/',
      '///evil.com',
      'www.bank.com@evil.com',
      '%E0%A4%A',
      '/relative-path',
    ]) {
      test('removes unsafe href $href from actual DOM', () async {
        final attributes = await processLink(href);
        expect(attributes.containsKey('href'), isFalse);
      });
    }

    test('keeps an explicitly authorized https link and forces safe target', () async {
      final attributes = await processLink('https://example.org/article');
      expect(attributes['href'], 'https://example.org/article');
      expect(attributes['target'], '_blank');
      expect(attributes['rel']!.split(' '), contains('noreferrer'));
    });

    test('keeps allowed mailto and tel links without opening other schemes', () async {
      expect((await processLink('mailto:person@example.org'))['href'], 'mailto:person@example.org');
      expect((await processLink('tel:+33123456789'))['href'], 'tel:+33123456789');
    });

    test('removes rel=opener and cannot leak referrer via noopener alone', () async {
      final attributes = await processLink('https://example.org', rel: 'opener noopener nofollow');
      final rel = attributes['rel']!.split(' ');
      expect(rel, containsAll(['noreferrer', 'nofollow']));
      expect(rel, isNot(contains('opener')));
    });
  });
}
