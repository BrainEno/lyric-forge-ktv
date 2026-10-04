import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../player/domain/models/play_history.dart';
import '../../../player/domain/models/playback_state.dart';
import '../../../player/domain/repositories/play_history_repository.dart';
import '../../../player/domain/services/audio_player_service.dart';
import '../../../player/domain/services/playback_session_service.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../../transcription/domain/models/transcription_queue_models.dart';
import '../../../transcription/domain/services/batch_transcription_queue.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final ProjectRepository _projectRepository;
  late final PlayHistoryRepository _playHistoryRepository;
  late final PlaybackSessionService _playbackSession;
  late final AudioPlayerService _audioPlayer;
  late final BatchTranscriptionQueue _transcriptionQueue;
  late Future<List<ProjectManifest>> _projectsFuture;
  late Future<List<PlayHistory>> _playHistoryFuture;

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  void initState() {
    super.initState();
    final services = ServiceLocatorGlobal.I;
    _projectRepository = services.projectRepository;
    _playHistoryRepository = services.playHistoryRepository;
    _playbackSession = services.playbackSessionService;
    _audioPlayer = services.audioPlayerService;
    _transcriptionQueue = services.transcriptionQueue;
    _loadData();
  }

  void _loadData() {
    _projectsFuture = _projectRepository.getRecentProjects(limit: 8);
    _playHistoryFuture = _playHistoryRepository.getRecentPlayHistory(limit: 10);
  }

  Future<void> _refreshData() async {
    setState(_loadData);
  }

  Future<void> _openLocalPlayer([PlayHistory? history]) async {
    await Navigator.pushNamed(
      context,
      Routes.quickPlay,
      arguments: history,
    );
    if (mounted) _refreshData();
  }

  void _openCurrentPlayer(PlaybackItem item) {
    final projectId = item.projectId;
    if (projectId != null) {
      Navigator.pushNamed(context, Routes.playerPath(projectId));
    } else {
      Navigator.pushNamed(context, Routes.quickPlay);
    }
  }

  Future<void> _playQueueItem(PlaybackItem item) async {
    await _playbackSession.playItem(item);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: StreamBuilder<PlaybackSessionState>(
          stream: _playbackSession.stateStream,
          initialData: _playbackSession.currentState,
          builder: (context, sessionSnapshot) {
            final session = sessionSnapshot.data ??
                const PlaybackSessionState();
            return StreamBuilder<PlaybackState>(
              stream: _audioPlayer.stateStream,
              initialData: _audioPlayer.currentState,
              builder: (context, playbackSnapshot) {
                final playback = playbackSnapshot.data ??
                    const PlaybackState.idle();
                return StreamBuilder<TranscriptionQueueSnapshot>(
                  stream: _transcriptionQueue.snapshots,
                  initialData: _transcriptionQueue.current,
                  builder: (context, queueSnapshot) {
                    final queue = queueSnapshot.data ??
                        const TranscriptionQueueSnapshot(
                          items: [],
                          isPaused: false,
                          isProcessing: false,
                        );
                    return RefreshIndicator(
                      onRefresh: _refreshData,
                      color: AppColors.accent,
                      backgroundColor: AppColors.bgElevated,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1360),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.lg,
                                AppSpacing.md,
                                AppSpacing.lg,
                                AppSpacing.xxxl,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _DashboardHeader(
                                    isDesktop: _isDesktop,
                                    onOpenMusic: _openLocalPlayer,
                                    onNewProject: () => Navigator.pushNamed(
                                      context,
                                      Routes.import,
                                    ),
                                    onRemote: () => Navigator.pushNamed(
                                      context,
                                      _isDesktop
                                          ? Routes.mediaSharing
                                          : Routes.remoteLibrary,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xl),
                                  _NowPlayingArea(
                                    session: session,
                                    playback: playback,
                                    onOpenMusic: _openLocalPlayer,
                                    onOpenCurrent: _openCurrentPlayer,
                                    onPlayPause:
                                        _playbackSession.togglePlayPause,
                                    onPrevious:
                                        _playbackSession.skipPrevious,
                                    onNext: _playbackSession.skipNext,
                                    onPlayQueueItem: _playQueueItem,
                                  ),
                                  if (queue.items.isNotEmpty) ...[
                                    const SizedBox(height: AppSpacing.lg),
                                    _BackgroundWorkCard(
                                      snapshot: queue,
                                      onOpen: () => Navigator.pushNamed(
                                        context,
                                        Routes.import,
                                      ),
                                      onPauseResume: queue.isPaused
                                          ? _transcriptionQueue.resume
                                          : _transcriptionQueue.pause,
                                    ),
                                  ],
                                  const SizedBox(height: AppSpacing.xxxl),
                                  _SectionHeader(
                                    title: '最近播放',
                                    subtitle: '继续你最近听过的本地音乐',
                                    actionLabel: '打开音乐',
                                    onAction: _openLocalPlayer,
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  FutureBuilder<List<PlayHistory>>(
                                    future: _playHistoryFuture,
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return const _SectionLoading(
                                          height: 190,
                                        );
                                      }
                                      final histories = snapshot.data ?? [];
                                      if (histories.isEmpty) {
                                        return _EmptyMediaCard(
                                          icon: Icons.headphones_rounded,
                                          title: '还没有播放记录',
                                          message: '打开一首本地音乐后，会从这里快速继续。',
                                          actionLabel: '选择音乐',
                                          onAction: _openLocalPlayer,
                                        );
                                      }
                                      return _RecentListeningShelf(
                                        histories: histories,
                                        onPlay: _openLocalPlayer,
                                      );
                                    },
                                  ),
                                  const SizedBox(height: AppSpacing.xxxl),
                                  _SectionHeader(
                                    title: '最近工程',
                                    subtitle: '继续识别、校对，或打开已经准备好的 KTV 工程',
                                    actionLabel: '批量导入',
                                    onAction: () => Navigator.pushNamed(
                                      context,
                                      Routes.import,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  FutureBuilder<List<ProjectManifest>>(
                                    future: _projectsFuture,
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return const _SectionLoading(
                                          height: 260,
                                        );
                                      }
                                      if (snapshot.hasError) {
                                        return _LoadError(
                                          onRetry: _refreshData,
                                        );
                                      }
                                      final projects = snapshot.data ?? [];
                                      if (projects.isEmpty) {
                                        return _EmptyMediaCard(
                                          icon: Icons.auto_awesome_rounded,
                                          title: '还没有歌词工程',
                                          message:
                                              '导入歌曲后，LyricForge 会在后台逐首识别并保存工程。',
                                          actionLabel: '导入歌曲',
                                          onAction: () => Navigator.pushNamed(
                                            context,
                                            Routes.import,
                                          ),
                                        );
                                      }
                                      return _ProjectShelf(
                                        projects: projects,
                                        onOpen: (project) =>
                                            Navigator.pushNamed(
                                          context,
                                          Routes.projectDetailPath(project.id),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  final bool isDesktop;
  final VoidCallback onOpenMusic;
  final VoidCallback onNewProject;
  final VoidCallback onRemote;

  const _DashboardHeader({
    required this.isDesktop,
    required this.onOpenMusic,
    required this.onNewProject,
    required this.onRemote,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'LyricForge',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              '你的本地音乐、歌词与 KTV 工作台',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        );
        final actions = Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: onOpenMusic,
              icon: const Icon(Icons.library_music_rounded, size: 18),
              label: const Text('打开音乐'),
            ),
            if (isDesktop)
              IconButton.filledTonal(
                tooltip: '远程音乐库',
                onPressed: onRemote,
                icon: const Icon(Icons.cast_connected_rounded),
              ),
            FilledButton.icon(
              onPressed: onNewProject,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('导入并识别'),
            ),
          ],
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: AppSpacing.md),
              actions,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: title),
            actions,
          ],
        );
      },
    );
  }
}

class _NowPlayingArea extends StatelessWidget {
  final PlaybackSessionState session;
  final PlaybackState playback;
  final VoidCallback onOpenMusic;
  final ValueChanged<PlaybackItem> onOpenCurrent;
  final Future<void> Function() onPlayPause;
  final Future<void> Function() onPrevious;
  final Future<void> Function() onNext;
  final Future<void> Function(PlaybackItem) onPlayQueueItem;

  const _NowPlayingArea({
    required this.session,
    required this.playback,
    required this.onOpenMusic,
    required this.onOpenCurrent,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.onPlayQueueItem,
  });

  @override
  Widget build(BuildContext context) {
    final current = session.currentItem;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final hero = current == null
            ? _IdleHero(onOpenMusic: onOpenMusic)
            : _NowPlayingHero(
                item: current,
                playback: playback,
                session: session,
                onOpen: () => onOpenCurrent(current),
                onPlayPause: onPlayPause,
                onPrevious: onPrevious,
                onNext: onNext,
              );
        final queue = _PlaybackQueueCard(
          session: session,
          onPlayItem: onPlayQueueItem,
        );
        if (!wide) {
          return Column(
            children: [
              hero,
              const SizedBox(height: AppSpacing.md),
              queue,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 2, child: hero),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: queue),
          ],
        );
      },
    );
  }
}

