import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/player/data/services/remote_rebinding_playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/remote_playback_item_resolver.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/transfer/data/services/media_hub_rebinding_audio_player_service.dart';
import 'package:lyric_forge_ktv/features/transfer/data/services/media_hub_remote_playback_item_resolver.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/media_hub_connection.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/remote_audio_track.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/services/media_hub_client_service.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/services/media_hub_connection_store.dart';

void main() {
  test('resolver rebinds stale stream and artwork URLs using saved connection',
      () async {
    const latest = MediaHubConnection(
      host: '10.0.0.8',
      port: 8844,
      token: 'new-token',
    );
    final client = _FakeMediaHubClient(
      tracks: const [
        RemoteAudioTrack(
          id: 'track-1',
          title: 'Fresh Title',
          artist: 'Fresh Artist',
          album: 'Fresh Album',
          format: 'flac',
          byteLength: 100,
          streamPath: '/v1/tracks/track-1/audio',
          downloadPath: '/v1/tracks/track-1/download',
          hasArtwork: true,
          artworkPath: '/v1/tracks/track-1/artwork',
        ),
      ],
    );
    final resolver = MediaHubRemotePlaybackItemResolver(
      client: client,
      connectionStore: _MemoryConnectionStore(latest),
    );
    final stale = _remoteItem(
      Uri.parse('http://192.168.1.4:4545/v1/tracks/track-1/audio?token=old'),
    );

    final resolved = await resolver.resolveForPlayback(stale);

    expect(client.connectCalls, 1);
    expect(resolved.id, stale.id, reason: 'queue identity must remain stable');
    expect(resolved.title, 'Fresh Title');
    expect(resolved.artist, 'Fresh Artist');
    expect(resolved.streamUri?.host, '10.0.0.8');
    expect(resolved.streamUri?.port, 8844);
    expect(resolved.streamUri?.queryParameters['token'], 'new-token');
    final artwork = Uri.parse(
      resolved.audioAsset.metadata['remoteArtworkUri'] as String,
    );
    expect(artwork.host, '10.0.0.8');
    expect(artwork.queryParameters['token'], 'new-token');
    expect(resolved.audioAsset.metadata['album'], 'Fresh Album');
  });

  test('audio rebinder rewrites Media Hub URL even for internal queue loads',
      () async {
    const latest = MediaHubConnection(
      host: '172.16.0.9',
      port: 7788,
      token: 'current-token',
    );
    final client = _FakeMediaHubClient(tracks: const [])..connection = latest;
    final raw = _FakeAudioPlayer();
    final audio = MediaHubRebindingAudioPlayerService(
      delegate: raw,
      client: client,
      connectionStore: _MemoryConnectionStore(null),
    );

    await audio.loadAudioUri(
      uri: Uri.parse(
        'http://old-host:4000/v1/tracks/abc/audio?token=expired&quality=full',
      ),
    );

    expect(raw.lastLoadedUri?.host, '172.16.0.9');
    expect(raw.lastLoadedUri?.port, 7788);
    expect(raw.lastLoadedUri?.queryParameters['token'], 'current-token');
    expect(raw.lastLoadedUri?.queryParameters['quality'], 'full');
  });

  test('restored remote session stays offline until explicit playback action',
      () async {
    final stale = _remoteItem(
      Uri.parse('http://old-host:4000/v1/tracks/track-1/audio?token=old'),
    );
    final fresh = stale.copyWith(
      streamUri: Uri.parse(
        'http://new-host:5000/v1/tracks/track-1/audio?token=new',
      ),
      audioAsset: stale.audioAsset.copyWith(
        originalPath:
            'http://new-host:5000/v1/tracks/track-1/audio?token=new',
      ),
    );
    final delegate = _FakePlaybackSession(stale);
    final resolver = _FakeResolver(fresh);
    final session = RemoteRebindingPlaybackSessionService(
      delegate: delegate,
      resolver: resolver,
    );
    addTearDown(session.dispose);

    await Future<void>.delayed(Duration.zero);
    expect(resolver.calls, 0, reason: 'construction/restore must not network');

    await session.togglePlayPause();

    expect(resolver.calls, 1);
    expect(delegate.updatedItems.single.id, stale.id);
    expect(delegate.currentState.currentItem?.streamUri, fresh.streamUri);
    expect(delegate.toggleCalls, 1);
  });

  test('resolver failure keeps the restored queue untouched', () async {
    final stale = _remoteItem(
      Uri.parse('http://old-host:4000/v1/tracks/track-1/audio?token=old'),
    );
    final delegate = _FakePlaybackSession(stale);
    final session = RemoteRebindingPlaybackSessionService(
      delegate: delegate,
      resolver: const _FailingResolver(),
    );
    addTearDown(session.dispose);

    await expectLater(
      session.togglePlayPause(),
      throwsA(isA<RemotePlaybackResolutionException>()),
    );
    expect(delegate.currentState.currentItem?.streamUri, stale.streamUri);
    expect(delegate.updatedItems, isEmpty);
    expect(delegate.toggleCalls, 0);
  });
}

PlaybackItem _remoteItem(Uri uri) {
  return PlaybackItem(
    id: 'remote:desktop:track-1',
    title: 'Old Title',
    artist: 'Old Artist',
    streamUri: uri,
    audioAsset: AudioAsset(
      originalPath: uri.toString(),
      format: 'mp3',
      duration: const Duration(minutes: 3),
      metadata: const <String, dynamic>{
        'transferSource': 'media-hub-stream',
        'remoteTrackId': 'track-1',
        'remoteArtworkUri':
            'http://old-host:4000/v1/tracks/track-1/artwork?token=old',
      },
    ),
  );
}

