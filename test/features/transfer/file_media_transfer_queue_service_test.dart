import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transfer/data/services/file_media_transfer_queue_service.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/media_hub_connection.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/media_transfer_batch.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/media_transfer_queue.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/models/remote_audio_track.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/services/media_hub_client_service.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/services/media_transfer_service.dart';

void main() {
  late Directory temp;
  late _FakeClient client;
  late _FakeTransfers transfers;
  late FileMediaTransferQueueService queue;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lyricforge-transfer-queue-');
    client = _FakeClient();
    transfers = _FakeTransfers();
    queue = FileMediaTransferQueueService(
      transfers: transfers,
      client: client,
      rootDirectory: temp,
    );
  });

  tearDown(() async {
    await queue.dispose();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('restart recovers transferring item back to queued', () async {
    final now = DateTime.now();
    final file = File('${temp.path}${Platform.pathSeparator}media_transfer_queue.json');
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'paused': false,
        'items': [
          MediaTransferQueueItem(
            id: 'upload:1',
            direction: MediaTransferDirection.uploadToDesktop,
            title: 'Interrupted',
            status: MediaTransferQueueStatus.transferring,
            createdAt: now,
            updatedAt: now,
            sourcePath: '${temp.path}${Platform.pathSeparator}a.mp3',
            bytesTransferred: 123,
            totalBytes: 456,
          ).toJson(),
        ],
      }),
    );

    await queue.initialize();

    expect(queue.currentState.items, hasLength(1));
    expect(
      queue.currentState.items.single.status,
      MediaTransferQueueStatus.queued,
    );
    expect(queue.currentState.items.single.bytesTransferred, 0);
  });

  test('disconnected queue pauses without failing queued items', () async {
    client.connected = false;
    final source = File('${temp.path}${Platform.pathSeparator}offline.mp3');
    await source.writeAsBytes(const [1, 2, 3]);
    await queue.initialize();
    await queue.enqueueUploads([source.path]);

    await queue.processPending();

    expect(queue.currentState.isPaused, isTrue);
    expect(queue.currentState.pauseReason, isNotNull);
    expect(
      queue.currentState.items.single.status,
      MediaTransferQueueStatus.queued,
    );
    expect(transfers.uploadCalls, 0);
  });

  test('same remote download is kept as one logical queue item', () async {
    client.connected = false;
    await queue.initialize();
    final track = _track('same', 'Same Song');

    await queue.enqueueDownloads([track, track]);
    await queue.enqueueDownloads([track]);

    expect(queue.currentState.items, hasLength(1));
    expect(queue.currentState.items.single.id, 'download:same');
  });

  test('failed upload can be retried and completed', () async {
    client.connected = false;
    final source = File('${temp.path}${Platform.pathSeparator}retry.mp3');
    await source.writeAsBytes(List<int>.filled(8, 1));
    await queue.initialize();
    await queue.enqueueUploads([source.path]);

    client.connected = true;
    transfers.failUploads = true;
    await queue.processPending();
    expect(
      queue.currentState.items.single.status,
      MediaTransferQueueStatus.failed,
    );

    client.connected = false;
    transfers.failUploads = false;
    await queue.retry(queue.currentState.items.single.id);
    expect(
      queue.currentState.items.single.status,
      MediaTransferQueueStatus.queued,
    );

    client.connected = true;
    await queue.processPending();
    expect(
      queue.currentState.items.single.status,
      MediaTransferQueueStatus.completed,
    );
    expect(transfers.uploadCalls, 2);
  });

  test('completed queue state persists across service recreation', () async {
    client.connected = false;
    final source = File('${temp.path}${Platform.pathSeparator}persist.mp3');
    await source.writeAsBytes(List<int>.filled(5, 7));
    await queue.initialize();
    await queue.enqueueUploads([source.path]);
    client.connected = true;
    await queue.processPending();
    expect(
      queue.currentState.items.single.status,
      MediaTransferQueueStatus.completed,
    );

    await queue.dispose();
    queue = FileMediaTransferQueueService(
      transfers: transfers,
      client: client,
      rootDirectory: temp,
    );
    client.connected = false;
    await queue.initialize();

    expect(queue.currentState.items, hasLength(1));
    expect(
      queue.currentState.items.single.status,
      MediaTransferQueueStatus.completed,
    );
  });
}

RemoteAudioTrack _track(String id, String title) => RemoteAudioTrack(
      id: id,
      title: title,
      format: 'mp3',
      byteLength: 10,
      streamPath: '/v1/tracks/$id/audio',
      downloadPath: '/v1/tracks/$id/audio?download=1',
    );

class _FakeTransfers implements MediaTransferService {
  int uploadCalls = 0;
  bool failUploads = false;

  @override
  Future<MediaTransferBatchResult> downloadRemoteTracks(
    List<RemoteAudioTrack> tracks, {
    MediaTransferProgressCallback? onProgress,
  }) async {
    return MediaTransferBatchResult(
      tracks
          .map(
            (track) => MediaTransferItemResult(
              id: track.id,
              title: track.title,
              direction: MediaTransferDirection.downloadFromDesktop,
              succeeded: true,
              destinationPath: '/tmp/${track.title}.${track.format}',
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<MediaTransferBatchResult> uploadLocalFiles(
    List<String> sourcePaths, {
    MediaTransferProgressCallback? onProgress,
  }) async {
    uploadCalls++;
    final path = sourcePaths.single;
    final file = File(path);
    final total = await file.length();
    final title = file.uri.pathSegments.last.split('.').first;
    onProgress?.call(
      MediaTransferItemProgress(
        id: path,
        title: title,
        direction: MediaTransferDirection.uploadToDesktop,
        status: MediaTransferItemStatus.transferring,
        bytesTransferred: total,
        totalBytes: total,
      ),
    );
    if (failUploads) {
      return MediaTransferBatchResult([
        MediaTransferItemResult(
          id: path,
          title: title,
          direction: MediaTransferDirection.uploadToDesktop,
          succeeded: false,
          error: 'network failed',
        ),
      ]);
    }
    return MediaTransferBatchResult([
      MediaTransferItemResult(
        id: path,
        title: title,
        direction: MediaTransferDirection.uploadToDesktop,
        succeeded: true,
      ),
    ]);
  }
}

class _FakeClient implements MediaHubClientService {
  bool connected = false;

  @override
  MediaHubConnection? get currentConnection => connected
      ? const MediaHubConnection(host: '127.0.0.1', port: 1, token: 'token')
      : null;

  @override
  bool get isConnected => connected;

  @override
  Future<MediaHubConnection> connect(Uri pairingUri) => throw UnimplementedError();
  @override
  Future<void> connectTo(MediaHubConnection connection) async => connected = true;
  @override
  Future<void> disconnect() async => connected = false;
  @override
  Future<void> dispose() async {}
  @override
  Future<void> downloadTrack({
    required RemoteAudioTrack track,
    required String destinationPath,
    TransferProgressCallback? onProgress,
  }) => throw UnimplementedError();
  @override
  Future<List<RemoteAudioTrack>> fetchTracks() => throw UnimplementedError();
  @override
  Future<LyricDocument?> fetchLyrics(RemoteAudioTrack track) => throw UnimplementedError();
  @override
  Uri playbackUriFor(RemoteAudioTrack track) => throw UnimplementedError();
  @override
  Future<void> uploadFile({
    required String sourcePath,
    String? remoteFileName,
    TransferProgressCallback? onProgress,
  }) => throw UnimplementedError();
}
