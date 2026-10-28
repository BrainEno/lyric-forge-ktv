import 'dart:convert';
import 'dart:io';

import 'asr_transcript_eval.dart' as transcript_eval;

const _shaPattern = r'^[0-9a-f]{64}$';
const _metricFields = [
  'characterEditCount',
  'characterInsertions',
  'characterDeletions',
  'characterSubstitutions',
  'tokenEditCount',
  'tokenInsertions',
  'tokenDeletions',
  'tokenSubstitutions',
  'normalizedCharacterErrorRate',
  'normalizedTokenErrorRate',
];

String _requiredString(Map<String, dynamic> value, String key) {
  final raw = value[key];
  if (raw is! String || raw.trim().isEmpty) {
    throw FormatException('Expected non-empty string: $key');
  }
  return raw.trim();
}

String _requiredSha(Map<String, dynamic> value, String key) {
  final hash = _requiredString(value, key).toLowerCase();
  if (!RegExp(_shaPattern).hasMatch(hash)) {
    throw FormatException('$key must be a 64-character SHA-256.');
  }
  return hash;
}

Map<String, dynamic> _map(dynamic value, String label) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$label must be a JSON object.');
  }
  return value;
}

List<dynamic> _list(dynamic value, String label) {
  if (value is! List) throw FormatException('$label must be a JSON array.');
  return value;
}

class _Sample {
  final String id;
  final String songId;
  final String language;
  final String referenceText;
  final String sourceSha;
  final int durationMs;

  const _Sample({
    required this.id,
    required this.songId,
    required this.language,
    required this.referenceText,
    required this.sourceSha,
    required this.durationMs,
  });

  factory _Sample.parse(dynamic raw) {
    final value = _map(raw, 'Sample');
    final id = _requiredString(value, 'id');
    final text = value['referenceText'];
    final duration = value['audioDurationMs'];
    if (text is! String || text.trim().isEmpty) {
      throw FormatException('Sample $id needs referenceText.');
    }
    if (duration is! int || duration <= 0) {
      throw FormatException('Sample $id needs positive audioDurationMs.');
    }
    if (value['referenceReviewed'] != true) {
      throw FormatException('Sample $id must have referenceReviewed: true.');
    }
    final rawSongId = value['songId'];
    if (rawSongId != null &&
        (rawSongId is! String || rawSongId.trim().isEmpty)) {
      throw FormatException('Sample $id has invalid songId.');
    }
    return _Sample(
      id: id,
      songId: rawSongId == null ? id : (rawSongId as String).trim(),
      language: _requiredString(value, 'language'),
      referenceText: text,
      sourceSha: _requiredSha(value, 'sourceAudioSha256'),
      durationMs: duration,
    );
  }
}

class _Output {
  final _Sample sample;
  final Map<String, dynamic> score;
  const _Output(this.sample, this.score);

  String get engine => _requiredString(score, 'engine');
  String get audioSha => _requiredSha(score, 'audioSha256');
  String get model => _requiredString(score, 'modelRevision');
  String get runtime => _requiredString(score, 'runtimeVersion');

  int integer(String field) {
    final value = score[field];
    if (value is! int) throw FormatException('Invalid metric: $field.');
    return value;
  }

  double number(String field) {
    final value = score[field];
    if (value is! num) throw FormatException('Invalid metric: $field.');
    return value.toDouble();
  }
}

class _Configuration {
  final String model;
  final String runtime;
  const _Configuration(this.model, this.runtime);

  @override
  bool operator ==(Object other) =>
      other is _Configuration &&
      other.model == model &&
      other.runtime == runtime;
  @override
  int get hashCode => Object.hash(model, runtime);
}

class _Pair {
  final _Output before;
  final _Output after;
  const _Pair(this.before, this.after);

  String get songId => before.sample.songId;
  String get engine => before.engine;
  bool get audioChanged => before.audioSha != after.audioSha;

  Map<String, Object?> toJson() {
    final result = <String, Object?>{
      'songId': songId,
      'language': before.sample.language,
      'engine': engine,
      'sourceAudioSha256': before.sample.sourceSha,
      'baselineInputAudioSha256': before.audioSha,
      'sharedInputAudioSha256': after.audioSha,
      'inputAudioChanged': audioChanged,
      'modelRevision': before.model,
      'runtimeVersion': before.runtime,
      'referenceCharacterCount': before.integer('referenceCharacterCount'),
      'referenceTokenCount': before.integer('referenceTokenCount'),
      'baselineWordErrorRate':
          before.score['wordErrorRate'] is num &&
              after.score['wordErrorRate'] is num
          ? (before.score['wordErrorRate'] as num).toDouble()
          : null,
      'sharedWordErrorRate':
          before.score['wordErrorRate'] is num &&
              after.score['wordErrorRate'] is num
          ? (after.score['wordErrorRate'] as num).toDouble()
          : null,
      'wordErrorRateComparable':
          before.score['wordErrorRate'] is num &&
          after.score['wordErrorRate'] is num,
    };
    for (final metric in _metricFields) {
      result['baseline' + _capitalize(metric)] = before.score[metric];
      result['shared' + _capitalize(metric)] = after.score[metric];
      result[metric + 'Delta'] = _delta(
        before.score[metric],
        after.score[metric],
      );
    }
    return result;
  }
}

