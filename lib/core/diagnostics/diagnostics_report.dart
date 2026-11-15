import 'dart:async';
import 'dart:convert';

import 'app_build_info.dart';
import 'crash_capture.dart';
import 'log_record.dart';
import 'log_redactor.dart';

/// A named block of structured facts contributed by a feature (ASR runtime
/// state, KTV microphone state …).
///
/// Sections return maps of scalars, lists and maps, never free-form
/// documents: that keeps lyrics, audio and project content out of the
/// report by construction. Every value is redacted again when the report is
/// built.
class DiagnosticsSection {
  final String id;
  final String title;
  final Future<Map<String, Object?>> Function() collect;
  final Duration timeout;

  const DiagnosticsSection({
    required this.id,
    required this.title,
    required this.collect,
    this.timeout = const Duration(seconds: 5),
  });
}

/// The outcome of one section: its data, or why it could not be collected.
class DiagnosticsSectionResult {
  final String id;
  final String title;
  final Map<String, Object?>? data;
  final String? failure;

  const DiagnosticsSectionResult({
    required this.id,
    required this.title,
    this.data,
    this.failure,
  });

  Map<String, Object?> toJson() => {
    'title': title,
    if (data != null) 'data': data,
    if (failure != null) 'failure': failure,
  };
}

/// A complete, redacted diagnostics bundle.
class DiagnosticsReport {
  static const int schemaVersion = 1;

  static const String privacyNotice =
      '不含歌词、音频或工程内容；密钥、令牌、邮箱和路径中的用户名已替换。'
      '诊断包只保存在本机，是否发送由你决定。';

  final DateTime generatedAt;
  final AppBuildInfo build;
  final List<DiagnosticsSectionResult> sections;
  final Map<String, Object?> timings;
  final List<CrashRecord> crashes;
  final List<LogRecord> logs;

  const DiagnosticsReport({
    required this.generatedAt,
    required this.build,
    required this.sections,
    required this.timings,
    required this.crashes,
    required this.logs,
  });

  String get suggestedFileName {
    final stamp = generatedAt
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '')
        .replaceAll('-', '');
    return 'elysium-diagnostics-${stamp.substring(0, 15)}.txt';
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'privacy': privacyNotice,
    'build': build.toJson(),
    'sections': {for (final section in sections) section.id: section.toJson()},
    'timings': timings,
    'crashes': [for (final crash in crashes) crash.toJson()],
    'logs': [for (final record in logs) record.toJson()],
  };

  /// Human-readable text with the machine-readable JSON appended, so one file
  /// serves both a person reading it and a script parsing it.
  String toText({bool includeJson = true}) {
    final buffer = StringBuffer()
      ..writeln('$appDisplayName 诊断包')
      ..writeln('生成时间：${generatedAt.toUtc().toIso8601String()}')
      ..writeln('隐私：$privacyNotice')
      ..writeln();

    _heading(buffer, '应用与平台');
    _writeMap(buffer, build.toJson(), 0);

    for (final section in sections) {
      _heading(buffer, section.title);
      if (section.failure != null) {
        buffer.writeln('收集失败：${section.failure}');
      } else if (section.data == null || section.data!.isEmpty) {
        buffer.writeln('（无数据）');
      } else {
        _writeMap(buffer, section.data!, 0);
      }
    }

    _heading(buffer, '操作耗时（本次运行）');
    if (timings.isEmpty) {
      buffer.writeln('（本次运行还没有计时数据）');
    } else {
      for (final entry in timings.entries) {
        final value = entry.value;
        final summary = value is Map ? value['summary'] : null;
        buffer.writeln('${entry.key}: ${_inline(summary)}');
      }
    }

    _heading(buffer, '崩溃记录（${crashes.length}）');
    if (crashes.isEmpty) buffer.writeln('（无）');
    for (final crash in crashes) {
      buffer.writeln(
        '${crash.time.toIso8601String()} [${crash.source.name}] '
        'v${crash.appVersion} ${crash.error}',
      );
      if (crash.context != null) buffer.writeln('  context: ${crash.context}');
      final stack = crash.stackTrace;
      if (stack != null) {
        for (final line in stack.split('\n').take(8)) {
          buffer.writeln('    $line');
        }
      }
    }

    _heading(buffer, '最近日志（${logs.length} 条）');
    if (logs.isEmpty) buffer.writeln('（无）');
    for (final record in logs) {
      buffer.writeln(
        record.format(includeStackTrace: record.level == LogLevel.error),
      );
    }

    if (includeJson) {
      buffer
        ..writeln()
        ..writeln('---- JSON ----')
        ..writeln(const JsonEncoder.withIndent('  ').convert(toJson()));
    }
    return buffer.toString();
  }

  static void _heading(StringBuffer buffer, String title) {
    buffer
      ..writeln()
      ..writeln('== $title ==');
  }

  static void _writeMap(StringBuffer buffer, Map<Object?, Object?> map, int depth) {
    final indent = '  ' * depth;
    for (final entry in map.entries) {
      final value = entry.value;
      if (value is Map && value.isNotEmpty) {
        buffer.writeln('$indent${entry.key}:');
        _writeMap(buffer, value, depth + 1);
      } else if (value is List && value.any((item) => item is Map)) {
        buffer.writeln('$indent${entry.key}:');
        for (final item in value) {
          if (item is Map) {
            buffer.writeln('$indent  - ${_inline(item)}');
          } else {
            buffer.writeln('$indent  - $item');
          }
        }
      } else {
        buffer.writeln('$indent${entry.key}: ${_inline(value)}');
      }
    }
  }

  static String _inline(Object? value) {
    if (value == null) return '—';
    if (value is Map) {
      return value.entries
          .map((entry) => '${entry.key}=${_inline(entry.value)}')
          .join(', ');
    }
    if (value is List) return '[${value.map(_inline).join(', ')}]';
    return '$value';
  }
}

