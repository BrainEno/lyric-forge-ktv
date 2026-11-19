import 'package:flutter/material.dart';

import '../theme/color_tokens.dart';
import 'app_empty_state.dart';

/// Centered message shown when a page, pane or list failed to load.
///
/// Uses the [AppEmptyState] layout with a red icon, so failures line up with
/// empty lists, and offers one retry button sized for touch. The text is a
/// live region, so screen readers announce the failure when it appears.
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.title,
    this.message,
    this.onRetry,
    this.retryLabel = defaultRetryLabel,
    this.icon = Icons.error_outline_rounded,
    this.density = AppEmptyStateDensity.page,
  });

  /// What failed, for example "加载工程失败".
  final String title;

  /// Optional explanation or technical detail below the title.
  final String? message;

  /// Shows the retry button when set.
  final VoidCallback? onRetry;

  final String retryLabel;
  final IconData icon;
  final AppEmptyStateDensity density;

  static const String defaultRetryLabel = '重试';

  /// Retry buttons keep the touch-target minimum height.
  static const double retryButtonHeight = 48;

  @override
  Widget build(BuildContext context) {
    final retry = onRetry;
    return Semantics(
      liveRegion: true,
      child: AppEmptyState(
        icon: icon,
        iconColor: AppColors.error,
        title: title,
        message: message,
        density: density,
        actions: [
          if (retry != null)
            FilledButton.tonalIcon(
              onPressed: retry,
              style: FilledButton.styleFrom(
                minimumSize: const Size(64, retryButtonHeight),
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(retryLabel),
            ),
        ],
      ),
    );
  }
}
