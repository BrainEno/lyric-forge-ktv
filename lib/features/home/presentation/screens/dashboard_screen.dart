import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../features/player/domain/models/play_history.dart';
import '../../../../features/player/domain/repositories/play_history_repository.dart';
import '../../../../features/project/domain/models/project_manifest.dart';
import '../../../../features/project/domain/repositories/project_repository.dart';

/// Desktop home for LyricForge.
///
/// The information architecture deliberately starts as a local music player:
/// open a song, resume recent listening, or continue a lyric project. Project
/// creation stays prominent without making ordinary playback feel like a
/// special or temporary mode.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final ProjectRepository _projectRepository;
  late final PlayHistoryRepository _playHistoryRepository;
  late Future<List<ProjectManifest>> _projectsFuture;
  late Future<List<PlayHistory>> _playHistoryFuture;

  @override
  void initState() {
    super.initState();
    _projectRepository = ServiceLocatorGlobal.I.projectRepository;
    _playHistoryRepository = ServiceLocatorGlobal.I.playHistoryRepository;
    _loadData();
  }

  void _loadData() {
    _projectsFuture = _projectRepository.getRecentProjects(limit: 8);
    _playHistoryFuture =
        _playHistoryRepository.getRecentPlayHistory(limit: 8);
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
    if (mounted) {
      _refreshData();
    }
  }

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshData,
          color: AppColors.accent,
          backgroundColor: AppColors.bgElevated,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.xxxl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HomeHeader(
                        isDesktop: _isDesktop,
                        onOpenMusic: _openLocalPlayer,
                        onOpenRemote: () => Navigator.pushNamed(
                          context,
                          _isDesktop
                              ? Routes.mediaSharing
                              : Routes.remoteLibrary,
                        ),
                        onNewProject: () =>
                            Navigator.pushNamed(context, Routes.import),
                      ),
                      const SizedBox(height: AppSpacing.xxxl),
                      _SectionHeading(
                        title: '最近播放',
                        subtitle: '像歌单一样继续播放本地音乐',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FutureBuilder<List<PlayHistory>>(
                        future: _playHistoryFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const _SectionLoading(height: 132);
                          }

                          final histories = snapshot.data ?? [];
                          if (histories.isEmpty) {
                            return _EmptyListeningState(
                              onOpenMusic: _openLocalPlayer,
                            );
                          }

                          return _RecentPlaylist(
                            histories: histories,
                            onPlay: _openLocalPlayer,
                          );
                        },
                      ),
                      const SizedBox(height: AppSpacing.xxxl),
                      const _SectionHeading(
                        title: '最近项目',
                        subtitle: '继续歌词识别、校对，或进入播放器与 KTV',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FutureBuilder<List<ProjectManifest>>(
                        future: _projectsFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const _SectionLoading(height: 220);
                          }

                          if (snapshot.hasError) {
                            return _LoadError(onRetry: _refreshData);
                          }

                          final projects = snapshot.data ?? [];
                          if (projects.isEmpty) {
                            return _EmptyProjectsState(
                              onNewProject: () =>
                                  Navigator.pushNamed(context, Routes.import),
                            );
                          }

                          return _ProjectGrid(
                            projects: projects,
                            onOpen: (project) => Navigator.pushNamed(
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
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  final bool isDesktop;
  final VoidCallback onOpenMusic;
  final VoidCallback onOpenRemote;
  final VoidCallback onNewProject;

  const _HomeHeader({
    required this.isDesktop,
    required this.onOpenMusic,
    required this.onOpenRemote,
    required this.onNewProject,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final identity = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'LyricForge',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '本地音乐播放器 · 歌词识别 · KTV',
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
              icon: const Icon(Icons.folder_open_rounded, size: 19),
              label: const Text('打开音乐'),
            ),
            if (isDesktop)
              IconButton(
                tooltip: '远程音乐库',
                onPressed: onOpenRemote,
                icon: const Icon(Icons.cast_connected_rounded),
              ),
            FilledButton.icon(
              onPressed: onNewProject,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('新建工程'),
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              identity,
              const SizedBox(height: AppSpacing.lg),
              actions,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: identity),
            actions,
          ],
        );
      },
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeading({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
              ),
        ),
      ],
    );
  }
}

