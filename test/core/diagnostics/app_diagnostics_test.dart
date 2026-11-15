import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/diagnostics/app_build_info.dart';
import 'package:lyric_forge_ktv/core/diagnostics/app_diagnostics.dart';
import 'package:lyric_forge_ktv/core/diagnostics/app_logger.dart';
import 'package:lyric_forge_ktv/core/diagnostics/crash_capture.dart';
import 'package:lyric_forge_ktv/core/diagnostics/diagnostics_report.dart';
import 'package:lyric_forge_ktv/core/diagnostics/file_log_sink.dart';
import 'package:lyric_forge_ktv/core/diagnostics/log_record.dart';

void main() {
  late Directory root;
  late AppLogger logger;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('app_diagnostics_test');
    logger = AppLogger(sinks: [MemoryLogSink()]);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<Directory> directory() async => Directory('${root.path}/diagnostics');

  AppDiagnostics diagnostics() => AppDiagnostics(
    directory: directory,
    logger: logger,
    fileSink: FileLogSink(
      directory: directory,
      flushDelay: const Duration(milliseconds: 10),
    ),
  );

  test('start attaches the file sink so records reach disk', () async {
    final subject = diagnostics();
    await subject.start(captureCrashes: false);
    logger.warning('ktv', 'monitor underrun');
    await logger.flush();

    final records = await subject.fileSink.readRecent();
    expect(records.map((record) => record.message), [
      'Started $appDisplayName $appVersion',
      'monitor underrun',
    ]);

    await subject.stop();
    logger.info('ktv', 'after stop');
    expect(
      (await subject.fileSink.readRecent()).map((record) => record.message),
      isNot(contains('after stop')),
    );
  });

  test('preferences persist and are restored on the next start', () async {
    final first = diagnostics();
    await first.start(captureCrashes: false);
    expect(first.verbose, isFalse);
    expect(first.storeCrashes, isTrue);
    await first.setVerbose(true);
    await first.setStoreCrashes(false);
    expect(logger.minimumLevel, LogLevel.debug);
    await first.stop();

    final saved = jsonDecode(
      await File(
        '${root.path}/diagnostics/${AppDiagnostics.preferencesFileName}',
      ).readAsString(),
    );
    expect(saved, {'version': 1, 'verbose': true, 'storeCrashes': false});

    logger = AppLogger(sinks: [MemoryLogSink()]);
    final second = diagnostics();
    await second.start(captureCrashes: false);
    expect(second.verbose, isTrue);
    expect(second.storeCrashes, isFalse);
    expect(logger.minimumLevel, LogLevel.debug);
    await second.stop();
  });

  test('a corrupt preferences file falls back to defaults', () async {
    final dir = await directory();
    await dir.create(recursive: true);
    await File(
      '${dir.path}/${AppDiagnostics.preferencesFileName}',
    ).writeAsString('[');
    final subject = diagnostics();
    await subject.start(captureCrashes: false);
    expect(subject.verbose, isFalse);
    expect(subject.storeCrashes, isTrue);
    await subject.stop();
  });

  test('summary, report and clearAll', () async {
    final subject = diagnostics()
      ..registerSection(
        DiagnosticsSection(
          id: 'library',
          title: '资料库规模',
          collect: () async => {'projects': 1},
        ),
      )
      // Same id replaces the earlier section.
      ..registerSection(
        DiagnosticsSection(
          id: 'library',
          title: '资料库规模',
          collect: () async => {'projects': 3},
        ),
      );
    await subject.start(captureCrashes: false);
    logger.error('ktv', 'export failed');
    subject.timings.record('ktv.exportMix', const Duration(seconds: 2));
    await subject.crashStore.add(
      CrashRecord(
        time: DateTime.utc(2026, 11, 15),
        source: CrashSource.flutter,
        error: 'x',
        appVersion: appVersion,
      ),
    );

    final summary = await subject.summary();
    expect(summary.crashCount, 1);
    expect(summary.lastCrashAt, DateTime.utc(2026, 11, 15));
    expect(summary.logFileBytes, greaterThan(0));

    final report = await subject.buildReport();
    expect(subject.sections, hasLength(1));
    expect(report.sections.single.data, {'projects': 3});
    expect(report.timings.keys, ['ktv.exportMix']);
    expect(report.crashes, hasLength(1));
    expect(
      report.logs.map((record) => record.message),
      contains('export failed'),
    );

    await subject.clearAll();
    final cleared = await subject.summary();
    expect(cleared.crashCount, 0);
    expect(subject.timings.operations, isEmpty);
    // Only the "cleared" notice itself remains.
    expect(
      (await subject.fileSink.readRecent()).map((record) => record.message),
      ['诊断记录已清除'],
    );
    expect(logger.memory!.records.map((record) => record.message), [
      '诊断记录已清除',
    ]);
    await subject.stop();
  });

  test('the report falls back to memory when the file has nothing', () async {
    final subject = diagnostics();
    // Not started: the file sink is not attached, records stay in memory.
    logger.info('app', 'memory only');
    final report = await subject.buildReport();
    expect(report.logs.single.message, 'memory only');
  });
}
