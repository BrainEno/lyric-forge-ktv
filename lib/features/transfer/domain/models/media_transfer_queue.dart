import 'media_transfer_batch.dart';
import 'remote_audio_track.dart';

enum MediaTransferQueueStatus { queued, transferring, completed, failed }

class MediaTransferQueueItem {
  final String id;
  final MediaTransferDirection direction;
  final String title;
  final MediaTransferQueueStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? sourcePath;
  final RemoteAudioTrack? remoteTrack;
  final int bytesTransferred;
  final int? totalBytes;
  final String? destinationPath;
  final String? error;

  const MediaTransferQueueItem({
    required this.id,
    required this.direction,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.sourcePath,
    this.remoteTrack,
    this.bytesTransferred = 0,
    this.totalBytes,
    this.destinationPath,
    this.error,
  });

  bool get isTerminal =>
      status == MediaTransferQueueStatus.completed ||
      status == MediaTransferQueueStatus.failed;

  MediaTransferQueueItem copyWith({
    MediaTransferQueueStatus? status,
    DateTime? updatedAt,
    int? bytesTransferred,
    int? totalBytes,
    String? destinationPath,
    String? error,
    bool clearDestinationPath = false,
    bool clearError = false,
  }) {
    return MediaTransferQueueItem(
      id: id,
      direction: direction,
      title: title,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sourcePath: sourcePath,
      remoteTrack: remoteTrack,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      totalBytes: totalBytes ?? this.totalBytes,
      destinationPath:
          clearDestinationPath ? null : destinationPath ?? this.destinationPath,
      error: clearError ? null : error ?? this.error,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'direction': direction.name,
        'title': title,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'sourcePath': sourcePath,
        'remoteTrack': remoteTrack == null
            ? null
            : {
                'id': remoteTrack!.id,
                'title': remoteTrack!.title,
                'artist': remoteTrack!.artist,
                'album': remoteTrack!.album,
                'format': remoteTrack!.format,
                'byteLength': remoteTrack!.byteLength,
                'durationMs': remoteTrack!.duration?.inMilliseconds,
                'streamPath': remoteTrack!.streamPath,
                'downloadPath': remoteTrack!.downloadPath,
                'hasLyrics': remoteTrack!.hasLyrics,
                'lyricsPath': remoteTrack!.lyricsPath,
                'hasArtwork': remoteTrack!.hasArtwork,
                'artworkPath': remoteTrack!.artworkPath,
              },
        'bytesTransferred': bytesTransferred,
        'totalBytes': totalBytes,
        'destinationPath': destinationPath,
        'error': error,
      };

  factory MediaTransferQueueItem.fromJson(Map<String, dynamic> json) {
    final directionName = json['direction'] as String?;
    final statusName = json['status'] as String?;
    final remote = json['remoteTrack'];
    return MediaTransferQueueItem(
      id: json['id'] as String,
      direction: MediaTransferDirection.values.firstWhere(
        (value) => value.name == directionName,
      ),
      title: json['title'] as String,
      status: MediaTransferQueueStatus.values.firstWhere(
        (value) => value.name == statusName,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      sourcePath: json['sourcePath'] as String?,
      remoteTrack: remote is Map
          ? RemoteAudioTrack.fromJson(Map<String, dynamic>.from(remote))
          : null,
      bytesTransferred: (json['bytesTransferred'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt(),
      destinationPath: json['destinationPath'] as String?,
      error: json['error'] as String?,
    );
  }
}

class MediaTransferQueueSnapshot {
  final List<MediaTransferQueueItem> items;
  final bool isPaused;
  final bool isProcessing;
  final String? pauseReason;

  const MediaTransferQueueSnapshot({
    this.items = const [],
    this.isPaused = false,
    this.isProcessing = false,
    this.pauseReason,
  });

  List<MediaTransferQueueItem> get queued => items
      .where((item) => item.status == MediaTransferQueueStatus.queued)
      .toList(growable: false);

  List<MediaTransferQueueItem> get failed => items
      .where((item) => item.status == MediaTransferQueueStatus.failed)
      .toList(growable: false);

  List<MediaTransferQueueItem> get completed => items
      .where((item) => item.status == MediaTransferQueueStatus.completed)
      .toList(growable: false);

  MediaTransferQueueItem? get active {
    for (final item in items) {
      if (item.status == MediaTransferQueueStatus.transferring) return item;
    }
    return null;
  }

  MediaTransferQueueSnapshot copyWith({
    List<MediaTransferQueueItem>? items,
    bool? isPaused,
    bool? isProcessing,
    String? pauseReason,
    bool clearPauseReason = false,
  }) {
    return MediaTransferQueueSnapshot(
      items: items ?? this.items,
      isPaused: isPaused ?? this.isPaused,
      isProcessing: isProcessing ?? this.isProcessing,
      pauseReason:
          clearPauseReason ? null : pauseReason ?? this.pauseReason,
    );
  }
}
