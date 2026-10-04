import '../models/local_media_library_entry.dart';

abstract class LocalMediaLibraryRepository {
  Future<List<LocalMediaLibraryEntry>> getAll();

  Future<List<String>> getRoots();

  /// Adds or refreshes paths in the persistent local library.
  /// Existing entries keep their original addedAt timestamp.
  Future<List<LocalMediaLibraryEntry>> addPaths(Iterable<String> paths);

  /// Records a user-selected music folder so refresh can discover new files.
  Future<void> addRoot(String rootPath);

  /// Re-checks known entries without deleting missing rows.
  Future<List<LocalMediaLibraryEntry>> refreshAvailability();

  /// Re-scans all available library roots and then refreshes known entries.
  Future<List<LocalMediaLibraryEntry>> refreshFromRoots(
    Iterable<String> supportedExtensions,
  );

  Future<void> remove(String sourcePath);

  Future<void> removeMissing();
}
