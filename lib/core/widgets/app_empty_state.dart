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

  /// First-run invitation that fills a whole screen (empty music library,
  /// nothing playing yet): the icon sits in a large tile, the title is a
  /// headline, and everything is framed in a card that scrolls on short
  /// screens.
  hero,
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
    this.status,
    this.footer,
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

  /// Shown between the message and the actions, e.g. an error line or a
  /// spinner while the actions are busy.
  final Widget? status;

  /// Shown below the actions, e.g. a quiet text button to a secondary path.
  final Widget? footer;

  /// Edge of the hero icon tile for [layout].
  static double heroIconExtentFor(AppLayoutSpec layout) {
    if (layout.isShort) return 92;
    if (layout.isCompact) return 112;
    return 156;
  }

  /// Upper bound for the text column so long messages stay readable.
  static const double maxContentWidth = 420;

  @override
  Widget build(BuildContext context) {
    if (density == AppEmptyStateDensity.hero) {
      return LayoutBuilder(
        builder: (context, constraints) =>
            _buildHero(context, AppResponsive.fromConstraints(constraints)),
      );
    }
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
            if (status != null) ...[
              const SizedBox(height: AppSpacing.md),
              status!,
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              _actionWrap(),
            ],
            if (footer != null) ...[
              const SizedBox(height: AppSpacing.sm),
              footer!,
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionWrap() {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      alignment: WrapAlignment.center,
      children: actions,
    );
  }

  Widget _buildHero(BuildContext context, AppLayoutSpec layout) {
    final text = Theme.of(context).textTheme;
    final tileExtent = heroIconExtentFor(layout);
    final gap = layout.isShort ? AppSpacing.md : AppSpacing.xl;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(layout.pageGutter),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: layout.isCompact ? 560 : 760),
          child: Container(
            padding: EdgeInsets.all(
              layout.isCompact ? AppSpacing.md : AppSpacing.xl,
            ),
            decoration: BoxDecoration(
              gradient: AppColors.cardGradient,
              borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
              border: Border.all(color: AppColors.borderMuted),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: tileExtent,
                  height: tileExtent,
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(
                      AppSpacing.radiusXLarge,
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: tileExtent * 0.44,
                    color: iconColor ?? AppColors.textSecondary,
                  ),
                ),
                SizedBox(height: gap),
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (message != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                if (status != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  status!,
                ],
                if (actions.isNotEmpty) ...[
                  SizedBox(height: gap),
                  _actionWrap(),
                ],
                if (footer != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  footer!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
