import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/asr_transcript_eval.dart' as evaluator;

void main() {
  test('compares engines on the same English reference', () {
    final report = evaluator.evaluateTranscriptCorpus(
      jsonEncode({
        'schemaVersion': 1,
        'samples': [
          {
            'id': 'en-01',
            'songId': 'song-en',
            'language': 'English',
            'referenceText': 'Hello, brave world!',
            'candidates': [
              {'engine': 'whisper-large-v3', 'text': 'Hello brave word'},
              {'engine': 'qwen3-asr-1.7b', 'text': 'Hello world'},
              {'engine': 'highest-quality-fusion', 'text': 'Hello brave world'},
            ],
          },
        ],
      }),
    );
    final overall = report['overallByEngine']! as Map<String, dynamic>;
    final whisper = overall['whisper-large-v3'] as Map<String, dynamic>;
    final qwen = overall['qwen3-asr-1.7b'] as Map<String, dynamic>;
    final fusion = overall['highest-quality-fusion'] as Map<String, dynamic>;
    expect(whisper['normalizedCharacterErrorRate'], closeTo(1 / 15, 0.000001));
    expect(whisper['wordErrorRate'], closeTo(1 / 3, 0.000001));
    expect(qwen['normalizedCharacterErrorRate'], closeTo(5 / 15, 0.000001));
    expect(qwen['wordErrorRate'], closeTo(1 / 3, 0.000001));
    expect(fusion['normalizedCharacterErrorRate'], 0);
    expect(fusion['wordErrorRate'], 0);
    expect(fusion['songCount'], 1);
    expect(report['candidateCount'], 3);
  });

  test(
    'breaks character errors into extra, omitted, and substituted units',
    () {
      final report = evaluator.evaluateTranscriptCorpus(
        jsonEncode({
          'schemaVersion': 1,
          'samples': [
            {
              'id': 'edit-breakdown',
              'language': 'English',
              'referenceText': 'abcdef',
              'candidates': [
                {'engine': 'test-engine', 'text': 'axdefz'},
              ],
            },
          ],
        }),
      );
      final score =
          (report['overallByEngine']! as Map<String, dynamic>)['test-engine']
              as Map<String, dynamic>;
      expect(score['characterEditCount'], 3);
      expect(score['characterInsertions'], 1);
      expect(score['characterDeletions'], 1);
      expect(score['characterSubstitutions'], 1);

      final sample =
          (report['samples']! as List).single as Map<String, dynamic>;
      final candidate =
          (sample['candidates']! as List).single as Map<String, dynamic>;
      expect(candidate['characterInsertions'], 1);
      expect(candidate['characterDeletions'], 1);
      expect(candidate['characterSubstitutions'], 1);
    },
  );

  test('records audio and runtime provenance for repeatable comparisons', () {
    final fingerprint = List<String>.filled(64, 'a').join();
    final report = evaluator.evaluateTranscriptCorpus(
      jsonEncode({
        'schemaVersion': 1,
        'samples': [
          {
            'id': 'provenance-01',
            'songId': 'tracked-song',
            'language': 'English',
            'audioSha256': fingerprint,
            'audioDurationMs': 12345,
            'referenceReviewed': true,
            'referenceText': 'hello world',
            'candidates': [
              {
                'engine': 'whisper-large-v3',
                'audioSha256': fingerprint,
                'modelRevision': 'large-v3@revision-a',
                'runtimeVersion': 'whisper.cpp-1.7',
                'text': 'hello world',
              },
            ],
          },
        ],
      }),
    );
    final provenance = report['provenance']! as Map<String, dynamic>;
    expect(provenance['warnings'], isEmpty);
    expect(provenance['samplesWithAudioFingerprint'], 1);
    expect(provenance['candidatesWithAudioFingerprint'], 1);
    final sample = (report['samples']! as List).single as Map<String, dynamic>;
    expect(sample['audioSha256'], fingerprint);
    expect(sample['audioDurationMs'], 12345);
    expect(sample['referenceReviewed'], isTrue);
    final candidate =
        (sample['candidates']! as List).single as Map<String, dynamic>;
    expect(candidate['modelRevision'], 'large-v3@revision-a');
    expect(candidate['runtimeVersion'], 'whisper.cpp-1.7');
  });

  test('keeps legacy corpus compatible but reports missing provenance', () {
    final report = evaluator.evaluateTranscriptCorpus(
      jsonEncode({
        'schemaVersion': 1,
        'samples': [
          {
            'id': 'legacy-01',
            'language': 'English',
            'referenceText': 'hello world',
            'candidates': [
              {'engine': 'legacy-engine', 'text': 'hello world'},
            ],
          },
        ],
      }),
    );
    final provenance = report['provenance']! as Map<String, dynamic>;
    expect(provenance['samplesMissingAudioFingerprint'], ['legacy-01']);
    expect(provenance['samplesMissingAudioDuration'], ['legacy-01']);
    expect(provenance['samplesWithoutConfirmedReferenceReview'], ['legacy-01']);
    expect(
      (provenance['candidatesMissingAudioFingerprint']! as List).length,
      1,
    );
    expect((provenance['candidatesMissingModelRevision']! as List).length, 1);
    expect((provenance['candidatesMissingRuntimeVersion']! as List).length, 1);
    expect((provenance['warnings']! as List).length, 6);
  });

  test('rejects mismatched candidate audio fingerprints', () {
    final reportInput = {
      'schemaVersion': 1,
      'samples': [
        {
          'id': 'mismatch-01',
          'language': 'English',
          'audioSha256': List<String>.filled(64, 'a').join(),
          'referenceText': 'hello world',
          'candidates': [
            {
              'engine': 'qwen',
              'audioSha256': List<String>.filled(64, 'b').join(),
              'text': 'hello world',
            },
          ],
        },
      ],
    };
    expect(
      () => evaluator.evaluateTranscriptCorpus(jsonEncode(reportInput)),
      throwsFormatException,
    );
  });

  test('validates audio fingerprint, duration, and review status fields', () {
    Map<String, Object?> corpus({
      Object? fingerprint,
      Object? duration = 1200,
      Object? reviewed = true,
    }) => {
      'schemaVersion': 1,
      'samples': [
        {
          'id': 'invalid-provenance',
          'language': 'English',
          if (fingerprint != null) 'audioSha256': fingerprint,
          'audioDurationMs': duration,
          'referenceReviewed': reviewed,
          'referenceText': 'hello world',
          'candidates': [
            {'engine': 'engine-a', 'text': 'hello world'},
          ],
        },
      ],
    };

    expect(
      () => evaluator.evaluateTranscriptCorpus(
        jsonEncode(corpus(fingerprint: 'not-a-sha256')),
      ),
      throwsFormatException,
    );
    expect(
      () => evaluator.evaluateTranscriptCorpus(jsonEncode(corpus(duration: 0))),
      throwsFormatException,
    );
    expect(
      () => evaluator.evaluateTranscriptCorpus(
        jsonEncode(corpus(reviewed: 'yes')),
      ),
      throwsFormatException,
    );
  });

  test('normalizes full-width Latin and suppresses WER for CJK text', () {
    final report = evaluator.evaluateTranscriptCorpus(
      jsonEncode({
        'schemaVersion': 1,
        'samples': [
          {
            'id': 'ja-01',
            'language': 'Japanese',
            'referenceText': 'Ｈｅｌｌｏ、世界！',
            'candidates': [
              {'engine': 'qwen3-asr-1.7b', 'text': 'hello 世界'},
            ],
          },
        ],
      }),
    );
    final score =
        (report['overallByEngine']! as Map<String, dynamic>)['qwen3-asr-1.7b']
            as Map<String, dynamic>;
    expect(score['normalizedCharacterErrorRate'], 0);
    expect(score['wordErrorRate'], isNull);
    expect(score['wordErrorSampleCount'], 0);
    expect(score['wordErrorUnavailableSampleCount'], 1);
    final japanese =
        (report['byLanguage']! as Map<String, dynamic>)['Japanese']
            as Map<String, dynamic>;
    expect(
      (japanese['qwen3-asr-1.7b'] as Map)['normalizedCharacterErrorRate'],
      0,
    );
  });

  test('empty candidate output is counted as a total omission', () {
    final report = evaluator.evaluateTranscriptCorpus(
      jsonEncode({
        'schemaVersion': 1,
        'samples': [
          {
            'id': 'empty-output',
            'language': 'English',
            'referenceText': 'hello world',
            'candidates': [
              {'engine': 'whisper', 'text': ''},
            ],
          },
        ],
      }),
    );
    final score =
        (report['overallByEngine']! as Map<String, dynamic>)['whisper']
            as Map<String, dynamic>;
    expect(score['normalizedCharacterErrorRate'], 1);
    expect(score['normalizedTokenErrorRate'], 1);
    expect(score['wordErrorRate'], 1);
    expect(score['candidateCount'], 1);
  });

  test('aggregates edit counts before calculating overall WER', () {
    final report = evaluator.evaluateTranscriptCorpus(
      jsonEncode({
        'schemaVersion': 1,
        'samples': [
          {
            'id': 'short',
            'songId': 'short-song',
            'language': 'English',
            'referenceText': 'a b',
            'candidates': [
              {'engine': 'engine-a', 'text': 'a'},
            ],
          },
          {
            'id': 'long',
            'songId': 'long-song',
            'language': 'English',
            'referenceText': 'one two three four',
            'candidates': [
              {'engine': 'engine-a', 'text': 'one two three four'},
            ],
          },
        ],
      }),
    );
    final score =
        (report['overallByEngine']! as Map<String, dynamic>)['engine-a']
            as Map<String, dynamic>;
    expect(score['wordErrorRate'], closeTo(1 / 6, 0.000001));
    expect(score['songCount'], 2);
    expect(score['candidateCount'], 2);
  });

  test(
    'rejects duplicate sample IDs, engine names and empty normalized reference',
    () {
      Map<String, Object?> sample({
        String id = 'sample',
        String reference = 'valid lyric',
        List<Map<String, String>>? candidates,
      }) => {
        'id': id,
        'language': 'English',
        'referenceText': reference,
        'candidates':
            candidates ??
            [
              {'engine': 'engine-a', 'text': 'valid lyric'},
            ],
      };

      expect(
        () => evaluator.evaluateTranscriptCorpus(
          jsonEncode({
            'schemaVersion': 1,
            'samples': [sample(), sample()],
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => evaluator.evaluateTranscriptCorpus(
          jsonEncode({
            'schemaVersion': 1,
            'samples': [
              sample(
                candidates: [
                  {'engine': 'same', 'text': 'one'},
                  {'engine': 'same', 'text': 'two'},
                ],
              ),
            ],
          }),
        ),
        throwsFormatException,
      );
      expect(
        () => evaluator.evaluateTranscriptCorpus(
          jsonEncode({
            'schemaVersion': 1,
            'samples': [sample(reference: ' !!! ')],
          }),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'CLI writes report separately and refuses to overwrite the corpus',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'asr-transcript-eval-',
      );
      final corpus = File(temp.path + '/corpus.json');
      final reportFile = File(temp.path + '/report.json');
      await corpus.writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'samples': [
            {
              'id': 'cli',
              'language': 'English',
              'referenceText': 'hello',
              'candidates': [
                {'engine': 'qwen', 'text': 'hello'},
              ],
            },
          ],
        }),
      );
      try {
        exitCode = 0;
        await evaluator.main([corpus.path, '--output', reportFile.path]);
        expect(exitCode, 0);
        expect(await reportFile.exists(), isTrue);
        expect(
          (jsonDecode(await reportFile.readAsString()) as Map)['evaluator'],
          'asr-transcript-quality-evaluator-v1',
        );
        exitCode = 0;
        await evaluator.main([corpus.path, '--output', corpus.path]);
        expect(exitCode, 2);
        expect(
          (jsonDecode(await corpus.readAsString()) as Map)['schemaVersion'],
          1,
        );
      } finally {
        exitCode = 0;
        await temp.delete(recursive: true);
      }
    },
  );
}