String _capitalize(String value) => value[0].toUpperCase() + value.substring(1);

Object? _delta(dynamic before, dynamic after) =>
    before is num && after is num ? after - before : null;

Map<String, Object?> _strictReport(String source, String label) {
  final report = transcript_eval.evaluateTranscriptCorpus(source);
  final provenance = report['provenance'];
  final warnings = provenance is Map ? provenance['warnings'] : null;
  if (warnings is! List || warnings.isNotEmpty) {
    throw FormatException(
      '$label corpus fails strict provenance: ' +
          (warnings is List
              ? warnings.map((item) => item.toString()).join(' ')
              : 'provenance warnings unavailable'),
    );
  }
  return report;
}

Map<String, _Sample> _samples(String source, String label) {
  final root = _map(jsonDecode(source), '$label corpus');
  if (root['schemaVersion'] != 1) {
    throw FormatException('$label corpus must use schemaVersion 1.');
  }
  final result = <String, _Sample>{};
  for (final raw in _list(root['samples'], '$label samples')) {
    final sample = _Sample.parse(raw);
    if (result.containsKey(sample.id)) {
      throw FormatException(
        '$label corpus repeats sample ID ' + sample.id + '.',
      );
    }
    result[sample.id] = sample;
  }
  return result;
}

void _validateSongMetadata(Map<String, _Sample> samples, String label) {
  final canonical = <String, _Sample>{};
  for (final sample in samples.values) {
    final first = canonical[sample.songId];
    if (first == null) {
      canonical[sample.songId] = sample;
    } else if (first.language != sample.language ||
        first.referenceText != sample.referenceText ||
        first.sourceSha != sample.sourceSha ||
        first.durationMs != sample.durationMs) {
      throw FormatException(
        '$label samples for songId ' +
            sample.songId +
            ' disagree on language, reference text, source audio fingerprint, or duration.',
      );
    }
  }
}

Map<String, _Output> _outputs(
  Map<String, Object?> report,
  Map<String, _Sample> samples,
  String label,
) {
  final result = <String, _Output>{};
  for (final rawSample in _list(report['samples'], '$label report samples')) {
    final sampleResult = _map(rawSample, '$label report sample');
    final id = _requiredString(sampleResult, 'id');
    final sample = samples[id];
    if (sample == null)
      throw FormatException('$label report has unknown sample $id.');
    for (final rawCandidate in _list(
      sampleResult['candidates'],
      '$label candidates',
    )) {
      final output = _Output(sample, _map(rawCandidate, '$label candidate'));
      final key = sample.songId + '\u0000' + output.engine;
      if (result.containsKey(key)) {
        throw FormatException(
          '$label has multiple candidates for songId ' +
              sample.songId +
              ' and engine ' +
              output.engine +
              '.',
        );
      }
      result[key] = output;
    }
  }
  return result;
}

Map<String, _Configuration> _configurations(
  Map<String, _Output> outputs,
  String label,
) {
  final result = <String, _Configuration>{};
  for (final output in outputs.values) {
    final config = _Configuration(output.model, output.runtime);
    final previous = result[output.engine];
    if (previous != null && previous != config) {
      throw FormatException(
        '$label engine ' +
            output.engine +
            ' uses mixed model/runtime versions.',
      );
    }
    result[output.engine] = config;
  }
  return result;
}

