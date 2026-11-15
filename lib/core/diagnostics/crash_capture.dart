import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'app_logger.dart';
import 'log_record.dart';

/// Where an uncaught error was intercepted.
enum CrashSource {
  /// `FlutterError.onError`: build, layout, paint and gesture errors.
  flutter,

  /// `PlatformDispatcher.onError`: uncaught asynchronous Dart errors.
  platform,
}

/// A redacted summary of one uncaught error, kept locally until the user
/// exports or clears diagnostics. Nothing is uploaded.
class CrashRecord {
  final DateTime time;
  final CrashSource source;
  final String error;
  final String? context;
  final String? stackTrace;
  final String appVersion;

  CrashRecord({
    required DateTime time,
    required this.source,
    required this.error,
    required this.appVersion,
    this.context,
    this.stackTrace,
  }) : time = time.toUtc();

  Map<String, Object?> toJson() => {
    'time': time.toIso8601String(),
    'source': source.name,
    'error': error,
    if (context != null) 'context': context,
    if (stackTrace != null) 'stackTrace': stackTrace,
    'appVersion': appVersion,
  };

  static CrashRecord? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final time = DateTime.tryParse('${raw['time']}');
    final source = CrashSource.values.asNameMap()[raw['source']];
    final error = raw['error'];
    if (time == null || source == null || error is! String) return null;
    final context = raw['context'];
    final stackTrace = raw['stackTrace'];
    final appVersion = raw['appVersion'];
    return CrashRecord(
      time: time,
      source: source,
      error: error,
      context: context is String ? context : null,
      stackTrace: stackTrace is String ? stackTrace : null,
      appVersion: appVersion is String ? appVersion : 'unknown',
    );
  }
}

/// Stores the most recent [capacity] crash records in one JSON file.
class CrashRecordStore {
  CrashRecordStore({
    required Future<Directory> Function() directory,
    this.capacity = 10,
  }) : _directory = directory;

  static const String fileName = 'crashes.json';

  final Future<Directory> Function() _directory;
  final int capacity;
  Future<void> _chain = Future<void>.value();

  Future<File> _file() async {
    final directory = await _directory();
    await directory.create(recursive: true);
    final separator = directory.path.endsWith(Platform.pathSeparator)
        ? ''
        : Platform.pathSeparator;
    return File('${directory.path}$separator$fileName');
  }

  Future<List<CrashRecord>> load() async {
    await _chain;
    return _read();
  }

  Future<List<CrashRecord>> _read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const [];
      final decoded = jsonDecode(await file.readAsString());
      final raw = decoded is Map ? decoded['crashes'] : null;
      if (raw is! List) return const [];
      return [
        for (final item in raw)
          if (CrashRecord.tryParse(item) case final record?) record,
      ];
    } on Object {
      // A damaged crash file is not worth another crash.
      return const [];
    }
  }

  Future<void> add(CrashRecord record) {
    _chain = _chain.then((_) async {
      final records = [...await _read(), record];
      final kept = records.length > capacity
          ? records.sublist(records.length - capacity)
          : records;
      final file = await _file();
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'version': 1,
          'crashes': [for (final item in kept) item.toJson()],
        }),
        flush: true,
      );
      await temporary.rename(file.path);
    }).catchError((Object _) {});
    return _chain;
  }

  Future<void> clear() {
    _chain = _chain.then((_) async {
      final file = await _file();
      if (await file.exists()) await file.delete();
    }).catchError((Object _) {});
    return _chain;
  }
}

/// Routes uncaught Flutter and asynchronous errors into the logger and the
/// local crash store, keeping Flutter's own reporting in debug builds.
///
/// [shouldStore] is read on every error, so turning crash records off in
/// settings takes effect immediately; the error is still logged.
///
/// Returns a callback that restores the previous handlers (for tests).
VoidCallback installCrashCapture({
  required AppLogger logger,
  required CrashRecordStore store,
  required String appVersion,
  PlatformDispatcher? dispatcher,
  bool Function()? shouldStore,
}) {
  final platform = dispatcher ?? PlatformDispatcher.instance;
  final previousFlutter = FlutterError.onError;
  final previousPlatform = platform.onError;

  void capture(
    CrashSource source,
    Object error,
    StackTrace? stackTrace, {
    String? context,
  }) {
    try {
      final record = logger.buildRecord(
        LogLevel.error,
        'crash',
        context == null
            ? 'Uncaught ${source.name} error'
            : 'Uncaught ${source.name} error ($context)',
        error: error,
        stackTrace: stackTrace,
      );
      logger.log(
        LogLevel.error,
        'crash',
        record.message,
        error: error,
        stackTrace: stackTrace,
      );
      if (shouldStore != null && !shouldStore()) return;
      unawaited(
        store.add(
          CrashRecord(
            time: record.time,
            source: source,
            error: record.error ?? record.message,
            context: context == null ? null : logger.redactor.redact(context),
            stackTrace: record.stackTrace,
            appVersion: appVersion,
          ),
        ),
      );
    } catch (_) {
      // Crash capture must never become the crash.
    }
  }

  FlutterError.onError = (details) {
    capture(
      CrashSource.flutter,
      details.exception,
      details.stack,
      context: details.context?.toDescription(),
    );
    if (previousFlutter != null) {
      previousFlutter(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  platform.onError = (error, stackTrace) {
    capture(CrashSource.platform, error, stackTrace);
    final previous = previousPlatform;
    if (previous != null) return previous(error, stackTrace);
    // Handled: it is logged and stored. The default handler would only print
    // it again, and in release builds an unhandled error can end the app.
    return true;
  };

  return () {
    FlutterError.onError = previousFlutter;
    platform.onError = previousPlatform;
  };
}
