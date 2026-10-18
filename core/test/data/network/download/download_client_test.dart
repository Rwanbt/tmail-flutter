import 'package:core/data/network/download/download_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DownloadClient.encodeToBase64Uri', () {
    test('attribute-escapes the file name and cid', () {
      final result = DownloadClient.encodeToBase64Uri({
        'bytesData': <int>[1, 2, 3],
        'mimeType': 'image/png',
        'cid': '"><script>alert(1)</script>',
        'fileName': '"><script>alert(1)</script>.png',
      });

      expect(result, isNot(contains('<script>')));
      expect(result, contains('alt="&quot;&gt;&lt;script&gt;alert(1)&lt;/script&gt;"'));
      expect(result, contains('id="cid:&quot;&gt;&lt;script&gt;alert(1)&lt;/script&gt;"'));
    });

    test('never emits an executable data URI from a hostile MIME header', () {
      for (final mime in [
        'text/html',
        'image/svg+xml',
        'image/svg',
        'image/png" onerror="alert(1)',
        'image/png; charset=utf-8',
      ]) {
        final result = DownloadClient.encodeToBase64Uri({
          'bytesData': <int>[1, 2, 3],
          'mimeType': mime,
          'cid': 'avatar@localhost',
          'fileName': 'avatar.png',
        });

        expect(result, contains('src="data:application/octet-stream;base64,AQID"'), reason: mime);
        expect(result, contains('data-mimetype="application/octet-stream"'), reason: mime);
        expect(result, isNot(contains('onerror=')), reason: mime);
      }
    });

    test('preserves safe raster media types and normalizes casing', () {
      final result = DownloadClient.encodeToBase64Uri({
        'bytesData': <int>[1, 2, 3],
        'mimeType': ' IMAGE/PNG ',
        'cid': 'image@localhost',
        'fileName': 'image.png',
      });

      expect(result, contains('src="data:image/png;base64,AQID"'));
      expect(result, contains('data-mimetype="image/png"'));
    });
  });
}
