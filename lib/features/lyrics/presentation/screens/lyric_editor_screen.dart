import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../player/domain/models/playback_state.dart';
import '../../../player/domain/services/audio_player_service.dart';
import '../../../player/domain/services/playback_session_service.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';

enum _ReviewFilter { all, needsReview, lowConfidence }

class LyricEditorScreen extends StatefulWidget {
  final String projectId;

  const LyricEditorScreen({
    super.key,
    required this.projectId,
  });

  @override
  State<LyricEditorScreen> createState() => _LyricEditorScreenState();
}

class _LyricEditorScreenState extends State<LyricEditorScreen> {
  late final ProjectRepository _repository;
  late final PlaybackSessionService _playbackSession;
  late final AudioPlayerService _audioService;
  late Future<ProjectManifest?> _projectFuture;

  LyricDocument? _editingDocument;
  bool _hasChanges = false;
  int? _selectedLineIndex;
  _ReviewFilter _filter = _ReviewFilter.all;

  @override
  void initState() {
    super.initState();
    _repository = ServiceLocatorGlobal.I.projectRepository;
    _playbackSession = ServiceLocatorGlobal.I.playbackSessionService;
    _audioService = ServiceLocatorGlobal.I.audioPlayerService;
    _loadProject();
  }

  void _loadProject() {
    _projectFuture = _repository.getProjectById(widget.projectId);
  }

