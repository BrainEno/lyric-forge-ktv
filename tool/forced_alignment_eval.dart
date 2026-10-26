import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../lib/features/lyrics/domain/proofreading/lyric_tokenizer.dart';

const _maxSpans = 1000;
const _maxCells = 1000000;
const _maxGroup = 8;
const _tokenizer = LyricTokenizer();

class _Span {
  final String text;
  final int start;
  final int end;
  final String normalized;
  _Span(this.text, this.start, this.end)
      : normalized = _tokenizer.tokenize(text).join().replaceAll("'", '');

  factory _Span.parse(dynamic raw, String field, int? duration) {
    if (raw is! Map<String, dynamic> ||
        raw['text'] is! String ||
        raw['startMs'] is! int ||
        raw['endMs'] is! int) {
      throw FormatException('$field entries need text, integer startMs/endMs.');
    }
    final text = raw['text'] as String;
    final start = raw['startMs'] as int;
    final end = raw['endMs'] as int;
    if (text.trim().isEmpty || start < 0 || end <= start) {
      throw FormatException('$field contains an empty or invalid span.');
    }
    if (duration != null && end > duration) {
      throw FormatException('$field span ends after audioDurationMs.');
    }
    return _Span(text, start, end);
  }
}

class _Sample {
  final String id;
  final String language;
  final int? duration;
  final List<_Span> reference;
  final List<_Span> actual;

  _Sample.parse(dynamic raw)
      : id = _requiredString(raw, 'id'),
        language = _requiredString(raw, 'language'),
        duration = _optionalInt(raw, 'audioDurationMs'),
        reference = _parseSpans(raw, 'referenceSpans'),
        actual = _parseSpans(raw, 'actualSpans') {
    if (duration != null && duration! <= 0) {
      throw FormatException('Sample ${id} has invalid audioDurationMs.');
    }
    if (reference.isEmpty) {
      throw FormatException('Sample ${id} needs at least one reference span.');
    }
    if (reference.length > _maxSpans || actual.length > _maxSpans) {
      throw FormatException('Sample ${id} exceeds $_maxSpans spans per side.');
    }
    _checkOrder(reference, 'referenceSpans', id);
    _checkOrder(actual, 'actualSpans', id);
  }

  static String _requiredString(dynamic raw, String key) {
    if (raw is! Map<String, dynamic> ||
        raw[key] is! String ||
        (raw[key] as String).trim().isEmpty) {
      throw FormatException('Every sample needs a non-empty $key.');
    }
    return raw[key] as String;
  }

  static int? _optionalInt(dynamic raw, String key) {
    final value = raw is Map<String, dynamic> ? raw[key] : null;
    if (value != null && value is! int) {
      throw FormatException('$key must be an integer when present.');
    }
    return value as int?;
  }

  static List<_Span> _parseSpans(dynamic raw, String key) {
    if (raw is! Map<String, dynamic> || raw[key] is! List) {
      throw FormatException('Every sample needs a $key array.');
    }
    final duration = _optionalInt(raw, 'audioDurationMs');
    return (raw[key] as List)
        .map((item) => _Span.parse(item, key, duration))
        .toList(growable: false);
  }

  static void _checkOrder(List<_Span> spans, String field, String id) {
    var previous = -1;
    for (final span in spans) {
      if (span.start < previous) {
        throw FormatException('$id $field must be ordered by startMs.');
      }
      previous = span.start;
    }
  }
}

class _Score {
  final _Sample sample;
  final int tolerance;
  final int expectedChars;
  final int actualChars;
  final int matchedChars;
  final int matchedReference;
  final int matchedActual;
  final List<int> errors;
  final List<Map<String, Object>> groups;

  _Score({
    required this.sample,
    required this.tolerance,
    required this.expectedChars,
    required this.actualChars,
    required this.matchedChars,
    required this.matchedReference,
    required this.matchedActual,
    required List<int> errors,
    required List<Map<String, Object>> groups,
  })  : errors = List.unmodifiable(errors),
        groups = List.unmodifiable(groups);

