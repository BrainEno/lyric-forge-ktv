/// Severity of a log record, lowest first.
enum LogLevel {
  debug('DEBUG'),
  info('INFO'),
  warning('WARN'),
  error('ERROR');

  const LogLevel(this.label);

  /// Fixed-width label used in text output.
  final String label;

  bool isAtLeast(LogLevel other) => index >= other.index;

  static LogLevel? tryParse(Object? name) {
    for (final level in values) {
      if (level.name == name) return level;
    }
    return null;
  }
}

/// One log entry. Text fields are already redacted when a record is built by
/// [AppLogger], so sinks and the diagnostics report never see raw secrets.
class LogRecord {
  final DateTime time;
  final LogLevel level;

  /// Module tag such as `transcription` or `ktv`; lower-case, no spaces.
  final String tag;
  final String message;

  /// `runtimeType: message` of the error, if any.
  final String? error;

  /// Trimmed stack trace, if any.
  final String? stackTrace;

  LogRecord({
    required DateTime time,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stackTrace,
  }) : time = time.toUtc();

  Map<String, Object?> toJson() => {
    't': time.toIso8601String(),
    'l': level.name,
    'g': tag,
    'm': message,
    if (error != null) 'e': error,
    if (stackTrace != null) 's': stackTrace,
  };

  /// Parses one stored record; returns null for anything malformed so a
  /// damaged log line never breaks the diagnostics export.
  static LogRecord? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final time = DateTime.tryParse('${raw['t']}');
    final level = LogLevel.tryParse(raw['l']);
    final tag = raw['g'];
    final message = raw['m'];
    if (time == null || level == null || tag is! String || message is! String) {
      return null;
    }
    final error = raw['e'];
    final stackTrace = raw['s'];
    return LogRecord(
      time: time,
      level: level,
      tag: tag,
      message: message,
      error: error is String ? error : null,
      stackTrace: stackTrace is String ? stackTrace : null,
    );
  }

  /// `2026-11-15T07:00:00.000Z WARN  [ktv] message — Error: detail`.
  String format({bool includeStackTrace = false}) {
    final buffer = StringBuffer()
      ..write(time.toIso8601String())
      ..write(' ')
      ..write(level.label.padRight(5))
      ..write(' [')
      ..write(tag)
      ..write('] ')
      ..write(message);
    if (error != null) buffer.write(' — $error');
    if (includeStackTrace && stackTrace != null) {
      for (final line in stackTrace!.split('\n')) {
        buffer.write('\n    $line');
      }
    }
    return buffer.toString();
  }
}