  Future<void> _saveChanges(ProjectManifest project) async {
    if (_editingDocument == null) return;

    final updated = project.copyWith(
      lyricDocument: _editingDocument,
      status: ProjectStatus.editing,
      currentStage: ProcessingStage.lyricsEdited,
    );

    await _repository.updateProject(updated);
    if (!mounted) return;

    setState(() => _hasChanges = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('歌词已保存'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _addNewLine() {
    setState(() {
      final lines = List<LyricLine>.from(_editingDocument?.lines ?? []);
      final lastEndTime = lines.isNotEmpty
          ? lines.last.endTime
          : const Duration(seconds: 5);

      lines.add(
        LyricLine(
          text: '',
          startTime: lastEndTime,
          endTime: lastEndTime + const Duration(seconds: 5),
        ),
      );

      final current = _editingDocument ??
          const LyricDocument(language: 'zh', lines: []);
      final metadata = _clearIndexedReviewMetadata(current.metadata);
      _editingDocument = current.copyWith(lines: lines, metadata: metadata);
      _selectedLineIndex = lines.length - 1;
      _filter = _ReviewFilter.all;
      _hasChanges = true;
    });
  }

  void _updateLine(int index, LyricLine updatedLine) {
    if (_editingDocument == null ||
        index < 0 ||
        index >= _editingDocument!.lines.length) {
      return;
    }

    setState(() {
      final lines = List<LyricLine>.from(_editingDocument!.lines);
      lines[index] = updatedLine;
      _editingDocument = _editingDocument!.copyWith(lines: lines);
      _hasChanges = true;
    });
  }

  void _deleteLine(int index) {
    if (_editingDocument == null ||
        index < 0 ||
        index >= _editingDocument!.lines.length) {
      return;
    }

    setState(() {
      final lines = List<LyricLine>.from(_editingDocument!.lines)
        ..removeAt(index);
      _editingDocument = _editingDocument!.copyWith(
        lines: lines,
        metadata: _clearIndexedReviewMetadata(_editingDocument!.metadata),
      );

      if (lines.isEmpty) {
        _selectedLineIndex = null;
      } else if (_selectedLineIndex == index) {
        _selectedLineIndex = index.clamp(0, lines.length - 1).toInt();
      } else if (_selectedLineIndex != null && _selectedLineIndex! > index) {
        _selectedLineIndex = _selectedLineIndex! - 1;
      }
      _hasChanges = true;
    });
  }

  Map<String, dynamic> _clearIndexedReviewMetadata(
    Map<String, dynamic> metadata,
  ) {
    return Map<String, dynamic>.from(metadata)
      ..remove('fallbackCandidates')
      ..remove('fallbackCandidateCount')
      ..remove('fallbackAppliedCount');
  }

  void _updateGlobalOffset(Duration offset) {
    setState(() {
      _editingDocument = _editingDocument?.copyWith(globalOffset: offset);
      _hasChanges = true;
    });
  }

  Duration _effectiveLineStart(LyricLine line) {
    final shifted =
        line.startTime + (_editingDocument?.globalOffset ?? Duration.zero);
    return shifted.isNegative ? Duration.zero : shifted;
  }

  Future<void> _previewLine(ProjectManifest project, int index) async {
    final document = _editingDocument;
    final audioAsset = project.audioAsset;
    if (document == null ||
        audioAsset == null ||
        index < 0 ||
        index >= document.lines.length) {
      return;
    }

    try {
      final currentItem = _playbackSession.currentState.currentItem;
      if (currentItem?.projectId != project.id) {
        final preferredSource = audioAsset.vocalPath != null
            ? AudioSourceType.vocals
            : AudioSourceType.original;
        await _playbackSession.playItem(
          PlaybackItem(
            id: 'project:${project.id}',
            title: project.name,
            artist: project.artist,
            projectId: project.id,
            artworkPath: audioAsset.thumbnailPath,
            hasLyrics: project.hasLyrics,
            audioAsset: audioAsset,
            preferredSource: preferredSource,
          ),
        );
      }

      await _playbackSession.seek(_effectiveLineStart(document.lines[index]));
      if (!_audioService.currentState.isPlaying) {
        await _audioService.play();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法试听当前歌词行：$error')),
      );
    }
  }

  Future<void> _togglePlayback(ProjectManifest project) async {
    try {
      final currentItem = _playbackSession.currentState.currentItem;
      if (currentItem?.projectId != project.id) {
        final index = _selectedLineIndex ?? 0;
        await _previewLine(project, index);
        return;
      }
      await _playbackSession.togglePlayPause();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法控制试听：$error')),
      );
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
        _editingDocument ??= project.lyricDocument ??
            const LyricDocument(language: 'zh', lines: []);

        if (_editingDocument!.lines.isNotEmpty && _selectedLineIndex == null) {
          _selectedLineIndex = 0;
        }

        return StreamBuilder<PlaybackState>(
          stream: _audioService.stateStream,
          initialData: _audioService.currentState,
          builder: (context, playbackSnapshot) {
            final playback =
                playbackSnapshot.data ?? const PlaybackState.idle();
            final activeProject =
                _playbackSession.currentState.currentItem?.projectId ==
                    project.id;

            return _LyricEditorContent(
              project: project,
              document: _editingDocument!,
              playback: playback,
              playbackBelongsToProject: activeProject,
              hasChanges: _hasChanges,
              selectedLineIndex: _selectedLineIndex,
              filter: _filter,
              onFilterChanged: (value) => setState(() => _filter = value),
              onSelectLine: (index) =>
                  setState(() => _selectedLineIndex = index),
              onSave: () => _saveChanges(project),
              onAddLine: _addNewLine,
              onUpdateLine: _updateLine,
              onDeleteLine: _deleteLine,
              onUpdateOffset: _updateGlobalOffset,
              onPreviewLine: (index) => _previewLine(project, index),
              onTogglePlayback: () => _togglePlayback(project),
            );
          },
        );
      },
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(title: const Text('歌词校对')),
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
      appBar: AppBar(title: const Text('歌词校对')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            const Text('加载歌词工程失败'),
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _LyricEditorContent extends StatelessWidget {
  final ProjectManifest project;
  final LyricDocument document;
  final PlaybackState playback;
  final bool playbackBelongsToProject;
  final bool hasChanges;
  final int? selectedLineIndex;
  final _ReviewFilter filter;
  final ValueChanged<_ReviewFilter> onFilterChanged;
  final ValueChanged<int> onSelectLine;
  final VoidCallback onSave;
  final VoidCallback onAddLine;
  final void Function(int, LyricLine) onUpdateLine;
  final ValueChanged<int> onDeleteLine;
  final ValueChanged<Duration> onUpdateOffset;
  final ValueChanged<int> onPreviewLine;
  final VoidCallback onTogglePlayback;

  const _LyricEditorContent({
    required this.project,
    required this.document,
    required this.playback,
    required this.playbackBelongsToProject,
    required this.hasChanges,
    required this.selectedLineIndex,
    required this.filter,
    required this.onFilterChanged,
    required this.onSelectLine,
    required this.onSave,
    required this.onAddLine,
    required this.onUpdateLine,
    required this.onDeleteLine,
    required this.onUpdateOffset,
    required this.onPreviewLine,
    required this.onTogglePlayback,
  });

  Map<String, dynamic>? _fallbackCandidateFor(int index) {
    final raw = document.metadata['fallbackCandidates'];
    if (raw is! List) return null;
    for (final item in raw) {
      if (item is! Map) continue;
      final candidate = Map<String, dynamic>.from(item);
      if (candidate['lineIndex'] == index) return candidate;
    }
    return null;
  }

  bool _needsReview(int index) {
    final line = document.lines[index];
    return line.confidence < 70 ||
        (line.confidence < 100 && _fallbackCandidateFor(index) != null);
  }

  int? _currentPlaybackLineIndex() {
    if (!playbackBelongsToProject || document.lines.isEmpty) return null;
    final offset = document.globalOffset ?? Duration.zero;
    for (var index = document.lines.length - 1; index >= 0; index--) {
      final shifted = document.lines[index].startTime + offset;
      final effective = shifted.isNegative ? Duration.zero : shifted;
      if (playback.position >= effective) return index;
    }
    return 0;
  }

  List<int> _visibleIndices() {
    final indices = <int>[];
    for (var index = 0; index < document.lines.length; index++) {
      final line = document.lines[index];
      final include = switch (filter) {
        _ReviewFilter.all => true,
        _ReviewFilter.needsReview => _needsReview(index),
        _ReviewFilter.lowConfidence => line.confidence < 70,
      };
      if (include) indices.add(index);
    }
    return indices;
  }

  @override
  Widget build(BuildContext context) {
    final lowConfidenceCount =
        document.lines.where((line) => line.confidence < 70).length;
    final reviewCount = List<int>.generate(document.lines.length, (i) => i)
        .where(_needsReview)
        .length;
    final currentPlaybackLine = _currentPlaybackLineIndex();
    final visibleIndices = _visibleIndices();
    final selectedIndex = selectedLineIndex != null &&
            selectedLineIndex! >= 0 &&
            selectedLineIndex! < document.lines.length
        ? selectedLineIndex
        : null;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        titleSpacing: AppSpacing.sm,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('歌词校对'),
            Text(
              project.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
          ],
        ),
        actions: [
          if (hasChanges)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: FilledButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text('保存修改'),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _EditorToolbar(
              document: document,
              playback: playback,
              playbackBelongsToProject: playbackBelongsToProject,
              lowConfidenceCount: lowConfidenceCount,
              reviewCount: reviewCount,
              filter: filter,
              onFilterChanged: onFilterChanged,
              onUpdateOffset: onUpdateOffset,
              onTogglePlayback: onTogglePlayback,
              onOpenPlayer: project.canPlay
                  ? () => Navigator.pushNamed(
                        context,
                        Routes.playerPath(project.id),
                      )
                  : null,
            ),
            Expanded(
              child: document.lines.isEmpty
                  ? _EmptyLyricsState(onAddLine: onAddLine)
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 980;
                        if (wide) {
                          return Row(
                            children: [
                              Expanded(
                                child: _LyricListPane(
                                  document: document,
                                  visibleIndices: visibleIndices,
                                  selectedIndex: selectedIndex,
                                  currentPlaybackLine: currentPlaybackLine,
                                  fallbackCandidateFor: _fallbackCandidateFor,
                                  onSelectLine: onSelectLine,
                                ),
                              ),
                              const VerticalDivider(width: 1),
                              SizedBox(
                                width: 430,
                                child: _InspectorPane(
                                  document: document,
                                  selectedIndex: selectedIndex,
                                  fallbackCandidate: selectedIndex == null
                                      ? null
                                      : _fallbackCandidateFor(selectedIndex),
                                  playback: playback,
                                  playbackBelongsToProject:
                                      playbackBelongsToProject,
                                  currentPlaybackLine: currentPlaybackLine,
                                  onUpdateLine: onUpdateLine,
                                  onDeleteLine: onDeleteLine,
                                  onPreviewLine: onPreviewLine,
                                ),
                              ),
                            ],
                          );
                        }

                        return Column(
                          children: [
                            Expanded(
                              child: _LyricListPane(
                                document: document,
                                visibleIndices: visibleIndices,
                                selectedIndex: selectedIndex,
                                currentPlaybackLine: currentPlaybackLine,
                                fallbackCandidateFor: _fallbackCandidateFor,
                                onSelectLine: onSelectLine,
                              ),
                            ),
                            if (selectedIndex != null) ...[
                              const Divider(height: 1),
                              SizedBox(
                                height: 330,
                                child: _InspectorPane(
                                  document: document,
                                  selectedIndex: selectedIndex,
                                  fallbackCandidate:
                                      _fallbackCandidateFor(selectedIndex),
                                  playback: playback,
                                  playbackBelongsToProject:
                                      playbackBelongsToProject,
                                  currentPlaybackLine: currentPlaybackLine,
                                  onUpdateLine: onUpdateLine,
                                  onDeleteLine: onDeleteLine,
                                  onPreviewLine: onPreviewLine,
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
            ),
            _BottomBar(
              totalLines: document.lines.length,
              visibleLines: visibleIndices.length,
              hasChanges: hasChanges,
              onAddLine: onAddLine,
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorToolbar extends StatelessWidget {
  final LyricDocument document;
  final PlaybackState playback;
  final bool playbackBelongsToProject;
  final int lowConfidenceCount;
  final int reviewCount;
  final _ReviewFilter filter;
  final ValueChanged<_ReviewFilter> onFilterChanged;
  final ValueChanged<Duration> onUpdateOffset;
  final VoidCallback onTogglePlayback;
  final VoidCallback? onOpenPlayer;

  const _EditorToolbar({
    required this.document,
    required this.playback,
    required this.playbackBelongsToProject,
    required this.lowConfidenceCount,
    required this.reviewCount,
    required this.filter,
    required this.onFilterChanged,
    required this.onUpdateOffset,
    required this.onTogglePlayback,
    required this.onOpenPlayer,
  });

  @override
  Widget build(BuildContext context) {
    final offset = document.globalOffset ?? Duration.zero;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.bgElevated,
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _MetricPill(
                icon: Icons.format_list_numbered_rounded,
                label: '${document.lines.length} 行',
              ),
              _MetricPill(
                icon: Icons.language_rounded,
                label: document.language.toUpperCase(),
              ),
              _MetricPill(
                icon: Icons.rule_rounded,
                label: '待复核 $reviewCount',
                emphasized: reviewCount > 0,
              ),
              _MetricPill(
                icon: Icons.warning_amber_rounded,
                label: '低置信度 $lowConfidenceCount',
                warning: lowConfidenceCount > 0,
              ),
              const SizedBox(width: AppSpacing.sm),
              ChoiceChip(
                selected: filter == _ReviewFilter.all,
                onSelected: (_) => onFilterChanged(_ReviewFilter.all),
                label: const Text('全部'),
              ),
              ChoiceChip(
                selected: filter == _ReviewFilter.needsReview,
                onSelected: (_) => onFilterChanged(_ReviewFilter.needsReview),
                label: const Text('待复核'),
              ),
              ChoiceChip(
                selected: filter == _ReviewFilter.lowConfidence,
                onSelected: (_) =>
                    onFilterChanged(_ReviewFilter.lowConfidence),
                label: const Text('低置信度'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: playbackBelongsToProject && playback.isPlaying
                    ? '暂停试听'
                    : '继续试听',
                onPressed: onTogglePlayback,
                icon: Icon(
                  playbackBelongsToProject && playback.isPlaying
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_fill_rounded,
                ),
              ),
              Text(
                playbackBelongsToProject
                    ? '${_formatDuration(playback.position)} / ${playback.duration == null ? '--:--' : _formatDuration(playback.duration!)}'
                    : '尚未开始试听',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              if (onOpenPlayer != null)
                TextButton.icon(
                  onPressed: onOpenPlayer,
                  icon: const Icon(Icons.open_in_full_rounded, size: 17),
                  label: const Text('完整播放器'),
                ),
              const SizedBox(width: AppSpacing.md),
              Text(
                '全局偏移',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.textTertiary,
                    ),
              ),
              _OffsetButton(
                label: '-100ms',
                onPressed: () => onUpdateOffset(
                  offset - const Duration(milliseconds: 100),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusCircular),
                ),
                child: Text(
                  _formatSignedDuration(offset),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ),
              _OffsetButton(
                label: '+100ms',
                onPressed: () => onUpdateOffset(
                  offset + const Duration(milliseconds: 100),
                ),
              ),
              if (offset != Duration.zero)
                TextButton(
                  onPressed: () => onUpdateOffset(Duration.zero),
                  child: const Text('归零'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LyricListPane extends StatelessWidget {
  final LyricDocument document;
  final List<int> visibleIndices;
  final int? selectedIndex;
  final int? currentPlaybackLine;
  final Map<String, dynamic>? Function(int) fallbackCandidateFor;
  final ValueChanged<int> onSelectLine;

  const _LyricListPane({
    required this.document,
    required this.visibleIndices,
    required this.selectedIndex,
    required this.currentPlaybackLine,
    required this.fallbackCandidateFor,
    required this.onSelectLine,
  });

  @override
  Widget build(BuildContext context) {
    if (visibleIndices.isEmpty) {
      return const _FilteredEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: visibleIndices.length,
      itemBuilder: (context, visibleIndex) {
        final index = visibleIndices[visibleIndex];
        final line = document.lines[index];
        final candidate = fallbackCandidateFor(index);
        return _LyricReviewRow(
          index: index,
          line: line,
          fallbackCandidate: candidate,
          selected: selectedIndex == index,
          playing: currentPlaybackLine == index,
          onTap: () => onSelectLine(index),
        );
      },
    );
  }
}

class _LyricReviewRow extends StatelessWidget {
  final int index;
  final LyricLine line;
  final Map<String, dynamic>? fallbackCandidate;
  final bool selected;
  final bool playing;
  final VoidCallback onTap;

  const _LyricReviewRow({
    required this.index,
    required this.line,
    required this.fallbackCandidate,
    required this.selected,
    required this.playing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final needsReview = line.confidence < 70 ||
        (line.confidence < 100 && fallbackCandidate != null);
    final background = selected
        ? AppColors.bgSurface
        : playing
            ? AppColors.accent.withAlpha(18)
            : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
              border: selected
                  ? Border.all(color: AppColors.accent.withAlpha(120))
                  : null,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  child: playing
                      ? const Icon(
                          Icons.graphic_eq_rounded,
                          size: 18,
                          color: AppColors.accent,
                        )
                      : Text(
                          '${index + 1}',
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: AppColors.textTertiary,
                                  ),
                        ),
                ),
                SizedBox(
                  width: 82,
                  child: Text(
                    _formatDuration(line.startTime),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textTertiary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                ),
                Expanded(
                  child: Text(
                    line.text.trim().isEmpty ? '（空歌词）' : line.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: line.text.trim().isEmpty
                              ? AppColors.textTertiary
                              : AppColors.textPrimary,
                          fontWeight:
                              playing ? FontWeight.w700 : FontWeight.w500,
                        ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (line.isChorus)
                  const _TinyBadge(label: '副歌', accent: true),
                if (fallbackCandidate != null && line.confidence < 100) ...[
                  const SizedBox(width: AppSpacing.xs),
                  const _TinyBadge(label: '双引擎'),
                ],
                if (needsReview) ...[
                  const SizedBox(width: AppSpacing.xs),
                  _TinyBadge(
                    label: '${line.confidence}',
                    warning: line.confidence < 70,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InspectorPane extends StatelessWidget {
  final LyricDocument document;
  final int? selectedIndex;
  final Map<String, dynamic>? fallbackCandidate;
  final PlaybackState playback;
  final bool playbackBelongsToProject;
  final int? currentPlaybackLine;
  final void Function(int, LyricLine) onUpdateLine;
  final ValueChanged<int> onDeleteLine;
  final ValueChanged<int> onPreviewLine;

  const _InspectorPane({
    required this.document,
    required this.selectedIndex,
    required this.fallbackCandidate,
    required this.playback,
    required this.playbackBelongsToProject,
    required this.currentPlaybackLine,
    required this.onUpdateLine,
    required this.onDeleteLine,
    required this.onPreviewLine,
  });

  @override
  Widget build(BuildContext context) {
    final index = selectedIndex;
    if (index == null || index < 0 || index >= document.lines.length) {
      return const _NoSelectionInspector();
    }

    final line = document.lines[index];
    return _LineInspector(
      key: ValueKey('inspector_$index'),
      index: index,
      line: line,
      fallbackCandidate: fallbackCandidate,
      isCurrentPlaybackLine:
          playbackBelongsToProject && currentPlaybackLine == index,
      isPlaying: playbackBelongsToProject && playback.isPlaying,
      onUpdate: (updated) => onUpdateLine(index, updated),
      onDelete: () => onDeleteLine(index),
      onPreview: () => onPreviewLine(index),
    );
  }
}

class _LineInspector extends StatefulWidget {
  final int index;
  final LyricLine line;
  final Map<String, dynamic>? fallbackCandidate;
  final bool isCurrentPlaybackLine;
  final bool isPlaying;
  final ValueChanged<LyricLine> onUpdate;
  final VoidCallback onDelete;
  final VoidCallback onPreview;

  const _LineInspector({
    super.key,
    required this.index,
    required this.line,
    required this.fallbackCandidate,
    required this.isCurrentPlaybackLine,
    required this.isPlaying,
    required this.onUpdate,
    required this.onDelete,
    required this.onPreview,
  });

  @override
  State<_LineInspector> createState() => _LineInspectorState();
}

class _LineInspectorState extends State<_LineInspector> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.line.text);
  }

  @override
  void didUpdateWidget(covariant _LineInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line.text != widget.line.text &&
        _textController.text != widget.line.text) {
      _textController.text = widget.line.text;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  String? _alternativeText() {
    final candidate = widget.fallbackCandidate;
    if (candidate == null) return null;
    return (candidate['alternativeText'] ?? candidate['whisperText'])
        ?.toString();
  }

  String _engineLabel(String? engine) {
    return switch (engine) {
      'qwen' => 'Qwen',
      'whisper' => 'Whisper',
      _ => engine ?? '备用引擎',
    };
  }

  void _updateText(String text) {
    widget.onUpdate(widget.line.copyWith(text: text, confidence: 100));
  }

  void _nudgeStart(Duration delta) {
    var next = widget.line.startTime + delta;
    if (next.isNegative) next = Duration.zero;
    final latest = widget.line.endTime - const Duration(milliseconds: 10);
    if (next > latest) next = latest.isNegative ? Duration.zero : latest;
    widget.onUpdate(widget.line.copyWith(startTime: next));
  }

  void _nudgeEnd(Duration delta) {
    var next = widget.line.endTime + delta;
    final earliest =
        widget.line.startTime + const Duration(milliseconds: 10);
    if (next < earliest) next = earliest;
    widget.onUpdate(widget.line.copyWith(endTime: next));
  }

  void _applyAlternative() {
    final alternative = _alternativeText();
    if (alternative == null || alternative.trim().isEmpty) return;
    _textController.text = alternative;
    widget.onUpdate(
      widget.line.copyWith(text: alternative, confidence: 100),
    );
  }

  @override
  Widget build(BuildContext context) {
    final alternative = _alternativeText();
    final duration = widget.line.endTime - widget.line.startTime;

    return Container(
      color: AppColors.bgElevated,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '第 ${widget.index + 1} 行',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatDuration(widget.line.startTime)} → ${_formatDuration(widget.line.endTime)} · ${_formatCompactDuration(duration)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.textTertiary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: '从这一行开始试听',
                onPressed: widget.onPreview,
                icon: Icon(
                  widget.isCurrentPlaybackLine && widget.isPlaying
                      ? Icons.graphic_eq_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              if (widget.line.confidence < 70)
                _TinyBadge(
                  label: '低置信度 ${widget.line.confidence}',
                  warning: true,
                )
              else
                _TinyBadge(label: '置信度 ${widget.line.confidence}'),
              if (widget.line.isChorus)
                const _TinyBadge(label: '副歌', accent: true),
              if (widget.fallbackCandidate != null)
                const _TinyBadge(label: '双引擎复核'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _textController,
            onChanged: _updateText,
            minLines: 2,
            maxLines: 4,
            style: Theme.of(context).textTheme.titleMedium,
            decoration: InputDecoration(
              labelText: '歌词文本',
              hintText: '输入这一行歌词',
              filled: true,
              fillColor: AppColors.bgSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (widget.fallbackCandidate != null &&
              alternative?.trim().isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.md),
            _AlternativeCandidateCard(
              primaryEngine: _engineLabel(
                widget.fallbackCandidate!['primaryEngine']?.toString(),
              ),
              alternativeEngine: _engineLabel(
                widget.fallbackCandidate!['alternativeEngine']?.toString(),
              ),
              alternativeText: alternative!,
              onApply: _applyAlternative,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _TimingEditor(
            title: '开始时间',
            value: widget.line.startTime,
            onNudge: _nudgeStart,
          ),
          const SizedBox(height: AppSpacing.sm),
          _TimingEditor(
            title: '结束时间',
            value: widget.line.endTime,
            onNudge: _nudgeEnd,
          ),
          const SizedBox(height: AppSpacing.lg),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('标记为副歌'),
            subtitle: const Text('播放器可使用这一标记强化副歌段落'),
            value: widget.line.isChorus,
            onChanged: (value) =>
                widget.onUpdate(widget.line.copyWith(isChorus: value)),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: widget.onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('删除这一行'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
          ),
        ],
      ),
    );
  }
}

class _TimingEditor extends StatelessWidget {
  final String title;
  final Duration value;
  final ValueChanged<Duration> onNudge;

  const _TimingEditor({
    required this.title,
    required this.value,
    required this.onNudge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ),
              Text(
                _formatDuration(value),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _NudgeButton(
                label: '-1s',
                onPressed: () => onNudge(const Duration(seconds: -1)),
              ),
              _NudgeButton(
                label: '-100ms',
                onPressed: () =>
                    onNudge(const Duration(milliseconds: -100)),
              ),
              _NudgeButton(
                label: '+100ms',
                onPressed: () =>
                    onNudge(const Duration(milliseconds: 100)),
              ),
              _NudgeButton(
                label: '+1s',
                onPressed: () => onNudge(const Duration(seconds: 1)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlternativeCandidateCard extends StatelessWidget {
  final String primaryEngine;
  final String alternativeEngine;
  final String alternativeText;
  final VoidCallback onApply;

  const _AlternativeCandidateCard({
    required this.primaryEngine,
    required this.alternativeEngine,
    required this.alternativeText,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.info.withAlpha(18),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        border: Border.all(color: AppColors.info.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$alternativeEngine 备选',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.info,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(alternativeText),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  '当前结果来自 $primaryEngine',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                ),
              ),
              TextButton(onPressed: onApply, child: const Text('采用备选')),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoSelectionInspector extends StatelessWidget {
  const _NoSelectionInspector();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgElevated,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.touch_app_outlined,
            size: 38,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '选择一行开始校对',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '文本、双引擎备选和时间轴微调都会集中显示在这里。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int totalLines;
  final int visibleLines;
  final bool hasChanges;
  final VoidCallback onAddLine;

  const _BottomBar({
    required this.totalLines,
    required this.visibleLines,
    required this.hasChanges,
    required this.onAddLine,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.bgElevated,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Text(
            visibleLines == totalLines
                ? '$totalLines 行歌词'
                : '显示 $visibleLines / $totalLines 行',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
          ),
          if (hasChanges) ...[
            const SizedBox(width: AppSpacing.sm),
            const _TinyBadge(label: '有未保存修改', warning: true),
          ],
          const Spacer(),
          FilledButton.tonalIcon(
            onPressed: onAddLine,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('添加歌词行'),
          ),
        ],
      ),
    );
  }
}

class _EmptyLyricsState extends StatelessWidget {
  final VoidCallback onAddLine;

  const _EmptyLyricsState({required this.onAddLine});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lyrics_outlined,
              size: 56,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '这个工程还没有歌词',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '可以先返回工程页运行自动识别，也可以从这里手动建立第一行歌词。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onAddLine,
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加第一行'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilteredEmptyState extends StatelessWidget {
  const _FilteredEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.task_alt_rounded,
            size: 42,
            color: AppColors.accent,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '当前筛选下没有待处理歌词',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool emphasized;
  final bool warning;

  const _MetricPill({
    required this.icon,
    required this.label,
    this.emphasized = false,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = warning
        ? AppColors.warning
        : emphasized
            ? AppColors.accent
            : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                ),
          ),
        ],
      ),
    );
  }
}

class _TinyBadge extends StatelessWidget {
  final String label;
  final bool accent;
  final bool warning;

  const _TinyBadge({
    required this.label,
    this.accent = false,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = warning
        ? AppColors.warning
        : accent
            ? AppColors.accent
            : AppColors.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontSize: 10,
            ),
      ),
    );
  }
}

class _OffsetButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _OffsetButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      ),
      child: Text(label),
    );
  }
}

class _NudgeButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _NudgeButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(70, 36),
        visualDensity: VisualDensity.compact,
      ),
      child: Text(label),
    );
  }
}

String _formatDuration(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
  final millis = (safe.inMilliseconds.remainder(1000) ~/ 10)
      .toString()
      .padLeft(2, '0');
  return '$minutes:$seconds.$millis';
}

String _formatCompactDuration(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  if (safe.inSeconds >= 1) {
    return '${(safe.inMilliseconds / 1000).toStringAsFixed(1)}s';
  }
  return '${safe.inMilliseconds}ms';
}

String _formatSignedDuration(Duration duration) {
  if (duration == Duration.zero) return '0ms';
  final sign = duration.isNegative ? '-' : '+';
  final milliseconds = duration.inMilliseconds.abs();
  if (milliseconds >= 1000) {
    return '$sign${(milliseconds / 1000).toStringAsFixed(1)}s';
  }
  return '$sign${milliseconds}ms';
}
