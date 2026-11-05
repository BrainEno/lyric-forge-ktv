import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_file_export_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/lyric_editor_dependencies.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/screens/lyric_editor_screen.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/data/repositories/memory_project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';

void main() {
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
      await tester.pumpAndSettle();
      await tester.tap(find.text('Original lyric'));
      await tester.pumpAndSettle();
      final lyricField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '歌词文本',
      );
      expect(lyricField, findsOneWidget);
      await tester.enterText(lyricField, 'Local edit');
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      expect(find.text('工程已在其他位置更新'), findsOneWidget);
      expect(find.textContaining('你的编辑仍保留'), findsOneWidget);

      final afterRejectedSave = await repository.getProjectById(project.id);
      expect(
        afterRejectedSave?.lyricDocument?.lines.single.text,
        'Background transcription',
      );
      expect(afterRejectedSave?.metadata['transcription'], {'engine': 'qwen'});

      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();
      expect(find.text('Local edit'), findsOneWidget);

      await tester.tap(find.byTooltip('保存修改'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('用当前歌词覆盖最新版'));
      await tester.pumpAndSettle();

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
