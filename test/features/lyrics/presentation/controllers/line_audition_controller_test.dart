import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_audition_window_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/controllers/line_audition_controller.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  late _FakeAudioPlayer audio;
  late _FakePlaybackSession session;
  late List<Object> boundaryErrors;
  late LineAuditionController controller;

  const window = LyricAuditionWindow(
    startAt: Duration(seconds: 10),
    endAt: Duration(seconds: 14),
    canAudition: true,
  );
  const request = LineAuditionRequest(
    projectId: 'p1',
    lineIndex: 0,
    lineId: 'line-a',
    window: window,
  );

  setUp(() {
    boundaryErrors = <Object>[];
    audio = _FakeAudioPlayer();
    session = _FakePlaybackSession(projectId: 'p1');
    controller = LineAuditionController(
      audioService: audio,
      playbackSession: session,
      onBoundaryError: boundaryErrors.add,
    );
  });

  tearDown(() async {
    controller.dispose();
    await audio.dispose();
    await session.dispose();
  });

  Future<void> noPrepare() async {}

  // The real caller loads the project into the queue; the fake session only
  // knows that it happened because prepare did it.
  Future<void> prepareProject() => session.playItem(
    PlaybackItem(
      id: 'project:p1',
      title: 'p1',
      projectId: 'p1',
      audioAsset: const AudioAsset(originalPath: '/a.mp3', format: 'mp3'),
    ),
  );

  group('开始试听', () {
    test('跳过前奏并开始播放', () async {
      final result = await controller.start(
        request: request,
        prepare: noPrepare,
      );

      expect(result.action, LineAuditionAction.started);
      expect(session.seeks, <Duration>[const Duration(seconds: 10)]);
      expect(audio.isPlaying, isTrue);
      expect(controller.isActive, isTrue);
    });

    test('队列里是别的工程时先装载本工程', () async {
      session.setProject('other');

      await controller.start(request: request, prepare: prepareProject);

      expect(session.playItemCalls, 1);
    });

    test('队列已经是本工程时不再重复装载', () async {
      await controller.start(request: request, prepare: prepareProject);

      expect(session.playItemCalls, 0);
    });

    test('时间窗无效时不播放，并清掉旧的试听', () async {
      await controller.start(request: request, prepare: noPrepare);

      final result = await controller.start(
        request: const LineAuditionRequest(
          projectId: 'p1',
          lineIndex: 1,
          lineId: 'line-b',
          window: LyricAuditionWindow(
            startAt: Duration(seconds: 300),
            endAt: Duration(seconds: 300),
            canAudition: false,
          ),
        ),
        prepare: noPrepare,
      );

      expect(result.action, LineAuditionAction.invalid);
      expect(controller.isActive, isFalse);
      expect(audio.isPlaying, isFalse, reason: '无效时间窗期间应停止出声');
    });

    test('播放器没有真正开始播放时返回失败原因', () async {
      audio.refusePlayback = true;

      final result = await controller.start(
        request: request,
        prepare: noPrepare,
      );

      expect(result.action, LineAuditionAction.failed);
      expect(result.error, contains('播放器未进入播放状态'));
    });
  });

  group('行按钮的暂停 / 继续', () {
    test('同一个窗口在播放时暂停', () async {
      await controller.start(request: request, prepare: noPrepare);
      audio.emitPosition(const Duration(seconds: 11));

      final result = await controller.toggle(
        request: request,
        prepare: noPrepare,
      );

      expect(result.action, LineAuditionAction.paused);
      expect(audio.isPlaying, isFalse);
    });

    test('同一个窗口停在窗口内时直接继续播放，不重新跳转', () async {
      await controller.start(request: request, prepare: noPrepare);
      await audio.pause();
      audio.emitPosition(const Duration(seconds: 12));
      final seeksBefore = session.seeks.length;

      final result = await controller.toggle(
        request: request,
        prepare: noPrepare,
      );

      expect(result.action, LineAuditionAction.resumed);
      expect(session.seeks.length, seeksBefore);
      expect(audio.isPlaying, isTrue);
    });

    test('同一个窗口已经播过结尾时重新从头开始', () async {
      await controller.start(request: request, prepare: noPrepare);
      await audio.pause();
      audio.emitPosition(const Duration(seconds: 20));

      final result = await controller.toggle(
        request: request,
        prepare: noPrepare,
      );

      expect(result.action, LineAuditionAction.started);
      expect(session.seeks.last, const Duration(seconds: 10));
    });
  });

  group('distinct windows and stale preview conditions', () {
    const alternative = LineAuditionRequest(
      projectId: 'p1',
      lineIndex: 0,
      lineId: 'line-a',
      window: LyricAuditionWindow(
        startAt: Duration(seconds: 20),
        endAt: Duration(seconds: 22),
        canAudition: true,
      ),
    );

    test(
      'same row, different interval starts new playback instead of pausing',
      () async {
        await controller.start(request: request, prepare: noPrepare);
        final result = await controller.toggle(
          request: alternative,
          prepare: noPrepare,
        );
        expect(result.action, LineAuditionAction.started);
        expect(session.seeks, [
          const Duration(seconds: 10),
          const Duration(seconds: 20),
        ]);
        expect(controller.active!.window.endAt, const Duration(seconds: 22));
        expect(audio.isPlaying, isTrue);
      },
    );

    test(
      'same row, different interval while paused starts from its own start',
      () async {
        await controller.start(request: request, prepare: noPrepare);
        await audio.pause();
        audio.emitPosition(const Duration(seconds: 11));
        final result = await controller.toggle(
          request: alternative,
          prepare: noPrepare,
        );
        expect(result.action, LineAuditionAction.started);
        expect(session.seeks.last, const Duration(seconds: 20));
        expect(audio.isPlaying, isTrue);
      },
    );

    test(
      'different controls with identical windows start independently',
      () async {
        await controller.start(request: request, prepare: noPrepare);
        const reference = LineAuditionRequest(
          projectId: 'p1',
          lineIndex: 0,
          lineId: 'line-a',
          previewKey: 'reference:0',
          window: window,
        );
        final result = await controller.toggle(
          request: reference,
          prepare: noPrepare,
        );
        expect(result.action, LineAuditionAction.started);
        expect(session.seeks, [
          const Duration(seconds: 10),
          const Duration(seconds: 10),
        ]);
        expect(controller.active!.previewKey, 'reference:0');
        expect(audio.pauseCalls, 0);
      },
    );

    test('a stale request cannot interrupt an active audition', () async {
      await controller.start(request: request, prepare: noPrepare);
      final result = await controller.toggle(
        request: alternative,
        prepare: noPrepare,
        isStillValid: () => false,
      );
      expect(result.action, LineAuditionAction.failed);
      expect(session.seeks, [const Duration(seconds: 10)]);
      expect(controller.active!.window.endAt, const Duration(seconds: 14));
      expect(audio.isPlaying, isTrue);
    });

    test('validation runs again after a delayed prepare', () async {
      session.setProject('other');
      final gate = Completer<void>();
      var valid = true;
      final pending = controller.start(
        request: request,
        prepare: () => gate.future,
        isStillValid: () => valid,
      );
      valid = false;
      gate.complete();
      final result = await pending;
      expect(result.action, LineAuditionAction.failed);
      expect(session.seeks, isEmpty);
      expect(audio.isPlaying, isFalse);
    });
  });

  group('audition source changes', () {
    test(
      'a changed source clears the bound window without pausing new playback',
      () async {
        var sameSource = true;
        await controller.start(
          request: request,
          prepare: noPrepare,
          isPlaybackStillValid: () => sameSource,
        );
        sameSource = false;
        audio.emitPosition(const Duration(seconds: 14));
        await pumpEventQueue();
        expect(controller.isActive, isFalse);
        expect(audio.isPlaying, isTrue);
        expect(audio.pauseCalls, 0);
      },
    );

    test(
      'a stale bound does not make a later toggle pause a different source',
      () async {
        var sameSource = true;
        await controller.start(
          request: request,
          prepare: noPrepare,
          isPlaybackStillValid: () => sameSource,
        );
        sameSource = false;
        final result = await controller.toggle(
          request: request,
          prepare: noPrepare,
        );
        expect(result.action, LineAuditionAction.started);
        expect(audio.pauseCalls, 0);
        expect(session.seeks, [
          const Duration(seconds: 10),
          const Duration(seconds: 10),
        ]);
      },
    );

    test('unchanged source still pauses at its bound', () async {
      await controller.start(
        request: request,
        prepare: noPrepare,
        isPlaybackStillValid: () => true,
      );
      audio.emitPosition(const Duration(seconds: 14));
      await pumpEventQueue();
      expect(audio.isPlaying, isFalse);
      expect(audio.pauseCalls, 1);
    });
  });

  group('播放到窗口结尾', () {
    test('不循环时在结尾暂停', () async {
      await controller.start(request: request, prepare: noPrepare);

      audio.emitPosition(const Duration(seconds: 14));
      await pumpEventQueue();

      expect(audio.isPlaying, isFalse);
      expect(controller.isActive, isTrue, reason: '暂停不等于丢弃当前行');
    });

    test('循环时回到窗口起点继续播放', () async {
      await controller.start(request: request, prepare: noPrepare);
      controller.loopEnabled = true;
      session.seeks.clear();

      audio.emitPosition(const Duration(seconds: 14));
      await pumpEventQueue();

      expect(session.seeks, <Duration>[const Duration(seconds: 10)]);
      expect(audio.isPlaying, isTrue);
    });

    test('结尾事件处理期间再次到达不会重复触发', () async {
      await controller.start(request: request, prepare: noPrepare);
      audio.pauseGate = Completer<void>();

      audio.emitPosition(const Duration(seconds: 14));
      audio.emitPosition(const Duration(seconds: 15));
      await pumpEventQueue();

      expect(audio.pauseCalls, 1);
      audio.pauseGate!.complete();
      await pumpEventQueue();
    });

    test('播放队列切到别的工程时丢弃当前行', () async {
      await controller.start(request: request, prepare: noPrepare);

      session.setProject('other');
      audio.emitPosition(const Duration(seconds: 11));
      await pumpEventQueue();

      expect(controller.isActive, isFalse);
    });
  });

  group('高亮行定位', () {
    test('按稳定 lineId 跟随行移动', () async {
      final document = _document(const [
        _Line(id: 'line-x', text: '别的行'),
        _Line(id: 'line-a', text: '当前行'),
      ]);

      // Started on line index 0; the document now has it at index 1.
      await controller.start(request: request, prepare: noPrepare);

      expect(controller.activeLineIndex(document), 1);
    });

    test('行被删除后不再指向任何一行', () async {
      await controller.start(request: request, prepare: noPrepare);

      final document = _document(const [_Line(id: 'line-x', text: '别的行')]);

      expect(controller.activeLineIndex(document), isNull);
    });

    test('队列不在本工程时高亮消失', () async {
      await controller.start(request: request, prepare: noPrepare);
      session.setProject('other');

      expect(
        controller.activeLineIndex(
          _document(const [_Line(id: 'line-a', text: '当前行')]),
        ),
        isNull,
      );
    });
  });

  test('循环开关只在变化时通知', () {
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    controller.loopEnabled = true;
    controller.loopEnabled = true;
    controller.loopEnabled = false;

    expect(notifications, 2);
  });

  test('边界动作抛错时上报而不是静默吞掉', () async {
    await controller.start(request: request, prepare: noPrepare);
    audio.throwOnPause = true;

    audio.emitPosition(const Duration(seconds: 14));
    await pumpEventQueue();

    expect(boundaryErrors, hasLength(1));
  });
}

