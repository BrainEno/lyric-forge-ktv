import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../lib/features/lyrics/domain/proofreading/lyric_tokenizer.dart';

const _maxSamples = 200;
const _maxCandidates = 10;
const _maxRunes = 20000;
const _maxEditCells = 8000000;
const _tokenizer = LyricTokenizer();

String _requiredString(dynamic raw, String key) {
  if (raw is! Map<String, dynamic> ||
      raw[key] is! String ||
      (raw[key] as String).trim().isEmpty) {
    throw FormatException('Expected non-empty string: ' + key);
  }
  return (raw[key] as String).trim();
}

String _requiredText(dynamic raw, String key) {
  if (raw is! Map<String, dynamic> || raw[key] is! String) {
    throw FormatException('Expected string: ' + key);
  }
  final value = raw[key] as String;
  if (value.runes.length > _maxRunes) {
    throw FormatException(key + ' exceeds the text-size limit.');
  }
  return value;
}

String? _optionalString(dynamic raw, String key) {
  if (raw is! Map<String, dynamic> || raw[key] == null) return null;
  return _requiredString(raw, key);
}

List<String> _tokens(String text) => _tokenizer.tokenize(text);
List<int> _characters(String text) => _tokens(text).join().runes.toList();

class _Candidate {
  final String engine;
  final List<String> tokens;
  final List<int> characters;

  _Candidate.parse(dynamic raw, String sampleId)
    : engine = _requiredString(raw, 'engine'),
      tokens = _tokens(_requiredText(raw, 'text')),
      characters = _characters(_requiredText(raw, 'text')) {
    if (engine.isEmpty) {
      throw FormatException('Empty engine name in sample ' + sampleId);
    }
  }
}

class _Sample {
  final String id;
  final String songId;
  final String language;
  final List<String> referenceTokens;
  final List<int> referenceCharacters;
  final List<_Candidate> candidates;

  _Sample.parse(dynamic raw)
    : id = _requiredString(raw, 'id'),
      songId = _optionalString(raw, 'songId') ?? _requiredString(raw, 'id'),
      language = _requiredString(raw, 'language'),
      referenceTokens = _tokens(_requiredText(raw, 'referenceText')),
      referenceCharacters = _characters(_requiredText(raw, 'referenceText')),
      candidates = _parseCandidates(raw) {
    if (referenceTokens.isEmpty || referenceCharacters.isEmpty) {
      throw FormatException(
        'Reference text for sample ' + id + ' has no normalized lyric characters.',
      );
    }
    if (candidates.isEmpty || candidates.length > _maxCandidates) {
      throw FormatException(
        'Sample ' + id + ' must contain 1–' + _maxCandidates.toString() +
            ' candidates.',
      );
    }
    final names = candidates.map((candidate) => candidate.engine).toSet();
    if (names.length != candidates.length) {
      throw FormatException('Duplicate engine name in sample ' + id);
    }
  }

  static List<_Candidate> _parseCandidates(dynamic raw) {
    if (raw is! Map<String, dynamic> || raw['candidates'] is! List) {
      throw const FormatException('Every sample needs a candidates array.');
    }
    final id = raw['id'] is String ? raw['id'] as String : '(unknown)';
    return (raw['candidates'] as List)
        .map((value) => _Candidate.parse(value, id))
        .toList(growable: false);
  }
}

