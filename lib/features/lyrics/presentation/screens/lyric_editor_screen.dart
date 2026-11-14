import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../player/domain/models/playback_state.dart';
import '../../../player/domain/services/audio_player_service.dart';
import '../../../player/domain/services/playback_session_service.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/lyric_review_queue.dart';
import '../../domain/proofreading/proofread_result.dart';
import '../../domain/services/lyric_audition_window_service.dart';
import '../../domain/services/lyric_file_export_service.dart';
import '../../domain/services/lyric_manual_edit_marker_service.dart';
import '../../domain/services/lyric_review_priority_service.dart';
import '../../domain/services/reference_alignment_restore_service.dart';
import '../../domain/services/reference_lyric_text_parser.dart';
import '../widgets/reference_alignment_backup_dialog.dart';
import '../widgets/reference_alignment_result_comparison.dart';
import '../controllers/line_audition_controller.dart';
import '../controllers/lyric_editor_document_controller.dart';
import '../controllers/lyric_editor_proofreading_coordinator.dart';
import '../lyric_editor_dependencies.dart';
import '../lyric_review_strings.dart';
import '../widgets/lyric_editor_content.dart';
import '../widgets/lyric_editor_toolbar.dart';
import '../widgets/lyric_list_pane.dart';
import '../widgets/lyric_proofread_v2_dialog.dart';
import '../widgets/project_save_conflict_dialog.dart';

class LyricEditorScreen extends StatefulWidget {
  final String projectId;

  /// Everything this screen talks to, decided by the assembly layer.
  ///
  /// Required rather than defaulted to the app singleton: the editor is the
  /// first feature migrated off the global locator (Phase 4.2), and a default
  /// would quietly bring it back.
  final LyricEditorDependencies dependencies;

  const LyricEditorScreen({
    super.key,
    required this.projectId,
    required this.dependencies,
  });

  @override
  State<LyricEditorScreen> createState() => _LyricEditorScreenState();
}

