import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/navigation/app_chrome_controller.dart';
import 'package:lyric_forge_ktv/core/widgets/app_error_state.dart';
import 'package:lyric_forge_ktv/features/player/data/services/file_audio_path_canonicalizer.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/audio_preview_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/ktv_microphone_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/ktv_recording_session.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_metadata_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_preview_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/ktv_microphone_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/ktv_recording_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/ktv_take_history_store.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/presentation/playback_screen_dependencies.dart';
import 'package:lyric_forge_ktv/features/player/presentation/screens/immersive_ktv_screen.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/fullscreen_ktv_lyric_stage.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/ktv_recording_toolbar.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/ktv_take_history_sheet.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';

/// The fullscreen KTV screen lost every recording entry point when the
/// unreachable `_FullScreenKtvView` was deleted: the services existed, the UI
/// existed, nothing linked them. These tests assert the entry points on the
/// real screen (not by scanning its source) and that the mutation guard is
/// reachable from it.
void main() {
  final project = ProjectManifest(
    id: 'song',
    name: 'Song',
    createdAt: DateTime.utc(2026, 10, 10),
    updatedAt: DateTime.utc(2026, 10, 10),
    audioAsset: const AudioAsset(
      originalPath: '/music/backing.wav',
      format: 'wav',
    ),
    lyricDocument: const LyricDocument(
      language: 'zh',
      lines: [
        LyricLine(
          text: '一',
          startTime: Duration.zero,
          endTime: Duration(seconds: 2),
        ),
      ],
    ),
  );

  late _FakeRecordingService recording;
  late _FakeMicrophoneService microphone;

  setUp(() {
    recording = _FakeRecordingService();
    microphone = _FakeMicrophoneService();
  });

  Widget buildScreen({
    _FakePlaybackSession? session,
    _FakeProjectRepository? projects,
  }) => ImmersiveKtvScreen(
    initialProjectId: project.id,
    dependencies: ImmersiveKtvDependencies(
      projectRepository: projects ?? _FakeProjectRepository(project),
      metadataRepository: _FakeMetadataRepository(),
      audioPlayer: _FakeAudioPlayerService(),
      playbackSession: session ?? _FakePlaybackSession(),
      pathCanonicalizer: const FileAudioPathCanonicalizer(),
      microphoneService: microphone,
      recordingService: recording,
      takeHistoryStore: _FakeTakeHistoryStore(),
      previewService: _FakePreviewService(),
    ),
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    _FakePlaybackSession? session,
    _FakeProjectRepository? projects,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: buildScreen(session: session, projects: projects),
      ),
    );
    // One frame for the project load, one more for the toolbar to rebuild with
    // the project in hand (until then its entry points are disabled).
    await tester.pump();
    await tester.pump();
  }

  Future<void> disposeScreen(WidgetTester tester) async {
    // Disposes the surface's idle-hide timer along with the screen.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('全屏 KTV 进出场不会在祖先 build/卸载期间通知应用 chrome', (tester) async {
    var showKtv = true;
    late StateSetter setHostState;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return ValueListenableBuilder<bool>(
              valueListenable: AppChromeController.immersive,
              builder: (_, _, _) =>
                  showKtv ? buildScreen() : const SizedBox.shrink(),
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(AppChromeController.immersive.value, isTrue);

    setHostState(() => showKtv = false);
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(AppChromeController.immersive.value, isFalse);
  });

  testWidgets('全屏 KTV 上有录音、演唱历史和麦克风入口', (tester) async {
    await pumpScreen(tester);

    for (final key in [
      KtvRecordingToolbar.recordButtonKey,
      KtvRecordingToolbar.historyButtonKey,
      KtvRecordingToolbar.microphoneButtonKey,
    ]) {
      final button = tester.widget<IconButton>(find.byKey(key));
      expect(button.onPressed, isNotNull, reason: '$key 应当可点击');
    }

    await disposeScreen(tester);
  });

  testWidgets('点击录音按钮用当前工程开始录制', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(KtvRecordingToolbar.recordButtonKey));
    // The surface also listens for double taps, so a single tap only resolves
    // after the double-tap timeout.
    await tester.pump(const Duration(milliseconds: 400));

    expect(recording.log, ['start:song']);

    await disposeScreen(tester);
  });

  testWidgets('导出进行中时录音按钮停用，历史入口给出导出提示', (tester) async {
    recording.emit(const KtvRecordingState(isExporting: true));
    await pumpScreen(tester);

    final record = tester.widget<IconButton>(
      find.byKey(KtvRecordingToolbar.recordButtonKey),
    );
    expect(record.onPressed, isNull);
    final history = tester.widget<IconButton>(
      find.byKey(KtvRecordingToolbar.historyButtonKey),
    );
    expect(history.onPressed, isNull);

    // Nothing opened behind the disabled button.
    expect(find.byType(KtvTakeHistorySheet), findsNothing);

    await disposeScreen(tester);
  });

  testWidgets('退出全屏 KTV 会停止仍在进行的录音', (tester) async {
    recording.emit(const KtvRecordingState(isRecording: true));
    await pumpScreen(tester);

    await disposeScreen(tester);
    await tester.pump();

    expect(recording.log, contains('stop'));
  });

  group('控制层', () {
    const song = PlaybackItem(
      id: 'song',
      title: 'Song (queue)',
      artist: '歌手',
      audioAsset: AudioAsset(originalPath: '/music/song.wav', format: 'wav'),
    );
    const other = PlaybackItem(
      id: 'other',
      title: 'Other',
      audioAsset: AudioAsset(originalPath: '/music/other.wav', format: 'wav'),
    );
    const playing = PlaybackState(
      isPlaying: true,
      isBuffering: false,
      isCompleted: false,
      isLoading: false,
      position: Duration(seconds: 30),
      duration: Duration(minutes: 3),
      bufferedPosition: Duration.zero,
      speed: 1,
      volume: 1,
    );

    _FakePlaybackSession playingSession() => _FakePlaybackSession(
      state: const PlaybackSessionState(queue: [song, other], currentIndex: 0),
      playback: playing,
    );

    Future<void> press(
      WidgetTester tester,
      LogicalKeyboardKey key, {
      LogicalKeyboardKey? modifier,
    }) async {
      if (modifier != null) await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyUpEvent(key);
      if (modifier != null) await tester.sendKeyUpEvent(modifier);
      await tester.pump();
    }

    testWidgets('标题醒目，下面是歌手；上下各有一层渐变遮罩', (tester) async {
      await pumpScreen(tester, session: playingSession());

      final title = tester.widget<Text>(
        find.byKey(ImmersiveKtvScreen.titleKey),
      );
      expect(title.data, 'Song');
      expect(title.style?.fontWeight, FontWeight.w700);
      expect(find.text('歌手'), findsOneWidget);

      for (final key in [
        ImmersiveKtvScreen.topScrimKey,
        ImmersiveKtvScreen.bottomScrimKey,
      ]) {
        final box = tester.widget<DecoratedBox>(find.byKey(key));
        final gradient =
            (box.decoration as BoxDecoration).gradient! as LinearGradient;
        expect(
          gradient.colors.first.a,
          closeTo(ImmersiveKtvScreen.scrimAlpha, 0.01),
        );
        expect(gradient.colors.last.a, closeTo(0, 0.01));
      }
      expect(find.byTooltip(ImmersiveKtvScreen.exitTooltip), findsOneWidget);

      await disposeScreen(tester);
    });

    testWidgets('桌面端显示按键提示，移动端不显示', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await pumpScreen(tester);
      final hint = tester.widget<Text>(
        find.byKey(ImmersiveKtvScreen.keyHintKey),
      );
      expect(hint.data, contains('空格 播放/暂停'));
      expect(hint.data, contains('Ctrl+←/→'));
      await disposeScreen(tester);

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await pumpScreen(tester);
      expect(find.byKey(ImmersiveKtvScreen.keyHintKey), findsNothing);
      await disposeScreen(tester);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('空格暂停，方向键快进快退，Ctrl+方向键切歌', (tester) async {
      final session = playingSession();
      await pumpScreen(tester, session: session);

      await press(tester, LogicalKeyboardKey.space);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(
        tester,
        LogicalKeyboardKey.arrowRight,
        modifier: LogicalKeyboardKey.controlLeft,
      );
      await press(
        tester,
        LogicalKeyboardKey.arrowLeft,
        modifier: LogicalKeyboardKey.controlLeft,
      );

      expect(session.log, ['toggle', 'seek:35', 'seek:25', 'next', 'previous']);

      await disposeScreen(tester);
    });

    testWidgets('按键会唤出已隐藏的控制层', (tester) async {
      final session = playingSession();
      await pumpScreen(tester, session: session);

      await tester.pump(const Duration(seconds: 4));
      final hidden = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.byKey(ImmersiveKtvScreen.titleKey),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(hidden.opacity, 0);

      await press(tester, LogicalKeyboardKey.arrowRight);
      final shown = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.byKey(ImmersiveKtvScreen.titleKey),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(shown.opacity, 1);
      expect(session.log, ['seek:35']);

      await disposeScreen(tester);
    });

    testWidgets('没有在播放的歌曲时按键不做任何事', (tester) async {
      final session = _FakePlaybackSession();
      await pumpScreen(tester, session: session);

      await press(tester, LogicalKeyboardKey.space);
      await press(tester, LogicalKeyboardKey.arrowRight);

      expect(session.log, isEmpty);

      await disposeScreen(tester);
    });

    testWidgets('歌词加载失败时显示统一的错误状态，重试后恢复', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final projects = _FakeProjectRepository(project, failures: 1);
      await pumpScreen(tester, projects: projects);

      expect(find.byKey(ImmersiveKtvScreen.errorKey), findsOneWidget);
      final error = tester.widget<AppErrorState>(
        find.byKey(ImmersiveKtvScreen.errorKey),
      );
      expect(error.title, ImmersiveKtvScreen.errorTitle);
      expect(error.message, contains('磁盘不可用'));
      expect(find.textContaining('歌词加载失败：'), findsNothing);

      await tester.tap(find.text(AppErrorState.defaultRetryLabel));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(projects.loads, 2);
      expect(find.byKey(ImmersiveKtvScreen.errorKey), findsNothing);
      expect(find.byType(FullscreenKtvLyricStage), findsOneWidget);
      expect(
        find.byKey(const ValueKey('fullscreen-ktv-empty-lyrics')),
        findsNothing,
      );

      await disposeScreen(tester);
    });
  });
}

