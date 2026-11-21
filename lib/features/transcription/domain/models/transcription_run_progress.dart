import 'transcription_models.dart';

export 'transcription_models.dart' show TranscriptionRunStep;

/// How much of a whole project run each [TranscriptionRunStep] takes, as
/// shares of the progress bar (D-049).
///
/// The shares follow what a song on the RTX profile spends in each step:
/// recognition with both engines dominates, separation is next (more on the
/// first run, which downloads the separator), the vocal check and saving
/// take seconds. A step that does not run is passed over at once, so the
/// bar only ever moves forward.
abstract final class TranscriptionRunPlan {
  static const Map<TranscriptionRunStep, double> shares = {
    TranscriptionRunStep.preparing: 0.03,
    TranscriptionRunStep.separating: 0.22,
    TranscriptionRunStep.recognizing: 0.60,
    TranscriptionRunStep.checking: 0.03,
    TranscriptionRunStep.fillingGaps: 0.10,
    TranscriptionRunStep.saving: 0.02,
  };

  /// Where [step] starts on the bar.
  static double startOf(TranscriptionRunStep step) {
    var start = 0.0;
    for (final earlier in TranscriptionRunStep.values) {
      if (earlier == step) break;
      start += shares[earlier]!;
    }
    return start;
  }

  /// The whole run's progress when [step] is [fraction] done.
  static double overallAt(TranscriptionRunStep step, double fraction) {
    final clamped = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
    return (startOf(step) + shares[step]! * clamped).clamp(0.0, 1.0);
  }
}

/// Turns the events of the steps of one project run into one forward-only
/// progress (D-049). Owned by the project workflow.
class TranscriptionRunMeter {
  TranscriptionRunStep? _step;
  double _overall = 0;

  /// The step in progress, or null between runs.
  TranscriptionRunStep? get step => _step;

  /// The whole run's progress so far.
  double get overall => _overall;

  /// A new run begins.
  void start() {
    _step = TranscriptionRunStep.preparing;
    _overall = 0;
  }

  /// The run is over; events after this are passed through untagged.
  void finish() {
    _step = null;
  }

  /// [event] as part of [step]. A step never moves back, and neither does
  /// the progress: an engine that reports 0% when it is cancelled, or a
  /// fallback engine starting again at 0%, leaves the bar where it was.
  TranscriptionProgress tag(
    TranscriptionProgress event,
    TranscriptionRunStep step,
  ) {
    final current = _step;
    if (current == null) return event;
    // A late event of a step already left (a separator's last message
    // arriving after recognition began) is shown in the current step and
    // does not move the bar: its percent belongs to the other step.
    final late = step.index < current.index;
    final effective = late ? current : step;
    _step = effective;
    final terminal =
        event.stage == TranscriptionStage.cancelled ||
        event.stage == TranscriptionStage.failed;
    if (!terminal && !late) {
      final value = TranscriptionRunPlan.overallAt(effective, event.progress);
      if (value > _overall) _overall = value;
    }
    return event.inRun(effective, _overall);
  }
}

/// Where a step stands in the step row of a run.
enum TranscriptionRunStepState { done, skipped, active, pending }

/// What a progress view of one project run shows: the step, the progress,
/// the time spent, whether the program has been quiet for a while and a
/// rough estimate of the time left (D-049).
///
/// The view feeds it every event and asks it again every second, so the
/// elapsed time keeps moving while a model runs without reporting.
class TranscriptionRunTracker {
  TranscriptionRunTracker({
    required DateTime startedAt,
    String message = TranscriptionRunText.preparingMessage,
  }) : _startedAt = startedAt,
       _lastEventAt = startedAt,
       _stepStartedAt = startedAt,
       _message = message;

  /// After this long without an event the view says the program is still
  /// running and what the step usually takes.
  static const Duration quietAfter = Duration(seconds: 20);

  /// No estimate before this much of the run is done or this much time has
  /// passed: the first steps say little about the rest.
  static const double estimateAfterFraction = 0.08;
  static const Duration estimateAfterTime = Duration(seconds: 20);

  final DateTime _startedAt;
  DateTime _lastEventAt;
  DateTime _stepStartedAt;
  TranscriptionRunStep _step = TranscriptionRunStep.preparing;
  final Set<TranscriptionRunStep> _visited = {TranscriptionRunStep.preparing};
  double _overall = 0;
  String _message;
  TranscriptionStage? _stage;

  DateTime get startedAt => _startedAt;
  TranscriptionRunStep get step => _step;
  double get overall => _overall;
  String get message => _message;

  /// The engine stage of the last event, for example aligning.
  TranscriptionStage? get stage => _stage;

  /// Takes [event], received at [now].
  void record(TranscriptionProgress event, DateTime now) {
    _lastEventAt = now;
    final message = event.message.trim();
    if (message.isNotEmpty) _message = message;
    _stage = event.stage;
    final step = event.step;
    if (step != null && step.index > _step.index) {
      _step = step;
      _stepStartedAt = now;
    }
    _visited.add(_step);
    final terminal =
        event.stage == TranscriptionStage.cancelled ||
        event.stage == TranscriptionStage.failed;
    if (terminal) return;
    final fraction = event.overall ?? _legacyOverall(event);
    if (fraction > _overall) _overall = fraction.clamp(0.0, 1.0);
  }

  /// An engine without a project workflow above it: its own progress is
  /// the progress of the current step.
  double _legacyOverall(TranscriptionProgress event) =>
      TranscriptionRunPlan.overallAt(_step, event.progress);

  Duration elapsed(DateTime now) => _nonNegative(now.difference(_startedAt));

  Duration stepElapsed(DateTime now) =>
      _nonNegative(now.difference(_stepStartedAt));

