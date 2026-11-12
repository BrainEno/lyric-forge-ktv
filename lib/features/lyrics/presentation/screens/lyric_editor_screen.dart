import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../player/domain/models/playback_state.dart';
import '../../../player/domain/services/audio_player_service.dart';
import '../../../player/domain/services/playback_session_service.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/lyric_review_queue.dart';
import '../../domain/models/reference_lyric_input.dart';
import '../../domain/proofreading/apply_reference_alignment_use_case.dart';
import '../../domain/proofreading/forced_alignment_language.dart';
import '../../domain/proofreading/forced_alignment_proofread_service.dart';
import '../../domain/proofreading/proofread_result.dart';
import '../../domain/proofreading/project_proofread_evidence.dart';
import '../../domain/proofreading/reference_alignment_audio_guard.dart';
import '../../domain/proofreading/reference_alignment_timing_applier.dart';
import '../../domain/proofreading/proofread_v2_document_composer.dart';
import '../../domain/proofreading/run_proofread_v2_use_case.dart';
import '../../domain/proofreading/run_reference_proofread_use_case.dart';
import '../../domain/proofreading/reference_proofread_change_set.dart';
import '../../domain/services/lyric_audition_window_service.dart';
import '../../domain/services/lyric_file_export_service.dart';
import '../../domain/services/lyric_manual_edit_marker_service.dart';
import '../../domain/services/lyric_review_decision_service.dart';
import '../../domain/services/lyric_review_priority_service.dart';
import '../../domain/services/lyric_timeline_validator.dart';
import '../../domain/services/reference_alignment_restore_service.dart';
import '../../domain/services/reference_lyric_text_parser.dart';
import '../widgets/reference_alignment_backup_dialog.dart';
import '../widgets/reference_alignment_dialog.dart';
import '../widgets/reference_alignment_review.dart';
import '../widgets/reference_proofread_review_dialog.dart';
import '../widgets/reference_proofread_timing_review_dialog.dart';
import '../widgets/timing_evidence_import_dialog.dart';
import '../widgets/reference_alignment_result_comparison.dart';
import '../controllers/line_audition_controller.dart';
import '../controllers/lyric_editor_document_controller.dart';
import '../lyric_editor_dependencies.dart';
import '../lyric_review_strings.dart';
import '../widgets/lyric_editor_atoms.dart';
import '../widgets/lyric_inspector_pane.dart';
import '../widgets/lyric_list_pane.dart';
import '../widgets/lyric_proofread_v2_dialog.dart';
import '../widgets/lyric_edit_shortcuts.dart';
import '../widgets/lyric_editor_toolbar.dart';
import '../widgets/lyric_proofread_menu_button.dart';
import '../widgets/unsaved_lyric_edits_dialog.dart';
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

class _LyricEditorScreenState extends State<LyricEditorScreen> {
  late final ProjectRepository _repository;
  late final PlaybackSessionService _playbackSession;
  late final AudioPlayerService _audioService;
  late final LyricFileExportService _exportService;
  late final LyricManualEditMarkerService _lineMarkers;
  late final ReferenceLyricTextParser _referenceParser;
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
    final revision = _editor.documentRevision;

    final input = await showReferenceAlignmentDialog(
      context,
      parser: _referenceParser,
      initialTitle: project.name,
      initialArtist: project.artist,
    );
    if (input == null || !_proofreadIsCurrent(revision)) return;

