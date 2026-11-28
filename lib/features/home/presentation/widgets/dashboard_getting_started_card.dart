import 'package:flutter/material.dart';

import '../../../../core/onboarding/getting_started.dart';
import '../../../../core/onboarding/getting_started_card.dart';
import '../../domain/models/getting_started.dart';

/// The words of the 开始使用 checklist (D-070), kept together for tests.
abstract final class GettingStartedText {
  static const String title = '三步做出第一首 KTV 歌词';
  static const String doneTitle = '三步都完成了';
  static const String doneMessage = '以后从“最近工程”继续识别、校对和唱歌。这张卡片收起后，可以在设置里重新打开。';
  static const String dismissedNotice = GettingStartedCardText.dismissedNotice;

  static String progress(int done, int total) =>
      GettingStartedCardText.progress(done, total);

  static String stepTitle(GettingStartedStep step) => switch (step) {
    GettingStartedStep.importSong => '导入一首歌，自动识别歌词',
    GettingStartedStep.reviewLyrics => '校对歌词',
    GettingStartedStep.singKtv => '用 KTV 模式唱一遍',
  };

  static const String lockedDetail = '识别出歌词后就可以开始。';

  static String stepDetail(
    GettingStartedStep step,
    GettingStartedProgress progress,
  ) {
    final state = progress.stateOf(step);
    if (state == GettingStartedStepState.locked) return lockedDetail;
    final done = state == GettingStartedStepState.done;
    switch (step) {
      case GettingStartedStep.importSong:
        final recognizing = progress.recognizing;
        if (recognizing != null) {
          return '正在识别「${recognizing.name}」，识别完成后这一步会自动打勾。';
        }
        final song = progress.lyricsProject;
        if (song != null) return '「${song.name}」的歌词已经识别好了。';
        return '选一首本地歌曲，应用会在后台识别歌词并建好工程。'
            '第一次识别前会先引导你安装识别模型。';
      case GettingStartedStep.reviewLyrics:
        return done
            ? '已经确认过歌词，之后随时可以回到歌词编辑器继续校对。'
            : '在歌词编辑器里边听边看，标着“必看”的行先看，没问题就确认。';
      case GettingStartedStep.singKtv:
        return done
            ? '已经打开过 KTV。想唱哪首，从“最近工程”打开就行。'
            : '打开播放器，点“KTV”跟着逐行亮起的歌词唱，还可以录下来回放。';
    }
  }

  /// The button of a step that can be done now; null when it has none.
  static String? action(
    GettingStartedStep step,
    GettingStartedStepState state,
  ) {
    if (state == GettingStartedStepState.done ||
        state == GettingStartedStepState.locked) {
      return null;
    }
    return switch (step) {
      GettingStartedStep.importSong =>
        state == GettingStartedStepState.inProgress ? '查看进度' : '导入并识别',
      GettingStartedStep.reviewLyrics => '打开歌词编辑器',
      GettingStartedStep.singKtv => '去唱歌',
    };
  }
}

/// The dashboard's 开始使用 checklist (D-070): import a song, review its
/// lyrics, sing it in KTV. Each step ticks itself from the user's projects
/// and has a button that goes straight to where it is done.
class DashboardGettingStartedCard extends StatelessWidget {
  final GettingStartedProgress progress;
  final ValueChanged<GettingStartedStep> onOpenStep;
  final VoidCallback onDismiss;
  final VoidCallback onFinish;

  const DashboardGettingStartedCard({
    super.key,
    required this.progress,
    required this.onOpenStep,
    required this.onDismiss,
    required this.onFinish,
  });

  static const Key cardKey = ValueKey('dashboard:getting-started');
  static const Key dismissKey = ValueKey('dashboard:getting-started:dismiss');
  static const Key finishKey = ValueKey('dashboard:getting-started:finish');

  static Key stepKey(GettingStartedStep step) =>
      ValueKey('dashboard:getting-started:${step.name}');

  static Key actionKey(GettingStartedStep step) =>
      ValueKey('dashboard:getting-started:${step.name}:action');

  @override
  Widget build(BuildContext context) {
    return GettingStartedCard(
      key: cardKey,
      title: GettingStartedText.title,
      doneTitle: GettingStartedText.doneTitle,
      doneMessage: GettingStartedText.doneMessage,
      dismissKey: dismissKey,
      finishKey: finishKey,
      onDismiss: onDismiss,
      onFinish: onFinish,
      items: [
        for (final step in GettingStartedStep.values)
          GettingStartedItem(
            key: stepKey(step),
            title: GettingStartedText.stepTitle(step),
            detail: GettingStartedText.stepDetail(step, progress),
            state: progress.stateOf(step),
            actionLabel: GettingStartedText.action(
              step,
              progress.stateOf(step),
            ),
            onAction: () => onOpenStep(step),
            actionKey: actionKey(step),
          ),
      ],
    );
  }
}
