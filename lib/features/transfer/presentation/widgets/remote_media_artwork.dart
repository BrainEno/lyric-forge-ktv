import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/widgets/app_artwork.dart';
import '../../domain/models/remote_audio_track.dart';
import '../../domain/services/media_hub_client_service.dart';

/// A desktop track's cover on the phone: the local copy when the song was
/// downloaded, otherwise the bytes fetched over the pinned channel.
///
/// It draws the frame and placeholder of [AppArtwork] (audit T-03): the same
/// corner radii, the same surface and the same icon scaled to the edge, so a
/// song looks the same in the phone's view of the desktop library as in the
/// local library. Only the fetch differs, because the token must stay out of
/// the URL.
class RemoteMediaArtwork extends StatefulWidget {
  final RemoteAudioTrack track;
  final MediaHubClientService client;
  final String? localPath;

  /// Edge length; null fills the parent.
  final double? extent;
  final IconData fallbackIcon;
  final double borderRadius;

  /// Clip to a circle, as artists are in the local library; [borderRadius]
  /// is ignored. Give it a square: it does not centre itself in a wide cell.
  final bool circle;

  const RemoteMediaArtwork({
    super.key,
    required this.track,
    required this.client,
    this.localPath,
    this.extent,
    this.fallbackIcon = Icons.music_note_rounded,
    this.borderRadius = AppArtwork.rowRadius,
    this.circle = false,
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
    if (AppArtwork.existingFile(localPath) != null ||
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
    final localPath = widget.localPath;
    if (AppArtwork.existingFile(localPath) != null) {
      // A downloaded cover that cannot be decoded falls back like a failed
      // download does (audit C-04); AppArtwork does that for files.
      return AppArtwork(
        path: localPath,
        size: widget.extent,
        borderRadius: widget.borderRadius,
        placeholderIcon: widget.fallbackIcon,
        circle: widget.circle,
      );
    }

    final extent = widget.extent;
    final image = _remoteImage();
    final sized = extent == null
        ? SizedBox.expand(child: image)
        : SizedBox.square(dimension: extent, child: image);
    if (widget.circle) return ClipOval(child: sized);
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: sized,
    );
  }

  Widget _fallback() =>
      AppArtworkPlaceholder(icon: widget.fallbackIcon, size: widget.extent);

  Widget _remoteImage() {
    final future = _artworkFuture;
    if (future == null) return _fallback();

    return FutureBuilder<List<int>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _fallback();
        final bytes = snapshot.data;
        if (snapshot.connectionState == ConnectionState.done) {
          if (bytes == null || bytes.isEmpty) return _fallback();
          return Image.memory(
            Uint8List.fromList(bytes),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => _fallback(),
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            _fallback(),
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
