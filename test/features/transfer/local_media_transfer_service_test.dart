import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_library_entry.dart';
import 'package:lyric_forge_ktv/features/player/domain/repositories/local_media_library_repository.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transfer/data/services/local_media_transfer_service.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/media_hub_connection.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/remote_audio_track.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/services/media_hub_client_service.dart';

void main() {
  late Directory temp;
  late _FakeLibraryRepository library;
  late _FakeMediaHubClient client;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lyricforge-transfer-');
    library = _FakeLibraryRepository();
    client = _FakeMediaHubClient();
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('downloads multiple tracks and imports every success into Library', () async {
    client.payloads['a'] = List<int>.filled(12, 1);
    client.payloads['b'] = List<int>.filled(8, 2);
    final service = LocalMediaTransferService(
      client: client,
      libraryRepository: library,
      downloadDirectory: temp,
    );

    final result = await service.downloadRemoteTracks([
      _track('a', 'A', 12),
      _track('b', 'B', 8),
    ]);

    expect(result.completed.length, 2);
    expect(result.failed, isEmpty);
    expect(client.downloadedIds, ['a', 'b']);
    expect(library.addedPaths.length, 2);
    for (final path in library.addedPaths) {
      expect(await File(path).exists(), isTrue);
    }
  });

  test('one failed transfer does not stop remaining tracks', () async {
    client.payloads['a'] = List<int>.filled(4, 1);
    client.payloads['c'] = List<int>.filled(6, 3);
    client.failIds.add('b');
    final service = LocalMediaTransferService(
      client: client,
      libraryRepository: library,
      downloadDirectory: temp,
    );

    final result = await service.downloadRemoteTracks([
      _track('a', 'A', 4),
      _track('b', 'B', 5),
      _track('c', 'C', 6),
    ]);

    expect(result.completed.map((item) => item.id), ['a', 'c']);
    expect(result.failed.single.id, 'b');
    expect(client.downloadedIds, ['a', 'c']);
    expect(library.addedPaths.length, 2);
  });

  test('reuses an existing same-size download but still imports it', () async {
    final track = _track('reuse1234', 'Reusable', 10);
    final existing = File('${temp.path}${Platform.pathSeparator}Reusable_reuse123.mp3');
    await existing.writeAsBytes(List<int>.filled(10, 7));
    final service = LocalMediaTransferService(
      client: client,
      libraryRepository: library,
      downloadDirectory: temp,
    );

    final result = await service.downloadRemoteTracks([track]);

    expect(result.completed.single.id, track.id);
    expect(client.downloadedIds, isEmpty);
    expect(library.addedPaths, [existing.path]);
  });
}

RemoteAudioTrack _track(String id, String title, int bytes) => RemoteAudioTrack(
      id: id,
      title: title,
      format: 'mp3',
      byteLength: bytes,
      streamPath: '/v1/tracks/$id/audio',
      downloadPath: '/v1/tracks/$id/audio?download=1',
    );

class _FakeMediaHubClient implements MediaHubClientService {
  final Map<String, List<int>> payloads = {};
  final Set<String> failIds = {};
  final List<String> downloadedIds = [];

  @override
  MediaHubConnection? get currentConnection => null;

  @override
  bool get isConnected => true;

  @override
  Future<void> downloadTrack({
    required RemoteAudioTrack track,
    required String destinationPath,
    TransferProgressCallback? onProgress,
  }) async {
    if (failIds.contains(track.id)) throw Exception('failed ${track.id}');
    final bytes = payloads[track.id] ?? List<int>.filled(track.byteLength, 1);
    final file = File(destinationPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    downloadedIds.add(track.id);
    onProgress?.call(bytes.length, bytes.length);
  }

  @override
  Future<MediaHubConnection> connect(Uri pairingUri) => throw UnimplementedError();
  @override
  Future<void> connectTo(MediaHubConnection connection) => throw UnimplementedError();
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<List<RemoteAudioTrack>> fetchTracks() => throw UnimplementedError();
  @override
  Future<LyricDocument?> fetchLyrics(RemoteAudioTrack track) => throw UnimplementedError();
  @override
  Uri playbackUriFor(RemoteAudioTrack track) => throw UnimplementedError();
}

class _FakeLibraryRepository implements LocalMediaLibraryRepository {
  final List<String> addedPaths = [];

  @override
  Future<List<LocalMediaLibraryEntry>> addPaths(Iterable<String> paths) async {
    addedPaths.addAll(paths);
    return const [];
  }

  @override
  Future<void> addRoot(String rootPath) async {}
  @override
  Future<List<LocalMediaLibraryEntry>> getAll() async => const [];
  @override
  Future<LocalMediaLibraryEntry?> getByPath(String sourcePath) async => null;
  @override
  Future<List<String>> getRoots() async => const [];
  @override
  Future<void> remove(String sourcePath) async {}
  @override
  Future<void> removeMissing() async {}
  @override
  Future<List<LocalMediaLibraryEntry>> refreshAvailability() async => const [];
  @override
  Future<List<LocalMediaLibraryEntry>> refreshFromRoots(
    Iterable<String> supportedExtensions,
  ) async => const [];
  @override
  Future<List<LocalMediaLibraryEntry>> refreshMetadata({bool force = false}) async => const [];
}
