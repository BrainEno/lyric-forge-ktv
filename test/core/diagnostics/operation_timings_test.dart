import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/diagnostics/app_logger.dart';
import 'package:lyric_forge_ktv/core/diagnostics/operation_timings.dart';

void main() {
  test('summarizes median, max, last, failures and real-time factor', () {
    final timings = OperationTimings();
    timings
      ..record(
        'asr',
        const Duration(seconds: 30),
        mediaDuration: const Duration(minutes: 1),
      )
      ..record(
        'asr',
        const Duration(seconds: 90),
        mediaDuration: const Duration(minutes: 3),
      )
      ..record(
        'asr',
        const Duration(seconds: 10),
        outcome: OperationOutcome.failure,
      );

    final summary = timings.summarize('asr')!;
    expect(summary.count, 3);
    expect(summary.failures, 1);
    expect(summary.median, const Duration(seconds: 30));
    expect(summary.max, const Duration(seconds: 90));
    expect(summary.last, const Duration(seconds: 10));
    expect(summary.medianRealTimeFactor, closeTo(0.5, 1e-9));
    expect(timings.summarize('missing'), isNull);
  });

  test('median of an even number of samples is the mean of the middle', () {
    final timings = OperationTimings()
      ..record('x', const Duration(milliseconds: 100))
      ..record('x', const Duration(milliseconds: 300));
    expect(timings.summarize('x')!.median, const Duration(milliseconds: 200));
  });

  test('keeps only the most recent samples per operation', () {
    final timings = OperationTimings(samplesPerOperation: 3);
    for (var i = 1; i <= 5; i++) {
      timings.record('x', Duration(seconds: i));
    }
    expect(timings.samplesFor('x').map((sample) => sample.elapsed.inSeconds), [
      3,
      4,
      5,
    ]);
  });

  test('a span records exactly once', () {
    final timings = OperationTimings();
    final span = timings.start('ktv.exportMix');
    expect(span.finish(outcome: OperationOutcome.failure), isNotNull);
    expect(span.finish(), isNull);
    expect(timings.samplesFor('ktv.exportMix').single.outcome,
        OperationOutcome.failure);
  });

  test('measure records success with media duration and attributes', () async {
    final timings = OperationTimings();
    final result = await timings.measure(
      'job',
      () async => 42,
      mediaDurationOf: (_) => const Duration(seconds: 10),
      attributesOf: (value) => {'value': value},
    );
    expect(result, 42);
    final sample = timings.samplesFor('job').single;
    expect(sample.outcome, OperationOutcome.success);
    expect(sample.mediaDuration, const Duration(seconds: 10));
    expect(sample.attributes, {'value': 42});
  });

  test('measure records failures, classifies cancellations and rethrows',
      () async {
    final timings = OperationTimings();
    await expectLater(
      timings.measure<void>('job', () async => throw StateError('x')),
      throwsStateError,
    );
    await expectLater(
      timings.measure<void>(
        'job',
        () async => throw const FormatException('cancel'),
        classify: (_) => OperationOutcome.cancelled,
      ),
      throwsFormatException,
    );
    final samples = timings.samplesFor('job');
    expect(samples.map((sample) => sample.outcome), [
      OperationOutcome.failure,
      OperationOutcome.cancelled,
    ]);
    expect(samples.first.attributes, {'error': 'StateError'});
  });

  test('toJson includes summary and recent samples; clear empties', () async {
    final timings = OperationTimings(
      clock: () => DateTime.utc(2026, 11, 15),
    )..record(
        'x',
        const Duration(seconds: 2),
        mediaDuration: const Duration(seconds: 8),
        attributes: const {'mode': 'fast'},
      );
    final json = timings.toJson();
    final entry = json['x'] as Map<String, Object?>;
    expect(entry['summary'], containsPair('count', 1));
    expect(entry['recent'], [
      {
        'finishedAt': '2026-11-15T00:00:00.000Z',
        'elapsedMs': 2000,
        'outcome': 'success',
        'mediaMs': 8000,
        'realTimeFactor': 0.25,
        'attributes': {'mode': 'fast'},
      },
    ]);

    var notified = 0;
    final subscription = timings.changes.listen((_) => notified++);
    timings.clear();
    await Future<void>.delayed(Duration.zero);
    expect(notified, 1);
    await subscription.cancel();
    expect(timings.operations, isEmpty);
    expect(timings.toJson(), isEmpty);
  });

  test('notifies listeners and logs each sample', () async {
    final logger = AppLogger(sinks: [MemoryLogSink()]);
    final timings = OperationTimings(logger: logger);
    var notified = 0;
    final subscription = timings.changes.listen((_) => notified++);
    timings.record(
      'asr',
      const Duration(seconds: 3),
      mediaDuration: const Duration(seconds: 6),
    );
    await Future<void>.delayed(Duration.zero);
    expect(notified, 1);
    await subscription.cancel();
    expect(
      logger.memory!.records.single.message,
      'asr success in 3000 ms (RTF 0.50)',
    );
    expect(logger.memory!.records.single.tag, 'timing');
  });
}
