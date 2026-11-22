import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/services/audio_library_import_service.dart';
import '../../domain/services/media_audio_extractor.dart';
import '../../domain/services/media_import_service.dart';

/// A file the user picked: its display name and a readable local copy.
class PickedMediaFile {
  final String name;
  final String path;

  const PickedMediaFile({required this.name, required this.path});
}

/// Opens the system picker for [source]; null when the user cancels.
typedef MediaFilePicker =
    Future<List<PickedMediaFile>?> Function(MediaImportSource source);

/// Adds imported songs to the music library.
typedef ImportedMediaSink = Future<void> Function(List<String> paths);

/// [MediaImportService] for iOS and Android (D-056).
///
/// The pickers hand out temporary copies, so every song is kept in the app's
/// own folder ([importDirectory], "Imported Audio" under Documents — visible
/// in the iOS 文件 App) before it is added to the library. Videos are not
/// kept: their sound is extracted into an `.m4a` file next to the songs.
class LocalMediaImportService implements MediaImportService {
  static const String importFolderName = 'Imported Audio';

  final MediaAudioExtractor extractor;
  final ImportedMediaSink onImported;
  final MediaFilePicker _pick;
  final Future<Directory> Function() _importDirectory;
  final Future<void> Function() _cleanUpPickerFiles;

  @override
  final bool supportsPhotoLibrary;

  @override
  final bool supportsVideo;

  LocalMediaImportService({
    required this.extractor,
    required this.onImported,
    MediaFilePicker? pick,
    Future<Directory> Function()? importDirectory,
    Future<void> Function()? cleanUpPickerFiles,
    this.supportsPhotoLibrary = true,
    this.supportsVideo = true,
  }) : _pick = pick ?? pickMediaWithFilePicker,
       _importDirectory = importDirectory ?? defaultImportDirectory,
       _cleanUpPickerFiles = cleanUpPickerFiles ?? _clearFilePickerCache;

