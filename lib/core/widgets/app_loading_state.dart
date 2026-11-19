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