class _MemoryConnectionStore implements MediaHubConnectionStore {
  MediaHubConnection? value;

  _MemoryConnectionStore(this.value);

  @override
  Future<MediaHubConnection?> loadLastConnection() async => value;

  @override
  Future<void> saveConnection(MediaHubConnection connection) async {
    value = connection;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class _FakeMediaHubClient implements MediaHubClientService {
  final List<RemoteAudioTrack> tracks;
  MediaHubConnection? connection;
  int connectCalls = 0;

  _FakeMediaHubClient({required this.tracks});

  @override
  MediaHubConnection? get currentConnection => connection;

  @override
  bool get isConnected => connection != null;

  @override
  Future<MediaHubConnection> connect(Uri pairingUri) async {
    final parsed = MediaHubConnection.fromPairingUri(pairingUri);
    await connectTo(parsed);
    return parsed;
  }

  @override
  Future<void> connectTo(MediaHubConnection connection) async {
    connectCalls++;
    this.connection = connection;
  }

  @override
  Future<void> disconnect() async {
    connection = null;
  }

  @override
  Future<List<RemoteAudioTrack>> fetchTracks() async => tracks;

  @override
  Uri playbackUriFor(RemoteAudioTrack track) {
    final current = connection!;
    return current.resolve(track.streamPath).replace(
      queryParameters: {'token': current.token},
    );
  }

  @override
  Future<LyricDocument?> fetchLyrics(RemoteAudioTrack track) async => null;

  @override
  Future<void> downloadTrack({
    required RemoteAudioTrack track,
    required String destinationPath,
    TransferProgressCallback? onProgress,
  }) async {}

  @override
  Future<void> uploadFile({
    required String sourcePath,
    String? remoteFileName,
    TransferProgressCallback? onProgress,
  }) async {}

  @override
  Future<void> dispose() async {}
}

class _FakeAudioPlayer implements AudioPlayerService {
  final StreamController<PlaybackState> _state =
      StreamController<PlaybackState>.broadcast();
  final StreamController<Duration> _position =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _duration =
      StreamController<Duration?>.broadcast();
  PlaybackState playbackState = const PlaybackState.idle();
  Uri? lastLoadedUri;

  @override
  PlaybackState get currentState => playbackState;

  @override
  Stream<PlaybackState> get stateStream => _state.stream;

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<Duration?> get durationStream => _duration.stream;

  @override
  Future<void> loadAudioUri({
    required Uri uri,
    AudioSourceType source = AudioSourceType.original,
  }) async {
    lastLoadedUri = uri;
  }

  @override
  Future<void> loadProjectAudio({
    required AudioAsset audioAsset,
    AudioSourceType preferredSource = AudioSourceType.instrumental,
  }) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> switchSource(AudioSourceType source) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async {
    await _state.close();
    await _position.close();
    await _duration.close();
  }
}

class _FakeResolver implements RemotePlaybackItemResolver {
  final PlaybackItem resolved;
  int calls = 0;

  _FakeResolver(this.resolved);

  @override
  Future<PlaybackItem> resolveForPlayback(PlaybackItem item) async {
    calls++;
    return resolved;
  }
}

class _FailingResolver implements RemotePlaybackItemResolver {
  const _FailingResolver();

  @override
  Future<PlaybackItem> resolveForPlayback(PlaybackItem item) {
    throw const RemotePlaybackResolutionException('请重新连接桌面音乐库');
  }
}

class _FakePlaybackSession implements PlaybackSessionService {
  final StreamController<PlaybackSessionState> _stateController =
      StreamController<PlaybackSessionState>.broadcast();
  PlaybackSessionState _state;
  PlaybackState _playbackState = const PlaybackState.idle();
  final List<PlaybackItem> updatedItems = <PlaybackItem>[];
  int toggleCalls = 0;

  _FakePlaybackSession(PlaybackItem item)
      : _state = PlaybackSessionState(queue: [item], currentIndex: 0);

  @override
  Stream<PlaybackSessionState> get stateStream => _stateController.stream;

  @override
  PlaybackSessionState get currentState => _state;

  @override
  PlaybackState get playbackState => _playbackState;

  @override
  Future<void> updateItem(PlaybackItem item) async {
    final queue = List<PlaybackItem>.from(_state.queue);
    final index = queue.indexWhere((candidate) => candidate.id == item.id);
    if (index < 0) return;
    queue[index] = item;
    updatedItems.add(item);
    _state = _state.copyWith(queue: List<PlaybackItem>.unmodifiable(queue));
    _stateController.add(_state);
  }

  @override
  Future<void> togglePlayPause() async {
    toggleCalls++;
    _playbackState = _playbackState.copyWith(
      isPlaying: !_playbackState.isPlaying,
    );
  }

  @override
  Future<void> playItem(PlaybackItem item, {Duration? resumeFrom}) async {}

  @override
  Future<void> setQueue(List<PlaybackItem> items, {int startIndex = 0}) async {}

  @override
  Future<void> enqueue(PlaybackItem item) async {}

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
  Future<void> skipPrevious() async {}

  @override
  Future<void> skipNext() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> dispose() async {
    await _stateController.close();
  }
}
