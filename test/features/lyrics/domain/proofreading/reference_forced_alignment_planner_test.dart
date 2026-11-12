import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_input.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/reference_lyric_line.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/reference_forced_alignment_planner.dart';

const planner = ReferenceForcedAlignmentPlanner();
const duration = Duration(seconds: 30);

ReferenceLyricInput input(
  List<String> texts, {
  String? title,
  String? artist,
  bool timed = false,
}) => ReferenceLyricInput(
  lines: [
    for (final text in texts)
      ReferenceLyricLine(
        text: text,
        startTime: timed ? const Duration(seconds: 20) : null,
        endTime: timed ? const Duration(seconds: 21) : null,
      ),
  ],
  timed: timed,
  format: timed ? 'lrc' : 'txt',
  title: title,
  artist: artist,
);

ForcedAlignedSpan span(String text, int startMs, int endMs) => ForcedAlignedSpan(
  text: text,
  start: Duration(milliseconds: startMs),
  end: Duration(milliseconds: endMs),
);

PreparedReferenceAlignment prepared(List<String> texts) =>
    planner.prepare(input(texts)).prepared!;

void main() {
  group('prepare sanitized reference snapshot', () {
    test('retains original indices after metadata, section headers and blanks', () {
      final result = planner.prepare(input([
        'My Song',
        '作词：someone',
        '',
        '[Verse 1]',
        '  hello   world ',
        '[Chorus]',
        ' tonight ',
      ], title: 'My Song'));
      expect(result.status, ReferenceForcedAlignmentStatus.ready);
      final value = result.prepared!;
      expect(value.text, 'hello world\ntonight');
      expect(value.lines.map((line) => line.referenceIndex), [4, 6]);
      expect(value.lines.map((line) => line.text), ['hello world', 'tonight']);
      expect(() => value.lines.clear(), throwsUnsupportedError);
    });

    test('an empty or metadata-only reference never reaches alignment', () {
      for (final texts in [<String>[], ['', '  '], ['[Chorus]', '作词：A']]) {
        final result = planner.prepare(input(texts));
        expect(result.status, ReferenceForcedAlignmentStatus.noUsableLyrics);
        expect(result.prepared, isNull);
      }
    });

    test('embedded newlines and CR cannot corrupt original index mapping', () {
      for (final text in ['first\nsecond', 'first\rsecond', 'first\r\nsecond']) {
        final result = planner.prepare(input(['ok', text]));
        expect(result.status, ReferenceForcedAlignmentStatus.invalidReference);
        expect(result.prepared, isNull);
      }
    });

    test('rejects excessive line count and line length before sanitizing', () {
      final tooMany = List<String>.filled(ReferenceForcedAlignmentPlanner.maxReferenceLines + 1, 'a');
      expect(planner.prepare(input(tooMany)).status, ReferenceForcedAlignmentStatus.referenceLimitExceeded);
      final tooLong = 'a' * (ReferenceForcedAlignmentPlanner.maxLineCodeUnits + 1);
      expect(planner.prepare(input([tooLong])).status, ReferenceForcedAlignmentStatus.referenceLimitExceeded);
      expect(planner.prepare(input(['a'], title: tooLong)).status, ReferenceForcedAlignmentStatus.referenceLimitExceeded);
      expect(planner.prepare(input(['a'], artist: tooLong)).status, ReferenceForcedAlignmentStatus.referenceLimitExceeded);
    });

    test('total text budget is bounded independently of individual lines', () {
      final texts = List<String>.filled(51, 'a' * 4000);
      expect(planner.prepare(input(texts)).status, ReferenceForcedAlignmentStatus.referenceLimitExceeded);
      expect(planner.prepare(input(List<String>.filled(50, 'a' * 4000))).status, ReferenceForcedAlignmentStatus.ready);
    });

    test('reference timestamps do not become aligner output', () {
      final value = planner.prepare(input(['hello'], timed: true)).prepared!;
      final result = planner.plan(reference: value, spans: [span('hello', 300, 900)], audioDuration: duration);
      expect(result.proposals.single.start, const Duration(milliseconds: 300));
      expect(result.proposals.single.end, const Duration(milliseconds: 900));
    });
  });

  group('complete line timing proposals', () {
    test('combines consecutive tokens without changing their bounds', () {
      final result = planner.plan(
        reference: prepared(['hello world', 'sing tonight']),
        spans: [span('hello', 100, 500), span('world', 600, 1000), span('sing', 2000, 2200), span('tonight', 2300, 2900)],
        audioDuration: duration,
      );
      expect(result.status, ReferenceForcedAlignmentStatus.ready);
      expect(result.isReady, isTrue);
      expect(result.proposals, hasLength(2));
      expect(result.proposals[0].referenceIndex, 0);
      expect(result.proposals[0].referenceText, 'hello world');
      expect(result.proposals[0].start, const Duration(milliseconds: 100));
      expect(result.proposals[0].end, const Duration(milliseconds: 1000));
      expect(result.proposals[1].start, const Duration(seconds: 2));
      expect(result.proposals[1].end, const Duration(milliseconds: 2900));
      expect(result.proposals.every((line) => line.source == 'forcedAlignment(reference)'), isTrue);
      expect(() => result.proposals.clear(), throwsUnsupportedError);
    });

    test('case and whitespace differences are allowed, punctuation preserved', () {
      final result = planner.plan(reference: prepared(['Hello, world!', "It's me."]), spans: [
        span('HELLO,', 0, 200), span(' world! ', 200, 500), span('It', 800, 900), span("'s", 900, 1000), span('ME.', 1000, 1500),
      ], audioDuration: duration);
      expect(result.status, ReferenceForcedAlignmentStatus.ready);
      expect(result.proposals[1].referenceText, "It's me.");
    });

    test('supports Chinese, Japanese, Korean, emoji and supplementary characters', () {
      final result = planner.plan(reference: prepared(['我爱𠀀🙂', '歌を歌う', '안녕하세요']), spans: [
        span('我', 0, 100), span('爱𠀀', 100, 200), span('🙂', 200, 300),
        span('歌を', 500, 600), span('歌う', 600, 800),
        span('안녕', 1000, 1100), span('하세요', 1100, 1300),
      ], audioDuration: duration);
      expect(result.status, ReferenceForcedAlignmentStatus.ready);
      expect(result.proposals.map((line) => line.referenceText), ['我爱𠀀🙂', '歌を歌う', '안녕하세요']);
    });

    test('repeated lyrics consume distinct spans in order', () {
      final result = planner.plan(reference: prepared(['la la', 'la la', 'la la']), spans: [
        span('la', 100, 200), span('la', 200, 300),
        span('la', 1000, 1100), span('la', 1100, 1200),
        span('la', 2000, 2100), span('la', 2100, 2200),
      ], audioDuration: duration);
      expect(result.status, ReferenceForcedAlignmentStatus.ready);
      expect(result.proposals.map((line) => line.start.inMilliseconds), [100, 1000, 2000]);
      expect(result.proposals.map((line) => line.end.inMilliseconds), [300, 1200, 2200]);
    });

    test('permits adjacent spans and an end exactly at audio duration', () {
      final result = planner.plan(reference: prepared(['a', 'b']), spans: [span('a', 0, 1000), span('b', 1000, 30000)], audioDuration: duration);
      expect(result.status, ReferenceForcedAlignmentStatus.ready);
      expect(result.proposals.last.end, duration);
    });
  });

  group('no partial timing proposals on invalid output', () {
    void expectFailure(ReferenceForcedAlignmentPlan result, ReferenceForcedAlignmentStatus status, {int? line, int? spanAt}) {
      expect(result.status, status);
      expect(result.isReady, isFalse);
      expect(result.proposals, isEmpty);
      expect(result.referenceIndex, line);
      expect(result.spanIndex, spanAt);
    }

    test('empty and incomplete responses identify original reference row', () {
      final ref = planner.prepare(input(['[Verse]', 'a', '', 'b'])).prepared!;
      expectFailure(planner.plan(reference: ref, spans: [], audioDuration: duration), ReferenceForcedAlignmentStatus.incompleteAlignment, line: 1, spanAt: 0);
      expectFailure(planner.plan(reference: ref, spans: [span('a', 0, 100)], audioDuration: duration), ReferenceForcedAlignmentStatus.incompleteAlignment, line: 3, spanAt: 1);
    });

    test('mismatched word, missing punctuation, emoji or changed accents fail closed', () {
      for (final pair in [
        ['hello!', 'hello'], ['A🙂', 'A'], ['café', 'cafe'], ['hello', 'yellow'],
      ]) {
        expectFailure(planner.plan(reference: prepared([pair[0]]), spans: [span(pair[1], 0, 100)], audioDuration: duration), ReferenceForcedAlignmentStatus.textMismatch, line: 0, spanAt: 0);
      }
    });

    test('a single span crossing a lyric-line boundary is not split by guesswork', () {
      expectFailure(planner.plan(reference: prepared(['hello', 'world']), spans: [span('hello world', 0, 1000)], audioDuration: duration), ReferenceForcedAlignmentStatus.textMismatch, line: 0, spanAt: 0);
    });

    test('extra leading, middle and trailing tokens cannot be skipped', () {
      final ref = prepared(['a', 'b']);
      final cases = [
        [span('x', 0, 100), span('a', 100, 200), span('b', 200, 300)],
        [span('a', 0, 100), span('x', 100, 200), span('b', 200, 300)],
        [span('a', 0, 100), span('b', 100, 200), span('x', 200, 300)],
      ];
      final first = planner.plan(reference: ref, spans: cases[0], audioDuration: duration);
      final middle = planner.plan(reference: ref, spans: cases[1], audioDuration: duration);
      final trailing = planner.plan(reference: ref, spans: cases[2], audioDuration: duration);
      expectFailure(first, ReferenceForcedAlignmentStatus.textMismatch, line: 0, spanAt: 0);
      expectFailure(middle, ReferenceForcedAlignmentStatus.textMismatch, line: 1, spanAt: 1);
      expectFailure(trailing, ReferenceForcedAlignmentStatus.extraSpans, spanAt: 2);
    });

    test('rejects negative, zero-length, reversed, overlapping, out-of-range or empty spans', () {
      final ref = prepared(['a', 'b']);
      final cases = [
        [span('a', -1, 10)],
        [span('a', 10, 10)],
        [span('a', 20, 10)],
        [span('a', 0, 200), span('b', 100, 300)],
        [span('a', 500, 600), span('b', 100, 200)],
        [span('a', 0, 30001)],
        [span(' ', 0, 100)],
      ];
      for (var i = 0; i < cases.length; i++) {
        final expectedIndex = i == 3 || i == 4 ? 1 : 0;
        expectFailure(planner.plan(reference: ref, spans: cases[i], audioDuration: duration), ReferenceForcedAlignmentStatus.invalidSpan, spanAt: expectedIndex);
      }
    });

    test('nonpositive duration and excessive response size fail before matching', () {
      final ref = prepared(['a']);
      for (final length in [Duration.zero, const Duration(milliseconds: -1)]) {
        expectFailure(planner.plan(reference: ref, spans: [span('a', 0, 10)], audioDuration: length), ReferenceForcedAlignmentStatus.invalidAudio);
      }
      final tooMany = List<ForcedAlignedSpan>.filled(ReferenceForcedAlignmentPlanner.maxSpans + 1, span('a', 0, 1));
      expectFailure(planner.plan(reference: ref, spans: tooMany, audioDuration: duration), ReferenceForcedAlignmentStatus.spanLimitExceeded);
      final huge = 'a' * (ReferenceForcedAlignmentPlanner.maxSpanCodeUnits + 1);
      expectFailure(planner.plan(reference: ref, spans: [span(huge, 0, 1)], audioDuration: duration), ReferenceForcedAlignmentStatus.invalidSpan, spanAt: 0);
    });

    test('total span text budget is enforced before matching', () {
      final spans = [for (var i = 0; i < 51; i++) span('a' * 4000, i, i + 1)];
      expectFailure(planner.plan(reference: prepared(['a']), spans: spans, audioDuration: duration), ReferenceForcedAlignmentStatus.spanLimitExceeded, spanAt: 50);
    });
  });

  group('alignment service orchestration', () {
    test('passes sanitized reference, path, language and audio duration once', () async {
      var calls = 0;
      String? observedPath;
      String? observedText;
      String? observedLanguage;
      Duration? observedDuration;
      final service = ReferenceForcedAlignmentService(runner: ({required audioPath, required text, required language, required audioDuration}) async {
        calls++;
        observedPath = audioPath;
        observedText = text;
        observedLanguage = language;
        observedDuration = audioDuration;
        return [span('hello', 100, 300), span('world', 300, 500), span('sing', 1000, 1500)];
      });
      final source = input(['[Verse]', ' hello world ', '', 'sing']);
      final result = await service.build(reference: source, audioPath: '/vocals.wav', language: 'English', audioDuration: duration);
      expect(calls, 1);
      expect(observedPath, '/vocals.wav');
      expect(observedText, 'hello world\nsing');
      expect(observedLanguage, 'English');
      expect(observedDuration, duration);
      expect(result.status, ReferenceForcedAlignmentStatus.ready);
      expect(result.proposals.map((p) => p.referenceIndex), [1, 3]);
      expect(source.lines[1].text, ' hello world ');
    });

    test('invalid preparation and audio skip the runner', () async {
      var calls = 0;
      final service = ReferenceForcedAlignmentService(runner: ({required audioPath, required text, required language, required audioDuration}) async {
        calls++;
        return [];
      });
      final missing = await service.build(reference: input(['[Chorus]']), audioPath: 'x', language: 'English', audioDuration: duration);
      expect(missing.status, ReferenceForcedAlignmentStatus.noUsableLyrics);
      final invalid = await service.build(reference: input(['a\nb']), audioPath: 'x', language: 'English', audioDuration: duration);
      expect(invalid.status, ReferenceForcedAlignmentStatus.invalidReference);
      for (final (path, language, audioDuration) in [
        ('', 'English', duration),
        (' ', 'English', duration),
        ('x', '', duration),
        ('x', ' ', duration),
        ('x', 'English', Duration.zero),
      ]) {
        final result = await service.build(reference: input(['a']), audioPath: path, language: language, audioDuration: audioDuration);
        expect(result.status, ReferenceForcedAlignmentStatus.invalidAudio);
        expect(result.proposals, isEmpty);
      }
      expect(calls, 0);
    });

    test('runtime errors are unavailable, resource contention is retryable', () async {
      final unavailable = ReferenceForcedAlignmentService(runner: ({required audioPath, required text, required language, required audioDuration}) async => throw Exception('offline'));
      final result = await unavailable.build(reference: input(['a']), audioPath: 'x', language: 'English', audioDuration: duration);
      expect(result.status, ReferenceForcedAlignmentStatus.alignmentUnavailable);
      expect(result.proposals, isEmpty);
      final busy = ReferenceForcedAlignmentService(runner: ({required audioPath, required text, required language, required audioDuration}) async => throw const ForcedAlignmentResourceBusyException());
      await expectLater(busy.build(reference: input(['a']), audioPath: 'x', language: 'English', audioDuration: duration), throwsA(isA<ForcedAlignmentResourceBusyException>()));
    });

    test('programmer errors are not silently reported as runtime failure', () async {
      final service = ReferenceForcedAlignmentService(runner: ({required audioPath, required text, required language, required audioDuration}) async => throw StateError('bug'));
      await expectLater(service.build(reference: input(['a']), audioPath: 'x', language: 'English', audioDuration: duration), throwsStateError);
    });

    test('reference mutation during async call cannot remap the prepared output', () async {
      final lines = [const ReferenceLyricLine(text: 'hello'), const ReferenceLyricLine(text: 'world')];
      final source = ReferenceLyricInput(lines: lines, timed: false, format: 'txt');
      final pending = Completer<List<ForcedAlignedSpan>>();
      final service = ReferenceForcedAlignmentService(runner: ({required audioPath, required text, required language, required audioDuration}) => pending.future);
      final future = service.build(reference: source, audioPath: 'x', language: 'English', audioDuration: duration);
      lines[0] = const ReferenceLyricLine(text: 'changed');
      lines.clear();
      pending.complete([span('hello', 0, 100), span('world', 200, 300)]);
      final result = await future;
      expect(result.status, ReferenceForcedAlignmentStatus.ready);
      expect(result.proposals.map((p) => p.referenceText), ['hello', 'world']);
      expect(result.proposals.map((p) => p.referenceIndex), [0, 1]);
    });

    test('valid backend but incomplete output remains a failure, not unavailable', () async {
      final service = ReferenceForcedAlignmentService(runner: ({required audioPath, required text, required language, required audioDuration}) async => [span('hello', 0, 100)]);
      final result = await service.build(reference: input(['hello', 'world']), audioPath: 'x', language: 'English', audioDuration: duration);
      expect(result.status, ReferenceForcedAlignmentStatus.incompleteAlignment);
      expect(result.referenceIndex, 1);
      expect(result.proposals, isEmpty);
    });
  });
}
