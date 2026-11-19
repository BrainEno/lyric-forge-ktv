import 'package:flutter/material.dart';

import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_artwork.dart';
import '../../domain/services/playback_session_service.dart';

/// [AppArtwork] for a playback item, with one rule for every player surface.
///
/// The item's own cover wins, then the audio file's thumbnail. Only Media Hub
/// streams may fall back to their remote cover URL, which matches what the
/// session service downloads and what the system media controls publish.
class PlaybackArtwork extends StatelessWidget {
  const PlaybackArtwork({
    super.key,
    required this.item,
    this.size,
    this.borderRadius = AppSpacing.radiusSmall,
  });

  final PlaybackItem item;

  /// Edge length; null fills the parent.
  final double? size;

  final double borderRadius;

  /// The local cover path: the item's artwork, else the audio thumbnail.
  static String? localPathOf(PlaybackItem item) => item.localArtworkPath;

  /// The remote cover of a Media Hub stream, if it has a usable one.
  static Uri? remoteUriOf(PlaybackItem item) {
    if (!item.isRemoteStream) return null;
    final raw = item.audioAsset.metadata['remoteArtworkUri'];
    if (raw is! String) return null;
    return AppArtwork.networkUri(Uri.tryParse(raw.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AppArtwork(
      path: localPathOf(item),
      remoteUri: remoteUriOf(item),
      size: size,
      borderRadius: borderRadius,
      placeholderIcon: item.isRemoteStream
          ? Icons.cloud_rounded
          : Icons.album_rounded,
    );
  }
}
