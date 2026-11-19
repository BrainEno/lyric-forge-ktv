import 'package:flutter/material.dart';

import '../theme/color_tokens.dart';
import '../theme/spacing_tokens.dart';

/// Meaning of an [AppBadge], which decides its colour.
enum AppBadgeTone {
  /// Plain metadata such as a format, a count or a duration.
  neutral,

  /// The current item or a selected state.
  accent,

  /// Something finished or healthy.
  success,

  /// Something that needs a look but still works.
  warning,

  /// Something failed or is missing.
  error,

  /// Neutral information that should stand out from metadata.
  info,
}

/// How much room an [AppBadge] takes.
enum AppBadgeSize {
  /// Inside dense rows such as lyric lines and list tiles.
  small,

  /// Next to titles, in headers and in cards.
  regular,
}

/// Rounded label for status, metadata and counts.
///
/// Replaces the per-screen pill widgets so padding, radius, icon size,
/// background alpha and text style are the same everywhere. Neutral badges sit
/// on the surface colour with secondary text; every other tone, or an explicit
/// [color], uses a light tint of that colour behind text in the full colour.
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.icon,
    this.tone = AppBadgeTone.neutral,
    this.color,
    this.size = AppBadgeSize.regular,
    this.emphasized = false,
  });

  final String label;

  /// Optional leading icon.
  final IconData? icon;

  final AppBadgeTone tone;

  /// Overrides the [tone] colour, for callers that already map a status to a
  /// colour of their own.
  final Color? color;

  final AppBadgeSize size;

  /// Bold label, for badges that carry the main status of a row.
  final bool emphasized;

  /// Background alpha of tinted badges (out of 255).
  static const int tintAlpha = 24;

  /// Foreground colour for [tone], or null for the neutral style.
  static Color? toneColor(AppBadgeTone tone) {
    return switch (tone) {
      AppBadgeTone.neutral => null,
      AppBadgeTone.accent => AppColors.accent,
      AppBadgeTone.success => AppColors.success,
      AppBadgeTone.warning => AppColors.warning,
      AppBadgeTone.error => AppColors.error,
      AppBadgeTone.info => AppColors.info,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tint = color ?? toneColor(tone);
    final foreground = tint ?? AppColors.textSecondary;
    final background = tint?.withAlpha(tintAlpha) ?? AppColors.bgSurface;
    final small = size == AppBadgeSize.small;
    final text = Theme.of(context).textTheme;
    final textStyle = text.labelSmall?.copyWith(
      color: foreground,
      fontSize: small ? 10 : null,
      fontWeight: emphasized ? FontWeight.w700 : null,
    );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : AppSpacing.sm,
        vertical: small ? 2 : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: small ? 12 : 14, color: foreground),
            SizedBox(width: small ? 3 : AppSpacing.xs),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyle,
            ),
          ),
        ],
      ),
    );
  }
}
