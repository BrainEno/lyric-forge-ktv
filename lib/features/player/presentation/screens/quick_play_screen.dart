import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/play_history.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/audio_library_import_service.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/playback_session_service.dart';
import '../widgets/local_media_metadata_dialog.dart';
import '../widgets/local_song_lyrics_import_action.dart';
import '../widgets/playback_queue_panel.dart';

/// Primary local-music player.
///
/// Songs remain ordinary local music until the user explicitly attaches lyrics
/// or starts a transcription workflow. Playback state/history is app-scoped and
/// survives route changes.
class QuickPlayScreen extends StatefulWidget {
  final PlayHistory? initialHistory;

  const QuickPlayScreen({
    super.key,
    this.initialHistory,
  });

  @override
  State<QuickPlayScreen> createState() => _QuickPlayScreenState();
}

class _QuickPlayScreenState extends State<QuickPlayScreen> {
  late final AudioPlayerService _audio;
  late final AudioLibraryImportService _importer;
  late final PlaybackSessionService _session;
  StreamSubscription<PlaybackSessionState>? _sessionSubscription;

  File? _selectedFile;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _audio = ServiceLocatorGlobal.I.audioPlayerService;
    _importer = ServiceLocatorGlobal.I.audioLibraryImportService;
    _session = ServiceLocatorGlobal.I.playbackSessionService;

    final current = _session.currentState.currentItem;
    if (current != null && current.projectId == null) {
      _selectedFile = File(current.audioAsset.originalPath);
    }
    _sessionSubscription = _session.stateStream.listen(_syncSessionState);

