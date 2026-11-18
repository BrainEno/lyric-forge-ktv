import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_download_http_client_factory.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/resumable_file_download.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';

void main() {
  final payload = List<int>.generate(64, (index) => index);

  late HttpServer server;
  late _Behaviour behaviour;
  late List<String?> ranges;
  late Directory temp;
  late File part;
  late ResumableFileDownload download;
  late AsrTransferCancellation cancellation;

  Uri uri() => Uri.parse('http://127.0.0.1:${server.port}/model.bin');

  setUp(() async {
    behaviour = _Behaviour.honourRange;
    ranges = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      ranges.add(range);
      final response = request.response;
      final offset = range == null
          ? 0
          : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      switch (behaviour) {
        case _Behaviour.notFound:
          response.statusCode = HttpStatus.notFound;
        case _Behaviour.ignoreRange:
          response.contentLength = payload.length;
          response.add(payload);
        case _Behaviour.wrongRangeStart:
          response.statusCode = HttpStatus.partialContent;
          response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes 0-${payload.length - 1}/${payload.length}',
          );
          response.add(payload);
        case _Behaviour.honourRange:
          if (offset > 0) {
            response.statusCode = HttpStatus.partialContent;
            response.headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes $offset-${payload.length - 1}/${payload.length}',
            );
          }
          response.contentLength = payload.length - offset;
          response.add(payload.sublist(offset));
      }
      await response.close();
    });
    temp = await Directory.systemTemp.createTemp('resumable_download_test');
    part = File('${temp.path}${Platform.pathSeparator}model.bin.part');
    download = ResumableFileDownload(
      clientFactory: AsrDownloadHttpClientFactory(
        environment: () => const {},
        systemProxyLookup: () async => null,
      ),
      timeout: const Duration(seconds: 5),
    );
    cancellation = AsrTransferCancellation();
  });

  tearDown(() async {
    await server.close(force: true);
    await temp.delete(recursive: true);
  });

  Future<ResumableDownloadException> failure(Future<void> future) async {
    try {
      await future;
    } on ResumableDownloadException catch (error) {
      return error;
    }
    fail('expected a ResumableDownloadException');
  }

  test('downloads into the part file and reports the full size', () async {
    final samples = <DownloadProgress>[];

    await download.fetch(
      uri(),
      part,
      cancellation: cancellation,
      onProgress: samples.add,
    );

    expect(await part.readAsBytes(), payload);
    expect(ranges, [null]);
    expect(samples.last.receivedBytes, payload.length);
    expect(samples.last.totalBytes, payload.length);
    expect(samples.last.fraction, 1.0);
  });

  test('continues a kept part file with a byte range', () async {
    await part.writeAsBytes(payload.sublist(0, 20));

    await download.fetch(uri(), part, cancellation: cancellation);

    expect(ranges, ['bytes=20-']);
    expect(await part.readAsBytes(), payload);
  });

  test('restarts when the server ignores the range', () async {
    behaviour = _Behaviour.ignoreRange;
    await part.writeAsBytes(List<int>.filled(20, 0xff));

    await download.fetch(uri(), part, cancellation: cancellation);

    expect(ranges, ['bytes=20-']);
    expect(await part.readAsBytes(), payload);
  });

  test('rejects a 206 that does not continue the part file', () async {
    behaviour = _Behaviour.wrongRangeStart;
    await part.writeAsBytes(payload.sublist(0, 20));

    final error = await failure(
      download.fetch(uri(), part, cancellation: cancellation),
    );

    expect(error.failure, DownloadFailure.inconsistentResume);
    expect(error.contentRange, 'bytes 0-63/64');
    expect(await part.exists(), isFalse);
  });

  test('keeps the part file on an HTTP error', () async {
    behaviour = _Behaviour.notFound;
    await part.writeAsBytes(payload.sublist(0, 20));

    final error = await failure(
      download.fetch(uri(), part, cancellation: cancellation),
    );

    expect(error.failure, DownloadFailure.httpStatus);
    expect(error.statusCode, HttpStatus.notFound);
    expect(await part.length(), 20);
  });

  test('a body shorter than the expected size stays resumable', () async {
    final error = await failure(
      download.fetch(
        uri(),
        part,
        cancellation: cancellation,
        expectedBytes: payload.length + 10,
      ),
    );

    expect(error.failure, DownloadFailure.incomplete);
    expect(error.sizeDetails, 'expected=74, actual=64');
    expect(await part.length(), payload.length);
  });

  test('a body longer than the expected size is discarded', () async {
    final error = await failure(
      download.fetch(
        uri(),
        part,
        cancellation: cancellation,
        expectedBytes: payload.length - 4,
      ),
    );

    expect(error.failure, DownloadFailure.oversized);
    expect(await part.exists(), isFalse);
  });

  test('a part file longer than the expected size is not resumed', () async {
    await part.writeAsBytes(List<int>.filled(payload.length + 1, 0));

    await download.fetch(
      uri(),
      part,
      cancellation: cancellation,
      expectedBytes: payload.length,
    );

    expect(ranges, [null]);
    expect(await part.readAsBytes(), payload);
  });

  test('without resume a kept part file is replaced', () async {
    await part.writeAsBytes(payload.sublist(0, 20));

    await download.fetch(uri(), part, cancellation: cancellation, resume: false);

    expect(ranges, [null]);
    expect(await part.readAsBytes(), payload);
  });

  test('a cancel during the transfer throws the install cancellation', () async {
    await expectLater(
      download.fetch(
        uri(),
        part,
        cancellation: cancellation,
        onProgress: (_) => cancellation.cancel(),
      ),
      throwsA(
        isA<TranscriptionException>().having(
          (error) => error.kind,
          'kind',
          TranscriptionFailureKind.cancelled,
        ),
      ),
    );
  });

  test('promote replaces the target with the finished part file', () async {
    final target = File('${temp.path}${Platform.pathSeparator}model.bin');
    await target.writeAsString('old');
    await part.writeAsBytes(payload);

    expect(ResumableFileDownload.partFileFor(target).path, part.path);
    await ResumableFileDownload.promote(part, target);

    expect(await target.readAsBytes(), payload);
    expect(await part.exists(), isFalse);
  });

  test('reset clears an earlier cancel', () {
    cancellation.cancel();
    expect(cancellation.throwIfRequested, throwsA(isA<TranscriptionException>()));

    cancellation.reset();
    expect(cancellation.isRequested, isFalse);
    cancellation.throwIfRequested();
  });
}

enum _Behaviour { honourRange, ignoreRange, wrongRangeStart, notFound }
