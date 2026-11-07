/// Filename extensions accepted by local audio import and Media Hub uploads.
/// This checks the name only; it does not validate or decode file contents.
const supportedLocalAudioExtensions = <String>[
  'mp3',
  'flac',
  'wav',
  'm4a',
  'aac',
  'ogg',
];

class AudioDirectorySelection {
  final String rootPath;
  final List<String> audioPaths;

  const AudioDirectorySelection({
    required this.rootPath,
    required this.audioPaths,
  });
}

abstract class AudioLibraryImportService {
  List<String> get supportedExtensions;

  /// Opens a native picker that allows selecting one or more audio files.
  Future<List<String>> pickAudioFiles();

  /// Opens a native folder picker and returns supported audio files found
  /// recursively under the selected directory.
  Future<List<String>> pickAudioDirectory();

  /// Same folder import operation, but also reports the selected root so a
  /// persistent local library can rescan it for newly-added music later.
  ///
  /// The default keeps older/fake implementations source-compatible. Concrete
  /// desktop implementations should override this to provide a real rootPath.
  Future<AudioDirectorySelection?> pickAudioDirectorySelection() async {
    final paths = await pickAudioDirectory();
    if (paths.isEmpty) return null;
    return AudioDirectorySelection(rootPath: '', audioPaths: paths);
  }
}
