import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_build_info.dart';
import 'app_logger.dart';
import 'crash_capture.dart';
import 'diagnostics_report.dart';
import 'file_log_sink.dart';
import 'log_record.dart';
import 'log_redactor.dart';
import 'operation_timings.dart';

/// What the settings card shows without building a whole report.
class DiagnosticsSummary {
  final int logFileBytes;
  final int crashCount;
  final DateTime? lastCrashAt;
  final bool verbose;
  final bool storeCrashes;

  const DiagnosticsSummary({
    required this.logFileBytes,
    required this.crashCount,
    required this.lastCrashAt,
    required this.verbose,
    required this.storeCrashes,
  });
}

/// The user-facing diagnostics features in one place: local log files,
/// crash records, operation timings, the verbosity preference and the
/// exportable report. Everything stays on the device.
class AppDiagnostics {
  AppDiagnostics({
    required Future<Directory> Function() directory,
    AppLogger? logger,
    OperationTimings? timings,
    FileLogSink? fileSink,
    CrashRecordStore? crashStore,
    AppBuildInfo Function()? buildInfo,
    DateTime Function()? clock,
  }) : _directory = directory,
       logger = logger ?? appLog,
       _buildInfo = buildInfo,
       _clock = clock {
    this.fileSink = fileSink ?? FileLogSink(directory: directory);
    this.crashStore = crashStore ?? CrashRecordStore(directory: directory);
    this.timings = timings ?? OperationTimings(logger: this.logger);
  }

  static const String preferencesFileName = 'diagnostics_settings.json';
  static const int reportLogLimit = 400;

  final Future<Directory> Function() _directory;
  final AppLogger logger;
  late final FileLogSink fileSink;
  late final CrashRecordStore crashStore;
  late final OperationTimings timings;
  final AppBuildInfo Function()? _buildInfo;
  final DateTime Function()? _clock;
  final List<DiagnosticsSection> _sections = [];
  VoidCallback? _uninstallCrashCapture;
  bool _verbose = false;
  bool _storeCrashes = true;
  bool _started = false;

  bool get verbose => _verbose;

  /// Whether uncaught errors are kept as crash records (on by default; the
  /// records never leave the device unless the user exports them).
  bool get storeCrashes => _storeCrashes;

  List<DiagnosticsSection> get sections => List.unmodifiable(_sections);

  /// Adds a feature section; a section with the same id is replaced.
  void registerSection(DiagnosticsSection section) {
    _sections
      ..removeWhere((existing) => existing.id == section.id)
      ..add(section);
  }

  /// Attaches the file sink and, unless [captureCrashes] is false, the crash
  /// handlers. Safe to call once; later calls do nothing.
  Future<void> start({bool captureCrashes = true}) async {
    if (_started) return;
    _started = true;
    logger.redactor = LogRedactor(homeDirectories: _homeDirectories());
    logger.addSink(fileSink);
    if (captureCrashes) {
      _uninstallCrashCapture = installCrashCapture(
        logger: logger,
        store: crashStore,
        appVersion: appVersion,
        shouldStore: () => _storeCrashes,
      );
    }
    await _loadPreferences();
    logger.info('app', 'Started $appDisplayName $appVersion');
  }

  Future<void> stop() async {
    _uninstallCrashCapture?.call();
    _uninstallCrashCapture = null;
    await logger.flush();
    logger.removeSink(fileSink);
    _started = false;
  }

  /// Debug-level records are kept only while verbose logging is on.
  Future<void> setVerbose(bool value) async {
    _verbose = value;
    logger.minimumLevel = value ? LogLevel.debug : LogLevel.info;
    logger.info('diagnostics', value ? '详细日志已开启' : '详细日志已关闭');
    await _savePreferences();
  }

  Future<void> setStoreCrashes(bool value) async {
    _storeCrashes = value;
    logger.info('diagnostics', value ? '崩溃记录已开启' : '崩溃记录已关闭');
    await _savePreferences();
  }

  Future<void> _savePreferences() async {
    try {
      final file = await _preferencesFile();
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'version': 1,
          'verbose': _verbose,
          'storeCrashes': _storeCrashes,
        }),
        flush: true,
      );
      await temporary.rename(file.path);
    } catch (error, stackTrace) {
      logger.warning(
        'diagnostics',
        'Could not save the diagnostics preferences',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<DiagnosticsSummary> summary() async {
    final crashes = await crashStore.load();
    var bytes = 0;
    try {
      bytes = await fileSink.sizeInBytes();
    } catch (_) {}
    return DiagnosticsSummary(
      logFileBytes: bytes,
      crashCount: crashes.length,
      lastCrashAt: crashes.isEmpty ? null : crashes.last.time,
      verbose: _verbose,
      storeCrashes: _storeCrashes,
    );
  }

  Future<DiagnosticsReport> buildReport() {
    final builder = DiagnosticsReportBuilder(
      redactor: logger.redactor,
      sections: sections,
      loadLogs: _recentLogs,
      loadCrashes: crashStore.load,
      timings: timings.toJson,
      buildInfo: _buildInfo,
      clock: _clock,
    );
    return builder.build();
  }

  /// Deletes log files, crash records, in-memory records and timings.
  Future<void> clearAll() async {
    await fileSink.clear();
    await crashStore.clear();
    logger.memory?.clear();
    timings.clear();
    logger.info('diagnostics', '诊断记录已清除');
  }

  Future<List<LogRecord>> _recentLogs() async {
    try {
      final records = await fileSink.readRecent(limit: reportLogLimit);
      if (records.isNotEmpty) return records;
    } catch (_) {}
    // No readable file (sandboxed, read-only disk): fall back to memory.
    final memory = logger.memory?.records ?? const <LogRecord>[];
    return memory.length <= reportLogLimit
        ? memory
        : memory.sublist(memory.length - reportLogLimit);
  }

  Future<void> _loadPreferences() async {
    try {
      final file = await _preferencesFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      if (decoded['verbose'] == true) {
        _verbose = true;
        logger.minimumLevel = LogLevel.debug;
      }
      if (decoded['storeCrashes'] == false) _storeCrashes = false;
    } catch (_) {
      // Unreadable preferences fall back to the default level.
    }
  }

  Future<File> _preferencesFile() async {
    final directory = await _directory();
    await directory.create(recursive: true);
    final separator = directory.path.endsWith(Platform.pathSeparator)
        ? ''
        : Platform.pathSeparator;
    return File('${directory.path}$separator$preferencesFileName');
  }

  static List<String> _homeDirectories() {
    try {
      final environment = Platform.environment;
      return [
        for (final key in const ['HOME', 'USERPROFILE'])
          if (environment[key] case final value? when value.trim().isNotEmpty)
            value,
      ];
    } catch (_) {
      return const [];
    }
  }
}
