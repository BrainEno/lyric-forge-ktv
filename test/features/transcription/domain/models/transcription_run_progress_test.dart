import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_run_progress.dart';

// D-049: one forward-only progress for a whole project run, the step row,
// the stopwatch and the quiet hint, and their wording.

TranscriptionProgress _event(
  double progress, {
  String message = '',
  TranscriptionStage stage = TranscriptionStage.transcribing,
  TranscriptionRunStep? step,
  double? overall,
}) => TranscriptionProgress(
  stage: stage,
  progress: progress,
  message: message,
  step: step,
  overall: overall,
);

final _t0 = DateTime(2026, 11, 18, 9);

DateTime _at(int seconds) => _t0.add(Duration(seconds: seconds));

void main() {
  group('TranscriptionRunPlan', () {
    test('the shares cover the whole bar, one per step', () {
      expect(
        TranscriptionRunPlan.shares.keys,
        unorderedEquals(TranscriptionRunStep.values),
      );
      final total = TranscriptionRunPlan.shares.values.fold<double>(
        0,
        (sum, share) => sum + share,
      );
      expect(total, closeTo(1, 1e-9));
      for (final share in TranscriptionRunPlan.shares.values) {
        expect(share, greaterThan(0));
      }
    });

    test('recognition takes the largest share', () {
      final recognition =
          TranscriptionRunPlan.shares[TranscriptionRunStep.recognizing]!;
      for (final entry in TranscriptionRunPlan.shares.entries) {
        if (entry.key == TranscriptionRunStep.recognizing) continue;
        expect(recognition, greaterThan(entry.value), reason: '${entry.key}');
      }
    });

    test('steps start where the previous one ends', () {
      expect(TranscriptionRunPlan.startOf(TranscriptionRunStep.preparing), 0);
      for (var i = 1; i < TranscriptionRunStep.values.length; i++) {
        final previous = TranscriptionRunStep.values[i - 1];
        final step = TranscriptionRunStep.values[i];
        expect(
          TranscriptionRunPlan.startOf(step),
          closeTo(TranscriptionRunPlan.overallAt(previous, 1), 1e-9),
          reason: '$step',
        );
      }
      expect(
        TranscriptionRunPlan.overallAt(TranscriptionRunStep.saving, 1),
        closeTo(1, 1e-9),
      );
    });

    test('a step half done is half its share past its start', () {
      expect(
        TranscriptionRunPlan.overallAt(TranscriptionRunStep.recognizing, 0.5),
        closeTo(0.25 + 0.30, 1e-9),
      );
      expect(
        TranscriptionRunPlan.overallAt(TranscriptionRunStep.separating, 0.5),
        closeTo(0.03 + 0.11, 1e-9),
      );
    });

    test('out-of-range fractions are clamped, NaN counts as nothing', () {
      expect(
        TranscriptionRunPlan.overallAt(TranscriptionRunStep.checking, -1),
        closeTo(
          TranscriptionRunPlan.startOf(TranscriptionRunStep.checking),
          1e-9,
        ),
      );
      expect(
        TranscriptionRunPlan.overallAt(TranscriptionRunStep.checking, 3),
        closeTo(
          TranscriptionRunPlan.startOf(TranscriptionRunStep.fillingGaps),
          1e-9,
        ),
      );
      expect(
        TranscriptionRunPlan.overallAt(
          TranscriptionRunStep.preparing,
          double.nan,
        ),
        0,
      );
    });
  });

  group('TranscriptionProgress', () {
    test('inRun keeps the event and adds the step and the overall', () {
      final tagged = _event(
        0.4,
        message: 'Qwen3-ASR 识别中',
        stage: TranscriptionStage.aligning,
      ).inRun(TranscriptionRunStep.recognizing, 0.49);
      expect(tagged.stage, TranscriptionStage.aligning);
      expect(tagged.progress, 0.4);
      expect(tagged.message, 'Qwen3-ASR 识别中');
      expect(tagged.step, TranscriptionRunStep.recognizing);
      expect(tagged.overall, 0.49);
    });

    test('displayFraction prefers the overall and is clamped', () {
      expect(_event(0.9).displayFraction, 0.9);
      expect(_event(0.9, overall: 0.3).displayFraction, 0.3);
      expect(_event(1.7).displayFraction, 1);
      expect(_event(-0.2).displayFraction, 0);
      expect(_event(0.5, overall: 2).displayFraction, 1);
    });

    test('an engine on its own leaves step and overall empty', () {
      final plain = _event(0.5);
      expect(plain.step, isNull);
      expect(plain.overall, isNull);
    });
  });

  group('TranscriptionRunMeter', () {
    test('passes events through untouched outside a run', () {
      final meter = TranscriptionRunMeter();
      final event = _event(0.5);
      expect(
        identical(meter.tag(event, TranscriptionRunStep.recognizing), event),
        isTrue,
      );
      expect(meter.step, isNull);
    });

    test('maps each step onto its share of the bar', () {
      final meter = TranscriptionRunMeter()..start();
      expect(meter.step, TranscriptionRunStep.preparing);
      final separating = meter.tag(
        _event(0.5, stage: TranscriptionStage.preprocessing),
        TranscriptionRunStep.separating,
      );
      expect(separating.step, TranscriptionRunStep.separating);
      expect(separating.overall, closeTo(0.14, 1e-9));
      final recognizing = meter.tag(
        _event(0.5),
        TranscriptionRunStep.recognizing,
      );
      expect(recognizing.overall, closeTo(0.55, 1e-9));
      expect(meter.overall, closeTo(0.55, 1e-9));
    });

    test('a fallback engine starting again at 0% does not move it back', () {
      final meter = TranscriptionRunMeter()..start();
      meter.tag(_event(0.8), TranscriptionRunStep.recognizing);
      final restarted = meter.tag(
        _event(0.02, message: '换用 Whisper 识别'),
        TranscriptionRunStep.recognizing,
      );
      expect(restarted.message, '换用 Whisper 识别');
      expect(
        restarted.overall,
        closeTo(
          TranscriptionRunPlan.overallAt(TranscriptionRunStep.recognizing, 0.8),
          1e-9,
        ),
      );
    });

    test('cancelled and failed events leave the progress alone', () {
      final meter = TranscriptionRunMeter()..start();
      meter.tag(_event(0.5), TranscriptionRunStep.recognizing);
      for (final stage in [
        TranscriptionStage.cancelled,
        TranscriptionStage.failed,
      ]) {
        final terminal = meter.tag(
          _event(1, stage: stage),
          TranscriptionRunStep.recognizing,
        );
        expect(terminal.overall, closeTo(0.55, 1e-9), reason: '$stage');
      }
    });

    test('a later event of an earlier step stays in the current step', () {
      final meter = TranscriptionRunMeter()..start();
      meter.tag(_event(0.1), TranscriptionRunStep.fillingGaps);
      final late = meter.tag(
        _event(0.9, stage: TranscriptionStage.preprocessing),
        TranscriptionRunStep.separating,
      );
      expect(late.step, TranscriptionRunStep.fillingGaps);
      expect(meter.step, TranscriptionRunStep.fillingGaps);
      expect(
        late.overall,
        closeTo(
          TranscriptionRunPlan.overallAt(TranscriptionRunStep.fillingGaps, 0.1),
          1e-9,
        ),
      );
    });

    test('skipped steps are jumped over', () {
      final meter = TranscriptionRunMeter()..start();
      final saving = meter.tag(
        _event(0, stage: TranscriptionStage.parsing),
        TranscriptionRunStep.saving,
      );
      expect(
        saving.overall,
        closeTo(
          TranscriptionRunPlan.startOf(TranscriptionRunStep.saving),
          1e-9,
        ),
      );
    });

    test('start begins again from zero; finish stops tagging', () {
      final meter = TranscriptionRunMeter()..start();
      meter.tag(_event(1), TranscriptionRunStep.saving);
      meter.finish();
      expect(meter.step, isNull);
      final after = meter.tag(_event(0.3), TranscriptionRunStep.recognizing);
      expect(after.step, isNull);
      meter.start();
      expect(meter.overall, 0);
      final again = meter.tag(_event(0), TranscriptionRunStep.preparing);
      expect(again.overall, 0);
    });
  });

  group('TranscriptionRunTracker', () {
    test('starts in preparing with the preparing message', () {
      final tracker = TranscriptionRunTracker(startedAt: _t0);
      expect(tracker.step, TranscriptionRunStep.preparing);
      expect(tracker.overall, 0);
      expect(tracker.message, TranscriptionRunText.preparingMessage);
      expect(tracker.stage, isNull);
      expect(tracker.startedAt, _t0);
    });

    test('follows the step, the message and the overall of each event', () {
      final tracker = TranscriptionRunTracker(startedAt: _t0)
        ..record(
          _event(
            0.5,
            message: '正在分离人声 50%',
            stage: TranscriptionStage.preprocessing,
            step: TranscriptionRunStep.separating,
            overall: 0.14,
          ),
          _at(30),
        );
      expect(tracker.step, TranscriptionRunStep.separating);
      expect(tracker.message, '正在分离人声 50%');
      expect(tracker.overall, 0.14);
      expect(tracker.stage, TranscriptionStage.preprocessing);
      expect(tracker.stepElapsed(_at(40)), const Duration(seconds: 10));
      expect(tracker.elapsed(_at(40)), const Duration(seconds: 40));
    });

    test('an empty message keeps the last one', () {
      final tracker = TranscriptionRunTracker(startedAt: _t0)
        ..record(_event(0.1, message: 'Qwen3-ASR 识别中'), _at(1))
        ..record(_event(0.2, message: '  '), _at(2));
      expect(tracker.message, 'Qwen3-ASR 识别中');
    });

    test('never moves back, also not for cancelled or failed events', () {
      final tracker = TranscriptionRunTracker(startedAt: _t0)
        ..record(
          _event(0.5, step: TranscriptionRunStep.recognizing, overall: 0.55),
          _at(60),
        )
        ..record(
          _event(0.1, step: TranscriptionRunStep.recognizing, overall: 0.31),
          _at(61),
        )
        ..record(
          _event(
            0,
            stage: TranscriptionStage.cancelled,
            message: '已取消',
            step: TranscriptionRunStep.recognizing,
            overall: 0,
          ),
          _at(62),
        );
      expect(tracker.overall, 0.55);
      expect(tracker.message, '已取消');
    });

    test('a step that comes back later does not move the step back', () {
      final tracker = TranscriptionRunTracker(startedAt: _t0)
        ..record(_event(0, step: TranscriptionRunStep.fillingGaps), _at(5))
        ..record(_event(0, step: TranscriptionRunStep.separating), _at(6));
      expect(tracker.step, TranscriptionRunStep.fillingGaps);
      expect(tracker.stepElapsed(_at(10)), const Duration(seconds: 5));
    });

    test('an untagged engine event counts within the current step', () {
      final tracker = TranscriptionRunTracker(startedAt: _t0)
        ..record(_event(0, step: TranscriptionRunStep.recognizing), _at(1))
        ..record(_event(0.5), _at(2));
      expect(
        tracker.overall,
        closeTo(
          TranscriptionRunPlan.overallAt(TranscriptionRunStep.recognizing, 0.5),
          1e-9,
        ),
      );
    });

    test('is quiet after twenty seconds without news', () {
      final tracker = TranscriptionRunTracker(startedAt: _t0)
        ..record(_event(0.1), _at(10));
      expect(tracker.isQuiet(_at(29)), isFalse);
      expect(tracker.isQuiet(_at(30)), isTrue);
      expect(tracker.sinceLastEvent(_at(45)), const Duration(seconds: 35));
      tracker.record(_event(0.2), _at(45));
      expect(tracker.isQuiet(_at(46)), isFalse);
    });

    test('times before the start count as zero', () {
      final tracker = TranscriptionRunTracker(startedAt: _t0);
      final before = _t0.subtract(const Duration(seconds: 5));
      expect(tracker.elapsed(before), Duration.zero);
      expect(tracker.sinceLastEvent(before), Duration.zero);
      expect(tracker.stepElapsed(before), Duration.zero);
    });

    test('estimates nothing early on', () {
      final tracker = TranscriptionRunTracker(startedAt: _t0)
        ..record(_event(0, overall: 0.05), _at(5));
      // Too little done.
      expect(tracker.remaining(_at(60)), isNull);
      tracker.record(_event(0, overall: 0.5), _at(10));
      // Enough done, but too soon.
      expect(tracker.remaining(_at(10)), isNull);
    });

    test('estimates the rest from the pace so far', () {
      final tracker = TranscriptionRunTracker(startedAt: _t0)
        ..record(_event(0, overall: 0.25), _at(60));
      expect(tracker.remaining(_at(60)), const Duration(seconds: 180));
      tracker.record(_event(0, overall: 1), _at(90));
      expect(tracker.remaining(_at(90)), Duration.zero);
    });

    test('the step row: done, skipped, active and pending', () {
      final tracker = TranscriptionRunTracker(startedAt: _t0)
        ..record(_event(0, step: TranscriptionRunStep.recognizing), _at(3))
        ..record(_event(0, step: TranscriptionRunStep.fillingGaps), _at(90));
      expect(
        tracker.stateOf(TranscriptionRunStep.preparing),
        TranscriptionRunStepState.done,
      );
      expect(
        tracker.stateOf(TranscriptionRunStep.separating),
        TranscriptionRunStepState.skipped,
      );
      expect(
        tracker.stateOf(TranscriptionRunStep.recognizing),
        TranscriptionRunStepState.done,
      );
      expect(
        tracker.stateOf(TranscriptionRunStep.checking),
        TranscriptionRunStepState.skipped,
      );
      expect(
        tracker.stateOf(TranscriptionRunStep.fillingGaps),
        TranscriptionRunStepState.active,
      );
      expect(
        tracker.stateOf(TranscriptionRunStep.saving),
        TranscriptionRunStepState.pending,
      );
    });
  });

  group('TranscriptionRunText', () {
    test('every step has a label, a title and a hint', () {
      for (final step in TranscriptionRunStep.values) {
        expect(TranscriptionRunText.stepLabel(step), isNotEmpty);
        expect(TranscriptionRunText.stepTitle(step), startsWith('正在'));
        expect(TranscriptionRunText.stepHint(step), endsWith('。'));
      }
    });

    test('the labels are distinct', () {
      final labels = TranscriptionRunStep.values
          .map(TranscriptionRunText.stepLabel)
          .toSet();
      expect(labels, hasLength(TranscriptionRunStep.values.length));
    });

    test('the step counter counts from one', () {
      expect(
        TranscriptionRunText.stepCounter(TranscriptionRunStep.preparing),
        '第 1/6 步',
      );
      expect(
        TranscriptionRunText.stepCounter(TranscriptionRunStep.recognizing),
        '第 3/6 步',
      );
      expect(
        TranscriptionRunText.stepCounter(TranscriptionRunStep.saving),
        '第 6/6 步',
      );
    });

    test('the one-line form puts the step before the message', () {
      expect(
        TranscriptionRunText.stepLine(
          TranscriptionRunStep.recognizing,
          ' Qwen3-ASR 识别中 ',
        ),
        '第 3/6 步 · 识别歌词：Qwen3-ASR 识别中',
      );
      expect(
        TranscriptionRunText.stepLine(TranscriptionRunStep.saving, ''),
        '第 6/6 步 · 保存',
      );
    });

    test('the stopwatch', () {
      expect(TranscriptionRunText.clock(Duration.zero), '0:00');
      expect(TranscriptionRunText.clock(const Duration(seconds: 42)), '0:42');
      expect(
        TranscriptionRunText.clock(const Duration(minutes: 3, seconds: 5)),
        '3:05',
      );
      expect(
        TranscriptionRunText.clock(
          const Duration(hours: 1, minutes: 2, seconds: 5),
        ),
        '1:02:05',
      );
      expect(TranscriptionRunText.clock(const Duration(seconds: -3)), '0:00');
      expect(
        TranscriptionRunText.elapsed(const Duration(seconds: 75)),
        '已用时 1:15',
      );
    });

    test('durations in words', () {
      expect(
        TranscriptionRunText.duration(const Duration(seconds: 42)),
        '42 秒',
      );
      expect(
        TranscriptionRunText.duration(const Duration(minutes: 3, seconds: 5)),
        '3 分 05 秒',
      );
      expect(
        TranscriptionRunText.duration(const Duration(hours: 1, minutes: 2)),
        '1 小时 02 分',
      );
    });

    test('the estimate in words', () {
      expect(TranscriptionRunText.remaining(null), '正在估算剩余时间');
      expect(
        TranscriptionRunText.remaining(const Duration(seconds: 40)),
        '预计不到 1 分钟',
      );
      expect(
        TranscriptionRunText.remaining(const Duration(seconds: 61)),
        '预计还需约 2 分钟',
      );
      expect(
        TranscriptionRunText.remaining(const Duration(minutes: 4)),
        '预计还需约 4 分钟',
      );
    });

    test('percent is rounded down so 100% means finished', () {
      expect(TranscriptionRunText.percent(0.999), '99%');
      expect(TranscriptionRunText.percent(1), '100%');
      expect(TranscriptionRunText.percent(0.5), '50%');
      expect(TranscriptionRunText.percent(-1), '0%');
      expect(TranscriptionRunText.percent(double.nan), '0%');
    });

    test('quiet, finished, cancelled and the stop confirmation', () {
      expect(
        TranscriptionRunText.quiet(const Duration(seconds: 25)),
        '已 25 秒没有新的进度消息，程序仍在运行，请不要关闭窗口。',
      );
      expect(
        TranscriptionRunText.finished(const Duration(minutes: 2, seconds: 3)),
        contains('用时 2 分 03 秒'),
      );
      expect(TranscriptionRunText.cancelled, contains('现有歌词保持不变'));
      expect(
        TranscriptionRunText.cancelConfirmation(const Duration(minutes: 3)),
        allOf(contains('3 分 00 秒'), contains('从头开始')),
      );
    });
  });
}