LyricDocument _document(List<_Line> lines) {
  return LyricDocument(
    language: 'zh',
    lines: [
      for (final line in lines)
        LyricLine(
          id: line.id,
          text: line.text,
          startTime: Duration.zero,
          endTime: const Duration(seconds: 4),
        ),
    ],
  );
}

class _Line {
  const _Line({required this.id, required this.text});

  final String id;
  final String text;
}

class _FakeAudioPlayer implements AudioPlayerService {
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast();
  PlaybackState _state = const PlaybackState.idle();

  bool refusePlayback = false;
  bool throwOnPause = false;
  int pauseCalls = 0;
  Completer<void>? pauseGate;
  Duration position = Duration.zero;

  bool get isPlaying => _state.isPlaying;

  void emitPosition(Duration value) {
    position = value;
    _state = _state.copyWith(position: value);
    _positions.add(value);
  }

  @override
  PlaybackState get currentState => _state;

  @override
  Stream<PlaybackState> get stateStream => const Stream<PlaybackState>.empty();

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<Duration?> get durationStream => const Stream<Duration?>.empty();

  @override
  Future<void> play() async {
    if (refusePlayback) return;
    _state = _state.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    if (throwOnPause) throw StateError('pause failed');
    final gate = pauseGate;
    if (gate != null) await gate.future;
    _state = _state.copyWith(isPlaying: false);
  }

