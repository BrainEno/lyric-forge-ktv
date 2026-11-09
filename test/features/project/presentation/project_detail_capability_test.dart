import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/services/project_accompaniment_importer.dart';
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

ProjectManifest _project({required ProcessingStage stage, AudioAsset? audio}) =>
    ProjectManifest(
      id: 'project',
      name: 'Test song',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      currentStage: stage,
      audioAsset: audio,
      lyricDocument: const LyricDocument(
        language: 'zh',
        lines: [
          LyricLine(
            text: '歌词',
            startTime: Duration.zero,
            endTime: Duration(seconds: 1),
          ),
        ],
      ),
    );

Future<void> _showProject(
  WidgetTester tester,
  ProjectManifest project,
  Size size, {
  _Projects? projects,
  ProjectAccompanimentImporter? importer,
  ActiveProjectPlaybackSourceUpdater? updater,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final dependencies = ProjectDetailDependencies(
    projectRepository: projects ?? _Projects(project),
    accompanimentImporter: importer ?? _Importer(),
    playbackSourceUpdater: updater,
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
  await tester.pumpWidget(
    MaterialApp(
      home: ProjectDetailScreen(
        projectId: project.id,
        dependencies: dependencies,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [const Size(390, 844), const Size(1366, 768)]) {
    testWidgets(
      'missing audio is not described as waiting for separation at $size',
      (tester) async {
        await _showProject(
          tester,
          _project(stage: ProcessingStage.lyricsEdited),
          size,
        );
        expect(find.text('缺少工程音频'), findsOneWidget);
        expect(find.text('歌词已准备好，工程需要音频才能进入播放器。'), findsOneWidget);
        expect(find.textContaining('等待伴奏处理'), findsNothing);
        final button = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, '缺少工程音频'),
        );
        expect(button.onPressed, isNull);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'original audio remains playable without a separated track at $size',
      (tester) async {
        await _showProject(
          tester,
          _project(
            stage: ProcessingStage.lyricsEdited,
            audio: const AudioAsset(
              originalPath: '/music/song.mp3',
              format: 'mp3',
            ),
          ),
          size,
        );
        expect(find.text('歌词已经校对，可以进入播放器预览 KTV 效果。'), findsOneWidget);
        final button = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, '打开播放器'),
        );
        expect(button.onPressed, isNotNull);
        expect(find.textContaining('等待伴奏处理'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'desktop import shows progress, updates project and confirms replacement',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final project = _project(
          stage: ProcessingStage.lyricsEdited,
          audio: const AudioAsset(
            originalPath: '/music/song.mp3',
            format: 'mp3',
          ),
        );
        final projects = _Projects(project);
        final result = Completer<ProjectManifest?>();
        final importer = _Importer(onImport: (_) => result.future);
        await _showProject(
          tester,
          project,
          const Size(1366, 768),
          projects: projects,
          importer: importer,
        );
        await tester.tap(find.text('导入已有伴奏'));
        await tester.pump();
        expect(importer.calls, 1);
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, '正在导入伴奏…'),
              )
              .onPressed,
          isNull,
        );
        projects.project = project.copyWith(
          audioAsset: project.audioAsset!.copyWith(
            instrumentalPath: '/managed/backing.mp3',
          ),
        );
        result.complete(projects.project);
        await tester.pumpAndSettle();
        expect(find.text('更换伴奏'), findsOneWidget);
        expect(find.textContaining('伴奏已导入'), findsOneWidget);
        await tester.tap(find.text('更换伴奏'));
        await tester.pumpAndSettle();
        expect(find.text('更换伴奏？'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(importer.calls, 1);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  for (final outcome in ['updated', 'rejected', 'error']) {
    testWidgets('import handles playback sync $outcome', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final project = _project(
          stage: ProcessingStage.lyricsEdited,
          audio: const AudioAsset(originalPath: '/song.mp3', format: 'mp3'),
        );
        final updated = project.copyWith(
          audioAsset: project.audioAsset!.copyWith(
            instrumentalPath: '/managed/backing.mp3',
          ),
        );
        final projects = _Projects(project);
        final updater = _Updater(outcome);
        final importer = _Importer(
          onImport: (_) async {
            projects.project = updated;
            return updated;
          },
        );
        await _showProject(
          tester,
          project,
          const Size(1366, 768),
          projects: projects,
          importer: importer,
          updater: updater,
        );
        await tester.tap(find.text('导入已有伴奏'));
        await tester.pumpAndSettle();
        expect(updater.calls, 1);
        expect(updater.projectId, project.id);
        expect(updater.expected, same(project.audioAsset));
        expect(updater.replacement, same(updated.audioAsset));
        expect(find.text('更换伴奏'), findsOneWidget);
        expect(
          find.textContaining(outcome == 'updated' ? '同步到当前播放队列' : '切换歌曲'),
          findsOneWidget,
        );
        expect(find.textContaining('导入伴奏失败'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('cancelled import does not update playback', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final project = _project(
        stage: ProcessingStage.lyricsEdited,
        audio: const AudioAsset(originalPath: '/song.mp3', format: 'mp3'),
      );
      final updater = _Updater('updated');
      await _showProject(
        tester,
        project,
        const Size(1366, 768),
        updater: updater,
      );
      await tester.tap(find.text('导入已有伴奏'));
      await tester.pumpAndSettle();
      expect(updater.calls, 0);
      expect(find.textContaining('伴奏已导入'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('completed import syncs even after detail screen is closed', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final project = _project(
        stage: ProcessingStage.lyricsEdited,
        audio: const AudioAsset(originalPath: '/song.mp3', format: 'mp3'),
      );
      final pending = Completer<ProjectManifest?>();
      final updater = _Updater('updated');
      await _showProject(
        tester,
        project,
        const Size(1366, 768),
        importer: _Importer(onImport: (_) => pending.future),
        updater: updater,
      );
      await tester.tap(find.text('导入已有伴奏'));
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      pending.complete(
        project.copyWith(
          audioAsset: project.audioAsset!.copyWith(
            instrumentalPath: '/backing.mp3',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(updater.calls, 1);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop import reports a project conflict', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final project = _project(
        stage: ProcessingStage.lyricsEdited,
        audio: const AudioAsset(originalPath: '/music/song.mp3', format: 'mp3'),
      );
      final importer = _Importer(
        onImport: (_) async =>
            throw const ProjectUpdateConflictException(currentProject: null),
      );
      await _showProject(
        tester,
        project,
        const Size(1366, 768),
        importer: importer,
      );
      await tester.tap(find.text('导入已有伴奏'));
      await tester.pumpAndSettle();
      expect(find.textContaining('工程已发生变化'), findsOneWidget);
      expect(find.text('导入已有伴奏'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('mobile does not expose desktop accompaniment import', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await _showProject(
        tester,
        _project(
          stage: ProcessingStage.lyricsEdited,
          audio: const AudioAsset(
            originalPath: '/music/song.mp3',
            format: 'mp3',
          ),
        ),
        const Size(390, 844),
      );
      expect(find.text('导入已有伴奏'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('legacy separation stage does not claim the tracks are ready', (
    tester,
  ) async {
    await _showProject(
      tester,
      _project(
        stage: ProcessingStage.vocalsSeparated,
        audio: const AudioAsset(originalPath: '/music/song.mp3', format: 'mp3'),
      ),
      const Size(1366, 768),
    );
    expect(find.text('工程记录了音轨分离阶段'), findsOneWidget);
    expect(find.text('人声与伴奏已经准备好'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _Updater implements ActiveProjectPlaybackSourceUpdater {
  _Updater(this.outcome);
  final String outcome;
  int calls = 0;
  String? projectId;
  AudioAsset? expected;
  AudioAsset? replacement;

  @override
  Future<bool> updateActiveProjectSources({
    required String projectId,
    required AudioAsset expected,
    required AudioAsset replacement,
  }) async {
    calls++;
    this.projectId = projectId;
    this.expected = expected;
    this.replacement = replacement;
    if (outcome == 'error') throw StateError('sync failed');
    return outcome == 'updated';
  }
}

class _Projects extends Fake implements ProjectRepository {
  _Projects(this.project);
  ProjectManifest project;
  @override
  Future<ProjectManifest?> getProjectById(String id) async => project;
}

class _Importer extends Fake implements ProjectAccompanimentImporter {
  _Importer({this.onImport});
  final Future<ProjectManifest?> Function(ProjectManifest)? onImport;
  int calls = 0;

  @override
  Future<ProjectManifest?> importFor(ProjectManifest project) {
    calls++;
    return onImport?.call(project) ?? Future.value(null);
  }
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
