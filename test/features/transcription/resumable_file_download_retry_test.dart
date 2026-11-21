import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_download_http_client_factory.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/resumable_file_download.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';

/// A mid-transfer failure must cost only the bytes in flight: the retry
/// continues the part file with a byte range instead of starting over.
void main() {
  final payload = List<int>.generate(64, (index) => index);

  late HttpServer server;
  late List<String?> ranges;
  // How many bytes each successive request sends before the connection is
  // cut; null serves the request normally.
  late List<int?> cutAfter;
  late int statusOverride;
  late Directory temp;
  late File part;
  late AsrTransferCancellation cancellation;

  Uri uri() => Uri.parse('http://127.0.0.1:${server.port}/model.bin');

  ResumableFileDownload downloader({int retries = 3}) {
    return ResumableFileDownload(
      clientFactory: AsrDownloadHttpClientFactory(
        environment: () => const {},
        systemProxyLookup: () async => null,
      ),
      timeout: const Duration(seconds: 5),
      transientRetries: retries,
      retryDelay: Duration.zero,
    );
  }

  setUp(() async {
    ranges = [];
    cutAfter = [];
    statusOverride = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      final index = ranges.length;
      ranges.add(range);
      final response = request.response;
      if (statusOverride != 0) {
        response.statusCode = statusOverride;
        await response.close();
        return;
      }
      final offset = range == null
          ? 0
          : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      if (offset > 0) {
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $offset-${payload.length - 1}/${payload.length}',
        );
      }
      response.contentLength = payload.length - offset;
      final cut = index < cutAfter.length ? cutAfter[index] : null;
      if (cut == null) {
        response.add(payload.sublist(offset));
        await response.close();
        return;
      }
      final socket = await response.detachSocket();
      if (cut > 0) {
        socket.add(payload.sublist(offset, offset + cut));
        await socket.flush();
      }
      socket.destroy();
    });
    temp = await Directory.systemTemp.createTemp('resumable_retry_test');
    part = File('${temp.path}${Platform.pathSeparator}model.bin.part');
    cancellation = AsrTransferCancellation();
  });

  tearDown(() async {
    await server.close(force: true);
    await temp.delete(recursive: true);
  });

  test('a dropped connection continues from the kept bytes', () async {
    cutAfter = [24];
    final retries = <DownloadRetry>[];

    await downloader().fetch(
      uri(),
      part,
      cancellation: cancellation,
      expectedBytes: payload.length,
      onRetry: retries.add,
    );

    expect(ranges, [null, 'bytes=24-']);
    expect(await part.readAsBytes(), payload);
    expect(retries, hasLength(1));
    expect(retries.single.keptBytes, 24);
    expect(retries.single.totalBytes, payload.length);
    expect(retries.single.attempt, 1);
  });

  test('every attempt that adds bytes earns another retry', () async {
    cutAfter = [10, 10, 10, 10, 10];

    await downloader(retries: 1).fetch(
      uri(),
      part,
      cancellation: cancellation,
      expectedBytes: payload.length,
    );

    expect(ranges, [
      null,
      'bytes=10-',
      'bytes=20-',
      'bytes=30-',
      'bytes=40-',
      'bytes=50-',
    ]);
    expect(await part.readAsBytes(), payload);
  });

  test('gives up after the allowed failures without progress', () async {
    cutAfter = [16, 0, 0, 0, 0];
    final retries = <DownloadRetry>[];

    await expectLater(
      downloader(retries: 2).fetch(
        uri(),
        part,
        cancellation: cancellation,
        expectedBytes: payload.length,
        onRetry: retries.add,
      ),
      throwsA(
        predicate<Object>(ResumableFileDownload.isTransientFailure),
      ),
    );

    // The first failure made progress and counts as one in a row; the
    // retry that added nothing is the second, and the next one stops.
    expect(ranges, [null, 'bytes=16-', 'bytes=16-']);
    expect(retries, hasLength(2));
    expect(await part.length(), 16, reason: 'the break point is kept');
  });

  test('without retries the first transport failure is reported', () async {
    cutAfter = [8];

    await expectLater(
      downloader(retries: 0).fetch(
        uri(),
        part,
        cancellation: cancellation,
        expectedBytes: payload.length,
      ),
      throwsA(predicate<Object>(ResumableFileDownload.isTransientFailure)),
    );

    expect(ranges, [null]);
    expect(await part.length(), 8);
  });

  test('HTTP errors are left to the caller to handle', () async {
    statusOverride = HttpStatus.serviceUnavailable;

    final error = await _downloadFailure(
      downloader().fetch(uri(), part, cancellation: cancellation),
    );

    expect(error.failure, DownloadFailure.httpStatus);
    expect(ranges, hasLength(1));
  });

  test('a retried fresh download keeps its own bytes', () async {
    cutAfter = [12];
    await part.writeAsBytes(List<int>.filled(30, 0xee));

    await downloader().fetch(
      uri(),
      part,
      cancellation: cancellation,
      resume: false,
    );

    // The stale part file is dropped once; the retry continues the new one.
    expect(ranges, [null, 'bytes=12-']);
    expect(await part.readAsBytes(), payload);
  });

  test('a cancel while waiting to retry stops the download', () async {
    cutAfter = [8];
    final slow = ResumableFileDownload(
      clientFactory: AsrDownloadHttpClientFactory(
        environment: () => const {},
        systemProxyLookup: () async => null,
      ),
      timeout: const Duration(seconds: 5),
      transientRetries: 3,
      retryDelay: const Duration(seconds: 30),
    );

    final future = slow.fetch(
      uri(),
      part,
      cancellation: cancellation,
      expectedBytes: payload.length,
      onRetry: (_) => Timer(
        const Duration(milliseconds: 50),
        cancellation.cancel,
      ),
    );

    await expectLater(
      future,
      throwsA(
        isA<TranscriptionException>().having(
          (error) => error.kind,
          'kind',
          TranscriptionFailureKind.cancelled,
        ),
      ),
    );
    expect(ranges, [null]);
    expect(await part.length(), 8);
  });

  test('classifies transport failures as transient', () {
    expect(
      ResumableFileDownload.isTransientFailure(
        const SocketException('Connection reset by peer'),
      ),
      isTrue,
    );
    expect(
      ResumableFileDownload.isTransientFailure(
        const HttpException('Connection closed while receiving data'),
      ),
      isTrue,
    );
    expect(
      ResumableFileDownload.isTransientFailure(TimeoutException('stalled')),
      isTrue,
    );
    expect(
      ResumableFileDownload.isTransientFailure(
        const FileSystemException('No space left on device'),
      ),
      isFalse,
    );
    expect(
      ResumableFileDownload.isTransientFailure(const FormatException('x')),
      isFalse,
    );
  });

  test('describes a retry with the kept bytes', () {
    final message = describeDownloadRetry(
      'Elysium Player 识别引擎',
      DownloadRetry(
        attempt: 2,
        maxConsecutiveAttempts: 3,
        keptBytes: 1100 * 1024 * 1024,
        totalBytes: 1223455711,
        delay: const Duration(seconds: 4),
        error: const SocketException('reset'),
      ),
    );

    expect(message, contains('已保留 1.07 GB / 1.14 GB'));
    expect(message, contains('4 秒后从断点继续下载'));
    expect(message, contains('第 2 次重连'));
    expect(formatDownloadBytes(512 * 1024), '512 KB');
    expect(formatDownloadBytes(5 * 1024 * 1024), '5.0 MB');
    expect(formatDownloadBytes(10), '10 B');
  });
}

Future<ResumableDownloadException> _downloadFailure(Future<void> future) async {
  try {
    await future;
  } on ResumableDownloadException catch (error) {
    return error;
  }
  fail('expected a ResumableDownloadException');
}
