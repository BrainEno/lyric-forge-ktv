import '../models/local_media_library_entry.dart';

abstract class LocalMediaLibraryRepository {
  Future<List<LocalMediaLibraryEntry>> getAll();

  Future<LocalMediaLibraryEntry?> getByPath(String sourcePath);

  /// Adds or refreshes paths in the persistent local library.
  /// Existing entries keep their original addedAt timestamp.
  Future<List<LocalMediaLibraryEntry>> addPaths(Iterable<String> paths);

  Future<List<String>> getRoots();

  Future<void> addRoot(String rootPath);

  /// Re-checks known file availability and discovers new files from roots.
  Future<List<LocalMediaLibraryEntry>> refreshAvailability();

  Future<List<LocalMediaLibraryEntry>> refreshFromRoots(
    Iterable<String> supportedExtensions,
  );

  /// Re-reads embedded audio tags. When [force] is false, unchanged source
  /// files use the cached metadata snapshot.
  Future<List<LocalMediaLibraryEntry>> refreshMetadata({bool force = false});

  Future<void> remove(String sourcePath);

  Future<void> removeMissing();
}
