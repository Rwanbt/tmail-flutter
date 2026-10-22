@TestOn('vm')

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/data/network/download/download_client.dart';
import 'package:core/data/network/download/download_manager.dart';
import 'package:core/domain/exceptions/download_file_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// A download client that answers with a body of [bytes] and announces
/// [announcedSize] bytes: what an interrupted transfer looks like to the
/// download manager (the connection ends before the whole blob arrived).
class _MemoryDownloadClient implements DownloadClient {
  _MemoryDownloadClient(
    this.bytes, {
    this.announcedSize,
  });

  final List<int> bytes;
  final int? announcedSize;
  int calls = 0;

  @override
  Future<ResponseBody> downloadFile(
    String url,
    String basicAuth,
    CancelToken? cancelToken,
  ) async {
    calls += 1;
    return ResponseBody(
      Stream.value(Uint8List.fromList(bytes)),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/octet-stream'],
        if (announcedSize != null)
          Headers.contentLengthHeader: ['$announcedSize'],
      },
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  group('JMAP attachment download integrity', () {
    test('refuses a truncated attachment instead of saving it', () async {
      final directory =
          await Directory.systemTemp.createTemp('tmail-truncated-');
      addTearDown(() => directory.delete(recursive: true));
      final client = _MemoryDownloadClient([1, 2, 3], announcedSize: 10);

      await expectLater(
        DownloadManager(client).downloadFile(
          'https://jmap.example.invalid/download',
          Future.value(directory),
          'invoice.pdf',
          'synthetic-auth',
          expectedSize: 10,
        ),
        throwsA(isA<IncompleteDownloadFileException>()),
      );

      expect(
        await directory.list().isEmpty,
        isTrue,
        reason: 'a truncated attachment must not be left on disk',
      );
    });

    test('refuses an attachment that does not match the announced size',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('tmail-oversized-');
      addTearDown(() => directory.delete(recursive: true));
      final client = _MemoryDownloadClient([1, 2, 3, 4], announcedSize: 3);

      await expectLater(
        DownloadManager(client).downloadFile(
          'https://jmap.example.invalid/download',
          Future.value(directory),
          'invoice.pdf',
          'synthetic-auth',
          expectedSize: 3,
        ),
        throwsA(isA<IncompleteDownloadFileException>()),
      );

      expect(
        await directory.list().isEmpty,
        isTrue,
        reason: 'an attachment of an unexpected size must not be kept',
      );
    });

    test('keeps an attachment whose size matches the announced one',
        () async {
      final directory = await Directory.systemTemp.createTemp('tmail-complete-');
      addTearDown(() => directory.delete(recursive: true));
      final client = _MemoryDownloadClient([1, 2, 3], announcedSize: 3);

      final result = await DownloadManager(client).downloadFile(
        'https://jmap.example.invalid/download',
        Future.value(directory),
        'invoice.pdf',
        'synthetic-auth',
        expectedSize: 3,
      );

      expect(await File(result.filePath).readAsBytes(), [1, 2, 3]);
      expect(client.calls, 1);
    });

    test('keeps an attachment when the server announces no size', () async {
      final directory = await Directory.systemTemp.createTemp('tmail-unknown-');
      addTearDown(() => directory.delete(recursive: true));
      final client = _MemoryDownloadClient([1, 2, 3]);

      final result = await DownloadManager(client).downloadFile(
        'https://jmap.example.invalid/download',
        Future.value(directory),
        'invoice.pdf',
        'synthetic-auth',
      );

      expect(await File(result.filePath).readAsBytes(), [1, 2, 3]);
    });
  });
}
