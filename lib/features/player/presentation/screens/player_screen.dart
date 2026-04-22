import 'package:flutter/material.dart';

import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/audio_player_service.dart';

/// Player screen - KTV playback with synced lyrics display.
/// Desktop-first: real audio playback using just_audio.
class PlayerScreen extends StatefulWidget {
  final String projectId;

  const PlayerScreen({
    super.key,
    required this.projectId,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final ProjectRepository _repository;
  late final AudioPlayerService _audioService;
  late Future<ProjectManifest?> _projectFuture;

  @override
  void initState() {
    super.initState();
    _repository = ServiceLocatorGlobal.I.projectRepository;
    _audioService = ServiceLocatorGlobal.I.audioPlayerService;
    _loadProject();
  }

  void _loadProject() {
    _projectFuture = _repository.getProjectById(widget.projectId);
  }

  Future<void> _initializeAudio(ProjectManifest project) async {
    if (project.audioAsset != null) {
      try {
        await _audioService.loadProjectAudio(
          audioAsset: project.audioAsset!,
        );
      } catch (e) {
        // Error will be shown in UI via stream
      }
    }
  }

  Future<void> _playPause() async {
    final state = _audioService.currentState;
    if (state.isPlaying) {
      await _audioService.pause();
    } else {
      await _audioService.play();
    }
  }

  Future<void> _seek(Duration position) async {
    await _audioService.seek(position);
  }

  Future<void> _switchSource(AudioSourceType source) async {
    try {
      await _audioService.switchSource(source);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法切换到该音源: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProjectManifest?>(
      future: _projectFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingState();
        }

        if (snapshot.hasError || snapshot.data == null) {
          return _ErrorState(onRetry: () => setState(_loadProject));
        }

        final project = snapshot.data!;
        return _PlayerContent(
          project: project,
          audioService: _audioService,
          onInitialize: () => _initializeAudio(project),
          onPlayPause: _playPause,
          onSeek: _seek,
          onLyricTap: (line) => _seek(line.startTime),
          onSwitchSource: _switchSource,
        );
      },
    );
  }

  @override
  void dispose() {
    _audioService.stop();
    super.dispose();
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            const Text('加载失败'),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _PlayerContent extends StatefulWidget {
  final ProjectManifest project;
  final AudioPlayerService audioService;
  final VoidCallback onInitialize;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<LyricLine> onLyricTap;
  final ValueChanged<AudioSourceType> onSwitchSource;

  const _PlayerContent({
    required this.project,
    required this.audioService,
    required this.onInitialize,
    required this.onPlayPause,
    required this.onSeek,
    required this.onLyricTap,
    required this.onSwitchSource,
  });

  @override
  State<_PlayerContent> createState() => _PlayerContentState();
}

class _PlayerContentState extends State<_PlayerContent> {
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  void _initialize() {
    widget.onInitialize();
  }

  LyricLine? _getCurrentLine(List<LyricLine> lines, Duration position) {
    for (var i = lines.length - 1; i >= 0; i--) {
      if (position >= lines[i].startTime) {
        return lines[i];
      }
    }
    return lines.isNotEmpty ? lines.first : null;
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.project.lyricDocument?.lines ?? [];
    final availableSources = widget.project.audioAsset?.availableSources ?? [];

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: StreamBuilder<PlaybackState>(
          stream: widget.audioService.stateStream,
          initialData: widget.audioService.currentState,
          builder: (context, snapshot) {
            final state = snapshot.data ?? const PlaybackState.idle();
            final currentLine = _getCurrentLine(lyrics, state.position);

            return Column(
              children: [
                // Album artwork area
                Expanded(
                  flex: 2,
                  child: Container(
                    margin: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.bgElevated,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(77),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Container(
                          color: AppColors.bgSurface,
                          child: Center(
                            child: Icon(
                              Icons.album,
                              size: 80,
                              color: state.isLoading
                                  ? AppColors.accent
                                  : AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Song info
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Column(
                    children: [
                      Text(
                        widget.project.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.project.artist != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          widget.project.artist!,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),

                // Progress bar with buffer
                _ProgressBar(
                  state: state,
                  onSeek: widget.onSeek,
                ),

                const SizedBox(height: AppSpacing.lg),

                // Audio source selector
                if (availableSources.length > 1)
                  _AudioSourceSelector(
                    availableSources: availableSources,
                    currentSource: state.currentSource,
                    onSourceChanged: widget.onSwitchSource,
                  ),

                const SizedBox(height: AppSpacing.lg),

                // Controls
                _PlaybackControls(
                  isPlaying: state.isPlaying,
                  isBuffering: state.isBuffering,
                  onPlayPause: widget.onPlayPause,
                ),

                const SizedBox(height: AppSpacing.xl),

                // Lyrics display
                Expanded(
                  flex: 1,
                  child: lyrics.isEmpty
                      ? Center(
                          child: Text(
                            '暂无歌词',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                          itemCount: lyrics.length,
                          itemBuilder: (context, index) {
                            final line = lyrics[index];
                            final isCurrent = line == currentLine;
                            return GestureDetector(
                              onTap: () => widget.onLyricTap(line),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.sm,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  line.text,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: isCurrent
                                        ? AppColors.accent
                                        : AppColors.textSecondary,
                                    fontWeight:
                                        isCurrent ? FontWeight.w700 : FontWeight.normal,
                                    height: 1.5,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          },
                        ),
                ),

                const SizedBox(height: AppSpacing.lg),

                // Bottom action bar
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.bgElevated,
                    border: Border(
                      top: BorderSide(color: AppColors.borderSubtle),
                    ),
                  ),
                  child: SafeArea(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pushNamed(
                            context,
                            Routes.lyricEditorPath(widget.project.id),
                          ),
                          icon: const Icon(Icons.edit),
                          tooltip: '编辑歌词',
                        ),
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.tune),
                          tooltip: '调整偏移',
                        ),
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.share),
                          tooltip: '导出',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final PlaybackState state;
  final ValueChanged<Duration> onSeek;

  const _ProgressBar({
    required this.state,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    final duration = state.duration;
    final max = duration?.inMilliseconds.toDouble() ?? 1.0;
    final value = state.position.inMilliseconds.toDouble().clamp(0.0, max);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        children: [
          // Custom progress bar with buffer
          SizedBox(
            height: 20,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Background
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.bgHighlight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Buffered
                if (duration != null)
                  FractionallySizedBox(
                    widthFactor: state.bufferedPercent.clamp(0.0, 1.0),
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textTertiary.withAlpha(77),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                // Progress
                FractionallySizedBox(
                  widthFactor: state.progressPercent.clamp(0.0, 1.0),
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Slider (invisible but interactive)
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 0,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                      elevation: 0,
                    ),
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    value: value,
                    min: 0,
                    max: max,
                    onChanged: duration != null
                        ? (v) => onSeek(Duration(milliseconds: v.toInt()))
                        : null,
                    activeColor: Colors.transparent,
                    inactiveColor: Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // Time labels
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
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
          ),
        ],
      ),
    );
  }
}

class _AudioSourceSelector extends StatelessWidget {
  final List<AudioSourceType> availableSources;
  final AudioSourceType? currentSource;
  final ValueChanged<AudioSourceType> onSourceChanged;

  const _AudioSourceSelector({
    required this.availableSources,
    required this.currentSource,
    required this.onSourceChanged,
  });

  String _getSourceLabel(AudioSourceType source) {
    return switch (source) {
      AudioSourceType.original => '原声',
      AudioSourceType.instrumental => '伴奏',
      AudioSourceType.vocals => '人声',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: availableSources.map((source) {
          final isSelected = source == currentSource;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: TextButton(
              onPressed: () => onSourceChanged(source),
              style: TextButton.styleFrom(
                backgroundColor: isSelected
                    ? AppColors.accent.withAlpha(51)
                    : AppColors.bgElevated,
                foregroundColor: isSelected
                    ? AppColors.accent
                    : AppColors.textSecondary,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                ),
              ),
              child: Text(_getSourceLabel(source)),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  final bool isPlaying;
  final bool isBuffering;
  final VoidCallback onPlayPause;

  const _PlaybackControls({
    required this.isPlaying,
    required this.isBuffering,
    required this.onPlayPause,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.skip_previous),
          iconSize: 36,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: AppSpacing.xl),
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: AppColors.accent,
            shape: BoxShape.circle,
          ),
          child: isBuffering
              ? const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: AppColors.pureWhite,
                      strokeWidth: 2,
                    ),
                  ),
                )
              : IconButton(
                  onPressed: onPlayPause,
                  icon: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                  ),
                  iconSize: 32,
                  color: AppColors.pureWhite,
                ),
        ),
        const SizedBox(width: AppSpacing.xl),
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.skip_next),
          iconSize: 36,
          color: AppColors.textSecondary,
        ),
      ],
    );
  }
}
