import '../models/transcription_models.dart';

abstract class TranscriptionSettingsStore {
  Future<TranscriptionConfig?> load();

  Future<void> save(TranscriptionConfig config);

  Future<void> clear();
}

abstract class TranscriptionDownloadProxyStore {
  Future<String?> loadDownloadProxy();

  Future<void> saveDownloadProxy(String proxy);
}
