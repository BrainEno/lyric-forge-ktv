import '../models/transcription_models.dart';

abstract class TranscriptionService {
  Stream<TranscriptionProgress> get progressStream;

  bool get isRunning;

  Future<TranscriptionResult> transcribe(TranscriptionRequest request);

  Future<void> cancel();

  Future<void> dispose();
}
