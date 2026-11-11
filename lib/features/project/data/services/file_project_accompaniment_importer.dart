import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../player/domain/services/audio_library_import_service.dart';
import '../../domain/models/project_manifest.dart';
import '../../domain/repositories/project_repository.dart';
import '../../domain/services/project_accompaniment_importer.dart';
import '../../domain/services/project_vocal_importer.dart';

/// Copies a user-selected stem into application storage before linking it.
class FileProjectAccompanimentImporter implements ProjectAccompanimentImporter, ProjectVocalImporter {
  final ProjectRepository projectRepository;
  final Directory? storageDirectory;
  final Future<String?> Function()? pickPath;

  const FileProjectAccompanimentImporter({
    required this.projectRepository,
    this.storageDirectory,
    this.pickPath,
  });

  Future<String?> _pick({required bool vocal}) async {
    final picker = pickPath;
    if (picker != null) return picker();
    final unfiltered = Platform.isMacOS;
    final result = await FilePicker.platform.pickFiles(
      type: unfiltered ? FileType.any : FileType.custom,
      allowedExtensions: unfiltered ? null : supportedLocalAudioExtensions,
      allowMultiple: false,
      dialogTitle: vocal ? '选择已有人声音频' : '选择已有伴奏音频',
      withData: false,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.single.path;
    if (path == null || path.isEmpty)
      throw const FormatException('No local file path');
    return path;
  }

  @override
  Future<ProjectManifest?> importFor(ProjectManifest project) =>
      _import(project, vocal: false);

  @override
  Future<ProjectManifest?> importVocalFor(ProjectManifest project) =>
      _import(project, vocal: true);

  Future<ProjectManifest?> _import(ProjectManifest project, {required bool vocal}) async {
    final audio = project.audioAsset;
    if (audio == null) throw StateError('Project has no original audio');
    final path = await _pick(vocal: vocal);
    if (path == null) return null;
    final source = File(path);
    final name = source.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    final extension = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    if (!supportedLocalAudioExtensions.contains(extension)) {
      throw const FormatException('Unsupported audio extension');
    }
    if (!await source.exists() || await source.length() == 0) {
      throw const FileSystemException('Selected audio is missing or empty');
    }
    final root =
        storageDirectory ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}LyricForge${Platform.pathSeparator}${vocal ? 'Vocals' : 'Accompaniment'}',
        );
    await root.create(recursive: true);
    final destination = File(
      '${root.path}${Platform.pathSeparator}${const Uuid().v4()}.$extension',
    );
    try {
      await source.copy(destination.path);
    } catch (_) {
      try {
        if (await destination.exists()) await destination.delete();
      } catch (_) {
        // Preserve the original copy failure if cleanup also fails.
      }
      rethrow;
    }

    // The repository can update its in-memory snapshot before a disk error.
    // Keep the new copy on every save failure so no live snapshot points at a
    // deleted file; unused copies can be cleaned up by a future safe GC.
    return projectRepository.updateProjectIfUnchanged(
      project.copyWith(
        audioAsset: vocal
            ? audio.copyWith(vocalPath: destination.path)
            : audio.copyWith(instrumentalPath: destination.path),
      ),
      expectedRevision: project.revision,
    );
  }
}
