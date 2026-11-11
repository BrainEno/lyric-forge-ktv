import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/controllers/lyric_editor_document_controller.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_review_proposal.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_input.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/reference_alignment_dialog.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_file_export_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/lyric_editor_dependencies.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/screens/lyric_editor_screen.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/memory_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';

void main() {
  testWidgets('delayed alignment discards edits and blocks a second run', (
    tester,
  ) async {
    final pending = Completer<List<ForcedAlignedSpan>>();
    var calls = 0;
    final editor = await _openEditor(tester, ({
      required audioPath,
      required text,
      required language,
      required audioDuration,
    }) {
      calls++;
      return pending.future;
    });
    await _startAlignment(tester);
    expect(calls, 1);
    await tester.tap(find.byIcon(Icons.spellcheck_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('智能校对 V2'), findsNothing);
    editor.updateLine(
      0,
      editor.document!.lines.single.copyWith(text: 'New manual edit'),
    );
    await tester.pump();
    pending.complete([]);
    await tester.pumpAndSettle();
    expect(editor.document!.lines.single.text, 'New manual edit');
    expect(editor.canUndo, isTrue);
    expect(find.textContaining('原提案已丢弃'), findsOneWidget);
    expect(find.text('智能校对提案复核'), findsNothing);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit then undo still invalidates a delayed result', (
    tester,
  ) async {
    final pending = Completer<List<ForcedAlignedSpan>>();
    final editor = await _openEditor(
      tester,
      ({
        required audioPath,
        required text,
        required language,
        required audioDuration,
      }) => pending.future,
    );
    await _startAlignment(tester);
    editor.updateLine(
      0,
      editor.document!.lines.single.copyWith(text: 'temporary'),
    );
    editor.undo();
    pending.complete([]);
    await tester.pumpAndSettle();
    expect(editor.document!.lines.single.text, 'Human lyric');
    expect(editor.canRedo, isTrue);
    expect(find.textContaining('原提案已丢弃'), findsOneWidget);
    expect(find.text('智能校对提案复核'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changes while review is open block application', (tester) async {
    final editor = await _openEditor(tester, _emptyAlignment);
    await _startAlignment(tester);
    expect(find.text('智能校对提案复核'), findsOneWidget);
    editor.updateLine(
      0,
      editor.document!.lines.single.copyWith(text: 'Changed during review'),
    );
    await tester.pump();
    Navigator.of(tester.element(find.text('智能校对提案复核'))).pop(
      LyricProofreadV2Selection(
        acceptedProposalIndices: {0},
        restoredDraftIndices: {},
      ),
    );
    await tester.pumpAndSettle();
    expect(editor.document!.lines.single.text, 'Changed during review');
    expect(editor.canUndo, isTrue);
    expect(find.textContaining('原提案已丢弃'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late alignment after disposal does not access disposed state', (
    tester,
  ) async {
    final pending = Completer<List<ForcedAlignedSpan>>();
    await _openEditor(
      tester,
      ({
        required audioPath,
        required text,
        required language,
        required audioDuration,
      }) => pending.future,
    );
    await _startAlignment(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.complete([]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('智能校对提案复核'), findsNothing);
  });

  testWidgets('a change in the options dialog aborts before running', (
    tester,
  ) async {
    var calls = 0;
    final editor = await _openEditor(tester, ({
      required audioPath,
      required text,
      required language,
      required audioDuration,
    }) async {
      calls++;
      return [];
    });
    await tester.tap(find.byIcon(Icons.spellcheck_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('智能校对 V2'));
    await tester.pumpAndSettle();
    editor.setLineReviewed(0, reviewed: true);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.textContaining('原提案已丢弃'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unchanged reference proposal applies and remains undoable', (
    tester,
  ) async {
    final editor = await _openEditor(tester, _emptyAlignment);
    await tester.tap(find.byIcon(Icons.spellcheck_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('智能校对 V2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('参考歌词优先'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    editor.select(null);
    Navigator.of(tester.element(find.byType(ReferenceAlignmentDialog))).pop(
      ReferenceLyricInput(
        lines: [
          ReferenceLyricLine(
            text: 'Human lyric',
            startTime: const Duration(milliseconds: 500),
            endTime: const Duration(milliseconds: 1500),
          ),
        ],
        timed: true,
        format: 'lrc',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('智能校对提案复核'), findsOneWidget);
    Navigator.of(tester.element(find.text('智能校对提案复核'))).pop(
      LyricProofreadV2Selection(
        acceptedProposalIndices: {0},
        restoredDraftIndices: {},
      ),
    );
    await tester.pumpAndSettle();
    expect(
      editor.document!.lines.single.startTime,
      const Duration(milliseconds: 500),
    );
    expect(editor.alignmentSnapshot, isNotNull);
    expect(editor.undo().applied, isTrue);
    expect(editor.document!.lines.single.startTime, Duration.zero);
    expect(editor.redo().applied, isTrue);
    expect(
      editor.document!.lines.single.startTime,
      const Duration(milliseconds: 500),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'editing another row while alignment runs preserves it and allows retry',
    (tester) async {
      final firstRun = Completer<List<ForcedAlignedSpan>>();
      var calls = 0;
      final editor = await _openEditor(tester, ({
        required audioPath,
        required text,
        required language,
        required audioDuration,
      }) {
        calls++;
        return calls == 1 ? firstRun.future : Future.value([]);
      }, initialDocument: _twoLineDocument());
      await _startAlignment(tester);
      expect(calls, 1);
      expect(editor.selectedLineIndex, 0);
      editor.updateLine(
        1,
        editor.document!.lines[1].copyWith(text: 'Second line edited'),
      );
      await tester.pump();
      firstRun.complete([]);
      await tester.pumpAndSettle();
      expect(editor.document!.lines.map((line) => line.text), [
        'Human lyric',
        'Second line edited',
      ]);
      expect(editor.canUndo, isTrue);
      expect(find.textContaining('原提案已丢弃'), findsOneWidget);
      expect(find.text('智能校对提案复核'), findsNothing);
      await _startAlignment(tester);
      expect(calls, 2);
      expect(find.text('智能校对提案复核'), findsOneWidget);
      expect(editor.document!.lines[1].text, 'Second line edited');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an edit to another row invalidates a real reference proposal', (
    tester,
  ) async {
    final editor = await _openEditor(
      tester,
      _emptyAlignment,
      initialDocument: _twoLineDocument(),
    );
    await tester.tap(find.byIcon(Icons.spellcheck_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('智能校对 V2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('参考歌词优先'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(ReferenceAlignmentDialog))).pop(
      ReferenceLyricInput(
        lines: [
          ReferenceLyricLine(
            text: 'Human lyric',
            startTime: const Duration(milliseconds: 500),
            endTime: const Duration(milliseconds: 1500),
          ),
          ReferenceLyricLine(
            text: 'Second line',
            startTime: const Duration(milliseconds: 2100),
            endTime: const Duration(milliseconds: 2900),
          ),
        ],
        timed: true,
        format: 'lrc',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('智能校对提案复核'), findsOneWidget);
    editor.updateLine(
      1,
      editor.document!.lines[1].copyWith(text: 'My second line'),
    );
    await tester.pump();
    Navigator.of(tester.element(find.text('智能校对提案复核'))).pop(
      LyricProofreadV2Selection(
        acceptedProposalIndices: {0, 1},
        restoredDraftIndices: {},
      ),
    );
    await tester.pumpAndSettle();
    expect(editor.document!.lines[0].startTime, Duration.zero);
    expect(editor.document!.lines[1].text, 'My second line');
    expect(editor.alignmentSnapshot, isNull);
    expect(editor.undo().applied, isTrue);
    expect(editor.document!.lines[1].text, 'Second line');
    expect(editor.redo().applied, isTrue);
    expect(editor.document!.lines[1].text, 'My second line');
    expect(find.textContaining('原提案已丢弃'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reloading while alignment runs discards the old song result', (
    tester,
  ) async {
    final pending = Completer<List<ForcedAlignedSpan>>();
    final editor = await _openEditor(
      tester,
      ({
        required audioPath,
        required text,
        required language,
        required audioDuration,
      }) => pending.future,
      initialDocument: _twoLineDocument(),
    );
    await _startAlignment(tester);
    editor.load(_document('Reloaded lyric'));
    await tester.pump();
    pending.complete([]);
    await tester.pumpAndSettle();
    expect(editor.document!.lines.single.text, 'Reloaded lyric');
    expect(editor.canUndo, isFalse);
    expect(find.text('智能校对提案复核'), findsNothing);
    expect(find.textContaining('原提案已丢弃'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('busy alignment explains retry and never changes lyrics', (
    tester,
  ) async {
    final repository = MemoryProjectRepository();
    var project = await repository.createProject(name: 'Song');
    project = await repository.updateProject(
      project.copyWith(
        lyricDocument: _document('Human lyric'),
        audioAsset: const AudioAsset(
          originalPath: 'song.wav',
          format: 'wav',
          duration: Duration(seconds: 3),
        ),
      ),
    );
    var calls = 0;
    final dependencies = LyricEditorDependencies(
      projectRepository: repository,
      playbackSession: _FakePlaybackSession(),
      audioPlayer: _FakeAudioPlayer(),
      lyricFileExport: _FakeLyricFileExport(),
      lyricFileImport: _FakeLyricFileImport(),
      forcedAlignmentRunner:
          ({
            required audioPath,
            required text,
            required language,
            required audioDuration,
          }) async {
            calls++;
            throw const ForcedAlignmentResourceBusyException();
          },
    );
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: LyricEditorScreen(
          projectId: project.id,
          dependencies: dependencies,
        ),
      ),
    );
    await _settleAndAssertNoFrameworkException(tester, 'initial render');
    await tester.tap(find.byIcon(Icons.spellcheck_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('智能校对 V2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ASR 优先'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('forced_alignment_review_toggle')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('识别资源正忙，请等待其他任务结束后重试'), findsOneWidget);
    expect(find.text('智能校对提案复核'), findsNothing);
    expect(
      (await repository.getProjectById(
        project.id,
      ))!.lyricDocument!.lines.single.text,
      'Human lyric',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'stale editor save is rejected, edits remain, and explicit overwrite preserves new metadata',
    (tester) async {
      final repository = MemoryProjectRepository();
      var project = await repository.createProject(name: 'Song');
      project = await repository.updateProject(
        project.copyWith(lyricDocument: _document('Original lyric')),
      );
      final dependencies = LyricEditorDependencies(
        projectRepository: repository,
        playbackSession: _FakePlaybackSession(),
        audioPlayer: _FakeAudioPlayer(),
        lyricFileExport: _FakeLyricFileExport(),
        lyricFileImport: _FakeLyricFileImport(),
        forcedAlignmentRunner: _emptyAlignment,
      );

      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: LyricEditorScreen(
            projectId: project.id,
            dependencies: dependencies,
          ),
        ),
      );
      await _settleAndAssertNoFrameworkException(tester, 'initial render');
      final lyricField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '歌词文本',
      );
      if (lyricField.evaluate().isEmpty) {
        // If the editor has no default selection, choose the row explicitly.
        // The same text may also be rendered in the inspector once selected.
        await tester.tap(find.text('Original lyric').first);
        await _settleAndAssertNoFrameworkException(tester, 'select lyric');
      }
      expect(lyricField, findsOneWidget);
      tester.widget<TextField>(lyricField).onChanged?.call('Local edit');
      await _settleAndAssertNoFrameworkException(tester, 'edit lyric');
      expect(find.byIcon(Icons.save_rounded), findsOneWidget);

      final backgroundUpdate = await repository.updateProject(
        project.copyWith(
          lyricDocument: _document('Background transcription'),
          currentStage: ProcessingStage.transcriptionComplete,
          metadata: const {
            'transcription': {'engine': 'qwen'},
          },
        ),
      );

      final saveButton = find.byIcon(Icons.save_rounded);
      expect(saveButton, findsOneWidget);
      await tester.tap(saveButton);
      await _settleAndAssertNoFrameworkException(tester, 'reject stale save');
      expect(find.text('工程已在其他位置更新'), findsOneWidget);
      expect(find.textContaining('你的编辑仍保留'), findsOneWidget);

      final afterRejectedSave = await repository.getProjectById(project.id);
      expect(
        afterRejectedSave?.lyricDocument?.lines.single.text,
        'Background transcription',
      );
      expect(afterRejectedSave?.metadata['transcription'], {'engine': 'qwen'});

      await tester.tap(find.text('继续编辑'));
      await _settleAndAssertNoFrameworkException(tester, 'continue editing');
      expect(
        tester.widget<TextField>(lyricField).controller?.text,
        'Local edit',
      );

      await tester.tap(find.widgetWithText(FilledButton, '保存修改'));
      await _settleAndAssertNoFrameworkException(tester, 'retry save');
      await tester.tap(find.text('用当前歌词覆盖最新版'));
      await _settleAndAssertNoFrameworkException(tester, 'confirm overwrite');

      final explicitlyOverwritten = await repository.getProjectById(project.id);
      expect(
        explicitlyOverwritten?.lyricDocument?.lines.single.text,
        'Local edit',
      );
      expect(explicitlyOverwritten?.metadata['transcription'], {
        'engine': 'qwen',
      });
      expect(explicitlyOverwritten?.revision, backgroundUpdate.revision + 1);
    },
  );
}

Future<LyricEditorDocumentController> _openEditor(
  WidgetTester tester,
  ForcedAlignmentRunner runner, {
  LyricDocument? initialDocument,
}) async {
  final repository = MemoryProjectRepository();
  var project = await repository.createProject(name: 'Song');
  project = await repository.updateProject(
    project.copyWith(
      lyricDocument: initialDocument ?? _document('Human lyric'),
      audioAsset: const AudioAsset(
        originalPath: 'song.wav',
        format: 'wav',
        duration: Duration(seconds: 3),
      ),
    ),
  );
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: LyricEditorScreen(
        projectId: project.id,
        dependencies: LyricEditorDependencies(
          projectRepository: repository,
          playbackSession: _FakePlaybackSession(),
          audioPlayer: _FakeAudioPlayer(),
          lyricFileExport: _FakeLyricFileExport(),
          lyricFileImport: _FakeLyricFileImport(),
          forcedAlignmentRunner: runner,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final field = find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == '歌词文本',
  );
  return Provider.of<LyricEditorDocumentController>(
    tester.element(field),
    listen: false,
  );
}

Future<void> _startAlignment(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.spellcheck_rounded).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('智能校对 V2'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('ASR 优先'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey('forced_alignment_review_toggle')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('继续'));
  await tester.pumpAndSettle();
}

Future<void> _settleAndAssertNoFrameworkException(
  WidgetTester tester,
  String operation,
) async {
  await tester.pumpAndSettle();
  final exception = tester.takeException();
  if (exception != null) {
    fail('Unhandled Flutter exception after $operation: $exception');
  }
}

LyricDocument _document(String text) => LyricDocument(
  language: 'en',
  lines: [
    LyricLine(
      text: text,
      startTime: Duration.zero,
      endTime: const Duration(seconds: 2),
    ),
  ],
);

LyricDocument _twoLineDocument() => LyricDocument(
  language: 'en',
  lines: [
    ..._document('Human lyric').lines,
    const LyricLine(
      text: 'Second line',
      startTime: Duration(milliseconds: 2100),
      endTime: Duration(milliseconds: 2900),
    ),
  ],
);

Future<List<ForcedAlignedSpan>> _emptyAlignment({
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

class _FakeLyricFileImport implements LyricFileImportService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