  /// Documents/Imported Audio, created on first use.
  static Future<Directory> defaultImportDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${documents.path}${Platform.pathSeparator}$importFolderName',
    );
    await directory.create(recursive: true);
    return directory;
  }

  /// The system pickers through `file_picker`.
  static Future<List<PickedMediaFile>?> pickMediaWithFilePicker(
    MediaImportSource source,
  ) async {
    final result = switch (source) {
      MediaImportSource.files => await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          ...supportedLocalAudioExtensions,
          ...supportedLocalVideoExtensions,
        ],
        allowMultiple: true,
        dialogTitle: '选择音频或视频',
        withData: false,
        withReadStream: false,
      ),
      MediaImportSource.photoLibrary => await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: true,
        dialogTitle: '选择视频',
        withData: false,
        withReadStream: false,
      ),
    };
    if (result == null) return null;
    return [
      for (final file in result.files)
        if (file.path != null)
          PickedMediaFile(name: file.name, path: file.path!),
    ];
  }

  static Future<void> _clearFilePickerCache() async {
    try {
      await FilePicker.platform.clearTemporaryFiles();
    } on Object {
      // Only the picker's own temporary copies; the OS clears them anyway.
    }
  }

  @override
  Future<MediaImportResult> importMedia(
    MediaImportSource source, {
    void Function(MediaImportProgress progress)? onProgress,
  }) async {
    final picked = await _pick(source);
    if (picked == null || picked.isEmpty) return MediaImportResult.none;

    final directory = await _importDirectory();
    final imported = <String>[];
    final failures = <MediaImportFailure>[];
    var extracted = 0;
    try {
      for (var index = 0; index < picked.length; index++) {
        final file = picked[index];
        // The display name normally carries the extension; fall back to the
        // copy's path when a picker hands out a bare name.
        final byName = mediaImportKindOf(file.name);
        final effectiveKind = byName == MediaImportKind.unsupported
            ? mediaImportKindOf(file.path)
            : byName;
        try {
          switch (effectiveKind) {
            case MediaImportKind.audio:
              onProgress?.call(
                MediaImportProgress(
                  index: index,
                  total: picked.length,
                  name: file.name,
                  phase: MediaImportPhase.copying,
                ),
              );
              imported.add(await _keepAudio(file, directory));
            case MediaImportKind.video:
              if (!supportsVideo) {
                throw const MediaAudioExtractionException(
                  MediaAudioExtractionException.unsupportedPlatform,
                );
              }
              onProgress?.call(
                MediaImportProgress(
                  index: index,
                  total: picked.length,
                  name: file.name,
                  phase: MediaImportPhase.extracting,
                ),
              );
              imported.add(await _extractAudio(file, directory));
              extracted++;
            case MediaImportKind.unsupported:
              failures.add(
                MediaImportFailure(name: file.name, reason: '不支持的文件格式'),
              );
          }
        } on MediaAudioExtractionException catch (error) {
          failures.add(
            MediaImportFailure(name: file.name, reason: error.userMessage),
          );
        } on FileSystemException catch (error) {
          failures.add(
            MediaImportFailure(
              name: file.name,
              reason: '无法保存：${error.osError?.message ?? error.message}',
            ),
          );
        } on Object catch (error) {
          failures.add(
            MediaImportFailure(name: file.name, reason: '导入失败：$error'),
          );
        }
      }
      if (imported.isNotEmpty) await onImported(imported);
    } finally {
      await _cleanUpPickerFiles();
    }
    return MediaImportResult(
      importedPaths: imported,
      extractedFromVideo: extracted,
      failures: failures,
    );
  }

  /// Copies an audio file into [directory]; a file already there is reused,
  /// and the same song picked twice is kept once.
  Future<String> _keepAudio(PickedMediaFile file, Directory directory) async {
    final source = File(file.path);
    if (_isInside(source.path, directory.path)) return source.path;
    final length = await source.length();
    final name = safeFileName(file.name, fallback: 'audio');
    final existing = File(_join(directory.path, name));
    if (await existing.exists() && await existing.length() == length) {
      return existing.path;
    }
    final target = await uniqueFile(directory, name);
    await source.copy(target.path);
    return target.path;
  }

  Future<String> _extractAudio(
    PickedMediaFile file,
    Directory directory,
  ) async {
    final base = _withoutExtension(safeFileName(file.name, fallback: 'video'));
    final target = await uniqueFile(directory, '$base.m4a');
    try {
      final result = await extractor.extractAudio(
        inputPath: file.path,
        outputPath: target.path,
      );
      final output = File(result.path);
      if (!await output.exists() || await output.length() == 0) {
        throw const MediaAudioExtractionException(
          MediaAudioExtractionException.failed,
          '没有生成音频文件',
        );
      }
      return output.path;
    } on Object {
      if (await target.exists()) await target.delete();
      rethrow;
    }
  }

  /// [name] without characters that file systems reject, never empty.
  static String safeFileName(String name, {required String fallback}) {
    final slash = name.lastIndexOf(RegExp(r'[/\\]'));
    final cleaned = name
        .substring(slash + 1)
        .replaceAll(RegExp(r'[\x00-\x1f<>:"|?*]'), '_')
        .trim();
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return fallback;
    return cleaned;
  }

  /// A file in [directory] called [name], or "name (2).ext" and so on when
  /// that is taken.
  static Future<File> uniqueFile(Directory directory, String name) async {
    final base = _withoutExtension(name);
    final extension = name.substring(base.length);
    var candidate = File(_join(directory.path, name));
    var counter = 2;
    while (await candidate.exists()) {
      candidate = File(_join(directory.path, '$base ($counter)$extension'));
      counter++;
    }
    return candidate;
  }

  static String _withoutExtension(String name) {
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }

  static String _join(String directory, String name) =>
      directory.endsWith(Platform.pathSeparator)
      ? '$directory$name'
      : '$directory${Platform.pathSeparator}$name';

  static bool _isInside(String path, String directory) {
    final prefix = directory.endsWith(Platform.pathSeparator)
        ? directory
        : '$directory${Platform.pathSeparator}';
    return File(path).absolute.path.startsWith(prefix);
  }
}
