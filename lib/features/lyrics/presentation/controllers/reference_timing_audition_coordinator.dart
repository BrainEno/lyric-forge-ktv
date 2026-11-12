import '../../domain/proofreading/reference_alignment_audio_guard.dart';
import '../../domain/proofreading/reference_forced_alignment_planner.dart';
import '../../domain/proofreading/reference_timing_audition_planner.dart';
import '../../domain/services/lyric_audition_window_service.dart';

enum ReferenceTimingPreviewStatus {
  started,
  paused,
  resumed,
  busy,
  closed,
  staleEditor,
  audioCheckFailed,
  invalidPlayback,
  playbackFailed,
}

class ReferenceTimingPreviewResult {
  final ReferenceTimingPreviewStatus status;
  final ReferenceAlignmentAudioStatus? audioStatus;
  final ReferenceTimingAuditionFailure? playbackFailure;
  final String? error;

  const ReferenceTimingPreviewResult(
    this.status, {
    this.audioStatus,
    this.playbackFailure,
    this.error,
  });
}

/// Coordinates one review dialog's asynchronous audition requests.
///
/// A pending hash is invalidated by [close]. Only one request can be in flight,
/// preventing rapid clicks from completing out of order. If playback is already
/// being started when the dialog closes, [stopOwnedPlayback] must only stop the
/// exact request it owns, never another window or project.
class ReferenceTimingAuditionCoordinator {
  final ReferenceAlignmentAudioGuard guard;
  final ReferenceAlignmentAudioSnapshot snapshot;
  final ReferenceTimingPlaybackSnapshot Function() playbackSnapshot;
  final bool Function() isEditorCurrent;
  final Future<ReferenceTimingPreviewResult> Function(
    int proposalIndex,
    int? sourceIndex,
    LyricAuditionWindow window,
  ) play;
  final Future<void> Function() stopOwnedPlayback;
  final Duration? audioDuration;
  final ReferenceTimingAuditionPlanner planner;

  bool _closed = false;
  bool _busy = false;
  bool _ownsPlayback = false;

  ReferenceTimingAuditionCoordinator({
    required this.guard,
    required this.snapshot,
    required this.playbackSnapshot,
    required this.isEditorCurrent,
    required this.play,
    required this.stopOwnedPlayback,
    this.audioDuration,
    this.planner = const ReferenceTimingAuditionPlanner(),
  });

  bool get isClosed => _closed;
  bool get isBusy => _busy;

  Future<ReferenceTimingPreviewResult> preview({
    required int proposalIndex,
    required int? sourceIndex,
    required ReferenceForcedTimingProposal evidence,
  }) async {
    if (_closed) return const ReferenceTimingPreviewResult(ReferenceTimingPreviewStatus.closed);
    if (_busy) return const ReferenceTimingPreviewResult(ReferenceTimingPreviewStatus.busy);
    if (!isEditorCurrent()) return const ReferenceTimingPreviewResult(ReferenceTimingPreviewStatus.staleEditor);
    _busy = true;
    try {
      final checked = await guard.verify(snapshot);
      if (_closed) return const ReferenceTimingPreviewResult(ReferenceTimingPreviewStatus.closed);
      if (!isEditorCurrent()) return const ReferenceTimingPreviewResult(ReferenceTimingPreviewStatus.staleEditor);
      if (checked.status != ReferenceAlignmentAudioStatus.matches) {
        return ReferenceTimingPreviewResult(ReferenceTimingPreviewStatus.audioCheckFailed, audioStatus: checked.status);
      }
      final plan = planner.plan(
        evidence: evidence,
        projectId: snapshot.projectId,
        verifiedAudioPath: snapshot.audioPath,
        playback: playbackSnapshot(),
        verifiedAudioDuration: audioDuration,
      );
      if (!plan.canAudition) {
        return ReferenceTimingPreviewResult(ReferenceTimingPreviewStatus.invalidPlayback, playbackFailure: plan.failure);
      }
      final result = await play(proposalIndex, sourceIndex, plan.window!);
      if (result.status == ReferenceTimingPreviewStatus.started ||
          result.status == ReferenceTimingPreviewStatus.resumed ||
          result.status == ReferenceTimingPreviewStatus.paused) {
        _ownsPlayback = true;
      }
      if (_closed || !isEditorCurrent()) {
        if (_ownsPlayback) await stopOwnedPlayback();
        _ownsPlayback = false;
        return ReferenceTimingPreviewResult(_closed ? ReferenceTimingPreviewStatus.closed : ReferenceTimingPreviewStatus.staleEditor);
      }
      return result;
    } finally {
      _busy = false;
    }
  }

  /// Cancels pending validation and stops only the last preview this dialog
  /// started. If a start is still in flight, its completion performs cleanup.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!_busy && _ownsPlayback) {
      _ownsPlayback = false;
      await stopOwnedPlayback();
    }
  }
}
