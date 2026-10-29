import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/remote_audio_track.dart';
import '../../domain/services/media_hub_client_service.dart';

class RemoteMediaArtwork extends StatefulWidget {
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
  State<RemoteMediaArtwork> createState() => _RemoteMediaArtworkState();
}

class _RemoteMediaArtworkState extends State<RemoteMediaArtwork> {
  Future<List<int>>? _artworkFuture;
  String? _connectionKey;

  @override
  void initState() {
    super.initState();
    _refreshArtworkFuture();
  }

  @override
  void didUpdateWidget(covariant RemoteMediaArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id ||
        oldWidget.track.artworkPath != widget.track.artworkPath ||
        oldWidget.track.hasArtwork != widget.track.hasArtwork ||
        oldWidget.client != widget.client ||
        oldWidget.localPath != widget.localPath ||
        _connectionKey != _currentConnectionKey()) {
      _refreshArtworkFuture();
    }
  }

  String? _currentConnectionKey() {
    final connection = widget.client.currentConnection;
    if (connection == null) return null;
    return '${connection.host}:${connection.port}:'
        '${connection.token}:${connection.tlsFingerprint}';
  }

  void _refreshArtworkFuture() {
    _connectionKey = _currentConnectionKey();
    final localPath = widget.localPath;
    final artworkPath = widget.track.artworkPath?.trim();
    if ((localPath != null && File(localPath).existsSync()) ||
        !widget.track.hasArtwork ||
        artworkPath == null ||
        artworkPath.isEmpty ||
        widget.client.currentConnection == null) {
      _artworkFuture = null;
      return;
    }

    // The client fetches bytes through the certificate-pinned HTTPS channel
    // and supplies the Bearer token in a request header, never in the URL.
    _artworkFuture = widget.client.fetchArtwork(widget.track);
  }

  @override
  Widget build(BuildContext context) {
    final local = widget.localPath == null ? null : File(widget.localPath!);
    final localExists = local != null && local.existsSync();
    final radius =
        widget.borderRadius ?? BorderRadius.circular(AppSpacing.radiusSmall);

    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: widget.extent,
        height: widget.extent,
        color: AppColors.bgSurface,
        child: localExists
            ? Image.file(local, fit: BoxFit.cover)
            : _remoteImage(),
      ),
    );
  }

  Widget _remoteImage() {
    final future = _artworkFuture;
    if (future == null) return _Fallback(icon: widget.fallbackIcon);

    return FutureBuilder<List<int>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _Fallback(icon: widget.fallbackIcon);
        }
        final bytes = snapshot.data;
        if (snapshot.connectionState == ConnectionState.done) {
          if (bytes == null || bytes.isEmpty) {
            return _Fallback(icon: widget.fallbackIcon);
          }
          return Image.memory(
            Uint8List.fromList(bytes),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => _Fallback(icon: widget.fallbackIcon),
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            _Fallback(icon: widget.fallbackIcon),
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
    );
  }
}

class _Fallback extends StatelessWidget {
  final IconData icon;

  const _Fallback({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Center(child: Icon(icon, color: AppColors.textSecondary));
  }
}
