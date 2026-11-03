import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/layout/app_responsive.dart';
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
import '../../../transcription/domain/services/asr_runtime_manager.dart';
import '../../domain/models/lyric_edit_history.dart';
import '../../domain/models/lyric_review_queue.dart';
import '../../domain/models/reference_lyric_input.dart';
import '../../domain/proofreading/asr_reference_correction_suggester.dart';
import '../../domain/proofreading/asr_first_pipeline.dart';
import '../../domain/proofreading/forced_alignment_language.dart';
import '../../domain/proofreading/forced_alignment_proofread_service.dart';
import '../../domain/proofreading/proofread_result.dart';
import '../../domain/proofreading/proofread_v2_document_composer.dart';
import '../../domain/proofreading/proofread_v2_review_assembler.dart';
import '../../domain/proofreading/proofread_strategy_selector.dart';
import '../../domain/proofreading/reference_first_pipeline.dart';
import '../../domain/proofreading/reference_token_aligner.dart';
import '../../domain/proofreading/reference_proofread_review_builder.dart';
import '../../domain/proofreading/reference_proofread_change_set.dart';
import '../../domain/services/lyric_alignment_service.dart';
import '../../domain/services/lyric_audition_window_service.dart';
import '../../domain/services/lyric_file_export_service.dart';
import '../../domain/services/lyric_manual_edit_marker_service.dart';
import '../../domain/services/lyric_review_decision_service.dart';
import '../../domain/services/lyric_review_priority_service.dart';
import '../../domain/services/lyric_timeline_insertion_service.dart';
import '../../domain/services/lyric_timeline_validator.dart';
import '../../domain/services/reference_alignment_applier.dart';
import '../../domain/services/reference_alignment_provenance_builder.dart';
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
import '../lyric_review_strings.dart';
import '../widgets/lyric_editor_atoms.dart';
import '../widgets/lyric_inspector_pane.dart';
import '../widgets/lyric_list_pane.dart';
import '../widgets/lyric_proofread_v2_dialog.dart';
import '../widgets/lyric_edit_shortcuts.dart';
import '../widgets/lyric_editor_toolbar.dart';
import '../widgets/lyric_proofread_menu_button.dart';
import '../widgets/unsaved_lyric_edits_dialog.dart';

/// 参考对齐应用前的完整内存快照，用于立即撤销（不写磁盘）。
class _AlignmentUndoSnapshot {
  final LyricDocument document;
  final Set<String> manuallyEditedLineIds;
  final int? selectedLineIndex;
  final bool hasChanges;
  final bool isReferenceProofread;

  const _AlignmentUndoSnapshot({
    required this.document,
    required this.manuallyEditedLineIds,
    required this.selectedLineIndex,
    required this.hasChanges,
    this.isReferenceProofread = false,
  });
}

class LyricEditorScreen extends StatefulWidget {
  final String projectId;

  const LyricEditorScreen({super.key, required this.projectId});

  @override
  State<LyricEditorScreen> createState() => _LyricEditorScreenState();
}

class _LyricEditorScreenState extends State<LyricEditorScreen> {
  late final ProjectRepository _repository;
  late final PlaybackSessionService _playbackSession;
  late final AudioPlayerService _audioService;
  late final LyricFileExportService _exportService;
  late final LyricManualEditMarkerService _lineMarkers;
  static const _provenance = ReferenceAlignmentProvenanceBuilder();
  late final ReferenceLyricTextParser _referenceParser;
  late Future<ProjectManifest?> _projectFuture;

  LyricDocument? _editingDocument;
  bool _hasChanges = false;
  bool _followPlayback = true;
  int? _selectedLineIndex;
  LyricReviewFilter _filter = LyricReviewFilter.all;

  /// 插入新行后递增，用于让列表/检查器知道"该聚焦这个新行"。
  int _focusRequestId = 0;
  int? _focusLineIndex;

  /// 本次编辑器会话中手动改过文字的行标识（基于稳定 lineId）；
  /// 插入/删除/对齐后标识不随索引漂移，参考对齐默认跳过这些行。
  final Set<String> _manuallyEditedLineIds = {};

  /// 最近一次参考对齐应用前的内存快照；任何后续手动编辑都会使其失效。
  _AlignmentUndoSnapshot? _alignmentUndoSnapshot;