  double? get recall =>
      expectedChars == 0 ? null : matchedChars / expectedChars;
  double get precision =>
      actualChars == 0 ? 0 : matchedChars / actualChars;
  double? get mae =>
      errors.isEmpty ? null : errors.reduce((a, b) => a + b) / errors.length;
  double? percentile(double p) {
    if (errors.isEmpty) return null;
    final sorted = errors.toList()..sort();
    if (p == 0.5 && sorted.length.isEven) {
      final mid = sorted.length ~/ 2;
      return (sorted[mid - 1] + sorted[mid]) / 2;
    }
    return sorted[
      (sorted.length * p).ceil().clamp(1, sorted.length).toInt() - 1
    ].toDouble();
  }

  int get within => errors.where((error) => error <= tolerance).length;
  Map<String, Object?> toJson() => {
        'sampleId': sample.id,
        'language': sample.language,
        'expectedSpanCount': sample.reference.length,
        'actualSpanCount': sample.actual.length,
        'matchedGroups': groups.length,
        'matchedExpectedSpans': matchedReference,
        'matchedActualSpans': matchedActual,
        'unmatchedExpectedSpans': sample.reference.length - matchedReference,
        'unmatchedActualSpans': sample.actual.length - matchedActual,
        'expectedCharacters': expectedChars,
        'actualCharacters': actualChars,
        'matchedCharacters': matchedChars,
        'textRecall': recall,
        'textPrecision': precision,
        'boundaryCount': errors.length,
        'meanAbsoluteBoundaryErrorMs': mae,
        'medianAbsoluteBoundaryErrorMs': percentile(0.5),
        'p95AbsoluteBoundaryErrorMs': percentile(0.95),
        'maxAbsoluteBoundaryErrorMs':
            errors.isEmpty ? null : errors.reduce((a, b) => a > b ? a : b),
        'withinToleranceBoundaryCount': within,
        'withinToleranceBoundaryRate':
            errors.isEmpty ? null : within / errors.length,
        'toleranceMs': tolerance,
        'matchedGroupDetails': groups,
      };
}

