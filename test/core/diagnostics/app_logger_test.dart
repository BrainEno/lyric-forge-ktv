import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/diagnostics/app_logger.dart';
import 'package:lyric_forge_ktv/core/diagnostics/log_record.dart';
import 'package:lyric_forge_ktv/core/diagnostics/log_redactor.dart';

class _ThrowingSink implements LogSink {
  @override
  void write(LogRecord record) => throw StateError('disk full');

  @override
  Future<void> flush() async => throw StateError('disk full');
}

void main() {
  final fixedTime = DateTime.utc(2026, 11, 15, 8, 30);

  AppLogger logger({LogLevel minimum = LogLevel.info, List<LogSink>? sinks}) =>
      AppLogger(
        sinks: sinks ?? [MemoryLogSink()],
        minimumLevel: minimum,
        clock: () => fixedTime,
        redactor: LogRedactor(homeDirectories: ['/Users/alice']),
      );

  test('drops records below the minimum level', () {
    final log = logger();
    log.debug('ktv', 'gain changed');
    log.info('ktv', 'recording started');
    expect(log.memory!.records.map((record) => record.message), [
      'recording started',
    ]);

    log.minimumLevel = LogLevel.debug;
    log.debug('ktv', 'gain changed');
    expect(log.memory!.records, hasLength(2));
  });

  test('redacts message, error and stack trace', () {
    final log = logger();
    log.warning(
      'Transfer',
      'GET /stream?token=abc from /Users/alice/Music',
      error: StateError('auth failed for bob@example.com'),
      stackTrace: StackTrace.fromString(
        '#0 main (file:///Users/alice/app/lib/main.dart:1:1)',
      ),
    );
    final record = log.memory!.records.single;
    expect(record.tag, 'transfer');
    expect(record.level, LogLevel.warning);
    expect(record.time, fixedTime);
    expect(record.message, 'GET /stream?token=<redacted> from ~/Music');
    expect(record.error, 'StateError: Bad state: auth failed for <email>');
    expect(record.stackTrace, '#0 main (file://~/app/lib/main.dart:1:1)');
  });

  test('a throwing sink never breaks logging or the caller', () async {
    final memory = MemoryLogSink();
    final log = logger(sinks: [_ThrowingSink(), memory]);
    log.error('app', 'still recorded');
    await log.flush();
    expect(memory.records.single.message, 'still recorded');
  });

  test('memory sink keeps only the most recent records', () {
    final memory = MemoryLogSink(capacity: 3);
    final log = logger(sinks: [memory]);
    for (var i = 0; i < 5; i++) {
      log.info('app', 'line $i');
    }
    expect(memory.records.map((record) => record.message), [
      'line 2',
      'line 3',
      'line 4',
    ]);
    memory.clear();
    expect(memory.records, isEmpty);
  });

  test('addSink ignores duplicates and removeSink detaches', () {
    final memory = MemoryLogSink();
    final extra = MemoryLogSink();
    final log = logger(sinks: [memory]);
    log
      ..addSink(extra)
      ..addSink(extra);
    expect(log.sinks, hasLength(2));
    log.info('app', 'one');
    log.removeSink(extra);
    log.info('app', 'two');
    expect(extra.records, hasLength(1));
    expect(memory.records, hasLength(2));
  });

  test('normalizes tags', () {
    final log = logger();
    log.info(' KTV Mixer ', 'a');
    log.info('', 'b');
    log.info('x' * 40, 'c');
    expect(log.memory!.records.map((record) => record.tag), [
      'ktv-mixer',
      'app',
      'x' * 32,
    ]);
  });

  test('describeError caps long errors and adds the type once', () {
    expect(
      AppLogger.describeError(const FormatException('bad')),
      'FormatException: bad',
    );
    expect(AppLogger.describeError('plain'), 'String: plain');
    final long = AppLogger.describeError('x' * 1000, maxLength: 100);
    expect(long, startsWith('String: '));
    expect(long, contains('已截断'));
    expect(long.length, lessThan(140));
  });

  test('trimStackTrace keeps the first frames', () {
    final trace = StackTrace.fromString(
      List.generate(10, (index) => '#$index frame').join('\n'),
    );
    final trimmed = AppLogger.trimStackTrace(trace, 3);
    expect(trimmed.split('\n'), ['#0 frame', '#1 frame', '#2 frame', '…（另有 7 帧）']);
  });

  group('LogRecord', () {
    test('round-trips through JSON', () {
      final record = LogRecord(
        time: fixedTime,
        level: LogLevel.error,
        tag: 'crash',
        message: 'boom',
        error: 'StateError: x',
        stackTrace: '#0 a\n#1 b',
      );
      final parsed = LogRecord.tryParse(record.toJson())!;
      expect(parsed.toJson(), record.toJson());
    });

    test('rejects malformed input', () {
      expect(LogRecord.tryParse(null), isNull);
      expect(LogRecord.tryParse({'t': 'nope', 'l': 'info'}), isNull);
      expect(
        LogRecord.tryParse({
          't': fixedTime.toIso8601String(),
          'l': 'loud',
          'g': 'a',
          'm': 'b',
        }),
        isNull,
      );
    });

    test('formats a readable line', () {
      final record = LogRecord(
        time: fixedTime,
        level: LogLevel.warning,
        tag: 'ktv',
        message: 'late',
        error: 'TimeoutException',
        stackTrace: '#0 a',
      );
      expect(
        record.format(),
        '2026-11-15T08:30:00.000Z WARN  [ktv] late — TimeoutException',
      );
      expect(record.format(includeStackTrace: true), endsWith('\n    #0 a'));
    });
  });
}
