import 'dart:convert';

import 'package:core/presentation/utils/html_transformer/dom/image_transformers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImageTransformer CID image conversion', () {
    test('uses exact base64 padding for 1, 2 and 3-byte JPEGs', () {
      for (final bytes in [<int>[1], <int>[1, 2], <int>[1, 2, 3]]) {
        final expected = base64Encode(bytes);
        final actual = ImageTransformer.encodeToBase64Uri({
          'bytesData': bytes,
          'mimeType': 'image/jpeg',
        });

        expect(actual, 'data:image/jpeg;base64,$expected');
        expect(base64Decode(actual.split(',').last), bytes);
      }
    });

    test('rejects MIME types capable of carrying executable document content', () {
      for (final hostile in [
        'text/html',
        'image/svg+xml',
        'IMAGE/SVG',
        'image/png;charset=UTF-8',
        'image/png;base64,Zm9v',
      ]) {
        final actual = ImageTransformer.encodeToBase64Uri({
          'bytesData': <int>[1, 2, 3],
          'mimeType': hostile,
        });

        expect(actual, 'data:application/octet-stream;base64,AQID', reason: hostile);
      }
    });

    test('keeps canonical PNG and normalizes common jpg aliases', () {
      expect(
        ImageTransformer.encodeToBase64Uri({'bytesData': <int>[1], 'mimeType': 'IMAGE/PNG'}),
        'data:image/png;base64,AQ==',
      );
      expect(
        ImageTransformer.encodeToBase64Uri({'bytesData': <int>[1], 'mimeType': 'image/jpg'}),
        'data:image/jpeg;base64,AQ==',
      );
    });
  });
}
