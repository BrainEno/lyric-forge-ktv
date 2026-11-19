// Shared pieces of the dashboard cards: artwork, the eyebrow label, the hero
// and card backgrounds, and the muted caption style.
//
// Split out of `dashboard_screen.dart`, which held 21 private widgets in one
// 1600-line file (audit D-06).

import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_artwork.dart';

class DashboardArtwork extends StatelessWidget {
  final String? path;
  final double size;
  const DashboardArtwork({super.key, this.path, required this.size});

  @override
  Widget build(BuildContext context) {
    return AppArtwork(
      path: path,
      size: size,
      borderRadius: AppSpacing.radiusMedium,
    );
  }
}

class DashboardEyebrow extends StatelessWidget {
  final String text;
  const DashboardEyebrow(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: AppColors.accent,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    );
  }
}

BoxDecoration dashboardHeroDecoration() => BoxDecoration(
  gradient: AppColors.playerGradient,
  borderRadius: BorderRadius.circular(AppSpacing.radiusXLarge),
  border: Border.all(color: AppColors.borderMuted),
);

BoxDecoration dashboardCardDecoration() => BoxDecoration(
  color: AppColors.bgElevated,
  borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
  border: Border.all(color: AppColors.borderMuted),
);

TextStyle? dashboardMutedLabel(BuildContext context) => Theme.of(
  context,
).textTheme.labelSmall?.copyWith(color: AppColors.textTertiary);
