import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/diagnostics/app_diagnostics.dart';
import 'package:lyric_forge_ktv/core/diagnostics/app_logger.dart';
import 'package:lyric_forge_ktv/core/diagnostics/crash_capture.dart';
import 'package:lyric_forge_ktv/core/diagnostics/file_log_sink.dart';
import 'package:lyric_forge_ktv/core/diagnostics/log_record.dart';
import 'package:lyric_forge_ktv/core/diagnostics/operation_timings.dart';
import 'package:lyric_forge_ktv/features/settings/presentation/widgets/diagnostics_settings_card.dart';

Future<Directory> _noDisk() async => throw const FileSystemException('none');

/// In-memory stand-ins so the widget test never touches the disk.
class _MemoryFileSink extends FileLogSink {
  _MemoryFileSink() : super(directory: _noDisk);

  final List<LogRecord> records = [];
  int clears = 0;

  @override
  void write(LogRecord record) => records.add(record);

  @override
  Future<void> flush() async {}

  @override
  Future<List<LogRecord>> readRecent({int limit = 400}) async =>
      List.of(records);

  @override
  Future<void> clear() async {
    clears++;
    records.clear();
  }

  @override
  Future<int> sizeInBytes() async => records.length * 1024;
}

class _MemoryCrashStore extends CrashRecordStore {
  _MemoryCrashStore() : super(directory: _noDisk);

  final List<CrashRecord> crashes = [];

  @override
  Future<List<CrashRecord>> load() async => List.of(crashes);

  @override
  Future<void> add(CrashRecord record) async => crashes.add(record);

  @override
  Future<void> clear() async => crashes.clear();
}