class _LyricEditorScreenState extends State<LyricEditorScreen>
    implements LyricEditorProofreadFlowHost {
  late final ProjectRepository _repository;
  late final PlaybackSessionService _playbackSession;
  late final AudioPlayerService _audioService;
  late final LyricFileExportService _exportService;
  late final LyricManualEditMarkerService _lineMarkers;
  late final ReferenceLyricTextParser _referenceParser;
  late final LyricEditorProofreadingCoordinator _proofreading;
  late Future<ProjectManifest?> _projectFuture;
  int? _projectRevision;

  /// Owns the document, its dirty flag, the selected row, the manual-edit marks
  /// and the undo history; this screen only decides what to show.
  late final LyricEditorDocumentController _editor;

  bool _proofreadV2InProgress = false;
  bool _followPlayback = true;
  LyricReviewFilter _filter = LyricReviewFilter.all;

  LyricDocument? get _editingDocument => _editor.document;
  int? get _selectedLineIndex => _editor.selectedLineIndex;

  /// 插入新行后递增，用于让列表/检查器知道"该聚焦这个新行"。
  int _focusRequestId = 0;
  int? _focusLineIndex;

  /// 仅当歌词文档发生变化时重新计算，避免播放进度流触发每帧风险排序。
  LyricDocument? _reviewPrioritySource;
  Duration? _reviewPriorityAudioDuration;
  LyricReviewQueue _reviewQueue = LyricReviewQueue.empty;
  Map<int, LyricReviewPriority> _reviewPriorityByIndex = const {};

  late final LineAuditionController _audition;

  int? get _activeAuditionLineIndex {
    final document = _editingDocument;
    final active = _audition.active;
    if (document == null || active == null) return null;
    if (active.projectId != widget.projectId) return null;
    return _audition.activeLineIndex(document);
  }

  /// 受保护行的当前索引视图：按稳定标识在现有行序中重新定位，供逐行确认使用。
  Set<int> get _manuallyEditedLineIndices => _editor.protectedIndices;

  /// Rebuilds the one review queue every counter and filter reads from.
  ///
  /// The toolbar used to derive three numbers here — a low-confidence count from
  /// raw scores, a "needs review" predicate, and the priority queue length —
  /// which meant the three could disagree and, for an unscored engine, all
  /// equalled the line count. [LyricReviewQueue] makes them one set.
  void _refreshReviewQueue(LyricDocument document, Duration? audioDuration) {
    if (identical(_reviewPrioritySource, document) &&
        _reviewPriorityAudioDuration == audioDuration) {
      return;
    }
    _reviewPrioritySource = document;
    _reviewPriorityAudioDuration = audioDuration;
    _reviewQueue = LyricReviewQueue.build(
      document,
      audioDuration: audioDuration,
      confidenceThreshold: kLyricReviewConfidenceThreshold,
    );
    _reviewPriorityByIndex = Map<int, LyricReviewPriority>.unmodifiable(
      _reviewQueue.byIndex,
    );
  }

  void _undo() => _applyHistoryEdit(_editor.undo());

  void _redo() => _applyHistoryEdit(_editor.redo());

  /// Shared tail of undo/redo: the document already changed inside the
  /// controller, so this only refreshes what the screen derives from it.
  void _applyHistoryEdit(LyricEditResult result) {
    final hint = result.hint;
    if (!result.applied) {
      if (hint != null) _showEditHint(hint);
      return;
    }
    _audition.clear();
    if (hint != null) _showEditHint(hint);
  }

  void _showEditHint(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _setLineReviewDecision(
    ProjectManifest project,
    int index, {
    required bool reviewed,
  }) {
    if (!_editor.setLineReviewed(index, reviewed: reviewed).applied) return;

    setState(() {
      _filter = LyricReviewFilter.needsReview;
      _refreshReviewQueue(_editingDocument!, project.audioAsset?.duration);
      _editor.select(
        _reviewPriorityByIndex.isEmpty
            ? null
            : (_reviewPriorityByIndex.values.toList()..sort((left, right) {
                    final byScore = right.score.compareTo(left.score);
                    return byScore != 0
                        ? byScore
                        : left.lineIndex.compareTo(right.lineIndex);
                  }))
                  .first
                  .lineIndex,
      );
    });

    final remaining = _reviewPriorityByIndex.length;
    final message = reviewed
        ? remaining == 0
              ? '已确认第 ${index + 1} 行；待复核队列已清空。保存后会保留本次确认。'
              : '已确认第 ${index + 1} 行；已跳到下一条待复核行（剩余 $remaining 行）。'
        : '已取消第 ${index + 1} 行的复核标记；该行已重新进入待复核队列。';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  @override
  void initState() {
    super.initState();
    final dependencies = widget.dependencies;
    _repository = dependencies.projectRepository;
    _playbackSession = dependencies.playbackSession;
    _audioService = dependencies.audioPlayer;
    _audition = LineAuditionController(
      audioService: _audioService,
      playbackSession: _playbackSession,
      onBoundaryError: _showAuditionError,
    )..addListener(_handleAuditionChanged);
    _exportService = dependencies.lyricFileExport;
    _lineMarkers = const LyricManualEditMarkerService();
    _editor = LyricEditorDocumentController(markerService: _lineMarkers);
    _referenceParser = ReferenceLyricTextParser(dependencies.lyricFileImport);
    _proofreading = LyricEditorProofreadingCoordinator(
      dependencies: dependencies,
      referenceParser: _referenceParser,
      host: this,
    );
    _loadProject();
  }

  void _handleAuditionChanged() {
    if (mounted) setState(() {});
  }

  void _showAuditionError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${LyricReviewStrings.auditionErrorPrefix}$error'),
      ),
    );
  }

  void _loadProject() {
    _projectFuture = _repository.getProjectById(widget.projectId).then((
      project,
    ) {
      if (!mounted) return project;
      if (project != null) _projectRevision = project.revision;
      if (project == null || _editor.document != null) return project;
      _editor.load(
        project.lyricDocument ??
            const LyricDocument(language: 'zh', lines: <LyricLine>[]),
      );
      return project;
    });
  }

  Future<void> _saveChanges(ProjectManifest project) async {
    if (_editingDocument == null) return;

    final updated = project.copyWith(
      lyricDocument: _editor.documentForSave(),
      status: ProjectStatus.editing,
      currentStage: ProcessingStage.lyricsEdited,
    );
    try {
      final saved = await _repository.updateProjectIfUnchanged(
        updated,
        expectedRevision: _projectRevision ?? project.revision,
      );
      _finishProjectSave(saved);
    } on ProjectUpdateConflictException catch (conflict) {
      await _resolveProjectSaveConflict(conflict);
    }
  }

  void _finishProjectSave(ProjectManifest saved) {
    if (!mounted) return;
    _projectRevision = saved.revision;
    _projectFuture = Future<ProjectManifest?>.value(saved);
    _editor.markSaved();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('歌词已保存'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _resolveProjectSaveConflict(
    ProjectUpdateConflictException conflict,
  ) async {
    final latest =
        conflict.currentProject ??
        await _repository.getProjectById(widget.projectId);
    if (!mounted) return;
    if (latest == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('工程已不存在；当前编辑仍保留，未保存。')));
      return;
    }

    final choice = await showProjectSaveConflictDialog(
      context,
      latestRevision: latest.revision,
    );
    if (!mounted) return;

    switch (choice) {
      case ProjectSaveConflictChoice.keepEditing:
        return;
      case ProjectSaveConflictChoice.reloadLatest:
        final reloaded = await _repository.getProjectById(widget.projectId);
        if (!mounted) return;
        if (reloaded == null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('工程已不存在；当前编辑仍保留，未保存。')));
          return;
        }
        _projectRevision = reloaded.revision;
        _projectFuture = Future<ProjectManifest?>.value(reloaded);
        _editor.load(
          reloaded.lyricDocument ??
              const LyricDocument(language: 'zh', lines: <LyricLine>[]),
        );
        setState(() {});
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已载入最新版工程。')));
        return;
      case ProjectSaveConflictChoice.overwriteLatest:
        final localDocument = _editor.documentForSave();
        final replacement = latest.copyWith(
          lyricDocument: localDocument,
          status: ProjectStatus.editing,
          currentStage: ProcessingStage.lyricsEdited,
        );
        try {
          final saved = await _repository.updateProjectIfUnchanged(
            replacement,
            expectedRevision: latest.revision,
          );
          _finishProjectSave(saved);
        } on ProjectUpdateConflictException catch (newConflict) {
          await _resolveProjectSaveConflict(newConflict);
        }
        return;
    }
  }

  Future<void> _exportLyrics(ProjectManifest project) async {
    final document = _editingDocument;
    if (document == null || document.lines.isEmpty) return;

    try {
      final path = await _exportService.exportLrc(
        document,
        suggestedFileName: project.name,
        title: project.name,
        artist: project.artist,
        album: project.album,
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('LRC 歌词已导出：$path')));
    } on LyricExportException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出歌词失败：$error')));
    }
  }

  Future<void> _openReferenceAlignment(ProjectManifest project) async {
    final document = _editingDocument;
    if (document == null || document.lines.isEmpty) return;
    await _proofreading.openReferenceAlignment(
      project: project,
      document: document,
      revision: _editor.documentRevision,
    );
  }

  Future<void> _openReferenceProofread(ProjectManifest project) async {
    final document = _editingDocument;
    if (document == null || document.lines.isEmpty) return;
    await _proofreading.openReferenceProofread(
      project: project,
      document: document,
      revision: _editor.documentRevision,
    );
  }

  Future<void> _openProofreadV2(ProjectManifest project) async {
    final document = _editingDocument;
    if (_proofreadV2InProgress || document == null || document.lines.isEmpty) {
      return;
    }
    final revision = _editor.documentRevision;
    setState(() => _proofreadV2InProgress = true);
    try {
      await _proofreading.runProofreadV2(
        project: project,
        document: document,
        revision: revision,
        projectRevision: _projectRevision ?? project.revision,
      );
    } finally {
      if (mounted) setState(() => _proofreadV2InProgress = false);
    }
  }

  @override
  BuildContext get proofreadContext => context;

  @override
  bool get proofreadIsMounted => mounted;

  @override
  int get proofreadDocumentRevision => _editor.documentRevision;

  @override
  int? get proofreadSelectedLineIndex => _selectedLineIndex;

  @override
  Set<int> get proofreadManuallyEditedLineIndices => _manuallyEditedLineIndices;

  @override
  AudioPlayerService get proofreadAudioService => _audioService;

  @override
  PlaybackSessionService get proofreadPlaybackSession => _playbackSession;

  @override
  LineAuditionController get proofreadAudition => _audition;

  @override
  bool proofreadIsCurrent(int revision) {
    if (!mounted) return false;
    if (_editor.documentRevision == revision) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('歌词在校对期间已更改，原提案已丢弃；当前修改仍保留，请重新生成校对提案。')),
    );
    return false;
  }

  @override
  Future<void> previewProofreadLine(ProjectManifest project, int index) =>
      _previewLine(project, index);

  @override
  Future<ProofreadTimedLinePreviewResult> previewProofreadTimedLine(
    ProjectManifest project,
    int index,
    LyricLine line,
    Duration globalOffset,
  ) => _previewTimedLine(project, index, line, globalOffset);

  @override
  Future<void> previewProofreadToken(
    ProjectManifest project,
    int index,
    TimedLyricToken token,
  ) => _previewProofreadToken(project, index, token);

  @override
  void applyProofreadDocument({
    required LyricDocument document,
    required String label,
    required int? selectedLineIndex,
    required bool isReferenceProofread,
    required String message,
  }) {
    if (!mounted) return;
    final shouldPauseAudition = _audition.isSounding;
    setState(() {
      _editor.replaceDocument(
        document,
        label: label,
        selectedLineIndex: selectedLineIndex,
        keepBatchSnapshot: true,
        isReferenceProofread: isReferenceProofread,
      );
      _audition.clear();
      _filter = LyricReviewFilter.all;
    });
    if (shouldPauseAudition) unawaited(_audioService.pause());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: '撤销', onPressed: _undoAlignmentApply),
      ),
    );
  }

  Future<void> _showAlignmentComparison(ProjectManifest project) async {
    final before = _editor.alignmentSnapshot?.document;
    final after = _editingDocument;
    if (before == null || after == null) return;

    await showReferenceAlignmentResultComparison(
      context,
      before: before,
      after: after,
      onPreviewLine: (index) => _previewLine(project, index),
    );
  }

  void _undoAlignmentApply() {
    final shouldPauseAudition = _audition.isSounding;
    if (!_editor.undoBatchChange().applied) return;
    setState(() {
      _audition.clear();
      _filter = LyricReviewFilter.all;
    });
    if (shouldPauseAudition) unawaited(_audioService.pause());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已撤销最近一次参考歌词批量更改（未写入磁盘）'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  /// 恢复对齐前的单槽备份：二次确认后替换编辑中的文档，不自动保存。
  Future<void> _restoreAlignmentBackup() async {
    final document = _editingDocument;
    if (document == null) return;

    final restored = await confirmReferenceAlignmentRestore(
      context,
      document: document,
    );
    if (restored == null || !mounted) return;

    final shouldPauseAudition = _audition.isSounding;
    setState(() {
      _editor.restoreDocument(restored, label: '恢复对齐前版本');
      _audition.clear();
      _filter = LyricReviewFilter.all;
    });
    if (shouldPauseAudition) unawaited(_audioService.pause());

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '已恢复对齐前版本（${restored.lines.length} 行），'
          '未自动保存，请检查后手动保存。',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _addNewLine() {
    _editor.addLine();
    setState(() => _filter = LyricReviewFilter.all);
  }

  /// 在当前试听位置插入一行，按开始时间落到正确索引。
  void _insertLineAtPlayback() {
    final position = _timelinePositionFromPlayback();
    final result = _editor.insertLineAt(position);
    setState(() {
      _filter = LyricReviewFilter.all;
      if (result.insertedLineIndex != null) {
        _focusRequestId++;
        _focusLineIndex = result.insertedLineIndex;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已在 ${formatLyricDuration(position)} 插入歌词行'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 编辑器内跳转：先暂停，避免拖动后仍在播放而错过目标位置。
  Future<void> _seekPlayback(Duration position) async {
    try {
      if (_audition.isActive && mounted) {
        _audition.clear();
      }
      if (_audioService.currentState.isPlaying) {
        await _audioService.pause();
      }
      await _playbackSession.seek(position);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法跳转试听：$error')));
    }
  }

  void _updateLine(int index, LyricLine updatedLine) {
    final result = _editor.updateLine(
      index,
      updatedLine,
      auditionTarget: _isAuditionTarget(index),
    );
    if (!result.applied) return;
    final shouldPauseAudition = result.clearsAudition && _audition.isSounding;
    if (result.clearsAudition) _audition.clear();
    if (shouldPauseAudition) unawaited(_audioService.pause());
  }

  /// Whether the row at [index] is the one the bounded audition is playing.
  ///
  /// Resolved through the audition request's line id when it has one, so the
  /// check keeps describing the same row after insertions and deletions.
  bool _isAuditionTarget(int index) {
    final active = _audition.active;
    if (active == null || active.projectId != widget.projectId) return false;
    final document = _editingDocument;
    final lineId =
        document == null || index < 0 || index >= document.lines.length
        ? null
        : document.lines[index].id;
    return active.lineId != null
        ? active.lineId == lineId
        : active.lineIndex == index;
  }

  void _setLineStartFromPlayback(int index) {
    final document = _editingDocument;
    if (document == null || index < 0 || index >= document.lines.length) return;
    final line = document.lines[index];
    var next = _timelinePositionFromPlayback();
    final latest = line.endTime - const Duration(milliseconds: 10);
    if (next > latest) next = latest;
    if (next.isNegative) next = Duration.zero;
    _updateLine(index, line.copyWith(startTime: next));
  }

  void _setLineEndFromPlayback(int index) {
    final document = _editingDocument;
    if (document == null || index < 0 || index >= document.lines.length) return;
    final line = document.lines[index];
    var next = _timelinePositionFromPlayback();
    final earliest = line.startTime + const Duration(milliseconds: 10);
    if (next < earliest) next = earliest;
    _updateLine(index, line.copyWith(endTime: next));
  }

  Duration _timelinePositionFromPlayback() {
    final offset = _editingDocument?.globalOffset ?? Duration.zero;
    final shifted = _audioService.currentState.position - offset;
    return shifted.isNegative ? Duration.zero : shifted;
  }

  void _deleteLine(int index) {
    final result = _editor.deleteLine(
      index,
      auditionTarget: _isAuditionTarget(index),
    );
    if (!result.applied) return;
    final shouldPauseAudition = result.clearsAudition && _audition.isSounding;
    if (result.clearsAudition) _audition.clear();
    if (shouldPauseAudition) unawaited(_audioService.pause());
  }

  void _updateGlobalOffset(Duration offset) {
    final shouldPauseAudition = _audition.isSounding;
    _editor.updateGlobalOffset(offset);
    _audition.clear();
    if (shouldPauseAudition) unawaited(_audioService.pause());
  }

  Future<ProofreadTimedLinePreviewResult> _previewTimedLine(
    ProjectManifest project,
    int index,
    LyricLine line,
    Duration globalOffset,
  ) async {
    final document = _editingDocument;
    final audioAsset = project.audioAsset;
    if (document == null ||
        audioAsset == null ||
        index < 0 ||
        index >= document.lines.length) {
      return const ProofreadTimedLinePreviewResult.failure('工程音频或原始歌词行不可用。');
    }

    final currentItem = _playbackSession.currentState.currentItem;
    final audioDuration = currentItem?.projectId == project.id
        ? (_audioService.currentState.duration ?? audioAsset.duration)
        : audioAsset.duration;
    final window = const LyricAuditionWindowService().calculate(
      lineStart: line.startTime,
      lineEnd: line.endTime,
      globalOffset: globalOffset,
      audioDuration: audioDuration,
    );
    if (!window.canAudition) {
      final error = await _startAuditionWindow(
        project,
        index,
        document,
        audioAsset,
        window,
        showError: false,
      );
      return ProofreadTimedLinePreviewResult.failure(
        error ?? '该时间范围超出音频有效时长或时间区间无效，无法试听。',
      );
    }

    try {
      final result = await _audition.toggle(
        request: LineAuditionRequest(
          projectId: project.id,
          lineIndex: index,
          lineId: document.lines[index].id,
          window: window,
        ),
        prepare: () => _prepareProjectPlayback(project, audioAsset),
      );
      return switch (result.action) {
        LineAuditionAction.paused =>
          const ProofreadTimedLinePreviewResult.success(message: '已暂停试听。'),
        LineAuditionAction.resumed =>
          _audioService.currentState.isPlaying
              ? const ProofreadTimedLinePreviewResult.success()
              : const ProofreadTimedLinePreviewResult.failure(
                  '播放器未恢复播放状态；请检查音频文件与播放器日志。',
                ),
        LineAuditionAction.invalid => ProofreadTimedLinePreviewResult.failure(
          LyricReviewStrings.auditionInvalidStart,
        ),
        LineAuditionAction.failed => ProofreadTimedLinePreviewResult.failure(
          result.error ?? '该时间范围超出音频有效时长或时间区间无效，无法试听。',
        ),
        LineAuditionAction.started =>
          result.error == null
              ? const ProofreadTimedLinePreviewResult.success()
              : ProofreadTimedLinePreviewResult.failure(result.error!),
      };
    } catch (error) {
      return ProofreadTimedLinePreviewResult.failure(error.toString());
    }
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

    final currentItem = _playbackSession.currentState.currentItem;
    final audioDuration = currentItem?.projectId == project.id
        ? (_audioService.currentState.duration ?? audioAsset.duration)
        : audioAsset.duration;
    final window = const LyricAuditionWindowService().calculate(
      lineStart: document.lines[index].startTime,
      lineEnd: document.lines[index].endTime,
      globalOffset: document.globalOffset ?? Duration.zero,
      audioDuration: audioDuration,
    );

    try {
      final result = await _audition.toggle(
        request: LineAuditionRequest(
          projectId: project.id,
          lineIndex: index,
          lineId: document.lines[index].id,
          window: window,
        ),
        prepare: () => _prepareProjectPlayback(project, audioAsset),
      );
      if (!mounted) return;
      switch (result.action) {
        case LineAuditionAction.started:
          _editor.select(index);
        case LineAuditionAction.invalid:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(LyricReviewStrings.auditionInvalidStart),
            ),
          );
        case LineAuditionAction.failed:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${LyricReviewStrings.auditionErrorPrefix}${result.error}',
              ),
            ),
          );
        case LineAuditionAction.paused:
        case LineAuditionAction.resumed:
          break;
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${LyricReviewStrings.auditionErrorPrefix}$error'),
        ),
      );
    }
  }

  /// Loads [project] into the queue when the queue is showing something else,
  /// so an audition seeks inside the right audio.
  Future<void> _prepareProjectPlayback(
    ProjectManifest project,
    AudioAsset audioAsset,
  ) async {
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

  Future<void> _previewProofreadToken(
    ProjectManifest project,
    int lineIndex,
    TimedLyricToken token,
  ) async {
    final document = _editingDocument;
    final audioAsset = project.audioAsset;
    if (document == null ||
        audioAsset == null ||
        lineIndex < 0 ||
        lineIndex >= document.lines.length) {
      return;
    }

    final currentItem = _playbackSession.currentState.currentItem;
    final audioDuration = currentItem?.projectId == project.id
        ? (_audioService.currentState.duration ?? audioAsset.duration)
        : audioAsset.duration;
    final window = const LyricAuditionWindowService().calculate(
      lineStart: token.interval.start,
      lineEnd: token.interval.end,
      globalOffset: document.globalOffset ?? Duration.zero,
      audioDuration: audioDuration,
      // Keep a small lead-in so users can hear the word's onset in context.
      preRoll: const Duration(milliseconds: 250),
    );
    await _startAuditionWindow(
      project,
      lineIndex,
      document,
      audioAsset,
      window,
    );
  }

  Future<String?> _startAuditionWindow(
    ProjectManifest project,
    int index,
    LyricDocument document,
    AudioAsset audioAsset,
    LyricAuditionWindow window, {
    bool showError = true,
  }) async {
    final result = await _audition.start(
      request: LineAuditionRequest(
        projectId: project.id,
        lineIndex: index,
        lineId: document.lines[index].id,
        window: window,
      ),
      prepare: () => _prepareProjectPlayback(project, audioAsset),
    );
    if (!mounted) return result.error ?? '校对页面已关闭。';

    switch (result.action) {
      case LineAuditionAction.started:
        _editor.select(index);
        return null;
      case LineAuditionAction.invalid:
        if (showError) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(LyricReviewStrings.auditionInvalidStart),
            ),
          );
        }
        return LyricReviewStrings.auditionInvalidStart;
      case LineAuditionAction.failed:
        if (showError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${LyricReviewStrings.auditionErrorPrefix}${result.error}',
              ),
            ),
          );
        }
        return result.error;
      case LineAuditionAction.paused:
      case LineAuditionAction.resumed:
        return null;
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

      final active = _audition.active;
      final playback = _audioService.currentState;
      if (active != null &&
          !playback.isPlaying &&
          active.window.endAt != null &&
          playback.position >= active.window.endAt!) {
        // The editor-wide transport resumes the whole track after a bounded
        // line audition has completed; the row button remains the replay action.
        _audition.clear();
      }
      await _playbackSession.togglePlayPause();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法控制试听：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProjectManifest?>(
      future: _projectFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LyricEditorLoadingState();
        }

        if (snapshot.hasError || snapshot.data == null) {
          return LyricEditorErrorState(onRetry: () => setState(_loadProject));
        }

        final project = snapshot.data!;
        return ChangeNotifierProvider<LyricEditorDocumentController>.value(
          value: _editor,
          child:
              Selector<
                LyricEditorDocumentController,
                ({
                  LyricDocument? document,
                  bool hasChanges,
                  int? selectedLineIndex,
                  bool canUndo,
                  bool canRedo,
                  String? undoLabel,
                  String? redoLabel,
                  LyricEditorSnapshot? alignmentSnapshot,
                })
              >(
                selector: (context, controller) => (
                  document: controller.document,
                  hasChanges: controller.hasChanges,
                  selectedLineIndex: controller.selectedLineIndex,
                  canUndo: controller.canUndo,
                  canRedo: controller.canRedo,
                  undoLabel: controller.undoLabel,
                  redoLabel: controller.redoLabel,
                  alignmentSnapshot: controller.alignmentSnapshot,
                ),
                builder: (context, editorState, child) {
                  final document = editorState.document!;
                  _refreshReviewQueue(document, project.audioAsset?.duration);
                  final restoreProbe = const ReferenceAlignmentRestoreService()
                      .probeBackup(document);
                  final canRestore =
                      restoreProbe is ReferenceAlignmentBackupAvailable;

                  return StreamBuilder<PlaybackState>(
                    stream: _audioService.stateStream,
                    initialData: _audioService.currentState,
                    builder: (context, playbackSnapshot) {
                      final playback =
                          playbackSnapshot.data ?? const PlaybackState.idle();
                      final playbackBelongsToProject =
                          _playbackSession
                              .currentState
                              .currentItem
                              ?.projectId ==
                          project.id;

                      return LyricEditorContent(
                        project: project,
                        document: document,
                        playback: playback,
                        playbackBelongsToProject: playbackBelongsToProject,
                        hasChanges: editorState.hasChanges,
                        reviewPriorityByIndex: _reviewPriorityByIndex,
                        reviewQueue: _reviewQueue,
                        activeAuditionLineIndex: _activeAuditionLineIndex,
                        auditionPlaying:
                            playbackBelongsToProject && playback.isPlaying,
                        loopCurrentLineAudition: _audition.loopEnabled,
                        onLoopCurrentLineAuditionChanged: (value) {
                          _audition.loopEnabled = value;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                value
                                    ? LyricReviewStrings.loopCurrentLineEnabled
                                    : LyricReviewStrings
                                          .loopCurrentLineDisabled,
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        followPlayback: _followPlayback,
                        selectedLineIndex: editorState.selectedLineIndex,
                        filter: _filter,
                        onFilterChanged: (value) => setState(() {
                          _filter = value;
                          if (value != LyricReviewFilter.needsReview) {
                            _audition.loopEnabled = false;
                          }
                        }),
                        onFollowPlaybackChanged: (value) =>
                            setState(() => _followPlayback = value),
                        onSelectLine: _editor.select,
                        onReviewDecision: (index, reviewed) =>
                            _setLineReviewDecision(
                              project,
                              index,
                              reviewed: reviewed,
                            ),
                        onSave: () => _saveChanges(project),
                        onUndo: _undo,
                        onRedo: _redo,
                        canUndo: editorState.canUndo,
                        canRedo: editorState.canRedo,
                        undoLabel: editorState.undoLabel,
                        redoLabel: editorState.redoLabel,
                        onExport: () => _exportLyrics(project),
                        onReferenceAlignment: document.lines.isEmpty
                            ? null
                            : () => _openReferenceAlignment(project),
                        onReferenceProofread: document.lines.isEmpty
                            ? null
                            : () => _openReferenceProofread(project),
                        onProofreadV2:
                            document.lines.isEmpty || _proofreadV2InProgress
                            ? null
                            : () => _openProofreadV2(project),
                        onUndoReferenceAlignment:
                            editorState.alignmentSnapshot == null
                            ? null
                            : _undoAlignmentApply,
                        onViewAlignmentComparison:
                            editorState.alignmentSnapshot == null ||
                                editorState
                                    .alignmentSnapshot!
                                    .isReferenceProofread
                            ? null
                            : () => _showAlignmentComparison(project),
                        onRestoreAlignment: canRestore
                            ? _restoreAlignmentBackup
                            : null,
                        onAddLine: _addNewLine,
                        onInsertAtPlayback: _insertLineAtPlayback,
                        onSeekPlayback: _seekPlayback,
                        focusRequestId: _focusRequestId,
                        focusLineIndex: _focusLineIndex,
                        onUpdateLine: _updateLine,
                        onDeleteLine: _deleteLine,
                        onUpdateOffset: _updateGlobalOffset,
                        onPreviewLine: (index) => _previewLine(project, index),
                        onSetStartFromPlayback: _setLineStartFromPlayback,
                        onSetEndFromPlayback: _setLineEndFromPlayback,
                        onTogglePlayback: () => _togglePlayback(project),
                        manuallyEditedLineIndices: _manuallyEditedLineIndices,
                      );
                    },
                  );
                },
              ),
        );
      },
    );
  }

  @override
  void dispose() {
    // Leaving the editor must not leave a bounded audition sounding.
    if (_audition.isSounding) {
      unawaited(_audioService.pause().catchError((Object _) {}));
    }
    _audition.removeListener(_handleAuditionChanged);
    _audition.dispose();
    _editor.dispose();
    super.dispose();
  }
}