/// Aligns normalized span text in source order, allowing up to eight contiguous
/// spans to be grouped on either side. Reports errors only; never repairs time.
_Score _evaluate(_Sample sample, int tolerance, int maxGroup) {
  final ref = sample.reference.map((span) => span.normalized).toList();
  final pred = sample.actual.map((span) => span.normalized).toList();
  final n = ref.length;
  final m = pred.length;
  if ((n + 1) * (m + 1) > _maxCells) {
    throw FormatException(
      'Sample ${sample.id} needs more than $_maxCells DP cells; split it.',
    );
  }
  final refChars = ref.fold<int>(0, (sum, text) => sum + text.runes.length);
  final predChars = pred.fold<int>(0, (sum, text) => sum + text.runes.length);
  final refGroups = _groups(ref, maxGroup);
  final predGroups = _groups(pred, maxGroup);
  final score = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  final count = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  // 0 = skip expected span; 1 = skip actual span; >= 2 = matched group sizes.
  final action = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));

  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      var bestScore = score[i + 1][j];
      var bestCount = count[i + 1][j];
      var bestAction = 0;
      var bestSpanCount = 1 << 30;
      if (_better(score[i][j + 1], count[i][j + 1], 1, 1 << 30,
          bestScore, bestCount, bestAction, bestSpanCount)) {
        bestScore = score[i][j + 1];
        bestCount = count[i][j + 1];
        bestAction = 1;
      }
      final maxRef = math.min(maxGroup, n - i);
      final maxPred = math.min(maxGroup, m - j);
      for (var a = 1; a <= maxRef; a++) {
        final text = refGroups[i][a - 1];
        if (text == null || text.isEmpty) continue;
        for (var b = 1; b <= maxPred; b++) {
          if (text != predGroups[j][b - 1]) continue;
          final candidateScore = text.runes.length + score[i + a][j + b];
          final candidateCount = 1 + count[i + a][j + b];
          final candidateAction = 2 + (a - 1) * maxGroup + b - 1;
          if (_better(candidateScore, candidateCount, candidateAction, a + b,
              bestScore, bestCount, bestAction, bestSpanCount)) {
            bestScore = candidateScore;
            bestCount = candidateCount;
            bestAction = candidateAction;
            bestSpanCount = a + b;
          }
        }
      }
      score[i][j] = bestScore;
      count[i][j] = bestCount;
      action[i][j] = bestAction;
    }
  }

  final errors = <int>[];
  final groups = <Map<String, Object>>[];
  var matchedChars = 0;
  var matchedRef = 0;
  var matchedPred = 0;
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    final code = action[i][j];
    if (code == 0) {
      i++;
      continue;
    }
    if (code == 1) {
      j++;
      continue;
    }
    final encoded = code - 2;
    final a = encoded ~/ maxGroup + 1;
    final b = encoded % maxGroup + 1;
    final text = refGroups[i][a - 1]!;
    final startError =
        (sample.actual[j].start - sample.reference[i].start).abs();
    final endError =
        (sample.actual[j + b - 1].end - sample.reference[i + a - 1].end).abs();
    errors
      ..add(startError)
      ..add(endError);
    groups.add({
      'referenceStartIndex': i,
      'referenceSpanCount': a,
      'actualStartIndex': j,
      'actualSpanCount': b,
      'normalizedText': text,
      'startBoundaryErrorMs': startError,
      'endBoundaryErrorMs': endError,
    });
    matchedChars += text.runes.length;
    matchedRef += a;
    matchedPred += b;
    i += a;
    j += b;
  }
  return _Score(
    sample: sample,
    tolerance: tolerance,
    expectedChars: refChars,
    actualChars: predChars,
    matchedChars: matchedChars,
    matchedReference: matchedRef,
    matchedActual: matchedPred,
    errors: errors,
    groups: groups,
  );
}

List<List<String?>> _groups(List<String> spans, int maxGroup) =>
    List.generate(spans.length, (start) {
      final result = List<String?>.filled(maxGroup, null);
      final buffer = StringBuffer();
      for (
        var size = 1;
        size <= math.min(maxGroup, spans.length - start);
        size++
      ) {
        buffer.write(spans[start + size - 1]);
        result[size - 1] = buffer.toString();
      }
      return result;
    });

bool _better(
  int score,
  int count,
  int action,
  int spanCount,
  int bestScore,
  int bestCount,
  int bestAction,
  int bestSpanCount,
) {
  if (score != bestScore) return score > bestScore;
  if (count != bestCount) return count > bestCount;
  final match = action >= 2;
  final bestMatch = bestAction >= 2;
  if (match != bestMatch) return match;
  if (match && spanCount != bestSpanCount) return spanCount < bestSpanCount;
  return action < bestAction;
}

