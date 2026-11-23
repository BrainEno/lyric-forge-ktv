import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/automatic_accompaniment.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_review_overview.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/services/project_accompaniment_importer.dart';
import 'package:lyric_forge_ktv/features/project/domain/services/project_deletion_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/services/project_vocal_importer.dart';
import 'package:lyric_forge_ktv/features/project/presentation/project_detail_dependencies.dart';
import 'package:lyric_forge_ktv/features/project/presentation/screens/project_detail_screen.dart';
import 'package:lyric_forge_ktv/features/project/presentation/widgets/project_audio_sources_section.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/vocal_separation_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_download_connection_checker.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_managed_storage_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_storage_preflight_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/project_accompaniment_generator.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/project_transcription_workflow.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_profile_resolver.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_settings_store.dart';
import 'package:lyric_forge_ktv/features/transcription/presentation/transcription_screen_dependencies.dart';

import '../support/fake_project_deletion_service.dart';

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
  ProjectTranscriptionWorkflow? workflow,
  TranscriptionSettingsStore? settings,
  ProjectDeletionService? deletionService,
  ProjectLyricReviewCounter? reviewCounter,
  double textScale = 1,
  bool openAudioSources = true,
  bool pushed = false,
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
    transcriptionWorkflow: workflow ?? _Workflow(),
    asrRuntimeSetupDependencies: AsrRuntimeSetupDependencies(
      asrRuntimeManager: _Runtime(),
      asrStoragePreflightService: _Preflight(),
      asrManagedStorageService: _Storage(),
      transcriptionSettingsStore: settings ?? _Settings(),
      configDialogDependencies: TranscriptionConfigDialogDependencies(
        profileResolver: _Profiles(),
        downloadConnectionChecker: _Connection(),
        downloadProxyStore: _Proxy(),
      ),
    ),
    deletionService: deletionService,
    reviewCounter: reviewCounter,
  );
  final screen = ProjectDetailScreen(
    projectId: project.id,
    dependencies: dependencies,
  );
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: pushed
          ? Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => screen),
                  ),
                  child: const Text('open project'),
                ),
              ),
            )
          : screen,
    ),
  );
  await tester.pumpAndSettle();
  if (pushed) {
    await tester.tap(find.text('open project'));
    await tester.pumpAndSettle();
  }
  // The track imports are folded behind 伴奏与人声 (desktop only).
  final toggle = find.byKey(ProjectAudioSourcesSection.toggleKey);
  if (openAudioSources && toggle.evaluate().isNotEmpty) {
    await _reveal(tester, toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
  }
}

