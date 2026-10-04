import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
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

  final importChoice = await _showLyricImportOptionsDialog(
    context,
    path: path,
    supportedExtensions: importer.supportedExtensions,
  );
  if (importChoice == null || !context.mounted) return;

  LyricImportResult result;
  try {
    result = await _importWithEncodingFallback(
      context,
      importer,
      path,
      encodingHint: importChoice.encodingHint,
    );
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
  String path, {
  String? encodingHint,
}) async {
  try {
    return await importer.importFile(path, encodingHint: encodingHint);
  } on LyricImportException catch (error) {
    final message = error.message.toLowerCase();
    final encodingRelated =
        message.contains('编码') || message.contains('解码');
    if (!encodingRelated || encodingHint != null) rethrow;
    if (!context.mounted) rethrow;

    final fallback = await _showLyricImportOptionsDialog(
      context,
      path: path,
      supportedExtensions: importer.supportedExtensions,
      recoveryMessage: error.message,
      forceManualEncoding: true,
    );
    if (fallback == null || fallback.encodingHint == null) rethrow;
    return importer.importFile(
      path,
      encodingHint: fallback.encodingHint,
    );
  }
}

Future<_LyricImportChoice?> _showLyricImportOptionsDialog(
  BuildContext context, {
  required String path,
  required Set<String> supportedExtensions,
  String? recoveryMessage,
  bool forceManualEncoding = false,
}) {
  return showDialog<_LyricImportChoice>(
    context: context,
    builder: (_) => _LyricImportOptionsDialog(
      path: path,
      supportedExtensions: supportedExtensions,
      recoveryMessage: recoveryMessage,
      forceManualEncoding: forceManualEncoding,
    ),
  );
}

class _LyricImportChoice {
  final String? encodingHint;

  const _LyricImportChoice({required this.encodingHint});
}

class _LyricImportOptionsDialog extends StatefulWidget {
  final String path;
  final Set<String> supportedExtensions;
  final String? recoveryMessage;
  final bool forceManualEncoding;

  const _LyricImportOptionsDialog({
    required this.path,
    required this.supportedExtensions,
    this.recoveryMessage,
    this.forceManualEncoding = false,
  });

  @override
  State<_LyricImportOptionsDialog> createState() =>
      _LyricImportOptionsDialogState();
}

class _LyricImportOptionsDialogState
    extends State<_LyricImportOptionsDialog> {
  late String _encodingValue;

  static const _encodingLabels = <String, String>{
    'auto': '自动检测（推荐）',
    'utf-8': 'UTF-8',
    'utf-16': 'UTF-16',
    'gbk': 'GBK / 中文 Windows',
    'shift_jis': 'Shift-JIS / 日文',
    'euc-jp': 'EUC-JP / 日文',
    'windows-1252': 'Windows-1252',
  };

  @override
  void initState() {
    super.initState();
    _encodingValue = widget.forceManualEncoding ? 'utf-8' : 'auto';
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final media = MediaQuery.of(context);
    final fileName = widget.path.split(Platform.pathSeparator).last;
    final extension = _extensionOf(widget.path).toUpperCase();
    final maxWidth = spec.isCompact
        ? (spec.width - spec.pageGutter * 2)
            .clamp(280.0, 520.0)
            .toDouble()
        : 560.0;
    final chromeReserve = spec.isShort ? 132.0 : 156.0;
    final maxHeight = (media.size.height -
            media.viewInsets.bottom -
            spec.pageGutter * 2 -
            chromeReserve)
        .clamp(64.0, 680.0)
        .toDouble();

    return AlertDialog(
      backgroundColor: AppColors.bgElevated,
      insetPadding: EdgeInsets.all(spec.pageGutter),
      titlePadding: EdgeInsets.fromLTRB(
        spec.pageGutter,
        spec.pageGutter,
        spec.pageGutter,
        AppSpacing.sm,
      ),
      contentPadding: EdgeInsets.fromLTRB(
        spec.pageGutter,
        0,
        spec.pageGutter,
        AppSpacing.sm,
      ),
      actionsPadding: EdgeInsets.fromLTRB(
        spec.pageGutter,
        AppSpacing.sm,
        spec.pageGutter,
        spec.pageGutter,
      ),
      title: Text(
        widget.forceManualEncoding ? '重新选择歌词编码' : '导入歌词',
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _ImportFileSummary(
                fileName: fileName,
                extension: extension,
              ),
              if (widget.recoveryMessage != null) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withAlpha(18),
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusMedium),
                    border: Border.all(
                      color: AppColors.warning.withAlpha(70),
                    ),
                  ),
                  child: Text(
                    '自动解码没有成功：${widget.recoveryMessage}\n'
                    '请选择这个歌词文件原本使用的文本编码。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Text(
                '文本编码',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                widget.forceManualEncoding
                    ? '请选择明确编码后再次导入。'
                    : '默认先自动检测。旧版中文 Windows 歌词常见 GBK，日文歌词常见 Shift-JIS / EUC-JP。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                value: _encodingValue,
                isExpanded: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.translate_rounded),
                ),
                items: [
                  for (final entry in _encodingLabels.entries)
                    if (!widget.forceManualEncoding || entry.key != 'auto')
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(
                          entry.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _encodingValue = value);
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                '支持格式',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.textTertiary,
                    ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final item
                      in (widget.supportedExtensions.toList()..sort()))
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(item.toUpperCase()),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '导入只会在 LyricForge 中建立或更新歌词工程，不会修改原音频文件，也不会覆盖音频标签。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
              ),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.end,
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            minimumSize: Size(0, spec.minimumInteractiveExtent),
          ),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(
            context,
            _LyricImportChoice(
              encodingHint:
                  _encodingValue == 'auto' ? null : _encodingValue,
            ),
          ),
          style: FilledButton.styleFrom(
            minimumSize: Size(0, spec.minimumInteractiveExtent),
          ),
          icon: const Icon(Icons.file_upload_outlined),
          label: Text(
            widget.forceManualEncoding ? '用此编码重试' : '导入',
          ),
        ),
      ],
    );
  }
}

class _ImportFileSummary extends StatelessWidget {
  final String fileName;
  final String extension;

  const _ImportFileSummary({
    required this.fileName,
    required this.extension,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      ),
      child: Row(
        children: [
          SizedBox(
            width: spec.minimumInteractiveExtent,
            height: spec.minimumInteractiveExtent,
            child: const Icon(Icons.lyrics_outlined),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  extension.isEmpty ? '歌词文本文件' : '$extension 歌词文件',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _extensionOf(String path) {
  final fileName = path.split(Platform.pathSeparator).last;
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return '';
  return fileName.substring(dot + 1);
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
