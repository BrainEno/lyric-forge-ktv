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
import 'package:lyric_forge_ktv/features/project/domain/services/project_vocal_importer.dart';
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
  ProjectVocalImporter? vocalImporter,
  ActiveProjectPlaybackSourceUpdater? updater,
  double textScale = 1,
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
    vocalImporter: vocalImporter ?? _VocalImporter(),
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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
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

  testWidgets(
    'vocal import disables competing operations and confirms replacement',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final project = _project(
          stage: ProcessingStage.lyricsEdited,
          audio: const AudioAsset(originalPath: '/song.wav', format: 'wav'),
        );
        final projects = _Projects(project);
        final pending = Completer<ProjectManifest?>();
        final importer = _VocalImporter(onImport: (_) => pending.future);
        await _showProject(
          tester,
          project,
          const Size(1366, 768),
          projects: projects,
          vocalImporter: importer,
        );
        await tester.tap(find.text('导入已有人声'));
        await tester.pump();
        expect(importer.calls, 1);
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, '正在导入人声…'),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, '导入已有伴奏'),
              )
              .onPressed,
          isNull,
        );
        projects.project = project.copyWith(
          audioAsset: project.audioAsset!.copyWith(
            vocalPath: '/managed/vocal.wav',
          ),
        );
        pending.complete(projects.project);
        await tester.pumpAndSettle();
        expect(find.textContaining('人声已导入'), findsOneWidget);
        expect(find.text('更换人声'), findsOneWidget);
        await tester.tap(find.text('更换人声'));
        await tester.pumpAndSettle();
        expect(find.text('更换人声？'), findsOneWidget);
        expect(find.textContaining('原文件不会删除'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(importer.calls, 1);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('vocal replacement proceeds only after confirmation', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final project = _project(
        stage: ProcessingStage.lyricsEdited,
        audio: const AudioAsset(
          originalPath: '/song.wav',
          vocalPath: '/old.wav',
          format: 'wav',
        ),
      );
      final importer = _VocalImporter();
      await _showProject(
        tester,
        project,
        const Size(1366, 768),
        vocalImporter: importer,
      );
      await tester.tap(find.text('更换人声'));
      await tester.pumpAndSettle();
      expect(importer.calls, 0);
      await tester.tap(find.text('选择新人声'));
      await tester.pumpAndSettle();
      expect(importer.calls, 1);
      expect(find.text('更换人声'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final outcome in ['updated', 'rejected', 'error']) {
    testWidgets('vocal import handles playback sync $outcome', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final project = _project(
          stage: ProcessingStage.lyricsEdited,
          audio: const AudioAsset(originalPath: '/song.wav', format: 'wav'),
        );
        final updated = project.copyWith(
          audioAsset: project.audioAsset!.copyWith(
            vocalPath: '/managed/vocal.wav',
          ),
        );
        final projects = _Projects(project);
        final importer = _VocalImporter(
          onImport: (_) async {
            projects.project = updated;
            return updated;
          },
        );
        final updater = _Updater(outcome);
        await _showProject(
          tester,
          project,
          const Size(1366, 768),
          projects: projects,
          vocalImporter: importer,
          updater: updater,
        );
        await tester.tap(find.text('导入已有人声'));
        await tester.pumpAndSettle();
        expect(updater.calls, 1);
        expect(updater.expected, same(project.audioAsset));
        expect(updater.replacement, same(updated.audioAsset));
        expect(find.text('更换人声'), findsOneWidget);
        expect(
          find.textContaining(outcome == 'updated' ? '同步到当前播放队列' : '切换歌曲'),
          findsOneWidget,
        );
        expect(find.textContaining('导入人声失败'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('vocal import reports stale revision and supports retry', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final project = _project(
        stage: ProcessingStage.lyricsEdited,
        audio: const AudioAsset(originalPath: '/song.wav', format: 'wav'),
      );
      final importer = _VocalImporter(
        onImport: (_) async =>
            throw const ProjectUpdateConflictException(currentProject: null),
      );
      await _showProject(
        tester,
        project,
        const Size(1366, 768),
        vocalImporter: importer,
      );
      await tester.tap(find.text('导入已有人声'));
      await tester.pumpAndSettle();
      expect(find.textContaining('工程已发生变化，未替换人声'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '导入已有人声'),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('cancelled vocal picker does not update playback or project', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final project = _project(
        stage: ProcessingStage.lyricsEdited,
        audio: const AudioAsset(originalPath: '/song.wav', format: 'wav'),
      );
      final updater = _Updater('updated');
      final importer = _VocalImporter();
      await _showProject(
        tester,
        project,
        const Size(1366, 768),
        vocalImporter: importer,
        updater: updater,
      );
      await tester.tap(find.text('导入已有人声'));
      await tester.pumpAndSettle();
      expect(importer.calls, 1);
      expect(updater.calls, 0);
      expect(find.text('导入已有人声'), findsOneWidget);
      expect(find.textContaining('人声已导入'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final size in [const Size(320, 568), const Size(800, 480)]) {
    testWidgets('vocal import remains reachable at $size with enlarged text', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final project = _project(stage: ProcessingStage.lyricsEdited, audio: const AudioAsset(originalPath: '/song.wav', format: 'wav'));
        final importer = _VocalImporter();
        await _showProject(tester, project, size, vocalImporter: importer, textScale: 2);
        final button = find.widgetWithText(OutlinedButton, '导入已有人声');
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        expect(button.hitTestable(), findsOneWidget);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(importer.calls, 1);
        expect(tester.takeException(), isNull);
      } finally { debugDefaultTargetPlatformOverride = null; }
    });
  }

  testWidgets('vocal importer failure releases both import controls', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final project = _project(stage: ProcessingStage.lyricsEdited, audio: const AudioAsset(originalPath: '/song.wav', format: 'wav'));
      final importer = _VocalImporter(onImport: (_) async => throw StateError('bad file'));
      await _showProject(tester, project, const Size(1366, 768), vocalImporter: importer);
      await tester.tap(find.text('导入已有人声'));
      await tester.pumpAndSettle();
      expect(find.textContaining('导入人声失败'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '导入已有伴奏')).onPressed, isNotNull);
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '导入已有人声')).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    } finally { debugDefaultTargetPlatformOverride = null; }
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
      expect(find.text('导入已有人声'), findsNothing);
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

class _VocalImporter extends Fake implements ProjectVocalImporter {
  _VocalImporter({this.onImport});
  final Future<ProjectManifest?> Function(ProjectManifest)? onImport;
  int calls = 0;
  @override
  Future<ProjectManifest?> importVocalFor(ProjectManifest project) {
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
