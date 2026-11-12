import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_input.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/reference_alignment_audio_guard.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/reference_forced_alignment_planner.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/reference_timing_audition_planner.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_audition_window_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/controllers/reference_timing_audition_coordinator.dart';

class Guard implements ReferenceAlignmentAudioGuard {
  int calls = 0;
  ReferenceAlignmentAudioStatus status = ReferenceAlignmentAudioStatus.matches;
  Completer<ReferenceAlignmentAudioCheck>? gate;
  @override
  Future<ReferenceAlignmentAudioCheck> capture({required String projectId, required int projectRevision, required String audioPath}) async => throw UnimplementedError();
  @override
  Future<ReferenceAlignmentAudioCheck> verify(ReferenceAlignmentAudioSnapshot snapshot) async {
    calls++;
    if (gate != null) return gate!.future;
    return ReferenceAlignmentAudioCheck(status: status, snapshot: status == ReferenceAlignmentAudioStatus.matches ? snapshot : null);
  }
}

void main() {
  const snapshot = ReferenceAlignmentAudioSnapshot(projectId: 'p', projectRevision: 3, audioPath: '/v.wav', audioSha256: 'hash');
  const planner = ReferenceForcedAlignmentPlanner();
  final prepared = planner.prepare(const ReferenceLyricInput(lines: [ReferenceLyricLine(text: 'line')], timed: false, format: 'txt')).prepared!;
  final timing = planner.plan(reference: prepared, spans: const [ForcedAlignedSpan(text: 'line', start: Duration(seconds: 1), end: Duration(seconds: 2))], audioDuration: const Duration(seconds: 4)).proposals.single;
  late Guard guard;
  late ReferenceTimingAuditionCoordinator coordinator;
  late ReferenceTimingPlaybackSnapshot playback;
  late bool current;
  late int plays;
  late int stops;
  late int? lastSource;
  late int? lastProposal;
  late LyricAuditionWindow? lastWindow;
  Completer<ReferenceTimingPreviewResult>? playGate;

  setUp(() {
    guard = Guard();
    current = true;
    plays = 0;
    stops = 0;
    lastSource = null;
    lastProposal = null;
    lastWindow = null;
    playGate = null;
    playback = const ReferenceTimingPlaybackSnapshot(projectId: 'p', audioPath: '/v.wav', duration: Duration(seconds: 4));
    coordinator = ReferenceTimingAuditionCoordinator(
      guard: guard,
      snapshot: snapshot,
      playbackSnapshot: () => playback,
      isEditorCurrent: () => current,
      audioDuration: const Duration(seconds: 4),
      play: (proposal, source, window) async {
        plays++;
        lastProposal = proposal;
        lastSource = source;
        lastWindow = window;
        return playGate?.future ?? const ReferenceTimingPreviewResult(ReferenceTimingPreviewStatus.started);
      },
      stopOwnedPlayback: () async { stops++; },
    );
  });

  Future<ReferenceTimingPreviewResult> preview({int proposal = 4, int? source = 2}) => coordinator.preview(proposalIndex: proposal, sourceIndex: source, evidence: timing);

  test('verifies every request and passes a bounded absolute window', () async {
    final first = await preview();
    expect(first.status, ReferenceTimingPreviewStatus.started);
    expect(guard.calls, 1);
    expect(plays, 1);
    expect(lastProposal, 4);
    expect(lastSource, 2);
    expect(lastWindow!.startAt, const Duration(milliseconds: 750));
    expect(lastWindow!.endAt, const Duration(seconds: 2));
    await preview();
    expect(guard.calls, 2);
    expect(plays, 2);
  });

  test('inserted rows can preview without an original line index', () async {
    expect((await preview(proposal: 9, source: null)).status, ReferenceTimingPreviewStatus.started);
    expect(lastProposal, 9);
    expect(lastSource, isNull);
  });

  for (final status in ReferenceAlignmentAudioStatus.values.where((s) => s != ReferenceAlignmentAudioStatus.matches)) {
    test('audio status $status refuses playback', () async {
      guard.status = status;
      final result = await preview();
      expect(result.status, ReferenceTimingPreviewStatus.audioCheckFailed);
      expect(result.audioStatus, status);
      expect(plays, 0);
      expect(coordinator.isBusy, isFalse);
    });
  }

  test('stale editor before hash skips both hash and playback', () async {
    current = false;
    expect((await preview()).status, ReferenceTimingPreviewStatus.staleEditor);
    expect(guard.calls, 0);
    expect(plays, 0);
  });

  test('edit during hash discards the result', () async {
    guard.gate = Completer<ReferenceAlignmentAudioCheck>();
    final pending = preview();
    current = false;
    guard.gate!.complete(const ReferenceAlignmentAudioCheck(status: ReferenceAlignmentAudioStatus.matches, snapshot: snapshot));
    expect((await pending).status, ReferenceTimingPreviewStatus.staleEditor);
    expect(plays, 0);
  });

  test('closing during hash prevents late playback', () async {
    guard.gate = Completer<ReferenceAlignmentAudioCheck>();
    final pending = preview();
    await coordinator.close();
    guard.gate!.complete(const ReferenceAlignmentAudioCheck(status: ReferenceAlignmentAudioStatus.matches, snapshot: snapshot));
    expect((await pending).status, ReferenceTimingPreviewStatus.closed);
    expect(plays, 0);
    expect(stops, 0);
    expect((await preview()).status, ReferenceTimingPreviewStatus.closed);
  });

  test('concurrent click is rejected rather than racing hashes', () async {
    guard.gate = Completer<ReferenceAlignmentAudioCheck>();
    final pending = preview();
    expect(coordinator.isBusy, isTrue);
    expect((await preview(proposal: 8)).status, ReferenceTimingPreviewStatus.busy);
    expect(guard.calls, 1);
    guard.gate!.complete(const ReferenceAlignmentAudioCheck(status: ReferenceAlignmentAudioStatus.matches, snapshot: snapshot));
    expect((await pending).status, ReferenceTimingPreviewStatus.started);
    expect(lastProposal, 4);
    expect(coordinator.isBusy, isFalse);
  });

  test('source change during hash is checked after hashing', () async {
    guard.gate = Completer<ReferenceAlignmentAudioCheck>();
    final pending = preview();
    playback = const ReferenceTimingPlaybackSnapshot(projectId: 'p', audioPath: '/other.wav');
    guard.gate!.complete(const ReferenceAlignmentAudioCheck(status: ReferenceAlignmentAudioStatus.matches, snapshot: snapshot));
    final result = await pending;
    expect(result.status, ReferenceTimingPreviewStatus.invalidPlayback);
    expect(result.playbackFailure, ReferenceTimingAuditionFailure.wrongAudio);
    expect(plays, 0);
  });

  test('close stops a finished owned audition only once', () async {
    await preview();
    await coordinator.close();
    await coordinator.close();
    expect(stops, 1);
  });

  test('close during pending player start cleans up on completion', () async {
    playGate = Completer<ReferenceTimingPreviewResult>();
    final pending = preview();
    await Future<void>.delayed(Duration.zero);
    expect(plays, 1);
    await coordinator.close();
    expect(stops, 0);
    playGate!.complete(const ReferenceTimingPreviewResult(ReferenceTimingPreviewStatus.started));
    expect((await pending).status, ReferenceTimingPreviewStatus.closed);
    expect(stops, 1);
  });

  test('editing during player start cleans up before returning stale', () async {
    playGate = Completer<ReferenceTimingPreviewResult>();
    final pending = preview();
    await Future<void>.delayed(Duration.zero);
    current = false;
    playGate!.complete(const ReferenceTimingPreviewResult(ReferenceTimingPreviewStatus.started));
    expect((await pending).status, ReferenceTimingPreviewStatus.staleEditor);
    expect(stops, 1);
  });

  test('failed playback is not treated as owned sound', () async {
    playGate = Completer<ReferenceTimingPreviewResult>();
    final pending = preview();
    await Future<void>.delayed(Duration.zero);
    playGate!.complete(const ReferenceTimingPreviewResult(ReferenceTimingPreviewStatus.playbackFailed, error: 'failure'));
    expect((await pending).error, 'failure');
    await coordinator.close();
    expect(stops, 0);
  });
}
