import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/local_lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_file_export_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_review_decision_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/controllers/lyric_editor_document_controller.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/lyric_editor_dependencies.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/screens/lyric_editor_screen.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_batch_selection_bar.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_batch_shift_dialog.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_review_row.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/memory_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

/// D-066: choosing several rows in the editor and editing them together.
void main() {
  Finder row(String text) => find.widgetWithText(LyricReviewRow, text);

  Future<LyricEditorDocumentController> open(
    WidgetTester tester, {
    Size size = const Size(1600, 900),
    double textScale = 1,
  }) async {
    final repository = MemoryProjectRepository();
    var project = await repository.createProject(name: 'Song');
    project = await repository.updateProject(
      project.copyWith(
        lyricDocument: LyricDocument(
          language: 'zh',
          lines: [
            for (var index = 0; index < 5; index++)
              LyricLine(
                text: 'line ${index + 1}',
                startTime: Duration(seconds: index * 4 + 1),
                endTime: Duration(seconds: index * 4 + 3),
              ),
          ],
        ),
        audioAsset: const AudioAsset(
          originalPath: 'song.wav',
          format: 'wav',
          duration: Duration(seconds: 60),
        ),
      ),
    );
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: LyricEditorScreen(
          projectId: project.id,
          dependencies: LyricEditorDependencies(
            projectRepository: repository,
            playbackSession: _FakePlaybackSession(),
            audioPlayer: _FakeAudioPlayer(),
            lyricFileExport: _FakeLyricFileExport(),
            lyricFileImport: LocalLyricFileImportService(),
            forcedAlignmentRunner: _noAlignment,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return Provider.of<LyricEditorDocumentController>(
      tester.element(find.byType(LyricReviewRow).first),
      listen: false,
    );
  }

  List<String> texts(LyricEditorDocumentController editor) => [
    for (final line in editor.document!.lines) line.text,
  ];

  testWidgets('多选, choose two neighbours, merge, then undo from the notice', (
    tester,
  ) async {
    final editor = await open(tester);
    await tester.tap(find.byKey(LyricBatchActionBar.startKey));
    await tester.pumpAndSettle();
    expect(find.byKey(LyricBatchActionBar.barKey), findsOneWidget);
    expect(find.text(LyricBatchStrings.nothingChosen), findsOneWidget);

    await tester.tap(row('line 2'));
    await tester.tap(row('line 3'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 行'), findsOneWidget);

    await tester.tap(find.byKey(LyricBatchActionBar.mergeKey));
    await tester.pumpAndSettle();
    expect(texts(editor), ['line 1', 'line 2 line 3', 'line 4', 'line 5']);
    expect(find.text('已把第 2–3 行合并成一行'), findsOneWidget);
    expect(find.byKey(LyricBatchActionBar.barKey), findsNothing);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(editor.document!.lines, hasLength(5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ctrl+click and Shift+click, then mark them reviewed', (
    tester,
  ) async {
    final editor = await open(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(row('line 2'));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    // line 1 was selected when the editor opened.
    expect(find.text('已选 2 行'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(row('line 4'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(editor.batchSelection, [1, 2, 3]);

    await tester.tap(find.byKey(LyricBatchActionBar.reviewKey));
    await tester.pumpAndSettle();
    expect(
      const LyricReviewDecisionService().reviewedIndices(editor.document!),
      {1, 2, 3},
    );
    expect(find.text('已将 3 行标记为已复核'), findsOneWidget);
    expect(editor.batchMode, isFalse);
  });

  testWidgets('shift two rows apart; the rows stay chosen', (tester) async {
    final editor = await open(tester);
    editor
      ..startBatch(0)
      ..toggleBatchLine(2);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(LyricBatchActionBar.shiftKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(LyricBatchShiftDialog.nudgeKey(1000)));
    await tester.pump();
    await tester.tap(find.byKey(LyricBatchShiftDialog.confirmKey));
    await tester.pumpAndSettle();

    final lines = editor.document!.lines;
    expect(lines[0].startTime, const Duration(seconds: 2));
    expect(lines[1].startTime, const Duration(seconds: 5));
    expect(lines[2].startTime, const Duration(seconds: 10));
    expect(find.text('已把 2 行的时间推后 1.00 秒'), findsOneWidget);
    expect(find.text('已选 2 行'), findsOneWidget);
  });

  testWidgets('delete the chosen rows, and Esc leaves batch mode', (
    tester,
  ) async {
    final editor = await open(tester);
    editor.selectAllBatch([3, 4]);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(LyricBatchActionBar.deleteKey));
    await tester.pumpAndSettle();
    expect(texts(editor), ['line 1', 'line 2', 'line 3']);
    expect(find.text('已删除 2 行'), findsOneWidget);

    editor.startBatch(1);
    await tester.pumpAndSettle();
    expect(find.byKey(LyricBatchActionBar.barKey), findsOneWidget);
    // A tap chooses a row and gives the list the keyboard.
    await tester.tap(row('line 1'));
    await tester.pumpAndSettle();
    expect(editor.batchSelection, [0, 1]);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(editor.batchMode, isFalse);
    expect(find.byKey(LyricBatchActionBar.barKey), findsNothing);
  });

  testWidgets('back leaves batch mode before it leaves the editor', (
    tester,
  ) async {
    final editor = await open(tester);
    editor.startBatch(0);
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(editor.batchMode, isFalse);
    expect(find.byType(LyricEditorScreen), findsOneWidget);
  });

  testWidgets('a phone: long press starts choosing, the bar fits', (
    tester,
  ) async {
    final editor = await open(tester, size: const Size(390, 844));
    // On a phone the times sit under the text; press the text itself.
    await tester.longPress(find.text('line 2'));
    await tester.pumpAndSettle();
    expect(editor.batchSelection, [1]);
    expect(find.byKey(LyricBatchActionBar.barKey), findsOneWidget);

    // In batch mode a tap chooses instead of opening the row's sheet.
    await tester.tap(find.text('line 3'));
    await tester.pumpAndSettle();
    expect(editor.batchSelection, [1, 2]);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<List<ForcedAlignedSpan>> _noAlignment({
  required String audioPath,
  required String text,
  required String language,
  required Duration audioDuration,
}) async => const [];

class _FakeAudioPlayer implements AudioPlayerService {
  @override
  PlaybackState get currentState => const PlaybackState.idle();

  @override
  Stream<PlaybackState> get stateStream => const Stream.empty();

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlaybackSession implements PlaybackSessionService {
  @override
  PlaybackSessionState get currentState => const PlaybackSessionState();

  @override
  Stream<PlaybackSessionState> get stateStream => const Stream.empty();

  @override
  PlaybackState get playbackState => const PlaybackState.idle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLyricFileExport implements LyricFileExportService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