/// Scrolls [finder] to the middle of the page, clear of the pinned app bar.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
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
        await _reveal(tester, find.text('更换伴奏'));
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
        await _reveal(tester, find.text('更换人声'));
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
    testWidgets('vocal import remains reachable at $size with enlarged text', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final project = _project(
          stage: ProcessingStage.lyricsEdited,
          audio: const AudioAsset(originalPath: '/song.wav', format: 'wav'),
        );
        final importer = _VocalImporter();
        await _showProject(
          tester,
          project,
          size,
          vocalImporter: importer,
          textScale: 2,
        );
        final button = find.widgetWithText(OutlinedButton, '导入已有人声');
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        expect(button.hitTestable(), findsOneWidget);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(importer.calls, 1);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('vocal importer failure releases both import controls', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final project = _project(
        stage: ProcessingStage.lyricsEdited,
        audio: const AudioAsset(originalPath: '/song.wav', format: 'wav'),
      );
      final importer = _VocalImporter(
        onImport: (_) async => throw StateError('bad file'),
      );
      await _showProject(
        tester,
        project,
        const Size(1366, 768),
        vocalImporter: importer,
      );
      await tester.tap(find.text('导入已有人声'));
      await tester.pumpAndSettle();
      expect(find.textContaining('导入人声失败'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '导入已有伴奏'),
            )
            .onPressed,
        isNotNull,
      );
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

  testWidgets('track imports start folded behind 伴奏与人声', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await _showProject(
        tester,
        _project(
          stage: ProcessingStage.lyricsEdited,
          audio: const AudioAsset(
            originalPath: '/song.wav',
            vocalPath: '/vocal.wav',
            format: 'wav',
          ),
        ),
        const Size(1366, 768),
        openAudioSources: false,
      );

      expect(find.text('伴奏与人声'), findsOneWidget);
      expect(find.text('没有伴奏轨 · 已有人声轨'), findsOneWidget);
      expect(find.text('导入已有伴奏'), findsNothing);
      expect(find.text('更换人声'), findsNothing);
      // The main path is still first.
      expect(find.widgetWithText(FilledButton, '校对歌词'), findsOneWidget);

      final toggle = find.byKey(ProjectAudioSourcesSection.toggleKey);
      await _reveal(tester, toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('导入已有伴奏'), findsOneWidget);
      expect(find.text('更换人声'), findsOneWidget);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('导入已有伴奏'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('自动生成伴奏 runs in the section and links the result (D-060)', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final project = _project(
        stage: ProcessingStage.lyricsEdited,
        audio: const AudioAsset(originalPath: '/song.mp3', format: 'mp3'),
      );
      final projects = _Projects(project);
      final workflow = _GeneratingWorkflow(projects);
      final updater = _Updater('updated');
      await _showProject(
        tester,
        project,
        const Size(1366, 768),
        projects: projects,
        workflow: workflow,
        settings: _LoadedSettings(),
        updater: updater,
      );

      final generate = find.byKey(ProjectAudioSourcesSection.generateKey);
      await _reveal(tester, generate);
      await tester.tap(generate);
      await tester.pump();
      await tester.pump();

      expect(workflow.generations, 1);
      expect(find.text('正在分离人声 30%'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(generate, findsNothing);
      final transcribe = find.widgetWithText(TextButton, '重新识别歌词');
      expect(tester.widget<TextButton>(transcribe).onPressed, isNull);

      workflow.release.complete();
      await tester.pumpAndSettle();

      expect(find.textContaining('伴奏已生成'), findsOneWidget);
      expect(find.text('打开播放器'), findsWidgets);
      expect(find.text('已有伴奏轨（自动分离） · 没有人声轨'), findsOneWidget);
      expect(find.text('换成已有伴奏'), findsOneWidget);
      expect(generate, findsNothing);
      expect(updater.calls, 1);
      expect(updater.replacement?.instrumentalPath, '/stems/accompaniment.wav');
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('自动生成伴奏 is not offered without a separator', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await _showProject(
        tester,
        _project(
          stage: ProcessingStage.lyricsEdited,
          audio: const AudioAsset(originalPath: '/song.mp3', format: 'mp3'),
        ),
        const Size(1366, 768),
      );
      expect(find.text('导入已有伴奏'), findsOneWidget);
      expect(find.text('自动生成伴奏'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the section stays open across the refresh after an import', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final project = _project(
        stage: ProcessingStage.lyricsEdited,
        audio: const AudioAsset(originalPath: '/song.mp3', format: 'mp3'),
      );
      final projects = _Projects(project);
      final importer = _Importer(
        onImport: (_) async {
          projects.project = project.copyWith(
            audioAsset: project.audioAsset!.copyWith(
              instrumentalPath: '/managed/backing.mp3',
            ),
          );
          return projects.project;
        },
      );
      await _showProject(
        tester,
        project,
        const Size(1366, 768),
        projects: projects,
        importer: importer,
      );

      await tester.tap(find.text('导入已有伴奏'));
      await tester.pumpAndSettle();

      expect(find.text('更换伴奏'), findsOneWidget);
      expect(find.text('已有伴奏轨 · 没有人声轨'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  group('删除工程 (D-063, D-064)', () {
    testWidgets('goes to 最近删除 at once, goes back, 撤销 restores', (tester) async {
      final projects = _Projects(_project(stage: ProcessingStage.lyricsEdited));
      final deletion = FakeProjectDeletionService();
      await _showProject(
        tester,
        projects.project,
        const Size(1366, 768),
        projects: projects,
        deletionService: deletion,
        openAudioSources: false,
        pushed: true,
      );

      await tester.tap(find.byKey(const ValueKey('project_detail_more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('project_detail_delete')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('project_delete_dialog')), findsNothing);
      expect(deletion.deleted, ['project']);
      expect(find.byType(ProjectDetailScreen), findsNothing);
      expect(find.text('open project'), findsOneWidget);
      expect(find.text('工程已移到“最近删除”'), findsOneWidget);

      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(deletion.restored, ['project']);
      expect(find.text('工程已恢复'), findsOneWidget);
    });

    testWidgets('a project in use stays open and says why', (tester) async {
      final projects = _Projects(_project(stage: ProcessingStage.lyricsEdited));
      final deletion = FakeProjectDeletionService()
        ..blockers['project'] = '这首歌正在播放，换一首或停止播放后再删除';
      await _showProject(
        tester,
        projects.project,
        const Size(1366, 768),
        projects: projects,
        deletionService: deletion,
        openAudioSources: false,
        pushed: true,
      );
      await tester.tap(find.byKey(const ValueKey('project_detail_more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('project_detail_delete')));
      await tester.pumpAndSettle();

      expect(deletion.deleted, isEmpty);
      expect(find.byType(ProjectDetailScreen), findsOneWidget);
      expect(find.text('这首歌正在播放，换一首或停止播放后再删除'), findsOneWidget);
    });

    testWidgets('without the service there is no delete menu', (tester) async {
      await _showProject(
        tester,
        _project(stage: ProcessingStage.lyricsEdited),
        const Size(1366, 768),
      );
      expect(find.byKey(const ValueKey('project_detail_more')), findsNothing);
    });
  });

  group('演唱语言 (D-062)', () {
    ProjectManifest songWithAudio({Map<String, dynamic> metadata = const {}}) =>
        _project(
          stage: ProcessingStage.lyricsEdited,
          audio: const AudioAsset(originalPath: '/song.wav', format: 'wav'),
        ).copyWith(metadata: metadata);

    Future<void> choose(WidgetTester tester, String code) async {
      final menu = find.byKey(const ValueKey('project_sung_language_menu'));
      await _reveal(tester, menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('project_sung_language_$code')));
      await tester.pumpAndSettle();
    }

    testWidgets('is saved with the project and offers to recognise again', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final projects = _RevisionedProjects(
          songWithAudio(
            metadata: const {
              'transcription': {'detectedLanguage': 'nn'},
            },
          ),
        );
        await _showProject(
          tester,
          projects.project,
          const Size(1366, 768),
          projects: projects,
          openAudioSources: false,
        );
        expect(find.text('上次识别：挪威语（引擎检测）'), findsOneWidget);

        await choose(tester, 'en');

        expect(projects.updates, 1);
        expect(projects.project.metadata['sungLanguage'], 'en');
        // The last recognition's record is kept.
        expect(projects.project.metadata['transcription'], isNotNull);
        expect(find.text('这首歌固定按英文识别，不受识别设置影响'), findsOneWidget);
        expect(find.text('演唱语言已设为英文，重新识别后生效'), findsOneWidget);
        expect(find.widgetWithText(SnackBarAction, '重新识别'), findsOneWidget);

        ScaffoldMessenger.of(
          tester.element(find.byType(ProjectDetailScreen)),
        ).removeCurrentSnackBar();
        await tester.pumpAndSettle();
        await choose(tester, 'auto');
        expect(projects.project.metadata, isNot(contains('sungLanguage')));
        expect(find.text('演唱语言改为自动判断，重新识别后生效'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a concurrent change is reported, not overwritten', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final projects = _RevisionedProjects(songWithAudio())..conflict = true;
        await _showProject(
          tester,
          projects.project,
          const Size(1366, 768),
          projects: projects,
          openAudioSources: false,
        );
        await choose(tester, 'ja');
        expect(projects.project.metadata, isNot(contains('sungLanguage')));
        expect(find.text('工程刚刚被修改，请再选一次演唱语言'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('is not offered on mobile', (tester) async {
      await _showProject(
        tester,
        songWithAudio(metadata: const {'sungLanguage': 'en'}),
        const Size(390, 844),
      );
      expect(
        find.byKey(const ValueKey('project_sung_language_menu')),
        findsNothing,
      );
    });
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
      expect(find.text('伴奏与人声'), findsNothing);
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

  group('歌词卡片用编辑器的“建议复核”说法 (D-069)', () {
    ProjectManifest withFrozenCounts() {
      final project = _project(stage: ProcessingStage.lyricsEdited);
      return project.copyWith(
        lyricDocument: project.lyricDocument!.copyWith(
          metadata: const {
            'lowConfidenceLineCount': 9,
            'fallbackCandidateCount': 4,
          },
        ),
      );
    }

    testWidgets('显示建议复核和必看，不再显示识别时记下的旧数字', (tester) async {
      ProjectManifest? counted;
      await _showProject(
        tester,
        withFrozenCounts(),
        const Size(1366, 768),
        reviewCounter: (project) {
          counted = project;
          return const ProjectLyricReviewOverview(
            suggested: 7,
            mustCheck: 2,
            reviewed: 1,
          );
        },
      );

      expect(counted?.id, 'project');
      expect(find.text('还有 7 行建议复核，其中 2 行必看，在歌词编辑器里逐行确认。'), findsOneWidget);
      expect(find.text('建议复核 · 7 行'), findsOneWidget);
      expect(find.text('必看 · 2 行'), findsOneWidget);
      expect(find.textContaining('低置信度'), findsNothing);
      expect(find.textContaining('重点复核'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('全部确认后说明已确认，不显示必看', (tester) async {
      await _showProject(
        tester,
        withFrozenCounts(),
        const Size(1366, 768),
        reviewCounter: (_) => const ProjectLyricReviewOverview(
          suggested: 0,
          mustCheck: 0,
          reviewed: 1,
        ),
      );

      expect(find.text('建议复核的行都已确认，仍可在歌词编辑器里逐行检查。'), findsOneWidget);
      expect(find.text('建议复核 · 无'), findsOneWidget);
      expect(find.textContaining('必看'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('没有计数时只显示行数和语言', (tester) async {
      await _showProject(tester, withFrozenCounts(), const Size(1366, 768));

      expect(find.text('自动识别结果仍建议进入歌词编辑器逐行校对。'), findsOneWidget);
      expect(find.textContaining('建议复核 ·'), findsNothing);
      expect(find.textContaining('低置信度'), findsNothing);
    });
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

/// Saves conditional updates like the real repository: by revision.
class _RevisionedProjects extends _Projects {
  _RevisionedProjects(super.project);

  int updates = 0;
  bool conflict = false;

  @override
  Future<ProjectManifest> updateProjectIfUnchanged(
    ProjectManifest project, {
    required int expectedRevision,
  }) async {
    if (conflict || expectedRevision != this.project.revision) {
      throw ProjectUpdateConflictException(currentProject: this.project);
    }
    updates++;
    return this.project = project.copyWith(revision: expectedRevision + 1);
  }
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

class _GeneratingWorkflow extends Fake
    implements ProjectTranscriptionWorkflow, ProjectAccompanimentGenerator {
  _GeneratingWorkflow(this.projects);

  final _Projects projects;
  final _progress = StreamController<TranscriptionProgress>.broadcast(
    sync: true,
  );
  final release = Completer<void>();
  int generations = 0;

  @override
  Stream<TranscriptionProgress> get progressStream => _progress.stream;

  @override
  bool get canGenerateAccompaniment => true;

  @override
  Future<AccompanimentGeneration> generateAccompaniment(
    String projectId,
  ) async {
    generations++;
    _progress.add(
      const TranscriptionProgress(
        stage: TranscriptionStage.preprocessing,
        progress: 0.5,
        message: '正在分离人声 30%',
      ),
    );
    await release.future;
    projects.project = projects.project.copyWith(
      audioAsset: linkAutomaticAccompaniment(
        projects.project.audioAsset!,
        path: '/stems/accompaniment.wav',
        generatedAt: DateTime.utc(2026, 11, 22),
      ),
    );
    return AccompanimentGeneration(
      const VocalSeparationOutcome.separated(
        vocalPath: '/stems/vocals.wav',
        accompanimentPath: '/stems/accompaniment.wav',
        provider: 'dml',
        elapsed: Duration(seconds: 70),
        separatorRevision: 'htdemucs-ft-vocals-onnx-v1',
      ),
      project: projects.project,
    );
  }
}

class _LoadedSettings extends Fake implements TranscriptionSettingsStore {
  @override
  Future<TranscriptionConfig?> load() async =>
      const TranscriptionConfig(whisperExecutable: 'whisper', modelPath: 'm');
}

class _Runtime extends Fake implements AsrRuntimeManager {}

class _Preflight extends Fake implements AsrStoragePreflightService {}

class _Storage extends Fake implements AsrManagedStorageService {}

class _Settings extends Fake implements TranscriptionSettingsStore {}

class _Profiles extends Fake implements TranscriptionProfileResolver {}

class _Connection extends Fake implements AsrDownloadConnectionChecker {}

class _Proxy extends Fake implements TranscriptionDownloadProxyStore {}
