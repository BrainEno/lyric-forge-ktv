import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/project_manifest.dart';
import '../../domain/services/project_duplicate_finder.dart';
import '../project_list_dependencies.dart';
import '../widgets/project_deletion_flow.dart';

/// 全部工程: every lyric project, with deleting and cleaning up the songs
/// that got a project more than once (D-063).
///
/// The dashboard only shows the eight most recent projects and nothing
/// could delete one, so a song recognised twice stayed twice for good.
class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({
    super.key,
    required this.dependencies,
    this.duplicatesOnly = false,
  });

  final ProjectListDependencies dependencies;

  /// Opens on the duplicates.
  final bool duplicatesOnly;

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  List<ProjectManifest>? _projects;
  List<ProjectDuplicateGroup> _groups = const [];
  Object? _error;
  String _query = '';
  late bool _duplicatesOnly = widget.duplicatesOnly;
  bool _selecting = false;
  bool _deleting = false;
  final Set<String> _selected = {};

  ProjectListDependencies get _deps => widget.dependencies;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final projects = await _deps.projectRepository.getAllProjects();
      if (!mounted) return;
      final finder = ProjectDuplicateFinder(
        canonicalize: _deps.canonicalizeAudioPath,
      );
      setState(() {
        _projects = projects;
        _groups = finder.find(projects);
        _error = null;
        final ids = {for (final project in projects) project.id};
        _selected.retainWhere(ids.contains);
        if (_groups.isEmpty) _duplicatesOnly = false;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  bool _matches(ProjectManifest project) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return project.name.toLowerCase().contains(query) ||
        (project.artist?.toLowerCase().contains(query) ?? false);
  }

  Future<void> _open(ProjectManifest project) async {
    await Navigator.pushNamed(context, Routes.projectDetailPath(project.id));
    if (mounted) await _load();
  }

  Future<void> _delete(List<ProjectManifest> projects, {String? note}) async {
    if (_deleting || projects.isEmpty) return;
    setState(() => _deleting = true);
    try {
      final outcome = await deleteProjectsWithConfirmation(
        context,
        service: _deps.deletionService,
        projects: projects,
        keepNote: note,
      );
      if (!mounted) return;
      if (outcome.deleted.isNotEmpty) {
        _selected.removeAll(outcome.deleted);
        if (_selected.isEmpty) _selecting = false;
      }
      await _load();
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _cleanDuplicates() {
    final extras = [for (final group in _groups) ...group.extras];
    final String note;
    if (_groups.length == 1) {
      final group = _groups.single;
      final reason = ProjectDuplicateFinder.keepReason(group);
      note =
          '保留“${group.keep.name}”（$reason），'
          '删除另外 ${extras.length} 个重复的工程。';
    } else {
      note =
          '${_groups.length} 首歌各保留一个工程（优先保留有歌词、校对过、最近修改的），'
          '删除其余 ${extras.length} 个。';
    }
    return _delete(extras, note: note);
  }

  void _toggleSelecting() => setState(() {
    _selecting = !_selecting;
    _selected.clear();
  });

  void _toggle(ProjectManifest project) => setState(() {
    if (!_selected.remove(project.id)) _selected.add(project.id);
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final projects = _projects;
    final selected = [
      for (final project in projects ?? const <ProjectManifest>[])
        if (_selected.contains(project.id)) project,
    ];
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        surfaceTintColor: Colors.transparent,
        title: Text(_selecting ? '已选 ${selected.length} 个' : '全部工程'),
        actions: [
          if (projects != null && projects.isNotEmpty)
            TextButton(
              key: const ValueKey('project_list_select'),
              onPressed: _deleting ? null : _toggleSelecting,
              child: Text(_selecting ? '完成' : '选择'),
            ),
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          SizedBox(width: spec.isCompact ? AppSpacing.xs : AppSpacing.sm),
        ],
      ),
      bottomNavigationBar: _selecting && selected.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  spec.pageGutter,
                  AppSpacing.sm,
                  spec.pageGutter,
                  AppSpacing.sm,
                ),
                child: FilledButton.icon(
                  key: const ValueKey('project_list_delete_selected'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                    minimumSize: Size.fromHeight(spec.minimumInteractiveExtent),
                  ),
                  onPressed: _deleting ? null : () => _delete(selected),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text('删除所选（${selected.length}）'),
                ),
              ),
            )
          : null,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: spec.contentMaxWidth),
          child: _body(spec, projects),
        ),
      ),
    );
  }

  Widget _body(AppLayoutSpec spec, List<ProjectManifest>? projects) {
    final theme = Theme.of(context);
    if (_error != null) {
      return _Message(
        icon: Icons.error_outline_rounded,
        text: '工程列表加载失败',
        action: TextButton(onPressed: _load, child: const Text('重试')),
      );
    }
    if (projects == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (projects.isEmpty) {
      return const _Message(
        icon: Icons.library_music_outlined,
        text: '还没有歌词工程',
      );
    }

    final duplicateIds = {
      for (final group in _groups)
        for (final project in group.projects) project.id,
    };
    final keepIds = {for (final group in _groups) group.keep.id};
    final rows = <Widget>[];
    if (_duplicatesOnly) {
      for (final group in _groups) {
        final members = group.projects.where(_matches).toList();
        if (members.isEmpty) continue;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.xs,
            ),
            child: Text(
              '${group.keep.name} · ${_reasonLabel(group.reason)} · '
              '${group.projects.length} 个',
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        );
        for (final project in members) {
          rows.add(_row(project, keep: keepIds.contains(project.id)));
        }
      }
    } else {
      for (final project in projects.where(_matches)) {
        rows.add(
          _row(
            project,
            duplicate: duplicateIds.contains(project.id),
            keep: keepIds.contains(project.id),
          ),
        );
      }
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          spec.pageGutter,
          AppSpacing.sm,
          spec.pageGutter,
          AppSpacing.xl,
        ),
        children: [
          TextField(
            key: const ValueKey('project_list_search'),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: '搜索歌名或歌手',
              isDense: true,
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_groups.isNotEmpty) ...[
            _DuplicateBanner(
              groups: _groups,
              showingDuplicates: _duplicatesOnly,
              busy: _deleting,
              onToggle: () =>
                  setState(() => _duplicatesOnly = !_duplicatesOnly),
              onClean: _cleanDuplicates,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Text(
            '${projects.length} 个工程',
            key: const ValueKey('project_list_count'),
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: Text('没有符合的工程')),
            ),
          ...rows,
        ],
      ),
    );
  }

  Widget _row(
    ProjectManifest project, {
    bool duplicate = false,
    bool keep = false,
  }) {
    return _ProjectRow(
      key: ValueKey('project_row_${project.id}'),
      project: project,
      badge: _duplicatesOnly
          ? (keep ? '建议保留' : '重复')
          : (duplicate ? (keep ? '有重复' : '重复') : null),
      selecting: _selecting,
      selected: _selected.contains(project.id),
      onTap: () => _selecting ? _toggle(project) : _open(project),
      onLongPress: _selecting || _deleting
          ? null
          : () => setState(() {
              _selecting = true;
              _selected
                ..clear()
                ..add(project.id);
            }),
      onDelete: _deleting ? null : () => _delete([project]),
    );
  }

  static String _reasonLabel(ProjectDuplicateReason reason) => switch (reason) {
    ProjectDuplicateReason.sameAudio => '同一个音频文件',
    ProjectDuplicateReason.sameSong => '同名同时长',
  };
}

