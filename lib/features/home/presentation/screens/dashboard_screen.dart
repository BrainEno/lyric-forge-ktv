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
  late final ProjectRepository _projects;
  late final PlayHistoryRepository _history;
  late final PlaybackSessionService _playbackSession;
  late final AudioPlayerService _audioPlayer;
  late final BatchTranscriptionQueue _transcriptionQueue;
  late Future<List<ProjectManifest>> _projectsFuture;
  late Future<List<PlayHistory>> _historyFuture;

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  void initState() {
    super.initState();
    final services = ServiceLocatorGlobal.I;
    _projects = services.projectRepository;
    _history = services.playHistoryRepository;
    _playbackSession = services.playbackSessionService;
    _audioPlayer = services.audioPlayerService;
    _transcriptionQueue = services.transcriptionQueue;
    _loadData();
  }

  void _loadData() {
    _projectsFuture = _projects.getRecentProjects(limit: 8);
    _historyFuture = _history.getRecentPlayHistory(limit: 10);
  }

  Future<void> _refresh() async => setState(_loadData);

  Future<void> _openLocalPlayer([PlayHistory? history]) async {
    await Navigator.pushNamed(context, Routes.quickPlay, arguments: history);
    if (mounted) _refresh();
  }

  void _openCurrent(PlaybackItem item) {
    final projectId = item.projectId;
    Navigator.pushNamed(
      context,
      projectId == null ? Routes.quickPlay : Routes.playerPath(projectId),
    );
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
            final session =
                sessionSnapshot.data ?? const PlaybackSessionState();
            return StreamBuilder<PlaybackState>(
              stream: _audioPlayer.stateStream,
              initialData: _audioPlayer.currentState,
              builder: (context, playbackSnapshot) {
                final playback =
                    playbackSnapshot.data ?? const PlaybackState.idle();
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
                      onRefresh: _refresh,
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
                                  _Header(
                                    isDesktop: _isDesktop,
                                    onOpenMusic: _openLocalPlayer,
                                    onImport: () => Navigator.pushNamed(
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
                                    onOpenCurrent: _openCurrent,
                                    onPlayPause:
                                        _playbackSession.togglePlayPause,
                                    onPrevious:
                                        _playbackSession.skipPrevious,
                                    onNext: _playbackSession.skipNext,
                                    onPlayQueueItem:
                                        _playbackSession.playItem,
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
                                    action: '打开音乐',
                                    onAction: _openLocalPlayer,
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  FutureBuilder<List<PlayHistory>>(
                                    future: _historyFuture,
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return const _LoadingBlock(height: 190);
                                      }
                                      final items = snapshot.data ?? [];
                                      if (items.isEmpty) {
                                        return _EmptyCard(
                                          icon: Icons.headphones_rounded,
                                          title: '还没有播放记录',
                                          message: '打开一首本地音乐后，会从这里快速继续。',
                                          action: '选择音乐',
                                          onAction: _openLocalPlayer,
                                        );
                                      }
                                      return _RecentShelf(
                                        histories: items,
                                        onPlay: _openLocalPlayer,
                                      );
                                    },
                                  ),
                                  const SizedBox(height: AppSpacing.xxxl),
                                  _SectionHeader(
                                    title: '最近工程',
                                    subtitle: '继续识别、校对，或打开已经准备好的 KTV 工程',
                                    action: '批量导入',
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
                                        return const _LoadingBlock(height: 260);
                                      }
                                      if (snapshot.hasError) {
                                        return _EmptyCard(
                                          icon: Icons.error_outline_rounded,
                                          title: '最近工程加载失败',
                                          message: '工程文件暂时无法读取，可以重新加载一次。',
                                          action: '重试',
                                          onAction: _refresh,
                                        );
                                      }
                                      final items = snapshot.data ?? [];
                                      if (items.isEmpty) {
                                        return _EmptyCard(
                                          icon: Icons.auto_awesome_rounded,
                                          title: '还没有歌词工程',
                                          message:
                                              '导入歌曲后，LyricForge 会在后台逐首识别并保存工程。',
                                          action: '导入歌曲',
                                          onAction: () => Navigator.pushNamed(
                                            context,
                                            Routes.import,
                                          ),
                                        );
                                      }
                                      return _ProjectGrid(
                                        projects: items,
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

class _Header extends StatelessWidget {
  final bool isDesktop;
  final VoidCallback onOpenMusic;
  final VoidCallback onImport;
  final VoidCallback onRemote;

  const _Header({
    required this.isDesktop,
    required this.onOpenMusic,
    required this.onImport,
    required this.onRemote,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final identity = Column(
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
              onPressed: onImport,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('导入并识别'),
            ),
          ],
        );
        return compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  identity,
                  const SizedBox(height: AppSpacing.md),
                  actions,
                ],
              )
            : Row(children: [Expanded(child: identity), actions]);
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
    final hero = current == null
        ? _IdleHero(onOpenMusic: onOpenMusic)
        : _PlayingHero(
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

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(
            children: [
              hero,
              const SizedBox(height: AppSpacing.md),
              queue,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
      decoration: _heroDecoration(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showArtwork = constraints.maxWidth >= 520;
          return Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Eyebrow('LOCAL FIRST'),
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
              if (showArtwork) ...[
                const SizedBox(width: AppSpacing.lg),
                const _Artwork(size: 150),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PlayingHero extends StatelessWidget {
  final PlaybackItem item;
  final PlaybackState playback;
  final PlaybackSessionState session;
  final VoidCallback onOpen;
  final Future<void> Function() onPlayPause;
  final Future<void> Function() onPrevious;
  final Future<void> Function() onNext;

  const _PlayingHero({
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
      decoration: _heroDecoration(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final detail = Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Eyebrow('正在播放'),
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
                    : item.projectId == null
                        ? '本地音乐'
                        : 'LyricForge 工程',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: AppSpacing.md),
              _HeroProgress(playback),
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
                _Artwork(path: item.artworkPath, size: 104),
                const SizedBox(height: AppSpacing.md),
                detail,
              ],
            );
          }
          return Row(
            children: [
              _Artwork(path: item.artworkPath, size: 172),
              const SizedBox(width: AppSpacing.lg),
              Expanded(child: detail),
            ],
          );
        },
      ),
    );
  }
}

class _HeroProgress extends StatelessWidget {
  final PlaybackState playback;
  const _HeroProgress(this.playback);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LinearProgressIndicator(
          value: playback.progressPercent.clamp(0.0, 1.0).toDouble(),
          minHeight: 4,
          backgroundColor: AppColors.bgHighlight,
          borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Text(playback.formattedPosition, style: _mutedLabel(context)),
            const Spacer(),
            Text(playback.formattedDuration, style: _mutedLabel(context)),
          ],
        ),
      ],
    );
  }
}

