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
