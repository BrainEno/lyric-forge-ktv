import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_input.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_language.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_review_proposal.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_strategy_selector.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_v2_document_composer.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/reference_forced_alignment_planner.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/run_proofread_v2_use_case.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

const draft = LyricDocument(language: 'en', globalOffset: Duration(milliseconds: 200), metadata: {
  'timingProvenance': {'a': 'manual', 'b': 'mappedAsr'},
}, lines: [
  LyricLine(id: 'a', text: 'hello world', startTime: Duration.zero, endTime: Duration(seconds: 2)),
  LyricLine(id: 'b', text: 'sing tonight', startTime: Duration(seconds: 2), endTime: Duration(seconds: 4)),
]);
const audio = AudioAsset(originalPath: '/song.wav', vocalPath: '/vocal.wav', format: 'wav', duration: Duration(seconds: 8));
ReferenceLyricInput reference(List<String> lines) => ReferenceLyricInput(lines: [for (final text in lines) ReferenceLyricLine(text: text)], timed: false, format: 'txt');
ForcedAlignedSpan span(String text, int start, int end) => ForcedAlignedSpan(text: text, start: Duration(milliseconds: start), end: Duration(milliseconds: end));

class Spy {
  int calls = 0;
  String? path;
  String? text;
  String? language;
  Duration? duration;
  List<ForcedAlignedSpan> spans = [
    span('hello', 500, 800), span('world', 900, 1300),
    span('sing', 3500, 3700), span('tonight', 3800, 4500),
  ];
  Object? error;
  Completer<List<ForcedAlignedSpan>>? pending;
  Future<List<ForcedAlignedSpan>> run({required String audioPath, required String text, required String language, required Duration audioDuration}) async {
    calls++;
    path = audioPath;
    this.text = text;
    this.language = language;
    duration = audioDuration;
    if (error != null) throw error!;
    return pending == null ? spans : await pending!.future;
  }
}