Map<String, Object?> _summarize(List<_Score> scores) {
  final expected = scores.fold<int>(0, (sum, row) => sum + row.expectedChars);
  final actual = scores.fold<int>(0, (sum, row) => sum + row.actualChars);
  final matched = scores.fold<int>(0, (sum, row) => sum + row.matchedChars);
  final errors = scores.expand((row) => row.errors).toList()..sort();
  final within = scores.fold<int>(0, (sum, row) => sum + row.within);
  double? percentile(double p) {
    if (errors.isEmpty) return null;
    if (p == 0.5 && errors.length.isEven) {
      final mid = errors.length ~/ 2;
      return (errors[mid - 1] + errors[mid]) / 2;
    }
    return errors[
      (errors.length * p).ceil().clamp(1, errors.length).toInt() - 1
    ].toDouble();
  }

  return {
    'sampleCount': scores.length,
    'expectedCharacters': expected,
    'predictedCharacters': actual,
    'matchedCharacters': matched,
    'textRecall': expected == 0 ? null : matched / expected,
    'textPrecision': actual == 0 ? 0.0 : matched / actual,
    'matchedGroups': scores.fold<int>(0, (sum, row) => sum + row.groups.length),
    'unmatchedReferenceSpans': scores.fold<int>(
      0,
      (sum, row) =>
          sum + row.sample.reference.length - row.matchedReference,
    ),
    'unmatchedActualSpans': scores.fold<int>(
      0, (sum, row) => sum + row.sample.actual.length - row.matchedActual),
    'boundaryCount': errors.length,
    'meanAbsoluteBoundaryErrorMs':
        errors.isEmpty ? null : errors.reduce((a, b) => a + b) / errors.length,
    'medianAbsoluteBoundaryErrorMs': percentile(0.5),
    'p95AbsoluteBoundaryErrorMs': percentile(0.95),
    'maxAbsoluteBoundaryErrorMs':
        errors.isEmpty ? null : errors.reduce((a, b) => a > b ? a : b),
    'withinToleranceBoundaryCount': within,
    'withinToleranceBoundaryRate':
        errors.isEmpty ? null : within / errors.length,
  };
}

Map<String, Object?> evaluateForcedAlignmentCorpus(String source) {
  final root = jsonDecode(source);
  if (root is! Map<String, dynamic> || root['schemaVersion'] != 1) {
    throw const FormatException(
      'Corpus must be a schemaVersion 1 JSON object.',
    );
  }
  final rawSamples = root['samples'];
  final tolerance = root['toleranceMs'] ?? 150;
  final maxGroup = root['maxGroupSpans'] ?? 8;
  if (rawSamples is! List || rawSamples.isEmpty || rawSamples.length > 200 ||
      tolerance is! int || tolerance < 0 ||
      maxGroup is! int || maxGroup < 1 || maxGroup > _maxGroup) {
    throw const FormatException(
      'Invalid samples, toleranceMs, or maxGroupSpans.',
    );
  }
  final samples = rawSamples.map(_Sample.parse).toList(growable: false);
  if (samples.map((sample) => sample.id).toSet().length != samples.length) {
    throw const FormatException('Sample IDs must be unique.');
  }
  final scores = samples.map((sample) => _evaluate(sample, tolerance, maxGroup))
      .toList(growable: false);
  final languages = samples.map((sample) => sample.language).toSet().toList()
    ..sort();
  return {
    'schemaVersion': 1,
    'evaluator': 'forced-alignment-quality-evaluator-v1',
    'toleranceMs': tolerance,
    'maxGroupSpans': maxGroup,
    'sampleCount': scores.length,
    'overall': _summarize(scores),
    'byLanguage': {
      for (final language in languages)
        language: _summarize(
          scores.where((score) => score.sample.language == language).toList(),
        ),
    },
    'samples': scores.map((score) => score.toJson()).toList(),
    'interpretation': {
      'textRecall':
          'Matched normalized reference characters / reference characters.',
      'textPrecision':
          'Matched normalized reference characters / predicted characters.',
      'boundaryError':
          'Absolute start/end error for each matched text group, in milliseconds.',
      'matching':
          'Ordered, bounded grouping accepts different span segmentation; no timestamps are interpolated.',
    },
  };
}


List<Map<String, Object?>> _parseReferenceSpans(
  String source,
  String sampleId,
  int audioDurationMs,
) {
  dynamic decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    throw const FormatException('Reference spans are not valid JSON.');
  }
  final rawSpans =
      decoded is Map<String, dynamic> ? decoded['referenceSpans'] : decoded;
  if (rawSpans is! List || rawSpans.isEmpty || rawSpans.length > _maxSpans) {
    throw const FormatException(
      'Reference JSON needs a non-empty span array within the span limit.',
    );
  }
  final spans = rawSpans
      .map((item) => _Span.parse(item, 'referenceSpans', audioDurationMs))
      .toList(growable: false);
  _Sample._checkOrder(spans, 'referenceSpans', sampleId);
  return [
    for (final span in spans)
      {'text': span.text, 'startMs': span.start, 'endMs': span.end},
  ];
}

