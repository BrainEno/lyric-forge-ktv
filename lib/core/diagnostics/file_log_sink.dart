import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_logger.dart';
import 'log_record.dart';

/// Appends records as JSON lines to `<directory>/app.log`, rotating to
/// `app.1.log` when the file passes [maxBytes].
///
/// Writes are batched and serialised on one future chain, so logging from a
/// hot path never waits for disk and two writes never interleave. Disk errors
/// are swallowed: a log that cannot be written must not crash the app.
class FileLogSink implements LogSink {
  FileLogSink({
    required Future<Directory> Function() directory,
    this.maxBytes = 512 * 1024,
    this.flushDelay = const Duration(milliseconds: 400),
  }) : assert(maxBytes > 1024),
       _directory = directory;

  static const String fileName = 'app.log';
  static const String rotatedFileName = 'app.1.log';

  final Future<Directory> Function() _directory;
  final int maxBytes;
  final Duration flushDelay;

  final List<String> _pending = <String>[];
  Future<void> _chain = Future<void>.value();
  Timer? _timer;
  Directory? _resolved;
  int? _knownSize;

  @override
  void write(LogRecord record) {
    _pending.add(jsonEncode(record.toJson()));
    // Errors are rare and the most useful lines; write them promptly.
    if (record.level == LogLevel.error) {
      unawaited(flush());
      return;
    }
    _timer ??= Timer(flushDelay, () => unawaited(flush()));
  }

  @override
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return _chain;
    final batch = List<String>.of(_pending);
    _pending.clear();
    _chain = _chain.then((_) => _append(batch)).catchError((Object _) {});
    return _chain;
  }

  Future<Directory> _logDirectory() async {
    final cached = _resolved;
    if (cached != null) return cached;
    final directory = await _directory();
    await directory.create(recursive: true);
    return _resolved = directory;
  }

  Future<void> _append(List<String> lines) async {
    final directory = await _logDirectory();
    final file = File(_join(directory.path, fileName));
    var size = _knownSize ??= await file.exists() ? await file.length() : 0;
    final payload = '${lines.join('\n')}\n';
    final bytes = utf8.encode(payload);
    if (size > 0 && size + bytes.length > maxBytes) {
      final rotated = File(_join(directory.path, rotatedFileName));
      if (await rotated.exists()) await rotated.delete();
      await file.rename(rotated.path);
      size = 0;
    }
    await File(
      file.path,
    ).writeAsBytes(bytes, mode: FileMode.append, flush: true);
    _knownSize = size + bytes.length;
  }

  /// The most recent [limit] records across the rotated and current file,
  /// oldest first. Includes previous sessions, which is what a bug report
  /// about "it crashed yesterday" needs.
  Future<List<LogRecord>> readRecent({int limit = 400}) async {
    await flush();
    final directory = await _logDirectory();
    final records = <LogRecord>[];
    for (final name in [rotatedFileName, fileName]) {
      final file = File(_join(directory.path, name));
      if (!await file.exists()) continue;
      final List<String> lines;
      try {
        lines = await file.readAsLines();
      } on FormatException {
        // A torn multi-byte write; skip the file rather than fail the export.
        continue;
      }
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final record = LogRecord.tryParse(jsonDecode(line));
          if (record != null) records.add(record);
        } on FormatException {
          continue;
        }
      }
    }
    if (records.length <= limit) return records;
    return records.sublist(records.length - limit);
  }

  /// Deletes both log files.
  Future<void> clear() async {
    _pending.clear();
    await flush();
    final directory = await _logDirectory();
    _chain = _chain
        .then((_) async {
          for (final name in [fileName, rotatedFileName]) {
            final file = File(_join(directory.path, name));
            if (await file.exists()) await file.delete();
          }
          _knownSize = 0;
        })
        .catchError((Object _) {});
    await _chain;
  }

  /// Total size of the log files in bytes.
  Future<int> sizeInBytes() async {
    await flush();
    final directory = await _logDirectory();
    var total = 0;
    for (final name in [fileName, rotatedFileName]) {
      final file = File(_join(directory.path, name));
      if (await file.exists()) total += await file.length();
    }
    return total;
  }

  static String _join(String directory, String name) =>
      directory.endsWith(Platform.pathSeparator)
      ? '$directory$name'
      : '$directory${Platform.pathSeparator}$name';
}