  Duration sinceLastEvent(DateTime now) =>
      _nonNegative(now.difference(_lastEventAt));

  /// Nothing has been reported for [quietAfter].
  bool isQuiet(DateTime now) => sinceLastEvent(now) >= quietAfter;

  /// A rough estimate of the time left from the pace so far, rounded to
  /// whole seconds; null while there is too little to go on.
  Duration? remaining(DateTime now) {
    final spent = elapsed(now);
    if (_overall < estimateAfterFraction || spent < estimateAfterTime) {
      return null;
    }
    if (_overall >= 1) return Duration.zero;
    final seconds = spent.inMilliseconds / 1000 * (1 - _overall) / _overall;
    return Duration(seconds: seconds.round());
  }

  /// Where [step] stands: steps before the current one are done, or skipped
  /// when the run never reported them.
  TranscriptionRunStepState stateOf(TranscriptionRunStep step) {
    if (step == _step) return TranscriptionRunStepState.active;
    if (step.index > _step.index) return TranscriptionRunStepState.pending;
    return _visited.contains(step)
        ? TranscriptionRunStepState.done
        : TranscriptionRunStepState.skipped;
  }

  static Duration _nonNegative(Duration value) =>
      value.isNegative ? Duration.zero : value;
}

/// The wording of a running recognition (D-049), shared by the project page
/// and the batch queue.
abstract final class TranscriptionRunText {
  static const String preparingMessage = '准备本地歌词识别';

  /// Short name of [step] for the step row.
  static String stepLabel(TranscriptionRunStep step) => switch (step) {
    TranscriptionRunStep.preparing => '准备',
    TranscriptionRunStep.separating => '分离人声',
    TranscriptionRunStep.recognizing => '识别歌词',
    TranscriptionRunStep.checking => '检查草稿',
    TranscriptionRunStep.fillingGaps => '补全漏句',
    TranscriptionRunStep.saving => '保存',
  };

  /// What the program is doing in [step], as a title.
  static String stepTitle(TranscriptionRunStep step) => switch (step) {
    TranscriptionRunStep.preparing => '正在准备识别',
    TranscriptionRunStep.separating => '正在分离人声',
    TranscriptionRunStep.recognizing => '正在识别歌词',
    TranscriptionRunStep.checking => '正在检查歌词草稿',
    TranscriptionRunStep.fillingGaps => '正在补全漏句',
    TranscriptionRunStep.saving => '正在保存歌词草稿',
  };

  /// What [step] usually takes, said when the program has been quiet.
  static String stepHint(TranscriptionRunStep step) => switch (step) {
    TranscriptionRunStep.preparing => '正在检查识别环境并备份现有歌词，通常只需几秒。',
    TranscriptionRunStep.separating => '第一次使用会先下载人声分离组件；分离一首歌通常需要 30 秒到 2 分钟。',
    TranscriptionRunStep.recognizing =>
      '模型正在整首识别，这一步通常需要 1 到 5 分钟，期间进度可能长时间不变。',
    TranscriptionRunStep.checking => '正在对照人声音轨检查每一行，通常只需几秒。',
    TranscriptionRunStep.fillingGaps => '正在逐段重新识别有人声但没有歌词的地方。',
    TranscriptionRunStep.saving => '正在写入工程，马上完成。',
  };

  /// "第 3/6 步".
  static String stepCounter(TranscriptionRunStep step) =>
      '第 ${step.index + 1}/${TranscriptionRunStep.values.length} 步';

  /// [step] with the counter, for one-line places such as the queue.
  static String stepLine(TranscriptionRunStep step, String message) {
    final detail = message.trim();
    final head = '${stepCounter(step)} · ${stepLabel(step)}';
    return detail.isEmpty ? head : '$head：$detail';
  }

  /// A stopwatch reading: "0:42", "3:05", "1:02:05".
  static String clock(Duration value) {
    final total = value.isNegative ? 0 : value.inSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = (total % 60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
    }
    return '$minutes:$seconds';
  }

  /// A duration in words: "42 秒", "3 分 05 秒", "1 小时 02 分".
  static String duration(Duration value) {
    final total = value.isNegative ? 0 : value.inSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    if (hours > 0) {
      return '$hours 小时 ${minutes.toString().padLeft(2, '0')} 分';
    }
    if (minutes > 0) {
      return '$minutes 分 ${seconds.toString().padLeft(2, '0')} 秒';
    }
    return '$seconds 秒';
  }

  /// "已用时 3:05".
  static String elapsed(Duration value) => '已用时 ${clock(value)}';

  /// The estimate in words.
  static String remaining(Duration? value) {
    if (value == null) return '正在估算剩余时间';
    if (value < const Duration(minutes: 1)) return '预计不到 1 分钟';
    final minutes = (value.inSeconds / 60).ceil();
    return '预计还需约 $minutes 分钟';
  }

  /// Said after [quietFor] without an event.
  static String quiet(Duration quietFor) =>
      '已 ${duration(quietFor)}没有新的进度消息，程序仍在运行，请不要关闭窗口。';

  /// Percent of [fraction], rounded down so 100% means finished.
  static String percent(double fraction) {
    final clamped = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
    return '${(clamped * 100).floor()}%';
  }

  /// The confirmation before a long run is stopped.
  static String cancelConfirmation(Duration spent) =>
      '已经识别了 ${duration(spent)}。停止后本次结果不会保存，'
      '下次需要从头开始识别；现有歌词保持不变。';

  /// The message after a run finished in [spent].
  static String finished(Duration spent) =>
      '歌词草稿已生成（用时 ${duration(spent)}），可以进入编辑器校对。';

  /// The message after the user stopped a run.
  static const String cancelled = '已停止识别，现有歌词保持不变。';
}