class _IdleHero extends StatelessWidget {
  final VoidCallback onOpenMusic;

  const _IdleHero({required this.onOpenMusic});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 250),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: AppColors.playerGradient,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Eyebrow(label: 'LOCAL FIRST'),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '把你的音乐库变成\n可以继续制作的 KTV 工程',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '先正常听歌，需要歌词时再交给后台批量识别。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: onOpenMusic,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('选择音乐开始播放'),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              color: AppColors.bgSurface.withAlpha(190),
              borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
            ),
            child: const Icon(
              Icons.album_rounded,
              size: 74,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _NowPlayingHero extends StatelessWidget {
  final PlaybackItem item;
  final PlaybackState playback;
  final PlaybackSessionState session;
  final VoidCallback onOpen;
  final Future<void> Function() onPlayPause;
  final Future<void> Function() onPrevious;
  final Future<void> Function() onNext;

  const _NowPlayingHero({
    required this.item,
    required this.playback,
    required this.session,
    required this.onOpen,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 250),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppColors.playerGradient,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final artwork = _Artwork(
            path: item.artworkPath,
            size: compact ? 104 : 172,
          );
          final details = Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Eyebrow(label: '正在播放'),
              const SizedBox(height: AppSpacing.sm),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                item.artist?.trim().isNotEmpty == true
                    ? item.artist!
                    : item.projectId != null
                        ? 'LyricForge 工程'
                        : '本地音乐',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: AppSpacing.md),
              _HeroProgress(playback: playback),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton.filledTonal(
                    tooltip: '上一首 / 回到开头',
                    onPressed: onPrevious,
                    icon: const Icon(Icons.skip_previous_rounded),
                  ),
                  IconButton.filled(
                    tooltip: playback.isPlaying ? '暂停' : '播放',
                    onPressed: playback.isBuffering ? null : onPlayPause,
                    icon: playback.isBuffering
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            playback.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                  ),
                  IconButton.filledTonal(
                    tooltip: '下一首',
                    onPressed: session.canSkipNext ? onNext : null,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                  OutlinedButton.icon(
                    onPressed: onOpen,
                    icon: Icon(
                      item.projectId == null
                          ? Icons.open_in_new_rounded
                          : Icons.lyrics_rounded,
                      size: 17,
                    ),
                    label: Text(
                      item.projectId == null ? '打开播放器' : '打开歌词播放器',
                    ),
                  ),
                ],
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                artwork,
                const SizedBox(height: AppSpacing.md),
                details,
              ],
            );
          }
          return Row(
            children: [
              artwork,
              const SizedBox(width: AppSpacing.lg),
              Expanded(child: details),
            ],
          );
        },
      ),
    );
  }
}

