import 'package:core/presentation/utils/html_transformer/sanitize_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SanitizeUrl test', () {
    final sanitizeUrl = SanitizeUrl();

    test('SHOULD return valid url WHEN input text is valid url start with https', () {
      final validUrl = sanitizeUrl.process('https://linagora.com');
      expect(
        validUrl,
        equals('https://linagora.com')
      );
    });

    test('SHOULD return valid url WHEN input text is valid url start with http', () {
      final validUrl = sanitizeUrl.process('http://linagora.com');
      expect(
        validUrl,
        equals('http://linagora.com')
      );
    });

    test('SHOULD return valid url WHEN input text start with www', () {
      final validUrl = sanitizeUrl.process('www.linagora.com');
      expect(
        validUrl,
        equals('https://www.linagora.com')
      );
    });

    test('SHOULD return valid url WHEN input text start with valid domain', () {
      final validUrl = sanitizeUrl.process('linagora.com');
      expect(
        validUrl,
        equals('https://linagora.com')
      );
    });

    test('SHOULD return empty string text WHEN input text is empty', () {
      final validUrl = sanitizeUrl.process('');
      expect(
        validUrl,
        equals('')
      );
    });

    test('SHOULD return empty string text WHEN input text not contain url', () {
      final validUrl = sanitizeUrl.process('Linagora Company');
      expect(
        validUrl,
        equals('')
      );
    });

    test('SHOULD return empty string text WHEN input text is email address', () {
      final validUrl = sanitizeUrl.process('example@linagora.com');
      expect(
        validUrl,
        equals('')
      );
    });

    test('SHOULD return empty string text WHEN input text is mailto link', () {
      final validUrl = sanitizeUrl.process('mailto:example@linagora.com');
      expect(
        validUrl,
        equals('')
      );
    });

    test('SHOULD return empty string text WHEN input text is invalid url', () {
      final validUrl = sanitizeUrl.process('linagora mail.com');
      expect(
        validUrl,
        equals('')
      );
    });

    test('SHOULD return empty string WHEN input text start with //', () {
      final validUrl = sanitizeUrl.process('//linagora.com');
      expect(
        validUrl,
        equals('')
      );
    });

    test('SHOULD return empty string WHEN input text start with /', () {
      final validUrl = sanitizeUrl.process('/linagora.com');
      expect(
        validUrl,
        equals('')
      );
    });

    test('SHOULD return valid url WHEN input text is url encoded start with https', () {
      final validUrl = sanitizeUrl.process('https%3A%2F%2Flinagora.com');
      expect(
        validUrl,
        equals('https://linagora.com')
      );
    });

    test('SHOULD return valid url WHEN input text is url encoded start with http', () {
      final validUrl = sanitizeUrl.process('http%3A%2F%2Flinagora.com');
      expect(
        validUrl,
        equals('http://linagora.com')
      );
    });

    test('SHOULD fail closed WHEN decoding an untrusted URL throws', () {
      // Arrange
      const inputText = "%E0%A4%A";
      const expectedOutput = '';

      // Act
      final result = sanitizeUrl.process(inputText);

      // Assert
      expect(result, expectedOutput);
    });

    test('SHOULD reject URL authority userinfo spoofing in autolink text', () {
      expect(sanitizeUrl.process('https://trusted.example@evil.example/path'), '');
      expect(sanitizeUrl.process('http://alice:password@evil.example/'), '');
    });

    test('SHOULD retain legitimate HTTPS host with an explicit port', () {
      expect(sanitizeUrl.process('https://example.org:8443/inbox'),
          'https://example.org:8443/inbox');
    });
  });
}
