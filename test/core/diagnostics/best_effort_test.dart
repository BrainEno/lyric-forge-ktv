import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/diagnostics/app_logger.dart';
import 'package:lyric_forge_ktv/core/diagnostics/best_effort.dart';
import 'package:lyric_forge_ktv/core/diagnostics/log_record.dart';

void main() {
  late MemoryLogSink sink;
  late AppLogger logger;

  setUp(() {
    sink = MemoryLogSink();
    logger = AppLogger(sinks: [sink], minimumLevel: LogLevel.debug);
  });

  test('a successful step logs nothing', () async {
    var ran = false;
    await bestEffort('test', '清理', () => ran = true, logger: logger);

    expect(ran, isTrue);
    expect(sink.records, isEmpty);
  });

  test('a failed housekeeping step is logged at debug without stack', () async {
    await bestEffort(
      'test.cleanup',
      '删除临时文件',
      () async => throw const FileSystemExceptionLike('gone'),
      logger: logger,
    );

    final record = sink.records.single;
    expect(record.level, LogLevel.debug);
    expect(record.tag, 'test.cleanup');
    expect(record.message, '删除临时文件 失败，已忽略');
    expect(record.error, contains('gone'));
    expect(record.stackTrace, isNull);
  });

  test('a failed degraded step is a warning with its stack', () async {
    await bestEffort(
      'test',
      '停止录音',
      () => throw StateError('busy'),
      impact: BestEffortImpact.degraded,
      logger: logger,
    );

    final record = sink.records.single;
    expect(record.level, LogLevel.warning);
    expect(record.error, contains('busy'));
    expect(record.stackTrace, isNotNull);
  });

  test('housekeeping failures stay out of a non-verbose log', () async {
    final quiet = AppLogger(sinks: [sink]);
    await bestEffort('test', '清理', () => throw StateError('x'), logger: quiet);

    expect(sink.records, isEmpty);
  });

  test('bestEffortSync runs synchronously and reports failures', () {
    var ran = false;
    bestEffortSync('test', '发信号', () => ran = true, logger: logger);
    bestEffortSync(
      'test',
      '发信号',
      () => throw UnsupportedError('no signal'),
      logger: logger,
    );

    expect(ran, isTrue);
    expect(sink.records.single.error, contains('no signal'));
  });

  test('bestEffortValue returns the value or the fallback', () async {
    expect(await bestEffortValue('test', '读取', () async => 7, fallback: 0), 7);
    expect(
      await bestEffortValue(
        'test',
        '读取',
        () async => throw StateError('unreadable'),
        fallback: 0,
        logger: logger,
      ),
      0,
    );
    expect(sink.records.single.message, '读取 失败，已忽略');
  });
}

class FileSystemExceptionLike implements Exception {
  const FileSystemExceptionLike(this.message);

  final String message;

  @override
  String toString() => 'FileSystemExceptionLike: $message';
}