int _editDistance<T>(List<T> left, List<T> right, String context) {
  if ((left.length + 1) * (right.length + 1) > _maxEditCells) {
    throw FormatException(
      context + ' exceeds the edit-distance limit; split the clip.',
    );
  }
  var rows = left;
  var columns = right;
  if (columns.length > rows.length) {
    final swap = rows;
    rows = columns;
    columns = swap;
  }
  var previous = List<int>.generate(columns.length + 1, (i) => i);
  var current = List<int>.filled(columns.length + 1, 0);
  for (var i = 1; i <= rows.length; i++) {
    current[0] = i;
    for (var j = 1; j <= columns.length; j++) {
      final replace = rows[i - 1] == columns[j - 1] ? 0 : 1;
      current[j] = math.min(
        math.min(current[j - 1] + 1, previous[j] + 1),
        previous[j - 1] + replace,
      );
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[columns.length];
}

bool _containsCjk(List<String> tokens) =>
    tokens.any((token) => _tokenizer.isCjkToken(token));

class _Score {
  final _Sample sample;
  final _Candidate candidate;
  final int characterEdits;
  final int tokenEdits;
  final bool wordComparable;

  _Score(this.sample, this.candidate)
    : characterEdits = _editDistance<int>(
        sample.referenceCharacters,
        candidate.characters,
        'Sample ' + sample.id + ' / ' + candidate.engine + ' character comparison',
      ),
      tokenEdits = _editDistance<String>(
        sample.referenceTokens,
        candidate.tokens,
        'Sample ' + sample.id + ' / ' + candidate.engine + ' token comparison',
      ),
      wordComparable =
          !_containsCjk(sample.referenceTokens) &&
          !_containsCjk(candidate.tokens);

  Map<String, Object?> toJson() {
    final wordRate = wordComparable
        ? tokenEdits / sample.referenceTokens.length
        : null;
    return {
      'sampleId': sample.id,
      'songId': sample.songId,
      'language': sample.language,
      'engine': candidate.engine,
      'referenceCharacterCount': sample.referenceCharacters.length,
      'candidateCharacterCount': candidate.characters.length,
      'characterEditCount': characterEdits,
      'normalizedCharacterErrorRate':
          characterEdits / sample.referenceCharacters.length,
      'referenceTokenCount': sample.referenceTokens.length,
      'candidateTokenCount': candidate.tokens.length,
      'tokenEditCount': tokenEdits,
      'normalizedTokenErrorRate': tokenEdits / sample.referenceTokens.length,
      'wordErrorRateAvailable': wordComparable,
      'referenceWordCount': wordComparable
          ? sample.referenceTokens.length
          : null,
      'candidateWordCount': wordComparable ? candidate.tokens.length : null,
      'wordEditCount': wordComparable ? tokenEdits : null,
      'wordErrorRate': wordRate,
    };
  }
}

Map<String, Object?> _summarize(List<_Score> scores) {
  final referenceCharacters = scores.fold<int>(
    0, (sum, score) => sum + score.sample.referenceCharacters.length,
  );
  final characterEdits = scores.fold<int>(
    0, (sum, score) => sum + score.characterEdits,
  );
  final referenceTokens = scores.fold<int>(
    0, (sum, score) => sum + score.sample.referenceTokens.length,
  );
  final tokenEdits = scores.fold<int>(
    0, (sum, score) => sum + score.tokenEdits,
  );
  final wordScores = scores.where((score) => score.wordComparable).toList();
  final referenceWords = wordScores.fold<int>(
    0, (sum, score) => sum + score.sample.referenceTokens.length,
  );
  final wordEdits = wordScores.fold<int>(
    0, (sum, score) => sum + score.tokenEdits,
  );
  return {
    'candidateCount': scores.length,
    'songCount': scores.map((score) => score.sample.songId).toSet().length,
    'normalizedReferenceCharacterCount': referenceCharacters,
    'characterEditCount': characterEdits,
    'normalizedCharacterErrorRate': characterEdits / referenceCharacters,
    'referenceTokenCount': referenceTokens,
    'tokenEditCount': tokenEdits,
    'normalizedTokenErrorRate': tokenEdits / referenceTokens,
    'wordErrorSampleCount': wordScores.length,
    'wordErrorUnavailableSampleCount': scores.length - wordScores.length,
    'referenceWordCount': referenceWords,
    'wordEditCount': wordEdits,
    'wordErrorRate': wordScores.isEmpty ? null : wordEdits / referenceWords,
  };
}

/// Scores Whisper, Qwen, and fusion candidates against the same verified text.
Map<String, Object?> evaluateTranscriptCorpus(String source) {
  final root = jsonDecode(source);
  if (root is! Map<String, dynamic> || root['schemaVersion'] != 1) {
    throw const FormatException('Corpus must be a schemaVersion 1 JSON object.');
  }
  final rawSamples = root['samples'];
  if (rawSamples is! List || rawSamples.isEmpty || rawSamples.length > _maxSamples) {
    throw const FormatException('Corpus needs 1–200 samples.');
  }
  final samples = rawSamples.map(_Sample.parse).toList(growable: false);
  if (samples.map((sample) => sample.id).toSet().length != samples.length) {
    throw const FormatException('Sample IDs must be unique.');
  }
  final scores = [
    for (final sample in samples)
      for (final candidate in sample.candidates) _Score(sample, candidate),
  ];
  final engines = scores.map((score) => score.candidate.engine).toSet().toList()..sort();
  final languages = samples.map((sample) => sample.language).toSet().toList()..sort();

  return {
    'schemaVersion': 1,
    'evaluator': 'asr-transcript-quality-evaluator-v1',
    'sampleCount': samples.length,
    'candidateCount': scores.length,
    'overallByEngine': {
      for (final engine in engines)
        engine: _summarize(
          scores.where((score) => score.candidate.engine == engine).toList(),
        ),
    },
    'byLanguage': {
      for (final language in languages)
        language: {
          for (final engine in engines)
            if (scores.any(
              (score) =>
                  score.sample.language == language &&
                  score.candidate.engine == engine,
            ))
              engine: _summarize(
                scores.where(
                  (score) =>
                      score.sample.language == language &&
                      score.candidate.engine == engine,
                ).toList(),
              ),
        },
    },
    'samples': [
      for (final sample in samples)
        {
          'id': sample.id,
          'songId': sample.songId,
          'language': sample.language,
          'referenceCharacterCount': sample.referenceCharacters.length,
          'referenceTokenCount': sample.referenceTokens.length,
          'candidates': [
            for (final score in scores.where(
              (score) => score.sample.id == sample.id,
            ))
              score.toJson(),
          ],
        },
    ],
    'interpretation': {
      'normalizedCharacterErrorRate':
          'Character edits / reference characters; case, whitespace and punctuation are ignored.',
      'normalizedTokenErrorRate':
          'Token edits / reference tokens using the shared lyric tokenizer; CJK text is tokenized character by character.',
      'wordErrorRate':
          'Only reported when neither reference nor candidate contains CJK characters.',
      'limitations':
          'This tool does not evaluate timestamps or line segmentation. Use a manually verified reference and the forced-alignment evaluator for timing metrics.',
    },
  };
}

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('--help')) {
    stdout.writeln(
      'Usage: dart run tool/asr_transcript_eval.dart <corpus.json> [--output <report.json>]',
    );
    stdout.writeln('Use a manually checked reference for the same audio clip.');
    if (args.isEmpty) exitCode = 2;
    return;
  }
  String? outputPath;
  if (args.length == 3 && args[1] == '--output') {
    outputPath = args[2];
  } else if (args.length != 1) {
    stderr.writeln('Invalid arguments. Use --help for usage.');
    exitCode = 2;
    return;
  }
  try {
    final input = File(args.first);
    if (!await input.exists()) {
      throw FileSystemException('Evaluation corpus not found.', input.path);
    }
    if (outputPath != null &&
        File(outputPath).absolute.path == input.absolute.path) {
      throw ArgumentError('Report output must not overwrite the input corpus.');
    }
    final report = evaluateTranscriptCorpus(await input.readAsString());
    final encoded = const JsonEncoder.withIndent('  ').convert(report) + '\n';
    if (outputPath == null) {
      stdout.write(encoded);
    } else {
      await File(outputPath).writeAsString(encoded);
      stdout.writeln('Wrote ASR transcript evaluation report: ' + outputPath);
    }
  } on FormatException catch (error) {
    stderr.writeln('Invalid ASR transcript corpus: ' + error.message);
    exitCode = 2;
  } on ArgumentError catch (error) {
    stderr.writeln('Invalid ASR transcript evaluation data: ' + error.toString());
    exitCode = 2;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
  }
}
