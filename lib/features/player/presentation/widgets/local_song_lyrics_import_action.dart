import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_capabilities.dart';
import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../lyrics/domain/services/lyric_file_import_service.dart';
import '../../../project/domain/models/lyric_timing.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/repositories/local_media_metadata_repository.dart';
import '../../domain/services/imported_lyrics_project.dart';
import '../../domain/services/playback_lyrics_project_linker.dart';
import '../../domain/services/playback_session_service.dart';
import '../local_library_dependencies.dart';
import 'lyric_file_picker.dart';
import 'lyrics_source_sheet.dart';
import 'song_lyrics_acquisition.dart';
import 'song_lyrics_preview_dialog.dart';

/// Adds lyrics to a local song that does not have a lyric project yet.
///
/// The user picks where they come from (D-054): the lyric sites, timed lyrics
/// first and checked by ear before saving; a lyric file; or pasted text.
/// Untimed lyrics are kept as reference lyrics the player shows statically.
///
/// [dependencies] replaced five app-wide service lookups: the action is a
/// function, not a widget, so it had nowhere to receive its collaborators from
/// and simply reached into the process-wide locator. Every caller — the library,
/// quick play and both player bars — now passes the bundle it already holds.
Future<void> importLyricsForLocalPlaybackItem(
  BuildContext context,
  PlaybackItem item,
  LyricsImportDependencies dependencies,
) async {
  if (item.projectId != null) return;

  final importer = dependencies.importer;
  final resolver = dependencies.lyricsResolver;
  final projectRepository = resolver.projectRepository;
  final mediaMetadataRepository = resolver.metadataRepository;

  // Do not treat a storage failure as an absent project: that could create a
  // duplicate project or replace an existing association.
  String? resolvedProjectId;
  ProjectManifest? project;
  try {
    final resolution = await resolver.resolveAndSync(item);
    resolvedProjectId = resolution.projectId;
    if (resolvedProjectId == null) {
      project = await _linkedOrMatchingProject(
        projectRepository: projectRepository,
        mediaMetadataRepository: mediaMetadataRepository,
        item: item,
      );
    }
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('无法读取歌曲或歌词工程，请检查存储后重试：$error')));
    return;
  }
  if (!context.mounted) return;
  if (resolvedProjectId != null) {
    if (AppCapabilities.lyricWorkbench) {
      await Navigator.pushNamed(
        context,
        Routes.lyricEditorPath(resolvedProjectId),
      );
      return;
    }
    // A phone has no lyric editor (D-058): its 导入歌词 on a song with
    // lyrics replaces them, from the same three sources.
    try {
      project = await projectRepository.getProjectById(resolvedProjectId);
    } on Object {
      project = null;
    }
    if (!context.mounted) return;
    if (project == null) {
      await Navigator.pushNamed(context, Routes.playerPath(resolvedProjectId));
      return;
    }
  }

  final lookup = dependencies.songLyricsLookup;
  final choice = await showLyricsSourceSheet(
    context,
    onlineAvailable: lookup != null,
    songTitle: item.title,
  );
  if (choice == null || !context.mounted) return;
  if (choice == LyricsSourceChoice.file) {
    await _importLyricFileForItem(context, item, dependencies, project);
    return;
  }

  final queries = await songLyricsQueries(
    name: item.title,
    artist: item.artist,
    duration: item.audioAsset.duration,
    audioPath: choice == LyricsSourceChoice.online
        ? item.audioAsset.originalPath
        : null,
    tagReader: dependencies.songTagReader,
  );
  if (!context.mounted) return;
  final lyrics = await acquireSongLyrics(
    context,
    choice: choice,
    importer: importer,
    lookup: lookup,
    playback: _previewPlayback(item, dependencies),
    query: queries.first,
    fallbackQueries: queries.skip(1).toList(),
  );
  if (lyrics == null || !context.mounted) return;

  final ProjectManifest saved;
  try {
    saved = await _saveLyricsForItem(
      item,
      dependencies,
      project,
      lyrics.result,
      source: lyrics.source,
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('歌词保存失败：$error')));
    return;
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(savedSongLyricsMessage(lyrics))));
  // Fetched and pasted lyrics are meant to be read while listening, so the
  // song opens in the player rather than in the editor.
  await Navigator.pushNamed(context, Routes.playerPath(saved.id));
}

/// The original 导入歌词文件 path: file picker, encoding choice, import.
///
/// Timed files open in the editor, as they always did; plain-text files are
/// reference lyrics now (D-054) and open in the player, which shows them as
/// static text.
Future<void> _importLyricFileForItem(
  BuildContext context,
  PlaybackItem item,
  LyricsImportDependencies dependencies,
  ProjectManifest? project,
) async {
  final importer = dependencies.importer;
  String? path;
  try {
    path = await pickLyricFilePath(importer);
  } on LyricImportException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
    return;
  }
  if (path == null || !context.mounted) return;

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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('歌词导入失败：$error')));
    return;
  }

  final savedProject = await _saveLyricsForItem(
    item,
    dependencies,
    project,
    result,
  );

  if (!context.mounted) return;
  final timed = result.document.isTimed;
  // A phone has no editor (D-058), so timed files open in the player too.
  final workbench = AppCapabilities.lyricWorkbench;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        importedLyricFileMessage(
          timed: timed,
          wordTimedRows: result.wordTimedRows,
          workbench: workbench,
        ),
      ),
    ),
  );
  await Navigator.pushNamed(
    context,
    timed && workbench
        ? Routes.lyricEditorPath(savedProject.id)
        : Routes.playerPath(savedProject.id),
  );
}

