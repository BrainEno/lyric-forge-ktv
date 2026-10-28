import '../models/embedded_audio_metadata.dart';

abstract class EmbeddedAudioMetadataReader {
  Future<EmbeddedAudioMetadata> read(String sourcePath);
}