    if (widget.initialHistory != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadHistory(widget.initialHistory!);
      });
    }
  }

  Future<void> _loadHistory(PlayHistory history) async {
    final file = File(history.filePath);
    if (!await file.exists()) {
      if (!mounted) return;
      setState(() => _error = '找不到这首音乐的本地文件，可能已被移动或删除。');
      return;
    }

    if (!mounted) return;
    setState(() {
      _selectedFile = file;
      _error = null;
    });
    await _playFile(file, resumeFrom: history.lastPosition);
  }

  Future<void> _pickFiles() async {
    try {
      final paths = await _importer.pickAudioFiles();
      if (paths.isNotEmpty) await _queuePaths(paths);
    } catch (error, stackTrace) {
      debugPrint('Audio multi-select error: $error');
      debugPrint('$stackTrace');
      if (mounted) setState(() => _error = '无法导入音频: $error');
    }
  }

  Future<void> _pickFolder() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final paths = await _importer.pickAudioDirectory();
      if (paths.isEmpty) {
        if (mounted) setState(() => _error = '这个文件夹里没有找到支持的音频文件');
        return;
      }
      await _queuePaths(paths);
    } catch (error, stackTrace) {
      debugPrint('Audio folder import error: $error');
      debugPrint('$stackTrace');
      if (mounted) setState(() => _error = '无法读取音乐文件夹: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _queuePaths(List<String> paths) async {
    final items = <PlaybackItem>[];
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) continue;
      final format = _extension(path);
      if (!_importer.supportedExtensions.contains(format)) continue;

      final audioAsset = AudioAsset(originalPath: path, format: format);
      items.add(
        PlaybackItem(
          id: 'local:$path',
          title: _fileTitle(path),
          audioAsset: audioAsset,
          preferredSource: AudioSourceType.original,
          artworkPath: audioAsset.thumbnailPath,
        ),
      );
    }

    if (items.isEmpty) {
      if (mounted) setState(() => _error = '没有可播放的音频文件');
      return;
    }

    if (_selectedFile != null && _session.currentState.queue.isNotEmpty) {
      for (final item in items) {
        await _session.enqueue(item);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已添加 ${items.length} 首到播放队列')),
        );
      }
      return;
    }

    await _session.setQueue(items, startIndex: 0);
    if (!mounted) return;
    setState(() {
      _selectedFile = File(items.first.audioAsset.originalPath);
      _error = null;
    });
  }

  void _syncSessionState(PlaybackSessionState session) {
    if (!mounted) return;
    final current = session.currentItem;

    if (current == null) {
      if (_selectedFile != null) {
        setState(() {
          _selectedFile = null;
          _error = null;
        });
      }
      return;
    }

    if (current.projectId != null) {
      final projectId = current.projectId!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, Routes.playerPath(projectId));
        }
      });
      return;
    }

    setState(() {
      _selectedFile = File(current.audioAsset.originalPath);
      _error = null;
    });
  }

  Future<void> _playFile(File file, {Duration? resumeFrom}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final asset = AudioAsset(
        originalPath: file.path,
        format: _extension(file.path),
      );
      await _session.playItem(
        PlaybackItem(
          id: 'local:${file.path}',
          title: _fileTitle(file.path),
          audioAsset: asset,
          preferredSource: AudioSourceType.original,
          artworkPath: asset.thumbnailPath,
        ),
        resumeFrom: resumeFrom,
      );
    } catch (error) {
      if (mounted) setState(() => _error = '无法播放文件: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _fileName(String path) => path.split(Platform.pathSeparator).last;

  String _extension(String path) {
    final parts = path.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  String _fileTitle(String path) {
    return _fileName(path).replaceAll(
      RegExp(r'\.(mp3|flac|wav|m4a|ogg|aac)$', caseSensitive: false),
      '',
    );
  }

  Future<void> _seekRelative(Duration delta) async {
    final state = _audio.currentState;
    final duration = state.duration;
    var target = state.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (duration != null && target > duration) target = duration;
    await _session.seek(target);
  }

  Future<void> _showQueue() async {
    final height = (MediaQuery.sizeOf(context).height * 0.62)
        .clamp(280.0, 520.0)
        .toDouble();
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: PlaybackQueuePanel(
            session: _session,
            height: height,
            allowClearAll: true,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final file = _selectedFile;
    final current = _session.currentState.currentItem;
    final localItem = current != null && current.projectId == null ? current : null;
    final screenLayout = AppResponsive.of(context);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: const Text('本地音乐'),
        backgroundColor: AppColors.bgBase,
        actions: [
          if (file != null) ...[
            if (screenLayout.isCompact)
              IconButton(
                onPressed: _showQueue,
                icon: const Icon(Icons.queue_music_rounded),
                tooltip: '播放队列',
              ),
            IconButton(
              onPressed: _pickFiles,
              icon: const Icon(Icons.library_add_rounded),
              tooltip: '添加音乐到队列',
            ),
            IconButton(
              onPressed: _pickFolder,
              icon: const Icon(Icons.folder_copy_rounded),
              tooltip: '导入音乐文件夹',
            ),
          ],
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: SafeArea(
        child: file == null || localItem == null
            ? _EmptyPlayer(
                isLoading: _isLoading,
                error: _error,
                onPickFiles: _pickFiles,
                onPickFolder: _pickFolder,
                onCreateProject: () =>
                    Navigator.pushNamed(context, Routes.import),
              )
            : _PlayerWorkspace(
                audio: _audio,
                session: _session,
                item: localItem,
                format: _extension(file.path).toUpperCase(),
                fileName: _fileName(file.path),
                isLoading: _isLoading,
                error: _error,
                onSkipBack: () =>
                    _seekRelative(const Duration(seconds: -10)),
                onSkipForward: () =>
                    _seekRelative(const Duration(seconds: 10)),
                onEditMetadata: () =>
                    showLocalMediaMetadataDialog(context, localItem),
                onLyrics: () =>
                    importLyricsForLocalPlaybackItem(context, localItem),
              ),
      ),
    );
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    super.dispose();
  }
}

class _EmptyPlayer extends StatelessWidget {
  final bool isLoading;
  final String? error;
  final VoidCallback onPickFiles;
  final VoidCallback onPickFolder;
  final VoidCallback onCreateProject;

  const _EmptyPlayer({
    required this.isLoading,
    required this.error,
    required this.onPickFiles,
    required this.onPickFolder,
    required this.onCreateProject,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppResponsive.fromConstraints(constraints);
        final heroExtent = layout.isShort
            ? 92.0
            : layout.isCompact
                ? 112.0
                : 156.0;
        final cardPadding = layout.isCompact ? AppSpacing.md : AppSpacing.xl;

        return Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(layout.pageGutter),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: layout.isCompact ? 560 : 760,
              ),
              child: Container(
                padding: EdgeInsets.all(cardPadding),
                decoration: BoxDecoration(
                  gradient: AppColors.cardGradient,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
                  border: Border.all(color: AppColors.borderMuted),
                ),
                child: Column(
                  children: [
                    Container(
                      width: heroExtent,
                      height: heroExtent,
                      decoration: BoxDecoration(
                        color: AppColors.bgSurface,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusXLarge),
                      ),
                      child: Icon(
                        Icons.library_music_rounded,
                        size: heroExtent * 0.44,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    SizedBox(
                      height: layout.isShort ? AppSpacing.md : AppSpacing.xl,
                    ),
                    Text(
                      '你的本地音乐',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '先像普通播放器一样打开音乐。歌词、AI 识别、KTV 和工程制作都是需要时再使用的能力。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ],
                    SizedBox(
                      height: layout.isShort ? AppSpacing.md : AppSpacing.xl,
                    ),
                    if (isLoading)
                      const Padding(
                        padding: EdgeInsets.only(bottom: AppSpacing.md),
                        child: CircularProgressIndicator(),
                      ),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      alignment: WrapAlignment.center,
                      children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: Size(
                              layout.minimumInteractiveExtent,
                              layout.minimumInteractiveExtent,
                            ),
                          ),
                          onPressed: isLoading ? null : onPickFiles,
                          icon: const Icon(Icons.library_add_rounded),
                          label: const Text('选择音乐'),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: Size(
                              layout.minimumInteractiveExtent,
                              layout.minimumInteractiveExtent,
                            ),
                          ),
                          onPressed: isLoading ? null : onPickFolder,
                          icon: const Icon(Icons.folder_copy_rounded),
                          label: const Text('打开音乐文件夹'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextButton.icon(
                      onPressed: onCreateProject,
                      icon: const Icon(Icons.auto_awesome_rounded),
                      label: const Text('需要 AI 识别？进入歌词制作'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlayerWorkspace extends StatelessWidget {
  final AudioPlayerService audio;
  final PlaybackSessionService session;
  final PlaybackItem item;
  final String format;
  final String fileName;
  final bool isLoading;
  final String? error;
  final VoidCallback onSkipBack;
  final VoidCallback onSkipForward;
  final VoidCallback onEditMetadata;
  final VoidCallback onLyrics;

  const _PlayerWorkspace({
    required this.audio,
    required this.session,
    required this.item,
    required this.format,
    required this.fileName,
    required this.isLoading,
    required this.error,
    required this.onSkipBack,
    required this.onSkipForward,
    required this.onEditMetadata,
    required this.onLyrics,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: audio.stateStream,
      initialData: audio.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? const PlaybackState.idle();
        return LayoutBuilder(
          builder: (context, constraints) {
            final layout = AppResponsive.fromConstraints(constraints);
            final player = _PlayerCard(
              layout: layout,
              item: item,
              format: format,
              fileName: fileName,
              state: state,
              isLoading: isLoading,
              error: error ?? state.error,
              session: session,
              audio: audio,
              onSkipBack: onSkipBack,
              onSkipForward: onSkipForward,
              onEditMetadata: onEditMetadata,
              onLyrics: onLyrics,
            );
            final queueHeight = layout.isShort
                ? 220.0
                : layout.isCompact
                    ? 300.0
                    : 360.0;

            if (layout.isCompact) {
              final playerWidth = (constraints.maxWidth - layout.pageGutter * 2)
                  .clamp(0.0, layout.playerContentMaxWidth)
                  .toDouble();
              return Padding(
                padding: EdgeInsets.all(layout.pageGutter),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: playerWidth,
                      child: player,
                    ),
                  ),
                ),
              );
            }

            if (!layout.supportsTwoPane) {
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: layout.playerContentMaxWidth),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(layout.pageGutter),
                    child: Column(
                      children: [
                        player,
                        SizedBox(height: layout.sectionGap),
                        PlaybackQueuePanel(
                          session: session,
                          height: queueHeight,
                          allowClearAll: true,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final availableQueueHeight = constraints.maxHeight.isFinite
                ? (constraints.maxHeight - layout.pageGutter * 2)
                    .clamp(260.0, 720.0)
                    .toDouble()
                : 520.0;
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: layout.playerContentMaxWidth),
                child: Padding(
                  padding: EdgeInsets.all(layout.pageGutter),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: player,
                        ),
                      ),
                      SizedBox(width: layout.sectionGap),
                      SizedBox(
                        width: layout.sidePanelWidth,
                        child: PlaybackQueuePanel(
                          session: session,
                          height: availableQueueHeight,
                          allowClearAll: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PlayerCard extends StatelessWidget {
  final AppLayoutSpec layout;
  final PlaybackItem item;
  final String format;
  final String fileName;
  final PlaybackState state;
  final bool isLoading;
  final String? error;
  final PlaybackSessionService session;
  final AudioPlayerService audio;
  final VoidCallback onSkipBack;
  final VoidCallback onSkipForward;
  final VoidCallback onEditMetadata;
  final VoidCallback onLyrics;

  const _PlayerCard({
    required this.layout,
    required this.item,
    required this.format,
    required this.fileName,
    required this.state,
    required this.isLoading,
    required this.error,
    required this.session,
    required this.audio,
    required this.onSkipBack,
    required this.onSkipForward,
    required this.onEditMetadata,
    required this.onLyrics,
  });

  @override
  Widget build(BuildContext context) {
    final horizontal = !layout.isShort &&
        (layout.isExpanded || layout.isLarge || layout.isExtraLarge);
    final artworkExtent = layout.isCompact
        ? (layout.height * 0.28).clamp(180.0, 240.0).toDouble()
        : horizontal
            ? layout.playerArtworkMaxExtent.clamp(210.0, 300.0).toDouble()
            : layout.playerArtworkMaxExtent.clamp(200.0, 360.0).toDouble();
    final cardPadding = layout.isCompact
        ? AppSpacing.md
        : layout.isMedium
            ? AppSpacing.lg
            : AppSpacing.xl;

    final artwork = SizedBox(
      width: artworkExtent,
      child: RepaintBoundary(
        child: _Artwork(
          path: item.artworkPath ?? item.audioAsset.thumbnailPath,
          isLoading: isLoading || state.isLoading,
        ),
      ),
    );
    final details = _PlayerDetails(
      layout: layout,
      item: item,
      format: format,
      fileName: fileName,
      state: state,
      error: error,
      session: session,
      audio: audio,
      onSkipBack: onSkipBack,
      onSkipForward: onSkipForward,
      onEditMetadata: onEditMetadata,
      onLyrics: onLyrics,
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(cardPadding),
          decoration: BoxDecoration(
            gradient: AppColors.cardGradient,
            borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
            border: Border.all(color: AppColors.borderMuted),
          ),
          child: horizontal
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    artwork,
                    SizedBox(width: layout.sectionGap),
                    Expanded(child: details),
                  ],
                )
              : Column(
                  children: [
                    artwork,
                    SizedBox(height: layout.sectionGap),
                    details,
                  ],
                ),
        ),
      ),
    );
  }
}

class _PlayerDetails extends StatelessWidget {
  final AppLayoutSpec layout;
  final PlaybackItem item;
  final String format;
  final String fileName;
  final PlaybackState state;
  final String? error;
  final PlaybackSessionService session;
  final AudioPlayerService audio;
  final VoidCallback onSkipBack;
  final VoidCallback onSkipForward;
  final VoidCallback onEditMetadata;
  final VoidCallback onLyrics;

  const _PlayerDetails({
    required this.layout,
    required this.item,
    required this.format,
    required this.fileName,
    required this.state,
    required this.error,
    required this.session,
    required this.audio,
    required this.onSkipBack,
    required this.onSkipForward,
    required this.onEditMetadata,
    required this.onLyrics,
  });

  @override
  Widget build(BuildContext context) {
    final artist = item.artist?.trim();
    final titleStyle = (layout.isCompact
            ? Theme.of(context).textTheme.headlineSmall
            : Theme.of(context).textTheme.headlineMedium)
        ?.copyWith(
      fontWeight: FontWeight.w900,
      height: 1.08,
      letterSpacing: -0.5,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '本地音乐',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          item.title,
          maxLines: layout.isCompact ? 2 : 3,
          overflow: TextOverflow.ellipsis,
          style: titleStyle,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          artist?.isNotEmpty == true ? artist! : '未知艺人',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            _InfoChip(label: format.isEmpty ? 'AUDIO' : format),
            _InfoChip(label: item.hasLyrics ? '已有歌词' : '未添加歌词'),
            const _InfoChip(label: 'LOCAL'),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
              ),
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.error.withAlpha(18),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
            ),
            child: Text(
              error!,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
        SizedBox(height: layout.isShort ? AppSpacing.md : AppSpacing.xl),
        _ProgressBar(state: state, onSeek: session.seek),
        const SizedBox(height: AppSpacing.md),
        _Transport(
          layout: layout,
          state: state,
          session: session,
          onSkipBack: onSkipBack,
          onSkipForward: onSkipForward,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            const Icon(
              Icons.volume_down_rounded,
              size: 20,
              color: AppColors.textTertiary,
            ),
            Expanded(
              child: Slider(
                value: state.volume.clamp(0.0, 1.0).toDouble(),
                min: 0,
                max: 1,
                onChanged: audio.setVolume,
              ),
            ),
            const Icon(
              Icons.volume_up_rounded,
              size: 20,
              color: AppColors.textTertiary,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                minimumSize: Size(
                  layout.minimumInteractiveExtent,
                  layout.minimumInteractiveExtent,
                ),
              ),
              onPressed: onLyrics,
              icon: const Icon(Icons.lyrics_rounded),
              label: Text(item.hasLyrics ? '打开歌词' : '导入歌词'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: Size(
                  layout.minimumInteractiveExtent,
                  layout.minimumInteractiveExtent,
                ),
              ),
              onPressed: onEditMetadata,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('编辑资料与封面'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Artwork extends StatelessWidget {
  final String? path;
  final bool isLoading;

  const _Artwork({
    required this.path,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final file = path == null ? null : File(path!);
    final hasArtwork = file != null && file.existsSync();

    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
        child: Container(
          decoration: BoxDecoration(
            gradient: AppColors.cardGradient,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(82),
                blurRadius: 32,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : hasArtwork
                  ? Image.file(file!, fit: BoxFit.cover)
                  : Container(
                      color: AppColors.bgSurface,
                      child: const Icon(
                        Icons.album_rounded,
                        size: 96,
                        color: AppColors.textSecondary,
                      ),
                    ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;

  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.bgHighlight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _Transport extends StatelessWidget {
  final AppLayoutSpec layout;
  final PlaybackState state;
  final PlaybackSessionService session;
  final VoidCallback onSkipBack;
  final VoidCallback onSkipForward;

  const _Transport({
    required this.layout,
    required this.state,
    required this.session,
    required this.onSkipBack,
    required this.onSkipForward,
  });

  @override
  Widget build(BuildContext context) {
    final queue = session.currentState;
    final secondaryExtent = layout.minimumInteractiveExtent;
    final primaryExtent = layout.primaryPlayerControlExtent;

    Widget secondaryButton({
      required String tooltip,
      required IconData icon,
      required VoidCallback? onPressed,
    }) {
      return SizedBox(
        width: secondaryExtent,
        height: secondaryExtent,
        child: IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          icon: Icon(icon),
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        secondaryButton(
          onPressed: queue.canSkipPrevious ? session.skipPrevious : null,
          tooltip: '上一首 / 重新开始',
          icon: Icons.skip_previous_rounded,
        ),
        secondaryButton(
          onPressed: onSkipBack,
          tooltip: '后退 10 秒',
          icon: Icons.replay_10_rounded,
        ),
        SizedBox(
          width: primaryExtent,
          height: primaryExtent,
          child: IconButton(
            onPressed: state.isBuffering || state.isLoading
                ? null
                : session.togglePlayPause,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.pureWhite,
              disabledBackgroundColor: AppColors.textDisabled,
              foregroundColor: AppColors.pureBlack,
            ),
            icon: state.isBuffering || state.isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.pureBlack,
                    ),
                  )
                : Icon(
                    state.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: layout.isCompact ? 30 : 34,
                  ),
          ),
        ),
        secondaryButton(
          onPressed: onSkipForward,
          tooltip: '前进 10 秒',
          icon: Icons.forward_10_rounded,
        ),
        secondaryButton(
          onPressed: queue.canSkipNext ? session.skipNext : null,
          tooltip: '下一首',
          icon: Icons.skip_next_rounded,
        ),
      ],
    );
  }
}

class _ProgressBar extends StatefulWidget {
  final PlaybackState state;
  final ValueChanged<Duration> onSeek;

  const _ProgressBar({required this.state, required this.onSeek});

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final duration = widget.state.duration;
    final rawMax = duration?.inMilliseconds.toDouble() ?? 1.0;
    final max = rawMax <= 0 ? 1.0 : rawMax;
    final playbackValue = widget.state.position.inMilliseconds
        .toDouble()
        .clamp(0.0, max)
        .toDouble();
    final value = (_dragValue ?? playbackValue).clamp(0.0, max).toDouble();
    final displayPosition = _dragValue == null
        ? widget.state.formattedPosition
        : _formatDuration(Duration(milliseconds: value.round()));

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: AppColors.pureWhite,
            inactiveTrackColor: AppColors.bgHighlight,
            thumbColor: AppColors.pureWhite,
            overlayColor: AppColors.hoverOverlay,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: value,
            min: 0,
            max: max,
            onChangeStart: duration == null
                ? null
                : (next) => setState(() => _dragValue = next),
            onChanged: duration == null
                ? null
                : (next) => setState(() => _dragValue = next),
            onChangeEnd: duration == null
                ? null
                : (next) {
                    setState(() => _dragValue = null);
                    widget.onSeek(Duration(milliseconds: next.round()));
                  },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              displayPosition,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
            Text(
              widget.state.formattedDuration,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
