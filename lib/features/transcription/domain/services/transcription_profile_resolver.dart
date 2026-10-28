import '../models/transcription_models.dart';

abstract class TranscriptionProfileResolver {
  Future<TranscriptionHardwareInfo> detectHardware();

  Future<ResolvedTranscriptionProfile> resolve(
    TranscriptionConfig config,
  );
}