void main() {
  late AppLogger logger;
  late _MemoryFileSink fileSink;
  late _MemoryCrashStore crashStore;
  late AppDiagnostics diagnostics;
  late List<({String fileName, Uint8List bytes})> saved;
  late String? clipboard;

  setUp(() {
    logger = AppLogger(sinks: [MemoryLogSink()]);
    fileSink = _MemoryFileSink();
    crashStore = _MemoryCrashStore();
    diagnostics = AppDiagnostics(
      directory: _noDisk,
      logger: logger,
      fileSink: fileSink,
      crashStore: crashStore,
      timings: OperationTimings(),
    );
    logger.addSink(fileSink);
    saved = [];
    clipboard = null;
  });

  Future<void> pumpCard(WidgetTester tester, {String? savePath}) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DiagnosticsSettingsCard(
              diagnostics: diagnostics,
              saveFile: ({required fileName, required bytes}) async {
                saved.add((fileName: fileName, bytes: bytes));
                return savePath;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows log size and crash summary', (tester) async {
    logger.info('app', 'one');
    await crashStore.add(
      CrashRecord(
        time: DateTime(2026, 11, 14, 21, 5),
        source: CrashSource.flutter,
        error: 'x',
        appVersion: '1.0.0+1',
      ),
    );
    await pumpCard(tester);

    expect(find.text('诊断与日志'), findsOneWidget);
    expect(
      find.text('日志 1.0 KB · 1 条崩溃记录（最近 2026-11-14 21:05）'),
      findsOneWidget,
    );
  });

  testWidgets('exports the redacted report through the file saver', (
    tester,
  ) async {
    logger.warning('transfer', 'GET /x?token=secret-value');
    await pumpCard(tester, savePath: '/tmp/report.txt');

    await tester.tap(find.byKey(const ValueKey('diagnostics-export')));
    await tester.pumpAndSettle();

    expect(saved, hasLength(1));
    expect(saved.single.fileName, startsWith('elysium-diagnostics-'));
    final text = utf8.decode(saved.single.bytes);
    expect(text, contains('token=<redacted>'));
    expect(text, isNot(contains('secret-value')));
    expect(text, contains('---- JSON ----'));
    expect(find.text('诊断包已导出：/tmp/report.txt'), findsOneWidget);
  });

  testWidgets('a cancelled export shows nothing', (tester) async {
    await pumpCard(tester);
    await tester.tap(find.byKey(const ValueKey('diagnostics-export')));
    await tester.pumpAndSettle();
    expect(saved, hasLength(1));
    expect(find.byKey(const ValueKey('diagnostics-message')), findsNothing);
  });

  testWidgets('copies the text report without JSON', (tester) async {
    logger.info('ktv', 'take saved');
    await pumpCard(tester);

    await tester.tap(find.byKey(const ValueKey('diagnostics-copy')));
    await tester.pumpAndSettle();

    expect(clipboard, contains('[ktv] take saved'));
    expect(clipboard, isNot(contains('---- JSON ----')));
    expect(find.text('诊断信息已复制，可直接粘贴到问题反馈中'), findsOneWidget);
  });

  testWidgets('clearing asks first and then removes records', (tester) async {
    logger.info('app', 'old');
    await crashStore.add(
      CrashRecord(
        time: DateTime(2026, 11, 14),
        source: CrashSource.platform,
        error: 'x',
        appVersion: '1.0.0+1',
      ),
    );
    await pumpCard(tester);

    await tester.tap(find.byKey(const ValueKey('diagnostics-clear')));
    await tester.pumpAndSettle();
    expect(find.text('清除诊断记录？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(fileSink.clears, 0);

    await tester.tap(find.byKey(const ValueKey('diagnostics-clear')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '清除'),
      ),
    );
    await tester.pumpAndSettle();

    expect(fileSink.clears, 1);
    expect(crashStore.crashes, isEmpty);
    expect(find.text('诊断记录已清除'), findsOneWidget);
    expect(find.textContaining('没有崩溃记录'), findsOneWidget);
  });

  testWidgets('switches change verbosity and crash storage', (tester) async {
    await pumpCard(tester);

    await tester.tap(find.byKey(const ValueKey('diagnostics-verbose')));
    await tester.pumpAndSettle();
    expect(diagnostics.verbose, isTrue);
    expect(logger.minimumLevel, LogLevel.debug);

    await tester.tap(find.byKey(const ValueKey('diagnostics-store-crashes')));
    await tester.pumpAndSettle();
    expect(diagnostics.storeCrashes, isFalse);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('diagnostics-store-crashes')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets('lists timing summaries with readable labels', (tester) async {
    await pumpCard(tester);
    expect(find.text('识别歌词或录制 KTV 后在这里查看耗时'), findsOneWidget);

    diagnostics.timings.record(
      'transcription.transcribe',
      const Duration(seconds: 90),
      mediaDuration: const Duration(minutes: 5),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('diagnostics-timings')));
    await tester.pumpAndSettle();

    expect(find.text('歌词识别'), findsOneWidget);
    expect(
      find.text('1 次 · 中位 1 分 30 秒 · 最长 1 分 30 秒 · 最近 1 分 30 秒 · 实时倍率 0.30'),
      findsOneWidget,
    );
  });

  group('formatting', () {
    test('durations', () {
      expect(
        formatDiagnosticsDuration(const Duration(milliseconds: 420)),
        '420 毫秒',
      );
      expect(
        formatDiagnosticsDuration(const Duration(milliseconds: 12400)),
        '12.4 秒',
      );
      expect(
        formatDiagnosticsDuration(const Duration(seconds: 125)),
        '2 分 5 秒',
      );
    });

    test('bytes', () {
      expect(formatDiagnosticsBytes(512), '512 B');
      expect(formatDiagnosticsBytes(1536), '1.5 KB');
      expect(formatDiagnosticsBytes(3 * 1024 * 1024), '3.0 MB');
    });

    test('summary with failures and no media', () {
      expect(
        describeOperationSummary(
          const OperationSummary(
            operation: 'ktv.startRecording',
            count: 2,
            failures: 1,
            median: Duration(milliseconds: 300),
            max: Duration(milliseconds: 500),
            last: Duration(milliseconds: 100),
            medianRealTimeFactor: null,
          ),
        ),
        '2 次 · 中位 300 毫秒 · 最长 500 毫秒 · 最近 100 毫秒 · 失败 1',
      );
    });
  });
}
