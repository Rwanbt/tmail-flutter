import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/data/constants/constant.dart';
import 'package:core/data/network/download/download_client.dart';
import 'package:core/data/network/download/downloaded_response.dart';
import 'package:core/domain/exceptions/download_file_exception.dart';
import 'package:core/utils/app_logger.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:universal_html/html.dart' as html;

class DownloadManager {
  final DownloadClient _downloadClient;

  DownloadManager(this._downloadClient);

  /// Attachment filenames are untrusted JMAP/email metadata. Never let
  /// them escape [directoryToSave], even when the server returns Windows
  /// separators on a Unix host (or vice versa).
  static String validateDownloadFilename(String filename) {
    if (filename.isEmpty ||
        filename.length > 255 ||
        filename == '.' ||
        filename == '..' ||
        filename != filename.trim() ||
        RegExp(r'[/\\\x00-\x1f\x7f]').hasMatch(filename) ||
        RegExp(r'[. ]$').hasMatch(filename) ||
        RegExp(r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\.|$)',
                caseSensitive: false)
            .hasMatch(filename)) {
      throw ArgumentError.value(
        filename,
        'filename',
        'Unsafe attachment filename',
      );
    }
    return filename;
  }

  Future<DownloadedResponse> downloadFile(
      String downloadUrl,
      Future<Directory> directoryToSave,
      String filename,
      String basicAuth,
      {CancelToken? cancelToken,
      int? expectedSize}
  ) async {
    // Check before starting the HTTP request or opening any output file.
    final safeFilename = validateDownloadFilename(filename);
    final streamController = StreamController<DownloadedResponse>();

    try {
      await Future.wait([
        _downloadClient.downloadFile(downloadUrl, basicAuth, cancelToken),
        directoryToSave
      ]).then((values) async {
        final response = (values[0] as ResponseBody);
        final mediaType = _extractMediaTypeFromResponse(response);
        final fileStream = response.stream;
        // The number of bytes actually written to the file: compared with the
        // size the server announced, so an interrupted transfer cannot be
        // mistaken for a complete attachment.
        var writtenSize = 0;
        // Two different emails (or accounts) can contain an attachment with
        // the same name. Give each download its own directory so a later
        // FileMode.write cannot replace an earlier private attachment.
        final isolatedDirectory = await (values[1] as Directory)
            .createTemp('tmail-attachment-');
        final tempFilePath =
            '${isolatedDirectory.absolute.path}/$safeFilename';

        final file = File(tempFilePath);
        late RandomAccessFile randomAccessFile;
        try {
          file.createSync();
          randomAccessFile = file.openSync(mode: FileMode.write);
        } catch (_) {
          await isolatedDirectory.delete(recursive: true);
          rethrow;
        }
        late StreamSubscription subscription;

        subscription = fileStream
            .takeWhile((_) => cancelToken == null || !cancelToken.isCancelled)
            .listen((data) {
              subscription.pause();
              randomAccessFile.writeFrom(data).then((accessFile) {
                randomAccessFile = accessFile;
                writtenSize += data.length;
                subscription.resume();
                // onDone is responsible for one cancellation result and
                // cleanup; never emit a second error from this callback.
              }).catchError((error) async {
                await subscription.cancel();
                await randomAccessFile.close();
                await isolatedDirectory.delete(recursive: true);
                streamController.sink.addError(CommonDownloadFileException(error.toString()));
                await streamController.close();
              });
        }, onDone: () async {
          await randomAccessFile.close();
          if (cancelToken != null && cancelToken.isCancelled) {
            if (await file.exists()) await file.delete();
            await isolatedDirectory.delete();
            streamController.sink.addError(CancelDownloadFileException(cancelToken.cancelError?.message));
          } else if (expectedSize != null && writtenSize != expectedSize) {
            // The transfer ended before the announced size was reached: the
            // file on disk is truncated, it must never be given to the caller.
            if (await file.exists()) await file.delete();
            await isolatedDirectory.delete(recursive: true);
            streamController.sink.addError(IncompleteDownloadFileException(
              'The attachment was truncated: $writtenSize bytes received '
              'instead of $expectedSize',
            ));
          } else {
            streamController.sink.add(DownloadedResponse(tempFilePath, mediaType: mediaType));
          }
          await streamController.close();
        }, onError: (error) async {
          await randomAccessFile.close();
          await file.delete();
          await isolatedDirectory.delete();
          streamController.sink.addError(CommonDownloadFileException(error.toString()));
          await streamController.close();
        });
      });
    } catch(exception) {
      if (cancelToken != null && cancelToken.isCancelled) {
        streamController.sink.addError(CancelDownloadFileException(cancelToken.cancelError?.message));
        await streamController.close();
        return streamController.stream.first;
      } else {
        rethrow;
      }
    }
    return streamController.stream.first;
  }

  void createAnchorElementDownloadFileWeb(
      Uint8List bytes,
      String filename
  ) {
    try {
      final mimeType = _detectMimeType(filename, headerBytes: bytes);
      final blob = html.Blob([bytes], mimeType);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.document.createElement('a') as html.AnchorElement
        ..href = url
        ..style.display = 'none'
        ..download = filename;
      html.document.body?.children.add(anchor);

      anchor.click();

      html.document.body?.children.remove(anchor);
      html.Url.revokeObjectUrl(url);
    } catch (exception) {
      log('DownloadManager::createAnchorElementDownloadFileWeb(): ERROR: $exception');
      rethrow;
    }
  }

  String _detectMimeType(String fileName, {Uint8List? headerBytes}) {
    try {
      return lookupMimeType(fileName, headerBytes: headerBytes) ?? Constant.octetStreamMimeType;
    } catch (exception) {
      log('DownloadManager::_detectMimeType(): ERROR: $exception');
      return Constant.octetStreamMimeType;
    }
  }

  MediaType? _extractMediaTypeFromResponse(ResponseBody responseBody) {
    try {
      final contentType = responseBody.headers[Headers.contentTypeHeader];
      return MediaType.parse(contentType!.first);
    } catch (e) {
      logWarning('DownloadManager::_extractMediaTypeFromResponse(): $e');
      return null;
    }
  }
}
