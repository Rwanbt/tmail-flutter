import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/data/network/download/download_client.dart';
import 'package:core/data/network/download/download_manager.dart';
import 'package:core/domain/exceptions/download_file_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryDownloadClient implements DownloadClient {
  int calls = 0;

  @override
  Future<ResponseBody> downloadFile(
    String url,
    String basicAuth,
    CancelToken? cancelToken,
  ) async {
    calls += 1;
    return ResponseBody(
      Stream.value(Uint8List.fromList([calls, 2, 3])),
      200,
      headers: {Headers.contentTypeHeader: ['application/octet-stream']},
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  group('JMAP attachment download destination security', () {
    for (final hostileName in [
      '../outside.pdf',
      r'..\outside.pdf',
      '/etc/passwd',
      r'C:\Users\Public\outside.pdf',
      './inside.pdf',
      'nested/child.pdf',
      'nested\\child.pdf',
      '..',
      '.',
      '',
      'invoice\u0000.pdf',
      'invoice\n.pdf',
      'invoice.pdf ',
      'CON',
      'aux.txt',
      'COM1.txt',
      List.filled(256, 'x').join(),
    ]) {
      test('fails closed for untrusted filename $hostileName', () {
        expect(
          () => DownloadManager.validateDownloadFilename(hostileName),
          throwsArgumentError,
        );
      });
    }

    for (final safeName in [
      'invoice-2026.pdf',
      'rapport fiscal 2026.pdf',
      'résumé 📄.pdf',
      'notes.txt',
      '.hidden-attachment',
      List.filled(255, 'x').join(),
    ]) {
      test('preserves legitimate attachment filename $safeName', () {
        expect(
          DownloadManager.validateDownloadFilename(safeName),
          safeName,
        );
      });
    }

    test('rejects traversal before reading or requesting a private attachment', () async {
      final directory = await Directory.systemTemp.createTemp('tmail-safe-');
      addTearDown(() => directory.delete(recursive: true));
      final client = _MemoryDownloadClient();
      final manager = DownloadManager(client);

      await expectLater(
        manager.downloadFile(
          'https://jmap.example.invalid/download',
          Future.value(directory),
          '../outside.pdf',
          'synthetic-auth',
        ),
        throwsArgumentError,
      );
      expect(client.calls, 0, reason: 'hostile names must not trigger a JMAP request');
    });

    test('writes a safe attachment only under its requested temporary directory', () async {
      final directory = await Directory.systemTemp.createTemp('tmail-safe-');
      addTearDown(() => directory.delete(recursive: true));
      final client = _MemoryDownloadClient();
      final result = await DownloadManager(client).downloadFile(
        'https://jmap.example.invalid/download',
        Future.value(directory),
        'invoice.pdf',
        'synthetic-auth',
      );

      expect(result.filePath, '${directory.absolute.path}/invoice.pdf');
      expect(await File(result.filePath).readAsBytes(), [1, 2, 3]);
      expect(client.calls, 1);
    });

    test('downloads with the same name preserve each private attachment', () async {
      final directory = await Directory.systemTemp.createTemp('tmail-safe-');
      addTearDown(() => directory.delete(recursive: true));
      final client = _MemoryDownloadClient();
      final manager = DownloadManager(client);

      final first = await manager.downloadFile(
        'https://jmap.example.invalid/account-one',
        Future.value(directory),
        'invoice.pdf',
        'account-one-auth',
      );
      final second = await manager.downloadFile(
        'https://jmap.example.invalid/account-two',
        Future.value(directory),
        'invoice.pdf',
        'account-two-auth',
      );

      expect(first.filePath, isNot(second.filePath));
      expect(await File(first.filePath).readAsBytes(), [1, 2, 3]);
      expect(await File(second.filePath).readAsBytes(), [2, 2, 3]);
      expect(client.calls, 2);
    });

    test('cancellation cannot retain a truncated private attachment on disk', () async {
      final directory = await Directory.systemTemp.createTemp('tmail-safe-');
      addTearDown(() => directory.delete(recursive: true));
      final token = CancelToken()..cancel('synthetic cancel');
      final manager = DownloadManager(_MemoryDownloadClient());

      await expectLater(
        manager.downloadFile(
          'https://jmap.example.invalid/download',
          Future.value(directory),
          'sensitive.pdf',
          'synthetic-auth',
          cancelToken: token,
        ),
        throwsA(isA<CancelDownloadFileException>()),
      );
      expect(
        await File('${directory.absolute.path}/sensitive.pdf').exists(),
        isFalse,
      );
    });
  });
}
