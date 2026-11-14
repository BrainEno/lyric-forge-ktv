import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../player/domain/services/audio_player_service.dart';
import '../../../player/domain/services/playback_session_service.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../domain/models/reference_lyric_input.dart';
import '../../domain/proofreading/apply_reference_alignment_use_case.dart';
import '../../domain/proofreading/forced_alignment_language.dart';
import '../../domain/proofreading/forced_alignment_proofread_service.dart';
import '../../domain/proofreading/proofread_result.dart';
import '../../domain/proofreading/project_proofread_evidence.dart';
import '../../domain/proofreading/reference_alignment_audio_guard.dart';
import '../../domain/proofreading/reference_alignment_timing_applier.dart';
import '../../domain/proofreading/reference_timing_audition_planner.dart';
import '../../domain/proofreading/proofread_v2_document_composer.dart';
import '../../domain/proofreading/run_proofread_v2_use_case.dart';
import '../../domain/proofreading/run_reference_proofread_use_case.dart';
import '../../domain/services/lyric_timeline_validator.dart';
import '../../domain/services/reference_lyric_text_parser.dart';
import '../controllers/line_audition_controller.dart';
import '../controllers/reference_timing_audition_coordinator.dart';
import '../lyric_editor_dependencies.dart';
import '../lyric_review_strings.dart';
import '../widgets/lyric_proofread_v2_dialog.dart';
import '../widgets/project_asr_snapshot_dialog.dart';
import '../widgets/project_chunk_asr_snapshot_dialog.dart';
import '../widgets/reference_alignment_dialog.dart';
import '../widgets/reference_alignment_review.dart';
import '../widgets/reference_proofread_review_dialog.dart';
import '../widgets/reference_proofread_timing_review_dialog.dart';
import '../widgets/timing_evidence_import_dialog.dart';

/// The presentation boundary between editor state and proofreading flows.
///
/// The coordinator owns modal sequencing and stale-result checks, while the
/// host owns the editor's mutable document, audition and playback state. The
/// domain use cases remain the only place that builds or applies proposals.
abstract interface class LyricEditorProofreadFlowHost {
  BuildContext get proofreadContext;
  bool get proofreadIsMounted;
  int get proofreadDocumentRevision;
  int? get proofreadSelectedLineIndex;
  Set<int> get proofreadManuallyEditedLineIndices;
  AudioPlayerService get proofreadAudioService;
  PlaybackSessionService get proofreadPlaybackSession;
  LineAuditionController get proofreadAudition;

  bool proofreadIsCurrent(int revision);

  Future<void> previewProofreadLine(ProjectManifest project, int index);

  Future<ProofreadTimedLinePreviewResult> previewProofreadTimedLine(
    ProjectManifest project,
    int index,
    LyricLine line,
    Duration globalOffset,
  );

  Future<void> previewProofreadToken(
    ProjectManifest project,
    int index,
    TimedLyricToken token,
  );

  void applyProofreadDocument({
    required LyricDocument document,
    required String label,
    required int? selectedLineIndex,
    required bool isReferenceProofread,
    required String message,
  });
}

/// Runs review interactions without owning or directly mutating the editor.
class LyricEditorProofreadingCoordinator {
  final LyricEditorDependencies dependencies;
  final ReferenceLyricTextParser referenceParser;
  final LyricEditorProofreadFlowHost host;

  const LyricEditorProofreadingCoordinator({
    required this.dependencies,
    required this.referenceParser,
    required this.host,
  });

