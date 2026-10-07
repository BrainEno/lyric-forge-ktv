import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/library_metadata_playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_library_entry.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_state.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_library_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

void main() {
  late Directory cache;
  late HttpServer server;
  late _FakePlaybackSession delegate;
  late LibraryMetadataPlaybackSessionService session;
  var artworkRequests = 0;

  setUp(() async {
    cache = await Directory.systemTemp.createTemp('elysium-remote-artwork-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    delegate = _FakePlaybackSession();
    session = LibraryMetadataPlaybackSessionService(
      delegate: delegate,
      libraryRepository: _EmptyLibraryRepository(),
      remoteArtworkCacheDirectory: cache,
    );
    unawaited(
      server.forEach((request) async {
        if (request.uri.path == '/artwork') {
          artworkRequests++;
          request.response.statusCode = HttpStatus.ok;
          request.response.headers.contentType = ContentType('image', 'png');
          request.response.add(const <int>[137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3]);
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      }),
    );
  });

  tearDown(() async {
    await session.dispose();
    await server.close(force: true);
    if (await cache.exists()) await cache.delete(recursive: true);
  });

  PlaybackItem remoteItem() {
    final artwork = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      path: '/artwork',
      queryParameters: const {'token': 'test-token'},
    );
    final stream = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      path: '/audio',
      queryParameters: const {'token': 'test-token'},
    );
    return PlaybackItem(
      id: 'remote:test:track-1',
      title: 'Remote Song',
      artist: 'Remote Artist',
      streamUri: stream,
      audioAsset: AudioAsset(
        originalPath: stream.toString(),
        format: 'flac',
        metadata: <String, dynamic>{
          'remoteTrackId': 'track-1',
          'remoteArtworkUri': artwork.toString(),
        },
      ),
    );
  }

  test('remote artwork is cached and written back to the shared queue item', () async {
    await session.setQueue(<PlaybackItem>[remoteItem()]);

    final hydrated = await _waitForHydratedArtwork(delegate);
    final path = hydrated.artworkPath;
    expect(path, isNotNull);
    expect(await File(path!).exists(), isTrue);
    expect(await File(path).readAsBytes(),
        const <int>[137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3]);
    expect(hydrated.audioAsset.thumbnailPath, path);
    expect(artworkRequests, 1);
  });

  test('cached remote artwork is reused without another network request', () async {
    await session.setQueue(<PlaybackItem>[remoteItem()]);
    await _waitForHydratedArtwork(delegate);
    expect(artworkRequests, 1);

    await session.setQueue(<PlaybackItem>[remoteItem()]);
    final hydratedAgain = await _waitForHydratedArtwork(delegate);

    expect(hydratedAgain.artworkPath, isNotNull);
    expect(artworkRequests, 1);
  });
}

Future<PlaybackItem> _waitForHydratedArtwork(
  _FakePlaybackSession delegate,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final item = delegate.currentState.currentItem;
    final path = item?.artworkPath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return item!;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw StateError('remote artwork was not hydrated');
}

class _EmptyLibraryRepository implements LocalMediaLibraryRepository {
  @override
  Future<List<LocalMediaLibraryEntry>> getAll() async => const [];

  @override
  Future<LocalMediaLibraryEntry?> getByPath(String sourcePath) async => null;

  @override
  Future<List<LocalMediaLibraryEntry>> addPaths(Iterable<String> paths) async =>
      const [];

  @override
  Future<List<String>> getRoots() async => const [];

  @override
  Future<void> addRoot(String rootPath) async {}

  @override
  Future<List<LocalMediaLibraryEntry>> refreshAvailability() async => const [];

  @override
  Future<List<LocalMediaLibraryEntry>> refreshFromRoots(
    Iterable<String> supportedExtensions,
  ) async => const [];

  @override
  Future<List<LocalMediaLibraryEntry>> refreshMetadata({bool force = false}) async =>
      const [];

  @override
  Future<void> remove(String sourcePath) async {}

  @override
  Future<void> removeMissing() async {}
}

class _FakePlaybackSession implements PlaybackSessionService {
  final StreamController<PlaybackSessionState> _controller =
      StreamController<PlaybackSessionState>.broadcast();
  PlaybackSessionState _state = const PlaybackSessionState();

  @override
  Stream<PlaybackSessionState> get stateStream => _controller.stream;

  @override
  PlaybackSessionState get currentState => _state;

  @override
  PlaybackState get playbackState => const PlaybackState.idle();

  void _emit(PlaybackSessionState state) {
    _state = state;
    _controller.add(state);
  }

  @override
  Future<void> playItem(PlaybackItem item, {Duration? resumeFrom}) async {
    _emit(PlaybackSessionState(queue: <PlaybackItem>[item], currentIndex: 0));
  }

  @override
  Future<void> setQueue(List<PlaybackItem> items, {int startIndex = 0}) async {
    _emit(
      PlaybackSessionState(
        queue: List<PlaybackItem>.unmodifiable(items),
        currentIndex: items.isEmpty ? -1 : startIndex,
      ),
    );
  }

  @override
  Future<void> enqueue(PlaybackItem item) async {
    final queue = <PlaybackItem>[..._state.queue, item];
    _emit(_state.copyWith(queue: List<PlaybackItem>.unmodifiable(queue)));
  }

  @override
  Future<void> updateItem(PlaybackItem item) async {
    final index = _state.queue.indexWhere((candidate) => candidate.id == item.id);
    if (index < 0) return;
    final queue = List<PlaybackItem>.from(_state.queue)..[index] = item;
    _emit(_state.copyWith(queue: List<PlaybackItem>.unmodifiable(queue)));
  }

  @override
  Future<void> playAt(int index) async {
    if (index < 0 || index >= _state.queue.length) return;
    _emit(_state.copyWith(currentIndex: index));
  }

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
  Future<void> togglePlayPause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}
