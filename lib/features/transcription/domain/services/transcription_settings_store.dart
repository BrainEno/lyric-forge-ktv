import '../models/transcription_models.dart';

abstract class TranscriptionSettingsStore {
  Future<TranscriptionConfig?> load();

  Future<void> save(TranscriptionConfig config);

  Future<void> clear();
}
