import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../player/domain/models/playback_state.dart';
import '../../../player/domain/services/audio_player_service.dart';
import '../../../player/domain/services/playback_session_service.dart';
import '../../../player/presentation/widgets/seekable_progress_bar.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../../transcription/data/services/forced_alignment_proofread_service.dart';
import '../../../transcription/domain/services/asr_runtime_manager.dart';
import '../../data/services/reference_lyric_text_parser.dart';
import '../../domain/models/reference_lyric_input.dart';
import '../../domain/proofreading/asr_reference_correction_suggester.dart';
import '../../domain/proofreading/asr_first_pipeline.dart';
import '../../domain/proofreading/proofread_result.dart';
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
import '../widgets/reference_alignment_backup_dialog.dart';
import '../widgets/reference_alignment_dialog.dart';
import '../widgets/reference_alignment_review.dart';
import '../widgets/reference_proofread_review_dialog.dart';
import '../widgets/reference_proofread_timing_review_dialog.dart';
import '../widgets/timing_evidence_import_dialog.dart';
import '../widgets/reference_alignment_result_comparison.dart';
import '../lyric_review_strings.dart';
import '../widgets/lyric_row_audition_button.dart';
import '../widgets/lyric_proofread_v2_dialog.dart';

enum _ReviewFilter { all, needsReview, lowConfidence, smartReview }

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

class _ActiveLineAudition {
  final String projectId;
  final int lineIndex;
  final String? lineId;
  final LyricAuditionWindow window;

