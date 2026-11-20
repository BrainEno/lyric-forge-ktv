import 'package:flutter/material.dart';

import '../layout/app_responsive.dart';
import '../theme/color_tokens.dart';
import '../theme/spacing_tokens.dart';
import 'app_tap_target.dart';

/// The grid card of every music catalog: a cover above a title and up to two
/// short lines, read by a screen reader as one button (audit T-03, L-04).
///
/// The local library's artist/album, playlist and song grids and the phone's
/// view of the desktop library each drew this card themselves, with two
/// corner radii, three paddings, two title weights, three grid ratios and two
/// ways of showing an unavailable item. Their ripple also ran under an opaque container, so a
/// tap left no visible trace. This card is the one shape they share: the
/// surface is the [Material], so the ink shows, and the border turns red only
/// for an item that cannot be opened.
class AppCatalogCard extends StatelessWidget {
  const AppCatalogCard({
    super.key,
    required this.artwork,
    required this.title,
    required this.semanticLabel,
    this.subtitle,
    this.caption,
    this.semanticHint,
    this.onTap,
    this.enabled = true,
    this.unavailable = false,
    this.subtitleIsAlert = false,
    this.semanticActions = const {},
    this.titleTrailing,
    this.artworkOverlay,
    this.compact = false,
  });

  /// The cover, usually an `AppArtwork` without a size; it gets the largest
  /// square that fits above the text, centred.
  final Widget artwork;
  final String title;

  /// The line under the title, e.g. the artist or a count.
  final String? subtitle;

  /// A smaller third line, e.g. the format and lyrics notes.
  final String? caption;

  /// The whole card in one sentence; see [AppTapTarget.join].
  final String semanticLabel;

  /// What a tap does, e.g. 播放 or 打开专辑.
  final String? semanticHint;
  final VoidCallback? onTap;

  /// False reads the card as disabled and drops its tap; the
  /// [semanticActions] stay.
  final bool enabled;

  /// The item cannot be opened (a missing file): red border.
  final bool unavailable;

  /// The subtitle reports a problem, e.g. 2 首不可用: red text.
  final bool subtitleIsAlert;

  /// The buttons inside the card by label, in reading order; see
  /// [AppTapTarget.actions].
  final Map<String, VoidCallback?> semanticActions;

  /// A small control at the end of the title row, e.g. a ⋯ menu.
  final Widget? titleTrailing;

  /// A control in the cover's top-right corner, e.g. a ⋯ menu.
  final Widget? artworkOverlay;

  /// Tighter padding for phone grids.
  final bool compact;

  static const double radius = AppSpacing.radiusXLarge;

  /// The narrowest a card may get before the grid drops a column.
  static double minTileWidthFor(AppLayoutSpec layout) =>
      layout.isCompact ? 160 : 190;

  /// Width over height. The cover is square and as wide as the card, so the
  /// card is a little taller than wide by the text below it.
  static double aspectRatioFor(AppLayoutSpec layout) =>
      layout.isCompact ? 0.74 : 0.72;

  /// How many cards fit across [layout]: two at least, seven at most.
  static int columnsFor(AppLayoutSpec layout) =>
      layout.gridColumns(minTileWidth: minTileWidthFor(layout), min: 2);

  /// The grid every catalog of these cards uses, so artists, albums, songs
  /// and playlists, local or on the desktop, line up the same way.
  static SliverGridDelegate gridDelegateFor(AppLayoutSpec layout) {
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columnsFor(layout),
      childAspectRatio: aspectRatioFor(layout),
      crossAxisSpacing: AppSpacing.md,
      mainAxisSpacing: AppSpacing.md,
    );
  }

  /// The padding inside the card.
  static double paddingFor({required bool compact}) =>
      compact ? AppSpacing.sm : AppSpacing.md;

  /// The border colour for an available or [unavailable] item.
  static Color borderColorFor({required bool unavailable}) =>
      unavailable ? AppColors.error.withAlpha(80) : AppColors.borderMuted;

  /// The subtitle colour, red when it reports a problem.
  static Color subtitleColorFor({required bool alert}) =>
      alert ? AppColors.errorText : AppColors.textSecondary;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tap = enabled ? onTap : null;
    final overlay = artworkOverlay;
    final trailing = titleTrailing;
    final subtitleText = subtitle;
    final captionText = caption;

    return AppTapTarget(
      label: semanticLabel,
      hint: semanticHint,
      enabled: enabled,
      onTap: onTap,
      actions: semanticActions,
      child: Material(
        color: AppColors.bgElevated,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: borderColorFor(unavailable: unavailable)),
        ),
        child: InkWell(
          onTap: tap,
          hoverColor: AppColors.hoverOverlay,
          child: Padding(
            padding: EdgeInsets.all(paddingFor(compact: compact)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: overlay == null
                          ? artwork
                          : Stack(
                              fit: StackFit.expand,
                              children: [
                                artwork,
                                Align(
                                  alignment: Alignment.topRight,
                                  child: overlay,
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ?trailing,
                  ],
                ),
                if (subtitleText != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitleText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: subtitleColorFor(alert: subtitleIsAlert),
                    ),
                  ),
                ],
                if (captionText != null && captionText.isNotEmpty)
                  Text(
                    captionText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