/// Compares per-engine normalization with the shared-normalized-input path.
Map<String, Object?> evaluateAsrPreprocessingComparison({
  required String baselineCorpus,
  required String sharedCorpus,
}) {
  final baselineReport = _strictReport(baselineCorpus, 'Baseline');
  final sharedReport = _strictReport(sharedCorpus, 'Shared');
  final baselineSamples = _samples(baselineCorpus, 'Baseline');
  final sharedSamples = _samples(sharedCorpus, 'Shared');
  _validateSongMetadata(baselineSamples, 'Baseline');
  _validateSongMetadata(sharedSamples, 'Shared');

  final baseline = _outputs(baselineReport, baselineSamples, 'Baseline');
  final shared = _outputs(sharedReport, sharedSamples, 'Shared');
  final missingShared =
      baseline.keys.toSet().difference(shared.keys.toSet()).toList()..sort();
  final missingBaseline =
      shared.keys.toSet().difference(baseline.keys.toSet()).toList()..sort();
  if (missingShared.isNotEmpty || missingBaseline.isNotEmpty) {
    throw FormatException(
      'Corpora must contain the same songId/engine pairs. Missing from shared: '
      '$missingShared; missing from baseline: $missingBaseline.',
    );
  }

  final baselineConfigs = _configurations(baseline, 'Baseline');
  final sharedConfigs = _configurations(shared, 'Shared');
  if (baselineConfigs.length != sharedConfigs.length ||
      baselineConfigs.keys.any(
        (engine) => baselineConfigs[engine] != sharedConfigs[engine],
      )) {
    throw const FormatException(
      'Model revision/runtime differs between A/B corpora.',
    );
  }

  final pairs = <_Pair>[];
  for (final key in baseline.keys) {
    final before = baseline[key]!;
    final after = shared[key]!;
    if (before.sample.language != after.sample.language ||
        before.sample.referenceText != after.sample.referenceText ||
        before.sample.sourceSha != after.sample.sourceSha ||
        before.sample.durationMs != after.sample.durationMs ||
        before.model != after.model ||
        before.runtime != after.runtime) {
      throw FormatException(
        'Paired candidate ' +
            before.sample.songId +
            '/' +
            before.engine +
            ' changed source, reference, duration, model, or runtime.',
      );
    }
    pairs.add(_Pair(before, after));
  }
  pairs.sort((a, b) {
    final bySong = a.songId.compareTo(b.songId);
    return bySong != 0 ? bySong : a.engine.compareTo(b.engine);
  });

  final engines = pairs.map((pair) => pair.engine).toSet().toList()..sort();
  final changed = pairs.where((pair) => pair.audioChanged).length;
  return {
    'schemaVersion': 1,
    'evaluator': 'asr-preprocessing-ab-evaluator-v1',
    'baselineSampleCount': baselineSamples.length,
    'sharedSampleCount': sharedSamples.length,
    'songCount': pairs.map((pair) => pair.songId).toSet().length,
    'pairedCandidateCount': pairs.length,
    'inputAudioChangedCandidateCount': changed,
    'inputAudioUnchangedCandidateCount': pairs.length - changed,
    'preprocessingEffectTestable': changed > 0,
    'warnings': [
      if (changed == 0)
        'All paired candidate input hashes match; this run cannot isolate an audio-byte change.',
    ],
    'byEngine': {
      for (final engine in engines)
        engine: _summarize(
          pairs.where((pair) => pair.engine == engine).toList(),
        ),
    },
    'pairs': [for (final pair in pairs) pair.toJson()],
    'interpretation': {
      'deltaDirection':
          'Shared metric minus baseline metric; negative error deltas favor shared normalization.',
      'sourceAudioSha256':
          'Original source-file fingerprint before preprocessing; must match between runs.',
      'candidateAudioSha256':
          'Fingerprint of the exact normalized audio bytes supplied to each candidate.',
      'limitations':
          'Requires real audio, manually reviewed references, actual input hashes, and pinned model/runtime versions. Synthetic tests validate only this evaluator.',
    },
  };
}

Map<String, Object?> _summarize(List<_Pair> pairs) {
  if (pairs.isEmpty) throw const FormatException('Empty engine pair set.');
  int sumReference(String key) =>
      pairs.fold<int>(0, (sum, pair) => sum + pair.before.integer(key));
  int sumMetric(String field, bool after) => pairs.fold<int>(
    0,
    (sum, pair) => sum + (after ? pair.after : pair.before).integer(field),
  );

  final referenceCharacters = sumReference('referenceCharacterCount');
  final referenceTokens = sumReference('referenceTokenCount');
  final result = <String, Object?>{
    'candidateCount': pairs.length,
    'songCount': pairs.map((pair) => pair.songId).toSet().length,
    'referenceCharacterCount': referenceCharacters,
    'referenceTokenCount': referenceTokens,
  };
  for (final metric in _metricFields.where(
    (field) => !field.startsWith('normalized'),
  )) {
    final before = sumMetric(metric, false);
    final after = sumMetric(metric, true);
    result['baseline' + _capitalize(metric)] = before;
    result['shared' + _capitalize(metric)] = after;
    result[metric + 'Delta'] = after - before;
  }
  final baselineCharacterEdits = sumMetric('characterEditCount', false);
  final sharedCharacterEdits = sumMetric('characterEditCount', true);
  final baselineTokenEdits = sumMetric('tokenEditCount', false);
  final sharedTokenEdits = sumMetric('tokenEditCount', true);
  result.addAll({
    'baselineNormalizedCharacterErrorRate':
        baselineCharacterEdits / referenceCharacters,
    'sharedNormalizedCharacterErrorRate':
        sharedCharacterEdits / referenceCharacters,
    'normalizedCharacterErrorRateDelta':
        (sharedCharacterEdits - baselineCharacterEdits) / referenceCharacters,
    'baselineNormalizedTokenErrorRate': baselineTokenEdits / referenceTokens,
    'sharedNormalizedTokenErrorRate': sharedTokenEdits / referenceTokens,
    'normalizedTokenErrorRateDelta':
        (sharedTokenEdits - baselineTokenEdits) / referenceTokens,
    'baselineWordErrorRate': _wordRate(pairs, false),
    'sharedWordErrorRate': _wordRate(pairs, true),
    'wordErrorRateComparablePairCount': pairs
        .where(
          (pair) =>
              pair.before.score['wordErrorRate'] is num &&
              pair.after.score['wordErrorRate'] is num,
        )
        .length,
  });
  return result;
}