  Future<void> openReferenceAlignment({
    required ProjectManifest project,
    required LyricDocument document,
    required int revision,
  }) async {
    if (document.lines.isEmpty) return;

    final context = host.proofreadContext;
    final input = await showReferenceAlignmentDialog(
      context,
      parser: referenceParser,
      initialTitle: project.name,
      initialArtist: project.artist,
    );
    if (input == null ||
        !context.mounted ||
        !host.proofreadIsCurrent(revision)) {
      return;
    }

    final plan = const ApplyReferenceAlignmentUseCase().prepare(
      draft: document,
      input: input,
      protectedLineIndices: host.proofreadManuallyEditedLineIndices,
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
    if (decision == null ||
        !context.mounted ||
        !host.proofreadIsCurrent(revision)) {
      return;
    }
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
      if (keep != true || !host.proofreadIsCurrent(revision)) return;
    }

    final appliedDocument = proposal.materialize(appliedAt: DateTime.now());

    final selection = result.corrections.isNotEmpty
        ? result.corrections.first.asrLineIndex
        : result.insertions.isNotEmpty
        ? result.insertions.first.asrLineIndex
        : host.proofreadSelectedLineIndex;
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
    host.applyProofreadDocument(
      document: appliedDocument,
      label: '应用参考歌词对齐',
      selectedLineIndex: selection,
      isReferenceProofread: false,
      message:
          '${parts.isEmpty ? '参考歌词已对齐' : parts.join('，')}$timelineWarning。请检查后保存。',
    );
  }

  Future<void> openReferenceProofread({
    required ProjectManifest project,
    required LyricDocument document,
    required int revision,
  }) async {
    if (document.lines.isEmpty) return;

    final context = host.proofreadContext;
    final input = await showReferenceAlignmentDialog(
      context,
      parser: referenceParser,
      initialTitle: project.name,
      initialArtist: project.artist,
    );
    if (input == null ||
        !context.mounted ||
        !host.proofreadIsCurrent(revision)) {
      return;
    }

    final evidence = await showTimingEvidenceImportDialog(context);
    if (!context.mounted || !host.proofreadIsCurrent(revision)) return;
    final plan = const RunReferenceProofreadUseCase().build(
      draft: document,
      reference: input,
      timingEvidence: evidence,
      protectedDraftIndices: host.proofreadManuallyEditedLineIndices,
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
        !context.mounted ||
        !host.proofreadIsCurrent(revision)) {
      return;
    }
    final applied = plan.apply(selected);
    host.applyProofreadDocument(
      document: applied.after,
      label: '应用逐行纠错',
      selectedLineIndex: applied.changedDraftIndices.isEmpty
          ? host.proofreadSelectedLineIndex
          : applied.changedDraftIndices.first,
      isReferenceProofread: true,
      message: plan.hasTimingEvidence
          ? '已应用 ${applied.changedDraftIndices.length} 行文字与校时建议；请试听检查并保存。'
          : '已应用 ${applied.changedDraftIndices.length} 行文字纠错；现有时间戳保持不变，请试听检查并保存。',
    );
  }

