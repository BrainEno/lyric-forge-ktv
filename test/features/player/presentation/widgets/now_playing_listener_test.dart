import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/widgets/app_song_row.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/now_playing_listener.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

PlaybackItem _local(String path, {String title = '晴天'}) => PlaybackItem(
  id: 'local:$path',
  title: title,
  audioAsset: AudioAsset(originalPath: path, format: 'mp3'),
);

PlaybackItem _stream(String path) => PlaybackItem(
  id: 'remote:1',
  title: '远程',
  streamUri: Uri.parse('http://desktop.local/stream/1'),
  audioAsset: AudioAsset(originalPath: path, format: 'mp3'),
);

PlaybackState _state({required bool playing, int positionMs = 0}) =>
    PlaybackState(
      isPlaying: playing,
      isBuffering: false,
      isCompleted: false,
      isLoading: false,
      position: Duration(milliseconds: positionMs),
      duration: const Duration(minutes: 4),
      bufferedPosition: Duration.zero,
      volume: 1,
      speed: 1,
    );

void main() {
  final song = '${Directory.systemTemp.path}/now_playing/晴天.mp3';
  final other = '${Directory.systemTemp.path}/now_playing/稻香.mp3';

  group('NowPlaying', () {
    test('marks the row of the current local file', () {
      final playing = NowPlaying(item: _local(song), isPlaying: true);
      expect(playing.localPath, song);
      expect(playing.playbackForPath(song), AppSongRowPlayback.playing);
      expect(playing.playbackForPath(other), AppSongRowPlayback.none);

      final paused = NowPlaying(item: _local(song));
      expect(paused.playbackForPath(song), AppSongRowPlayback.paused);
    });

    test('a relative and an absolute path of one file match', () {
      const relative = 'music/晴天.mp3';
      final playing = NowPlaying(
        item: _local(File(relative).absolute.path),
        isPlaying: true,
      );
      expect(playing.playbackForPath(relative), AppSongRowPlayback.playing);
    });

    test('a stream marks no local row', () {
      final stream = NowPlaying(item: _stream(song), isPlaying: true);
      expect(stream.localPath, isNull);
      expect(stream.playbackForPath(song), AppSongRowPlayback.none);
    });

    test('nothing loaded marks nothing', () {
      expect(NowPlaying.none.item, isNull);
      expect(NowPlaying.none.playbackForPath(song), AppSongRowPlayback.none);
    });

    test('two values are equal when song and state match', () {
      expect(
        NowPlaying(item: _local(song), isPlaying: true),
        NowPlaying(item: _local(song, title: '改过的标题'), isPlaying: true),
      );
      expect(
        NowPlaying(item: _local(song), isPlaying: true),
        isNot(NowPlaying(item: _local(song))),
      );
      expect(
        NowPlaying(item: _local(song)).hashCode,
        NowPlaying(item: _local(song)).hashCode,
      );
    });
  });

  group('NowPlayingListener', () {
    // A stream event lands after the frame that `pump` checks for, so the
    // rebuild it asks for is drawn by the next one.
    Future<void> deliver(WidgetTester tester) async {
      await tester.pump();
      await tester.pump();
    }

    late _Session session;
    late _Audio audio;
    late List<NowPlaying> builds;

    setUp(() {
      session = _Session(
        PlaybackSessionState(queue: [_local(song)], currentIndex: 0),
      );
      audio = _Audio(_state(playing: false));
      builds = [];
    });

    tearDown(() async {
      await session.close();
      await audio.close();
    });

    Widget host() => MaterialApp(
      home: NowPlayingListener(
        playbackSession: session,
        audioPlayer: audio,
        builder: (context, nowPlaying) {
          builds.add(nowPlaying);
          return Text(nowPlaying.item?.title ?? '无');
        },
      ),
    );

    testWidgets('starts from the current values', (tester) async {
      await tester.pumpWidget(host());

      expect(find.text('晴天'), findsOneWidget);
      expect(builds.single.isPlaying, isFalse);
    });

    testWidgets('follows play and pause', (tester) async {
      await tester.pumpWidget(host());

      audio.emit(_state(playing: true));
      await deliver(tester);
      expect(builds.last.isPlaying, isTrue);

      audio.emit(_state(playing: false));
      await deliver(tester);
      expect(builds.last.isPlaying, isFalse);
      expect(builds, hasLength(3));
    });

    testWidgets('follows the song', (tester) async {
      await tester.pumpWidget(host());

      session.emit(
        PlaybackSessionState(
          queue: [_local(other, title: '稻香')],
          currentIndex: 0,
        ),
      );
      await deliver(tester);

      expect(find.text('稻香'), findsOneWidget);
      expect(builds.last.localPath, other);
    });

    testWidgets('ignores position reports that change nothing', (tester) async {
      await tester.pumpWidget(host());
      audio.emit(_state(playing: true));
      await deliver(tester);
      final before = builds.length;

      for (var ms = 200; ms <= 2000; ms += 200) {
        audio.emit(_state(playing: true, positionMs: ms));
        await deliver(tester);
      }

      expect(builds, hasLength(before));
    });

    testWidgets('a stopped queue is never shown as playing', (tester) async {
      await tester.pumpWidget(host());
      session.emit(const PlaybackSessionState());
      audio.emit(_state(playing: true));
      await deliver(tester);

      expect(builds.last.item, isNull);
      expect(builds.last.isPlaying, isFalse);
      expect(find.text('无'), findsOneWidget);
    });

    testWidgets('stops listening when it leaves the tree', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpWidget(const SizedBox());

      expect(session.hasListener, isFalse);
      expect(audio.hasListener, isFalse);
    });
  });
}

class _Session implements PlaybackSessionService {
  _Session(this.currentState);

  final _controller = StreamController<PlaybackSessionState>.broadcast();

  @override
  PlaybackSessionState currentState;

  bool get hasListener => _controller.hasListener;

  void emit(PlaybackSessionState state) {
    currentState = state;
    _controller.add(state);
  }

  Future<void> close() => _controller.close();

  @override
  Stream<PlaybackSessionState> get stateStream => _controller.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Audio implements AudioPlayerService {
  _Audio(this.currentState);

  final _controller = StreamController<PlaybackState>.broadcast();

  @override
  PlaybackState currentState;

  bool get hasListener => _controller.hasListener;

  void emit(PlaybackState state) {
    currentState = state;
    _controller.add(state);
  }

  Future<void> close() => _controller.close();

  @override
  Stream<PlaybackState> get stateStream => _controller.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