/// Assembles a [DiagnosticsReport] from build info, feature sections, timings,
/// crash records and recent logs, redacting everything once more.
class DiagnosticsReportBuilder {
  DiagnosticsReportBuilder({
    required this.redactor,
    required this.sections,
    required this.loadLogs,
    required this.loadCrashes,
    required this.timings,
    AppBuildInfo Function()? buildInfo,
    DateTime Function()? clock,
  }) : _buildInfo = buildInfo ?? AppBuildInfo.current,
       _clock = clock ?? DateTime.now;

  final LogRedactor redactor;
  final List<DiagnosticsSection> sections;
  final Future<List<LogRecord>> Function() loadLogs;
  final Future<List<CrashRecord>> Function() loadCrashes;
  final Map<String, Object?> Function() timings;
  final AppBuildInfo Function() _buildInfo;
  final DateTime Function() _clock;

  Future<DiagnosticsReport> build() async {
    final results = await Future.wait([
      for (final section in sections) _collect(section),
    ]);
    List<LogRecord> logs;
    try {
      logs = await loadLogs();
    } catch (_) {
      logs = const [];
    }
    List<CrashRecord> crashes;
    try {
      crashes = await loadCrashes();
    } catch (_) {
      crashes = const [];
    }
    final build = _buildInfo();
    return DiagnosticsReport(
      generatedAt: _clock(),
      build: AppBuildInfo(
        version: build.version,
        buildMode: build.buildMode,
        operatingSystem: build.operatingSystem,
        operatingSystemVersion: redactor.redact(build.operatingSystemVersion),
        dartVersion: build.dartVersion,
        processorCount: build.processorCount,
        locale: build.locale,
      ),
      sections: results,
      timings: _asMap(redactor.redactValue(timings())),
      crashes: [
        for (final crash in crashes)
          CrashRecord(
            time: crash.time,
            source: crash.source,
            error: redactor.redact(crash.error),
            context: crash.context == null
                ? null
                : redactor.redact(crash.context!),
            stackTrace: crash.stackTrace == null
                ? null
                : redactor.redact(crash.stackTrace!),
            appVersion: crash.appVersion,
          ),
      ],
      // Records were redacted when written; files from older builds or
      // another machine are redacted again here.
      logs: [
        for (final record in logs)
          LogRecord(
            time: record.time,
            level: record.level,
            tag: record.tag,
            message: redactor.redact(record.message),
            error: record.error == null ? null : redactor.redact(record.error!),
            stackTrace: record.stackTrace == null
                ? null
                : redactor.redact(record.stackTrace!),
          ),
      ],
    );
  }

  Future<DiagnosticsSectionResult> _collect(DiagnosticsSection section) async {
    try {
      final data = await section.collect().timeout(section.timeout);
      return DiagnosticsSectionResult(
        id: section.id,
        title: section.title,
        data: _asMap(redactor.redactValue(data)),
      );
    } on TimeoutException {
      return DiagnosticsSectionResult(
        id: section.id,
        title: section.title,
        failure: '超时（${section.timeout.inSeconds} 秒）',
      );
    } catch (error) {
      return DiagnosticsSectionResult(
        id: section.id,
        title: section.title,
        failure: redactor.redact('${error.runtimeType}: $error'),
      );
    }
  }

  static Map<String, Object?> _asMap(Object? value) =>
      value is Map<String, Object?> ? value : <String, Object?>{};
}
