import 'package:flutter/material.dart';

import '../layout/app_responsive.dart';
import '../theme/color_tokens.dart';
import '../theme/spacing_tokens.dart';

/// How much room an [AppEmptyState] takes.
enum AppEmptyStateDensity {
  /// Main content of a page or pane: 56 px icon, title and optional message.
  page,

  /// Inside a side panel, sheet or list section: 36 px icon, muted title.
  panel,
}

/// Centered placeholder shown when a list, page or pane has nothing to show.
///
/// Replaces the per-screen private empty widgets so icon size, spacing, text
/// styles and action layout stay the same everywhere. Pass buttons with a
/// finite minimum size in [actions]; they are laid out in a centered [Wrap].
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actions = const [],
    this.density = AppEmptyStateDensity.page,
    this.iconColor,
  });

  final IconData icon;
  final String title;

  /// Optional second line that explains what to do next.
  final String? message;

  /// Buttons offered below the text, usually one primary action.
  final List<Widget> actions;

  final AppEmptyStateDensity density;

  /// Icon colour; defaults to the tertiary text colour. Error states pass
  /// [AppColors.error].
  final Color? iconColor;

  /// Upper bound for the text column so long messages stay readable.
  static const double maxContentWidth = 420;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isPage = density == AppEmptyStateDensity.page;
    final padding = isPage && !AppResponsive.of(context).isCompact
        ? AppSpacing.xl
        : AppSpacing.lg;
    final titleStyle = isPage
        ? text.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : text.bodyMedium?.copyWith(color: AppColors.textSecondary);
    final messageStyle = isPage
        ? text.bodyMedium?.copyWith(color: AppColors.textSecondary)
        : text.bodySmall?.copyWith(color: AppColors.textTertiary);

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: maxContentWidth),
        padding: EdgeInsets.all(padding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: isPage ? 56 : 36,
              color: iconColor ?? AppColors.textTertiary,
            ),
            SizedBox(height: isPage ? AppSpacing.md : AppSpacing.sm),
            Semantics(
              header: isPage,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: titleStyle,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(message!, textAlign: TextAlign.center, style: messageStyle),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                alignment: WrapAlignment.center,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
