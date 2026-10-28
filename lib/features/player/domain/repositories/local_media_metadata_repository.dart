import '../models/local_media_metadata.dart';

abstract class LocalMediaMetadataRepository {
  Future<LocalMediaMetadata?> getForAudio(String sourcePath);

  Future<List<LocalMediaMetadata>> getAll();

  Future<LocalMediaMetadata> save(LocalMediaMetadata metadata);

  Future<void> removeForAudio(String sourcePath);

  /// Copies a user-selected image into app-owned storage and returns the copy.
  /// Saving that path into metadata is intentionally a separate mutation so
  /// callers can preview/cancel before committing the media edit.
  Future<String> importArtwork({
    required String sourcePath,
    required String imagePath,
  });

  Future<void> removeManagedArtwork(String? artworkPath);
}
