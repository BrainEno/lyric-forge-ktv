import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';

/// Player screen - KTV playback with synced lyrics display.
/// Desktop-first: placeholder audio playback with real lyrics sync.
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
  late Future<ProjectManifest?> _projectFuture;
  Timer? _positionTimer;
  Duration _currentPosition = Duration.zero;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _repository = ServiceLocatorGlobal.I.projectRepository;
    _loadProject();
  }

  void _loadProject() {
    _projectFuture = _repository.getProjectById(widget.projectId);
  }

  void _playPause() {
    setState(() {
      _isPlaying = !_isPlaying;
      if (_isPlaying) {
        _positionTimer = Timer.periodic(
          const Duration(milliseconds: 100),
          (_) {
            setState(() {
              _currentPosition += const Duration(milliseconds: 100);
              // Loop at 5 minutes for placeholder
              if (_currentPosition.inMinutes >= 5) {
                _currentPosition = Duration.zero;
              }
            });
          },
        );
      } else {
        _positionTimer?.cancel();
      }
    });
  }

  void _seek(Duration position) {
    setState(() {
      _currentPosition = position;
    });
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
          currentPosition: _currentPosition,
          isPlaying: _isPlaying,
          onPlayPause: _playPause,
          onSeek: _seek,
          onLyricTap: (line) => _seek(line.startTime),
        );
      },
    );
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
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

class _PlayerContent extends StatelessWidget {
  final ProjectManifest project;
  final Duration currentPosition;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<LyricLine> onLyricTap;

  const _PlayerContent({
    required this.project,
    required this.currentPosition,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onSeek,
    required this.onLyricTap,
  });

  LyricLine? _getCurrentLine(List<LyricLine> lines) {
    for (var i = lines.length - 1; i >= 0; i--) {
      if (currentPosition >= lines[i].startTime) {
        return lines[i];
      }
    }
    return lines.isNotEmpty ? lines.first : null;
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = project.lyricDocument?.lines ?? [];
    final currentLine = _getCurrentLine(lyrics);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Column(
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
                      child: const Center(
                        child: Icon(
                          Icons.album,
                          size: 80,
                          color: AppColors.textTertiary,
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
                    project.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (project.artist != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      project.artist!,
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

            // Progress bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                children: [
                  Slider(
                    value: currentPosition.inMilliseconds.toDouble(),
                    min: 0,
                    max: 300000, // 5 minutes placeholder
                    onChanged: (value) {
                      onSeek(Duration(milliseconds: value.toInt()));
                    },
                    activeColor: AppColors.accent,
                    inactiveColor: AppColors.bgHighlight,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(currentPosition),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        Text(
                          _formatDuration(const Duration(minutes: 5)),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // Controls
            Row(
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
                  child: IconButton(
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
                          onTap: () => onLyricTap(line),
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
                        Routes.lyricEditorPath(project.id),
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
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