    final plan = const ApplyReferenceAlignmentUseCase().prepare(
      draft: document,
      input: input,
      protectedLineIndices: _manuallyEditedLineIndices,
      audioDuration: project.audioAsset?.duration,
    );
    if (plan.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('参考歌词中没有可用于对齐的文本行')));
      return;
    }

    final decision = await showReferenceAlignmentReview(
      context,
      document: document,
      alignment: plan.alignment,
      input: input,
      manuallyEditedLineIndices: plan.protectedLineIndices,
      timingUnavailableReason: _referenceTimingUnavailableReason(
        plan.timingUnavailableReason,
      ),
      minimumSimilarity: plan.minimumSimilarity,
    );
    if (decision == null || !_proofreadIsCurrent(revision)) return;
    if (!decision.hasChanges) return;

    final proposal = plan.apply(
      applyReferenceTiming: decision.applyReferenceTiming,
      acceptedReferenceIndices: decision.acceptedReferenceIndices,
      acceptedMissingReferenceIndices: decision.acceptedMissingReferenceIndices,
      overriddenAsrLineIndices: decision.overriddenAsrLineIndices,
    );
    final result = proposal.result;
    if (!result.hasChanges) return;

    // 时间轴校验门：允许先看预览，但严重的新冲突必须由用户明确决定保留。
    final comparison = result.timelineComparison;
    if (comparison != null && comparison.hasIntroducedSeriousIssues) {
      final keep = await _confirmIntroducedTimelineIssues(
        comparison,
        autoRepairCount: result.timelineRepairs.length,
      );
      if (keep != true || !_proofreadIsCurrent(revision)) return;
    }

    final appliedDocument = proposal.materialize(appliedAt: DateTime.now());

    final selection = result.corrections.isNotEmpty
        ? result.corrections.first.asrLineIndex
        : result.insertions.isNotEmpty
        ? result.insertions.first.asrLineIndex
        : _selectedLineIndex;
    final shouldPauseAudition = _audition.isSounding;
    setState(() {
      _editor.replaceDocument(
        appliedDocument,
        label: '应用参考歌词对齐',
        selectedLineIndex: selection,
        keepBatchSnapshot: true,
      );
      _audition.clear();
      _filter = LyricReviewFilter.all;
    });
    if (shouldPauseAudition) unawaited(_audioService.pause());

    final parts = <String>[
      if (result.corrections.isNotEmpty) '纠正 ${result.corrections.length} 行',
      if (result.insertions.isNotEmpty) '补全 ${result.insertions.length} 行',
      if (result.timingUpdatedCount > 0) '更新 ${result.timingUpdatedCount} 行时间',
      if (result.timelineRepairs.isNotEmpty)
        '自动修复时间轴 ${result.timelineRepairs.length} 处',
      if (result.skippedManuallyEditedIndices.isNotEmpty)
        '跳过 ${result.skippedManuallyEditedIndices.length} 行手动编辑',
      if (decision.overriddenAsrLineIndices.isNotEmpty)
        '覆盖 ${decision.overriddenAsrLineIndices.length} 行手动编辑',
    ];
    final timelineWarning = comparison?.hasIntroducedSeriousIssues == true
        ? '；时间轴有新增冲突，已按你的确认保留'
        : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${parts.isEmpty ? '参考歌词已对齐' : parts.join('，')}$timelineWarning。'
          '请检查后保存。',
        ),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: '撤销', onPressed: _undoAlignmentApply),
      ),
    );
  }

  Future<void> _openReferenceProofread(ProjectManifest project) async {
    final document = _editingDocument;
    if (document == null || document.lines.isEmpty) return;
    final revision = _editor.documentRevision;

    final input = await showReferenceAlignmentDialog(
      context,
      parser: _referenceParser,
      initialTitle: project.name,
      initialArtist: project.artist,
    );
    if (input == null || !_proofreadIsCurrent(revision)) return;

    final evidence = await showTimingEvidenceImportDialog(context);
    if (!_proofreadIsCurrent(revision)) return;
    final plan = const RunReferenceProofreadUseCase().build(
      draft: document,
      reference: input,
      timingEvidence: evidence,
      protectedDraftIndices: _manuallyEditedLineIndices,
      audioDuration: project.audioAsset?.duration,
    );
    if (plan.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有发现可供复核的文字差异')));
      return;
    }
    final selected = plan.hasTimingEvidence
        ? await showReferenceProofreadTimingReviewDialog(
            context,
            document: document,
            items: plan.timedItems,
          )
        : await showReferenceProofreadReviewDialog(
            context,
            document: document,
            suggestions: plan.suggestions,
          );
    if (selected == null ||
        selected.isEmpty ||
        !_proofreadIsCurrent(revision)) {
      return;
    }
    final applied = plan.apply(selected);
    _commitReferenceProofreadChange(
      applied,
      message: plan.hasTimingEvidence
          ? '已应用 ${applied.changedDraftIndices.length} 行文字与校时建议；请试听检查并保存。'
          : '已应用 ${applied.changedDraftIndices.length} 行文字纠错；现有时间戳保持不变，请试听检查并保存。',
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
      await _runProofreadV2(
        project,
        document,
        revision,
        _projectRevision ?? project.revision,
      );
    } finally {
      if (mounted) setState(() => _proofreadV2InProgress = false);
    }
  }

  bool _proofreadIsCurrent(int revision) {
    if (!mounted) return false;
    if (_editor.documentRevision == revision) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('歌词在校对期间已更改，原提案已丢弃；当前修改仍保留，请重新生成校对提案。')),
    );
    return false;
  }

  Future<void> _runProofreadV2(
    ProjectManifest project,
    LyricDocument document,
    int revision,
    int projectRevision,
  ) async {
    final options = await showProofreadV2RunOptionsDialog(
      context,
      allowProjectEvidence:
          widget.dependencies.projectProofreadEvidenceLoader != null,
    );
    if (options == null || !_proofreadIsCurrent(revision)) return;

    LyricDocument? secondaryAsr;
    final secondaryText = options.secondaryTranscriptText;
    if (secondaryText != null) {
      late final ReferenceLyricInput parsed;
      try {
        parsed = _referenceParser.parsePasted(secondaryText);
      } catch (error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法解析第二份 ASR 转写稿：$error')));
        return;
      }
      if (!parsed.timed ||
          parsed.lines.any(
            (line) => line.startTime == null || line.endTime == null,
          )) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('第二份 ASR 转写稿必须为每行都带时间戳的 LRC、SRT 或 WebVTT。'),
          ),
        );
        return;
      }
      secondaryAsr = LyricDocument(
        language: document.language,
        lines: [
          for (final line in parsed.lines)
            LyricLine(
              text: line.text,
              startTime: line.startTime!,
              endTime: line.endTime!,
              // Imported transcripts have no calibrated confidence metadata, so
              // the line is unscored rather than "60% sure".
              confidence: unscoredConfidencePlaceholder,
              confidenceSource: LyricConfidenceSource.unscored,
            ),
        ],
        globalOffset: Duration.zero,
        metadata: const {'proofreadEvidenceSource': 'secondaryAsrPaste'},
      );
    }

    ReferenceLyricInput? reference;
    if (options.useReference) {
      reference = await showReferenceAlignmentDialog(
        context,
        parser: _referenceParser,
        initialTitle: project.name,
        initialArtist: project.artist,
      );
      if (reference == null || !_proofreadIsCurrent(revision)) return;
    }

    try {
      ProjectProofreadEvidenceResult? projectEvidence;
      if (options.useProjectEvidence) {
        final loader = widget.dependencies.projectProofreadEvidenceLoader;
        if (loader == null) return;
        projectEvidence = await loader(
          projectId: project.id,
          expectedProjectRevision: projectRevision,
          draft: document,
        );
        if (!_proofreadIsCurrent(revision)) return;
        if (projectEvidence.status !=
            ProjectProofreadEvidenceStatus.available) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                LyricReviewStrings.projectEvidenceUnavailable(
                  projectEvidence.status,
                ),
              ),
              duration: const Duration(seconds: 6),
            ),
          );
          return;
        }
        secondaryAsr = projectEvidence.secondary;
      }
      // Capture before invoking the aligner, then recheck after the long run
      // and again before applying any explicitly selected reference times.
      final audioGuard = widget.dependencies.referenceAlignmentAudioGuard;
      ReferenceAlignmentAudioCheck? audioCheck;
      final asset = project.audioAsset;
      if (reference != null && options.useForcedAlignment && asset != null && audioGuard != null) {
        audioCheck = await audioGuard.capture(
          projectId: project.id,
          projectRevision: projectRevision,
          audioPath: asset.vocalPath ?? asset.originalPath,
        );
        if (!_proofreadIsCurrent(revision)) return;
      }
      final run =
          await RunProofreadV2UseCase(
            runner: widget.dependencies.forcedAlignmentRunner,
          ).build(
            draft: document,
            strategy: options.strategy,
            audioAsset: project.audioAsset,
            reference: reference,
            secondary: secondaryAsr,
            useForcedAlignment: options.useForcedAlignment,
            manuallyEditedIndices: _manuallyEditedLineIndices,
          );
      if (!_proofreadIsCurrent(revision)) return;
      final assembly = run.assembly;
      final decision = run.decision;
      final summary = run.summary;
      if (assembly.referenceAlignmentPlan?.isReady == true && audioCheck?.snapshot != null && audioGuard != null) {
        audioCheck = await audioGuard.verify(audioCheck!.snapshot!);
        if (!_proofreadIsCurrent(revision)) return;
      }
      final timingSnapshot = audioCheck?.status == ReferenceAlignmentAudioStatus.matches
          ? audioCheck?.snapshot : null;

      final selection = await showLyricProofreadV2ReviewDialog(
        context,
        summary: LyricReviewStrings.proofreadV2Summary(summary),
        explanation: [
          if (projectEvidence != null)
            '工程独立第二稿：${projectEvidence.secondaryEngine} · ${projectEvidence.capturedAtUtc!.toIso8601String()}；音频已核对，模型内容未校验。',
          LyricReviewStrings.proofreadV2Explanations(assembly.explanations),
          if (assembly.referenceAlignmentPlan case final plan?) ...[
            LyricReviewStrings.referenceAlignmentSummary(plan),
            if (plan.isReady)
              audioCheck == null
                  ? '无法校验音源；参考对齐时间仅可查看，不可采纳。'
                  : LyricReviewStrings.referenceAlignmentAudioStatus(audioCheck.status),
          ],
        ].join(' '),
        alignmentDiagnostics: assembly.alignmentDiagnostics,
        allowReferenceTimingSelection: timingSnapshot != null,
        items: assembly.items,
        droppedItems: assembly.droppedItems,
        onPreviewDraftLine: project.audioAsset == null
            ? null
            : (index) => _previewLine(project, index),
        onPreviewTimedLine: project.audioAsset == null
            ? null
            : (index, line, globalOffset) =>
                  _previewTimedLine(project, index, line, globalOffset),
        originalGlobalOffset: document.globalOffset ?? Duration.zero,
        proposedGlobalOffset:
            assembly.proposalDocument.globalOffset ?? Duration.zero,
        onPreviewAlignmentToken: project.audioAsset == null
            ? null
            : (index, token) => _previewProofreadToken(project, index, token),
      );
      if (selection == null || !_proofreadIsCurrent(revision)) return;

      Future<bool> verifyTimingSnapshot() async {
        if (selection.acceptedReferenceTimingIndices.isEmpty) return true;
        if (audioGuard == null || timingSnapshot == null) return false;
        final check = await audioGuard.verify(timingSnapshot);
        if (!_proofreadIsCurrent(revision)) return false;
        if (check.status != ReferenceAlignmentAudioStatus.matches) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(LyricReviewStrings.referenceAlignmentAudioStatus(check.status)),
            duration: const Duration(seconds: 6),
          ));
          return false;
        }
        return true;
      }
      if (!await verifyTimingSnapshot()) return;

      const composer = ProofreadV2DocumentComposer();
      final after = composer.compose(
        before: document,
        proposalDocument: assembly.proposalDocument,
        items: assembly.items,
        droppedItems: assembly.droppedItems,
        selection: selection,
        effectiveStrategy: decision.effectiveStrategy,
      );
      if (!composer.isDifferent(document, after)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('所选提案没有产生可应用的歌词或时间变化。')));
        return;
      }

      final comparison = const LyricTimelineValidator().compare(
        before: document.lines,
        after: after.lines,
        audioDuration: project.audioAsset?.duration,
        globalOffset: after.globalOffset ?? Duration.zero,
      );
      if (comparison.hasIntroducedSeriousIssues) {
        final keep = await _confirmIntroducedTimelineIssues(
          comparison,
          autoRepairCount: 0,
        );
        if (keep != true || !_proofreadIsCurrent(revision)) return;
      }
      if (!_proofreadIsCurrent(revision)) return;
      if (!await verifyTimingSnapshot()) return;
      if (!_proofreadIsCurrent(revision)) return;
      _commitProofreadV2Document(after);
    } catch (error) {
      if (!_proofreadIsCurrent(revision)) return;
      final detail = error is ReferenceTimingApplyException
          ? LyricReviewStrings.referenceTimingApplyFailure(error.reason)
          : error is ForcedAlignmentLanguageResolutionException
          ? LyricReviewStrings.forcedAlignmentLanguageError(error)
          : error is ProofreadV2MissingAudioException
          ? 'Bad state: ForcedAligner 需要工程音频及有效音频时长；请先检查音频资源。'
          : error is ForcedAlignmentResourceBusyException
          ? LyricReviewStrings.forcedAlignmentBusy
          : '$error';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法生成或应用校对提案：$detail')));
    }
  }

  void _commitProofreadV2Document(LyricDocument after) {
    final shouldPauseAudition = _audition.isSounding;
    setState(() {
      _editor.replaceDocument(
        after,
        label: '应用校对提案',
        selectedLineIndex: after.lines.isEmpty ? null : 0,
        keepBatchSnapshot: true,
        isReferenceProofread: true,
      );
      _audition.clear();
      _filter = LyricReviewFilter.all;
    });
    if (shouldPauseAudition) unawaited(_audioService.pause());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已应用智能校对提案（${after.lines.length} 行），未写入磁盘。'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: '撤销', onPressed: _undoAlignmentApply),
      ),
    );
  }

  void _commitReferenceProofreadChange(
    ReferenceProofreadAppliedChange applied, {
    required String message,
  }) {
    final shouldPauseAudition = _audition.isSounding;
    setState(() {
      _editor.replaceDocument(
        applied.after,
        label: '应用逐行纠错',
        selectedLineIndex: applied.changedDraftIndices.isEmpty
            ? _selectedLineIndex
            : applied.changedDraftIndices.first,
        keepBatchSnapshot: true,
        isReferenceProofread: true,
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

  Future<bool?> _confirmIntroducedTimelineIssues(
    LyricTimelineValidationComparison comparison, {
    required int autoRepairCount,
  }) {
    final issues = comparison.introduced
        .where((issue) => !issue.canAutoFix)
        .take(6)
        .map((issue) => '• ${issue.message}')
        .join('\n');
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: const Text('这次对齐引入了时间轴冲突'),
        content: SingleChildScrollView(
          child: Text(
            '系统已先尝试安全修复结束时间重叠：$autoRepairCount 处。\n\n'
            '以下问题在自动修复后仍无法可靠推断：\n\n$issues\n\n'
            '可以撤销本次对齐，或保留结果并逐行校准。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('撤销本次对齐'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('保留并检查'),
          ),
        ],
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

  String? _referenceTimingUnavailableReason(
    ReferenceTimingUnavailableReason? reason,
  ) {
    return switch (reason) {
      ReferenceTimingUnavailableReason.partiallyTimed =>
        '参考歌词只有部分行带时间戳，无法整体替换时间轴；本次只纠正文字并补全漏行。',
      ReferenceTimingUnavailableReason.structuralMismatch =>
        '参考歌词与当前草稿不是一一对应（存在漏行、多余行或空行），本次只纠正文字、补全漏行并保留原时间轴。',
      ReferenceTimingUnavailableReason.protectedLines =>
        '本次有手动编辑过的行，先只纠正文字以避免打乱时间轴；需要替换时间轴时请先保存并重新打开工程。',
      null => null,
    };
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
          return const _LoadingState();
        }

        if (snapshot.hasError || snapshot.data == null) {
          return _ErrorState(onRetry: () => setState(_loadProject));
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

                      return _LyricEditorContent(
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
  final Map<int, LyricReviewPriority> reviewPriorityByIndex;
  final LyricReviewQueue reviewQueue;
  final int? activeAuditionLineIndex;
  final bool auditionPlaying;
  final bool loopCurrentLineAudition;
  final ValueChanged<bool> onLoopCurrentLineAuditionChanged;
  final bool followPlayback;
  final int? selectedLineIndex;
  final LyricReviewFilter filter;
  final ValueChanged<LyricReviewFilter> onFilterChanged;
  final ValueChanged<bool> onFollowPlaybackChanged;
  final ValueChanged<int> onSelectLine;
  final void Function(int, bool) onReviewDecision;
  final VoidCallback onSave;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final bool canUndo;
  final bool canRedo;
  final String? undoLabel;
  final String? redoLabel;
  final VoidCallback onExport;
  final VoidCallback? onReferenceAlignment;
  final VoidCallback? onReferenceProofread;
  final VoidCallback? onProofreadV2;
  final VoidCallback? onUndoReferenceAlignment;
  final VoidCallback? onViewAlignmentComparison;
  final VoidCallback? onRestoreAlignment;
  final VoidCallback onAddLine;
  final VoidCallback onInsertAtPlayback;
  final ValueChanged<Duration> onSeekPlayback;
  final int focusRequestId;
  final int? focusLineIndex;
  final void Function(int, LyricLine) onUpdateLine;
  final ValueChanged<int> onDeleteLine;
  final ValueChanged<Duration> onUpdateOffset;
  final ValueChanged<int> onPreviewLine;
  final ValueChanged<int> onSetStartFromPlayback;
  final ValueChanged<int> onSetEndFromPlayback;
  final VoidCallback onTogglePlayback;
  final Set<int> manuallyEditedLineIndices;

  const _LyricEditorContent({
    required this.project,
    required this.document,
    required this.playback,
    required this.playbackBelongsToProject,
    required this.hasChanges,
    required this.reviewPriorityByIndex,
    required this.reviewQueue,
    required this.activeAuditionLineIndex,
    required this.auditionPlaying,
    required this.loopCurrentLineAudition,
    required this.onLoopCurrentLineAuditionChanged,
    required this.followPlayback,
    required this.selectedLineIndex,
    required this.filter,
    required this.onFilterChanged,
    required this.onFollowPlaybackChanged,
    required this.onSelectLine,
    required this.onReviewDecision,
    required this.onSave,
    required this.onUndo,
    required this.onRedo,
    required this.canUndo,
    required this.canRedo,
    required this.undoLabel,
    required this.redoLabel,
    required this.onExport,
    required this.onReferenceAlignment,
    required this.onReferenceProofread,
    required this.onProofreadV2,
    required this.onUndoReferenceAlignment,
    required this.onViewAlignmentComparison,
    required this.onRestoreAlignment,
    required this.onAddLine,
    required this.onInsertAtPlayback,
    required this.onSeekPlayback,
    required this.focusRequestId,
    required this.focusLineIndex,
    required this.onUpdateLine,
    required this.onDeleteLine,
    required this.onUpdateOffset,
    required this.onPreviewLine,
    required this.onSetStartFromPlayback,
    required this.onSetEndFromPlayback,
    required this.onTogglePlayback,
    this.manuallyEditedLineIndices = const {},
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

  bool _isLineReviewed(int index) =>
      const LyricReviewDecisionService().isReviewed(document, index);

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
      final include = switch (filter) {
        LyricReviewFilter.all => true,
        LyricReviewFilter.needsReview => reviewQueue.needsReview(index),
        LyricReviewFilter.lowConfidence => reviewQueue.isLowConfidence(index),
      };
      if (include) indices.add(index);
    }
    if (filter != LyricReviewFilter.all) {
      indices.sort((left, right) {
        final byPriority = (reviewPriorityByIndex[right]?.score ?? 0).compareTo(
          reviewPriorityByIndex[left]?.score ?? 0,
        );
        return byPriority != 0 ? byPriority : left.compareTo(right);
      });
    }
    return indices;
  }

  Future<void> _showInspectorSheet(
    BuildContext context,
    int index, {
    bool autofocusText = false,
  }) async {
    if (index < 0 || index >= document.lines.length) return;
    onSelectLine(index);
    final spec = AppResponsive.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.bgElevated,
      builder: (sheetContext) {
        final sheetSpec = AppResponsive.of(sheetContext);
        final heightFactor = sheetSpec.isShort ? 0.96 : 0.88;
        final isReviewed = _isLineReviewed(index);
        final canRecordDecision =
            isReviewed || reviewPriorityByIndex.containsKey(index);
        return FractionallySizedBox(
          heightFactor: heightFactor,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: spec.isCompact ? double.infinity : 720,
              ),
              child: LineInspector(
                key: ValueKey('sheet_inspector_$index'),
                index: index,
                line: document.lines[index],
                fallbackCandidate: _fallbackCandidateFor(index),
                isReviewed: isReviewed,
                onReviewDecision: canRecordDecision
                    ? (reviewed) {
                        onReviewDecision(index, reviewed);
                        Navigator.of(sheetContext).pop();
                      }
                    : null,
                isCurrentPlaybackLine:
                    playbackBelongsToProject &&
                    _currentPlaybackLineIndex() == index,
                isPlaying: playbackBelongsToProject && playback.isPlaying,
                autofocusText: autofocusText,
                onUpdate: (updated) => onUpdateLine(index, updated),
                onDelete: () {
                  onDeleteLine(index);
                  Navigator.of(sheetContext).pop();
                },
                onPreview: () => onPreviewLine(index),
                onUsePlaybackAsStart: playbackBelongsToProject
                    ? () => onSetStartFromPlayback(index)
                    : null,
                onUsePlaybackAsEnd: playbackBelongsToProject
                    ? () => onSetEndFromPlayback(index)
                    : null,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final currentPlaybackLine = _currentPlaybackLineIndex();
    final visibleIndices = _visibleIndices();
    final selectedIndex =
        selectedLineIndex != null &&
            selectedLineIndex! >= 0 &&
            selectedLineIndex! < document.lines.length
        ? selectedLineIndex
        : null;

    return PopScope(
      canPop: !hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!hasChanges) return;
        final decision = await confirmUnsavedLyricEdits(context);
        if (!context.mounted) return;
        switch (decision) {
          // "保存并返回" used to pop with `false` and call onSave(), which saved
          // the document but left the user on the editor, so the button did the
          // opposite of what it said. Saving now always ends with leaving.
          case UnsavedLyricEditsDecision.save:
            onSave();
            Navigator.of(context).pop();
          case UnsavedLyricEditsDecision.discard:
            Navigator.of(context).pop();
          case UnsavedLyricEditsDecision.stay:
            break;
        }
      },
      child: LyricEditShortcuts(
        onUndo: onUndo,
        onRedo: onRedo,
        onSave: onSave,
        child: Scaffold(
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
              if (spec.isCompactOrMedium || spec.isShort)
                LyricProofreadMenuButton(
                  compact: true,
                  onProofreadV2: onProofreadV2,
                  onReferenceAlignment: onReferenceAlignment,
                  onReferenceProofread: onReferenceProofread,
                  onViewComparison: onViewAlignmentComparison,
                  onUndoAlignment: onUndoReferenceAlignment,
                  onRestoreBackup: onRestoreAlignment,
                ),
              LyricEditorOverflowMenu(
                onUndo: canUndo ? onUndo : null,
                onRedo: canRedo ? onRedo : null,
                undoLabel: canUndo ? undoLabel : null,
                redoLabel: canRedo ? redoLabel : null,
                canExport: document.lines.isNotEmpty,
                onExport: onExport,
                onInsertAtPlayback: playbackBelongsToProject
                    ? onInsertAtPlayback
                    : null,
                onOpenPlayer: project.canPlay
                    ? () => Navigator.pushNamed(
                        context,
                        Routes.playerPath(project.id),
                      )
                    : null,
              ),
              if (hasChanges)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: spec.isCompact
                      ? IconButton.filledTonal(
                          tooltip: '保存修改',
                          onPressed: onSave,
                          icon: const Icon(Icons.save_rounded),
                        )
                      : FilledButton.icon(
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
                LyricEditorToolbar(
                  document: document,
                  playback: playback,
                  playbackBelongsToProject: playbackBelongsToProject,
                  review: reviewQueue,
                  filter: filter,
                  loopCurrentLineAudition: loopCurrentLineAudition,
                  onLoopCurrentLineAuditionChanged:
                      onLoopCurrentLineAuditionChanged,
                  followPlayback: followPlayback,
                  onFilterChanged: onFilterChanged,
                  onFollowPlaybackChanged: onFollowPlaybackChanged,
                  onUpdateOffset: onUpdateOffset,
                  onTogglePlayback: onTogglePlayback,
                  onSeekPlayback: onSeekPlayback,
                  onReferenceAlignment: onReferenceAlignment,
                  onReferenceProofread: onReferenceProofread,
                  onProofreadV2: onProofreadV2,
                  onUndoReferenceAlignment: onUndoReferenceAlignment,
                  onViewAlignmentComparison: onViewAlignmentComparison,
                  onRestoreAlignment: onRestoreAlignment,
                ),
                Expanded(
                  child: document.lines.isEmpty
                      ? _EmptyLyricsState(onAddLine: onAddLine)
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final layout = AppResponsive.fromConstraints(
                              constraints,
                            );
                            final twoPane = layout.supportsTwoPane;
                            final list = LyricListPane(
                              document: document,
                              visibleIndices: visibleIndices,
                              selectedIndex: selectedIndex,
                              currentPlaybackLine: currentPlaybackLine,
                              followPlayback: followPlayback,
                              focusRequestId: focusRequestId,
                              focusLineIndex: focusLineIndex,
                              fallbackCandidateFor: _fallbackCandidateFor,
                              reviewPriorityByIndex: reviewPriorityByIndex,
                              filter: filter,
                              activeAuditionLineIndex: activeAuditionLineIndex,
                              auditionPlaying: auditionPlaying,
                              onPreviewLine: project.audioAsset == null
                                  ? null
                                  : onPreviewLine,
                              onInsertedLineFocus: twoPane
                                  ? onSelectLine
                                  : (index) => _showInspectorSheet(
                                      context,
                                      index,
                                      autofocusText: true,
                                    ),
                              onSelectLine: twoPane
                                  ? onSelectLine
                                  : (index) =>
                                        _showInspectorSheet(context, index),
                              onUpdateLine: onUpdateLine,
                              onDeleteLine: onDeleteLine,
                              onSetStartFromPlayback: project.audioAsset == null
                                  ? null
                                  : onSetStartFromPlayback,
                              onSetEndFromPlayback: project.audioAsset == null
                                  ? null
                                  : onSetEndFromPlayback,
                              manuallyEditedLineIndices:
                                  manuallyEditedLineIndices,
                            );

                            if (!twoPane) return list;

                            return Row(
                              children: [
                                Expanded(child: list),
                                const VerticalDivider(width: 1),
                                SizedBox(
                                  width: layout.sidePanelWidth,
                                  child: InspectorPane(
                                    document: document,
                                    selectedIndex: selectedIndex,
                                    fallbackCandidate: selectedIndex == null
                                        ? null
                                        : _fallbackCandidateFor(selectedIndex),
                                    isReviewed:
                                        selectedIndex != null &&
                                        _isLineReviewed(selectedIndex),
                                    onReviewDecision:
                                        selectedIndex != null &&
                                            (_isLineReviewed(selectedIndex) ||
                                                reviewPriorityByIndex
                                                    .containsKey(selectedIndex))
                                        ? (reviewed) {
                                            onReviewDecision(
                                              selectedIndex,
                                              reviewed,
                                            );
                                          }
                                        : null,
                                    playback: playback,
                                    playbackBelongsToProject:
                                        playbackBelongsToProject,
                                    currentPlaybackLine: currentPlaybackLine,
                                    onUpdateLine: onUpdateLine,
                                    onDeleteLine: onDeleteLine,
                                    onPreviewLine: onPreviewLine,
                                    onSetStartFromPlayback:
                                        onSetStartFromPlayback,
                                    onSetEndFromPlayback: onSetEndFromPlayback,
                                    autofocusText:
                                        selectedIndex != null &&
                                        selectedIndex == focusLineIndex,
                                    focusRequestId: focusRequestId,
                                  ),
                                ),
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
        ),
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
    final spec = AppResponsive.of(context);
    final horizontalPadding = spec.pageGutter.clamp(12, 24).toDouble();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.bgElevated,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              visibleLines == totalLines
                  ? '$totalLines 行歌词'
                  : '显示 $visibleLines / $totalLines 行',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ),
          if (hasChanges && !spec.isCompact) ...[
            const SizedBox(width: AppSpacing.sm),
            const LyricTinyBadge(label: '有未保存修改', warning: true),
          ],
          const Spacer(),
          if (spec.isCompact)
            IconButton.filledTonal(
              tooltip: '添加歌词行',
              onPressed: onAddLine,
              icon: const Icon(Icons.add_rounded),
            )
          else
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
    final spec = AppResponsive.of(context);
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: EdgeInsets.all(spec.isCompact ? AppSpacing.lg : AppSpacing.xl),
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
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '可以先返回工程页运行自动识别，也可以从这里手动建立第一行歌词。',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onAddLine,
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加第一行'),
              style: FilledButton.styleFrom(
                minimumSize: Size.fromHeight(spec.minimumInteractiveExtent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