double? _readSeconds(dynamic value) {
  final seconds = value is num
      ? value.toDouble()
      : value is String
          ? double.tryParse(value)
          : null;
  if (seconds == null || !seconds.isFinite) return null;
  return seconds;
}

List<Map<String, Object?>> _parseActualSpans(
  String source,
  String sampleId,
  int audioDurationMs,
) {
  dynamic decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    throw const FormatException('Alignment response is not valid JSON.');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Alignment response must be a JSON object.');
  }
  final directItems = decoded['items'];
  final results = decoded['results'];
  final dynamic items;
  if (directItems is List) {
    items = directItems;
  } else if (results is List &&
      results.isNotEmpty &&
      results.first is Map<String, dynamic> &&
      (results.first as Map<String, dynamic>)['items'] is List) {
    items = (results.first as Map<String, dynamic>)['items'];
  } else {
    throw const FormatException(
      'Alignment response must contain items or results[0].items.',
    );
  }
  if ((items as List).length > _maxSpans) {
    throw const FormatException('Alignment response exceeds the span limit.');
  }

  final spans = <Map<String, Object?>>[];
  var previousStart = -1;
  for (var index = 0; index < items.length; index++) {
    final item = items[index];
    if (item is! Map<String, dynamic>) {
      throw FormatException('Alignment span $index is not an object.');
    }
    final text = item['text'];
    final startSeconds = _readSeconds(item['start_time'] ?? item['start']);
    final endSeconds = _readSeconds(item['end_time'] ?? item['end']);
    if (text is! String || text.trim().isEmpty) {
      throw FormatException('Alignment span $index has empty text.');
    }
    if (startSeconds == null || endSeconds == null) {
      throw FormatException('Alignment span $index has invalid timestamps.');
    }
    if (startSeconds < 0 || endSeconds <= startSeconds) {
      throw FormatException('Alignment span $index has an invalid interval.');
    }
    final startMs = (startSeconds * 1000).round();
    final endMs = (endSeconds * 1000).round();
    if (endMs <= startMs) {
      throw FormatException(
        'Alignment span $index collapses after millisecond rounding.',
      );
    }
    if (startMs < previousStart) {
      throw FormatException('Alignment spans are unordered at index $index.');
    }
    if (endMs > audioDurationMs) {
      throw FormatException(
        'Alignment span $index ends after audioDurationMs.',
      );
    }
    spans.add({'text': text, 'startMs': startMs, 'endMs': endMs});
    previousStart = startMs;
  }
  return spans;
}

