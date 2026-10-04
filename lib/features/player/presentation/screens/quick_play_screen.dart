import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/play_history.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/repositories/play_history_repository.dart';
import '../../domain/services/audio_library_import_service.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/playback_session_service.dart';
import '../widgets/playback_queue_panel.dart';

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
  late final PlayHistoryRepository _history;
  StreamSubscription<PlaybackSessionState>? _sessionSubscription;

  File? _selectedFile;
  String? _activeHistoryId;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _audio = ServiceLocatorGlobal.I.audioPlayerService;
    _importer = ServiceLocatorGlobal.I.audioLibraryImportService;
    _session = ServiceLocatorGlobal.I.playbackSessionService;
    _history = ServiceLocatorGlobal.I.playHistoryRepository;

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
      _activeHistoryId = history.id;
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
          title: _title(path),
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

    _activeHistoryId = const Uuid().v4();
    await _session.setQueue(items, startIndex: 0);
    final first = File(items.first.audioAsset.originalPath);
    if (mounted) {
      setState(() {
        _selectedFile = first;
        _error = null;
      });
    }
    await _saveHistory(first);
  }

  void _syncSessionState(PlaybackSessionState session) {
    if (!mounted) return;
    final current = session.currentItem;

    if (current == null) {
      if (_selectedFile != null) {
        setState(() {
          _selectedFile = null;
          _activeHistoryId = null;
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

    final file = File(current.audioAsset.originalPath);
    final changedTrack = _selectedFile?.path != file.path;
    setState(() {
      _selectedFile = file;
      _error = null;
      if (changedTrack) _activeHistoryId = const Uuid().v4();
    });

    if (changedTrack) unawaited(_saveHistory(file));
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
      _activeHistoryId ??= const Uuid().v4();
      await _session.playItem(
        PlaybackItem(
          id: 'local:${file.path}',
          title: _title(file.path),
          audioAsset: asset,
          preferredSource: AudioSourceType.original,
          artworkPath: asset.thumbnailPath,
        ),
        resumeFrom: resumeFrom,
      );
      await _saveHistory(file);
    } catch (error) {
      if (mounted) setState(() => _error = '无法播放文件: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveHistory(File file) async {
    try {
      final state = _audio.currentState;
      final id = _activeHistoryId ?? const Uuid().v4();
      _activeHistoryId = id;
      await _history.savePlayHistory(
        PlayHistory(
          id: id,
          name: _title(file.path),
          filePath: file.path,
          playedAt: DateTime.now(),
          lastPosition: state.position,
          duration: state.duration,
          lastSource: AudioSourceType.original,
        ),
      );
    } catch (error) {
      debugPrint('Failed to save play history: $error');
    }
  }

  String _fileName(String path) => path.split(Platform.pathSeparator).last;

  String _extension(String path) {
    final parts = path.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  String _title(String path) {
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
    await _audio.seek(target);
  }

  void _showKtvHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('这首音乐还没有歌词工程。新建工程并完成歌词识别后即可进入 KTV 模式。'),
        action: SnackBarAction(
          label: '新建工程',
          onPressed: () => Navigator.pushNamed(context, Routes.import),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final file = _selectedFile;
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: Text(file == null ? '本地播放器' : '本地音乐'),
        backgroundColor: AppColors.bgBase,
        actions: [
          if (file != null) ...[
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
        child: file == null
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
                title: _title(file.path),
                format: _extension(file.path).toUpperCase(),
                isLoading: _isLoading,
                error: _error,
                onSkipBack: () =>
                    _seekRelative(const Duration(seconds: -10)),
                onSkipForward: () =>
                    _seekRelative(const Duration(seconds: 10)),
                onKtvTap: _showKtvHint,
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
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            children: [
              Container(
                width: 148,
                height: 148,
                decoration: BoxDecoration(
                  gradient: AppColors.cardGradient,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(70),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.library_music_rounded,
                  size: 64,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                '打开本地音乐',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '多选音频或直接选择整个文件夹。歌曲会进入同一个全局播放队列，离开此页后仍可继续播放。',
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
              const SizedBox(height: AppSpacing.xl),
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
                    onPressed: isLoading ? null : onPickFiles,
                    icon: const Icon(Icons.library_add_rounded),
                    label: const Text('选择音乐（可多选）'),
                  ),
                  OutlinedButton.icon(
                    onPressed: isLoading ? null : onPickFolder,
                    icon: const Icon(Icons.folder_copy_rounded),
                    label: const Text('导入文件夹'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton.icon(
                onPressed: onCreateProject,
                icon: const Icon(Icons.lyrics_rounded),
                label: const Text('需要识别歌词？新建工程'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerWorkspace extends StatelessWidget {
  final AudioPlayerService audio;
  final PlaybackSessionService session;
  final String title;
  final String format;
  final bool isLoading;
  final String? error;
  final VoidCallback onSkipBack;
  final VoidCallback onSkipForward;
  final VoidCallback onKtvTap;

  const _PlayerWorkspace({
    required this.audio,
    required this.session,
    required this.title,
    required this.format,
    required this.isLoading,
    required this.error,
    required this.onSkipBack,
    required this.onSkipForward,
    required this.onKtvTap,
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
            final wide = constraints.maxWidth >= 1040;
            final player = _PlayerCard(
              title: title,
              format: format,
              state: state,
              isLoading: isLoading,
              error: error ?? state.error,
              session: session,
              audio: audio,
              onSkipBack: onSkipBack,
              onSkipForward: onSkipForward,
              onKtvTap: onKtvTap,
            );

            if (!wide) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  children: [
                    player,
                    const SizedBox(height: AppSpacing.lg),
                    PlaybackQueuePanel(
                      session: session,
                      height: 380,
                      allowClearAll: true,
                    ),
                  ],
                ),
              );
            }

            final queueHeight = constraints.maxHeight > 80
                ? constraints.maxHeight - 32
                : constraints.maxHeight;
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: player,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  SizedBox(
                    width: 390,
                    child: PlaybackQueuePanel(
                      session: session,
                      height: queueHeight,
                      allowClearAll: true,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _PlayerCard extends StatelessWidget {
  final String title;
  final String format;
  final PlaybackState state;
  final bool isLoading;
  final String? error;
  final PlaybackSessionService session;
  final AudioPlayerService audio;
  final VoidCallback onSkipBack;
  final VoidCallback onSkipForward;
  final VoidCallback onKtvTap;

  const _PlayerCard({
    required this.title,
    required this.format,
    required this.state,
    required this.isLoading,
    required this.error,
    required this.session,
    required this.audio,
    required this.onSkipBack,
    required this.onSkipForward,
    required this.onKtvTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
            border: Border.all(color: AppColors.borderMuted),
          ),
          child: Column(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 330),
                child: _Artwork(isLoading: isLoading || state.isLoading),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                '本地音乐',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '$format · 暂无歌词',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
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
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              _ProgressBar(state: state, onSeek: session.seek),
              const SizedBox(height: AppSpacing.lg),
              _Transport(
                state: state,
                session: session,
                onSkipBack: onSkipBack,
                onSkipForward: onSkipForward,
              ),
              const SizedBox(height: AppSpacing.lg),
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
              OutlinedButton.icon(
                onPressed: onKtvTap,
                icon: const Icon(Icons.mic_rounded),
                label: const Text('创建歌词工程后进入 KTV'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  final bool isLoading;

  const _Artwork({required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.cardGradient,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(82),
              blurRadius: 32,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Center(
          child: isLoading
              ? const CircularProgressIndicator()
              : const Icon(
                  Icons.album_rounded,
                  size: 104,
                  color: AppColors.textSecondary,
                ),
        ),
      ),
    );
  }
}

class _Transport extends StatelessWidget {
  final PlaybackState state;
  final PlaybackSessionService session;
  final VoidCallback onSkipBack;
  final VoidCallback onSkipForward;

  const _Transport({
    required this.state,
    required this.session,
    required this.onSkipBack,
    required this.onSkipForward,
  });

  @override
  Widget build(BuildContext context) {
    final queue = session.currentState;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      children: [
        IconButton(
          onPressed: queue.canSkipPrevious ? session.skipPrevious : null,
          tooltip: '上一首 / 重新开始',
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        IconButton(
          onPressed: onSkipBack,
          tooltip: '后退 10 秒',
          icon: const Icon(Icons.replay_10_rounded),
        ),
        SizedBox(
          width: 64,
          height: 64,
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
                    size: 34,
                  ),
          ),
        ),
        IconButton(
          onPressed: onSkipForward,
          tooltip: '前进 10 秒',
          icon: const Icon(Icons.forward_10_rounded),
        ),
        IconButton(
          onPressed: queue.canSkipNext ? session.skipNext : null,
          tooltip: '下一首',
          icon: const Icon(Icons.skip_next_rounded),
        ),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final PlaybackState state;
  final ValueChanged<Duration> onSeek;

  const _ProgressBar({required this.state, required this.onSeek});

  @override
  Widget build(BuildContext context) {
    final duration = state.duration;
    final rawMax = duration?.inMilliseconds.toDouble() ?? 1.0;
    final max = rawMax <= 0 ? 1.0 : rawMax;
    final value =
        state.position.inMilliseconds.toDouble().clamp(0.0, max).toDouble();

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
            onChanged: duration == null
                ? null
                : (next) => onSeek(Duration(milliseconds: next.round())),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              state.formattedPosition,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
            Text(
              state.formattedDuration,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}
