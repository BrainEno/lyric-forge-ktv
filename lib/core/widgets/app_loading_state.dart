import 'package:flutter/material.dart';

import '../theme/color_tokens.dart';
import '../theme/spacing_tokens.dart';

/// Centered progress indicator for a page or pane that is still loading.
///
/// Replaces the bare `Center(child: CircularProgressIndicator())` copies so
/// every loading view has the same spinner, an accessible label and, for
/// loads that can take a moment, an optional line of text below it.
class AppLoadingState extends StatelessWidget {
  const AppLoadingState({super.key, this.message});

  /// Optional line below the spinner, for example "正在读取工程".
  final String? message;

  /// Spoken label when no [message] is given.
  static const String defaultSemanticsLabel = '正在加载';

  @override
  Widget build(BuildContext context) {
    final text = message;
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              semanticsLabel: text ?? defaultSemanticsLabel,
            ),
            if (text != null) ...[
              const SizedBox(height: AppSpacing.md),
              ExcludeSemantics(
                child: Text(text, textAlign: TextAlign.center, style: style),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small spinner beside one line of text, for a step that runs inside a
/// card, dialog or toolbar rather than filling a pane.
///
/// The setup dialog, the storage preflight card and the span recognition
/// dialog each drew this row by hand, with their own spinner size and text
/// style. [framed] adds the elevated card used when the row stands alone in
/// a column of cards.
class AppInlineLoading extends StatelessWidget {
  const AppInlineLoading({
    super.key,
    required this.message,
    this.framed = false,
  });

  /// What is running, for example "正在检查安装磁盘可用空间…".
  final String message;

  /// Draw the row inside an elevated, rounded card.
  final bool framed;

  /// Edge length of the spinner; matches the 18 px icons beside it.
  static const double spinnerSize = 18;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary);
    final row = Row(
      mainAxisSize: framed ? MainAxisSize.max : MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: spinnerSize,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            semanticsLabel: message,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: ExcludeSemantics(child: Text(message, style: style)),
        ),
      ],
    );

    return Semantics(
      liveRegion: true,
      child: framed
          ? Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.bgElevated,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
                border: Border.all(color: AppColors.borderMuted),
              ),
              child: row,
            )
          : row,
    );
  }
}
