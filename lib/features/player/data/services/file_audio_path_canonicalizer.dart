import 'dart:io';

import '../../domain/services/audio_path_canonicalizer.dart';

/// [AudioPathCanonicalizer] backed by dart:io path resolution.
///
/// Relative paths are resolved against the process working directory and,
/// on Windows, the result is lower-cased because NTFS paths are
/// case-insensitive.
class FileAudioPathCanonicalizer implements AudioPathCanonicalizer {
  const FileAudioPathCanonicalizer();

  @override
  String canonicalize(String path) {
    final absolutePath = File(path).absolute.path;
    return Platform.isWindows ? absolutePath.toLowerCase() : absolutePath;
  }
}