class _PlaybackQueueCard extends StatelessWidget {
  final PlaybackSessionState session;
  final Future<void> Function(PlaybackItem) onPlayItem;

  const _PlaybackQueueCard({required this.session, required this.onPlayItem});

  @override
  Widget build(BuildContext context) {
    final start = session.currentIndex < 0 ? 0 : session.currentIndex;
    final end = (start + 5).clamp(0, session.queue.length).toInt();
    final items = start < end
        ? session.queue.sublist(start, end)
        : const <PlaybackItem>[];

    return Container(
      constraints: const BoxConstraints(minHeight: 250),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: _cardDecoration(),
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
              Text('${session.queue.length} 首', style: _mutedLabel(context)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (items.isEmpty)
            SizedBox(
              height: 155,
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
            for (var i = 0; i < items.length; i++)
              _QueueRow(
                item: items[i],
                current: start + i == session.currentIndex,
                onTap: () => onPlayItem(items[i]),
              ),
          if (session.queue.length > end && items.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '还有 ${session.queue.length - end} 首未显示',
              style: _mutedLabel(context),
            ),
          ],
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final PlaybackItem item;
  final bool current;
  final VoidCallback onTap;

  const _QueueRow({
    required this.item,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: current ? AppColors.accent.withAlpha(16) : Colors.transparent,
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
                            color: current
                                ? AppColors.accent
                                : AppColors.textPrimary,
                            fontWeight:
                                current ? FontWeight.w700 : FontWeight.w500,
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
                      style: _mutedLabel(context),
                    ),
                  ],
                ),
              ),
              Icon(
                current ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
                size: 18,
                color: current ? AppColors.accent : AppColors.textTertiary,
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
    final running = snapshot.items.where(
      (item) => item.status == TranscriptionQueueItemStatus.running,
    );
    final active = snapshot.items.where(
      (item) =>
          item.status == TranscriptionQueueItemStatus.running ||
          item.status == TranscriptionQueueItemStatus.queued ||
          item.status == TranscriptionQueueItemStatus.paused,
    ).length;
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
      decoration: _cardDecoration(),
      child: LayoutBuilder(
        builder: (context, constraints) {
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
                      style: _mutedLabel(context),
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
          if (constraints.maxWidth < 680) {
            return Column(
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
  final String action;
  final VoidCallback onAction;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onAction,
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
        TextButton(onPressed: onAction, child: Text(action)),
      ],
    );
  }
}

class _RecentShelf extends StatelessWidget {
  final List<PlayHistory> histories;
  final ValueChanged<PlayHistory> onPlay;

  const _RecentShelf({required this.histories, required this.onPlay});

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
          hoverColor: AppColors.hoverOverlay,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
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
                  style: _mutedLabel(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectGrid extends StatelessWidget {
  final List<ProjectManifest> projects;
  final ValueChanged<ProjectManifest> onOpen;

  const _ProjectGrid({required this.projects, required this.onOpen});

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
                  _Artwork(path: project.audioAsset?.thumbnailPath, size: 64),
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
                          style: _mutedLabel(context),
                        ),
                      ],
                    ),
                  ),
                  _StatusDot(project.status),
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
                    label: _stageLabel(project.currentStage),
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
    if (!kIsWeb && path?.trim().isNotEmpty == true) file = File(path!);
    final exists = file != null && file.existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      child: SizedBox(
        width: size,
        height: size,
        child: exists
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

class _StatusDot extends StatelessWidget {
  final ProjectStatus status;
  const _StatusDot(this.status);

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
  const _MetaChip({required this.icon, required this.label, this.accent = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
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
                  color: accent ? AppColors.accent : AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  final String text;
  const _Eyebrow(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.accent,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String action;
  final VoidCallback onAction;

  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: _cardDecoration(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final info = Row(
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
            ],
          );
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(onPressed: onAction, child: Text(action)),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: AppSpacing.md),
              OutlinedButton(onPressed: onAction, child: Text(action)),
            ],
          );
        },
      ),
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  final double height;
  const _LoadingBlock({required this.height});

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

BoxDecoration _heroDecoration() => BoxDecoration(
      gradient: AppColors.playerGradient,
      borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
      border: Border.all(color: AppColors.borderMuted),
    );

BoxDecoration _cardDecoration() => BoxDecoration(
      color: AppColors.bgElevated,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      border: Border.all(color: AppColors.borderMuted),
    );

TextStyle? _mutedLabel(BuildContext context) =>
    Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.textTertiary,
        );

String _stageLabel(ProcessingStage stage) => switch (stage) {
      ProcessingStage.none => '待开始',
      ProcessingStage.audioImported => '已导入',
      ProcessingStage.audioNormalized => '音频处理',
      ProcessingStage.vocalsSeparated => '人声已分离',
      ProcessingStage.transcriptionComplete => '歌词已识别',
      ProcessingStage.lyricsEdited => '歌词已校对',
      ProcessingStage.exported => '已导出',
    };
