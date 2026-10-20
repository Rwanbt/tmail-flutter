import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:model/email/attachment.dart';

const String inlineImageCidPrefix = 'cid:';

/// Data URL schemes, media types and the base64 marker are case-insensitive.
/// HTML pasted from other editors can legitimately use uppercase spellings.
bool isInlineBase64ImageDataUri(String? src) {
  final normalized = src?.trim().toLowerCase();
  return normalized != null &&
      normalized.startsWith('data:image/') &&
      normalized.contains(';base64,');
}

// Content-ID values may arrive bracketed from MIME or URL-encoded in an HTML
// cid: URL. The scheme is case-insensitive, while the identifier stays
// case-sensitive. Invalid percent escapes must never match another blob.
String? _normalizeContentId(String? value, {bool fromUrl = false}) {
  if (value == null) return null;
  var candidate = value.trim();
  if (fromUrl) {
    if (!candidate.toLowerCase().startsWith(inlineImageCidPrefix)) return null;
    candidate = candidate.substring(inlineImageCidPrefix.length).trim();
  }
  if (fromUrl) {
    try {
      candidate = Uri.decodeComponent(candidate).trim();
    } on FormatException {
      return null;
    } on ArgumentError {
      // Uri.decodeComponent throws ArgumentError for invalid percent escapes.
      return null;
    }
  }
  if (candidate.startsWith('<') && candidate.endsWith('>')) {
    candidate = candidate.substring(1, candidate.length - 1).trim();
  }
  return candidate.isEmpty ? null : candidate;
}

/// Synchronous inline-image matching, keyed by cid. The send path adds uploads
/// on top; the reload snapshot uses it alone because it cannot await.
extension InlineImageCidExtension on Map<String, Attachment> {
  Attachment? _findInlineAttachment(String cid) {
    final exactMatch = this[cid] ?? this['<$cid>'];
    if (exactMatch != null) return exactMatch;
    for (final entry in entries) {
      if (_normalizeContentId(entry.key) == cid ||
          _normalizeContentId(entry.value.cid) == cid) {
        return entry.value;
      }
    }
    return null;
  }

  /// Points an uploaded base64 `<img id="cid:X">` at `cid:X`.
  Attachment? resolveUploadedImage(Map<Object, String> imgAttributes) {
    final cid = _normalizeContentId(imgAttributes['id'], fromUrl: true);
    if (cid == null) return null;
    final attachment = _findInlineAttachment(cid);
    if (attachment == null) return null;

    // A literal '%' is legal in a MIME Content-ID but must be escaped in a URL.
    // Preserve '@' in the familiar cid:address form while escaping URI specials.
    final cidUrl = Uri.encodeComponent(cid).replaceAll('%40', '@');
    imgAttributes['src'] = '$inlineImageCidPrefix$cidUrl';
    imgAttributes.remove('id');
    return attachment;
  }

  /// Inline attachments already referenced by `<img src="cid:X">` tags.
  Iterable<Attachment> referencedBy(Iterable<Element> cidImgTags) => cidImgTags
      .map((img) => img.attributes['src'])
      .map((src) => _normalizeContentId(src, fromUrl: true))
      .nonNulls
      .map(_findInlineAttachment)
      .nonNulls;

  /// Rewrites uploaded base64 images to `cid:` and returns the inline
  /// attachments the HTML references. Unmatched base64 images stay inline.
  (String html, Set<Attachment> inlineImages) replaceUploadedImagesWithCid(
    String html,
  ) {
    final document = parse(html);
    final base64ImgTags = document.querySelectorAll('img[src]')
        .where((img) => isInlineBase64ImageDataUri(img.attributes['src']));
    final cidImgTags = document.querySelectorAll('img[src]');

    final inlineImages = {
      ...base64ImgTags.map((img) => resolveUploadedImage(img.attributes)).nonNulls,
      ...referencedBy(cidImgTags),
    };
    if (inlineImages.isEmpty) return (html, const {});

    return (document.body?.innerHtml ?? html, inlineImages);
  }
}
