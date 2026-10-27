import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/asr_preprocessing_ab_eval.dart' as ab_evaluator;

void main() {
  test(
    'compares each engine on the same reviewed source across pipeline paths',
    () {
      final baseline = _corpus(
        sourceFingerprint: _hash('f'),
        qwenInputFingerprint: _hash('a'),
        whisperInputFingerprint: _hash('b'),
        qwenText: 'hello world',
        whisperText: 'hello worl',
      );
      final shared = _corpus(
        sourceFingerprint: _hash('f'),
        qwenInputFingerprint: _hash('c'),
        whisperInputFingerprint: _hash('c'),
        qwenText: 'hello worl',
        whisperText: 'hello world',
        sharedInput: true,
      );

      final report = ab_evaluator.evaluateAsrPreprocessingComparison(
        baselineCorpus: jsonEncode(baseline),
        sharedCorpus: jsonEncode(shared),
      );

      expect(report['songCount'], 1);
      expect(report['pairedCandidateCount'], 2);
      expect(report['inputAudioChangedCandidateCount'], 2);
      expect(report['preprocessingEffectTestable'], isTrue);

      final byEngine = report['byEngine']! as Map<String, dynamic>;
      final qwen = byEngine['qwen3-asr-1.7b'] as Map<String, dynamic>;
      final whisper = byEngine['whisper-large-v3'] as Map<String, dynamic>;
      expect(qwen['baselineCharacterEditCount'], 0);
      expect(qwen['sharedCharacterEditCount'], 1);
      expect(qwen['characterEditCountDelta'], 1);
      expect(whisper['baselineCharacterEditCount'], 1);
      expect(whisper['sharedCharacterEditCount'], 0);
      expect(whisper['characterEditCountDelta'], -1);

      final pairs = report['pairs']! as List;
      expect(pairs.map((raw) => (raw as Map)['engine']).toSet(), {
        'qwen3-asr-1.7b',
        'whisper-large-v3',
      });
    },
  );

  test('rejects different original-source fingerprints', () {
    final baseline = _corpus(
      sourceFingerprint: _hash('f'),
      qwenInputFingerprint: _hash('a'),
      whisperInputFingerprint: _hash('a'),
      sharedInput: true,
    );
    final shared = _corpus(
      sourceFingerprint: _hash('e'),
      qwenInputFingerprint: _hash('a'),
      whisperInputFingerprint: _hash('a'),
      sharedInput: true,
    );

    expect(
      () => ab_evaluator.evaluateAsrPreprocessingComparison(
        baselineCorpus: jsonEncode(baseline),
        sharedCorpus: jsonEncode(shared),
      ),
      throwsFormatException,
    );
  });

  test('rejects a changed reference even when the source audio matches', () {
    final baseline = _corpus(
      sourceFingerprint: _hash('f'),
      qwenInputFingerprint: _hash('a'),
      whisperInputFingerprint: _hash('b'),
      referenceText: 'hello world',
    );
    final shared = _corpus(
      sourceFingerprint: _hash('f'),
      qwenInputFingerprint: _hash('c'),
      whisperInputFingerprint: _hash('c'),
      referenceText: 'hello there',
      sharedInput: true,
    );

    expect(
      () => ab_evaluator.evaluateAsrPreprocessingComparison(
        baselineCorpus: jsonEncode(baseline),
        sharedCorpus: jsonEncode(shared),
      ),
      throwsFormatException,
    );
  });

  test('rejects changed model/runtime configuration between variants', () {
    final baseline = _corpus(
      sourceFingerprint: _hash('f'),
      qwenInputFingerprint: _hash('a'),
      whisperInputFingerprint: _hash('b'),
    );
    final shared = _corpus(
      sourceFingerprint: _hash('f'),
      qwenInputFingerprint: _hash('c'),
      whisperInputFingerprint: _hash('c'),
      qwenModelRevision: 'qwen-weights-b',
      sharedInput: true,
    );

    expect(
      () => ab_evaluator.evaluateAsrPreprocessingComparison(
        baselineCorpus: jsonEncode(baseline),
        sharedCorpus: jsonEncode(shared),
      ),
      throwsFormatException,
    );
  });

  test('rejects a missing song/engine pair', () {
    final baseline = _corpus(
      sourceFingerprint: _hash('f'),
      qwenInputFingerprint: _hash('a'),
      whisperInputFingerprint: _hash('b'),
    );
    final shared = _corpus(
      sourceFingerprint: _hash('f'),
      qwenInputFingerprint: _hash('c'),
      whisperInputFingerprint: _hash('c'),
      includeWhisper: false,
      sharedInput: true,
    );

    expect(
      () => ab_evaluator.evaluateAsrPreprocessingComparison(
        baselineCorpus: jsonEncode(baseline),
        sharedCorpus: jsonEncode(shared),
      ),
      throwsFormatException,
    );
  });

  test('aggregates WER only over pairs where both variants support WER', () {
    final baseline = _corpus(
      sourceFingerprint: _hash('f'),
      qwenInputFingerprint: _hash('a'),
      whisperInputFingerprint: _hash('b'),
      qwenText: '你好世界',
      whisperText: 'hello worl',
    );
    final shared = _corpus(
      sourceFingerprint: _hash('f'),
      qwenInputFingerprint: _hash('c'),
      whisperInputFingerprint: _hash('c'),
      qwenText: 'unused baseline qwen text',
      sharedQwenText: 'hello world',
      whisperText: 'hello worl',
      sharedWhisperText: 'hello world',
      sharedInput: true,
    );

    final report = ab_evaluator.evaluateAsrPreprocessingComparison(
      baselineCorpus: jsonEncode(baseline),
      sharedCorpus: jsonEncode(shared),
    );
    final byEngine = report['byEngine']! as Map<String, dynamic>;
    final qwen = byEngine['qwen3-asr-1.7b'] as Map<String, dynamic>;
    final whisper = byEngine['whisper-large-v3'] as Map<String, dynamic>;

    expect(qwen['wordErrorRateComparablePairCount'], 0);
    expect(qwen['baselineWordErrorRate'], isNull);
    expect(qwen['sharedWordErrorRate'], isNull);
    expect(whisper['wordErrorRateComparablePairCount'], 1);
    expect(whisper['baselineWordErrorRate'], closeTo(1 / 3, 0.000001));
    expect(whisper['sharedWordErrorRate'], 0);

    final pairs = report['pairs']! as List;
    final qwenPair = pairs.cast<Map<String, dynamic>>().singleWhere(
      (pair) => pair['engine'] == 'qwen3-asr-1.7b',
    );
    expect(qwenPair['wordErrorRateComparable'], isFalse);
    expect(qwenPair['baselineWordErrorRate'], isNull);
    expect(qwenPair['sharedWordErrorRate'], isNull);
  });

  test('flags unchanged input bytes as unable to isolate preprocessing', () {
    final corpus = _corpus(
      sourceFingerprint: _hash('f'),
      qwenInputFingerprint: _hash('a'),
      whisperInputFingerprint: _hash('a'),
      sharedInput: true,
    );

    final report = ab_evaluator.evaluateAsrPreprocessingComparison(
      baselineCorpus: jsonEncode(corpus),
      sharedCorpus: jsonEncode(corpus),
    );

    expect(report['preprocessingEffectTestable'], isFalse);
    expect(report['inputAudioChangedCandidateCount'], 0);
    expect(report['warnings'], isNotEmpty);
  });
}

