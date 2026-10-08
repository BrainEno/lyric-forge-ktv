import 'package:flutter/material.dart';

import '../../domain/services/remote_playback_item_resolver.dart';

Future<void> runPlaybackActionWithFeedback(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } on RemotePlaybackResolutionException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error.message)));
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('播放失败，请检查音频或连接状态后重试。')),
      );
  }
}
