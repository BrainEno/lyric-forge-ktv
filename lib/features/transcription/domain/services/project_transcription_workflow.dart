import '../models/transcription_models.dart';

abstract class ProjectTranscriptionWorkflow {
  Stream<TranscriptionProgress> get progressStream;

  bool get isRunning;

  Future<void> transcribeProject(String projectId);

  Future<void> cancel();
}