String _hash(String char) => List<String>.filled(64, char).join();

Map<String, Object?> _corpus({
  required String sourceFingerprint,
  required String qwenInputFingerprint,
  required String whisperInputFingerprint,
  String referenceText = 'hello world',
  String qwenText = 'hello world',
  String? sharedQwenText,
  String whisperText = 'hello world',
  String? sharedWhisperText,
  String qwenModelRevision = 'qwen-weights-a',
  String whisperModelRevision = 'whisper-weights-a',
  bool includeWhisper = true,
  bool sharedInput = false,
}) {
  Map<String, Object?> sample({
    required String id,
    required String audioFingerprint,
    required List<Map<String, Object?>> candidates,
  }) => {
    'id': id,
    'songId': 'song-en-01',
    'language': 'English',
    'sourceAudioSha256': sourceFingerprint,
    'audioSha256': audioFingerprint,
    'audioDurationMs': 12000,
    'referenceReviewed': true,
    'referenceText': referenceText,
    'candidates': candidates,
  };

  Map<String, Object?> candidate({
    required String engine,
    required String audioFingerprint,
    required String text,
    required String modelRevision,
  }) => {
    'engine': engine,
    'audioSha256': audioFingerprint,
    'modelRevision': modelRevision,
    'runtimeVersion': engine == 'qwen3-asr-1.7b'
        ? 'qwen-runtime-1'
        : 'whisper-runtime-1',
    'text': text,
  };

  if (sharedInput) {
    final sharedHash = qwenInputFingerprint;
    return {
      'schemaVersion': 1,
      'samples': [
        sample(
          id: 'song-en-shared',
          audioFingerprint: sharedHash,
          candidates: [
            candidate(
              engine: 'qwen3-asr-1.7b',
              audioFingerprint: sharedHash,
              text: sharedQwenText ?? qwenText,
              modelRevision: qwenModelRevision,
            ),
            if (includeWhisper)
              candidate(
                engine: 'whisper-large-v3',
                audioFingerprint: sharedHash,
                text: sharedWhisperText ?? whisperText,
                modelRevision: whisperModelRevision,
              ),
          ],
        ),
      ],
    };
  }

  return {
    'schemaVersion': 1,
    'samples': [
      sample(
        id: 'song-en-baseline-qwen',
        audioFingerprint: qwenInputFingerprint,
        candidates: [
          candidate(
            engine: 'qwen3-asr-1.7b',
            audioFingerprint: qwenInputFingerprint,
            text: qwenText,
            modelRevision: qwenModelRevision,
          ),
        ],
      ),
      if (includeWhisper)
        sample(
          id: 'song-en-baseline-whisper',
          audioFingerprint: whisperInputFingerprint,
          candidates: [
            candidate(
              engine: 'whisper-large-v3',
              audioFingerprint: whisperInputFingerprint,
              text: whisperText,
              modelRevision: whisperModelRevision,
            ),
          ],
        ),
    ],
  };
}
