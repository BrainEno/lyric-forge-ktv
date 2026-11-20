import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/color_tokens.dart';
import '../theme/spacing_tokens.dart';

/// Square cover image with one placeholder style for the whole app.
///
/// Shows the local file at [path] when it exists, otherwise the image at
/// [remoteUri] (http and https only), otherwise [placeholderIcon] centered on
/// the surface colour. A file or download that cannot be decoded falls back to
/// the placeholder too. Without [size] the artwork fills its parent, which
/// must then give it bounded constraints.
///
/// The music library used to wrap this in three private widgets per section
/// that only chose a corner radius and an icon (audit L-04); the choices now
/// live here as [tileRadius], [rowRadius], [AppArtwork.person] and
/// [AppArtwork.missing], so every section draws the same cover for the same
/// kind of thing.
class AppArtwork extends StatelessWidget {
  const AppArtwork({
    super.key,
    this.path,
    this.remoteUri,
    this.size,
    this.borderRadius = AppSpacing.radiusSmall,
    this.placeholderIcon = Icons.album_rounded,
    this.placeholderColor,
    this.circle = false,
  }) : _missing = false;

  /// An artist's picture: round, with a person placeholder.
  const AppArtwork.person({super.key, this.path, this.size})
    : remoteUri = null,
      borderRadius = 0,
      placeholderIcon = Icons.person_rounded,
      placeholderColor = null,
      circle = true,
      _missing = false;

  /// A song whose file cannot be found: its cover if one is still on disk,
  /// otherwise a broken-link placeholder in the error colour instead of the
  /// album icon, so the gap reads as a problem rather than a missing cover.
  const AppArtwork.missing({
    super.key,
    this.path,
    this.size,
    this.borderRadius = AppArtwork.tileRadius,
  }) : remoteUri = null,
       placeholderIcon = Icons.link_off_rounded,
       // The error colour is read when the placeholder is built, so it
       // follows the theme (D-042); a constant constructor cannot hold it.
       placeholderColor = null,
       circle = false,
       _missing = true;

  final String? path;
  final Uri? remoteUri;

  /// Edge length; null fills the parent.
  final double? size;

  final double borderRadius;
  final IconData placeholderIcon;

  /// Placeholder icon colour; defaults to [AppColors.textTertiary]. Use a
  /// status colour only when the placeholder itself carries meaning, such as
  /// a song whose file is missing.
  final Color? placeholderColor;

  /// Clip to a circle instead of a rounded square; [borderRadius] is ignored.
  final bool circle;

  /// Built by [AppArtwork.missing]: the placeholder takes the error colour.
  final bool _missing;

  /// Corner radius of a cover that heads a card or a grid tile.
  static const double tileRadius = AppSpacing.radiusLarge;

  /// Corner radius of a cover at the start of a list row.
  static const double rowRadius = AppSpacing.radiusMedium;

  /// Placeholder icon size as a fraction of the artwork edge.
  static const double placeholderIconScale = 0.42;

  /// The local file to show, or null when [path] is empty or missing.
  static File? existingFile(String? path) {
    final trimmed = path?.trim();
    if (kIsWeb || trimmed == null || trimmed.isEmpty) return null;
    final file = File(trimmed);
    return file.existsSync() ? file : null;
  }

  /// [uri] when [Image.network] may load it, otherwise null.
  static Uri? networkUri(Uri? uri) {
    if (uri == null) return null;
    return uri.scheme == 'http' || uri.scheme == 'https' ? uri : null;
  }

  @override
  Widget build(BuildContext context) {
    final extent = size;
    final file = existingFile(path);
    final remote = networkUri(remoteUri);

    Widget placeholder() => AppArtworkPlaceholder(
      icon: placeholderIcon,
      color: placeholderColor ?? (_missing ? AppColors.error : null),
      size: extent,
    );

    final Widget image;
    if (file != null) {
      image = Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder(),
      );
    } else if (remote != null) {
      image = Image.network(
        remote.toString(),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder(),
      );
    } else {
      image = placeholder();
    }

    final sized = extent == null
        ? SizedBox.expand(child: image)
        : SizedBox.square(dimension: extent, child: image);
    if (circle) {
      // A circle in a wide cell stays round: centre a square of the short
      // side instead of stretching into an oval.
      if (extent != null) return ClipOval(child: sized);
      return LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.biggest.shortestSide;
          return Center(
            child: ClipOval(
              child: SizedBox.square(
                dimension: side.isFinite ? side : null,
                child: image,
              ),
            ),
          );
        },
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: sized,
    );
  }
}

/// The placeholder [AppArtwork] draws when there is no cover: [icon] at
/// [AppArtwork.placeholderIconScale] of the edge, on the surface colour.
///
/// Public so a cover that loads in steps (the phone fetching one from the
/// desktop) can show the same placeholder under its spinner.
class AppArtworkPlaceholder extends StatelessWidget {
  const AppArtworkPlaceholder({
    super.key,
    this.icon = Icons.album_rounded,
    this.color,
    this.size,
  });

  final IconData icon;

  /// Defaults to [AppColors.textTertiary].
  final Color? color;

  /// Edge length; null fills the parent and scales the icon to its short
  /// side.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final extent = size;
    if (extent != null) return _placeholder(extent);
    return LayoutBuilder(
      builder: (context, constraints) =>
          _placeholder(constraints.biggest.shortestSide),
    );
  }

  Widget _placeholder(double extent) {
    final iconSize = extent * AppArtwork.placeholderIconScale;
    return ColoredBox(
      color: AppColors.bgSurface,
      child: Center(
        child: Icon(
          icon,
          size: iconSize.isFinite ? iconSize : null,
          color: color ?? AppColors.textTertiary,
        ),
      ),
    );
  }
}
