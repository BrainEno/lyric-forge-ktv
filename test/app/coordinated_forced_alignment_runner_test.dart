import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/app/lyric_editor_assembly.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/lyric_review_strings.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_resource_coordinator.dart';

const _draft = LyricDocument(
  language: 'en',
  lines: [
    LyricLine(
      text: 'human lyric',
      startTime: Duration.zero,
      endTime: Duration(seconds: 1),
    ),
  ],
);

void main() {
  test('busy preflight is explicit and cannot modify the draft', () async {
    final resources = AsrResourceCoordinator();
    var calls = 0;
    final runner = coordinateForcedAlignmentRunner(
      resources: resources,
      delegate:
          ({
            required audioPath,
            required text,
            required language,
            required audioDuration,
          }) async {
            calls++;
            return [];
          },
    );
    for (final use in AsrResourceUse.values) {
      final owner = resources.tryAcquire(use)!;
      await expectLater(
        ForcedAlignmentProofreadService(runner: runner).buildReview(
          draft: _draft,
          audioPath: 'song.wav',
          referenceText: 'human lyric',
          language: 'English',
          audioDuration: const Duration(seconds: 1),
        ),
        throwsA(isA<ForcedAlignmentResourceBusyException>()),
      );
      expect(resources.activeUse, use);
      expect(calls, 0);
      expect(_draft.lines.single.text, 'human lyric');
      owner.release();
    }
    expect(LyricReviewStrings.forcedAlignmentBusy, contains('重试'));
  });

  test(
    'lease covers the complete async delegate and rejects competitors',
    () async {
      final resources = AsrResourceCoordinator();
      final entered = Completer<void>();
      final finish = Completer<void>();
      final expected = [
        const ForcedAlignedSpan(
          text: 'hi',
          start: Duration.zero,
          end: Duration(seconds: 1),
        ),
      ];
      final runner = coordinateForcedAlignmentRunner(
        resources: resources,
        delegate:
            ({
              required audioPath,
              required text,
              required language,
              required audioDuration,
            }) async {
              expect(audioPath, 'song.wav');
              expect(text, 'hi');
              expect(language, 'English');
              expect(audioDuration, const Duration(seconds: 2));
              entered.complete();
              await finish.future;
              return expected;
            },
      );
      final run = runner(
        audioPath: 'song.wav',
        text: 'hi',
        language: 'English',
        audioDuration: const Duration(seconds: 2),
      );
      await entered.future;
      expect(resources.activeUse, AsrResourceUse.alignment);
      for (final use in AsrResourceUse.values) {
        expect(resources.tryAcquire(use), isNull);
      }
      await expectLater(
        runner(
          audioPath: 'song.wav',
          text: 'hi',
          language: 'English',
          audioDuration: const Duration(seconds: 2),
        ),
        throwsA(isA<ForcedAlignmentResourceBusyException>()),
      );
      finish.complete();
      expect(await run, same(expected));
      expect(resources.activeUse, isNull);
    },
  );

  test(
    'delegate failure releases the lease and keeps fallback behavior',
    () async {
      final resources = AsrResourceCoordinator();
      final runner = coordinateForcedAlignmentRunner(
        resources: resources,
        delegate:
            ({
              required audioPath,
              required text,
              required language,
              required audioDuration,
            }) async {
              throw Exception('fake preflight or engine failure');
            },
      );
      final outcome = await ForcedAlignmentProofreadService(runner: runner)
          .buildReview(
            draft: _draft,
            audioPath: 'song.wav',
            referenceText: 'human lyric',
            language: 'English',
            audioDuration: const Duration(seconds: 1),
          );
      expect(outcome.alignmentAvailable, isFalse);
      expect(outcome.result.notes, contains('forcedAlignmentUnavailable'));
      expect(outcome.result.proposedDocument.lines.single.text, 'human lyric');
      expect(resources.activeUse, isNull);
    },
  );
}
