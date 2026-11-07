import '../models/local_media_metadata.dart';

/// A repository may expose best-effort reads for display. Implementations that
/// do so must also implement [CompleteLocalMediaMetadataReader] so association
/// decisions never mistake a partial snapshot for an authoritative result.
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

/// Opt-in capability for repositories whose normal reads may be incomplete.
/// Throws if the snapshot cannot safely determine an association or its absence.
abstract class CompleteLocalMediaMetadataReader {
  Future<LocalMediaMetadata?> getCompleteForAudio(String sourcePath);
}

/// Reads metadata for association decisions. Repositories without the optional
/// capability must make their ordinary reads authoritative or throw on failure.
Future<LocalMediaMetadata?> readCompleteLocalMediaMetadataForAudio(
  LocalMediaMetadataRepository repository,
  String sourcePath,
) {
  if (repository is CompleteLocalMediaMetadataReader) {
    return (repository as CompleteLocalMediaMetadataReader).getCompleteForAudio(
      sourcePath,
    );
  }
  return repository.getForAudio(sourcePath);
}
