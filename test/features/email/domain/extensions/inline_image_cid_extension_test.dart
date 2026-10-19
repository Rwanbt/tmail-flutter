import 'package:flutter_test/flutter_test.dart';
import 'package:jmap_dart_client/jmap/core/id.dart';
import 'package:model/email/attachment.dart';
import 'package:tmail_ui_user/features/email/domain/extensions/inline_image_cid_extension.dart';

void main() {
  final uploaded = Attachment(blobId: Id('blob-1'), cid: 'img-1');
  final inlineAttachments = {'img-1': uploaded};

  group('InlineImageCidExtension::resolveUploadedImage', () {
    test('points a matched base64 image at its cid and drops the id', () {
      final attributes = <Object, String>{'id': 'cid:img-1', 'src': 'data:image/png;base64,AAAA'};

      expect(inlineAttachments.resolveUploadedImage(attributes), uploaded);
      expect(attributes, {'src': 'cid:img-1'});
    });

    test('leaves the tag untouched when the cid has no upload', () {
      final attributes = <Object, String>{'id': 'cid:unknown', 'src': 'data:image/png;base64,AAAA'};

      expect(inlineAttachments.resolveUploadedImage(attributes), isNull);
      expect(attributes['id'], 'cid:unknown');
    });

    test('ignores a tag without a cid id', () {
      final attributes = <Object, String>{'id': 'logo', 'src': 'data:image/png;base64,AAAA'};

      expect(inlineAttachments.resolveUploadedImage(attributes), isNull);
    });

    test('resolves an encoded Content-ID with an uppercase CID scheme', () {
      final image = Attachment(blobId: Id('blob-encoded'), cid: 'photo@example.org');
      final attributes = <Object, String>{
        'id': 'CID:photo%40example.org',
        'src': 'data:image/png;base64,AAAA',
      };

      expect({'photo@example.org': image}.resolveUploadedImage(attributes), image);
      expect(attributes, {'src': 'cid:photo@example.org'});
    });

    test('does not rewrite an uploaded image with an invalid CID escape', () {
      final attributes = <Object, String>{
        'id': 'cid:img%ZZ-1',
        'src': 'data:image/png;base64,AAAA',
      };

      expect(inlineAttachments.resolveUploadedImage(attributes), isNull);
      expect(attributes, {
        'id': 'cid:img%ZZ-1',
        'src': 'data:image/png;base64,AAAA',
      });
    });

    test('keeps a literal percent in a MIME Content-ID when its URL is encoded', () {
      final image = Attachment(blobId: Id('blob-percent'), cid: '<photo%ZZ@example.org>');
      final attributes = <Object, String>{
        'id': 'cid:photo%25ZZ@example.org',
        'src': 'data:image/png;base64,AAAA',
      };

      expect({'upload-1': image}.resolveUploadedImage(attributes), image);
      expect(attributes, {'src': 'cid:photo%25ZZ@example.org'});
    });
  });

  group('InlineImageCidExtension::replaceUploadedImagesWithCid', () {
    test('rewrites an uploaded base64 image to cid and returns its attachment', () {
      final (html, inlineImages) = inlineAttachments.replaceUploadedImagesWithCid(
        '<p>hi<img id="cid:img-1" src="data:image/png;base64,AAAA"></p>',
      );

      expect(html, '<p>hi<img src="cid:img-1"></p>');
      expect(inlineImages, {uploaded});
    });

    test('returns the attachment of an image already referenced by cid', () {
      const content = '<p><img src="cid:img-1"></p>';

      final (html, inlineImages) = inlineAttachments.replaceUploadedImagesWithCid(content);

      expect(html, content);
      expect(inlineImages, {uploaded});
    });

    test('recovers inline images with encoded, uppercase and bracketed Content-IDs after reload', () {
      final image = Attachment(blobId: Id('blob-encoded'), cid: '<photo@example.org>');
      final attachments = {'<photo@example.org>': image};
      const content = '<p><img src="CID:photo%40example.org"></p>';

      final (html, inlineImages) = attachments.replaceUploadedImagesWithCid(content);

      expect(html, content);
      expect(inlineImages, {image});
    });

    test('does not attach unrelated images or malformed CID references', () {
      const content = '<img src="https://example.org/cid:photo%40example.org">'
          '<img src="cid:photo%ZZexample.org">';
      final image = Attachment(blobId: Id('blob-encoded'), cid: 'photo@example.org');
      final (html, inlineImages) =
          {'photo@example.org': image}.replaceUploadedImagesWithCid(content);

      expect(html, content);
      expect(inlineImages, isEmpty);
    });

    test('ignores malformed UTF-8 escapes while preserving valid inline images', () {
      const content = '<img src="cid:%E9">'
          '<img src="cid:img-1">'
          '<img id="cid:%ZZ" src="data:image/png;base64,AAAA">';

      final (html, inlineImages) = inlineAttachments.replaceUploadedImagesWithCid(content);

      expect(html, content);
      expect(inlineImages, {uploaded});
    });

    test('recovers a CID containing a literal percent after draft reload', () {
      final image = Attachment(blobId: Id('blob-percent'), cid: 'photo%ZZ@example.org');
      const content = '<img src="cid:photo%25ZZ@example.org">';

      final (html, inlineImages) =
          {'upload-1': image}.replaceUploadedImagesWithCid(content);

      expect(html, content);
      expect(inlineImages, {image});
    });

    test('keeps an image without an upload in base64', () {
      const content = '<p><img src="data:image/png;base64,BBBB"></p>';

      final (html, inlineImages) = inlineAttachments.replaceUploadedImagesWithCid(content);

      expect(html, content);
      expect(inlineImages, isEmpty);
    });

    test('drops an upload whose image was removed from the content', () {
      final (html, inlineImages) = inlineAttachments.replaceUploadedImagesWithCid('<p>text</p>');

      expect(html, '<p>text</p>');
      expect(inlineImages, isEmpty);
    });
  });
}