  @override
  Future<void> stop() async {
    _state = _state.copyWith(isPlaying: false, position: Duration.zero);
  }

  @override
  Future<void> seek(Duration target) async {
    position = target;
    _state = _state.copyWith(position: target);
  }

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> switchSource(AudioSourceType source) async {}

  @override
  Future<void> loadProjectAudio({
    required AudioAsset audioAsset,
    AudioSourceType preferredSource = AudioSourceType.instrumental,
  }) async {}

  @override
  Future<void> loadAudioUri({
    required Uri uri,
    AudioSourceType source = AudioSourceType.original,
  }) async {}

  @override
  Future<void> dispose() async {
    await _positions.close();
  }
}

class _FakePlaybackSession implements PlaybackSessionService {
  _FakePlaybackSession({required String projectId}) {
    setProject(projectId);
  }

  final List<Duration> seeks = <Duration>[];
  int playItemCalls = 0;
  String _projectId = '';
  late PlaybackSessionState _state;

  void setProject(String projectId) {
    _projectId = projectId;
    _state = PlaybackSessionState(
      queue: [
        PlaybackItem(
          id: 'project:$projectId',
          title: projectId,
          projectId: projectId,
          audioAsset: const AudioAsset(originalPath: '/a.mp3', format: 'mp3'),
        ),
      ],
      currentIndex: 0,
    );
  }

  @override
  PlaybackSessionState get currentState => _state;

  @override
  Stream<PlaybackSessionState> get stateStream =>
      const Stream<PlaybackSessionState>.empty();

  @override
  PlaybackState get playbackState => const PlaybackState.idle();

  @override
  Future<void> playItem(PlaybackItem item, {Duration? resumeFrom}) async {
    playItemCalls += 1;
    setProject(item.projectId ?? _projectId);
  }

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  @override
  Future<void> togglePlayPause() async {}

  @override
  Future<void> skipPrevious() async {}

  @override
  Future<void> skipNext() async {}

  @override
  Future<void> setQueue(List<PlaybackItem> items, {int startIndex = 0}) async {}

  @override
  Future<void> enqueue(PlaybackItem item) async {}

  @override
  Future<void> updateItem(PlaybackItem item) async {}

  @override
  Future<void> playAt(int index) async {}

  @override
  Future<void> removeAt(int index) async {}

  @override
  Future<void> moveItem(int oldIndex, int newIndex) async {}

  @override
  Future<void> clearQueue({bool keepCurrent = true}) async {}

  @override
  Future<void> setShuffleEnabled(bool enabled) async {}

  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {}

  @override
  Future<void> dispose() async {}
}
