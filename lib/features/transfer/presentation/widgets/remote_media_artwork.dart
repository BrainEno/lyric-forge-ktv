import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/remote_audio_track.dart';
import '../../domain/services/media_hub_client_service.dart';
import '../screens/remote_catalog_utils.dart';

class RemoteMediaArtwork extends StatelessWidget {
  final RemoteAudioTrack track;
  final MediaHubClientService client;
  final String? localPath;
  final double extent;
  final IconData fallbackIcon;
  final BorderRadius? borderRadius;

  const RemoteMediaArtwork({
    super.key,
    required this.track,
    required this.client,
    this.localPath,
    required this.extent,
    this.fallbackIcon = Icons.music_note_rounded,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final local = localPath == null ? null : File(localPath!);
    final localExists = local != null && local.existsSync();
    final remoteUri = localExists ? null : remoteArtworkUriFor(client, track);
    final radius = borderRadius ?? BorderRadius.circular(AppSpacing.radiusSmall);

    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: extent,
        height: extent,
        color: AppColors.bgSurface,
        child: localExists
            ? Image.file(local!, fit: BoxFit.cover)
            : remoteUri == null
                ? _Fallback(icon: fallbackIcon)
                : Image.network(
                    remoteUri.toString(),
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, __, ___) => _Fallback(icon: fallbackIcon),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          _Fallback(icon: fallbackIcon),
                          const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  final IconData icon;

  const _Fallback({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(icon, color: AppColors.textSecondary),
    );
  }
}
