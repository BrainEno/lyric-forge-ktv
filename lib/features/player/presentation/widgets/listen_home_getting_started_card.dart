import 'package:flutter/material.dart';

import '../../../../core/onboarding/getting_started.dart';
import '../../../../core/onboarding/getting_started_card.dart';
import '../../domain/models/mobile_getting_started.dart';

/// The words of the phone's 开始使用 checklist (D-071).
abstract final class ListenHomeGettingStartedText {
  static const String title = '三步让手机里的歌带上歌词';
  static const String doneTitle = '三步都完成了';
  static const String doneMessage =
      '以后在“歌词”页给更多歌配歌词，播放时点唱片就能看歌词。这张卡片收起后，可以在设置里重新打开。';

  static String stepTitle(MobileGettingStartedStep step) => switch (step) {
    MobileGettingStartedStep.addSongs => '把歌放进手机',
    MobileGettingStartedStep.addLyrics => '给一首歌配歌词',
    MobileGettingStartedStep.playWithLyrics => '跟着歌词播放一首',
  };

  static const String addLyricsLocked = '音乐库里有歌以后就可以开始。';
  static const String playLocked = '先给一首歌配上歌词。';

  static String stepDetail(
    MobileGettingStartedStep step,
    MobileGettingStartedProgress progress, {
    required bool canImport,
  }) {
    final state = progress.stateOf(step);
    final done = state == GettingStartedStepState.done;
    switch (step) {
      case MobileGettingStartedStep.addSongs:
        if (done) return '音乐库里已经有 ${progress.songCount} 首歌。';
        return canImport
            ? '从“文件”或相册导入音频、视频，或者连接电脑上的 Elysium Player 把歌传过来。'
            : '添加手机里的音乐文件夹，或者连接电脑上的 Elysium Player 把歌传过来。';
      case MobileGettingStartedStep.addLyrics:
        if (done) return '已经有 ${progress.lyricSongCount} 首歌配好了歌词。';
        if (state == GettingStartedStepState.locked) return addLyricsLocked;
        return '在“歌词”页联网获取、导入 LRC / TXT 歌词文件，或者直接粘贴歌词。';
      case MobileGettingStartedStep.playWithLyrics:
        if (done) return '已经跟着歌词听过了。之后点正在播放的唱片，就能打开歌词。';
        final song = progress.lyricSong;
        if (song == null) return playLocked;
        return '播放配好歌词的「${song.title}」，歌词会跟着歌曲滚动。';
    }
  }

  static const String importSongs = '导入歌曲';
  static const String openLibrary = '打开音乐库';
  static const String transfer = '从电脑传歌';
  static const String addLyrics = '去配歌词';
  static const String play = '播放';
}

/// The phone's 开始使用 checklist on 听歌 (D-071): put songs on the phone,
/// give one lyrics, listen along. Each step ticks itself from the library
/// and the recent plays.
class ListenHomeGettingStartedCard extends StatelessWidget {
  final MobileGettingStartedProgress progress;

  /// 导入音频或视频 (D-056); null where the app cannot import, and the
  /// first step opens the library instead.
  final VoidCallback? onImport;
  final VoidCallback onOpenLibrary;
  final VoidCallback onTransfer;
  final VoidCallback onAddLyrics;
  final VoidCallback onPlay;
  final VoidCallback onDismiss;
  final VoidCallback onFinish;

  const ListenHomeGettingStartedCard({
    super.key,
    required this.progress,
    required this.onImport,
    required this.onOpenLibrary,
    required this.onTransfer,
    required this.onAddLyrics,
    required this.onPlay,
    required this.onDismiss,
    required this.onFinish,
  });

  static const Key cardKey = ValueKey('listen-home:getting-started');
  static const Key dismissKey = ValueKey('listen-home:getting-started:dismiss');
  static const Key finishKey = ValueKey('listen-home:getting-started:finish');
  static const Key transferKey = ValueKey(
    'listen-home:getting-started:transfer',
  );

  static Key stepKey(MobileGettingStartedStep step) =>
      ValueKey('listen-home:getting-started:${step.name}');

  static Key actionKey(MobileGettingStartedStep step) =>
      ValueKey('listen-home:getting-started:${step.name}:action');

  @override
  Widget build(BuildContext context) {
    final canImport = onImport != null;
    GettingStartedItem item(
      MobileGettingStartedStep step, {
      required String label,
      required VoidCallback onAction,
      String? secondaryLabel,
      VoidCallback? onSecondary,
    }) => GettingStartedItem(
      key: stepKey(step),
      title: ListenHomeGettingStartedText.stepTitle(step),
      detail: ListenHomeGettingStartedText.stepDetail(
        step,
        progress,
        canImport: canImport,
      ),
      state: progress.stateOf(step),
      actionLabel: label,
      onAction: onAction,
      actionKey: actionKey(step),
      secondaryLabel: secondaryLabel,
      onSecondary: onSecondary,
      secondaryKey: secondaryLabel == null ? null : transferKey,
    );

    return GettingStartedCard(
      key: cardKey,
      title: ListenHomeGettingStartedText.title,
      doneTitle: ListenHomeGettingStartedText.doneTitle,
      doneMessage: ListenHomeGettingStartedText.doneMessage,
      dismissKey: dismissKey,
      finishKey: finishKey,
      onDismiss: onDismiss,
      onFinish: onFinish,
      items: [
        item(
          MobileGettingStartedStep.addSongs,
          label: canImport
              ? ListenHomeGettingStartedText.importSongs
              : ListenHomeGettingStartedText.openLibrary,
          onAction: onImport ?? onOpenLibrary,
          secondaryLabel: ListenHomeGettingStartedText.transfer,
          onSecondary: onTransfer,
        ),
        item(
          MobileGettingStartedStep.addLyrics,
          label: ListenHomeGettingStartedText.addLyrics,
          onAction: onAddLyrics,
        ),
        item(
          MobileGettingStartedStep.playWithLyrics,
          label: ListenHomeGettingStartedText.play,
          onAction: onPlay,
        ),
      ],
    );
  }
}
