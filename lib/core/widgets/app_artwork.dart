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
class AppArtwork extends StatelessWidget {
  const AppArtwork({
    super.key,
    this.path,
    this.remoteUri,
    this.size,
    this.borderRadius = AppSpacing.radiusSmall,
    this.placeholderIcon = Icons.album_rounded,
    this.placeholderColor,
  });

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

    Widget placeholder() {
      final icon = placeholderIcon;
      final color = placeholderColor ?? AppColors.textTertiary;
      if (extent != null) return _Placeholder(icon, color, extent);
      return LayoutBuilder(
        builder: (context, constraints) =>
            _Placeholder(icon, color, constraints.biggest.shortestSide),
      );
    }

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

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: extent == null
          ? SizedBox.expand(child: image)
          : SizedBox.square(dimension: extent, child: image),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.icon, this.color, this.extent);

  final IconData icon;
  final Color color;
  final double extent;

  @override
  Widget build(BuildContext context) {
    final iconSize = extent * AppArtwork.placeholderIconScale;
    return ColoredBox(
      color: AppColors.bgSurface,
      child: Center(
        child: Icon(
          icon,
          size: iconSize.isFinite ? iconSize : null,
          color: color,
        ),
      ),
    );
  }
}
