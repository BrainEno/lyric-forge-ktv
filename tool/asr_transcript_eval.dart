import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

const _sha256Pattern = r'^[0-9a-fA-F]{64}List<String> _tokens(String text) => _tokenizer.tokenize(text);
List<int> _characters(String text) => _tokens(text).join().runes.toList();

class _Candidate {
  final String engine;
  final String? audioSha256;
  final String? modelRevision;
  final String? runtimeVersion;
  final List<String> tokens;
  final List<int> characters;

  _Candidate.parse(dynamic raw, String sampleId)
    : engine = _requiredString(raw, 'engine'),
      audioSha256 = _optionalSha256(raw, 'audioSha256'),
      modelRevision = _optionalString(raw, 'modelRevision'),
      runtimeVersion = _optionalString(raw, 'runtimeVersion'),
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
  final String? audioSha256;
  final int? audioDurationMs;
  final bool? referenceReviewed;
  final List<String> referenceTokens;
  final List<int> referenceCharacters;
  final List<_Candidate> candidates;

  _Sample.parse(dynamic raw)
    : id = _requiredString(raw, 'id'),
      songId = _optionalString(raw, 'songId') ?? _requiredString(raw, 'id'),
      language = _requiredString(raw, 'language'),
      audioSha256 = _optionalSha256(raw, 'audioSha256'),
      audioDurationMs = _optionalInt(raw, 'audioDurationMs'),
      referenceReviewed = _optionalBool(raw, 'referenceReviewed'),
      referenceTokens = _tokens(_requiredText(raw, 'referenceText')),
      referenceCharacters = _characters(_requiredText(raw, 'referenceText')),
      candidates = _parseCandidates(raw) {
    if (referenceTokens.isEmpty || referenceCharacters.isEmpty) {
      throw FormatException(
        'Reference text for sample ' +
            id +
            ' has no normalized lyric characters.',
      );
    }
    if (candidates.isEmpty || candidates.length > _maxCandidates) {
      throw FormatException(
        'Sample ' +
            id +
            ' must contain 1–' +
            _maxCandidates.toString() +
            ' candidates.',
      );
    }
    if (audioDurationMs != null && audioDurationMs! <= 0) {
      throw FormatException('Sample ' + id + ' has invalid audioDurationMs.');
    }
    final names = candidates.map((candidate) => candidate.engine).toSet();
    if (names.length != candidates.length) {
      throw FormatException('Duplicate engine name in sample ' + id);
    }
    for (final candidate in candidates) {
      if (candidate.audioSha256 != null &&
          candidate.audioSha256 != audioSha256) {
        throw FormatException(
          'Candidate ' +
              candidate.engine +
              ' in sample ' +
              id +
              ' has an audioSha256 that does not match the sample input.',
        );
      }
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

class _EditSummary {
  const _EditSummary({
    required this.distance,
    required this.insertions,
    required this.deletions,
    required this.substitutions,
  });

  final int distance;
  final int insertions;
  final int deletions;
  final int substitutions;
}

/// Counts a deterministic minimum edit script from reference to candidate.
///
/// Insertions are candidate-only units; deletions are reference units omitted
/// by the candidate; substitutions are incorrect candidate units.
_EditSummary _editSummary<T>(
  List<T> reference,
  List<T> candidate,
  String context,
) {
  final rows = reference;
  final columns = candidate;
  final width = columns.length + 1;
  final height = rows.length + 1;
  final cellCount = height * width;
  if (cellCount > _maxEditCells) {
    throw FormatException(
      context + ' exceeds the edit-distance limit; split the clip.',
    );
  }

  // Store one direction byte per cell and roll the score rows to keep
  // backtrace memory bounded.
  // 0 = diagonal (match/substitution), 1 = delete reference, 2 = insert candidate.
  final directions = Uint8List(cellCount);
  for (var j = 1; j < width; j++) {
    directions[j] = 2;
  }
  var previous = List<int>.generate(width, (index) => index);
  var current = List<int>.filled(width, 0);
  for (var i = 1; i < height; i++) {
    current[0] = i;
    directions[i * width] = 1;
    for (var j = 1; j < width; j++) {
      final same = rows[i - 1] == columns[j - 1];
      var best = previous[j - 1] + (same ? 0 : 1);
      var direction = 0;
      final deletion = previous[j] + 1;
      if (deletion < best) {
        best = deletion;
        direction = 1;
      }
      final insertion = current[j - 1] + 1;
      if (insertion < best) {
        best = insertion;
        direction = 2;
      }
      current[j] = best;
      directions[i * width + j] = direction;
    }
    final swap = previous;
    previous = current;
    current = swap;
  }

  var i = rows.length;
  var j = columns.length;
  var insertions = 0;
  var deletions = 0;
  var substitutions = 0;
  while (i > 0 || j > 0) {
    final direction = directions[i * width + j];
    if (i > 0 && j > 0 && direction == 0) {
      if (rows[i - 1] != columns[j - 1]) substitutions++;
      i--;
      j--;
    } else if (i > 0 && (j == 0 || direction == 1)) {
      deletions++;
      i--;
    } else {
      insertions++;
      j--;
    }
  }

  return _EditSummary(
    distance: insertions + deletions + substitutions,
    insertions: insertions,
    deletions: deletions,
    substitutions: substitutions,
  );
}

bool _containsCjk(List<String> tokens) =>
    tokens.any((token) => _tokenizer.isCjkToken(token));

class _Score {
  final _Sample sample;
  final _Candidate candidate;
  final _EditSummary characterSummary;
  final _EditSummary tokenSummary;
  final bool wordComparable;

  int get characterEdits => characterSummary.distance;
  int get tokenEdits => tokenSummary.distance;

  _Score(this.sample, this.candidate)
    : characterSummary = _editSummary<int>(
        sample.referenceCharacters,
        candidate.characters,
        'Sample ' +
            sample.id +
            ' / ' +
            candidate.engine +
            ' character comparison',
      ),
      tokenSummary = _editSummary<String>(
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
      'audioSha256': candidate.audioSha256,
      'modelRevision': candidate.modelRevision,
      'runtimeVersion': candidate.runtimeVersion,
      'referenceCharacterCount': sample.referenceCharacters.length,
      'candidateCharacterCount': candidate.characters.length,
      'characterEditCount': characterEdits,
      'characterInsertions': characterSummary.insertions,
      'characterDeletions': characterSummary.deletions,
      'characterSubstitutions': characterSummary.substitutions,
      'normalizedCharacterErrorRate':
          characterEdits / sample.referenceCharacters.length,
      'referenceTokenCount': sample.referenceTokens.length,
      'candidateTokenCount': candidate.tokens.length,
      'tokenEditCount': tokenEdits,
      'tokenInsertions': tokenSummary.insertions,
      'tokenDeletions': tokenSummary.deletions,
      'tokenSubstitutions': tokenSummary.substitutions,
      'normalizedTokenErrorRate': tokenEdits / sample.referenceTokens.length,
      'wordErrorRateAvailable': wordComparable,
      'referenceWordCount': wordComparable
          ? sample.referenceTokens.length
          : null,
      'candidateWordCount': wordComparable ? candidate.tokens.length : null,
      'wordEditCount': wordComparable ? tokenEdits : null,
      'wordInsertions': wordComparable ? tokenSummary.insertions : null,
      'wordDeletions': wordComparable ? tokenSummary.deletions : null,
      'wordSubstitutions': wordComparable ? tokenSummary.substitutions : null,
      'wordErrorRate': wordRate,
    };
  }
}

Map<String, Object?> _summarize(List<_Score> scores) {
  final referenceCharacters = scores.fold<int>(
    0,
    (sum, score) => sum + score.sample.referenceCharacters.length,
  );
  final characterEdits = scores.fold<int>(
    0,
    (sum, score) => sum + score.characterEdits,
  );
  final characterInsertions = scores.fold<int>(
    0,
    (sum, score) => sum + score.characterSummary.insertions,
  );
  final characterDeletions = scores.fold<int>(
    0,
    (sum, score) => sum + score.characterSummary.deletions,
  );
  final characterSubstitutions = scores.fold<int>(
    0,
    (sum, score) => sum + score.characterSummary.substitutions,
  );
  final referenceTokens = scores.fold<int>(
    0,
    (sum, score) => sum + score.sample.referenceTokens.length,
  );
  final tokenEdits = scores.fold<int>(
    0,
    (sum, score) => sum + score.tokenEdits,
  );
  final tokenInsertions = scores.fold<int>(
    0,
    (sum, score) => sum + score.tokenSummary.insertions,
  );
  final tokenDeletions = scores.fold<int>(
    0,
    (sum, score) => sum + score.tokenSummary.deletions,
  );
  final tokenSubstitutions = scores.fold<int>(
    0,
    (sum, score) => sum + score.tokenSummary.substitutions,
  );
  final wordScores = scores.where((score) => score.wordComparable).toList();
  final referenceWords = wordScores.fold<int>(
    0,
    (sum, score) => sum + score.sample.referenceTokens.length,
  );
  final wordEdits = wordScores.fold<int>(
    0,
    (sum, score) => sum + score.tokenEdits,
  );
  final wordInsertions = wordScores.fold<int>(
    0,
    (sum, score) => sum + score.tokenSummary.insertions,
  );
  final wordDeletions = wordScores.fold<int>(
    0,
    (sum, score) => sum + score.tokenSummary.deletions,
  );
  final wordSubstitutions = wordScores.fold<int>(
    0,
    (sum, score) => sum + score.tokenSummary.substitutions,
  );
  return {
    'candidateCount': scores.length,
    'songCount': scores.map((score) => score.sample.songId).toSet().length,
    'normalizedReferenceCharacterCount': referenceCharacters,
    'characterEditCount': characterEdits,
    'characterInsertions': characterInsertions,
    'characterDeletions': characterDeletions,
    'characterSubstitutions': characterSubstitutions,
    'normalizedCharacterErrorRate': characterEdits / referenceCharacters,
    'referenceTokenCount': referenceTokens,
    'tokenEditCount': tokenEdits,
    'tokenInsertions': tokenInsertions,
    'tokenDeletions': tokenDeletions,
    'tokenSubstitutions': tokenSubstitutions,
    'normalizedTokenErrorRate': tokenEdits / referenceTokens,
    'wordErrorSampleCount': wordScores.length,
    'wordErrorUnavailableSampleCount': scores.length - wordScores.length,
    'referenceWordCount': referenceWords,
    'wordEditCount': wordEdits,
    'wordInsertions': wordInsertions,
    'wordDeletions': wordDeletions,
    'wordSubstitutions': wordSubstitutions,
    'wordErrorRate': wordScores.isEmpty ? null : wordEdits / referenceWords,
  };
}

/// Scores Whisper, Qwen, and fusion candidates against the same verified text.
Map<String, Object?> evaluateTranscriptCorpus(String source) {
  final root = jsonDecode(source);
  if (root is! Map<String, dynamic> || root['schemaVersion'] != 1) {
    throw const FormatException(
      'Corpus must be a schemaVersion 1 JSON object.',
    );
  }
  final rawSamples = root['samples'];
  if (rawSamples is! List ||
      rawSamples.isEmpty ||
      rawSamples.length > _maxSamples) {
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
  final engines = scores.map((score) => score.candidate.engine).toSet().toList()
    ..sort();
  final languages = samples.map((sample) => sample.language).toSet().toList()
    ..sort();
  final samplesMissingAudioFingerprint = samples
      .where((sample) => sample.audioSha256 == null)
      .map((sample) => sample.id)
      .toList(growable: false);
  final samplesMissingAudioDuration = samples
      .where((sample) => sample.audioDurationMs == null)
      .map((sample) => sample.id)
      .toList(growable: false);
  final samplesWithoutConfirmedReferenceReview = samples
      .where((sample) => sample.referenceReviewed != true)
      .map((sample) => sample.id)
      .toList(growable: false);
  final candidatesMissingAudioFingerprint = scores
      .where((score) => score.candidate.audioSha256 == null)
      .map(
        (score) => {
          'sampleId': score.sample.id,
          'engine': score.candidate.engine,
        },
      )
      .toList(growable: false);
  final candidatesMissingModelRevision = scores
      .where((score) => score.candidate.modelRevision == null)
      .map(
        (score) => {
          'sampleId': score.sample.id,
          'engine': score.candidate.engine,
        },
      )
      .toList(growable: false);
  final candidatesMissingRuntimeVersion = scores
      .where((score) => score.candidate.runtimeVersion == null)
      .map(
        (score) => {
          'sampleId': score.sample.id,
          'engine': score.candidate.engine,
        },
      )
      .toList(growable: false);
  final provenanceWarnings = <String>[
    if (samplesMissingAudioFingerprint.isNotEmpty)
      'Some samples do not record audioSha256; exact input identity cannot be audited.',
    if (samplesMissingAudioDuration.isNotEmpty)
      'Some samples do not record audioDurationMs.',
    if (samplesWithoutConfirmedReferenceReview.isNotEmpty)
      'Some references are not explicitly marked referenceReviewed: true.',
    if (candidatesMissingAudioFingerprint.isNotEmpty)
      'Some candidates do not record audioSha256.',
    if (candidatesMissingModelRevision.isNotEmpty)
      'Some candidates do not record modelRevision.',
    if (candidatesMissingRuntimeVersion.isNotEmpty)
      'Some candidates do not record runtimeVersion.',
  ];

  return {
    'schemaVersion': 1,
    'evaluator': 'asr-transcript-quality-evaluator-v1',
    'sampleCount': samples.length,
    'candidateCount': scores.length,
    'provenance': {
      'sampleCount': samples.length,
      'samplesWithAudioFingerprint':
          samples.length - samplesMissingAudioFingerprint.length,
      'samplesMissingAudioFingerprint': samplesMissingAudioFingerprint,
      'samplesWithAudioDuration':
          samples.length - samplesMissingAudioDuration.length,
      'samplesMissingAudioDuration': samplesMissingAudioDuration,
      'samplesWithConfirmedReferenceReview':
          samples.length - samplesWithoutConfirmedReferenceReview.length,
      'samplesWithoutConfirmedReferenceReview':
          samplesWithoutConfirmedReferenceReview,
      'candidateCount': scores.length,
      'candidatesWithAudioFingerprint':
          scores.length - candidatesMissingAudioFingerprint.length,
      'candidatesMissingAudioFingerprint': candidatesMissingAudioFingerprint,
      'candidatesWithModelRevision':
          scores.length - candidatesMissingModelRevision.length,
      'candidatesMissingModelRevision': candidatesMissingModelRevision,
      'candidatesWithRuntimeVersion':
          scores.length - candidatesMissingRuntimeVersion.length,
      'candidatesMissingRuntimeVersion': candidatesMissingRuntimeVersion,
      'warnings': provenanceWarnings,
    },
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
                scores
                    .where(
                      (score) =>
                          score.sample.language == language &&
                          score.candidate.engine == engine,
                    )
                    .toList(),
              ),
        },
    },
    'samples': [
      for (final sample in samples)
        {
          'id': sample.id,
          'songId': sample.songId,
          'language': sample.language,
          'audioSha256': sample.audioSha256,
          'audioDurationMs': sample.audioDurationMs,
          'referenceReviewed': sample.referenceReviewed,
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
      'audioSha256':
          'SHA-256 of the exact audio bytes supplied to the recognizer; candidate fingerprints, when present, must match the sample fingerprint.',
      'referenceReviewed':
          'True only after a person has checked the reference against the sung audio; missing or false status is reported as a provenance warning.',
      'editBreakdown':
          'Insertions are candidate-only units, deletions are reference units omitted by the candidate, and substitutions are incorrect candidate units. Counts form one deterministic minimum edit script; their sum equals the edit count.',
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
    stderr.writeln(
      'Invalid ASR transcript evaluation data: ' + error.toString(),
    );
    exitCode = 2;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
  }
}
;

String? _optionalSha256(dynamic raw, String key) {
  final value = raw is Map<String, dynamic> ? raw[key] : null;
  if (value == null) return null;
  if (value is! String || !RegExp(_sha256Pattern).hasMatch(value.trim())) {
    throw FormatException(key + ' must be a 64-character hexadecimal SHA-256.');
  }
  return value.trim().toLowerCase();
}

int? _optionalInt(dynamic raw, String key) {
  final value = raw is Map<String, dynamic> ? raw[key] : null;
  if (value != null && value is! int) {
    throw FormatException(key + ' must be an integer when present.');
  }
  return value as int?;
}

bool? _optionalBool(dynamic raw, String key) {
  final value = raw is Map<String, dynamic> ? raw[key] : null;
  if (value != null && value is! bool) {
    throw FormatException(key + ' must be a boolean when present.');
  }
  return value as bool?;
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
        'Reference text for sample ' +
            id +
            ' has no normalized lyric characters.',
      );
    }
    if (candidates.isEmpty || candidates.length > _maxCandidates) {
      throw FormatException(
        'Sample ' +
            id +
            ' must contain 1–' +
            _maxCandidates.toString() +
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

class _EditSummary {
  const _EditSummary({
    required this.distance,
    required this.insertions,
    required this.deletions,
    required this.substitutions,
  });

  final int distance;
  final int insertions;
  final int deletions;
  final int substitutions;
}

/// Counts a deterministic minimum edit script from reference to candidate.
///
/// Insertions are candidate-only units; deletions are reference units omitted
/// by the candidate; substitutions are incorrect candidate units.
_EditSummary _editSummary<T>(
  List<T> reference,
  List<T> candidate,
  String context,
) {
  final rows = reference;
  final columns = candidate;
  final width = columns.length + 1;
  final height = rows.length + 1;
  final cellCount = height * width;
  if (cellCount > _maxEditCells) {
    throw FormatException(
      context + ' exceeds the edit-distance limit; split the clip.',
    );
  }

  // Store one direction byte per cell and roll the score rows to keep
  // backtrace memory bounded.
  // 0 = diagonal (match/substitution), 1 = delete reference, 2 = insert candidate.
  final directions = Uint8List(cellCount);
  for (var j = 1; j < width; j++) {
    directions[j] = 2;
  }
  var previous = List<int>.generate(width, (index) => index);
  var current = List<int>.filled(width, 0);
  for (var i = 1; i < height; i++) {
    current[0] = i;
    directions[i * width] = 1;
    for (var j = 1; j < width; j++) {
      final same = rows[i - 1] == columns[j - 1];
      var best = previous[j - 1] + (same ? 0 : 1);
      var direction = 0;
      final deletion = previous[j] + 1;
      if (deletion < best) {
        best = deletion;
        direction = 1;
      }
      final insertion = current[j - 1] + 1;
      if (insertion < best) {
        best = insertion;
        direction = 2;
      }
      current[j] = best;
      directions[i * width + j] = direction;
    }
    final swap = previous;
    previous = current;
    current = swap;
  }

  var i = rows.length;
  var j = columns.length;
  var insertions = 0;
  var deletions = 0;
  var substitutions = 0;
  while (i > 0 || j > 0) {
    final direction = directions[i * width + j];
    if (i > 0 && j > 0 && direction == 0) {
      if (rows[i - 1] != columns[j - 1]) substitutions++;
      i--;
      j--;
    } else if (i > 0 && (j == 0 || direction == 1)) {
      deletions++;
      i--;
    } else {
      insertions++;
      j--;
    }
  }

  return _EditSummary(
    distance: insertions + deletions + substitutions,
    insertions: insertions,
    deletions: deletions,
    substitutions: substitutions,
  );
}

bool _containsCjk(List<String> tokens) =>
    tokens.any((token) => _tokenizer.isCjkToken(token));

class _Score {
  final _Sample sample;
  final _Candidate candidate;
  final _EditSummary characterSummary;
  final _EditSummary tokenSummary;
  final bool wordComparable;

  int get characterEdits => characterSummary.distance;
  int get tokenEdits => tokenSummary.distance;

  _Score(this.sample, this.candidate)
    : characterSummary = _editSummary<int>(
        sample.referenceCharacters,
        candidate.characters,
        'Sample ' +
            sample.id +
            ' / ' +
            candidate.engine +
            ' character comparison',
      ),
      tokenSummary = _editSummary<String>(
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
      'characterInsertions': characterSummary.insertions,
      'characterDeletions': characterSummary.deletions,
      'characterSubstitutions': characterSummary.substitutions,
      'normalizedCharacterErrorRate':
          characterEdits / sample.referenceCharacters.length,
      'referenceTokenCount': sample.referenceTokens.length,
      'candidateTokenCount': candidate.tokens.length,
      'tokenEditCount': tokenEdits,
      'tokenInsertions': tokenSummary.insertions,
      'tokenDeletions': tokenSummary.deletions,
      'tokenSubstitutions': tokenSummary.substitutions,
      'normalizedTokenErrorRate': tokenEdits / sample.referenceTokens.length,
      'wordErrorRateAvailable': wordComparable,
      'referenceWordCount': wordComparable
          ? sample.referenceTokens.length
          : null,
      'candidateWordCount': wordComparable ? candidate.tokens.length : null,
      'wordEditCount': wordComparable ? tokenEdits : null,
      'wordInsertions': wordComparable ? tokenSummary.insertions : null,
      'wordDeletions': wordComparable ? tokenSummary.deletions : null,
      'wordSubstitutions': wordComparable ? tokenSummary.substitutions : null,
      'wordErrorRate': wordRate,
    };
  }
}

Map<String, Object?> _summarize(List<_Score> scores) {
  final referenceCharacters = scores.fold<int>(
    0,
    (sum, score) => sum + score.sample.referenceCharacters.length,
  );
  final characterEdits = scores.fold<int>(
    0,
    (sum, score) => sum + score.characterEdits,
  );
  final characterInsertions = scores.fold<int>(
    0,
    (sum, score) => sum + score.characterSummary.insertions,
  );
  final characterDeletions = scores.fold<int>(
    0,
    (sum, score) => sum + score.characterSummary.deletions,
  );
  final characterSubstitutions = scores.fold<int>(
    0,
    (sum, score) => sum + score.characterSummary.substitutions,
  );
  final referenceTokens = scores.fold<int>(
    0,
    (sum, score) => sum + score.sample.referenceTokens.length,
  );
  final tokenEdits = scores.fold<int>(
    0,
    (sum, score) => sum + score.tokenEdits,
  );
  final tokenInsertions = scores.fold<int>(
    0,
    (sum, score) => sum + score.tokenSummary.insertions,
  );
  final tokenDeletions = scores.fold<int>(
    0,
    (sum, score) => sum + score.tokenSummary.deletions,
  );
  final tokenSubstitutions = scores.fold<int>(
    0,
    (sum, score) => sum + score.tokenSummary.substitutions,
  );
  final wordScores = scores.where((score) => score.wordComparable).toList();
  final referenceWords = wordScores.fold<int>(
    0,
    (sum, score) => sum + score.sample.referenceTokens.length,
  );
  final wordEdits = wordScores.fold<int>(
    0,
    (sum, score) => sum + score.tokenEdits,
  );
  final wordInsertions = wordScores.fold<int>(
    0,
    (sum, score) => sum + score.tokenSummary.insertions,
  );
  final wordDeletions = wordScores.fold<int>(
    0,
    (sum, score) => sum + score.tokenSummary.deletions,
  );
  final wordSubstitutions = wordScores.fold<int>(
    0,
    (sum, score) => sum + score.tokenSummary.substitutions,
  );
  return {
    'candidateCount': scores.length,
    'songCount': scores.map((score) => score.sample.songId).toSet().length,
    'normalizedReferenceCharacterCount': referenceCharacters,
    'characterEditCount': characterEdits,
    'characterInsertions': characterInsertions,
    'characterDeletions': characterDeletions,
    'characterSubstitutions': characterSubstitutions,
    'normalizedCharacterErrorRate': characterEdits / referenceCharacters,
    'referenceTokenCount': referenceTokens,
    'tokenEditCount': tokenEdits,
    'tokenInsertions': tokenInsertions,
    'tokenDeletions': tokenDeletions,
    'tokenSubstitutions': tokenSubstitutions,
    'normalizedTokenErrorRate': tokenEdits / referenceTokens,
    'wordErrorSampleCount': wordScores.length,
    'wordErrorUnavailableSampleCount': scores.length - wordScores.length,
    'referenceWordCount': referenceWords,
    'wordEditCount': wordEdits,
    'wordInsertions': wordInsertions,
    'wordDeletions': wordDeletions,
    'wordSubstitutions': wordSubstitutions,
    'wordErrorRate': wordScores.isEmpty ? null : wordEdits / referenceWords,
  };
}

/// Scores Whisper, Qwen, and fusion candidates against the same verified text.
Map<String, Object?> evaluateTranscriptCorpus(String source) {
  final root = jsonDecode(source);
  if (root is! Map<String, dynamic> || root['schemaVersion'] != 1) {
    throw const FormatException(
      'Corpus must be a schemaVersion 1 JSON object.',
    );
  }
  final rawSamples = root['samples'];
  if (rawSamples is! List ||
      rawSamples.isEmpty ||
      rawSamples.length > _maxSamples) {
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
  final engines = scores.map((score) => score.candidate.engine).toSet().toList()
    ..sort();
  final languages = samples.map((sample) => sample.language).toSet().toList()
    ..sort();

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
                scores
                    .where(
                      (score) =>
                          score.sample.language == language &&
                          score.candidate.engine == engine,
                    )
                    .toList(),
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
      'editBreakdown':
          'Insertions are candidate-only units, deletions are reference units omitted by the candidate, and substitutions are incorrect candidate units. Counts form one deterministic minimum edit script; their sum equals the edit count.',
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
    stderr.writeln(
      'Invalid ASR transcript evaluation data: ' + error.toString(),
    );
    exitCode = 2;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
  }
}
