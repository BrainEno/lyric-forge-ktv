import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/diagnostics/best_effort.dart';
import '../../../player/domain/models/playback_state.dart';
import '../../../player/domain/services/audio_player_service.dart';
import '../../../player/domain/services/playback_session_service.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/lyric_review_queue.dart';
import '../../domain/proofreading/proofread_result.dart';
import '../../domain/services/lyric_file_export_service.dart';
import '../../domain/services/lyric_manual_edit_marker_service.dart';
import '../../domain/services/lyric_review_priority_service.dart';
import '../../domain/services/reference_alignment_restore_service.dart';
import '../../domain/services/reference_lyric_text_parser.dart';
import '../widgets/reference_alignment_backup_dialog.dart';
import '../widgets/reference_alignment_result_comparison.dart';
import '../controllers/line_audition_controller.dart';
import '../controllers/lyric_editor_audition_flow.dart';
import '../controllers/lyric_editor_document_controller.dart';
import '../controllers/lyric_editor_proofreading_coordinator.dart';
import '../controllers/lyric_batch_text_tools_coordinator.dart';
import '../controllers/lyric_editor_save_flow.dart';
import '../controllers/lyric_export_coordinator.dart';
import '../lyric_editor_dependencies.dart';
import '../lyric_review_strings.dart';
import '../widgets/lyric_editor_actions.dart';
import '../widgets/lyric_editor_atoms.dart';
import '../widgets/lyric_editor_content.dart';
import '../widgets/lyric_editor_review_controls.dart';
import '../widgets/lyric_editor_toolbar.dart';
import '../widgets/lyric_line_delete_undo.dart';
import '../widgets/lyric_proofread_dialog.dart';

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
  late final LyricBatchTextToolsCoordinator _batchTools =
      LyricBatchTextToolsCoordinator(
        host: this,
        spanRecognizer: widget.dependencies.spanRecognizer,
        editingDocument: () => _editingDocument,
      );
  final LyricExportCoordinator _lyricExport = LyricExportCoordinator();
  late Future<ProjectManifest?> _projectFuture;
  late final LyricEditorSaveFlow _save;
  late final LyricEditorAuditionFlow _audio;

  /// Owns the document, its dirty flag, the selected row, the manual-edit marks
  /// and the undo history; this screen only decides what to show.
  late final LyricEditorDocumentController _editor;

  bool _proofreadPassRunning = false;
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
      _filter = LyricReviewFilter.suggested;
      _refreshReviewQueue(_editingDocument!, project.audioAsset?.duration);
      // The queue is already ranked: highest score first, then row order.
      _editor.select(
        _reviewQueue.isEmpty ? null : _reviewQueue.items.first.lineIndex,
      );
    });

    final remaining = _reviewPriorityByIndex.length;
    final message = reviewed
        ? remaining == 0
              ? '已确认第 ${index + 1} 行；建议复核的行已全部看完。保存后会保留本次确认。'
              : '已确认第 ${index + 1} 行；已跳到下一条建议复核的行（剩余 $remaining 行）。'
        : '已取消第 ${index + 1} 行的复核标记；该行重新列入建议复核。';
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
    _save = LyricEditorSaveFlow(
      repository: _repository,
      projectId: widget.projectId,
      editor: _editor,
      context: () => context,
      isMounted: () => mounted,
      onProjectChanged: (project) =>
          setState(() => _projectFuture = Future.value(project)),
      onSavingChanged: () => setState(() {}),
    );
    _audio = LyricEditorAuditionFlow(
      audition: _audition,
      audioService: _audioService,
      playbackSession: _playbackSession,
      document: () => _editingDocument,
      isMounted: () => mounted,
      selectLine: _editor.select,
      showMessage: _showMessage,
    );
    _loadProject();
  }

  void _handleAuditionChanged() {
    if (mounted) setState(() {});
  }

  void _showMessage(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(message)));
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
      if (project != null) _save.projectRevision = project.revision;
      if (project == null || _editor.document != null) return project;
      _editor.load(
        project.lyricDocument ??
            const LyricDocument(language: 'zh', lines: <LyricLine>[]),
      );
      return project;
    });
  }

  Future<void> _exportLyrics(ProjectManifest project) => _lyricExport.export(
    context,
    service: _exportService,
    project: project,
    document: _editingDocument,
  );

  Future<void> _openReferenceAlignment(ProjectManifest project) async {
    final document = _editingDocument;
    if (document == null || document.lines.isEmpty) return;
    await _proofreading.openReferenceAlignment(
      project: project,
      document: document,
      revision: _editor.documentRevision,
    );
  }

  Future<void> _openSmartProofread(ProjectManifest project) async {
    await _runProofreadPass(
      (document, revision) => _proofreading.runSmartProofread(
        project: project,
        document: document,
        revision: revision,
        projectRevision: _save.projectRevision ?? project.revision,
      ),
    );
  }

  Future<void> _runAutoProofread(ProjectManifest project) async {
    await _runProofreadPass(
      (document, revision) => _proofreading.runAutoProofread(
        project: project,
        document: document,
        revision: revision,
      ),
    );
  }

  /// One proofreading pass at a time; the menu entries are disabled while
  /// one runs.
  Future<void> _runProofreadPass(
    Future<void> Function(LyricDocument document, int revision) pass,
  ) async {
    final document = _editingDocument;
    if (_proofreadPassRunning || document == null || document.lines.isEmpty) {
      return;
    }
    setState(() => _proofreadPassRunning = true);
    try {
      await pass(document, _editor.documentRevision);
    } finally {
      if (mounted) setState(() => _proofreadPassRunning = false);
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
      _audio.previewLine(project, index);

  @override
  Future<ProofreadTimedLinePreviewResult> previewProofreadTimedLine(
    ProjectManifest project,
    int index,
    LyricLine line,
    Duration globalOffset,
  ) => _audio.previewTimedLine(project, index, line, globalOffset);

  @override
  Future<void> previewProofreadToken(
    ProjectManifest project,
    int index,
    TimedLyricToken token,
  ) => _audio.previewToken(project, index, token);

  @override
  void applyProofreadDocument({
    required LyricDocument document,
    required String label,
    required int? selectedLineIndex,
    required bool isReferenceProofread,
    required String message,
    Set<String> markManuallyEditedLineIds = const {},
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
        markManuallyEditedLineIds: markManuallyEditedLineIds,
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
      onPreviewLine: (index) => _audio.previewLine(project, index),
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
        content: Text('已撤销最近一次批量更改（未写入磁盘）'),
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

  void _updateLine(int index, LyricLine updatedLine) => _applyRowEdit(
    _editor.updateLine(
      index,
      updatedLine,
      auditionTarget: _isAuditionTarget(index),
    ),
  );

  /// Shared tail of row edits: drop (and pause) a stale audition, show a hint.
  void _applyRowEdit(LyricEditResult result) {
    final hint = result.hint;
    if (hint != null) _showEditHint(hint);
    if (!result.applied) return;
    final shouldPauseAudition = result.clearsAudition && _audition.isSounding;
    if (result.clearsAudition) _audition.clear();
    if (shouldPauseAudition) unawaited(_audioService.pause());
  }

  /// [playhead]: a paused playhead the content trusts as the audible break.
  void _splitLine(int index, int? textOffset, Duration? playhead) =>
      _applyRowEdit(
        _editor.splitLine(
          index,
          textOffset: textOffset,
          playbackPosition: playhead,
          auditionTarget: _isAuditionTarget(index),
        ),
      );

  void _mergeLineWithNext(int index) => _applyRowEdit(
    _editor.mergeLineWithNext(
      index,
      auditionTarget: _isAuditionTarget(index) || _isAuditionTarget(index + 1),
    ),
  );

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

  /// Deletes the row and offers 撤销 in a snackbar (D-064), on top of
  /// Ctrl/Cmd+Z: the undo applies only while nothing else has changed, so it
  /// never takes back a later edit instead.
  void _deleteLine(int index) {
    final result = _editor.deleteLine(
      index,
      auditionTarget: _isAuditionTarget(index),
    );
    _applyRowEdit(result);
    if (!result.applied || !mounted) return;
    offerLyricLineDeleteUndo(
      context,
      lineNumber: index + 1,
      revision: () => _editor.documentRevision,
      undo: _undo,
    );
  }

  void _updateGlobalOffset(Duration offset) {
    final shouldPauseAudition = _audition.isSounding;
    _editor.updateGlobalOffset(offset);
    _audition.clear();
    if (shouldPauseAudition) unawaited(_audioService.pause());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProjectManifest?>(
      future: _projectFuture,
      builder: (context, snapshot) {
        // A save swaps in a completed future: keep the editor mounted instead
        // of flashing the spinner and rebuilding every pane from scratch.
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
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
                        hasChanges: editorState.hasChanges,
                        onSave: () => _save.save(project),
                        isSaving: _save.isSaving,
                        player: LyricPlaybackControls(
                          state: playback,
                          belongsToProject: playbackBelongsToProject,
                          onSeek: _audio.seek,
                          onToggle: () => _audio.togglePlayback(
                            project,
                            selectedLineIndex: _selectedLineIndex,
                          ),
                        ),
                        review: _reviewControls(project),
                        history: LyricUndoRedoControls(
                          onUndo: _undo,
                          onRedo: _redo,
                          canUndo: editorState.canUndo,
                          canRedo: editorState.canRedo,
                          undoLabel: editorState.undoLabel,
                          redoLabel: editorState.redoLabel,
                        ),
                        proofread: LyricProofreadActions.forDocument(
                          hasLines: document.lines.isNotEmpty,
                          smartProofreadRunning: _proofreadPassRunning,
                          alignment: editorState.alignmentSnapshot,
                          canRestore: canRestore,
                          referenceAlignment: () =>
                              _openReferenceAlignment(project),
                          smartProofread: () => _openSmartProofread(project),
                          autoProofread: () => _runAutoProofread(project),
                          undoAlignment: _undoAlignmentApply,
                          viewComparison: () =>
                              _showAlignmentComparison(project),
                          restoreAlignment: _restoreAlignmentBackup,
                          batchTextTool: _batchTools.toolsFor(project),
                          vocalCheckAction: _batchTools.vocalCheckFor(project),
                        ),
                        edits: _lineEditActions,
                        audition: LyricAuditionControls(
                          onPreviewLine: (index) =>
                              _audio.previewLine(project, index),
                          activeLineIndex: _activeAuditionLineIndex,
                          playing:
                              playbackBelongsToProject && playback.isPlaying,
                          loopCurrentLine: _audition.loopEnabled,
                          onLoopCurrentLineChanged: _setLoopCurrentLine,
                        ),
                        onExport: () => _exportLyrics(project),
                        focusRequestId: _focusRequestId,
                        focusLineIndex: _focusLineIndex,
                        manuallyEditedLineIndices: _manuallyEditedLineIndices,
                        editor: _editor,
                      );
                    },
                  );
                },
              ),
        );
      },
    );
  }

  LyricReviewControls _reviewControls(ProjectManifest project) {
    return LyricReviewControls(
      queue: _reviewQueue,
      priorityByIndex: _reviewPriorityByIndex,
      filter: _filter,
      selectedLineIndex: _selectedLineIndex,
      followPlayback: _followPlayback,
      onFilterChanged: (value) => setState(() {
        _filter = value;
        if (value != LyricReviewFilter.suggested) {
          _audition.loopEnabled = false;
        }
      }),
      onFollowPlaybackChanged: (value) =>
          setState(() => _followPlayback = value),
      onSelectLine: _editor.select,
      onDecision: (index, reviewed) =>
          _setLineReviewDecision(project, index, reviewed: reviewed),
    );
  }

  LyricLineEditActions get _lineEditActions => LyricLineEditActions(
    onAddLine: _addNewLine,
    onInsertAtPlayback: _insertLineAtPlayback,
    onUpdateLine: _updateLine,
    onDeleteLine: _deleteLine,
    onSplitLine: _splitLine,
    onMergeLineWithNext: _mergeLineWithNext,
    onUpdateOffset: _updateGlobalOffset,
    onSetStartFromPlayback: _setLineStartFromPlayback,
    onSetEndFromPlayback: _setLineEndFromPlayback,
    onBatchEdit: _applyRowEdit,
  );

  void _setLoopCurrentLine(bool value) {
    _audition.loopEnabled = value;
    _showEditHint(
      value
          ? LyricReviewStrings.loopCurrentLineEnabled
          : LyricReviewStrings.loopCurrentLineDisabled,
    );
  }

  @override
  void dispose() {
    // Leaving the editor must not leave a bounded audition sounding.
    if (_audition.isSounding) {
      unawaited(
        bestEffort(
          'lyrics.editor',
          '离开编辑器时停止试听',
          _audioService.pause,
          impact: BestEffortImpact.degraded,
        ),
      );
    }
    _audition.removeListener(_handleAuditionChanged);
    _audition.dispose();
    _editor.dispose();
    super.dispose();
  }
}
