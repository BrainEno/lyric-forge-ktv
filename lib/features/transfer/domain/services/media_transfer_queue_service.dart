import 'dart:async';

import '../models/media_transfer_queue.dart';
import '../models/remote_audio_track.dart';

abstract class MediaTransferQueueService {
  Stream<MediaTransferQueueSnapshot> get stateStream;
  MediaTransferQueueSnapshot get currentState;

  Future<void> initialize();

  Future<void> enqueueDownloads(List<RemoteAudioTrack> tracks);

  Future<void> enqueueUploads(List<String> sourcePaths);

  Future<void> processPending();

  Future<void> pause({String? reason});

  Future<void> resume();

  Future<void> retry(String id);

  Future<void> retryFailed();

  Future<void> remove(String id);

  Future<void> clearCompleted();

  Future<void> dispose();
}