class _FakeRecordingService implements KtvRecordingService {
  final StreamController<KtvRecordingState> _states =
      StreamController<KtvRecordingState>.broadcast();
  final List<String> log = <String>[];
  KtvRecordingState _state = const KtvRecordingState();

  void emit(KtvRecordingState state) {
    _state = state;
    _states.add(state);
  }

  @override
  KtvRecordingState get currentState => _state;

  @override
  Stream<KtvRecordingState> get stateStream => _states.stream;

  @override
  Future<void> startRecording(ProjectManifest project) async {
    log.add('start:${project.id}');
    emit(const KtvRecordingState(isRecording: true));
  }

  @override
  Future<KtvRecordingSession?> stopRecording() async {
    log.add('stop');
    emit(const KtvRecordingState());
    return null;
  }

  @override
  Future<KtvRecordingSession> exportMix(
    KtvRecordingSession session, {
    double voiceVolume = 1.0,
    double? backingVolume,
  }) async => session;

  @override
  Future<void> dispose() async {
    await _states.close();
  }
}

class _FakeMicrophoneService implements KtvMicrophoneService {
  final StreamController<KtvMicrophoneState> _states =
      StreamController<KtvMicrophoneState>.broadcast();
  final StreamController<Uint8List> _pcm =
      StreamController<Uint8List>.broadcast();

