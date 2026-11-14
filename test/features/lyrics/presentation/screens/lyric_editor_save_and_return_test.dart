import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/local_lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_file_export_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/controllers/lyric_editor_document_controller.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/lyric_editor_dependencies.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/screens/lyric_editor_screen.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/memory_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';

/// Issue #438: "保存并返回" must wait for the write to succeed. Failures,
/// conflicts and edits made while the write is pending keep the editor open
/// with its draft instead of popping past an unsaved result.
void main() {
  testWidgets('save and return waits for the pending write before leaving', (
    tester,
  ) async {
    final harness = await _Harness.open(tester);
    harness.repository.gate = Completer<void>();
    harness.editLine(tester, 'edited while leaving');

    await harness.requestBack(tester);
    await tester.tap(find.text('保存并返回'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(harness.repository.writes, 1);
    expect(find.byType(LyricEditorScreen), findsOneWidget);
    expect(find.text('正在保存…'), findsOneWidget);

    harness.repository.gate!.complete();
    await tester.pumpAndSettle();

    expect(find.byType(LyricEditorScreen), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(await harness.savedText(), 'edited while leaving');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed write keeps the editor, the draft, and an error', (
    tester,
  ) async {
    final harness = await _Harness.open(tester);
    harness.repository.failure = const FileSystemException('disk full');
    final editor = harness.editLine(tester, 'unsaved draft');

    await harness.requestBack(tester);
    await tester.tap(find.text('保存并返回'));
    await tester.pumpAndSettle();

    expect(find.byType(LyricEditorScreen), findsOneWidget);
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(find.textContaining('当前编辑仍保留'), findsOneWidget);
    expect(editor.hasChanges, isTrue);
    expect(editor.document!.lines.single.text, 'unsaved draft');
    expect(await harness.savedText(), 'Human lyric');

    // Retrying after the storage problem clears saves and leaves once.
    harness.repository.failure = null;
    await harness.requestBack(tester);
    await tester.tap(find.text('保存并返回'));
    await tester.pumpAndSettle();
    expect(find.byType(LyricEditorScreen), findsNothing);
    expect(await harness.savedText(), 'unsaved draft');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a conflict kept for editing stays on the editor', (
    tester,
  ) async {
    final harness = await _Harness.open(tester);
    final editor = harness.editLine(tester, 'local edit');
    await harness.changeProjectElsewhere();

    await harness.requestBack(tester);
    await tester.tap(find.text('保存并返回'));
    await tester.pumpAndSettle();

    expect(find.text('工程已在其他位置更新'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('继续编辑'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LyricEditorScreen), findsOneWidget);
    expect(editor.hasChanges, isTrue);
    expect(editor.document!.lines.single.text, 'local edit');
    expect(await harness.savedText(), 'changed elsewhere');
    expect(tester.takeException(), isNull);
  });

  testWidgets('reloading the latest version after a conflict does not leave', (
    tester,
  ) async {
    final harness = await _Harness.open(tester);
    final editor = harness.editLine(tester, 'local edit');
    await harness.changeProjectElsewhere();

    await harness.requestBack(tester);
    await tester.tap(find.text('保存并返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重新载入最新版'));
    await tester.pumpAndSettle();

    expect(find.byType(LyricEditorScreen), findsOneWidget);
    expect(editor.hasChanges, isFalse);
    expect(editor.document!.lines.single.text, 'changed elsewhere');
    expect(tester.takeException(), isNull);
  });

  testWidgets('overwriting after a conflict saves and leaves exactly once', (
    tester,
  ) async {
    final harness = await _Harness.open(tester);
    harness.editLine(tester, 'local wins');
    await harness.changeProjectElsewhere();

    await harness.requestBack(tester);
    await tester.tap(find.text('保存并返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('用当前歌词覆盖最新版'));
    await tester.pumpAndSettle();

    expect(find.byType(LyricEditorScreen), findsNothing);
    // The home route below the editor must survive: popping twice would
    // remove it and leave an empty navigator.
    expect(find.text('home'), findsOneWidget);
    expect(await harness.savedText(), 'local wins');
    expect(tester.takeException(), isNull);
  });

  testWidgets('back requests during a pending save neither ask nor pop twice', (
    tester,
  ) async {
    final harness = await _Harness.open(tester);
    harness.repository.gate = Completer<void>();
    harness.editLine(tester, 'one save');

    await harness.requestBack(tester);
    await tester.tap(find.text('保存并返回'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await harness.requestBack(tester, settle: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('有未保存的修改'), findsNothing);

    harness.repository.gate!.complete();
    await tester.pumpAndSettle();

    expect(harness.repository.writes, 1);
    expect(find.byType(LyricEditorScreen), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an edit made while saving stays marked unsaved', (tester) async {
    final harness = await _Harness.open(tester);
    harness.repository.gate = Completer<void>();
    final editor = harness.editLine(tester, 'first version');

    await tester.tap(find.byKey(const ValueKey('lyric_editor_save_action')));
    await tester.pump();
    expect(find.text('正在保存…'), findsOneWidget);
    // Disabled while the write runs, so a second click cannot queue a write.
    await tester.tap(
      find.byKey(const ValueKey('lyric_editor_save_action')),
      warnIfMissed: false,
    );
    await tester.pump();

    harness.editLine(tester, 'second version');
    harness.repository.gate!.complete();
    await tester.pumpAndSettle();

    expect(harness.repository.writes, 1);
    expect(await harness.savedText(), 'first version');
    expect(editor.hasChanges, isTrue);
    expect(find.text('已保存，但保存期间的新修改尚未保存。'), findsOneWidget);

    // Leaving now still warns because the newest edit is not on disk.
    await harness.requestBack(tester);
    expect(find.text('有未保存的修改'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a plain save keeps the editor open and clean', (tester) async {
    final harness = await _Harness.open(tester);
    final editor = harness.editLine(tester, 'saved in place');

    await tester.tap(find.byKey(const ValueKey('lyric_editor_save_action')));
    await tester.pumpAndSettle();

    expect(find.byType(LyricEditorScreen), findsOneWidget);
    expect(editor.hasChanges, isFalse);
    expect(find.text('歌词已保存'), findsOneWidget);
    expect(await harness.savedText(), 'saved in place');

    await harness.requestBack(tester);
    expect(find.text('有未保存的修改'), findsNothing);
    expect(find.byType(LyricEditorScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _Harness {
  _Harness(this.repository, this.projectId);

  final _GatedProjectRepository repository;
  final String projectId;

  static Future<_Harness> open(WidgetTester tester) async {
    final repository = _GatedProjectRepository();
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
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final dependencies = LyricEditorDependencies(
      projectRepository: repository,
      playbackSession: _FakePlaybackSession(),
      audioPlayer: _FakeAudioPlayer(),
      lyricFileExport: _FakeLyricFileExport(),
      lyricFileImport: LocalLyricFileImportService(),
      forcedAlignmentRunner: _noAlignment,
    );
    final projectId = project.id;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                const Text('home'),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LyricEditorScreen(
                        projectId: projectId,
                        dependencies: dependencies,
                      ),
                    ),
                  ),
                  child: const Text('open editor'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open editor'));
    await tester.pumpAndSettle();
    expect(find.byType(LyricEditorScreen), findsOneWidget);
    return _Harness(repository, projectId);
  }

  LyricEditorDocumentController editor(WidgetTester tester) {
    final field = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '歌词文本',
    );
    return Provider.of<LyricEditorDocumentController>(
      tester.element(field.first),
      listen: false,
    );
  }

  LyricEditorDocumentController editLine(WidgetTester tester, String text) {
    final controller = editor(tester);
    final line = controller.document!.lines.single;
    controller.updateLine(0, line.copyWith(text: text));
    return controller;
  }

  Future<void> requestBack(WidgetTester tester, {bool settle = true}) async {
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    unawaited(navigator.maybePop());
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> changeProjectElsewhere() async {
    final current = await repository.getProjectById(projectId);
    await repository.updateProject(
      current!.copyWith(lyricDocument: _document('changed elsewhere')),
    );
  }

  Future<String?> savedText() async {
    final project = await repository.getProjectById(projectId);
    return project?.lyricDocument?.lines.single.text;
  }
}

class _GatedProjectRepository extends MemoryProjectRepository {
  Completer<void>? gate;
  Object? failure;
  int writes = 0;

  @override
  Future<ProjectManifest> updateProjectIfUnchanged(
    ProjectManifest project, {
    required int expectedRevision,
  }) async {
    writes++;
    final pending = gate;
    if (pending != null) await pending.future;
    final error = failure;
    if (error != null) throw error;
    return super.updateProjectIfUnchanged(
      project,
      expectedRevision: expectedRevision,
    );
  }
}

Future<List<ForcedAlignedSpan>> _noAlignment({
  required String audioPath,
  required String text,
  required String language,
  required Duration audioDuration,
}) async => const [];

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
