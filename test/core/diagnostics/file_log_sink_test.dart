import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/diagnostics/file_log_sink.dart';
import 'package:lyric_forge_ktv/core/diagnostics/log_record.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('file_log_sink_test');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  LogRecord record(int index, {LogLevel level = LogLevel.info}) => LogRecord(
    time: DateTime.utc(2026, 11, 15).add(Duration(seconds: index)),
    level: level,
    tag: 'test',
    message: 'line $index ${'x' * 40}',
  );

  FileLogSink sink({int maxBytes = 64 * 1024}) => FileLogSink(
    directory: () async => Directory('${root.path}/diagnostics'),
    maxBytes: maxBytes,
    flushDelay: const Duration(milliseconds: 10),
  );

  test('writes JSON lines and reads them back in order', () async {
    final log = sink();
    for (var i = 0; i < 5; i++) {
      log.write(record(i));
    }
    await log.flush();

    final file = File('${root.path}/diagnostics/${FileLogSink.fileName}');
    final lines = await file.readAsLines();
    expect(lines, hasLength(5));
    expect(jsonDecode(lines.first), containsPair('g', 'test'));

    final recent = await log.readRecent(limit: 3);
    expect(recent.map((item) => item.message.split(' ')[1]), ['2', '3', '4']);
  });

  test('flushes on the timer without an explicit flush', () async {
    final log = sink();
    log.write(record(1));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final file = File('${root.path}/diagnostics/${FileLogSink.fileName}');
    expect(await file.exists(), isTrue);
  });

  test('rotates once the file passes maxBytes and keeps both files', () async {
    final log = sink(maxBytes: 2048);
    for (var i = 0; i < 60; i++) {
      log.write(record(i));
      // Flush per record so the size check runs repeatedly.
      await log.flush();
    }
    final current = File('${root.path}/diagnostics/${FileLogSink.fileName}');
    final rotated = File(
      '${root.path}/diagnostics/${FileLogSink.rotatedFileName}',
    );
    expect(await rotated.exists(), isTrue);
    expect(await current.length(), lessThanOrEqualTo(2048));
    expect(await rotated.length(), lessThanOrEqualTo(2048));

    final recent = await log.readRecent(limit: 1000);
    // Oldest first, newest last, with no duplicates across the two files.
    expect(recent.last.message, startsWith('line 59 '));
    final indexes = [
      for (final item in recent) int.parse(item.message.split(' ')[1]),
    ];
    expect(indexes, orderedEquals([...indexes]..sort()));
    expect(indexes.toSet(), hasLength(indexes.length));
    expect(await log.sizeInBytes(), greaterThan(1024));
  });

  test('skips malformed and torn lines', () async {
    final directory = Directory('${root.path}/diagnostics');
    await directory.create(recursive: true);
    final file = File('${directory.path}/${FileLogSink.fileName}');
    await file.writeAsString(
      '${jsonEncode(record(1).toJson())}\n'
      'not json\n'
      '{"t":"2026-11-15","l":"info"}\n'
      '\n'
      '${jsonEncode(record(2).toJson())}\n'
      '{"t":"2026-11-15T00:00:03Z","l":"in',
    );
    final records = await sink().readRecent();
    expect(records.map((item) => item.message.split(' ')[1]), ['1', '2']);
  });

  test('clear removes both files and resets the size', () async {
    final log = sink(maxBytes: 2048);
    for (var i = 0; i < 40; i++) {
      log.write(record(i));
      await log.flush();
    }
    await log.clear();
    expect(await log.sizeInBytes(), 0);
    expect(await log.readRecent(), isEmpty);

    log.write(record(99, level: LogLevel.error));
    await log.flush();
    expect((await log.readRecent()).single.level, LogLevel.error);
  });

  test('an unwritable directory is swallowed', () async {
    final blocker = File('${root.path}/blocker');
    await blocker.writeAsString('file, not a directory');
    final log = FileLogSink(
      directory: () async => Directory('${blocker.path}/diagnostics'),
      flushDelay: const Duration(milliseconds: 10),
    );
    log.write(record(1, level: LogLevel.error));
    await expectLater(log.flush(), completes);
  });
}
