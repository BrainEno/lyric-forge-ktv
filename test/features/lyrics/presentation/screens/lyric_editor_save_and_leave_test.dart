import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_file_export_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/controllers/lyric_editor_document_controller.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/lyric_editor_dependencies.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/screens/lyric_editor_screen.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/memory_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';

void main() {
  group('lyric editor save and leave', () {
    testWidgets(
      '保存并返回 waits for one delayed write and exits only after it persists',
      (tester) async {
        final repository = _ControlledProjectRepository()
          ..saveGate = Completer<void>();
        final harness = await _openEditor(tester, repository);
        _edit(harness.editor, '等待保存的歌词');
        await tester.pump();

        await _requestLeave(tester);
        await tester.tap(find.text('保存并返回'));
        await tester.pump();

        expect(find.byType(LyricEditorScreen), findsOneWidget);
        expect(find.text('正在保存'), findsOneWidget);
        expect(repository.conditionalUpdateCalls, 1);
        final saveButton = find.byIcon(Icons.save_rounded);
        expect(saveButton, findsNothing);

        repository.saveGate!.complete();
        await tester.pumpAndSettle();

        expect(find.byType(LyricEditorScreen), findsNothing);
        expect(find.text('编辑器入口'), findsOneWidget);
        expect(repository.conditionalUpdateCalls, 1);
        expect(
          (await repository.getProjectById(
            harness.project.id,
          ))?.lyricDocument?.lines.single.text,
          '等待保存的歌词',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'write failure keeps the route and dirty draft, then supports retry',
      (tester) async {
        final repository = _ControlledProjectRepository()
          ..nextSaveError = FileSystemException('disk unavailable');
        final harness = await _openEditor(tester, repository);
        _edit(harness.editor, '失败后仍在的草稿');
        await tester.pump();

        await _requestLeave(tester);
        await tester.tap(find.text('保存并返回'));
        await tester.pumpAndSettle();

        expect(find.byType(LyricEditorScreen), findsOneWidget);
        expect(find.textContaining('保存歌词失败'), findsOneWidget);
        expect(harness.editor.hasChanges, isTrue);
        expect(harness.editor.document?.lines.single.text, '失败后仍在的草稿');
        expect(repository.conditionalUpdateCalls, 1);
        expect(
          (await repository.getProjectById(
            harness.project.id,
          ))?.lyricDocument?.lines.single.text,
          '原始歌词',
        );

        repository.nextSaveError = null;
        await tester.tap(find.byIcon(Icons.save_rounded));
        await tester.pumpAndSettle();

        expect(repository.conditionalUpdateCalls, 2);
        expect(harness.editor.hasChanges, isFalse);
        expect(
          (await repository.getProjectById(
            harness.project.id,
          ))?.lyricDocument?.lines.single.text,
          '失败后仍在的草稿',
        );
        expect(find.byType(LyricEditorScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'conflict keep-editing stays on the route and explicit overwrite then leaves',
      (tester) async {
        final repository = _ControlledProjectRepository();
        final harness = await _openEditor(tester, repository);
        _edit(harness.editor, '本地歌词');
        await tester.pump();

        await repository.updateProject(
          harness.project.copyWith(
            lyricDocument: _document('后台识别歌词'),
            metadata: const {
              'transcription': {'engine': 'qwen'},
            },
          ),
        );

        await _requestLeave(tester);
        await tester.tap(find.text('保存并返回'));
        await tester.pumpAndSettle();

        expect(find.text('工程已在其他位置更新'), findsOneWidget);
        await tester.tap(find.text('继续编辑'));
        await tester.pumpAndSettle();
        expect(find.byType(LyricEditorScreen), findsOneWidget);
        expect(harness.editor.document?.lines.single.text, '本地歌词');
        expect(harness.editor.hasChanges, isTrue);

        await _requestLeave(tester);
        await tester.tap(find.text('保存并返回'));
        await tester.pumpAndSettle();
        expect(find.text('工程已在其他位置更新'), findsOneWidget);
        await tester.tap(find.text('用当前歌词覆盖最新版'));
        await tester.pumpAndSettle();

        expect(find.byType(LyricEditorScreen), findsNothing);
        final saved = await repository.getProjectById(harness.project.id);
        expect(saved?.lyricDocument?.lines.single.text, '本地歌词');
        expect(saved?.metadata['transcription'], {'engine': 'qwen'});
        expect(repository.conditionalUpdateCalls, 3);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'disposing during a delayed direct save never throws and still commits the write',
      (tester) async {
        final repository = _ControlledProjectRepository()
          ..saveGate = Completer<void>();
        final harness = await _openEditor(tester, repository);
        _edit(harness.editor, '离开组件后的保存');
        await tester.pump();

        await tester.tap(find.byIcon(Icons.save_rounded));
        await tester.pump();
        expect(repository.conditionalUpdateCalls, 1);
        expect(find.text('正在保存'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        repository.saveGate!.complete();
        await tester.pumpAndSettle();

        expect(
          (await repository.getProjectById(
            harness.project.id,
          ))?.lyricDocument?.lines.single.text,
          '离开组件后的保存',
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}

Future<_EditorHarness> _openEditor(
  WidgetTester tester,
  _ControlledProjectRepository repository,
) async {
  var project = await repository.createProject(name: '保存测试工程');
  project = await repository.updateProject(
    project.copyWith(lyricDocument: _document('原始歌词')),
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
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LyricEditorScreen(
                      projectId: project.id,
                      dependencies: dependencies,
                    ),
                  ),
                );
              },
              child: const Text('编辑器入口'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('编辑器入口'));
  await tester.pumpAndSettle();
  final lyricField = find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == '歌词文本',
  );
  expect(lyricField, findsOneWidget);
  final editor = Provider.of<LyricEditorDocumentController>(
    tester.element(lyricField),
    listen: false,
  );
  return _EditorHarness(project: project, editor: editor);
}

void _edit(LyricEditorDocumentController editor, String text) {
  final original = editor.document!.lines.single;
  editor.updateLine(0, original.copyWith(text: text));
}

Future<void> _requestLeave(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  expect(find.text('有未保存的修改'), findsOneWidget);
}

LyricDocument _document(String text) => LyricDocument(
  language: 'zh',
  lines: [
    LyricLine(
      text: text,
      startTime: Duration.zero,
      endTime: const Duration(seconds: 2),
    ),
  ],
);

Future<List<ForcedAlignedSpan>> _emptyAlignment({
  required String audioPath,
  required String text,
  required String language,
  required Duration audioDuration,
}) async => const [];

class _EditorHarness {
  final ProjectManifest project;
  final LyricEditorDocumentController editor;

  const _EditorHarness({required this.project, required this.editor});
}

class _ControlledProjectRepository implements ProjectRepository {
  final MemoryProjectRepository _delegate = MemoryProjectRepository();

  Completer<void>? saveGate;
  Object? nextSaveError;
  int conditionalUpdateCalls = 0;

  @override
  Future<List<ProjectManifest>> getAllProjects() => _delegate.getAllProjects();

  @override
  Future<ProjectManifest?> getProjectById(String id) =>
      _delegate.getProjectById(id);

  @override
  Future<ProjectManifest> createProject({
    required String name,
    String? artist,
    String? album,
  }) => _delegate.createProject(name: name, artist: artist, album: album);

  @override
  Future<ProjectManifest> updateProject(ProjectManifest project) =>
      _delegate.updateProject(project);

  @override
  Future<ProjectManifest> updateProjectIfUnchanged(
    ProjectManifest project, {
    required int expectedRevision,
  }) async {
    conditionalUpdateCalls += 1;
    final gate = saveGate;
    if (gate != null) await gate.future;
    final error = nextSaveError;
    if (error != null) throw error;
    return _delegate.updateProjectIfUnchanged(
      project,
      expectedRevision: expectedRevision,
    );
  }

  @override
  Future<void> deleteProject(String id) => _delegate.deleteProject(id);

  @override
  Future<List<ProjectManifest>> getRecentProjects({int limit = 10}) =>
      _delegate.getRecentProjects(limit: limit);
}

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
