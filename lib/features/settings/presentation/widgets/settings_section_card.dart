import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';

/// Card that frames one group of settings: an icon, a title, an optional
/// one-line explanation and the controls below.
///
/// Settings used to put every recognition control into one long card. Each
/// group (plan, models and storage, maintenance, advanced) now gets its own
/// card so the page reads as a list of sections rather than one wall.
class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;

  /// Short explanation under the title.
  final String? subtitle;

  final Widget child;

  /// Size of the tinted square behind the icon.
  static const double iconBoxExtent = 40;

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    final text = Theme.of(context).textTheme;
    final description = subtitle;

    return Container(
      padding: EdgeInsets.all(layout.isCompact ? AppSpacing.md : AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
        border: Border.all(color: AppColors.borderMuted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: iconBoxExtent,
                height: iconBoxExtent,
                decoration: BoxDecoration(
                  color: AppColors.accent.withAlpha(24),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
                ),
                child: Icon(icon, size: 22, color: AppColors.accent),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        description,
                        style: text.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}
