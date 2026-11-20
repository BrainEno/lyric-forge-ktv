import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/separator_output_parser.dart';

void main() {
  group('parseSeparatorLine', () {
    test('reads stages and providers', () {
      final stage = parseSeparatorLine('LF_STAGE separate');
      expect(stage, isA<SeparatorStageEvent>());
      expect((stage! as SeparatorStageEvent).stage, 'separate');

      final provider = parseSeparatorLine('LF_PROVIDER dml');
      expect((provider! as SeparatorProviderEvent).provider, 'dml');
    });

    test('strips the carriage return of Windows consoles', () {
      final event = parseSeparatorLine('LF_PROGRESS 0.5000\r');
      expect((event! as SeparatorProgressEvent).fraction, 0.5);
      expect(
        (parseSeparatorLine('LF_PROVIDER cpu\r')! as SeparatorProviderEvent)
            .provider,
        'cpu',
      );
    });

    test('clamps progress and rejects garbage', () {
      expect(
        (parseSeparatorLine('LF_PROGRESS 1.2')! as SeparatorProgressEvent)
            .fraction,
        1.0,
      );
      expect(
        (parseSeparatorLine('LF_PROGRESS -0.1')! as SeparatorProgressEvent)
            .fraction,
        0.0,
      );
      expect(parseSeparatorLine('LF_PROGRESS'), isNull);
      expect(parseSeparatorLine('LF_PROGRESS abc'), isNull);
      expect(parseSeparatorLine('LF_PROGRESS NaN'), isNull);
      expect(parseSeparatorLine('LF_PROGRESS Infinity'), isNull);
    });

    test('reads the loudness statistics', () {
      final event = parseSeparatorLine(
        'LF_STATS mix_rms=0.200000 vocals_rms=0.080000 '
        'accompaniment_rms=0.150000 seconds=20.000',
      );
      final stats = (event! as SeparatorStatsEvent).stats;
      expect(stats.mixRms, 0.2);
      expect(stats.vocalsRms, 0.08);
      expect(stats.accompanimentRms, 0.15);
      expect(stats.seconds, 20);
      expect(stats.vocalsToMixRatio, closeTo(0.4, 1e-9));
    });

    test('statistics need at least the mix and vocal levels', () {
      expect(parseSeparatorLine('LF_STATS vocals_rms=0.1'), isNull);
      expect(parseSeparatorLine('LF_STATS mix_rms=0.1'), isNull);
      expect(parseSeparatorLine('LF_STATS mix_rms=x vocals_rms=0.1'), isNull);
      expect(parseSeparatorLine('LF_STATS mix_rms=-1 vocals_rms=0.1'), isNull);
      final partial = parseSeparatorLine('LF_STATS mix_rms=0 vocals_rms=0');
      final stats = (partial! as SeparatorStatsEvent).stats;
      expect(stats.accompanimentRms, 0);
      expect(stats.vocalsToMixRatio, isNull, reason: 'silent mix');
    });

    test('reads done, fallback and errors', () {
      expect(
        parseSeparatorLine('LF_DONE vocals=C:/人声/vocals.wav'),
        isA<SeparatorDoneEvent>(),
      );
      final fallback = parseSeparatorLine(
        'LF_FALLBACK dml unavailable: no adapter',
      );
      expect(
        (fallback! as SeparatorFallbackEvent).reason,
        'dml unavailable: no adapter',
      );
      final error =
          parseSeparatorLine('LF_ERROR 3 cannot read input WAV')!
              as SeparatorErrorEvent;
      expect(error.code, 3);
      expect(error.message, 'cannot read input WAV');
      final bare = parseSeparatorLine('LF_ERROR 6');
      expect((bare! as SeparatorErrorEvent).message, isEmpty);
      expect(parseSeparatorLine('LF_ERROR oops'), isNull);
    });

    test('anything else is log output', () {
      for (final line in [
        '',
        'loading model',
        'LF_STAGE',
        'LF_PROVIDER ',
        'lf_stage separate',
        'XLF_DONE',
        'LF_UNKNOWN 1',
      ]) {
        expect(parseSeparatorLine(line), isNull, reason: line);
      }
    });
  });

  group('SeparatorRunReport', () {
    SeparatorRunReport replay(List<String> lines) {
      final report = SeparatorRunReport();
      for (final line in lines) {
        final event = parseSeparatorLine(line);
        if (event != null) report.add(event);
      }
      return report;
    }

    test('collects a successful DirectML run', () {
      final report = replay([
        'LF_STAGE load-model',
        'LF_PROVIDER dml',
        'LF_STAGE separate',
        'LF_PROGRESS 0.2500',
        'some log line',
        'LF_PROGRESS 1.0000',
        'LF_STAGE write',
        'LF_STATS mix_rms=0.2 vocals_rms=0.1 accompaniment_rms=0.15 seconds=3',
        'LF_DONE vocals=out/vocals.wav accompaniment=out/accompaniment.wav',
      ]);
      expect(report.provider, 'dml');
      expect(report.fallbacks, isEmpty);
      expect(report.done, isTrue);
      expect(report.error, isNull);
      expect(report.stats?.vocalsRms, 0.1);
      expect(report.overallProgress, 1.0);
    });

    test('records a GPU fallback and restarts progress on the CPU', () {
      final report = replay([
        'LF_STAGE load-model',
        'LF_PROVIDER dml',
        'LF_STAGE separate',
        'LF_PROGRESS 0.4000',
        'LF_FALLBACK dml failed during inference: E_OUTOFMEMORY',
      ]);
      expect(report.provider, isNull);
      expect(report.progress, 0);
      expect(report.fallbacks, ['dml failed during inference: E_OUTOFMEMORY']);

      for (final line in [
        'LF_STAGE load-model',
        'LF_PROVIDER cpu',
        'LF_STAGE separate',
        'LF_PROGRESS 0.1000',
      ]) {
        report.add(parseSeparatorLine(line)!);
      }
      expect(report.provider, 'cpu');
      expect(report.progress, closeTo(0.1, 1e-9));
    });

    test('progress never moves backwards within one attempt', () {
      final report = replay([
        'LF_STAGE separate',
        'LF_PROGRESS 0.6',
        'LF_PROGRESS 0.3',
      ]);
      expect(report.progress, closeTo(0.6, 1e-9));
    });

    test('maps stages onto the whole run', () {
      final report = SeparatorRunReport();
      expect(report.overallProgress, 0);
      report.add(const SeparatorStageEvent('load-model'));
      expect(report.overallProgress, 0);
      report.add(const SeparatorStageEvent('separate'));
      expect(report.overallProgress, closeTo(0.05, 1e-9));
      report.add(const SeparatorProgressEvent(0.5));
      expect(report.overallProgress, closeTo(0.5, 1e-9));
      report.add(const SeparatorStageEvent('write'));
      expect(report.overallProgress, 0.95);
      report.add(const SeparatorDoneEvent());
      expect(report.overallProgress, 1.0);
    });

    test('keeps the error of a failed run', () {
      final report = replay([
        'LF_STAGE load-model',
        'LF_ERROR 4 cannot load model on cpu: bad protobuf',
      ]);
      expect(report.done, isFalse);
      expect(report.error?.code, 4);
      expect(report.error?.message, 'cannot load model on cpu: bad protobuf');
    });
  });
}