/// The note after a lyric file was imported. Untimed text is shown as static
/// reference lyrics; [workbench] says whether the editor is there to time or
/// proofread it (not on a phone, D-058).
@visibleForTesting
String importedLyricFileMessage({
  required bool timed,
  required int wordTimedRows,
  required bool workbench,
}) {
  if (!timed) {
    return workbench
        ? '文本歌词已作为参考歌词导入：播放时静态显示，需要同步时再去打轴'
        : '文本歌词已导入：播放时静态显示，可手动滚动';
  }
  final next = workbench ? '可直接校对或播放' : '可直接播放';
  return wordTimedRows > 0
      ? '歌词已导入（$wordTimedRows 行带逐字时间），$next'
      : '歌词已导入，$next';
}

/// Creates the song's project when needed, stores [result] on it and links
/// the song to it, so the library, the queue and Now Playing all see it.
Future<ProjectManifest> _saveLyricsForItem(
  PlaybackItem item,
  LyricsImportDependencies dependencies,
  ProjectManifest? project,
  LyricImportResult result, {
  String source = 'imported-file',
}) async {
  final resolver = dependencies.lyricsResolver;
  final projectRepository = resolver.projectRepository;
  final target =
      project ??
      await projectRepository.createProject(
        name: item.title,
        artist: item.artist ?? result.artist,
        album: result.album,
      );
  final updated = projectWithImportedLyrics(
    target,
    title: item.title,
    artist: item.artist,
    audioAsset: item.audioAsset,
    artworkPath: item.artworkPath,
    result: result,
    now: DateTime.now(),
    source: source,
  );
  final savedProject = await projectRepository.updateProject(updated);
  await linkPlaybackLyricsProject(
    audioPath: item.audioAsset.originalPath,
    projectId: savedProject.id,
    metadataRepository: resolver.metadataRepository,
    playbackSession: resolver.playbackSession,
    pathCanonicalizer: resolver.pathCanonicalizer,
  );
  return savedProject;
}

/// Lets the timing preview hear the song: it seeks the app player, and
/// starts this song first when another one is playing.
SongLyricsPreviewPlayback? _previewPlayback(
  PlaybackItem item,
  LyricsImportDependencies dependencies,
) {
  final audio = dependencies.audioPlayer;
  if (audio == null) return null;
  final session = dependencies.lyricsResolver.playbackSession;
  bool isCurrentSong() {
    final current = session.currentState.currentItem;
    if (current == null) return false;
    return current.id == item.id ||
        _samePath(
          current.audioAsset.originalPath,
          item.audioAsset.originalPath,
        );
  }

  return SongLyricsPreviewPlayback(
    positionStream: audio.positionStream,
    currentPosition: () => audio.currentState.position,
    isCurrentSong: isCurrentSong,
    seek: session.seek,
    playSong: () => session.playItem(item),
    togglePlayPause: session.togglePlayPause,
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
    final encodingRelated = message.contains('编码') || message.contains('解码');
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
    return importer.importFile(path, encodingHint: fallback.encodingHint);
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

class _LyricImportOptionsDialogState extends State<_LyricImportOptionsDialog> {
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
        ? (spec.width - spec.pageGutter * 2).clamp(280.0, 520.0).toDouble()
        : 560.0;
    final chromeReserve = spec.isShort ? 132.0 : 156.0;
    final maxHeight =
        (media.size.height -
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
      title: Text(widget.forceManualEncoding ? '重新选择歌词编码' : '导入歌词'),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _ImportFileSummary(fileName: fileName, extension: extension),
              if (widget.recoveryMessage != null) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withAlpha(18),
                    borderRadius: BorderRadius.circular(
                      AppSpacing.radiusMedium,
                    ),
                    border: Border.all(color: AppColors.warning.withAlpha(70)),
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
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                widget.forceManualEncoding
                    ? '请选择明确编码后再次导入。'
                    : '默认先自动检测。旧版中文 Windows 歌词常见 GBK，日文歌词常见 Shift-JIS / EUC-JP。',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: _encodingValue,
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
                '导入只会在 Elysium Player 中建立或更新歌词工程，不会修改原音频文件，也不会覆盖音频标签。',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
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
              encodingHint: _encodingValue == 'auto' ? null : _encodingValue,
            ),
          ),
          style: FilledButton.styleFrom(
            minimumSize: Size(0, spec.minimumInteractiveExtent),
          ),
          icon: const Icon(Icons.file_upload_outlined),
          label: Text(widget.forceManualEncoding ? '用此编码重试' : '导入'),
        ),
      ],
    );
  }
}

class _ImportFileSummary extends StatelessWidget {
  final String fileName;
  final String extension;

  const _ImportFileSummary({required this.fileName, required this.extension});

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
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
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
  final metadata = await readCompleteLocalMediaMetadataForAudio(
    mediaMetadataRepository,
    item.audioAsset.originalPath,
  );
  final linkedProjectId = metadata?.metadata['linkedProjectId'];
  if (linkedProjectId is String && linkedProjectId.isNotEmpty) {
    final linked = await projectRepository.getProjectById(linkedProjectId);
    if (linked != null) return linked;
  }

  return _findProjectForAudio(projectRepository, item.audioAsset.originalPath);
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