/// Captures a local /v1/align response and converts its timestamps to ms.
///
/// Only loopback endpoints are accepted so lyric text and local audio paths
/// cannot be sent to an arbitrary remote host by this developer tool.
Future<Map<String, Object?>> captureForcedAlignmentSample({
  required Uri endpoint,
  required String audioPath,
  required String lyricText,
  required String language,
  required String sampleId,
  required String referenceSpansJson,
  required int audioDurationMs,
  Duration requestTimeout = const Duration(minutes: 5),
}) async {
  if (endpoint.scheme != 'http' && endpoint.scheme != 'https') {
    throw ArgumentError.value(endpoint, 'endpoint', 'Must be an HTTP(S) URI.');
  }
  final address = InternetAddress.tryParse(endpoint.host);
  final loopback =
      endpoint.host.toLowerCase() == 'localhost' || address?.isLoopback == true;
  if (!loopback || endpoint.host.isEmpty) {
    throw ArgumentError.value(
      endpoint,
      'endpoint',
      'Must use a loopback host to protect local media and lyrics.',
    );
  }
  if (endpoint.path != '/v1/align') {
    throw ArgumentError.value(
      endpoint,
      'endpoint',
      'Path must be /v1/align; transcription is not forced alignment.',
    );
  }
  if (audioPath.trim().isEmpty ||
      lyricText.trim().isEmpty ||
      language.trim().isEmpty ||
      sampleId.trim().isEmpty) {
    throw ArgumentError('Audio, lyric text, language and sample ID are required.');
  }
  if (audioDurationMs <= 0 || requestTimeout <= Duration.zero) {
    throw ArgumentError('Audio duration and request timeout must be positive.');
  }
  final referenceSpans =
      _parseReferenceSpans(referenceSpansJson, sampleId, audioDurationMs);

  final client = HttpClient();
  try {
    final request = await client.postUrl(endpoint).timeout(requestTimeout);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'audio': audioPath,
      'text': lyricText,
      'language': language,
    }));
    final response = await request.close().timeout(requestTimeout);
    final body = await utf8.decoder.bind(response).join().timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FormatException(
        'Local /v1/align returned HTTP ${response.statusCode}.',
      );
    }
    final actualSpans = _parseActualSpans(body, sampleId, audioDurationMs);
    return {
      'id': sampleId,
      'language': language,
      'audioDurationMs': audioDurationMs,
      'referenceSpans': referenceSpans,
      'actualSpans': actualSpans,
    };
  } finally {
    client.close(force: true);
  }
}

Future<void> _runCaptureCommand(List<String> args) async {
  if (args.contains('--help')) {
    _writeCaptureUsage();
    return;
  }
  if (args.isEmpty || args.length.isOdd) {
    _writeCaptureUsage();
    exitCode = 2;
    return;
  }
  const allowed = {
    '--endpoint',
    '--audio',
    '--text-file',
    '--reference',
    '--id',
    '--language',
    '--duration-ms',
    '--output',
    '--append-to',
  };
  final options = <String, String>{};
  for (var index = 0; index < args.length; index += 2) {
    final key = args[index];
    if (!allowed.contains(key) || options.containsKey(key)) {
      throw ArgumentError('Unknown or repeated option: $key');
    }
    options[key] = args[index + 1];
  }
  const required = [
    '--endpoint',
    '--audio',
    '--text-file',
    '--reference',
    '--id',
    '--language',
    '--duration-ms',
  ];
  for (final key in required) {
    if ((options[key] ?? '').trim().isEmpty) {
      throw ArgumentError('Missing required option: $key');
    }
  }
  final hasOutput = options.containsKey('--output');
  final hasAppend = options.containsKey('--append-to');
  if (hasOutput == hasAppend) {
    throw ArgumentError('Specify exactly one of --output or --append-to.');
  }
  final durationMs = int.tryParse(options['--duration-ms']!);
  if (durationMs == null || durationMs <= 0) {
    throw ArgumentError('--duration-ms must be a positive integer.');
  }
  final endpoint = Uri.tryParse(options['--endpoint']!);
  if (endpoint == null) {
    throw ArgumentError('--endpoint must be a valid URI.');
  }

  final audioPath = options['--audio']!;
  final textPath = options['--text-file']!;
  final referencePath = options['--reference']!;
  final targetPath = options['--output'] ?? options['--append-to']!;
  final target = File(targetPath);
  for (final sourcePath in [audioPath, textPath, referencePath]) {
    if (File(sourcePath).absolute.path == target.absolute.path) {
      throw ArgumentError('Corpus output must not overwrite an input file.');
    }
  }
  if (!await File(audioPath).exists()) {
    throw FileSystemException('Audio file not found.', audioPath);
  }
  final lyricText = await File(textPath).readAsString();
  final referenceJson = await File(referencePath).readAsString();
  final sample = await captureForcedAlignmentSample(
    endpoint: endpoint,
    audioPath: audioPath,
    lyricText: lyricText,
    language: options['--language']!,
    sampleId: options['--id']!,
    referenceSpansJson: referenceJson,
    audioDurationMs: durationMs,
  );

  Map<String, Object?> corpus;
  if (hasAppend) {
    if (!await target.exists()) {
      throw FileSystemException('Existing corpus not found.', targetPath);
    }
    final existingSource = await target.readAsString();
    final existingDecoded = jsonDecode(existingSource);
    evaluateForcedAlignmentCorpus(existingSource);
    final existing = existingDecoded as Map<String, dynamic>;
    final samples = List<dynamic>.from(existing['samples'] as List);
    if (samples.any((row) => (row as Map)['id'] == sample['id'])) {
      throw FormatException('Sample ID already exists: ${sample['id']}.');
    }
    samples.add(sample);
    corpus = Map<String, Object?>.from(existing)..['samples'] = samples;
  } else {
    if (await target.exists()) {
      throw FileSystemException(
        'Output already exists; use --append-to to preserve and extend a corpus.',
        targetPath,
      );
    }
    corpus = {
      'schemaVersion': 1,
      'toleranceMs': 150,
      'maxGroupSpans': 8,
      'samples': [sample],
    };
  }
  evaluateForcedAlignmentCorpus(jsonEncode(corpus));
  await target.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(corpus)}\n',
    flush: true,
  );
  stdout.writeln('Captured sample ${sample['id']} into $targetPath.');
}