double? _wordRate(List<_Pair> pairs, bool after) {
  var edits = 0;
  var referenceWords = 0;
  for (final pair in pairs) {
    if (pair.before.score['wordErrorRate'] is! num ||
        pair.after.score['wordErrorRate'] is! num) {
      continue;
    }
    final candidate = after ? pair.after.score : pair.before.score;
    final count = candidate['wordEditCount'];
    final referenceCount = candidate['referenceWordCount'];
    if (count is int && referenceCount is int) {
      edits += count;
      referenceWords += referenceCount;
    }
  }
  return referenceWords == 0 ? null : edits / referenceWords;
}

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('--help')) {
    stdout.writeln(
      'Usage: dart run tool/asr_preprocessing_ab_eval.dart '
      '<baseline-corpus.json> <shared-corpus.json> [--output <report.json>]',
    );
    stdout.writeln(
      'Requires strict candidate provenance and sourceAudioSha256 per sample.',
    );
    if (args.isEmpty) exitCode = 2;
    return;
  }

  final positional = <String>[];
  String? outputPath;
  var outputSeen = false;
  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if (argument == '--output') {
      if (outputSeen ||
          index + 1 >= args.length ||
          args[index + 1].startsWith('--')) {
        stderr.writeln('Invalid --output option. Use --help for usage.');
        exitCode = 2;
        return;
      }
      outputSeen = true;
      outputPath = args[++index];
    } else if (argument.startsWith('--')) {
      stderr.writeln('Unknown option: $argument');
      exitCode = 2;
      return;
    } else {
      positional.add(argument);
    }
  }
  if (positional.length != 2) {
    stderr.writeln(
      'Provide baseline and shared corpus paths. Use --help for usage.',
    );
    exitCode = 2;
    return;
  }

  try {
    final baselineFile = File(positional[0]);
    final sharedFile = File(positional[1]);
    if (!await baselineFile.exists()) {
      throw FileSystemException(
        'Baseline corpus not found.',
        baselineFile.path,
      );
    }
    if (!await sharedFile.exists()) {
      throw FileSystemException('Shared corpus not found.', sharedFile.path);
    }
    final baselinePath = baselineFile.absolute.path;
    final sharedPath = sharedFile.absolute.path;
    if (baselinePath == sharedPath) {
      throw ArgumentError(
        'Baseline and shared corpora must be separate files.',
      );
    }
    if (outputPath != null) {
      final outputPathAbsolute = File(outputPath).absolute.path;
      if (outputPathAbsolute == baselinePath ||
          outputPathAbsolute == sharedPath) {
        throw ArgumentError(
          'Report output must not overwrite an input corpus.',
        );
      }
    }

    final report = evaluateAsrPreprocessingComparison(
      baselineCorpus: await baselineFile.readAsString(),
      sharedCorpus: await sharedFile.readAsString(),
    );
    final encoded = const JsonEncoder.withIndent('  ').convert(report) + '\n';
    if (outputPath == null) {
      stdout.write(encoded);
    } else {
      await File(outputPath).writeAsString(encoded);
      stdout.writeln('Wrote ASR preprocessing A/B report: $outputPath');
    }
    if (report['preprocessingEffectTestable'] != true) {
      stderr.writeln(
        'Warning: candidate input hashes match; preprocessing byte effects cannot be isolated.',
      );
    }
  } on FormatException catch (error) {
    stderr.writeln('Invalid ASR preprocessing A/B corpus: ' + error.message);
    exitCode = 2;
  } on ArgumentError catch (error) {
    stderr.writeln(
      'Invalid ASR preprocessing A/B evaluation: ' + error.toString(),
    );
    exitCode = 2;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
  }
}
