import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../lyrics/domain/services/lyric_file_import_service.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/local_media_metadata.dart';
import '../../domain/repositories/local_media_metadata_repository.dart';
import '../../domain/services/playback_session_service.dart';

Future<void> importLyricsForLocalPlaybackItem(
  BuildContext context,
  PlaybackItem item,
) async {
  if (item.projectId != null) return;

  final importer = ServiceLocatorGlobal.I.lyricFileImportService;
  final projectRepository = ServiceLocatorGlobal.I.projectRepository;
  final mediaMetadataRepository =
      ServiceLocatorGlobal.I.localMediaMetadataRepository;
  final playbackSession = ServiceLocatorGlobal.I.playbackSessionService;

  ProjectManifest? project = await _linkedOrMatchingProject(
    projectRepository: projectRepository,
    mediaMetadataRepository: mediaMetadataRepository,
    item: item,
  );
  if (!context.mounted) return;

  // Treat lyrics as part of the song rather than as an import-only workflow:
  // once a local song already has lyrics, the same control opens its editor.
  if (project?.hasLyrics == true) {
    await Navigator.pushNamed(
      context,
      Routes.lyricEditorPath(project!.id),
    );
    return;
  }

  final picked = await FilePicker.platform.pickFiles(
    dialogTitle: '导入歌词文件',
    type: FileType.custom,
    allowedExtensions: importer.supportedExtensions.toList()..sort(),
    allowMultiple: false,
  );
  final path = picked?.files.single.path;
  if (path == null || path.isEmpty || !context.mounted) return;

  LyricImportResult result;
  try {
    result = await _importWithEncodingFallback(context, importer, path);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('歌词导入失败：$error')),
    );
    return;
  }

  project ??= await projectRepository.createProject(
    name: item.title,
    artist: item.artist ?? result.artist,
    album: result.album,
  );

  final existingMetadata = Map<String, dynamic>.from(project.metadata);
  final backups = _nextLyricBackups(project);
  final timed = result.document.metadata['timed'] == true;
  final importedDocument = result.document.copyWith(
    metadata: {
      ...result.document.metadata,
      'detectedEncoding': result.detectedEncoding,
      'importedAt': DateTime.now().toIso8601String(),
    },
  );

  final updated = project.copyWith(
    name: item.title,
    artist: item.artist ?? result.artist,
    album: project.album ?? result.album,
    audioAsset: item.audioAsset.copyWith(
      thumbnailPath: item.artworkPath ?? item.audioAsset.thumbnailPath,
    ),
    lyricDocument: importedDocument,
    status: timed ? ProjectStatus.ready : ProjectStatus.editing,
    currentStage: timed
        ? ProcessingStage.lyricsEdited
        : ProcessingStage.transcriptionComplete,
    metadata: {
      ...existingMetadata,
      'lyricSource': 'imported-file',
      'lyricImport': {
        'path': result.sourcePath,
        'format': result.format.name,
        'encoding': result.detectedEncoding,
        'timed': timed,
        'importedAt': DateTime.now().toIso8601String(),
      },
      if (backups.isNotEmpty) 'lyricBackups': backups,
    },
  );
  final savedProject = await projectRepository.updateProject(updated);

  await _linkProjectToLocalMedia(
    mediaMetadataRepository,
    item,
    savedProject.id,
  );
  await playbackSession.updateItem(item.copyWith(hasLyrics: true));

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        timed
            ? '歌词已导入，可直接校对或播放'
            : '文本歌词已导入，请在歌词编辑器中补时间轴',
      ),
    ),
  );
  await Navigator.pushNamed(
    context,
    Routes.lyricEditorPath(savedProject.id),
  );
}

Future<LyricImportResult> _importWithEncodingFallback(
  BuildContext context,
  LyricFileImportService importer,
  String path,
) async {
  try {
    return await importer.importFile(path);
  } on LyricImportException catch (error) {
    final message = error.message.toLowerCase();
    if (!message.contains('编码') && !message.contains('解码')) rethrow;
    if (!context.mounted) rethrow;

    final encoding = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择歌词文本编码'),
        children: [
          _encodingChoice(context, 'UTF-8', 'utf-8'),
          _encodingChoice(context, 'UTF-16', 'utf-16'),
          _encodingChoice(context, 'GBK / 中文 Windows', 'gbk'),
          _encodingChoice(context, 'Shift-JIS / 日文', 'shift_jis'),
          _encodingChoice(context, 'EUC-JP / 日文', 'euc-jp'),
          _encodingChoice(context, 'Windows-1252', 'windows-1252'),
        ],
      ),
    );
    if (encoding == null) rethrow;
    return importer.importFile(path, encodingHint: encoding);
  }
}

Widget _encodingChoice(BuildContext context, String label, String value) {
  return SimpleDialogOption(
    onPressed: () => Navigator.pop(context, value),
    child: Text(label),
  );
}

Future<ProjectManifest?> _linkedOrMatchingProject({
  required ProjectRepository projectRepository,
  required LocalMediaMetadataRepository mediaMetadataRepository,
  required PlaybackItem item,
}) async {
  try {
    final metadata = await mediaMetadataRepository.getForAudio(
      item.audioAsset.originalPath,
    );
    final linkedProjectId = metadata?.metadata['linkedProjectId'];
    if (linkedProjectId is String && linkedProjectId.isNotEmpty) {
      final linked = await projectRepository.getProjectById(linkedProjectId);
      if (linked != null) return linked;
    }
  } catch (_) {
    // Fall back to matching the audio path. Optional media metadata must never
    // prevent a user from opening/importing lyrics.
  }

  return _findProjectForAudio(
    projectRepository,
    item.audioAsset.originalPath,
  );
}

Future<ProjectManifest?> _findProjectForAudio(
  ProjectRepository repository,
  String path,
) async {
  final projects = await repository.getAllProjects();
  for (final project in projects) {
    final projectPath = project.audioAsset?.originalPath;
    if (projectPath != null && _samePath(projectPath, path)) return project;
  }
  return null;
}

bool _samePath(String a, String b) {
  final left = File(a).absolute.path;
  final right = File(b).absolute.path;
  if (Platform.isWindows) return left.toLowerCase() == right.toLowerCase();
  return left == right;
}

List<Map<String, dynamic>> _nextLyricBackups(ProjectManifest project) {
  if (!project.hasLyrics) return const [];
  final existing = <Map<String, dynamic>>[];
  final raw = project.metadata['lyricBackups'];
  if (raw is List) {
    for (final entry in raw) {
      if (entry is Map) existing.add(Map<String, dynamic>.from(entry));
    }
  }
  existing.insert(0, {
    'createdAt': DateTime.now().toIso8601String(),
    'reason': 'replaced-by-import',
    'document': project.lyricDocument!.toJson(),
  });
  return existing.take(3).toList(growable: false);
}

Future<void> _linkProjectToLocalMedia(
  LocalMediaMetadataRepository repository,
  PlaybackItem item,
  String projectId,
) async {
  final stored = await repository.getForAudio(item.audioAsset.originalPath);
  final metadata = stored ??
      LocalMediaMetadata(
        sourcePath: item.audioAsset.originalPath,
        updatedAt: DateTime.now(),
      );
  await repository.save(
    metadata.copyWith(
      updatedAt: DateTime.now(),
      metadata: {
        ...metadata.metadata,
        'linkedProjectId': projectId,
        'hasLyrics': true,
      },
    ),
  );
}
