import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_draft_health_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_export_encoder.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_file_export_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/controllers/lyric_export_coordinator.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_batch_text_edit.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_export_dialog.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_proofread_menu_button.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_recognition_summary_card.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_timeline_repair_dialog.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_timing_shift_dialog.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';

// Every lyric below is synthetic text written for these tests.
LyricLine _line(String text, int startMs, int endMs, {String? id}) => LyricLine(
  text: text,
  startTime: Duration(milliseconds: startMs),
  endTime: Duration(milliseconds: endMs),
  id: id,
);

LyricDocument _doc(List<LyricLine> lines) =>
    LyricDocument(language: 'zh', lines: lines);

List<(int, int)> _spans(LyricDocument document) => [
  for (final l in document.lines)
    (l.startTime.inMilliseconds, l.endTime.inMilliseconds),
];

/// Pumps a button that opens a dialog through [open] and returns a getter
/// for its result.
Future<T? Function()> _openDialog<T>(
  WidgetTester tester,
  Future<T?> Function(BuildContext context) open,
) async {
  T? result;
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async => result = await open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => result;
}

FilledButton _confirm(WidgetTester tester, String key) =>
    tester.widget<FilledButton>(find.byKey(ValueKey(key)));

void main() {
  group('LyricTimelineRepairDialog', () {
    final faulty = _doc([
      _line('第一句', 10000, 13000, id: 'a'),
      _line('第二句', 50000, 53000, id: 'b'),
      _line('第三句', 14000, 18500, id: 'c'),
      _line('第四句', 18000, 21000, id: 'd'),
    ]);

    Future<LyricBatchTextEdit? Function()> open(
      WidgetTester tester,
      LyricDocument document,
    ) => _openDialog(
      tester,
      (context) => showLyricTimelineRepairDialog(
        context,
        document: document,
        protectedIndices: const {},
      ),
    );

    testWidgets('pre-selects rule-based repairs and applies them', (
      tester,
    ) async {
      final result = await open(tester, faulty);
      expect(find.text('可自动修复 2 行，需要人工定点 0 行。'), findsOneWidget);
      // The re-slot is a guess and must be opted into.
      expect(find.text('修复 1 行'), findsOneWidget);
      expect(find.textContaining('仍有'), findsOneWidget);
      expect(find.textContaining('请先试听确认'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('timeline_repair_confirm')));
      await tester.pumpAndSettle();

      final edit = result()!;
      expect(edit.label, LyricTimelineRepairStrings.actionTitle);
      expect(_spans(edit.document), [
        (10000, 13000),
        (50000, 53000),
        (14000, 18000),
        (18000, 21000),
      ]);
      expect(edit.selectedLineIndex, 2);
      expect(edit.message, contains('未写入磁盘'));
    });

    testWidgets('select all also re-slots the out-of-order row', (
      tester,
    ) async {
      final result = await open(tester, faulty);
      await tester.tap(
        find.byKey(const ValueKey('timeline_repair_toggle_all')),
      );
      await tester.pumpAndSettle();
      expect(find.text('修复 2 行'), findsOneWidget);
      expect(find.text('按当前勾选应用后，时间轴不再有冲突。'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('timeline_repair_confirm')));
      await tester.pumpAndSettle();
      expect(_spans(result()!.document)[1], (13000, 14000));
    });

    testWidgets('lists what cannot be repaired by rule', (tester) async {
      await open(
        tester,
        _doc([
          _line('第一句', 10000, 12000),
          _line('第二句', 20000, 22000),
          _line('第三句', 15000, 17000),
          _line('第四句', 30000, 32000),
        ]),
      );
      expect(find.text('需要人工定点'), findsOneWidget);
      expect(find.byKey(const ValueKey('timeline_manual_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('timeline_manual_1')), findsOneWidget);
      expect(find.text('没有可自动修复的行'), findsOneWidget);
      expect(_confirm(tester, 'timeline_repair_confirm').onPressed, isNull);
    });

    testWidgets('a clean timeline says so', (tester) async {
      await open(
        tester,
        _doc([_line('第一句', 0, 3000), _line('第二句', 4000, 6000)]),
      );
      expect(find.text('时间轴没有发现问题。'), findsOneWidget);
      expect(find.textContaining('没有关联音频时长'), findsOneWidget);
    });
  });

  group('LyricTimingShiftDialog', () {
    final song = _doc([
      _line('第一句', 0, 2000),
      _line('第二句', 3000, 5000),
      _line('第三句', 6000, 8000),
    ]);

    Future<LyricBatchTextEdit? Function()> open(
      WidgetTester tester, {
      Duration? playhead,
    }) => _openDialog(
      tester,
      (context) => showLyricTimingShiftDialog(
        context,
        document: song,
        selectedIndex: 1,
        playhead: playhead,
      ),
    );

    testWidgets('starts from the selected row and needs a non-zero offset', (
      tester,
    ) async {
      final result = await open(tester);
      expect(find.text('当前设置不会改变任何时间。'), findsOneWidget);
      expect(_confirm(tester, 'timing_shift_confirm').onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('timing_shift_nudge_1000')));
      await tester.pumpAndSettle();
      expect(find.textContaining('将调整 2 行'), findsOneWidget);
      expect(find.text('调整 2 行'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('timing_shift_confirm')));
      await tester.pumpAndSettle();
      final edit = result()!;
      expect(_spans(edit.document), [(0, 2000), (4000, 6000), (7000, 9000)]);
      expect(edit.selectedLineIndex, 1);
      expect(edit.label, LyricTimingShiftStrings.actionTitle);
    });

    testWidgets('typed offsets, the whole-song scope and bad input', (
      tester,
    ) async {
      final result = await open(tester);
      await tester.tap(find.byKey(const ValueKey('timing_shift_scope_all')));
      await tester.enterText(
        find.byKey(const ValueKey('timing_shift_offset')),
        'abc',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('偏移量格式不正确'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('timing_shift_offset')),
        '0.5',
      );
      await tester.pumpAndSettle();
      expect(find.text('调整 3 行'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('timing_shift_confirm')));
      await tester.pumpAndSettle();
      expect(_spans(result()!.document), [
        (500, 2500),
        (3500, 5500),
        (6500, 8500),
      ]);
    });

    testWidgets('aligns the first row of the range to the paused playhead', (
      tester,
    ) async {
      final result = await open(
        tester,
        playhead: const Duration(milliseconds: 9000),
      );
      await tester.tap(
        find.byKey(const ValueKey('timing_shift_offset_playhead')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('timing_shift_confirm')));
      await tester.pumpAndSettle();
      expect(_spans(result()!.document).sublist(1), [
        (9000, 11000),
        (12000, 14000),
      ]);
    });

    testWidgets('two-point calibration stretches between the anchors', (
      tester,
    ) async {
      final result = await open(tester);
      await tester.tap(find.text('两点校准'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('timing_shift_to_time')),
        '0:07.50',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('速度系数 1.5000'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('timing_shift_confirm')));
      await tester.pumpAndSettle();
      expect(_spans(result()!.document), [
        (0, 2000),
        (3000, 6000),
        (7500, 10500),
      ]);
    });
  });

  group('LyricExportDialog', () {
    final overlapping = _doc([
      _line('第一句', 1000, 3500),
      _line('第二句', 3000, 5000),
      _line('', 6000, 6500),
      _line('第三句', 10000, 12000),
    ]);

    Future<LyricExportRequest? Function()> open(WidgetTester tester) =>
        _openDialog(
          tester,
          (context) => showLyricExportDialog(context, document: overlapping),
        );

    String preview(WidgetTester tester) => tester
        .widget<SelectableText>(
          find.descendant(
            of: find.byKey(const ValueKey('lyric_export_preview')),
            matching: find.byType(SelectableText),
          ),
        )
        .data!;

    testWidgets('previews LRC with end markers and warns about the timeline', (
      tester,
    ) async {
      await open(tester);
      expect(preview(tester), contains('[re:Elysium Player]'));
      expect(
        preview(tester),
        endsWith('[00:05.000]\n[00:10.000]第三句\n[00:12.000]'),
      );
      expect(find.textContaining('行时间轴存在问题'), findsOneWidget);
      expect(find.text('1 个空行不会导出。'), findsOneWidget);
      expect(find.text('导出 .lrc'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('lyric_export_end_markers')),
      );
      await tester.tap(find.byKey(const ValueKey('lyric_export_end_markers')));
      await tester.pumpAndSettle();
      expect(preview(tester), isNot(contains('[00:12.000]')));
    });

    testWidgets('switching format updates the preview and the result', (
      tester,
    ) async {
      final result = await open(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('lyric_export_format_srt')),
      );
      await tester.tap(find.byKey(const ValueKey('lyric_export_format_srt')));
      await tester.pumpAndSettle();
      expect(preview(tester), contains('00:00:01,000 --> 00:00:03,000'));
      expect(find.text('导出 .srt'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('lyric_export_format_plainText')),
      );
      await tester.tap(
        find.byKey(const ValueKey('lyric_export_format_plainText')),
      );
      await tester.pumpAndSettle();
      expect(preview(tester), '第一句\n第二句\n\n第三句');
      // Plain text has no timing, so the timeline warning is irrelevant.
      expect(find.textContaining('行时间轴存在问题'), findsNothing);
      expect(
        find.byKey(const ValueKey('lyric_export_paragraphs')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('lyric_export_confirm')));
      await tester.pumpAndSettle();
      expect(result()!.format, LyricExportFormat.plainText);
      expect(result()!.options.paragraphsAtPauses, isTrue);
    });
  });

  group('LyricExportCoordinator', () {
    testWidgets('exports the chosen format and remembers it', (tester) async {
      final service = _RecordingExportService();
      final coordinator = LyricExportCoordinator();
      final project = ProjectManifest(
        id: 'p1',
        name: '测试歌',
        artist: '测试歌手',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      await _openDialog<bool>(tester, (context) async {
        await coordinator.export(
          context,
          service: service,
          project: project,
          document: _doc([_line('第一句', 0, 2000)]),
        );
        return true;
      });
      await tester.tap(find.byKey(const ValueKey('lyric_export_format_vtt')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lyric_export_confirm')));
      await tester.pumpAndSettle();

      expect(service.calls, hasLength(1));
      expect(service.calls.single.format, LyricExportFormat.vtt);
      expect(service.calls.single.suggestedFileName, '测试歌');
      expect(service.calls.single.metadata.artist, '测试歌手');
      expect(coordinator.lastFormat, LyricExportFormat.vtt);
      expect(find.textContaining('WebVTT 字幕已导出：/tmp/song.vtt'), findsOneWidget);
    });
  });

  testWidgets('the proofreading menu offers both timing tools', (tester) async {
    final fired = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: LyricProofreadMenuButton(
              onTimelineRepair: () => fired.add('repair'),
              onTimingShift: () => fired.add('shift'),
            ),
          ),
        ),
      ),
    );
    for (final entry in {
      LyricTimelineRepairStrings.actionTitle: 'repair',
      LyricTimingShiftStrings.actionTitle: 'shift',
    }.entries) {
      await tester.tap(find.text(LyricProofreadMenuButton.label));
      await tester.pumpAndSettle();
      if (find.text(entry.key).evaluate().isEmpty) {
        await tester.tap(find.text(LyricProofreadGroup.checks.label));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(fired.last, entry.value);
    }
  });

  test('a timeline hint opens the timeline check last', () {
    final hints = LyricRecognitionSummaryCard.healthHints(
      const LyricDraftHealth(
        captionRows: 1,
        repetitionGroups: 0,
        longLines: 0,
        fragments: 0,
        timelineRows: 3,
      ),
    );
    expect(hints.map((h) => h.tool), [
      LyricBatchTextTool.textCleanup,
      LyricBatchTextTool.timelineRepair,
    ]);
    expect(hints.last.label, '时间轴问题 3 行');
  });
}

class _ExportCall {
  final LyricExportFormat format;
  final String suggestedFileName;
  final LyricExportMetadata metadata;

  const _ExportCall(this.format, this.suggestedFileName, this.metadata);
}

class _RecordingExportService implements LyricFileExportService {
  final List<_ExportCall> calls = [];

  @override
  Future<String?> exportFile(
    LyricDocument document, {
    required LyricExportFormat format,
    required String suggestedFileName,
    LyricExportOptions options = const LyricExportOptions(),
    LyricExportMetadata metadata = const LyricExportMetadata(),
  }) async {
    calls.add(_ExportCall(format, suggestedFileName, metadata));
    return '/tmp/song.${format.extension}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
