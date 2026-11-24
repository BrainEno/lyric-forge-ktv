import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';

/// The words of 设置 › 帮助 › 开始使用指南 (D-070, D-071).
abstract final class GettingStartedSettingsText {
  static const String group = '帮助';
  static const String title = '开始使用指南';
  static const String subtitle = '首页的三步清单：导入并识别一首歌、校对歌词、用 KTV 模式唱一遍。';

  /// The phone's home is 听歌 (D-041), and its steps are its own (D-071).
  static const String mobileSubtitle = '听歌页的三步清单：把歌放进手机、给一首歌配歌词、跟着歌词播放。';
  static const String show = '在首页重新显示';
  static const String shown = '回到首页就能看到开始使用指南。';
  static String failed(Object error) => '没能打开开始使用指南：$error';
}

/// Brings the dashboard's 开始使用 checklist back after it was put away.
class GettingStartedSettingsCard extends StatelessWidget {
  final Future<void> Function() onShow;

  const GettingStartedSettingsCard({super.key, required this.onShow});

  static const Key showKey = ValueKey('settings:getting-started:show');

  Future<void> _show(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    String message;
    try {
      await onShow();
      message = GettingStartedSettingsText.shown;
    } on Object catch (error) {
      message = GettingStartedSettingsText.failed(error);
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final extent = AppResponsive.of(context).minimumInteractiveExtent;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: OutlinedButton.icon(
        key: showKey,
        style: OutlinedButton.styleFrom(minimumSize: Size(extent, extent)),
        onPressed: () => _show(context),
        icon: const Icon(Icons.replay_rounded, size: 18),
        label: const Text(GettingStartedSettingsText.show),
      ),
    );
  }
}