  /// 仅当歌词文档发生变化时重新计算，避免播放进度流触发每帧风险排序。
  LyricDocument? _reviewPrioritySource;
  Duration? _reviewPriorityAudioDuration;
  LyricReviewQueue _reviewQueue = LyricReviewQueue.empty;
  final LyricEditHistory _editHistory = LyricEditHistory();
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
  Set<int> get _manuallyEditedLineIndices {
    final document = _editingDocument;
    if (document == null) return const <int>{};
    return _lineMarkers.protectedIndices(document, _manuallyEditedLineIds);
  }

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

  /// Records the document as it is *now*, before an edit mutates it.
  ///
  /// Every user-visible change calls this first, so the undo stack is a record
  /// of what the user actually did rather than of what the code happened to
  /// touch. Loading a project clears it, because undo must never walk back into
  /// a different song.
  void _recordEdit(String label, {String? mergeKey}) {
    final document = _editingDocument;
    if (document == null) return;
    _editHistory.record(
      document,
      label: label,
      mergeKey: mergeKey,
      selectedLineIndex: _selectedLineIndex,
    );
  }

  void _undo() {
    final current = _editingDocument;
    if (current == null) return;
    final snapshot = _editHistory.undo(current);
    if (snapshot == null) {
      _showEditHint('没有可撤销的修改');
      return;
    }
    setState(() {
      _editingDocument = snapshot.document;
      _selectedLineIndex =
          snapshot.selectedLineIndex != null &&
              snapshot.selectedLineIndex! >= 0 &&
              snapshot.selectedLineIndex! < snapshot.document.lines.length
          ? snapshot.selectedLineIndex
          : null;
      _hasChanges = true;
      _alignmentUndoSnapshot = null;
      _audition.clear();
      _refreshReviewQueue(snapshot.document, _reviewPriorityAudioDuration);
    });
    _showEditHint('已撤销：${snapshot.label}');
  }

