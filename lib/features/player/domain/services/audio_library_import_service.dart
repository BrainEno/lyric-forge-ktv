abstract class AudioLibraryImportService {
  List<String> get supportedExtensions;

  /// Opens a native picker that allows selecting one or more audio files.
  Future<List<String>> pickAudioFiles();

  /// Opens a native folder picker and returns supported audio files found
  /// recursively under the selected directory.
  Future<List<String>> pickAudioDirectory();
}
