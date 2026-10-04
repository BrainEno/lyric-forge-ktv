import '../models/transcription_queue_models.dart';

abstract class BatchTranscriptionQueue {
  Stream<TranscriptionQueueSnapshot> get snapshots;

  TranscriptionQueueSnapshot get current;

  Future<void> initialize();

  Future<int> enqueuePaths(Iterable<String> paths);

  Future<void> pause();

  Future<void> resume();

  Future<void> retryFailed();

  Future<void> remove(String itemId);

  Future<void> clearCompleted();

  Future<void> dispose();
}