  void _redo() {
    final current = _editingDocument;
    if (current == null) return;
    final snapshot = _editHistory.redo(current);
    if (snapshot == null) {
      _showEditHint('没有可重做的修改');
      return;
    }
    setState(() {
      _editingDocument = snapshot.document;
      _selectedLineIndex =
          snapshot.selectedLineIndex != null &&
              snapshot.selectedLineIndex! >= 0 &&
              snapshot.selectedLineIndex! < snapshot.document.lines.length
          ? snapshot.selectedLineIndex
          : null;
      _hasChanges = true;
      _alignmentUndoSnapshot = null;
      _audition.clear();
      _refreshReviewQueue(snapshot.document, _reviewPriorityAudioDuration);
    });
    _showEditHint('已重做：${snapshot.label}');
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
    final document = _editingDocument;
    if (document == null || index < 0 || index >= document.lines.length) {
      return;
    }
    final updated = const LyricReviewDecisionService().setReviewed(
      document,
      index,
      reviewed: reviewed,
    );
    if (identical(updated, document)) return;
    _recordEdit(
      reviewed ? '标记第 ${index + 1} 行为已复核' : '取消第 ${index + 1} 行的复核标记',
    );

    setState(() {
      _editingDocument = updated;
      _hasChanges = true;
      _alignmentUndoSnapshot = null;
      _filter = LyricReviewFilter.needsReview;
      _refreshReviewQueue(updated, project.audioAsset?.duration);
      _selectedLineIndex = _reviewPriorityByIndex.isEmpty
          ? null
          : (_reviewPriorityByIndex.values.toList()..sort((left, right) {
                  final byScore = right.score.compareTo(left.score);
                  return byScore != 0
                      ? byScore
                      : left.lineIndex.compareTo(right.lineIndex);
                }))
                .first
                .lineIndex;
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
    _repository = ServiceLocatorGlobal.I.projectRepository;
    _playbackSession = ServiceLocatorGlobal.I.playbackSessionService;
    _audioService = ServiceLocatorGlobal.I.audioPlayerService;
    _audition = LineAuditionController(
      audioService: _audioService,
      playbackSession: _playbackSession,
      onBoundaryError: _showAuditionError,
    )..addListener(_handleAuditionChanged);
    _exportService = ServiceLocatorGlobal.I.lyricFileExportService;
    _lineMarkers = const LyricManualEditMarkerService();
    _referenceParser = ReferenceLyricTextParser(
      ServiceLocatorGlobal.I.lyricFileImportService,
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
    _projectFuture = _repository.getProjectById(widget.projectId);
  }

  Future<void> _saveChanges(ProjectManifest project) async {
    final document = _editingDocument;
    if (document == null) return;

    final updated = project.copyWith(
      lyricDocument: document.copyWith(
        metadata: _lineMarkers.persist(document, _manuallyEditedLineIds),
      ),
      status: ProjectStatus.editing,
      currentStage: ProcessingStage.lyricsEdited,
    );

    await _repository.updateProject(updated);
    if (!mounted) return;

    setState(() {
      _hasChanges = false;
      _alignmentUndoSnapshot = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('歌词已保存'), duration: Duration(seconds: 2)),
    );
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

    final input = await showReferenceAlignmentDialog(
      context,
      parser: _referenceParser,
      initialTitle: project.name,
      initialArtist: project.artist,
    );
    if (input == null || !mounted) return;

    const alignmentService = LyricAlignmentService();
    const applier = ReferenceAlignmentApplier();
    final alignment = alignmentService.align(
      document: document,
      referenceLines: input.lines,
    );
    if (alignment.entries.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('参考歌词中没有可用于对齐的文本行')));
      return;
    }

    final allReferenceLinesTimed = alignment.entries.every(
      (entry) => entry.referenceHasTimestamp,
    );
    final timingUnavailableReason = _referenceTimingUnavailableReason(
      input: input,
      alignment: alignment,
      allReferenceLinesTimed: allReferenceLinesTimed,
      documentLineCount: document.lines.length,
    );

    final decision = await showReferenceAlignmentReview(
      context,
      document: document,
      alignment: alignment,
      input: input,
      manuallyEditedLineIndices: _manuallyEditedLineIndices,
      timingUnavailableReason: timingUnavailableReason,
      minimumSimilarity: applier.minimumSimilarity,
    );
    if (decision == null || !mounted) return;
    if (!decision.hasChanges) return;

    final result = applier.apply(
      document: document,
      alignment: alignment,
      applyReferenceTiming: decision.applyReferenceTiming,
      acceptedReferenceIndices: decision.acceptedReferenceIndices,
      acceptedMissingReferenceIndices: decision.acceptedMissingReferenceIndices,
      protectedLineIndices: _manuallyEditedLineIndices.difference(
        decision.overriddenAsrLineIndices,
      ),
      audioDuration: project.audioAsset?.duration,
    );
    if (!result.hasChanges) return;

    // 时间轴校验门：允许先看预览，但严重的新冲突必须由用户明确决定保留。
    final comparison = result.timelineComparison;
    if (comparison != null && comparison.hasIntroducedSeriousIssues) {
      final keep = await _confirmIntroducedTimelineIssues(
        comparison,
        autoRepairCount: result.timelineRepairs.length,
      );
      if (!mounted || keep != true) return;
    }

    final snapshot = _AlignmentUndoSnapshot(
      document: document,
      manuallyEditedLineIds: Set<String>.from(_manuallyEditedLineIds),
      selectedLineIndex: _selectedLineIndex,
      hasChanges: _hasChanges,
    );

    final appliedDocument = decision.applyReferenceTiming
        ? result.document.copyWith(globalOffset: Duration.zero)
        : result.document;
    // 对齐补入的新行缺少稳定标识，先统一补齐；手工编辑保护按标识定位，无需按索引平移。
    final appliedWithLineIds = _lineMarkers.assignMissingLineIds(
      appliedDocument,
    );

    final now = DateTime.now();
    final backupMetadata = Map<String, dynamic>.from(document.metadata)
      ..remove(kReferenceAlignmentBackupKey);
    final backupDocument = LyricDocument(
      language: document.language,
      lines: document.lines,
      globalOffset: document.globalOffset,
      metadata: backupMetadata,
    );

    final metadata = Map<String, dynamic>.from(document.metadata)
      ..[kReferenceAlignmentBackupKey] = <String, dynamic>{
        'createdAt': now.toIso8601String(),
        'reason': 'reference-alignment',
        'source': input.sourcePath == null ? 'paste' : 'file',
        if (input.sourcePath != null) 'sourcePath': input.sourcePath,
        'format': input.format,
        'timed': input.timed,
        'referenceOffsetMs': input.offset.inMilliseconds,
        'lineCount': document.lines.length,
        'document': backupDocument.toJson(),
      }
      ..[ReferenceAlignmentProvenanceBuilder.metadataKey] = _provenance.build(
        appliedAt: now,
        input: input,
        minimumSimilarity: applier.minimumSimilarity,
        applyReferenceTiming: decision.applyReferenceTiming,
        acceptedReferenceCount: decision.acceptedReferenceIndices.length,
        acceptedMissingReferenceCount:
            decision.acceptedMissingReferenceIndices.length,
        overriddenManuallyEditedCount: decision.overriddenAsrLineIndices.length,
        result: result,
        appliedDocument: appliedWithLineIds,
      );

    final shouldPauseAudition = _audition.isSounding;
    _recordEdit('应用参考歌词对齐');
    setState(() {
      _editingDocument = appliedWithLineIds.copyWith(metadata: metadata);
      _audition.clear();
      _hasChanges = true;
      _alignmentUndoSnapshot = snapshot;
      _filter = LyricReviewFilter.all;
      if (result.corrections.isNotEmpty) {
        _selectedLineIndex = result.corrections.first.asrLineIndex;
      } else if (result.insertions.isNotEmpty) {
        _selectedLineIndex = result.insertions.first.asrLineIndex;
      }
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

    final input = await showReferenceAlignmentDialog(
      context,
      parser: _referenceParser,
      initialTitle: project.name,
      initialArtist: project.artist,
    );
    if (input == null || !mounted) return;

    final evidence = await showTimingEvidenceImportDialog(context);
    if (!mounted) return;

    final protectedIndices = _manuallyEditedLineIndices;
    if (evidence != null) {
      final items = const ReferenceProofreadReviewBuilder().build(
        draft: document,
        reference: input,
        timingEvidence: evidence,
        protectedDraftIndices: protectedIndices,
        audioDuration: project.audioAsset?.duration,
      );
      if (items.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('没有发现可供复核的文字差异')));
        return;
      }
      final selected = await showReferenceProofreadTimingReviewDialog(
        context,
        document: document,
        items: items,
      );
      if (selected == null || selected.isEmpty || !mounted) return;

      final applied = const ReferenceProofreadChangeSet().apply(
        draft: document,
        proposals: items,
        selectedDraftIndices: selected,
        protectedDraftIndices: protectedIndices,
      );
      _commitReferenceProofreadChange(
        document,
        applied,
        message:
            '已应用 ${applied.changedDraftIndices.length} 行文字与校时建议；'
            '请试听检查并保存。',
      );
      return;
    }

    // No independent timing evidence supplied: keep the explicit text-only
    // workflow, preserving all existing timestamps.
    final suggestions = const AsrReferenceCorrectionSuggester()
        .suggest(
          draft: document,
          reference: input,
          protectedDraftIndices: protectedIndices,
        )
        .suggestions;
    if (suggestions.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有发现可供复核的文字差异')));
      return;
    }
    final selected = await showReferenceProofreadReviewDialog(
      context,
      document: document,
      suggestions: suggestions,
    );
    if (selected == null || selected.isEmpty || !mounted) return;

    final applied = const ReferenceProofreadChangeSet().applyTextOnly(
      draft: document,
      suggestions: suggestions,
      selectedDraftIndices: selected,
      protectedDraftIndices: protectedIndices,
    );
    _commitReferenceProofreadChange(
      document,
      applied,
      message:
          '已应用 ${applied.changedDraftIndices.length} 行文字纠错；'
          '现有时间戳保持不变，请试听检查并保存。',
    );
  }

  Future<void> _openProofreadV2(ProjectManifest project) async {
    final document = _editingDocument;
    if (document == null || document.lines.isEmpty) return;

    final options = await showProofreadV2RunOptionsDialog(context);
    if (options == null || !mounted) return;

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
      if (reference == null || !mounted) return;
    }

    try {
      final referenceCoverage = reference == null
          ? null
          : const ReferenceTokenAligner()
                .align(
                  referenceText: reference.lines
                      .map((line) => line.text)
                      .join(' '),
                  draftText: document.lines.map((line) => line.text).join(' '),
                )
                .referenceCoverage;
      final decision = const ProofreadStrategySelector().select(
        requestedStrategy: options.strategy,
        hasReference: reference != null,
        referenceCoverage: referenceCoverage,
      );

      final reviewedIndices = const LyricReviewDecisionService()
          .reviewedIndices(document);
      final protectedDraftIndices = <int>{
        ..._manuallyEditedLineIndices,
        ...reviewedIndices,
      };

      const assembler = ProofreadV2ReviewAssembler();
      late final ProofreadV2ReviewAssembly assembly;
      ForcedAlignmentProofreadOutcome? alignmentOutcome;

      if (decision.effectiveStrategy == LyricSourceStrategy.referenceFirst) {
        final input = reference;
        if (input == null) {
          throw StateError('参考歌词优先策略需要参考歌词输入。');
        }
        assembly = assembler.referenceFirst(
          draft: document,
          requestedStrategy: options.strategy,
          result: const ReferenceFirstPipeline().build(
            draft: document,
            reference: input,
            protectedDraftIndices: protectedDraftIndices,
            audioDuration: project.audioAsset?.duration,
          ),
        );
      } else {
        late final ProofreadResult result;
        if (options.useForcedAlignment) {
          final audioAsset = project.audioAsset;
          final audioDuration = audioAsset?.duration;
          if (audioAsset == null ||
              audioDuration == null ||
              audioDuration <= Duration.zero) {
            throw StateError('ForcedAligner 需要工程音频及有效音频时长；请先检查音频资源。');
          }
          final locator = ServiceLocator();
          final language = ForcedAlignmentLanguage.resolve(document.language);
          final alignmentService = ForcedAlignmentProofreadService(
            runner:
                ({
                  required String audioPath,
                  required String text,
                  required String language,
                  required Duration audioDuration,
                }) async {
                  final savedConfig = await locator.transcriptionSettingsStore
                      .load();
                  if (savedConfig == null) {
                    throw Exception('尚未配置本地转写运行时。');
                  }
                  final resolved = await locator.transcriptionProfileResolver
                      .resolve(savedConfig);
                  final runtimeStatus = await locator.asrRuntimeManager.inspect(
                    resolved.config,
                  );
                  final runtimeReady = runtimeStatus.hasReadyComponents(const {
                    AsrRuntimeComponent.qwenRuntime,
                    AsrRuntimeComponent.qwenAligner,
                  });
                  if (!runtimeReady) {
                    throw Exception(
                      'Qwen ForcedAligner 运行时未就绪；请先在转写设置中准备高质量运行环境。',
                    );
                  }
                  return locator.qwenNativeTranscriptionService.alignReference(
                    audioPath: audioPath,
                    text: text,
                    language: language,
                    audioDuration: audioDuration,
                    config: resolved.config,
                  );
                },
          );
          alignmentOutcome = await alignmentService.buildReview(
            draft: document,
            audioPath: audioAsset.vocalPath ?? audioAsset.originalPath,
            referenceText: document.lines.map((line) => line.text).join('\n'),
            language: language,
            audioDuration: audioDuration,
            secondary: secondaryAsr,
            protectedDraftIndices: protectedDraftIndices,
          );
          result = alignmentOutcome.result;
        } else {
          result = const AsrFirstPipeline().build(
            draft: document,
            secondary: secondaryAsr,
            protectedDraftIndices: protectedDraftIndices,
            audioDuration: project.audioAsset?.duration,
          );
        }
        assembly = assembler.asrFirst(
          draft: document,
          result: result,
          usedForcedAlignment: options.useForcedAlignment,
          hasSecondaryTranscript: secondaryAsr != null,
          autoFellBackToAsr: decision.autoFellBackToAsr,
          alignmentOutcome: alignmentOutcome,
        );
      }

      if (!mounted) return;
      final summary = assembler.summary(
        effectiveStrategy: decision.effectiveStrategy,
        items: assembly.items,
        droppedItems: assembly.droppedItems,
        referenceCoverage: referenceCoverage,
      );

      final selection = await showLyricProofreadV2ReviewDialog(
        context,
        summary: summary,
        explanation: assembly.explanation,
        alignmentDiagnostics: assembly.alignmentDiagnostics,
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
      if (selection == null || !mounted) return;

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
        if (!mounted || keep != true) return;
      }
      _commitProofreadV2Document(document, after);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法生成或应用校对提案：$error')));
    }
  }