class _HeroProgress extends StatelessWidget {
  final PlaybackState playback;

  const _HeroProgress({required this.playback});

  @override
  Widget build(BuildContext context) {
    final progress = playback.progressPercent.clamp(0.0, 1.0).toDouble();
    return Column(
      children: [
        LinearProgressIndicator(
          value: progress,
          minHeight: 4,
          backgroundColor: AppColors.bgHighlight,
          borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Text(
              playback.formattedPosition,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
            const Spacer(),
            Text(
              playback.formattedDuration,
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

class _PlaybackQueueCard extends StatelessWidget {
  final PlaybackSessionState session;
  final Future<void> Function(PlaybackItem) onPlayItem;

  const _PlaybackQueueCard({
    required this.session,
    required this.onPlayItem,
  });

  @override
  Widget build(BuildContext context) {
    final currentIndex = session.currentIndex;
    final start = currentIndex < 0 ? 0 : currentIndex;
    final end = (start + 5).clamp(0, session.queue.length).toInt();
    final items = start < end ? session.queue.sublist(start, end) : <PlaybackItem>[];

    return Container(
      constraints: const BoxConstraints(minHeight: 250),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '播放队列',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const Spacer(),
              Text(
                '${session.queue.length} 首',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (items.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  '播放音乐后，这里会显示当前队列',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
              ),
            )
          else
            for (var localIndex = 0;
                localIndex < items.length;
                localIndex++)
              _QueueRow(
                item: items[localIndex],
                isCurrent: start + localIndex == currentIndex,
                onTap: () => onPlayItem(items[localIndex]),
              ),
          if (session.queue.length > items.length && items.isNotEmpty) ...[
            const Spacer(),
            Text(
              '还有 ${session.queue.length - end} 首未显示',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final PlaybackItem item;
  final bool isCurrent;
  final VoidCallback onTap;

  const _QueueRow({
    required this.item,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isCurrent ? AppColors.accent.withAlpha(16) : Colors.transparent,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              _Artwork(path: item.artworkPath, size: 38),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight:
                                isCurrent ? FontWeight.w700 : FontWeight.w500,
                            color: isCurrent
                                ? AppColors.accent
                                : AppColors.textPrimary,
                          ),
                    ),
                    Text(
                      item.artist?.trim().isNotEmpty == true
                          ? item.artist!
                          : item.projectId == null
                              ? '本地音乐'
                              : '歌词工程',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                isCurrent
                    ? Icons.graphic_eq_rounded
                    : Icons.play_arrow_rounded,
                size: 18,
                color: isCurrent
                    ? AppColors.accent
                    : AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackgroundWorkCard extends StatelessWidget {
  final TranscriptionQueueSnapshot snapshot;
  final VoidCallback onOpen;
  final Future<void> Function() onPauseResume;

  const _BackgroundWorkCard({
    required this.snapshot,
    required this.onOpen,
    required this.onPauseResume,
  });

  @override
  Widget build(BuildContext context) {
    final running = snapshot.items
        .where((item) => item.status == TranscriptionQueueItemStatus.running)
        .toList();
    final active = snapshot.items
        .where((item) =>
            item.status == TranscriptionQueueItemStatus.running ||
            item.status == TranscriptionQueueItemStatus.queued ||
            item.status == TranscriptionQueueItemStatus.paused)
        .length;
    final current = running.isEmpty ? null : running.first;
    final progress = snapshot.items.isEmpty
        ? 0.0
        : snapshot.items
                .map((item) =>
                    item.status == TranscriptionQueueItemStatus.completed
                        ? 1.0
                        : item.progress.clamp(0.0, 1.0).toDouble())
                .fold<double>(0, (sum, value) => sum + value) /
            snapshot.items.length;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final info = Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: (snapshot.failedCount > 0
                          ? AppColors.warning
                          : AppColors.accent)
                      .withAlpha(20),
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusMedium),
                ),
                child: Icon(
                  snapshot.isPaused
                      ? Icons.pause_rounded
                      : Icons.auto_awesome_motion_rounded,
                  color: snapshot.failedCount > 0
                      ? AppColors.warning
                      : AppColors.accent,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      snapshot.isPaused
                          ? '后台歌词任务已暂停'
                          : current != null
                              ? '正在识别 · ${current.projectName}'
                              : active > 0
                                  ? '后台歌词任务'
                                  : '歌词任务已处理完毕',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '完成 ${snapshot.completedCount} · 等待 ${snapshot.queuedCount} · 失败 ${snapshot.failedCount}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor: AppColors.bgHighlight,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusCircular),
                    ),
                  ],
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (active > 0)
                TextButton.icon(
                  onPressed: onPauseResume,
                  icon: Icon(
                    snapshot.isPaused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    size: 17,
                  ),
                  label: Text(snapshot.isPaused ? '继续' : '暂停'),
                ),
              OutlinedButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                label: const Text('查看队列'),
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: AppSpacing.sm),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: AppSpacing.md),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
              ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

class _RecentListeningShelf extends StatelessWidget {
  final List<PlayHistory> histories;
  final ValueChanged<PlayHistory> onPlay;

  const _RecentListeningShelf({
    required this.histories,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: histories.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (context, index) => _ListeningCard(
          history: histories[index],
          onTap: () => onPlay(histories[index]),
        ),
      ),
    );
  }
}

class _ListeningCard extends StatelessWidget {
  final PlayHistory history;
  final VoidCallback onTap;

  const _ListeningCard({required this.history, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Material(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
          hoverColor: AppColors.hoverOverlay,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: AppColors.cardGradient,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMedium),
                    ),
                    child: const Icon(
                      Icons.music_note_rounded,
                      size: 42,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  history.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  history.artist?.trim().isNotEmpty == true
                      ? history.artist!
                      : history.formattedPlayedAt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectShelf extends StatelessWidget {
  final List<ProjectManifest> projects;
  final ValueChanged<ProjectManifest> onOpen;

  const _ProjectShelf({
    required this.projects,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1160
            ? 4
            : constraints.maxWidth >= 820
                ? 3
                : constraints.maxWidth >= 540
                    ? 2
                    : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: projects.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            childAspectRatio: columns == 1 ? 2.5 : 1.35,
          ),
          itemBuilder: (context, index) => _ProjectCard(
            project: projects[index],
            onTap: () => onOpen(projects[index]),
          ),
        );
      },
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final ProjectManifest project;
  final VoidCallback onTap;

  const _ProjectCard({required this.project, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final lyricCount = project.lyricDocument?.lines.length ?? 0;
    return Material(
      color: AppColors.bgElevated,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.hoverOverlay,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Artwork(
                    path: project.audioAsset?.thumbnailPath,
                    size: 64,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          project.artist?.trim().isNotEmpty == true
                              ? project.artist!
                              : '歌词工程',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textTertiary,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  _ProjectStatusDot(status: project.status),
                ],
              ),
              const Spacer(),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  _MetaChip(
                    icon: project.hasLyrics
                        ? Icons.lyrics_rounded
                        : Icons.graphic_eq_rounded,
                    label: project.hasLyrics ? '$lyricCount 行歌词' : '待生成歌词',
                    accent: project.hasLyrics,
                  ),
                  _MetaChip(
                    icon: Icons.schedule_rounded,
                    label: _projectStageLabel(project.currentStage),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              LinearProgressIndicator(
                value: project.progressPercent.clamp(0.0, 1.0).toDouble(),
                minHeight: 3,
                backgroundColor: AppColors.bgHighlight,
                borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  final String? path;
  final double size;

  const _Artwork({this.path, required this.size});

  @override
  Widget build(BuildContext context) {
    File? file;
    if (!kIsWeb && path?.trim().isNotEmpty == true) {
      file = File(path!);
    }
    final hasFile = file != null && file.existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      child: SizedBox(
        width: size,
        height: size,
        child: hasFile
            ? Image.file(file!, fit: BoxFit.cover)
            : Container(
                decoration: const BoxDecoration(gradient: AppColors.cardGradient),
                child: Icon(
                  Icons.album_rounded,
                  size: size * 0.42,
                  color: AppColors.textTertiary,
                ),
              ),
      ),
    );
  }
}

class _ProjectStatusDot extends StatelessWidget {
  final ProjectStatus status;

  const _ProjectStatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ProjectStatus.ready => AppColors.accent,
      ProjectStatus.error => AppColors.error,
      ProjectStatus.transcribing || ProjectStatus.processing => AppColors.info,
      ProjectStatus.editing => AppColors.warning,
      _ => AppColors.textTertiary,
    };
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool accent;

  const _MetaChip({
    required this.icon,
    required this.label,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: accent ? AppColors.accent.withAlpha(16) : AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: accent ? AppColors.accent : AppColors.textTertiary,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: accent
                      ? AppColors.accent
                      : AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  final String label;

  const _Eyebrow({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.accent,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
    );
  }
}

class _EmptyMediaCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _EmptyMediaCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: Row(
        children: [
          Icon(icon, size: 42, color: AppColors.textTertiary),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  final VoidCallback onRetry;

  const _LoadError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return _EmptyMediaCard(
      icon: Icons.error_outline_rounded,
      title: '最近工程加载失败',
      message: '工程文件暂时无法读取，可以重新加载一次。',
      actionLabel: '重试',
      onAction: onRetry,
    );
  }
}

class _SectionLoading extends StatelessWidget {
  final double height;

  const _SectionLoading({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

String _projectStageLabel(ProcessingStage stage) {
  return switch (stage) {
    ProcessingStage.none => '待开始',
    ProcessingStage.audioImported => '已导入',
    ProcessingStage.audioNormalized => '音频处理',
    ProcessingStage.vocalsSeparated => '人声已分离',
    ProcessingStage.transcriptionComplete => '歌词已识别',
    ProcessingStage.lyricsEdited => '歌词已校对',
    ProcessingStage.exported => '已导出',
  };
}
