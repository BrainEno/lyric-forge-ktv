import 'audio_library_import_service.dart';

/// Video containers whose sound track the phone can pull out on its own
/// (decision D-056). iOS reads MP4/MOV/M4V/3GP through AVFoundation; Android
/// copies an AAC track out of MP4/3GP/MKV/WebM without re-encoding.
const supportedLocalVideoExtensions = <String>[
  'mp4',
  'mov',
  'm4v',
  '3gp',
  'mkv',
  'webm',
];

/// What a picked file is, judged by its extension only.
enum MediaImportKind { audio, video, unsupported }

/// [MediaImportKind] of [nameOrPath], by extension (case-insensitive).
MediaImportKind mediaImportKindOf(String nameOrPath) {
  final slash = nameOrPath.lastIndexOf(RegExp(r'[/\\]'));
  final name = nameOrPath.substring(slash + 1);
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return MediaImportKind.unsupported;
  final extension = name.substring(dot + 1).toLowerCase();
  if (supportedLocalAudioExtensions.contains(extension)) {
    return MediaImportKind.audio;
  }
  if (supportedLocalVideoExtensions.contains(extension)) {
    return MediaImportKind.video;
  }
  return MediaImportKind.unsupported;
}

/// Where the user picks from on a phone.
enum MediaImportSource {
  /// The system document picker ("文件" on iOS): audio and video files.
  files,

  /// The photo library: videos only.
  photoLibrary,
}

/// The step an import is on, for the progress dialog.
enum MediaImportPhase { copying, extracting }

/// One step of an import: file [index] (0-based) of [total], called [name].
class MediaImportProgress {
  final int index;
  final int total;
  final String name;
  final MediaImportPhase phase;

  const MediaImportProgress({
    required this.index,
    required this.total,
    required this.name,
    required this.phase,
  });
}

/// A picked file that could not be imported, and why, in words for the user.
class MediaImportFailure {
  final String name;
  final String reason;

  const MediaImportFailure({required this.name, required this.reason});
}

/// What one import produced.
class MediaImportResult {
  /// Audio files now in the app's own folder and in the music library.
  final List<String> importedPaths;

  /// How many of [importedPaths] were pulled out of videos.
  final int extractedFromVideo;

  final List<MediaImportFailure> failures;

  /// The user closed the picker without choosing anything.
  final bool cancelled;

  const MediaImportResult({
    this.importedPaths = const [],
    this.extractedFromVideo = 0,
    this.failures = const [],
    this.cancelled = false,
  });

  static const MediaImportResult none = MediaImportResult(cancelled: true);

  bool get isEmpty => importedPaths.isEmpty && failures.isEmpty;
}

/// Imports songs on a phone: picks audio or video files, keeps a copy of
/// each song in the app's own folder (picked files are temporary copies on
/// iOS and Android), turns videos into small audio files, and adds the
/// results to the music library.
abstract class MediaImportService {
  /// Whether videos can be picked from the photo library.
  bool get supportsPhotoLibrary;

  /// Whether the sound of a video can be extracted on this device.
  bool get supportsVideo;

  Future<MediaImportResult> importMedia(
    MediaImportSource source, {
    void Function(MediaImportProgress progress)? onProgress,
  });
}