  @override
  KtvMicrophoneState get currentState => const KtvMicrophoneState();

  @override
  Stream<KtvMicrophoneState> get stateStream => _states.stream;

  @override
  Stream<Uint8List> get rawPcm16Stream => _pcm.stream;

  @override
  Future<void> refreshInputDevices() async {}

  @override
  Future<void> selectInputDevice(String? deviceId) async {}

  @override
  Future<void> startMonitoring() async {}

  @override
  Future<void> stopMonitoring() async {}

  @override
  Future<void> setMicGain(double gain) async {}

  @override
  Future<void> setMonitorDelay(Duration delay) async {}

  @override
  Future<void> dispose() async {
    await _states.close();
    await _pcm.close();
  }
}

class _FakeAudioPlayerService implements AudioPlayerService {
  final StreamController<PlaybackState> _states =
      StreamController<PlaybackState>.broadcast();

  @override
  PlaybackState get currentState => const PlaybackState.idle();

  @override
  Stream<PlaybackState> get stateStream => _states.stream;

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  Future<void> dispose() async {
    await _states.close();
  }

  @override
  Future<void> loadAudioUri({
    required Uri uri,
    AudioSourceType source = AudioSourceType.original,
  }) async {}

  @override
  Future<void> loadProjectAudio({
    required AudioAsset audioAsset,
    AudioSourceType preferredSource = AudioSourceType.instrumental,
  }) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> switchSource(AudioSourceType source) async {}
}

