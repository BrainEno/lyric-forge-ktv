import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'log_record.dart';
import 'log_redactor.dart';

/// Receives redacted records. Implementations must not throw; the logger
/// still guards every call so a broken sink can never break the app.
abstract class LogSink {
  void write(LogRecord record);

  Future<void> flush() async {}
}

/// Keeps the most recent records in memory for the diagnostics report.
class MemoryLogSink implements LogSink {
  MemoryLogSink({this.capacity = 500}) : assert(capacity > 0);

  final int capacity;
  final Queue<LogRecord> _records = Queue<LogRecord>();

  List<LogRecord> get records => List.unmodifiable(_records);

  @override
  void write(LogRecord record) {
    _records.addLast(record);
    while (_records.length > capacity) {
      _records.removeFirst();
    }
  }

  void clear() => _records.clear();

  @override
  Future<void> flush() async {}
}

/// Mirrors records to the debug console in debug builds only.
class ConsoleLogSink implements LogSink {
  const ConsoleLogSink();

  @override
  void write(LogRecord record) {
    if (!kDebugMode) return;
    debugPrint(record.format(includeStackTrace: true));
  }

  @override
  Future<void> flush() async {}
}

/// Leveled, tagged logger with a single redaction point.
///
/// Use the shared [appLog] instead of `print`/`debugPrint`. Log metadata
/// (counts, durations, states, failure kinds) — never lyric text, audio
/// content or credentials. Text is redacted anyway, but structure is the
/// first line of defence.
class AppLogger {
  AppLogger({
    LogRedactor? redactor,
    List<LogSink>? sinks,
    this.minimumLevel = LogLevel.info,
    DateTime Function()? clock,
    this.maxStackTraceLines = 24,
  }) : redactor = redactor ?? LogRedactor(),
       _sinks = sinks ?? <LogSink>[MemoryLogSink(), const ConsoleLogSink()],
       _clock = clock ?? DateTime.now;

  LogRedactor redactor;
  LogLevel minimumLevel;
  final int maxStackTraceLines;
  final List<LogSink> _sinks;
  final DateTime Function() _clock;

  static final RegExp _tagPattern = RegExp(r'^[a-z0-9][a-z0-9._-]{0,31}$');

  List<LogSink> get sinks => List.unmodifiable(_sinks);

  /// The first in-memory sink, used by the diagnostics report.
  MemoryLogSink? get memory {
    for (final sink in _sinks) {
      if (sink is MemoryLogSink) return sink;
    }
    return null;
  }

  void addSink(LogSink sink) {
    if (!_sinks.contains(sink)) _sinks.add(sink);
  }

  void removeSink(LogSink sink) => _sinks.remove(sink);

  bool isEnabled(LogLevel level) => level.isAtLeast(minimumLevel);

  void debug(String tag, String message) => log(LogLevel.debug, tag, message);

  void info(String tag, String message) => log(LogLevel.info, tag, message);

  void warning(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(LogLevel.warning, tag, message, error: error, stackTrace: stackTrace);

  void error(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) => log(LogLevel.error, tag, message, error: error, stackTrace: stackTrace);

  void log(
    LogLevel level,
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!isEnabled(level)) return;
    final LogRecord record;
    try {
      record = buildRecord(
        level,
        tag,
        message,
        error: error,
        stackTrace: stackTrace,
      );
    } catch (_) {
      return;
    }
    for (final sink in List<LogSink>.of(_sinks)) {
      try {
        sink.write(record);
      } catch (_) {
        // A failing sink (full disk, closed file) must not take logging, or
        // the caller, down with it.
      }
    }
  }

  /// Builds a redacted record without writing it; used by crash capture so a
  /// crash summary and its log line are identical.
  LogRecord buildRecord(
    LogLevel level,
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    return LogRecord(
      time: _clock(),
      level: level,
      tag: _normalizeTag(tag),
      message: redactor.redact(message),
      error: error == null ? null : redactor.redact(describeError(error)),
      stackTrace: stackTrace == null
          ? null
          : redactor.redact(trimStackTrace(stackTrace, maxStackTraceLines)),
    );
  }

  Future<void> flush() async {
    for (final sink in List<LogSink>.of(_sinks)) {
      try {
        await sink.flush();
      } catch (_) {}
    }
  }

  /// `TypeName: message`, capped so a huge exception text (a whole stderr
  /// dump) cannot flood the log.
  static String describeError(Object error, {int maxLength = 600}) {
    final text = '$error';
    final type = '${error.runtimeType}';
    final described = text.startsWith(type) || text.startsWith('$type:')
        ? text
        : '$type: $text';
    if (described.length <= maxLength) return described;
    return '${described.substring(0, maxLength)}…（已截断 '
        '${described.length - maxLength} 字符）';
  }

  /// First [maxLines] non-empty frames of [stackTrace].
  static String trimStackTrace(StackTrace stackTrace, int maxLines) {
    final lines = '$stackTrace'
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.length <= maxLines) return lines.join('\n');
    return [
      ...lines.take(maxLines),
      '…（另有 ${lines.length - maxLines} 帧）',
    ].join('\n');
  }

  static String _normalizeTag(String tag) {
    final normalized = tag.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9._-]+'),
      '-',
    );
    if (_tagPattern.hasMatch(normalized)) return normalized;
    if (normalized.isEmpty) return 'app';
    final clipped = normalized.length > 32
        ? normalized.substring(0, 32)
        : normalized;
    return _tagPattern.hasMatch(clipped) ? clipped : 'app';
  }
}

/// The process-wide logger. Bootstrap attaches the file sink and the
/// user's verbosity preference; until then records stay in memory.
final AppLogger appLog = AppLogger();