void _writeCaptureUsage() {
  stdout.writeln(
    'Usage: dart run tool/forced_alignment_eval.dart capture',
  );
  stdout.writeln('  --endpoint http://127.0.0.1:PORT/v1/align --audio <audio.wav>');
  stdout.writeln('  --text-file <lyrics.txt> --reference <gold-spans.json>');
  stdout.writeln('  --id <sample-id> --language <English|Chinese|Japanese>');
  stdout.writeln(
    '  --duration-ms <duration> (--output <new-corpus.json> | --append-to <corpus.json>)',
  );
}

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == 'capture') {
    try {
      await _runCaptureCommand(args.skip(1).toList());
    } on FormatException catch (error) {
      stderr.writeln('Capture failed: ${error.message}');
      exitCode = 2;
    } on ArgumentError catch (error) {
      stderr.writeln('Capture failed: $error');
      exitCode = 2;
    } on FileSystemException catch (error) {
      stderr.writeln(error.message);
      exitCode = 2;
    } on SocketException catch (error) {
      stderr.writeln('Could not reach local /v1/align: $error');
      exitCode = 2;
    } on HttpException catch (error) {
      stderr.writeln('Local /v1/align failed: $error');
      exitCode = 2;
    } on TimeoutException catch (error) {
      stderr.writeln('Local /v1/align timed out: $error');
      exitCode = 2;
    }
    return;
  }
  if (args.isEmpty || args.contains('--help')) {
    stdout.writeln(
      'Usage: dart run tool/forced_alignment_eval.dart <corpus.json> [--output <report.json>]',
    );
    stdout.writeln(
      'Reference times must be manually checked against the original audio.',
    );
    if (args.isEmpty) exitCode = 2;
    return;
  }
  String? output;
  if (args.length == 3 && args[1] == '--output') {
    output = args[2];
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
    if (output != null && File(output).absolute.path == input.absolute.path) {
      throw ArgumentError('Report output must not overwrite the corpus input.');
    }
    final report = evaluateForcedAlignmentCorpus(await input.readAsString());
    final encoded = '${const JsonEncoder.withIndent('  ').convert(report)}\n';
    if (output == null) {
      stdout.write(encoded);
    } else {
      await File(output).writeAsString(encoded);
      stdout.writeln('Wrote evaluation report: $output');
    }
  } on FormatException catch (error) {
    stderr.writeln('Invalid evaluation corpus: ${error.message}');
    exitCode = 2;
  } on ArgumentError catch (error) {
    stderr.writeln('Invalid evaluation data: $error');
    exitCode = 2;
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
  }
}