class _RecentPlaylist extends StatelessWidget {
  final List<PlayHistory> histories;
  final ValueChanged<PlayHistory> onPlay;

  const _RecentPlaylist({
    required this.histories,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(color: AppColors.borderMuted),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const _PlaylistHeader(),
          for (var index = 0; index < histories.length; index++) ...[
            if (index > 0)
              const Divider(
                height: 1,
                indent: 76,
                endIndent: AppSpacing.md,
                color: AppColors.borderMuted,
              ),
            _RecentTrackRow(
              index: index + 1,
              history: histories[index],
              onTap: () => onPlay(histories[index]),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlaylistHeader extends StatelessWidget {
  const _PlaylistHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 44,
            child: Text(
              '#',
              style: TextStyle(color: AppColors.textTertiary),
            ),
          ),
          Expanded(
            child: Text(
              '歌曲',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
          ),
          SizedBox(
            width: 112,
            child: Text(
              '最近播放',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
          ),
          const SizedBox(width: 52),
        ],
      ),
    );
  }
}

class _RecentTrackRow extends StatelessWidget {
  final int index;
  final PlayHistory history;
  final VoidCallback onTap;

  const _RecentTrackRow({
    required this.index,
    required this.history,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.hoverOverlay,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  index.toString(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
              ),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppColors.cardGradient,
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusSmall),
                ),
                child: const Icon(
                  Icons.music_note_rounded,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      history.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      history.artist?.trim().isNotEmpty == true
                          ? history.artist!
                          : '本地音频',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 112,
                child: Text(
                  history.formattedPlayedAt,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
              ),
              Tooltip(
                message: '播放',
                child: IconButton(
                  onPressed: onTap,
                  icon: const Icon(Icons.play_arrow_rounded),
                  color: AppColors.pureBlack,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    minimumSize: const Size(36, 36),
                    maximumSize: const Size(36, 36),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectGrid extends StatelessWidget {
  final List<ProjectManifest> projects;
  final ValueChanged<ProjectManifest> onOpen;

  const _ProjectGrid({
    required this.projects,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1120
            ? 4
            : constraints.maxWidth >= 760
                ? 3
                : constraints.maxWidth >= 520
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
            childAspectRatio: 1.55,
          ),
          itemBuilder: (context, index) {
            final project = projects[index];
            return _ProjectTile(
              project: project,
              onTap: () => onOpen(project),
            );
          },
        );
      },
    );
  }
}

class _ProjectTile extends StatelessWidget {
  final ProjectManifest project;
  final VoidCallback onTap;

  const _ProjectTile({
    required this.project,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgElevated,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        hoverColor: AppColors.hoverOverlay,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: AppColors.cardGradient,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMedium),
                    ),
                    child: const Icon(
                      Icons.album_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    project.hasLyrics
                        ? Icons.lyrics_rounded
                        : Icons.graphic_eq_rounded,
                    size: 20,
                    color: project.hasLyrics
                        ? AppColors.accent
                        : AppColors.textTertiary,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                project.artist?.trim().isNotEmpty == true
                    ? project.artist!
                    : project.hasLyrics
                        ? '歌词已就绪'
                        : '歌词工程',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
              ),
            ],
          ),
        ),
      ),
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
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      alignment: Alignment.center,
      child: const CircularProgressIndicator(),
    );
  }
}

class _LoadError extends StatelessWidget {
  final VoidCallback onRetry;

  const _LoadError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: AppSpacing.md),
          const Expanded(child: Text('最近项目加载失败')),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _EmptyListeningState extends StatelessWidget {
  final VoidCallback onOpenMusic;

  const _EmptyListeningState({required this.onOpenMusic});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.queue_music_rounded,
            size: 34,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '还没有播放记录',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '打开一首本地音乐，它会出现在这里。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: onOpenMusic,
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('打开音乐'),
          ),
        ],
      ),
    );
  }
}

class _EmptyProjectsState extends StatelessWidget {
  final VoidCallback onNewProject;

  const _EmptyProjectsState({required this.onNewProject});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lyrics_outlined,
            size: 38,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '还没有歌词工程',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '从一首音频开始识别歌词，完成后即可进入 KTV。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onNewProject,
            icon: const Icon(Icons.add_rounded),
            label: const Text('新建工程'),
          ),
        ],
      ),
    );
  }
}