void main() {
  late Spy spy;
  late RunProofreadV2UseCase useCase;
  setUp(() { spy = Spy(); useCase = RunProofreadV2UseCase(runner: spy.run); });

  Future<ProofreadV2RunResult> run({bool alignment = true, LyricSourceStrategy strategy = LyricSourceStrategy.referenceFirst, ReferenceLyricInput? refs, LyricDocument source = draft, Set<int> protected = const {}}) => useCase.build(
    draft: source, strategy: strategy, audioAsset: audio,
    reference: refs ?? reference(['hello world', 'sing tonight']),
    useForcedAlignment: alignment, manuallyEditedIndices: protected,
  );

  test('explicit reference passes sanitized reference rather than draft to the runner', () async {
    final result = await run(refs: reference(['[Verse]', 'hello world', '', 'sing tonight']));
    expect(spy.calls, 1);
    expect(spy.text, 'hello world\nsing tonight');
    expect(spy.path, '/vocal.wav');
    expect(spy.language, 'English');
    expect(spy.duration, audio.duration);
    expect(result.decision.effectiveStrategy, LyricSourceStrategy.referenceFirst);
    expect(result.assembly.referenceAlignmentPlan!.status, ReferenceForcedAlignmentStatus.ready);
    final evidence = result.assembly.items.map((item) => item.referenceTimingEvidence).toList();
    expect(evidence.map((item) => item!.referenceIndex), [1, 3]);
    expect(evidence.map((item) => item!.source), ['forcedAlignment(reference)', 'forcedAlignment(reference)']);
    expect(evidence[0]!.start, const Duration(milliseconds: 500));
    expect(evidence[0]!.end, const Duration(milliseconds: 1300));
    expect(evidence[1]!.start, const Duration(milliseconds: 3500));
  });

  test('alignment evidence never changes proposal document or draft', () async {
    final before = jsonEncode(draft.toJson());
    final ordinary = await run(alignment: false);
    final withEvidence = await run();
    expect(jsonEncode(withEvidence.assembly.proposalDocument.toJson()), jsonEncode(ordinary.assembly.proposalDocument.toJson()));
    expect(jsonEncode(draft.toJson()), before);
    for (var i = 0; i < ordinary.assembly.items.length; i++) {
      expect(withEvidence.assembly.items[i].proposedLine.toJson(), ordinary.assembly.items[i].proposedLine.toJson());
      expect(withEvidence.assembly.items[i].verdict, ordinary.assembly.items[i].verdict);
      expect(withEvidence.assembly.items[i].hasChange, ordinary.assembly.items[i].hasChange);
    }
    expect(ordinary.assembly.referenceAlignmentPlan, isNull);
    expect(ordinary.assembly.items.every((item) => item.referenceTimingEvidence == null), isTrue);
  });

  test('even an accepted row never writes evidence timestamps or their provenance', () async {
    final ordinary = await run(alignment: false);
    final withEvidence = await run();
    const composer = ProofreadV2DocumentComposer();
    for (final selection in [
      LyricProofreadV2Selection(acceptedProposalIndices: {}, restoredDraftIndices: {}),
      LyricProofreadV2Selection(acceptedProposalIndices: {0}, restoredDraftIndices: {}),
      LyricProofreadV2Selection(acceptedProposalIndices: {0, 1}, restoredDraftIndices: {}),
    ]) {
      LyricDocument compose(ProofreadV2RunResult result) => composer.compose(before: draft, proposalDocument: result.assembly.proposalDocument, items: result.assembly.items, droppedItems: result.assembly.droppedItems, selection: selection, effectiveStrategy: result.decision.effectiveStrategy);
      final baseline = compose(ordinary);
      final tested = compose(withEvidence);
      expect(tested.toJson(), baseline.toJson());
      expect(tested.lines.first.startTime, isNot(const Duration(milliseconds: 500)));
      expect(tested.metadata['timingProvenance'], isNot(contains('forcedAlignment(reference)')));
      expect(tested.globalOffset, draft.globalOffset);
    }
  });

  test('protected lines keep their text and timing while reference evidence stays labeled separately', () async {
    final source = draft.copyWith(lines: [draft.lines[0].copyWith(text: 'hello worlds'), draft.lines[1]]);
    final result = await run(source: source, protected: {0});
    final row = result.assembly.items.firstWhere((row) => row.sourceIndex == 0);
    expect(row.verdict, LyricProofreadReviewVerdict.locked);
    expect(row.proposedLine.toJson(), source.lines.first.toJson());
    expect(row.referenceTimingEvidence!.referenceText, 'hello world');
    expect(row.referenceTimingEvidence!.start, const Duration(milliseconds: 500));
    expect(row.hasChange, isFalse);
  });

  test('a reference insertion can have evidence without creating an editable timestamp', () async {
    spy.spans = [span('hello world', 500, 1300), span('additional', 1700, 1900), span('sing tonight', 3500, 4500)];
    final result = await run(refs: reference(['hello world', 'additional', 'sing tonight']));
    final row = result.assembly.items.firstWhere((item) => item.referenceTimingEvidence?.referenceText == 'additional');
    expect(row.referenceTimingEvidence!.referenceIndex, 1);
    expect(row.referenceTimingEvidence!.start, const Duration(milliseconds: 1700));
    expect(row.proposedLine.startTime, isNot(const Duration(milliseconds: 1700)));
    expect(row.sourceIndex, isNull);
  });

  test('matching auto uses reference; unrelated auto uses ASR draft text', () async {
    final matching = await run(strategy: LyricSourceStrategy.auto);
    expect(matching.decision.effectiveStrategy, LyricSourceStrategy.referenceFirst);
    expect(matching.assembly.referenceAlignmentPlan!.status, ReferenceForcedAlignmentStatus.ready);
    expect(spy.text, 'hello world\nsing tonight');
    spy.spans = [];
    final fallback = await run(strategy: LyricSourceStrategy.auto, refs: reference(['completely unrelated words']));
    expect(fallback.decision.effectiveStrategy, LyricSourceStrategy.asrFirst);
    expect(fallback.assembly.referenceAlignmentPlan, isNull);
    expect(fallback.assembly.items.every((row) => row.referenceTimingEvidence == null), isTrue);
    expect(spy.text, 'hello world\nsing tonight');
  });

  test('explicit ASR ignores reference as alignment text', () async {
    spy.spans = [];
    final result = await run(strategy: LyricSourceStrategy.asrFirst, refs: reference(['unrelated']));
    expect(spy.text, 'hello world\nsing tonight');
    expect(result.assembly.referenceAlignmentPlan, isNull);
    expect(result.assembly.explanations.map((e) => e.code), contains(LyricProofreadV2ExplanationCode.referenceIgnoredByAsr));
  });

  test('failed or partial alignment retains ordinary review without time evidence', () async {
    final baseline = await run(alignment: false);
    for (final bad in [<ForcedAlignedSpan>[], [span('hello', 500, 800)], [span('wrong', 500, 800)]]) {
      spy.spans = bad;
      final result = await run();
      expect(result.assembly.referenceAlignmentPlan!.isReady, isFalse);
      expect(result.assembly.referenceAlignmentPlan!.proposals, isEmpty);
      expect(result.assembly.items.every((row) => row.referenceTimingEvidence == null), isTrue);
      expect(result.assembly.proposalDocument.toJson(), baseline.assembly.proposalDocument.toJson());
    }
    spy.error = Exception('offline');
    final offline = await run();
    expect(offline.assembly.referenceAlignmentPlan!.status, ReferenceForcedAlignmentStatus.alignmentUnavailable);
    expect(offline.assembly.proposalDocument.toJson(), baseline.assembly.proposalDocument.toJson());
  });

  test('audio and language failures do not invoke the aligner', () async {
    await expectLater(useCase.build(draft: draft, strategy: LyricSourceStrategy.referenceFirst, reference: reference(['hello world']), useForcedAlignment: true), throwsA(isA<ProofreadV2MissingAudioException>()));
    await expectLater(run(source: draft.copyWith(language: 'unknown')), throwsA(isA<ForcedAlignmentLanguageResolutionException>()));
    expect(spy.calls, 0);
  });

  test('busy is propagated for retry; no fallback is silently used', () async {
    spy.error = const ForcedAlignmentResourceBusyException();
    await expectLater(run(), throwsA(isA<ForcedAlignmentResourceBusyException>()));
  });

  test('reference snapshot is preserved across await', () async {
    final lines = [const ReferenceLyricLine(text: 'hello world'), const ReferenceLyricLine(text: 'sing tonight')];
    final ref = ReferenceLyricInput(lines: lines, timed: false, format: 'txt');
    spy.pending = Completer<List<ForcedAlignedSpan>>();
    final future = run(refs: ref);
    lines.clear();
    spy.pending!.complete(spy.spans);
    final result = await future;
    expect(result.assembly.items.map((item) => item.referenceTimingEvidence!.referenceText), ['hello world', 'sing tonight']);
  });
}
