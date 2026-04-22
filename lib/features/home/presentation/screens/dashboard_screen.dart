import 'package:flutter/material.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../features/player/domain/models/play_history.dart';
import '../../../../features/player/domain/repositories/play_history_repository.dart';
import '../../../../features/project/domain/models/project_manifest.dart';
import '../../../../features/project/domain/repositories/project_repository.dart';

/// Dashboard screen - entry point for the local KTV production tool.
/// Displays recent projects and provides entry to create new projects.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final ProjectRepository _repository;
  late final PlayHistoryRepository _playHistoryRepository;
  late Future<List<ProjectManifest>> _projectsFuture;
  late Future<List<PlayHistory>> _playHistoryFuture;

  @override
  void initState() {
    super.initState();
    _repository = ServiceLocatorGlobal.I.projectRepository;
    _playHistoryRepository = ServiceLocatorGlobal.I.playHistoryRepository;
    _loadData();
  }

  void _loadData() {
    _projectsFuture = _repository.getRecentProjects(limit: 10);
    _playHistoryFuture = _playHistoryRepository.getRecentPlayHistory(limit: 5);
  }

  Future<void> _refreshData() async {
    setState(_loadData);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshData,
          color: AppColors.accent,
          backgroundColor: AppColors.bgElevated,
          child: CustomScrollView(
            slivers: [
              // App Header with title and new project button
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'LyricForge',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              '本地 KTV 制作工具',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          _QuickPlayButton(
                            onTap: () => Navigator.pushNamed(
                              context,
                              Routes.quickPlay,
                            ).then((_) => _refreshData()),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          _NewProjectButton(
                            onTap: () => Navigator.pushNamed(context, Routes.import),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Play history section
              SliverToBoxAdapter(
                child: FutureBuilder<List<PlayHistory>>(
                  future: _playHistoryFuture,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    final histories = snapshot.data!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            AppSpacing.lg,
                            AppSpacing.md,
                            AppSpacing.sm,
                          ),
                          child: Row(
                            children: [
                              Text(
                                '最近播放',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: () {},
                                child: const Text('查看全部'),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          child: Column(
                            children: histories.map((history) {
                              return _PlayHistoryListItem(
                                history: history,
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  Routes.quickPlay,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              // Section title
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Text(
                        '最近项目',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {},
                        child: const Text('查看全部'),
                      ),
                    ],
                  ),
                ),
              ),

              // Project list or empty state
              FutureBuilder<List<ProjectManifest>>(
                future: _projectsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 48,
                              color: AppColors.error,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              '加载失败',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final projects = snapshot.data ?? [];

                  if (projects.isEmpty) {
                    return const SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyProjectsState(),
                    );
                  }

                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final project = projects[index];
                          return _ProjectListItem(
                            project: project,
                            onTap: () => Navigator.pushNamed(
                              context,
                              Routes.projectDetailPath(project.id),
                            ),
                          );
                        },
                        childCount: projects.length,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayHistoryListItem extends StatelessWidget {
  final PlayHistory history;
  final VoidCallback onTap;

  const _PlayHistoryListItem({
    required this.history,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: AppSpacing.xl * 2,
          height: AppSpacing.xl * 2,
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          ),
          child: const Icon(
            Icons.play_circle_outline,
            color: AppColors.textSecondary,
          ),
        ),
        title: Text(
          history.name,
          style: Theme.of(context).textTheme.titleMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          history.formattedPlayedAt,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}

class _ProjectListItem extends StatelessWidget {
  final ProjectManifest project;
  final VoidCallback onTap;

  const _ProjectListItem({
    required this.project,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: AppSpacing.xl * 2,
          height: AppSpacing.xl * 2,
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          ),
          child: const Icon(
            Icons.music_note,
            color: AppColors.textSecondary,
          ),
        ),
        title: Text(
          project.name,
          style: Theme.of(context).textTheme.titleMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: project.artist != null
            ? Text(
                project.artist!,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: const Icon(
          Icons.chevron_right,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}

class _QuickPlayButton extends StatelessWidget {
  final VoidCallback onTap;

  const _QuickPlayButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgElevated,
      borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_arrow,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '快速播放',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewProjectButton extends StatelessWidget {
  final VoidCallback onTap;

  const _NewProjectButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent,
      borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.add,
                size: 18,
                color: AppColors.pureWhite,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '新建工程',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.pureWhite,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyProjectsState extends StatelessWidget {
  const _EmptyProjectsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: AppSpacing.xxl * 3,
            height: AppSpacing.xxl * 3,
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
            ),
            child: const Icon(
              Icons.music_note_outlined,
              size: 48,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            '还没有项目',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '点击上方按钮导入音频，开始制作你的 KTV',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xl),
          OutlinedButton.icon(
            onPressed: () => Navigator.pushNamed(context, Routes.import),
            icon: const Icon(Icons.add),
            label: const Text('导入音频'),
          ),
        ],
      ),
    );
  }
}
