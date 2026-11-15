import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/diagnostics/app_build_info.dart';
import 'package:lyric_forge_ktv/core/diagnostics/crash_capture.dart';
import 'package:lyric_forge_ktv/core/diagnostics/diagnostics_report.dart';
import 'package:lyric_forge_ktv/core/diagnostics/log_record.dart';
import 'package:lyric_forge_ktv/core/diagnostics/log_redactor.dart';

const _build = AppBuildInfo(
  version: '1.0.0+1',
  buildMode: 'release',
  operatingSystem: 'macos',
  operatingSystemVersion: 'Version 15.1 (Build 24B83)',
  dartVersion: '3.11.4',
  processorCount: 10,
  locale: 'zh_TW',
);

DiagnosticsReportBuilder _builder({
  List<DiagnosticsSection> sections = const [],
  List<LogRecord> logs = const [],
  List<CrashRecord> crashes = const [],
  Map<String, Object?> timings = const {},
}) => DiagnosticsReportBuilder(
  redactor: LogRedactor(homeDirectories: ['/Users/alice']),
  sections: sections,
  loadLogs: () async => logs,
  loadCrashes: () async => crashes,
  timings: () => timings,
  buildInfo: () => _build,
  clock: () => DateTime.utc(2026, 11, 15, 9, 5, 7),
);

void main() {
  test('collects sections and redacts their values', () async {
    final report = await _builder(
      sections: [
        DiagnosticsSection(
          id: 'asr',
          title: '本地识别运行环境',
          collect: () async => {
            'ready': true,
            'managedRoot': '/Users/alice/Library/Application Support/x',
            'proxy': 'http://bob:pw@proxy.local:8080',
            'token': 'abc',
          },
        ),
      ],
    ).build();

    final asr = report.sections.single;
    expect(asr.failure, isNull);
    expect(asr.data, {
      'ready': true,
      'managedRoot': '~/Library/Application Support/x',
      'proxy': 'http://<redacted>@proxy.local:8080',
      'token': '<redacted>',
    });
  });

  test('a failing or slow section does not fail the report', () async {
    final never = Completer<Map<String, Object?>>();
    final report = await _builder(
      sections: [
        DiagnosticsSection(
          id: 'broken',
          title: 'Broken',
          collect: () async => throw StateError('no mic at /Users/alice/x'),
        ),
        DiagnosticsSection(
          id: 'slow',
          title: 'Slow',
          timeout: const Duration(milliseconds: 20),
          collect: () => never.future,
        ),
        DiagnosticsSection(
          id: 'ok',
          title: 'OK',
          collect: () async => {'count': 2},
        ),
      ],
    ).build();

    final byId = {for (final section in report.sections) section.id: section};
    expect(byId['broken']!.failure, 'StateError: Bad state: no mic at ~/x');
    expect(byId['slow']!.failure, startsWith('超时'));
    expect(byId['ok']!.data, {'count': 2});
  });

  test('re-redacts logs and crashes loaded from disk', () async {
    final report = await _builder(
      logs: [
        LogRecord(
          time: DateTime.utc(2026, 11, 14),
          level: LogLevel.warning,
          tag: 'transfer',
          message: 'GET /x?token=raw',
          error: 'mail carol@example.com',
          stackTrace: '#0 /Users/alice/a.dart',
        ),
      ],
      crashes: [
        CrashRecord(
          time: DateTime.utc(2026, 11, 14),
          source: CrashSource.platform,
          error: 'password=hunter2',
          context: '/home/dave/x',
          stackTrace: '#0 /Users/alice/b.dart',
          appVersion: '0.9.0',
        ),
      ],
    ).build();

    final log = report.logs.single;
    expect(log.message, 'GET /x?token=<redacted>');
    expect(log.error, 'mail <email>');
    expect(log.stackTrace, '#0 ~/a.dart');
    final crash = report.crashes.single;
    expect(crash.error, 'password=<redacted>');
    expect(crash.context, '~/x');
    expect(crash.stackTrace, '#0 ~/b.dart');
    expect(crash.appVersion, '0.9.0');
  });

  test('log and crash loading failures leave those parts empty', () async {
    final report = await DiagnosticsReportBuilder(
      redactor: LogRedactor(),
      sections: const [],
      loadLogs: () async => throw StateError('read-only'),
      loadCrashes: () async => throw StateError('read-only'),
      timings: () => const {},
      buildInfo: () => _build,
    ).build();
    expect(report.logs, isEmpty);
    expect(report.crashes, isEmpty);
  });

  test('text output has every part, the privacy notice and valid JSON',
      () async {
    final report = await _builder(
      sections: [
        DiagnosticsSection(
          id: 'ktv',
          title: 'KTV 麦克风',
          collect: () async => {
            'inputDevices': 2,
            'engineLatencyMs': 12,
            'devices': [
              {'label': 'USB'},
            ],
          },
        ),
      ],
      logs: [
        LogRecord(
          time: DateTime.utc(2026, 11, 15),
          level: LogLevel.error,
          tag: 'ktv',
          message: 'export failed',
          stackTrace: '#0 mix',
        ),
      ],
      timings: {
        'ktv.exportMix': {
          'summary': {'count': 1, 'medianMs': 4200},
          'recent': const [],
        },
      },
    ).build();

    final text = report.toText();
    expect(text, contains('Elysium Player 诊断包'));
    expect(text, contains(DiagnosticsReport.privacyNotice));
    expect(text, contains('== 应用与平台 =='));
    expect(text, contains('version: 1.0.0+1'));
    expect(text, contains('== KTV 麦克风 =='));
    expect(text, contains('engineLatencyMs: 12'));
    expect(text, contains('  - label=USB'));
    expect(text, contains('ktv.exportMix: count=1, medianMs=4200'));
    expect(text, contains('== 崩溃记录（0） =='));
    expect(text, contains('[ktv] export failed'));
    expect(text, contains('    #0 mix'));

    final json = jsonDecode(text.split('---- JSON ----\n').last)
        as Map<String, Object?>;
    expect(json['schemaVersion'], DiagnosticsReport.schemaVersion);
    expect(json['generatedAt'], '2026-11-15T09:05:07.000Z');
    expect((json['sections'] as Map)['ktv'], isNotNull);
    expect(json['logs'], hasLength(1));

    final short = report.toText(includeJson: false);
    expect(short, isNot(contains('---- JSON ----')));
  });

  test('suggests a timestamped file name', () async {
    final report = await _builder().build();
    expect(report.suggestedFileName, 'elysium-diagnostics-20261115T090507.txt');
  });

  test('an empty report says so instead of printing nothing', () async {
    final text = (await _builder().build()).toText(includeJson: false);
    expect(text, contains('（本次运行还没有计时数据）'));
    expect(text, contains('== 最近日志（0 条） =='));
  });
}