class _DuplicateBanner extends StatelessWidget {
  const _DuplicateBanner({
    required this.groups,
    required this.showingDuplicates,
    required this.busy,
    required this.onToggle,
    required this.onClean,
  });

  final List<ProjectDuplicateGroup> groups;
  final bool showingDuplicates;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onClean;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extras = groups.fold<int>(0, (sum, g) => sum + g.extras.length);
    return Container(
      key: const ValueKey('project_list_duplicates_banner'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withAlpha(20),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(color: AppColors.warning.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.copy_all_rounded, color: AppColors.warning),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${groups.length} 首歌有重复的工程，共多出 $extras 个',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '一键清理会给每首歌留下有歌词、校对过或最近修改的那个工程，其余删除；删除前会再确认。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              FilledButton.icon(
                key: const ValueKey('project_list_clean_duplicates'),
                onPressed: busy ? null : onClean,
                icon: const Icon(Icons.cleaning_services_rounded),
                label: const Text('一键清理重复'),
              ),
              OutlinedButton(
                key: const ValueKey('project_list_show_duplicates'),
                onPressed: onToggle,
                child: Text(showingDuplicates ? '显示全部工程' : '只看重复的'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    super.key,
    required this.project,
    required this.badge,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
  });

  final ProjectManifest project;
  final String? badge;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = project.lyricDocument?.lines.length ?? 0;
    final updated = project.updatedAt.toLocal();
    final details = [
      if (project.artist?.trim().isNotEmpty ?? false) project.artist!.trim(),
      _stageLabel(project.currentStage),
      if (lines > 0) '$lines 行',
      '${updated.month}月${updated.day}日更新',
    ].join(' · ');
    final badge = this.badge;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      color: selected ? AppColors.accentMuted : AppColors.bgElevated,
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        leading: selecting
            ? Checkbox(value: selected, onChanged: (_) => onTap())
            : Icon(
                project.hasLyrics
                    ? Icons.lyrics_outlined
                    : Icons.music_note_outlined,
                color: AppColors.textSecondary,
              ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                project.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: AppSpacing.sm),
              _Badge(badge, keep: badge == '建议保留' || badge == '有重复'),
            ],
          ],
        ),
        subtitle: Text(
          details,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
        trailing: selecting
            ? null
            : PopupMenuButton<String>(
                key: ValueKey('project_menu_${project.id}'),
                tooltip: '更多',
                onSelected: (value) {
                  if (value == 'open') onTap();
                  if (value == 'delete') onDelete?.call();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'open', child: Text('打开工程')),
                  PopupMenuItem(
                    key: ValueKey('project_delete_${project.id}'),
                    value: 'delete',
                    enabled: onDelete != null,
                    child: const Text('删除工程'),
                  ),
                ],
              ),
      ),
    );
  }

  static String _stageLabel(ProcessingStage stage) => switch (stage) {
    ProcessingStage.none => '待开始',
    ProcessingStage.audioImported => '已导入',
    ProcessingStage.audioNormalized => '音频处理',
    ProcessingStage.vocalsSeparated => '人声已分离',
    ProcessingStage.transcriptionComplete => '歌词已识别',
    ProcessingStage.lyricsEdited => '歌词已校对',
    ProcessingStage.exported => '已导出',
  };
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {required this.keep});

  final String text;
  final bool keep;

  @override
  Widget build(BuildContext context) {
    final color = keep ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: AppSpacing.iconSizeLarge,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(text),
          ?action,
        ],
      ),
    );
  }
}