class _FakePlaybackSession implements PlaybackSessionService {
  _FakePlaybackSession({
    this.state = const PlaybackSessionState(),
    this.playback = const PlaybackState.idle(),
  });

  final PlaybackSessionState state;
  final PlaybackState playback;
  final List<String> log = <String>[];

  final StreamController<PlaybackSessionState> _states =
      StreamController<PlaybackSessionState>.broadcast();

  @override
  PlaybackSessionState get currentState => state;

  @override
  Stream<PlaybackSessionState> get stateStream => _states.stream;

  @override
  PlaybackState get playbackState => playback;

  @override
  Future<void> seek(Duration position) async {
    log.add('seek:${position.inSeconds}');
  }

  @override
  Future<void> togglePlayPause() async {
    log.add('toggle');
  }

  @override
  Future<void> skipPrevious() async {
    log.add('previous');
  }

  @override
  Future<void> skipNext() async {
    log.add('next');
  }

  @override
  Future<void> dispose() async {
    await _states.close();
  }

  /// The screen only touches the transport calls above; the rest of the
  /// session contract is irrelevant here.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProjectRepository implements ProjectRepository {
  _FakeProjectRepository(this.project, {this.failures = 0});

  final ProjectManifest project;

  /// How many loads fail before the project comes back.
  int failures;
  int loads = 0;

  @override
  Future<ProjectManifest?> getProjectById(String id) async {
    loads++;
    if (failures > 0) {
      failures--;
      throw StateError('磁盘不可用');
    }
    return id == project.id ? project : null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMetadataRepository implements LocalMediaMetadataRepository {
  @override
  Future<LocalMediaMetadata?> getForAudio(String sourcePath) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTakeHistoryStore implements KtvTakeHistoryStore {
  @override
  Future<KtvTakeHistoryScanResult> scanProject(ProjectManifest project) async =>
      const KtvTakeHistoryScanResult(takes: [], recoveredCount: 0);

  @override
  Future<List<KtvRecordingSession>> listProject(
    ProjectManifest project,
  ) async => const [];

  @override
  Future<KtvRecordingSession> updateProjectTakeMetadata(
    ProjectManifest project,
    KtvRecordingSession take, {
    String? displayName,
    bool clearDisplayName = false,
    bool? isFavorite,
  }) async => take;

  @override
  Future<void> deleteProjectTake(
    ProjectManifest project,
    KtvRecordingSession take,
  ) async {}
}

class _FakePreviewService implements AudioPreviewService {
  final StreamController<AudioPreviewState> _states =
      StreamController<AudioPreviewState>.broadcast();

  @override
  AudioPreviewState get currentState => const AudioPreviewState.idle();

  @override
  Stream<AudioPreviewState> get stateStream => _states.stream;

  @override
  Future<Duration?> loadFile(String path) async => const Duration(seconds: 30);

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _states.close();
  }
}