  Future<void> runProofreadV2({
    required ProjectManifest project,
    required LyricDocument document,
    required int revision,
    required int projectRevision,
  }) async {
    final options = await showProofreadV2RunOptionsDialog(
      host.proofreadContext,
      allowProjectEvidence: dependencies.projectProofreadEvidenceLoader != null,
    );
    if (options == null || !host.proofreadIsCurrent(revision)) return;

    LyricDocument? secondaryAsr;
    final secondaryText = options.secondaryTranscriptText;
    if (secondaryText != null) {
      late final ReferenceLyricInput parsed;
      try {
        parsed = referenceParser.parsePasted(secondaryText);
      } catch (error) {
        ScaffoldMessenger.of(
          host.proofreadContext,
        ).showSnackBar(SnackBar(content: Text('无法解析第二份 ASR 转写稿：$error')));
        return;
      }
      if (!parsed.timed ||
          parsed.lines.any(
            (line) => line.startTime == null || line.endTime == null,
          )) {
        ScaffoldMessenger.of(host.proofreadContext).showSnackBar(
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
        host.proofreadContext,
        parser: referenceParser,
        initialTitle: project.name,
        initialArtist: project.artist,
      );
      if (reference == null || !host.proofreadIsCurrent(revision)) return;
    }

    try {
      ProjectProofreadEvidenceResult? projectEvidence;
      if (options.useProjectEvidence) {
        final loader = dependencies.projectProofreadEvidenceLoader;
        if (loader == null) return;
        projectEvidence = await loader(
          projectId: project.id,
          expectedProjectRevision: projectRevision,
          draft: document,
        );
        if (!host.proofreadIsCurrent(revision)) return;
        if (projectEvidence.status ==
            ProjectProofreadEvidenceStatus.chunkAuditOnly) {
          await showDialog<void>(
            context: host.proofreadContext,
            builder: (_) =>
                ProjectChunkAsrSnapshotDialog(chunks: projectEvidence!.chunks),
          );
          return;
        }
        if (projectEvidence.status ==
            ProjectProofreadEvidenceStatus.auditOnly) {
          await showDialog<void>(
            context: host.proofreadContext,
            builder: (_) =>
                ProjectAsrSnapshotDialog(evidence: projectEvidence!),
          );
          return;
        }
        if (projectEvidence.status !=
            ProjectProofreadEvidenceStatus.available) {
          ScaffoldMessenger.of(host.proofreadContext).showSnackBar(
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
      final audioGuard = dependencies.referenceAlignmentAudioGuard;
      ReferenceAlignmentAudioCheck? audioCheck;
      final asset = project.audioAsset;
      if (reference != null &&
          options.useForcedAlignment &&
          asset != null &&
          audioGuard != null) {
        audioCheck = await audioGuard.capture(
          projectId: project.id,
          projectRevision: projectRevision,
          audioPath: asset.vocalPath ?? asset.originalPath,
        );
        if (!host.proofreadIsCurrent(revision)) return;
      }
      final run =
          await RunProofreadV2UseCase(
            runner: dependencies.forcedAlignmentRunner,
          ).build(
            draft: document,
            strategy: options.strategy,
            audioAsset: project.audioAsset,
            reference: reference,
            secondary: secondaryAsr,
            useForcedAlignment: options.useForcedAlignment,
            manuallyEditedIndices: host.proofreadManuallyEditedLineIndices,
          );
      if (!host.proofreadIsCurrent(revision)) return;
      final assembly = run.assembly;
      final decision = run.decision;
      final summary = run.summary;
      if (assembly.referenceAlignmentPlan?.isReady == true &&
          audioCheck?.snapshot != null &&
          audioGuard != null) {
        audioCheck = await audioGuard.verify(audioCheck!.snapshot!);
        if (!host.proofreadIsCurrent(revision)) return;
      }
      final timingSnapshot =
          audioCheck?.status == ReferenceAlignmentAudioStatus.matches
          ? audioCheck?.snapshot
          : null;

      LineAuditionRequest? ownedReferenceAudition;
      ReferenceTimingPlaybackSnapshot playbackSnapshot() {
        final item = host.proofreadPlaybackSession.currentState.currentItem;
        final state = host.proofreadAudioService.currentState;
        final source = state.currentSource;
        return ReferenceTimingPlaybackSnapshot(
          projectId: item?.projectId,
          audioPath: source == null
              ? null
              : item?.audioAsset.getPathForSource(source),
          isRemote: item?.isRemoteStream ?? false,
          isLoading: state.isLoading,
          duration: state.duration,
        );
      }

      Future<void> stopOwnedReferenceAudition() async {
        final owned = ownedReferenceAudition;
        if (owned == null || !identical(host.proofreadAudition.active, owned))
          return;
        ownedReferenceAudition = null;
        final current = playbackSnapshot();
        if (timingSnapshot != null &&
            current.projectId == timingSnapshot.projectId &&
            !current.isRemote &&
            !current.isLoading &&
            current.audioPath == timingSnapshot.audioPath) {
          await host.proofreadAudition.pauseIfSounding();
        }
        if (identical(host.proofreadAudition.active, owned))
          host.proofreadAudition.clear();
      }

      late final ReferenceTimingAuditionCoordinator? previewCoordinator;
      previewCoordinator = audioGuard == null || timingSnapshot == null
          ? null
          : ReferenceTimingAuditionCoordinator(
              guard: audioGuard,
              snapshot: timingSnapshot,
              audioDuration: project.audioAsset?.duration,
              playbackSnapshot: playbackSnapshot,
              isEditorCurrent: () =>
                  host.proofreadIsMounted &&
                  host.proofreadDocumentRevision == revision,
              play: (proposalIndex, sourceIndex, window) async {
                bool valid() {
                  if (!host.proofreadIsMounted ||
                      previewCoordinator!.isClosed ||
                      host.proofreadDocumentRevision != revision)
                    return false;
                  final current = playbackSnapshot();
                  return current.projectId == timingSnapshot.projectId &&
                      !current.isLoading &&
                      !current.isRemote &&
                      current.audioPath == timingSnapshot.audioPath &&
                      (current.duration == null ||
                          window.endAt! <= current.duration!);
                }

                if (sourceIndex != null &&
                    (sourceIndex < 0 || sourceIndex >= document.lines.length)) {
                  return const ReferenceTimingPreviewResult(
                    ReferenceTimingPreviewStatus.playbackFailed,
                    error: '原始歌词行已不可用。',
                  );
                }
                final request = LineAuditionRequest(
                  projectId: project.id,
                  lineIndex: sourceIndex ?? -proposalIndex - 1,
                  previewKey: 'reference:$proposalIndex',
                  lineId: sourceIndex == null
                      ? null
                      : document.lines[sourceIndex].id,
                  window: window,
                );
                final result = await host.proofreadAudition.toggle(
                  request: request,
                  prepare: () async => throw StateError(
                    'Playback source changed during audition',
                  ),
                  isStillValid: valid,
                  isPlaybackStillValid: () {
                    final current = playbackSnapshot();
                    return current.projectId == timingSnapshot.projectId &&
                        !current.isRemote &&
                        !current.isLoading &&
                        current.audioPath == timingSnapshot.audioPath;
                  },
                );
                if (result.action == LineAuditionAction.started ||
                    result.action == LineAuditionAction.resumed ||
                    result.action == LineAuditionAction.paused) {
                  ownedReferenceAudition = host.proofreadAudition.active;
                  if (!valid()) {
                    await stopOwnedReferenceAudition();
                    return const ReferenceTimingPreviewResult(
                      ReferenceTimingPreviewStatus.playbackFailed,
                      error: '试听期间音源或歌词已变化。',
                    );
                  }
                }
                return switch (result.action) {
                  LineAuditionAction.started =>
                    const ReferenceTimingPreviewResult(
                      ReferenceTimingPreviewStatus.started,
                    ),
                  LineAuditionAction.resumed =>
                    const ReferenceTimingPreviewResult(
                      ReferenceTimingPreviewStatus.resumed,
                    ),
                  LineAuditionAction.paused =>
                    const ReferenceTimingPreviewResult(
                      ReferenceTimingPreviewStatus.paused,
                    ),
                  LineAuditionAction.invalid ||
                  LineAuditionAction.failed => ReferenceTimingPreviewResult(
                    ReferenceTimingPreviewStatus.playbackFailed,
                    error: result.error,
                  ),
                };
              },
              stopOwnedPlayback: stopOwnedReferenceAudition,
            );
      final selection = await showLyricProofreadV2ReviewDialog(
        host.proofreadContext,
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
                  : LyricReviewStrings.referenceAlignmentAudioStatus(
                      audioCheck.status,
                    ),
          ],
        ].join(' '),
        alignmentDiagnostics: assembly.alignmentDiagnostics,
        allowReferenceTimingSelection: timingSnapshot != null,
        onPreviewReferenceTiming: previewCoordinator == null
            ? null
            : (proposalIndex, sourceIndex, evidence) async {
                final result = await previewCoordinator!.preview(
                  proposalIndex: proposalIndex,
                  sourceIndex: sourceIndex,
                  evidence: evidence,
                );
                return switch (result.status) {
                  ReferenceTimingPreviewStatus.started =>
                    const ProofreadTimedLinePreviewResult.success(),
                  ReferenceTimingPreviewStatus.resumed =>
                    const ProofreadTimedLinePreviewResult.success(
                      message: '已继续试听参考对齐时间。',
                    ),
                  ReferenceTimingPreviewStatus.paused =>
                    const ProofreadTimedLinePreviewResult.success(
                      message: '已暂停试听。',
                    ),
                  _ => ProofreadTimedLinePreviewResult.failure(
                    LyricReviewStrings.referenceTimingPreviewFailure(result),
                  ),
                };
              },
        items: assembly.items,
        droppedItems: assembly.droppedItems,
        onPreviewDraftLine: project.audioAsset == null
            ? null
            : (index) => host.previewProofreadLine(project, index),
        onPreviewTimedLine: project.audioAsset == null
            ? null
            : (index, line, globalOffset) => host.previewProofreadTimedLine(
                project,
                index,
                line,
                globalOffset,
              ),
        originalGlobalOffset: document.globalOffset ?? Duration.zero,
        proposedGlobalOffset:
            assembly.proposalDocument.globalOffset ?? Duration.zero,
        onPreviewAlignmentToken: project.audioAsset == null
            ? null
            : (index, token) =>
                  host.previewProofreadToken(project, index, token),
      );
      await previewCoordinator?.close();
      if (selection == null || !host.proofreadIsCurrent(revision)) return;

      Future<bool> verifyTimingSnapshot() async {
        if (selection.acceptedReferenceTimingIndices.isEmpty) return true;
        if (audioGuard == null || timingSnapshot == null) return false;
        final check = await audioGuard.verify(timingSnapshot);
        if (!host.proofreadIsCurrent(revision)) return false;
        if (check.status != ReferenceAlignmentAudioStatus.matches) {
          ScaffoldMessenger.of(host.proofreadContext).showSnackBar(
            SnackBar(
              content: Text(
                LyricReviewStrings.referenceAlignmentAudioStatus(check.status),
              ),
              duration: const Duration(seconds: 6),
            ),
          );
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
          host.proofreadContext,
        ).showSnackBar(const SnackBar(content: Text('所选提案没有产生可应用的歌词或时间变化。')));
        return;
      }

      final comparison = const LyricTimelineValidator().compare(
        before: document.lines,
        after: after.lines,
        audioDuration: project.audioAsset?.duration,
        beforeGlobalOffset: document.globalOffset ?? Duration.zero,
        globalOffset: after.globalOffset ?? Duration.zero,
      );
      if (comparison.hasIntroducedSeriousIssues) {
        final keep = await _confirmIntroducedTimelineIssues(
          comparison,
          autoRepairCount: 0,
        );
        if (keep != true || !host.proofreadIsCurrent(revision)) return;
      }
      if (!host.proofreadIsCurrent(revision)) return;
      if (!await verifyTimingSnapshot()) return;
      if (!host.proofreadIsCurrent(revision)) return;
      host.applyProofreadDocument(
        document: after,
        label: '应用校对提案',
        selectedLineIndex: after.lines.isEmpty ? null : 0,
        isReferenceProofread: true,
        message: '已应用智能校对提案（${after.lines.length} 行），未写入磁盘。',
      );
    } catch (error) {
      if (!host.proofreadIsCurrent(revision)) return;
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
        host.proofreadContext,
      ).showSnackBar(SnackBar(content: Text('无法生成或应用校对提案：$detail')));
    }
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
      context: host.proofreadContext,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: const Text('这次对齐引入了时间轴冲突'),
        content: SingleChildScrollView(
          child: Text(
            '${autoRepairCount == 0 ? '本次没有自动修改其他行。' : '系统已先尝试安全修复结束时间重叠：$autoRepairCount 处。'}\n\n'
            '以下问题无法可靠推断：\n\n$issues\n\n'
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
}