  void _commitProofreadV2Document(LyricDocument before, LyricDocument after) {
    final snapshot = _AlignmentUndoSnapshot(
      document: before,
      manuallyEditedLineIds: Set<String>.from(_manuallyEditedLineIds),
      selectedLineIndex: _selectedLineIndex,
      hasChanges: _hasChanges,
      isReferenceProofread: true,
    );
    final shouldPauseAudition = _audition.isSounding;
    _recordEdit('应用校对提案');
    setState(() {
      _editingDocument = after;
      _audition.clear();
      _hasChanges = true;
      _alignmentUndoSnapshot = snapshot;
      _filter = LyricReviewFilter.all;
      _selectedLineIndex = after.lines.isEmpty ? null : 0;
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
    LyricDocument before,
    ReferenceProofreadAppliedChange applied, {
    required String message,
  }) {
    final snapshot = _AlignmentUndoSnapshot(
      document: before,
      manuallyEditedLineIds: Set<String>.from(_manuallyEditedLineIds),
      selectedLineIndex: _selectedLineIndex,
      hasChanges: _hasChanges,
      isReferenceProofread: true,
    );
    final shouldPauseAudition = _audition.isSounding;
    _recordEdit('应用逐行纠错');
    setState(() {
      _editingDocument = applied.after;
      _audition.clear();
      _hasChanges = true;
      _alignmentUndoSnapshot = snapshot;
      _filter = LyricReviewFilter.all;
      _selectedLineIndex = applied.changedDraftIndices.first;
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
    final before = _alignmentUndoSnapshot?.document;
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
    final snapshot = _alignmentUndoSnapshot;
    if (snapshot == null) return;
    final shouldPauseAudition = _audition.isSounding;
    _recordEdit('撤销参考对齐');
    setState(() {
      _editingDocument = snapshot.document;
      _audition.clear();
      _manuallyEditedLineIds
        ..clear()
        ..addAll(snapshot.manuallyEditedLineIds);
      _selectedLineIndex = snapshot.selectedLineIndex;
      _hasChanges = snapshot.hasChanges;
      _alignmentUndoSnapshot = null;
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

  String? _referenceTimingUnavailableReason({
    required ReferenceLyricInput input,
    required LyricAlignmentResult alignment,
    required bool allReferenceLinesTimed,
    required int documentLineCount,
  }) {
    if (!input.timed) return null;
    if (!allReferenceLinesTimed) {
      return '参考歌词只有部分行带时间戳，无法整体替换时间轴；本次只纠正文字并补全漏行。';
    }
    if (alignment.missingReferenceIndices.isNotEmpty ||
        alignment.unmatchedAsrIndices.isNotEmpty ||
        alignment.asrLines.length != documentLineCount) {
      return '参考歌词与当前草稿不是一一对应（存在漏行、多余行或空行），'
          '本次只纠正文字、补全漏行并保留原时间轴。';
    }
    if (_manuallyEditedLineIndices.isNotEmpty) {
      return '本次有手动编辑过的行，先只纠正文字以避免打乱时间轴；'
          '需要替换时间轴时请先保存并重新打开工程。';
    }
    return null;
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
    _recordEdit('恢复对齐前版本');
    setState(() {
      // 备份文档保留了各行的稳定标识：会话内标记按标识取交集继续生效，
      // 备份元数据中持久化的标记一并恢复；旧版本备份没有标识时自然失配。
      final restoredDocument = _lineMarkers.assignMissingLineIds(restored);
      final sessionSurvivors = _lineMarkers.prune(
        restoredDocument,
        _manuallyEditedLineIds,
      );
      _manuallyEditedLineIds
        ..clear()
        ..addAll(sessionSurvivors)
        ..addAll(_lineMarkers.restore(restoredDocument));
      _editingDocument = restoredDocument;
      _audition.clear();
      _hasChanges = true;
      _alignmentUndoSnapshot = null;
      _filter = LyricReviewFilter.all;
      final lastIndex = restored.lines.length - 1;
      if (lastIndex < 0) {
        _selectedLineIndex = null;
      } else if (_selectedLineIndex != null) {
        _selectedLineIndex = _selectedLineIndex!.clamp(0, lastIndex).toInt();
      }
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
    _recordEdit('添加歌词行');
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

      final current =
          _editingDocument ?? const LyricDocument(language: 'zh', lines: []);
      final metadata = _clearIndexedReviewMetadata(current.metadata);
      _editingDocument = _lineMarkers.assignMissingLineIds(
        current.copyWith(lines: lines, metadata: metadata),
      );
      _selectedLineIndex = lines.length - 1;
      _filter = LyricReviewFilter.all;
      _hasChanges = true;
      _alignmentUndoSnapshot = null;
    });
  }

  /// 在当前试听位置插入一行，按开始时间落到正确索引。
  void _insertLineAtPlayback() {
    final current =
        _editingDocument ?? const LyricDocument(language: 'zh', lines: []);
    final position = _timelinePositionFromPlayback();
    final insertion = const LyricTimelineInsertionService().insertAtPlayback(
      lines: current.lines,
      position: position,
    );
    final lines = List<LyricLine>.from(current.lines)
      ..insert(insertion.index, insertion.line);

    _recordEdit('在播放位置插入一行');
    setState(() {
      _editingDocument = _lineMarkers.assignMissingLineIds(
        current.copyWith(
          lines: lines,
          metadata: _clearIndexedReviewMetadata(current.metadata),
        ),
      );
      _selectedLineIndex = insertion.index;
      _filter = LyricReviewFilter.all;
      _hasChanges = true;
      _alignmentUndoSnapshot = null;
      _focusRequestId++;
      _focusLineIndex = insertion.index;
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
        setState(_audition.clear);
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
    final document = _editingDocument;
    if (document == null || index < 0 || index >= document.lines.length) {
      return;
    }

    final previousLine = document.lines[index];
    if (previousLine.text != updatedLine.text) {
      final lineId = previousLine.id;
      if (lineId != null) _manuallyEditedLineIds.add(lineId);
    }

    final active = _audition.active;
    final isActiveLine =
        active != null &&
        active.projectId == widget.projectId &&
        (active.lineId != null
            ? active.lineId == previousLine.id
            : active.lineIndex == index);
    final timingChanged =
        previousLine.startTime != updatedLine.startTime ||
        previousLine.endTime != updatedLine.endTime;
    final invalidateAudition = isActiveLine && timingChanged;
    final shouldPauseAudition = invalidateAudition && _audition.isSounding;

    // Repeated edits to one line inside the merge window are a single undo
    // step: retyping a lyric should not cost one undo per keystroke burst.
    _recordEdit('修改第 ${index + 1} 行', mergeKey: 'line:$index');
    setState(() {
      final lines = List<LyricLine>.from(document.lines);
      lines[index] = updatedLine;
      _editingDocument = document.copyWith(lines: lines);
      if (invalidateAudition) _audition.clear();
      _hasChanges = true;
      _alignmentUndoSnapshot = null;
    });
    if (shouldPauseAudition) unawaited(_audioService.pause());
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
    final document = _editingDocument;
    if (document == null || index < 0 || index >= document.lines.length) {
      return;
    }

    final removedLine = document.lines[index];
    final active = _audition.active;
    final isActiveLine =
        active != null &&
        active.projectId == widget.projectId &&
        (active.lineId != null
            ? active.lineId == removedLine.id
            : active.lineIndex == index);
    final shouldPauseAudition = isActiveLine && _audition.isSounding;

    _recordEdit('删除第 ${index + 1} 行');
    setState(() {
      final lines = List<LyricLine>.from(document.lines)..removeAt(index);
      _editingDocument = document.copyWith(
        lines: lines,
        metadata: _clearIndexedReviewMetadata(document.metadata),
      );
      if (removedLine.id != null) {
        _manuallyEditedLineIds.remove(removedLine.id);
      }
      if (isActiveLine) _audition.clear();

      _alignmentUndoSnapshot = null;
      if (lines.isEmpty) {
        _selectedLineIndex = null;
      } else if (_selectedLineIndex == index) {
        _selectedLineIndex = index.clamp(0, lines.length - 1).toInt();
      } else if (_selectedLineIndex != null && _selectedLineIndex! > index) {
        _selectedLineIndex = _selectedLineIndex! - 1;
      }
      _hasChanges = true;
    });
    if (shouldPauseAudition) unawaited(_audioService.pause());
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
    final shouldPauseAudition = _audition.isSounding;
    _recordEdit('调整全局偏移', mergeKey: 'offset');
    setState(() {
      _editingDocument = _editingDocument?.copyWith(globalOffset: offset);
      _audition.clear();
      _hasChanges = true;
      _alignmentUndoSnapshot = null;
    });
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
          setState(() => _selectedLineIndex = index);
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
        setState(() => _selectedLineIndex = index);
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
        setState(_audition.clear);
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
        if (_editingDocument == null) {
          final loaded =
              project.lyricDocument ??
              const LyricDocument(language: 'zh', lines: []);
          // 统一补齐稳定行标识，并恢复上次保存的手工编辑保护标记。
          _editingDocument = _lineMarkers.assignMissingLineIds(loaded);
          // A freshly loaded document is a new baseline: undoing across a
          // project load would restore lines from a different song.
          _editHistory.clear();
          _manuallyEditedLineIds
            ..clear()
            ..addAll(_lineMarkers.restore(_editingDocument!));
        }

        if (_editingDocument!.lines.isNotEmpty && _selectedLineIndex == null) {
          _selectedLineIndex = 0;
        }

        _refreshReviewQueue(_editingDocument!, project.audioAsset?.duration);
        final restoreProbe = const ReferenceAlignmentRestoreService()
            .probeBackup(_editingDocument!);
        final canRestore = restoreProbe is ReferenceAlignmentBackupAvailable;

        return StreamBuilder<PlaybackState>(
          stream: _audioService.stateStream,
          initialData: _audioService.currentState,
          builder: (context, playbackSnapshot) {
            final playback =
                playbackSnapshot.data ?? const PlaybackState.idle();
            final playbackBelongsToProject =
                _playbackSession.currentState.currentItem?.projectId ==
                project.id;

            return _LyricEditorContent(
              project: project,
              document: _editingDocument!,
              playback: playback,
              playbackBelongsToProject: playbackBelongsToProject,
              hasChanges: _hasChanges,
              reviewPriorityByIndex: _reviewPriorityByIndex,
              reviewQueue: _reviewQueue,
              activeAuditionLineIndex: _activeAuditionLineIndex,
              auditionPlaying: playbackBelongsToProject && playback.isPlaying,
              loopCurrentLineAudition: _audition.loopEnabled,
              onLoopCurrentLineAuditionChanged: (value) {
                setState(() => _audition.loopEnabled = value);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      value
                          ? LyricReviewStrings.loopCurrentLineEnabled
                          : LyricReviewStrings.loopCurrentLineDisabled,
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              followPlayback: _followPlayback,
              selectedLineIndex: _selectedLineIndex,
              filter: _filter,
              onFilterChanged: (value) => setState(() {
                _filter = value;
                if (value != LyricReviewFilter.needsReview) {
                  _audition.loopEnabled = false;
                }
              }),
              onFollowPlaybackChanged: (value) =>
                  setState(() => _followPlayback = value),
              onSelectLine: (index) =>
                  setState(() => _selectedLineIndex = index),
              onReviewDecision: (index, reviewed) =>
                  _setLineReviewDecision(project, index, reviewed: reviewed),
              onSave: () => _saveChanges(project),
              onUndo: _undo,
              onRedo: _redo,
              canUndo: _editHistory.canUndo,
              canRedo: _editHistory.canRedo,
              undoLabel: _editHistory.undoLabel,
              redoLabel: _editHistory.redoLabel,
              onExport: () => _exportLyrics(project),
              onReferenceAlignment: _editingDocument!.lines.isEmpty
                  ? null
                  : () => _openReferenceAlignment(project),
              onReferenceProofread: _editingDocument!.lines.isEmpty
                  ? null
                  : () => _openReferenceProofread(project),
              onProofreadV2: _editingDocument!.lines.isEmpty
                  ? null
                  : () => _openProofreadV2(project),
              onUndoReferenceAlignment: _alignmentUndoSnapshot == null
                  ? null
                  : _undoAlignmentApply,
              onViewAlignmentComparison:
                  _alignmentUndoSnapshot == null ||
                      _alignmentUndoSnapshot!.isReferenceProofread
                  ? null
                  : () => _showAlignmentComparison(project),
              onRestoreAlignment: canRestore ? _restoreAlignmentBackup : null,
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
