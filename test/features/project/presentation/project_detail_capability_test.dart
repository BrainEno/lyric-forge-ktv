import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';
import 'package:lyric_forge_ktv/features/project/presentation/project_detail_dependencies.dart';
import 'package:lyric_forge_ktv/features/project/presentation/screens/project_detail_screen.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_download_connection_checker.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_managed_storage_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_storage_preflight_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/project_transcription_workflow.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_profile_resolver.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_settings_store.dart';
import 'package:lyric_forge_ktv/features/transcription/presentation/transcription_screen_dependencies.dart';

ProjectManifest _project({
  required ProcessingStage stage,
  AudioAsset? audio,
}) => ProjectManifest(
  id: 'project',
  name: 'Test song',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  currentStage: stage,
  audioAsset: audio,
  lyricDocument: const LyricDocument(
    language: 'zh',
    lines: [LyricLine(text: '歌词', startTime: Duration.zero, endTime: Duration(seconds: 1))],
  ),
);

Future<void> _showProject(WidgetTester tester, ProjectManifest project, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final dependencies = ProjectDetailDependencies(
    projectRepository: _Projects(project),
    transcriptionWorkflow: _Workflow(),
    asrRuntimeSetupDependencies: AsrRuntimeSetupDependencies(
      asrRuntimeManager: _Runtime(),
      asrStoragePreflightService: _Preflight(),
      asrManagedStorageService: _Storage(),
      transcriptionSettingsStore: _Settings(),
      configDialogDependencies: TranscriptionConfigDialogDependencies(
        profileResolver: _Profiles(),
        downloadConnectionChecker: _Connection(),
        downloadProxyStore: _Proxy(),
      ),
    ),
  );
  await tester.pumpWidget(MaterialApp(home: ProjectDetailScreen(projectId: project.id, dependencies: dependencies)));
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [const Size(390, 844), const Size(1366, 768)]) {
    testWidgets('missing audio is not described as waiting for separation at $size', (tester) async {
      await _showProject(tester, _project(stage: ProcessingStage.lyricsEdited), size);
      expect(find.text('缺少工程音频'), findsOneWidget);
      expect(find.text('歌词已准备好，工程需要音频才能进入播放器。'), findsOneWidget);
      expect(find.textContaining('等待伴奏处理'), findsNothing);
      final button = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '缺少工程音频'));
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('original audio remains playable without a separated track at $size', (tester) async {
      await _showProject(tester, _project(
        stage: ProcessingStage.lyricsEdited,
        audio: const AudioAsset(originalPath: '/music/song.mp3', format: 'mp3'),
      ), size);
      expect(find.text('歌词已经校对，可以进入播放器预览 KTV 效果。'), findsOneWidget);
      final button = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '打开播放器'));
      expect(button.onPressed, isNotNull);
      expect(find.textContaining('等待伴奏处理'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('legacy separation stage does not claim the tracks are ready', (tester) async {
    await _showProject(tester, _project(
      stage: ProcessingStage.vocalsSeparated,
      audio: const AudioAsset(originalPath: '/music/song.mp3', format: 'mp3'),
    ), const Size(1366, 768));
    expect(find.text('工程记录了音轨分离阶段'), findsOneWidget);
    expect(find.text('人声与伴奏已经准备好'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _Projects extends Fake implements ProjectRepository {
  _Projects(this.project);
  final ProjectManifest project;
  @override
  Future<ProjectManifest?> getProjectById(String id) async => project;
}

class _Workflow extends Fake implements ProjectTranscriptionWorkflow {
  @override
  Stream<TranscriptionProgress> get progressStream => const Stream.empty();
}
class _Runtime extends Fake implements AsrRuntimeManager {}
class _Preflight extends Fake implements AsrStoragePreflightService {}
class _Storage extends Fake implements AsrManagedStorageService {}
class _Settings extends Fake implements TranscriptionSettingsStore {}
class _Profiles extends Fake implements TranscriptionProfileResolver {}
class _Connection extends Fake implements AsrDownloadConnectionChecker {}
class _Proxy extends Fake implements TranscriptionDownloadProxyStore {}
