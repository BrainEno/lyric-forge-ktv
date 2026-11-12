import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_input.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/reference_forced_alignment_planner.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/reference_timing_audition_planner.dart';

ReferenceForcedTimingProposal evidence(int startMs, int endMs) {
  const planner = ReferenceForcedAlignmentPlanner();
  final reference = planner.prepare(const ReferenceLyricInput(
    lines: [ReferenceLyricLine(text: 'line')],
    timed: false,
    format: 'txt',
  )).prepared!;
  return planner.plan(
    reference: reference,
    spans: [ForcedAlignedSpan(text: 'line', start: Duration(milliseconds: startMs), end: Duration(milliseconds: endMs))],
    audioDuration: const Duration(seconds: 30),
  ).proposals.single;
}

void main() {
  const planner = ReferenceTimingAuditionPlanner();
  const current = ReferenceTimingPlaybackSnapshot(projectId: 'project', audioPath: '/vocal.wav', duration: Duration(seconds: 10));
  ReferenceTimingAuditionPlan plan({
    ReferenceForcedTimingProposal? timing,
    String projectId = 'project',
    String path = '/vocal.wav',
    ReferenceTimingPlaybackSnapshot playback = current,
    Duration? verifiedDuration = const Duration(seconds: 10),
  }) => planner.plan(evidence: timing ?? evidence(1000, 2500), projectId: projectId, verifiedAudioPath: path, playback: playback, verifiedAudioDuration: verifiedDuration);

  group('absolute audio audition window', () {
    test('uses evidence without lyric document offset and has bounded pre-roll', () {
      final result = plan();
      expect(result.canAudition, isTrue);
      expect(result.failure, isNull);
      expect(result.window!.startAt, const Duration(milliseconds: 750));
      expect(result.window!.endAt, const Duration(milliseconds: 2500));
    });

    test('pre-roll clamps at zero without extending the end', () {
      final result = plan(timing: evidence(100, 700));
      expect(result.window!.startAt, Duration.zero);
      expect(result.window!.endAt, const Duration(milliseconds: 700));
    });

    test('end exactly at duration remains valid', () {
      final result = plan(timing: evidence(9000, 10000));
      expect(result.canAudition, isTrue);
      expect(result.window!.endAt, const Duration(seconds: 10));
    });

    test('unknown durations do not manufacture an end boundary', () {
      final result = plan(playback: const ReferenceTimingPlaybackSnapshot(projectId: 'project', audioPath: '/vocal.wav'), verifiedDuration: null);
      expect(result.canAudition, isTrue);
      expect(result.window!.endAt, const Duration(milliseconds: 2500));
    });

    test('either reported duration can reject an out-of-range end', () {
      expect(plan(verifiedDuration: const Duration(seconds: 2)).failure, ReferenceTimingAuditionFailure.beyondAudioDuration);
      expect(plan(playback: const ReferenceTimingPlaybackSnapshot(projectId: 'project', audioPath: '/vocal.wav', duration: Duration(seconds: 2))).failure, ReferenceTimingAuditionFailure.beyondAudioDuration);
    });

    test('zero or negative known durations are not interpreted as unknown', () {
      for (final duration in [Duration.zero, const Duration(seconds: -1)]) {
        expect(plan(verifiedDuration: duration).failure, ReferenceTimingAuditionFailure.beyondAudioDuration);
        expect(plan(playback: ReferenceTimingPlaybackSnapshot(projectId: 'project', audioPath: '/vocal.wav', duration: duration)).failure, ReferenceTimingAuditionFailure.beyondAudioDuration);
      }
    });
  });

  group('only the verified local source may be heard', () {
    test('rejects another project and an absent project', () {
      expect(plan(projectId: 'other').failure, ReferenceTimingAuditionFailure.wrongProject);
      expect(plan(playback: const ReferenceTimingPlaybackSnapshot(projectId: null, audioPath: '/vocal.wav')).failure, ReferenceTimingAuditionFailure.wrongProject);
    });

    test('rejects a remote stream even when the displayed file path matches', () {
      expect(plan(playback: const ReferenceTimingPlaybackSnapshot(projectId: 'project', audioPath: '/vocal.wav', isRemote: true)).failure, ReferenceTimingAuditionFailure.remoteSource);
    });

    test('does not seek while player is still loading', () {
      expect(plan(playback: const ReferenceTimingPlaybackSnapshot(projectId: 'project', audioPath: '/vocal.wav', isLoading: true)).failure, ReferenceTimingAuditionFailure.sourceLoading);
    });

    test('requires both observed and verified paths', () {
      expect(plan(path: '').failure, ReferenceTimingAuditionFailure.sourceUnavailable);
      expect(plan(playback: const ReferenceTimingPlaybackSnapshot(projectId: 'project', audioPath: null)).failure, ReferenceTimingAuditionFailure.sourceUnavailable);
      expect(plan(playback: const ReferenceTimingPlaybackSnapshot(projectId: 'project', audioPath: '')).failure, ReferenceTimingAuditionFailure.sourceUnavailable);
    });

    test('original, instrumental and similar-looking paths cannot stand in for vocal', () {
      for (final path in ['/song.wav', '/instrumental.wav', '/VOCAL.wav', '/vocal.wav ', '/other/vocal.wav']) {
        final result = plan(playback: ReferenceTimingPlaybackSnapshot(projectId: 'project', audioPath: path));
        expect(result.canAudition, isFalse, reason: path);
        expect(result.failure, ReferenceTimingAuditionFailure.wrongAudio, reason: path);
        expect(result.window, isNull, reason: path);
      }
    });

    test('does not infer a matching path from the project name', () {
      final result = plan(playback: const ReferenceTimingPlaybackSnapshot(projectId: 'project', audioPath: '/different.wav'));
      expect(result.failure, ReferenceTimingAuditionFailure.wrongAudio);
    });
  });
}