  const _ActiveLineAudition({
    required this.projectId,
    required this.lineIndex,
    required this.lineId,
    required this.window,
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
  _ReviewFilter _filter = _ReviewFilter.all;

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
  Map<int, LyricReviewPriority> _reviewPriorityByIndex = const {};

  late final StreamSubscription<Duration> _auditionPositionSubscription;
  _ActiveLineAudition? _activeLineAudition;
  bool _loopCurrentLineAudition = false;
  bool _auditionBoundaryActionInFlight = false;

  int? get _activeAuditionLineIndex {
    final active = _activeLineAudition;
    final document = _editingDocument;
    if (active == null ||
        document == null ||
        active.projectId != widget.projectId ||
        _playbackSession.currentState.currentItem?.projectId !=
            active.projectId) {
      return null;
    }
    final id = active.lineId;
    if (id != null) {
      for (var index = 0; index < document.lines.length; index++) {
        if (document.lines[index].id == id) return index;
      }
      return null;
    }
    return active.lineIndex >= 0 && active.lineIndex < document.lines.length
        ? active.lineIndex
        : null;
  }

  /// 受保护行的当前索引视图：按稳定标识在现有行序中重新定位，供逐行确认使用。
  Set<int> get _manuallyEditedLineIndices {
    final document = _editingDocument;
    if (document == null) return const <int>{};
    return _lineMarkers.protectedIndices(document, _manuallyEditedLineIds);
  }

  void _refreshReviewPriorityCache(
    LyricDocument document,
    Duration? audioDuration,
  ) {
    if (identical(_reviewPrioritySource, document) &&
        _reviewPriorityAudioDuration == audioDuration) {
      return;
    }
    _reviewPrioritySource = document;
    _reviewPriorityAudioDuration = audioDuration;
    final ranked = const LyricReviewPriorityService().rank(
      document,
      audioDuration: audioDuration,
    );
    _reviewPriorityByIndex = Map<int, LyricReviewPriority>.unmodifiable({
      for (final priority in ranked) priority.lineIndex: priority,
    });
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

    setState(() {
      _editingDocument = updated;
      _hasChanges = true;
      _alignmentUndoSnapshot = null;
      _filter = _ReviewFilter.smartReview;
      _refreshReviewPriorityCache(updated, project.audioAsset?.duration);
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
              ? '已确认第 ${index + 1} 行；智能复核队列已清空。保存后会保留本次确认。'
              : '已确认第 ${index + 1} 行；已跳到下一条优先复核项（剩余 $remaining 行）。'
        : '已取消第 ${index + 1} 行的复核标记；该行已重新进入复核队列。';
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
    _auditionPositionSubscription = _audioService.positionStream.listen(
      _handleAuditionPosition,
    );
    _exportService = ServiceLocatorGlobal.I.lyricFileExportService;
    _lineMarkers = const LyricManualEditMarkerService();
    _referenceParser = ReferenceLyricTextParser(
      ServiceLocatorGlobal.I.lyricFileImportService,
    );
    _loadProject();
  }

  void _handleAuditionPosition(Duration position) {
    final active = _activeLineAudition;
    if (active == null || active.window.endAt == null) return;

    if (_playbackSession.currentState.currentItem?.projectId !=
        active.projectId) {
      if (mounted) {
        setState(() => _activeLineAudition = null);
      } else {
        _activeLineAudition = null;
      }
      return;
    }

    final playback = _audioService.currentState;
    final reachedNaturalEndWhileLooping =
        _loopCurrentLineAudition && playback.isCompleted;
    if (_auditionBoundaryActionInFlight ||
        (!playback.isPlaying && !reachedNaturalEndWhileLooping) ||
        position < active.window.endAt!) {
      return;
    }

    _auditionBoundaryActionInFlight = true;
    unawaited(_handleAuditionBoundary(active));
  }

  Future<void> _handleAuditionBoundary(_ActiveLineAudition active) async {
    try {
      final playback = _audioService.currentState;
      final reachedNaturalEndWhileLooping =
          _loopCurrentLineAudition && playback.isCompleted;
      if (!mounted ||
          !identical(_activeLineAudition, active) ||
          _playbackSession.currentState.currentItem?.projectId !=
              active.projectId ||
          (!playback.isPlaying && !reachedNaturalEndWhileLooping)) {
        return;
      }

      if (_loopCurrentLineAudition && active.window.endAt != null) {
        await _playbackSession.seek(active.window.startAt);
        if (!mounted ||
            !identical(_activeLineAudition, active) ||
            _playbackSession.currentState.currentItem?.projectId !=
                active.projectId) {
          return;
        }
        if (_loopCurrentLineAudition) {
          if (!_audioService.currentState.isPlaying) {
            await _audioService.play();
          }
        } else if (_audioService.currentState.isPlaying) {
          await _audioService.pause();
        }
      } else if (_audioService.currentState.isPlaying) {
        await _audioService.pause();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${LyricReviewStrings.auditionErrorPrefix}$error'),
          ),
        );
      }
    } finally {
      _auditionBoundaryActionInFlight = false;
    }
  }

  Future<void> _pauseAuditionOnDispose() async {
    try {
      await _audioService.pause();
    } catch (_) {
      // The app-scoped player may already be changing sources during teardown.
    }
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

    final activeAudition = _activeLineAudition;
    final shouldPauseAudition =
        activeAudition != null &&
        _playbackSession.currentState.currentItem?.projectId ==
            activeAudition.projectId &&
        _audioService.currentState.isPlaying;
    setState(() {
      _editingDocument = appliedWithLineIds.copyWith(metadata: metadata);
      _activeLineAudition = null;
      _hasChanges = true;
      _alignmentUndoSnapshot = snapshot;
      _filter = _ReviewFilter.all;
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有发现可供复核的文字差异')),
        );
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
        message: '已应用 ${applied.changedDraftIndices.length} 行文字与校时建议；'
            '请试听检查并保存。',
      );
      return;
    }

    // No independent timing evidence supplied: keep the explicit text-only
    // workflow, preserving all existing timestamps.
    final suggestions = const AsrReferenceCorrectionSuggester().suggest(
      draft: document,
      reference: input,
      protectedDraftIndices: protectedIndices,
    ).suggestions;
    if (suggestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有发现可供复核的文字差异')),
      );
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
      message: '已应用 ${applied.changedDraftIndices.length} 行文字纠错；'
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法解析第二份 ASR 转写稿：$error')),
        );
        return;
      }
      if (!parsed.timed ||
          parsed.lines.any((line) => line.startTime == null || line.endTime == null)) {
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
              // Imported transcripts have no calibrated confidence metadata.
              // Keep the evidence conservative rather than treating it as 100%.
              confidence: 60,
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

      final reviewedIndices =
          const LyricReviewDecisionService().reviewedIndices(document);
      final protectedDraftIndices = <int>{
        ..._manuallyEditedLineIndices,
        ...reviewedIndices,
      };

      late final LyricDocument proposalDocument;
      late final List<LyricProofreadV2ReviewItem> items;
      late final List<LyricProofreadV2DroppedItem> droppedItems;
      late final String strategyExplanation;

      if (decision.effectiveStrategy == LyricSourceStrategy.referenceFirst) {
        final input = reference;
        if (input == null) {
          throw StateError('参考歌词优先策略需要参考歌词输入。');
        }
        final result = const ReferenceFirstPipeline().build(
          draft: document,
          reference: input,
          protectedDraftIndices: protectedDraftIndices,
          audioDuration: project.audioAsset?.duration,
        );
        proposalDocument = result.proposedDocument.copyWith(
          globalOffset: Duration.zero,
        );
        items = [
          for (var index = 0; index < result.lines.length; index++)
            () {
              final row = result.lines[index];
              final sourceIndex = row.draftIndex;
              final original = sourceIndex != null &&
                      sourceIndex >= 0 &&
                      sourceIndex < document.lines.length
                  ? document.lines[sourceIndex]
                  : null;
              return LyricProofreadV2ReviewItem(
                proposalIndex: index,
                sourceIndex: sourceIndex,
                proposedLine: row.line,
                originalLine: original,
                verdict: switch (row.verdict) {
                  ReferenceFirstVerdictLevel.locked =>
                    LyricProofreadReviewVerdict.locked,
                  ReferenceFirstVerdictLevel.green =>
                    LyricProofreadReviewVerdict.green,
                  ReferenceFirstVerdictLevel.amber =>
                    LyricProofreadReviewVerdict.amber,
                },
                reasonLabel: row.reasons
                    .map(_proofreadV2ReferenceReasonLabel)
                    .join('、'),
              );
            }(),
        ];
        droppedItems = [
          for (final row in result.droppedLines)
            LyricProofreadV2DroppedItem(
              sourceIndex: row.draftIndex,
              line: row.line,
              reasonLabel: '未找到可靠参考匹配；默认排除，可勾选恢复',
            ),
        ];
        strategyExplanation = [
          if (options.strategy == LyricSourceStrategy.auto)
            '自动策略计算参考文本覆盖率 ${(result.tokenCoverage * 100).round()}%。',
          '参考优先会以参考行组织提案；低置信、歧义、插值时间和结构差异保持琥珀色。',
          if (result.tokenDpBudgetExceeded)
            '词级对齐达到计算预算上限，覆盖率不能作为完整证据。',
          if (result.warnings.isNotEmpty)
            '参考输入包含 ${result.warnings.length} 条冲突或警告，相关行会要求复核。',
        ].join(' ');
      } else {
        ForcedAlignmentProofreadOutcome? alignmentOutcome;
        late final ProofreadResult result;
        if (options.useForcedAlignment) {
          final audioAsset = project.audioAsset;
          final audioDuration = audioAsset?.duration;
          if (audioAsset == null || audioDuration == null ||
              audioDuration <= Duration.zero) {
            throw StateError(
              'ForcedAligner 需要工程音频及有效音频时长；请先检查音频资源。',
            );
          }
          final locator = ServiceLocator();
          final language = _forcedAlignmentLanguage(
            document.language,
          );
          final alignmentService = ForcedAlignmentProofreadService(
            runner: ({
              required String audioPath,
              required String text,
              required String language,
              required Duration audioDuration,
            }) async {
              final savedConfig = await locator.transcriptionSettingsStore.load();
              if (savedConfig == null) {
                throw Exception('尚未配置本地转写运行时。');
              }
              final resolved = await locator.transcriptionProfileResolver
                  .resolve(savedConfig);
              final runtimeStatus = await locator.asrRuntimeManager.inspect(
                resolved.config,
              );
              final runtimeReady = runtimeStatus.components.any(
                    (item) => item.component == AsrRuntimeComponent.qwenRuntime &&
                        item.state == AsrRuntimeComponentState.ready,
                  ) &&
                  runtimeStatus.components.any(
                    (item) => item.component == AsrRuntimeComponent.qwenAligner &&
                        item.state == AsrRuntimeComponentState.ready,
                  );
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
        proposalDocument = result.proposedDocument;
        items = [
          for (var index = 0; index < result.lines.length; index++)
            () {
              final row = result.lines[index];
              return LyricProofreadV2ReviewItem(
                proposalIndex: index,
                sourceIndex: index,
                proposedLine: row.line,
                originalLine: document.lines[index],
                verdict: switch (row.verdict) {
                  ProofreadVerdict.locked =>
                    LyricProofreadReviewVerdict.locked,
                  ProofreadVerdict.green => LyricProofreadReviewVerdict.green,
                  ProofreadVerdict.amber => LyricProofreadReviewVerdict.amber,
                },
                reasonLabel: [
                  ...row.reasons.map(_proofreadV2ReasonLabel),
                  if (options.useForcedAlignment && row.tokens.isNotEmpty)
                    '词级对齐 ${row.tokens.length} 词',
                  if (options.useForcedAlignment && row.tokens.isEmpty)
                    '缺少词级对齐证据',
                ].join('、'),
              );
            }(),
        ];
        droppedItems = [
          for (final row in result.droppedLines)
            LyricProofreadV2DroppedItem(
              sourceIndex: row.sourceIndex,
              line: row.line,
              reasonLabel: row.reasons.map(_proofreadV2ReasonLabel).join('、'),
            ),
        ];
        strategyExplanation = [
          decision.autoFellBackToAsr
              ? '自动策略因参考文本覆盖率低于 25% 而退回 ASR 优先。'
              : secondaryAsr == null
              ? '未提供第二份 ASR 转写稿，因此只标记当前草稿风险。'
              : '已将第二份带时间戳的转写稿作为独立证据；文本分歧仍需逐行复核。',
          'ASR 优先阶段不会猜测新时间或改写现有歌词；没有可证明的变更时，应用按钮会保持禁用。',
          if (alignmentOutcome != null && alignmentOutcome.warning != null)
            alignmentOutcome.warning!,
          if (alignmentOutcome?.alignmentAvailable == true)
            'ForcedAligner 已提供词级时间证据；这些证据仅供复核，不会直接写入歌词时间戳。',
        ].join(' ');
      }

      if (!mounted) return;
      final greenCount = items
          .where((item) => item.verdict == LyricProofreadReviewVerdict.green)
          .length;
      final amberCount = items
          .where((item) => item.verdict == LyricProofreadReviewVerdict.amber)
          .length;
      final lockedCount = items
          .where((item) => item.verdict == LyricProofreadReviewVerdict.locked)
          .length;
      final summary = [
        '策略：${_proofreadV2StrategyLabel(decision.effectiveStrategy)}',
        if (referenceCoverage != null)
          '参考覆盖率 ${(referenceCoverage * 100).round()}%',
        '绿色 $greenCount',
        '琥珀色 $amberCount',
        '受保护 $lockedCount',
        '灰色 ${droppedItems.length}',
      ].join(' · ');

      final selection = await showLyricProofreadV2ReviewDialog(
        context,
        summary: summary,
        explanation: strategyExplanation,
        items: items,
        droppedItems: droppedItems,
        onPreviewDraftLine: project.audioAsset == null
            ? null
            : (index) => _previewLine(project, index),
      );
      if (selection == null || !mounted) return;

      final after = _composeProofreadV2Document(
        before: document,
        proposalDocument: proposalDocument,
        items: items,
        droppedItems: droppedItems,
        selection: selection,
        effectiveStrategy: decision.effectiveStrategy,
      );
      final hasLineChanges =
          !_sameProofreadLines(document.lines, after.lines) ||
          document.globalOffset != after.globalOffset;
      if (!hasLineChanges) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('所选提案没有产生可应用的歌词或时间变化。')),
        );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法生成或应用校对提案：$error')),
      );
    }
  }

  LyricDocument _composeProofreadV2Document({
    required LyricDocument before,
    required LyricDocument proposalDocument,
    required List<LyricProofreadV2ReviewItem> items,
    required List<LyricProofreadV2DroppedItem> droppedItems,
    required LyricProofreadV2Selection selection,
    required LyricSourceStrategy effectiveStrategy,
  }) {
    final accepted = selection.acceptedProposalIndices;
    final droppedIndices = droppedItems.map((item) => item.sourceIndex).toSet();
    final consumedDraftIndices = <int>{};
    final candidates = <({LyricLine line, int order})>[];
    var order = 0;

    for (final item in items) {
      final shouldAccept =
          item.verdict == LyricProofreadReviewVerdict.locked ||
          accepted.contains(item.proposalIndex);
      final sourceIndex = item.sourceIndex;
      if (sourceIndex != null) {
        if (sourceIndex < 0 ||
            sourceIndex >= before.lines.length ||
            !consumedDraftIndices.add(sourceIndex)) {
          continue;
        }
        candidates.add((
          line: shouldAccept ? item.proposedLine : before.lines[sourceIndex],
          order: order++,
        ));
      } else if (shouldAccept) {
        candidates.add((line: item.proposedLine, order: order++));
      }
    }

    final restoredCandidates = <({LyricLine line, int order})>[];
    for (var index = 0; index < before.lines.length; index++) {
      if (consumedDraftIndices.contains(index)) continue;
      final shouldRestore = selection.restoredDraftIndices.contains(index);
      if (shouldRestore || !droppedIndices.contains(index)) {
        restoredCandidates.add((line: before.lines[index], order: order++));
      }
    }
    restoredCandidates.sort((left, right) {
      final byStart = left.line.startTime.compareTo(right.line.startTime);
      if (byStart != 0) return byStart;
      return left.order.compareTo(right.order);
    });
    for (final restored in restoredCandidates) {
      var insertion = 0;
      while (insertion < candidates.length &&
          candidates[insertion].line.startTime <= restored.line.startTime) {
        insertion++;
      }
      candidates.insert(insertion, restored);
    }
    final lines = candidates.map((candidate) => candidate.line).toList();

    final metadata = Map<String, dynamic>.from(before.metadata);
    const timingKey = 'timingProvenance';
    final originalProvenance = metadata[timingKey];
    final proposedProvenance = proposalDocument.metadata[timingKey];
    final timingProvenance = <String, dynamic>{
      if (originalProvenance is Map)
        ...Map<String, dynamic>.from(originalProvenance),
    };
    final acceptedChanges = items.where(
      (item) =>
          item.verdict == LyricProofreadReviewVerdict.locked ||
          accepted.contains(item.proposalIndex),
    );
    for (final item in acceptedChanges) {
      final id = item.proposedLine.id;
      if (id == null) continue;
      if (proposedProvenance is Map && proposedProvenance.containsKey(id)) {
        timingProvenance[id] = proposedProvenance[id];
      } else if (item.hasChange) {
        timingProvenance.remove(id);
      }
    }
    final outputIds = lines.map((line) => line.id).whereType<String>().toSet();
    timingProvenance.removeWhere((id, _) => !outputIds.contains(id));
    if (originalProvenance is Map || proposedProvenance is Map) {
      metadata[timingKey] = timingProvenance;
    }

    final timingChanged = acceptedChanges.any(
      (item) =>
          item.originalLine == null ||
          item.originalLine!.startTime != item.proposedLine.startTime ||
          item.originalLine!.endTime != item.proposedLine.endTime,
    );
    final offset =
        effectiveStrategy == LyricSourceStrategy.referenceFirst && timingChanged
        ? Duration.zero
        : before.globalOffset;
    final candidate = LyricDocument(
      language: before.language,
      lines: lines,
      globalOffset: offset,
      metadata: metadata,
    );
    return _lineMarkers.assignMissingLineIds(candidate);
  }

  bool _sameProofreadLines(List<LyricLine> left, List<LyricLine> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      final a = left[index];
      final b = right[index];
      if (a.id != b.id ||
          a.text != b.text ||
          a.startTime != b.startTime ||
          a.endTime != b.endTime ||
          a.isChorus != b.isChorus ||
          a.confidence != b.confidence) {
        return false;
      }
    }
    return true;
  }

  String _forcedAlignmentLanguage(String language) {
    final normalized = language.trim().toLowerCase();
    if (normalized.contains('japanese') || normalized.contains('日本') ||
        normalized.contains('日文') || normalized == 'ja' ||
        normalized.startsWith('ja-')) {
      return 'Japanese';
    }
    if (normalized.contains('chinese') || normalized.contains('中文') ||
        normalized.contains('汉语') || normalized == 'zh' ||
        normalized.startsWith('zh-')) {
      return 'Chinese';
    }
    if (normalized.contains('english') || normalized.contains('英文') ||
        normalized == 'en' || normalized.startsWith('en-')) {
      return 'English';
    }
    throw StateError(
      '无法从工程语言“$language”确定 ForcedAligner 语言；请将工程语言设为中文、英文或日文。',
    );
  }

  String _proofreadV2StrategyLabel(LyricSourceStrategy strategy) {
    return switch (strategy) {
      LyricSourceStrategy.referenceFirst => '参考歌词优先',
      LyricSourceStrategy.asrFirst => 'ASR 优先',
      LyricSourceStrategy.auto => '自动选择',
    };
  }

  String _proofreadV2ReferenceReasonLabel(ReferenceFirstReason reason) {
    return switch (reason) {
      ReferenceFirstReason.lowConfidenceAlignment => '对齐置信度低',
      ReferenceFirstReason.ambiguousAlignment => '对齐存在歧义',
      ReferenceFirstReason.structuralMismatch => '行结构不匹配',
      ReferenceFirstReason.referenceTimestamp => '参考时间戳',
      ReferenceFirstReason.mappedAsrTiming => '沿用 ASR 时间',
      ReferenceFirstReason.interpolatedTiming => '插值时间需复核',
      ReferenceFirstReason.estimatedTailTiming => '尾部估算时间需复核',
      ReferenceFirstReason.timelineAdjusted => '时间轴已调整，需复核',
      ReferenceFirstReason.protectedLine => '手动编辑保护',
      ReferenceFirstReason.referenceImportWarning => '参考输入含警告',
    };
  }

  String _proofreadV2ReasonLabel(ProofreadReason reason) {
    return switch (reason) {
      ProofreadReason.asrAgreement => 'ASR 一致',
      ProofreadReason.asrDisagreement => 'ASR 不一致',
      ProofreadReason.lowConfidence => '置信度低',
      ProofreadReason.referenceCorrection => '参考文本纠正',
      ProofreadReason.ambiguousAlignment => '对齐存在歧义',
      ProofreadReason.structuralMismatch => '行结构不匹配',
      ProofreadReason.repeatedSegment => '疑似重复片段',
      ProofreadReason.suspectedHallucination => '疑似未演唱内容',
      ProofreadReason.missingReferenceLine => '参考歌词缺行',
      ProofreadReason.interpolatedTiming => '插值时间需复核',
      ProofreadReason.estimatedTiming => '估算时间需复核',
      ProofreadReason.timingAdjusted => '时间轴已调整',
      ProofreadReason.timingConflict => '时间轴冲突',
      ProofreadReason.protectedLine => '手动编辑保护',
      ProofreadReason.importWarning => '导入含警告',
      ProofreadReason.noTimingEvidence => '缺乏时间证据',
    };
  }

  void _commitProofreadV2Document(
    LyricDocument before,
    LyricDocument after,
  ) {
    final snapshot = _AlignmentUndoSnapshot(
      document: before,
      manuallyEditedLineIds: Set<String>.from(_manuallyEditedLineIds),
      selectedLineIndex: _selectedLineIndex,
      hasChanges: _hasChanges,
      isReferenceProofread: true,
    );
    final activeAudition = _activeLineAudition;
    final shouldPauseAudition = activeAudition != null &&
        _playbackSession.currentState.currentItem?.projectId ==
            activeAudition.projectId &&
        _audioService.currentState.isPlaying;
    setState(() {
      _editingDocument = after;
      _activeLineAudition = null;
      _hasChanges = true;
      _alignmentUndoSnapshot = snapshot;
      _filter = _ReviewFilter.all;
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
    final activeAudition = _activeLineAudition;
    final shouldPauseAudition = activeAudition != null &&
        _playbackSession.currentState.currentItem?.projectId ==
            activeAudition.projectId &&
        _audioService.currentState.isPlaying;
    setState(() {
      _editingDocument = applied.after;
      _activeLineAudition = null;
      _hasChanges = true;
      _alignmentUndoSnapshot = snapshot;
      _filter = _ReviewFilter.all;
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
    final activeAudition = _activeLineAudition;
    final shouldPauseAudition =
        activeAudition != null &&
        _playbackSession.currentState.currentItem?.projectId ==
            activeAudition.projectId &&
        _audioService.currentState.isPlaying;
    setState(() {
      _editingDocument = snapshot.document;
      _activeLineAudition = null;
      _manuallyEditedLineIds
        ..clear()
        ..addAll(snapshot.manuallyEditedLineIds);
      _selectedLineIndex = snapshot.selectedLineIndex;
      _hasChanges = snapshot.hasChanges;
      _alignmentUndoSnapshot = null;
      _filter = _ReviewFilter.all;
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

    final activeAudition = _activeLineAudition;
    final shouldPauseAudition =
        activeAudition != null &&
        _playbackSession.currentState.currentItem?.projectId ==
            activeAudition.projectId &&
        _audioService.currentState.isPlaying;
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
      _activeLineAudition = null;
      _hasChanges = true;
      _alignmentUndoSnapshot = null;
      _filter = _ReviewFilter.all;
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
      _filter = _ReviewFilter.all;
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

    setState(() {
      _editingDocument = _lineMarkers.assignMissingLineIds(
        current.copyWith(
          lines: lines,
          metadata: _clearIndexedReviewMetadata(current.metadata),
        ),
      );
      _selectedLineIndex = insertion.index;
      _filter = _ReviewFilter.all;
      _hasChanges = true;
      _alignmentUndoSnapshot = null;
      _focusRequestId++;
      _focusLineIndex = insertion.index;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已在 ${_formatDuration(position)} 插入歌词行'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 编辑器内跳转：先暂停，避免拖动后仍在播放而错过目标位置。
  Future<void> _seekPlayback(Duration position) async {
    try {
      if (_activeLineAudition != null && mounted) {
        setState(() => _activeLineAudition = null);
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

    final active = _activeLineAudition;
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
    final shouldPauseAudition =
        invalidateAudition &&
        _playbackSession.currentState.currentItem?.projectId ==
            active.projectId &&
        _audioService.currentState.isPlaying;

    setState(() {
      final lines = List<LyricLine>.from(document.lines);
      lines[index] = updatedLine;
      _editingDocument = document.copyWith(lines: lines);
      if (invalidateAudition) _activeLineAudition = null;
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
    final active = _activeLineAudition;
    final isActiveLine =
        active != null &&
        active.projectId == widget.projectId &&
        (active.lineId != null
            ? active.lineId == removedLine.id
            : active.lineIndex == index);
    final shouldPauseAudition =
        isActiveLine &&
        _playbackSession.currentState.currentItem?.projectId ==
            active.projectId &&
        _audioService.currentState.isPlaying;

    setState(() {
      final lines = List<LyricLine>.from(document.lines)..removeAt(index);
      _editingDocument = document.copyWith(
        lines: lines,
        metadata: _clearIndexedReviewMetadata(document.metadata),
      );
      if (removedLine.id != null) {
        _manuallyEditedLineIds.remove(removedLine.id);
      }
      if (isActiveLine) _activeLineAudition = null;

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
    final active = _activeLineAudition;
    final shouldPauseAudition =
        active != null &&
        _playbackSession.currentState.currentItem?.projectId ==
            active.projectId &&
        _audioService.currentState.isPlaying;
    setState(() {
      _editingDocument = _editingDocument?.copyWith(globalOffset: offset);
      _activeLineAudition = null;
      _hasChanges = true;
      _alignmentUndoSnapshot = null;
    });
    if (shouldPauseAudition) unawaited(_audioService.pause());
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

    final line = document.lines[index];
    final active = _activeLineAudition;
    final currentItem = _playbackSession.currentState.currentItem;
    final sameAudition =
        active != null &&
        active.projectId == project.id &&
        (active.lineId != null
            ? active.lineId == line.id
            : active.lineIndex == index);
    final playbackBelongsToProject = currentItem?.projectId == project.id;
    final playback = _audioService.currentState;

    try {
      if (sameAudition && playbackBelongsToProject) {
        if (playback.isPlaying) {
          await _audioService.pause();
          return;
        }
        final endAt = active.window.endAt;
        final canResume =
            playback.position >= active.window.startAt &&
            (endAt == null || playback.position < endAt);
        if (canResume) {
          await _audioService.play();
          return;
        }
      }

      await _startLineAudition(project, index, document, audioAsset);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${LyricReviewStrings.auditionErrorPrefix}$error'),
        ),
      );
    }
  }

  Future<void> _startLineAudition(
    ProjectManifest project,
    int index,
    LyricDocument document,
    AudioAsset audioAsset,
  ) async {
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

    if (!window.canAudition) {
      final active = _activeLineAudition;
      final shouldPauseAudition =
          active != null &&
          _playbackSession.currentState.currentItem?.projectId ==
              active.projectId &&
          _audioService.currentState.isPlaying;
      if (active != null && mounted) {
        setState(() => _activeLineAudition = null);
      }
      if (shouldPauseAudition) unawaited(_audioService.pause());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(LyricReviewStrings.auditionInvalidStart)),
      );
      return;
    }

    try {
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

      await _playbackSession.seek(window.startAt);
      final audition = _ActiveLineAudition(
        projectId: project.id,
        lineIndex: index,
        lineId: document.lines[index].id,
        window: window,
      );
      if (!mounted) return;
      setState(() {
        _activeLineAudition = audition;
        _selectedLineIndex = index;
      });
      if (!_audioService.currentState.isPlaying) {
        await _audioService.play();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _activeLineAudition = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${LyricReviewStrings.auditionErrorPrefix}$error'),
        ),
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

      final active = _activeLineAudition;
      final playback = _audioService.currentState;
      if (active != null &&
          !playback.isPlaying &&
          active.window.endAt != null &&
          playback.position >= active.window.endAt!) {
        // The editor-wide transport resumes the whole track after a bounded
        // line audition has completed; the row button remains the replay action.
        setState(() => _activeLineAudition = null);
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
          _manuallyEditedLineIds
            ..clear()
            ..addAll(_lineMarkers.restore(_editingDocument!));
        }

        if (_editingDocument!.lines.isNotEmpty && _selectedLineIndex == null) {
          _selectedLineIndex = 0;
        }

        _refreshReviewPriorityCache(
          _editingDocument!,
          project.audioAsset?.duration,
        );
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
              activeAuditionLineIndex: _activeAuditionLineIndex,
              auditionPlaying: playbackBelongsToProject && playback.isPlaying,
              loopCurrentLineAudition: _loopCurrentLineAudition,
              onLoopCurrentLineAuditionChanged: (value) {
                setState(() => _loopCurrentLineAudition = value);
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
                if (value != _ReviewFilter.smartReview) {
                  _loopCurrentLineAudition = false;
                }
              }),
              onFollowPlaybackChanged: (value) =>
                  setState(() => _followPlayback = value),
              onSelectLine: (index) =>
                  setState(() => _selectedLineIndex = index),
              onReviewDecision: (index, reviewed) =>
                  _setLineReviewDecision(project, index, reviewed: reviewed),
              onSave: () => _saveChanges(project),
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
              onViewAlignmentComparison: _alignmentUndoSnapshot == null ||
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
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    unawaited(_auditionPositionSubscription.cancel());
    final active = _activeLineAudition;
    if (active != null &&
        _playbackSession.currentState.currentItem?.projectId ==
            active.projectId &&
        _audioService.currentState.isPlaying) {
      unawaited(_pauseAuditionOnDispose());
    }
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
  final int? activeAuditionLineIndex;
  final bool auditionPlaying;
  final bool loopCurrentLineAudition;
  final ValueChanged<bool> onLoopCurrentLineAuditionChanged;
  final bool followPlayback;
  final int? selectedLineIndex;
  final _ReviewFilter filter;
  final ValueChanged<_ReviewFilter> onFilterChanged;
  final ValueChanged<bool> onFollowPlaybackChanged;
  final ValueChanged<int> onSelectLine;
  final void Function(int, bool) onReviewDecision;
  final VoidCallback onSave;
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

  const _LyricEditorContent({
    required this.project,
    required this.document,
    required this.playback,
    required this.playbackBelongsToProject,
    required this.hasChanges,
    required this.reviewPriorityByIndex,
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

  bool _needsReview(int index) {
    if (_isLineReviewed(index)) return false;
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
        _ReviewFilter.smartReview => reviewPriorityByIndex.containsKey(index),
      };
      if (include) indices.add(index);
    }
    if (filter == _ReviewFilter.smartReview) {
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
              child: _LineInspector(
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
    final lowConfidenceCount = document.lines
        .where((line) => line.confidence < 70)
        .length;
    final reviewCount = List<int>.generate(
      document.lines.length,
      (i) => i,
    ).where(_needsReview).length;
    final currentPlaybackLine = _currentPlaybackLineIndex();
    final visibleIndices = _visibleIndices();
    final selectedIndex =
        selectedLineIndex != null &&
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
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
        actions: [
          if ((spec.isCompactOrMedium || spec.isShort) &&
              onReferenceAlignment != null)
            IconButton(
              tooltip: '参考歌词纠正',
              onPressed: onReferenceAlignment,
              icon: const Icon(Icons.auto_fix_high_rounded),
            ),
          if ((spec.isCompactOrMedium || spec.isShort) &&
              onReferenceProofread != null)
            IconButton(
              tooltip: '逐行智能纠错（保留时间戳）',
              onPressed: onReferenceProofread,
              icon: const Icon(Icons.spellcheck_rounded),
            ),
          if ((spec.isCompactOrMedium || spec.isShort) &&
              onViewAlignmentComparison != null)
            IconButton(
              tooltip: '查看本次逐行对比',
              onPressed: onViewAlignmentComparison,
              icon: const Icon(Icons.compare_arrows_rounded),
            ),
          if ((spec.isCompactOrMedium || spec.isShort) &&
              onUndoReferenceAlignment != null)
            IconButton(
              tooltip: '撤销本次参考对齐',
              onPressed: onUndoReferenceAlignment,
              icon: const Icon(Icons.undo_rounded),
            ),
          if ((spec.isCompactOrMedium || spec.isShort) &&
              onRestoreAlignment != null)
            IconButton(
              tooltip: '恢复对齐前版本',
              onPressed: onRestoreAlignment,
              icon: const Icon(Icons.history_rounded),
            ),
          if (document.lines.isNotEmpty)
            IconButton(
              tooltip: '导出 LRC',
              onPressed: onExport,
              icon: const Icon(Icons.download_rounded),
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
            _EditorToolbar(
              document: document,
              playback: playback,
              playbackBelongsToProject: playbackBelongsToProject,
              lowConfidenceCount: lowConfidenceCount,
              reviewCount: reviewCount,
              smartReviewCount: reviewPriorityByIndex.length,
              filter: filter,
              loopCurrentLineAudition: loopCurrentLineAudition,
              onLoopCurrentLineAuditionChanged:
                  onLoopCurrentLineAuditionChanged,
              followPlayback: followPlayback,
              onFilterChanged: onFilterChanged,
              onFollowPlaybackChanged: onFollowPlaybackChanged,
              onUpdateOffset: onUpdateOffset,
              onTogglePlayback: onTogglePlayback,
              onInsertAtPlayback: playbackBelongsToProject
                  ? onInsertAtPlayback
                  : null,
              onSeekPlayback: onSeekPlayback,
              onReferenceAlignment: onReferenceAlignment,
              onReferenceProofread: onReferenceProofread,
              onProofreadV2: onProofreadV2,
              onUndoReferenceAlignment: onUndoReferenceAlignment,
              onViewAlignmentComparison: onViewAlignmentComparison,
              onRestoreAlignment: onRestoreAlignment,
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
                        final layout = AppResponsive.fromConstraints(
                          constraints,
                        );
                        final twoPane = layout.supportsTwoPane;
                        final list = _LyricListPane(
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
                              : (index) => _showInspectorSheet(context, index),
                        );

                        if (!twoPane) return list;

                        return Row(
                          children: [
                            Expanded(child: list),
                            const VerticalDivider(width: 1),
                            SizedBox(
                              width: layout.sidePanelWidth,
                              child: _InspectorPane(
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
                                            reviewPriorityByIndex.containsKey(
                                              selectedIndex,
                                            ))
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
                                onSetStartFromPlayback: onSetStartFromPlayback,
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
              onInsertAtPlayback: playbackBelongsToProject
                  ? onInsertAtPlayback
                  : null,
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
  final int smartReviewCount;
  final _ReviewFilter filter;
  final bool loopCurrentLineAudition;
  final ValueChanged<bool> onLoopCurrentLineAuditionChanged;
  final bool followPlayback;
  final ValueChanged<_ReviewFilter> onFilterChanged;
  final ValueChanged<bool> onFollowPlaybackChanged;
  final ValueChanged<Duration> onUpdateOffset;
  final VoidCallback onTogglePlayback;
  final VoidCallback? onInsertAtPlayback;
  final ValueChanged<Duration> onSeekPlayback;
  final VoidCallback? onReferenceAlignment;
  final VoidCallback? onReferenceProofread;
  final VoidCallback? onProofreadV2;
  final VoidCallback? onUndoReferenceAlignment;
  final VoidCallback? onViewAlignmentComparison;
  final VoidCallback? onRestoreAlignment;
  final VoidCallback? onOpenPlayer;

  const _EditorToolbar({
    required this.document,
    required this.playback,
    required this.playbackBelongsToProject,
    required this.lowConfidenceCount,
    required this.reviewCount,
    required this.smartReviewCount,
    required this.filter,
    required this.loopCurrentLineAudition,
    required this.onLoopCurrentLineAuditionChanged,
    required this.followPlayback,
    required this.onFilterChanged,
    required this.onFollowPlaybackChanged,
    required this.onUpdateOffset,
    required this.onTogglePlayback,
    required this.onInsertAtPlayback,
    required this.onSeekPlayback,
    required this.onReferenceAlignment,
    required this.onReferenceProofread,
    required this.onProofreadV2,
    required this.onUndoReferenceAlignment,
    required this.onViewAlignmentComparison,
    required this.onRestoreAlignment,
    required this.onOpenPlayer,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final offset = document.globalOffset ?? Duration.zero;
    final compactControls = spec.isCompactOrMedium || spec.isShort;
    final horizontalPadding = spec.pageGutter.clamp(12, 24).toDouble();

    Widget adaptiveControls(List<Widget> children) {
      if (!compactControls) {
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: children,
        );
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) const SizedBox(width: AppSpacing.sm),
              children[index],
            ],
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        AppSpacing.sm,
        horizontalPadding,
        AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.bgElevated,
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          adaptiveControls([
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
            Tooltip(
              message: '按低置信度、双引擎分歧、可疑重复和时间轴异常排序。分值仅表示复核优先级，不代表错误概率。',
              child: ChoiceChip(
                selected: filter == _ReviewFilter.smartReview,
                onSelected: (_) => onFilterChanged(_ReviewFilter.smartReview),
                label: Text('智能复核 $smartReviewCount'),
              ),
            ),
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
              onSelected: (_) => onFilterChanged(_ReviewFilter.lowConfidence),
              label: const Text('低置信度'),
            ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          adaptiveControls([
            SizedBox(
              width: spec.minimumInteractiveExtent,
              height: spec.minimumInteractiveExtent,
              child: IconButton(
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
            ),
            if (!playbackBelongsToProject)
              Text(
                '尚未开始试听',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            if (!spec.isCompactOrMedium)
              Tooltip(
                message: onInsertAtPlayback == null
                    ? '先试听本工程后可在当前时间插入'
                    : '在当前试听时间插入一行',
                child: FilledButton.tonalIcon(
                  onPressed: onInsertAtPlayback,
                  icon: const Icon(Icons.playlist_add_rounded, size: 18),
                  label: const Text('在播放位置插入'),
                ),
              ),
            if (!compactControls)
              Tooltip(
                message: onReferenceAlignment == null
                    ? '先导入或生成歌词草稿'
                    : '用参考歌词纠正 ASR 草稿',
                child: FilledButton.tonalIcon(
                  onPressed: onReferenceAlignment,
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                  label: const Text('参考歌词纠正'),
                ),
              ),
            if (!compactControls)
              Tooltip(
                message: onReferenceProofread == null
                    ? '先导入或生成歌词草稿'
                    : '逐行审核参考歌词建议；仅替换文字并保留当前时间戳',
                child: OutlinedButton.icon(
                  onPressed: onReferenceProofread,
                  icon: const Icon(Icons.spellcheck_rounded, size: 18),
                  label: const Text('逐行智能纠错'),
                ),
              ),
            Tooltip(
              message: onProofreadV2 == null
                  ? '先导入或生成歌词草稿'
                  : '生成不自动写盘的校对提案；逐行对比后再明确应用',
              child: FilledButton.tonalIcon(
                onPressed: onProofreadV2,
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('智能校对 V2'),
              ),
            ),
            if (!compactControls && onViewAlignmentComparison != null)
              OutlinedButton.icon(
                onPressed: onViewAlignmentComparison,
                icon: const Icon(Icons.compare_arrows_rounded, size: 18),
                label: const Text('查看逐行对比'),
              ),
            if (!compactControls && onUndoReferenceAlignment != null)
              Tooltip(
                message: '撤销最近一次参考对齐（未保存前有效）',
                child: FilledButton.tonalIcon(
                  onPressed: onUndoReferenceAlignment,
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: const Text('撤销最近更改'),
                ),
              ),
            if (!compactControls && onRestoreAlignment != null)
              Tooltip(
                message: '恢复参考歌词对齐前的歌词快照，需二次确认',
                child: FilledButton.tonalIcon(
                  onPressed: onRestoreAlignment,
                  icon: const Icon(Icons.history_rounded, size: 18),
                  label: const Text('恢复对齐前版本'),
                ),
              ),
            if (filter == _ReviewFilter.smartReview)
              Tooltip(
                message: LyricReviewStrings.loopCurrentLineHelp,
                child: FilterChip(
                  selected: loopCurrentLineAudition,
                  onSelected: onLoopCurrentLineAuditionChanged,
                  avatar: const Icon(Icons.repeat_rounded, size: 16),
                  label: const Text(LyricReviewStrings.loopCurrentLineLabel),
                ),
              ),
            FilterChip(
              selected: followPlayback,
              onSelected: onFollowPlaybackChanged,
              avatar: Icon(
                followPlayback
                    ? Icons.my_location_rounded
                    : Icons.location_disabled_rounded,
                size: 16,
              ),
              label: const Text('跟随播放'),
            ),
            if (onOpenPlayer != null)
              TextButton.icon(
                onPressed: onOpenPlayer,
                icon: const Icon(Icons.open_in_full_rounded, size: 17),
                label: Text(spec.isCompact ? '播放器' : '完整播放器'),
              ),
            Text(
              '全局偏移',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: AppColors.textTertiary),
            ),
            _OffsetButton(
              label: '-100ms',
              onPressed: () =>
                  onUpdateOffset(offset - const Duration(milliseconds: 100)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.bgSurface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
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
              onPressed: () =>
                  onUpdateOffset(offset + const Duration(milliseconds: 100)),
            ),
            if (offset != Duration.zero)
              TextButton(
                onPressed: () => onUpdateOffset(Duration.zero),
                child: const Text('归零'),
              ),
          ]),
          if (playbackBelongsToProject) ...[
            const SizedBox(height: AppSpacing.xs),
            SeekableProgressBar(
              state: playback,
              onSeek: onSeekPlayback,
              compact: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _LyricListPane extends StatefulWidget {
  final LyricDocument document;
  final List<int> visibleIndices;
  final Map<int, LyricReviewPriority> reviewPriorityByIndex;
  final _ReviewFilter filter;
  final int? activeAuditionLineIndex;
  final bool auditionPlaying;
  final int? selectedIndex;
  final int? currentPlaybackLine;
  final bool followPlayback;
  final int focusRequestId;
  final int? focusLineIndex;
  final Map<String, dynamic>? Function(int) fallbackCandidateFor;
  final ValueChanged<int>? onPreviewLine;
  final ValueChanged<int> onInsertedLineFocus;
  final ValueChanged<int> onSelectLine;

  const _LyricListPane({
    required this.document,
    required this.visibleIndices,
    required this.reviewPriorityByIndex,
    required this.filter,
    required this.activeAuditionLineIndex,
    required this.auditionPlaying,
    required this.selectedIndex,
    required this.currentPlaybackLine,
    required this.followPlayback,
    required this.focusRequestId,
    required this.focusLineIndex,
    required this.fallbackCandidateFor,
    required this.onPreviewLine,
    required this.onInsertedLineFocus,
    required this.onSelectLine,
  });

  @override
  State<_LyricListPane> createState() => _LyricListPaneState();
}

class _LyricListPaneState extends State<_LyricListPane> {
  static const double _estimatedRowExtent = 68;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scheduleFollow();
    if (widget.focusRequestId > 0) {
      _scheduleInsertedLineFocus();
    }
  }

  @override
  void didUpdateWidget(covariant _LyricListPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusRequestId != widget.focusRequestId) {
      _scheduleInsertedLineFocus();
    }
    final visibleIndicesChanged = !_sameIndices(
      oldWidget.visibleIndices,
      widget.visibleIndices,
    );
    if (widget.filter == _ReviewFilter.smartReview &&
        (oldWidget.filter != widget.filter || visibleIndicesChanged)) {
      _scheduleScrollToTop();
    } else if (widget.filter != _ReviewFilter.smartReview &&
        widget.followPlayback &&
        (!oldWidget.followPlayback ||
            oldWidget.currentPlaybackLine != widget.currentPlaybackLine ||
            visibleIndicesChanged)) {
      _scheduleFollow();
    }
  }

  bool _sameIndices(List<int> left, List<int> right) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  void _scheduleInsertedLineFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = widget.focusLineIndex;
      if (index != null) widget.onInsertedLineFocus(index);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleScrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_scrollController.offset < 1) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _scheduleFollow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !widget.followPlayback ||
          widget.filter == _ReviewFilter.smartReview ||
          !_scrollController.hasClients) {
        return;
      }
      final current = widget.currentPlaybackLine;
      if (current == null) return;
      final visiblePosition = widget.visibleIndices.indexOf(current);
      if (visiblePosition < 0) return;
      final position = _scrollController.position;
      final rawTarget =
          visiblePosition * _estimatedRowExtent -
          position.viewportDimension * 0.42;
      final target = rawTarget
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((_scrollController.offset - target).abs() < 20) return;
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.visibleIndices.isEmpty) {
      if (widget.filter == _ReviewFilter.smartReview) {
        return _SmartReviewEmptyState(
          reviewedCount: const LyricReviewDecisionService()
              .reviewedIndices(widget.document)
              .length,
        );
      }
      return const _FilteredEmptyState();
    }

    final spec = AppResponsive.of(context);
    final padding = spec.isCompact
        ? 8.0
        : spec.pageGutter.clamp(12, 24).toDouble();

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.all(padding),
      itemCount: widget.visibleIndices.length,
      itemBuilder: (context, visibleIndex) {
        final index = widget.visibleIndices[visibleIndex];
        final line = widget.document.lines[index];
        final candidate = widget.fallbackCandidateFor(index);
        return _LyricReviewRow(
          index: index,
          line: line,
          fallbackCandidate: candidate,
          isReviewed: const LyricReviewDecisionService().isReviewed(
            widget.document,
            index,
          ),
          priority: widget.reviewPriorityByIndex[index],
          selected: widget.selectedIndex == index,
          playing: widget.currentPlaybackLine == index,
          hasAudio: widget.onPreviewLine != null,
          auditionIsPlaying:
              widget.auditionPlaying && widget.activeAuditionLineIndex == index,
          onPreview: widget.onPreviewLine == null
              ? null
              : () => widget.onPreviewLine!(index),
          onTap: () => widget.onSelectLine(index),
        );
      },
    );
  }
}

class _LyricReviewRow extends StatelessWidget {
  final int index;
  final LyricLine line;
  final Map<String, dynamic>? fallbackCandidate;
  final bool isReviewed;
  final LyricReviewPriority? priority;
  final bool selected;
  final bool playing;
  final bool hasAudio;
  final bool auditionIsPlaying;
  final VoidCallback? onPreview;
  final VoidCallback onTap;

  const _LyricReviewRow({
    required this.index,
    required this.line,
    required this.fallbackCandidate,
    required this.isReviewed,
    required this.priority,
    required this.selected,
    required this.playing,
    required this.hasAudio,
    required this.auditionIsPlaying,
    required this.onPreview,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final needsReview =
        line.confidence < 70 ||
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
            constraints: BoxConstraints(
              minHeight: spec.minimumInteractiveExtent,
            ),
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
                  width: spec.isCompact ? 28 : 34,
                  child: playing
                      ? const Icon(
                          Icons.graphic_eq_rounded,
                          size: 18,
                          color: AppColors.accent,
                        )
                      : Text(
                          '${index + 1}',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: AppColors.textTertiary),
                        ),
                ),
                LyricRowAuditionButton(
                  hasAudio: hasAudio,
                  isPlaying: auditionIsPlaying,
                  onPressed: onPreview,
                ),
                if (hasAudio) const SizedBox(width: AppSpacing.xs),
                SizedBox(
                  width: spec.isCompact ? 68 : 82,
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
                    maxLines: spec.isCompact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: line.text.trim().isEmpty
                          ? AppColors.textTertiary
                          : AppColors.textPrimary,
                      fontWeight: playing ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                if (!spec.isCompact && line.isChorus)
                  const _TinyBadge(label: '副歌', accent: true),
                if (!spec.isCompact &&
                    fallbackCandidate != null &&
                    line.confidence < 100) ...[
                  const SizedBox(width: AppSpacing.xs),
                  const _TinyBadge(label: '双引擎'),
                ],
                if (isReviewed) ...[
                  const SizedBox(width: AppSpacing.xs),
                  const _TinyBadge(label: '已复核', accent: true),
                ] else if (priority != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Tooltip(
                    message: priority!.reasons.join('\n'),
                    child: _TinyBadge(
                      label: spec.isCompact ? '复核' : '优先 ${priority!.score}',
                      warning: priority!.score >= 45,
                    ),
                  ),
                ] else if (needsReview) ...[
                  const SizedBox(width: AppSpacing.xs),
                  _TinyBadge(
                    label: '${line.confidence}',
                    warning: line.confidence < 70,
                  ),
                ],
                if (!spec.supportsTwoPane) ...[
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.textTertiary,
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
  final bool isReviewed;
  final ValueChanged<bool>? onReviewDecision;
  final PlaybackState playback;
  final bool playbackBelongsToProject;
  final int? currentPlaybackLine;
  final void Function(int, LyricLine) onUpdateLine;
  final ValueChanged<int> onDeleteLine;
  final ValueChanged<int> onPreviewLine;
  final ValueChanged<int> onSetStartFromPlayback;
  final ValueChanged<int> onSetEndFromPlayback;
  final bool autofocusText;
  final int focusRequestId;

  const _InspectorPane({
    required this.document,
    required this.selectedIndex,
    required this.fallbackCandidate,
    required this.isReviewed,
    required this.onReviewDecision,
    required this.playback,
    required this.playbackBelongsToProject,
    required this.currentPlaybackLine,
    required this.onUpdateLine,
    required this.onDeleteLine,
    required this.onPreviewLine,
    required this.onSetStartFromPlayback,
    required this.onSetEndFromPlayback,
    required this.autofocusText,
    required this.focusRequestId,
  });

  @override
  Widget build(BuildContext context) {
    final index = selectedIndex;
    if (index == null || index < 0 || index >= document.lines.length) {
      return const _NoSelectionInspector();
    }

    final line = document.lines[index];
    return _LineInspector(
      key: ValueKey('inspector_${index}_$focusRequestId'),
      index: index,
      line: line,
      fallbackCandidate: fallbackCandidate,
      isReviewed: isReviewed,
      onReviewDecision: onReviewDecision,
      isCurrentPlaybackLine:
          playbackBelongsToProject && currentPlaybackLine == index,
      isPlaying: playbackBelongsToProject && playback.isPlaying,
      autofocusText: autofocusText,
      onUpdate: (updated) => onUpdateLine(index, updated),
      onDelete: () => onDeleteLine(index),
      onPreview: () => onPreviewLine(index),
      onUsePlaybackAsStart: playbackBelongsToProject
          ? () => onSetStartFromPlayback(index)
          : null,
      onUsePlaybackAsEnd: playbackBelongsToProject
          ? () => onSetEndFromPlayback(index)
          : null,
    );
  }
}

class _LineInspector extends StatefulWidget {
  final int index;
  final LyricLine line;
  final Map<String, dynamic>? fallbackCandidate;
  final bool isReviewed;
  final ValueChanged<bool>? onReviewDecision;
  final bool isCurrentPlaybackLine;
  final bool isPlaying;
  final bool autofocusText;
  final ValueChanged<LyricLine> onUpdate;
  final VoidCallback onDelete;
  final VoidCallback onPreview;
  final VoidCallback? onUsePlaybackAsStart;
  final VoidCallback? onUsePlaybackAsEnd;

  const _LineInspector({
    super.key,
    required this.index,
    required this.line,
    required this.fallbackCandidate,
    required this.isReviewed,
    required this.onReviewDecision,
    required this.isCurrentPlaybackLine,
    required this.isPlaying,
    this.autofocusText = false,
    required this.onUpdate,
    required this.onDelete,
    required this.onPreview,
    this.onUsePlaybackAsStart,
    this.onUsePlaybackAsEnd,
  });

  @override
  State<_LineInspector> createState() => _LineInspectorState();
}

class _LineInspectorState extends State<_LineInspector> {
  late final TextEditingController _textController;
  late final FocusNode _textFocusNode;
  late LyricLine _workingLine;

  @override
  void initState() {
    super.initState();
    _workingLine = widget.line;
    _textController = TextEditingController(text: widget.line.text);
    _textFocusNode = FocusNode();
    if (widget.autofocusText) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _textFocusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _LineInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line != widget.line) {
      _workingLine = widget.line;
    }
    if (oldWidget.line.text != widget.line.text &&
        _textController.text != widget.line.text) {
      _textController.text = widget.line.text;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _textFocusNode.dispose();
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

  void _emitUpdate(LyricLine updated) {
    setState(() => _workingLine = updated);
    widget.onUpdate(updated);
  }

  void _updateText(String text) {
    _emitUpdate(_workingLine.copyWith(text: text, confidence: 100));
  }

  void _nudgeStart(Duration delta) {
    var next = _workingLine.startTime + delta;
    if (next.isNegative) next = Duration.zero;
    final latest = _workingLine.endTime - const Duration(milliseconds: 10);
    if (next > latest) next = latest.isNegative ? Duration.zero : latest;
    _emitUpdate(_workingLine.copyWith(startTime: next));
  }

  void _nudgeEnd(Duration delta) {
    var next = _workingLine.endTime + delta;
    final earliest = _workingLine.startTime + const Duration(milliseconds: 10);
    if (next < earliest) next = earliest;
    _emitUpdate(_workingLine.copyWith(endTime: next));
  }

  void _applyAlternative() {
    final alternative = _alternativeText();
    if (alternative == null || alternative.trim().isEmpty) return;
    _textController.text = alternative;
    _emitUpdate(_workingLine.copyWith(text: alternative, confidence: 100));
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final alternative = _alternativeText();
    final duration = _workingLine.endTime - _workingLine.startTime;
    final inspectorPadding = spec.pageGutter.clamp(12, 24).toDouble();

    return Container(
      color: AppColors.bgElevated,
      child: ListView(
        padding: EdgeInsets.all(inspectorPadding),
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
                      '${_formatDuration(_workingLine.startTime)} → ${_formatDuration(_workingLine.endTime)} · ${_formatCompactDuration(duration)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: spec.minimumInteractiveExtent,
                height: spec.minimumInteractiveExtent,
                child: IconButton.filledTonal(
                  tooltip: '从这一行开始试听',
                  onPressed: widget.onPreview,
                  icon: Icon(
                    widget.isCurrentPlaybackLine && widget.isPlaying
                        ? Icons.graphic_eq_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              if (_workingLine.confidence < 70)
                _TinyBadge(
                  label: '低置信度 ${_workingLine.confidence}',
                  warning: true,
                )
              else
                _TinyBadge(label: '置信度 ${_workingLine.confidence}'),
              if (_workingLine.isChorus)
                const _TinyBadge(label: '副歌', accent: true),
              if (widget.fallbackCandidate != null)
                const _TinyBadge(label: '双引擎复核'),
            ],
          ),
          if (widget.onReviewDecision != null &&
              widget.line.id?.isNotEmpty == true) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => widget.onReviewDecision!(!widget.isReviewed),
                icon: Icon(
                  widget.isReviewed
                      ? Icons.undo_rounded
                      : Icons.check_circle_outline_rounded,
                ),
                label: Text(widget.isReviewed ? '取消已复核标记' : '确认歌词与时间无误并继续'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          TextField(
            controller: _textController,
            focusNode: _textFocusNode,
            onChanged: _updateText,
            minLines: 2,
            maxLines: spec.isShort ? 3 : 4,
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
          if (_workingLine.confidence < 100 &&
              widget.fallbackCandidate != null &&
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
            title: '人声起点',
            playbackPositionLabel: '标记人声起点',
            value: _workingLine.startTime,
            onNudge: _nudgeStart,
            onUsePlaybackPosition: widget.onUsePlaybackAsStart,
          ),
          const SizedBox(height: AppSpacing.sm),
          _TimingEditor(
            title: '人声终点',
            playbackPositionLabel: '标记人声终点',
            value: _workingLine.endTime,
            onNudge: _nudgeEnd,
            onUsePlaybackPosition: widget.onUsePlaybackAsEnd,
          ),
          const SizedBox(height: AppSpacing.lg),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('标记为副歌'),
            subtitle: const Text('播放器可使用这一标记强化副歌段落'),
            value: _workingLine.isChorus,
            onChanged: (value) =>
                _emitUpdate(_workingLine.copyWith(isChorus: value)),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: widget.onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('删除这一行'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              minimumSize: Size.fromHeight(spec.minimumInteractiveExtent),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimingEditor extends StatelessWidget {
  final String title;
  final String playbackPositionLabel;
  final Duration value;
  final ValueChanged<Duration> onNudge;
  final VoidCallback? onUsePlaybackPosition;

  const _TimingEditor({
    required this.title,
    required this.playbackPositionLabel,
    required this.value,
    required this.onNudge,
    this.onUsePlaybackPosition,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
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
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _NudgeButton(
                label: '-1s',
                minHeight: spec.minimumInteractiveExtent,
                onPressed: () => onNudge(const Duration(seconds: -1)),
              ),
              _NudgeButton(
                label: '-100ms',
                minHeight: spec.minimumInteractiveExtent,
                onPressed: () => onNudge(const Duration(milliseconds: -100)),
              ),
              _NudgeButton(
                label: '-10ms',
                minHeight: spec.minimumInteractiveExtent,
                onPressed: () => onNudge(const Duration(milliseconds: -10)),
              ),
              _NudgeButton(
                label: '+10ms',
                minHeight: spec.minimumInteractiveExtent,
                onPressed: () => onNudge(const Duration(milliseconds: 10)),
              ),
              _NudgeButton(
                label: '+100ms',
                minHeight: spec.minimumInteractiveExtent,
                onPressed: () => onNudge(const Duration(milliseconds: 100)),
              ),
              _NudgeButton(
                label: '+1s',
                minHeight: spec.minimumInteractiveExtent,
                onPressed: () => onNudge(const Duration(seconds: 1)),
              ),
              if (onUsePlaybackPosition != null)
                TextButton.icon(
                  onPressed: onUsePlaybackPosition,
                  icon: const Icon(Icons.my_location_rounded, size: 16),
                  label: Text(playbackPositionLabel),
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
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppColors.info),
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
          Text('选择一行开始校对', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '文本、双引擎备选和时间轴微调都会集中显示在这里。',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
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
  final VoidCallback? onInsertAtPlayback;

  const _BottomBar({
    required this.totalLines,
    required this.visibleLines,
    required this.hasChanges,
    required this.onAddLine,
    required this.onInsertAtPlayback,
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
            const _TinyBadge(label: '有未保存修改', warning: true),
          ],
          const Spacer(),
          if (spec.isCompactOrMedium)
            IconButton(
              tooltip: onInsertAtPlayback == null
                  ? '先试听本工程后可在当前时间插入'
                  : '在播放位置插入歌词行',
              onPressed: onInsertAtPlayback,
              icon: const Icon(Icons.playlist_add_rounded),
            ),
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

class _SmartReviewEmptyState extends StatelessWidget {
  final int reviewedCount;

  const _SmartReviewEmptyState({required this.reviewedCount});

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final completed = reviewedCount > 0;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: EdgeInsets.all(spec.pageGutter.clamp(16, 32).toDouble()),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                size: 44,
                color: AppColors.accent,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                completed ? '本轮智能复核已完成' : '暂未发现明显风险行',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                completed
                    ? '已确认 $reviewedCount 行。若修改了歌词文本或时间轴，该行会自动重新进入复核队列。请保存以保留确认记录。'
                    : '当前没有达到智能复核阈值的明显问题。自动评分不能判断歌词语义是否正确，仍可结合试听和个人听感检查。',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
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
          const Icon(Icons.task_alt_rounded, size: 42, color: AppColors.accent),
          const SizedBox(height: AppSpacing.sm),
          Text('当前筛选下没有待处理歌词', style: Theme.of(context).textTheme.titleMedium),
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
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
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
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: color, fontSize: 10),
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
    final spec = AppResponsive.of(context);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: Size(0, spec.minimumInteractiveExtent),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      ),
      child: Text(label),
    );
  }
}

class _NudgeButton extends StatelessWidget {
  final String label;
  final double minHeight;
  final VoidCallback onPressed;

  const _NudgeButton({
    required this.label,
    required this.minHeight,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: Size(70, minHeight),
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
  final millis = (safe.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(
    2,
    '0',
  );
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
