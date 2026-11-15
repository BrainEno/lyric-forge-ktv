import 'dart:async';
import 'dart:collection';

import 'app_logger.dart';

/// How a timed operation ended.
enum OperationOutcome { success, failure, cancelled }

/// One completed measurement.
class OperationSample {
  final String operation;
  final DateTime finishedAt;
  final Duration elapsed;
  final OperationOutcome outcome;

  /// Media length the operation processed, when known; gives the
  /// real-time factor that makes a 3-minute and a 9-minute song comparable.
  final Duration? mediaDuration;

  /// Small structured facts (engine, mode, failure kind). Values must be
  /// scalars and never contain lyric text or paths.
  final Map<String, Object?> attributes;

  const OperationSample({
    required this.operation,
    required this.finishedAt,
    required this.elapsed,
    required this.outcome,
    this.mediaDuration,
    this.attributes = const {},
  });

  /// Processing time divided by media time; below 1.0 is faster than
  /// real time.
  double? get realTimeFactor {
    final media = mediaDuration;
    if (media == null || media.inMilliseconds <= 0) return null;
    return elapsed.inMilliseconds / media.inMilliseconds;
  }

  Map<String, Object?> toJson() => {
    'finishedAt': finishedAt.toUtc().toIso8601String(),
    'elapsedMs': elapsed.inMilliseconds,
    'outcome': outcome.name,
    if (mediaDuration != null) 'mediaMs': mediaDuration!.inMilliseconds,
    if (realTimeFactor != null)
      'realTimeFactor': double.parse(realTimeFactor!.toStringAsFixed(3)),
    if (attributes.isNotEmpty) 'attributes': attributes,
  };
}

/// Summary of the recent samples of one operation.
class OperationSummary {
  final String operation;
  final int count;
  final int failures;
  final Duration median;
  final Duration max;
  final Duration last;
  final double? medianRealTimeFactor;

  const OperationSummary({
    required this.operation,
    required this.count,
    required this.failures,
    required this.median,
    required this.max,
    required this.last,
    required this.medianRealTimeFactor,
  });

  Map<String, Object?> toJson() => {
    'count': count,
    'failures': failures,
    'medianMs': median.inMilliseconds,
    'maxMs': max.inMilliseconds,
    'lastMs': last.inMilliseconds,
    if (medianRealTimeFactor != null)
      'medianRealTimeFactor': double.parse(
        medianRealTimeFactor!.toStringAsFixed(3),
      ),
  };
}

/// A running measurement started by [OperationTimings.start].
class OperationSpan {
  OperationSpan._(this._timings, this.operation, this._stopwatch);

  final OperationTimings _timings;
  final String operation;
  final Stopwatch _stopwatch;
  bool _finished = false;

  Duration get elapsed => _stopwatch.elapsed;

  /// Records the sample once; later calls are ignored so a `finally` block
  /// cannot double count an operation that already reported failure.
  OperationSample? finish({
    OperationOutcome outcome = OperationOutcome.success,
    Duration? mediaDuration,
    Map<String, Object?> attributes = const {},
  }) {
    if (_finished) return null;
    _finished = true;
    _stopwatch.stop();
    return _timings.record(
      operation,
      _stopwatch.elapsed,
      outcome: outcome,
      mediaDuration: mediaDuration,
      attributes: attributes,
    );
  }
}

/// Session-scoped timing samples for user-visible operations (KTV start,
/// mix export, recognition). These are the device numbers issue #226 asks
/// for; they are kept in memory, logged, and included in the diagnostics
/// report, never sent anywhere.
class OperationTimings {
  OperationTimings({
    this.samplesPerOperation = 20,
    AppLogger? logger,
    DateTime Function()? clock,
    Stopwatch Function()? stopwatchFactory,
  }) : _logger = logger,
       _clock = clock ?? DateTime.now,
       _stopwatchFactory = stopwatchFactory ?? Stopwatch.new;

  final int samplesPerOperation;
  final AppLogger? _logger;
  final DateTime Function() _clock;
  final Stopwatch Function() _stopwatchFactory;
  final Map<String, Queue<OperationSample>> _samples = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Fires after a sample is recorded or the samples are cleared.
  Stream<void> get changes => _changes.stream;

  static const String logTag = 'timing';

  OperationSpan start(String operation) =>
      OperationSpan._(this, operation, _stopwatchFactory()..start());

  /// Times [action]; a thrown error records a failure and is rethrown.
  /// [classify] can turn a specific error into [OperationOutcome.cancelled].
  Future<T> measure<T>(
    String operation,
    Future<T> Function() action, {
    Duration? Function(T result)? mediaDurationOf,
    Map<String, Object?> Function(T result)? attributesOf,
    OperationOutcome Function(Object error)? classify,
    Map<String, Object?> Function(Object error)? errorAttributesOf,
  }) async {
    final span = start(operation);
    try {
      final result = await action();
      span.finish(
        mediaDuration: mediaDurationOf?.call(result),
        attributes: attributesOf?.call(result) ?? const {},
      );
      return result;
    } catch (error) {
      span.finish(
        outcome: classify?.call(error) ?? OperationOutcome.failure,
        attributes:
            errorAttributesOf?.call(error) ??
            {'error': '${error.runtimeType}'},
      );
      rethrow;
    }
  }

  OperationSample record(
    String operation,
    Duration elapsed, {
    OperationOutcome outcome = OperationOutcome.success,
    Duration? mediaDuration,
    Map<String, Object?> attributes = const {},
  }) {
    final sample = OperationSample(
      operation: operation,
      finishedAt: _clock(),
      elapsed: elapsed,
      outcome: outcome,
      mediaDuration: mediaDuration,
      attributes: Map.unmodifiable(attributes),
    );
    final queue = _samples.putIfAbsent(operation, Queue<OperationSample>.new);
    queue.addLast(sample);
    while (queue.length > samplesPerOperation) {
      queue.removeFirst();
    }
    if (_changes.hasListener) _changes.add(null);
    final factor = sample.realTimeFactor;
    _logger?.info(
      logTag,
      '$operation ${outcome.name} in ${elapsed.inMilliseconds} ms'
      '${factor == null ? '' : ' (RTF ${factor.toStringAsFixed(2)})'}',
    );
    return sample;
  }

  List<String> get operations => _samples.keys.toList()..sort();

  List<OperationSample> samplesFor(String operation) =>
      List.unmodifiable(_samples[operation] ?? const <OperationSample>[]);

  OperationSummary? summarize(String operation) {
    final samples = _samples[operation];
    if (samples == null || samples.isEmpty) return null;
    final elapsed = [for (final sample in samples) sample.elapsed]..sort();
    final factors = [
      for (final sample in samples)
        if (sample.realTimeFactor != null) sample.realTimeFactor!,
    ]..sort();
    return OperationSummary(
      operation: operation,
      count: samples.length,
      failures: samples
          .where((sample) => sample.outcome == OperationOutcome.failure)
          .length,
      median: _median(elapsed),
      max: elapsed.last,
      last: samples.last.elapsed,
      medianRealTimeFactor: factors.isEmpty ? null : _medianDouble(factors),
    );
  }

  Map<String, Object?> toJson() => {
    for (final operation in operations)
      operation: {
        'summary': summarize(operation)!.toJson(),
        'recent': [
          for (final sample in samplesFor(operation)) sample.toJson(),
        ],
      },
  };

  void clear() {
    _samples.clear();
    if (_changes.hasListener) _changes.add(null);
  }

  static Duration _median(List<Duration> sorted) {
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) ~/ 2;
  }

  static double _medianDouble(List<double> sorted) {
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }
}
