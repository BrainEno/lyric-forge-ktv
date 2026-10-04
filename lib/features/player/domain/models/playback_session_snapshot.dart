import '../../../project/domain/models/audio_asset.dart';
import '../services/playback_session_service.dart';

class PlaybackSessionItemSnapshot {
  final String id;
  final String title;
  final String? artist;
  final String? artworkPath;
  final bool hasLyrics;
  final AudioAsset audioAsset;
  final AudioSourceType preferredSource;

  const PlaybackSessionItemSnapshot({
    required this.id,
    required this.title,
    required this.audioAsset,
    this.artist,
    this.artworkPath,
    this.hasLyrics = false,
    this.preferredSource = AudioSourceType.original,
  });

  factory PlaybackSessionItemSnapshot.fromPlaybackItem(PlaybackItem item) {
    return PlaybackSessionItemSnapshot(
      id: item.id,
      title: item.title,
      artist: item.artist,
      artworkPath: item.artworkPath,
      hasLyrics: item.hasLyrics,
      audioAsset: item.audioAsset,
      preferredSource: item.preferredSource,
    );
  }

  PlaybackItem toPlaybackItem() {
    return PlaybackItem(
      id: id,
      title: title,
      artist: artist,
      artworkPath: artworkPath,
      hasLyrics: hasLyrics,
      audioAsset: audioAsset,
      preferredSource: preferredSource,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'artworkPath': artworkPath,
        'hasLyrics': hasLyrics,
        'audioAsset': audioAsset.toJson(),
        'preferredSource': preferredSource.name,
      };

  factory PlaybackSessionItemSnapshot.fromJson(Map<String, dynamic> json) {
    final asset = json['audioAsset'];
    if (asset is! Map) throw const FormatException('snapshot 缺少 audioAsset');
    final sourceName = json['preferredSource'] as String?;
    final source = AudioSourceType.values.where((value) => value.name == sourceName);
    return PlaybackSessionItemSnapshot(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String?,
      artworkPath: json['artworkPath'] as String?,
      hasLyrics: json['hasLyrics'] as bool? ?? false,
      audioAsset: AudioAsset.fromJson(Map<String, dynamic>.from(asset)),
      preferredSource:
          source.isEmpty ? AudioSourceType.original : source.first,
    );
  }
}

class PlaybackSessionSnapshot {
  final List<PlaybackSessionItemSnapshot> items;
  final int currentIndex;
  final Duration position;
  final bool shuffleEnabled;
  final PlaybackRepeatMode repeatMode;
  final DateTime savedAt;

  const PlaybackSessionSnapshot({
    required this.items,
    required this.currentIndex,
    required this.position,
    required this.shuffleEnabled,
    required this.repeatMode,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'items': items.map((item) => item.toJson()).toList(growable: false),
        'currentIndex': currentIndex,
        'positionMs': position.inMilliseconds,
        'shuffleEnabled': shuffleEnabled,
        'repeatMode': repeatMode.name,
        'savedAt': savedAt.toIso8601String(),
      };

  factory PlaybackSessionSnapshot.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    if (rawItems is! List) throw const FormatException('snapshot 缺少 items');
    final items = <PlaybackSessionItemSnapshot>[];
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      items.add(
        PlaybackSessionItemSnapshot.fromJson(Map<String, dynamic>.from(raw)),
      );
    }
    final repeatName = json['repeatMode'] as String?;
    final repeats =
        PlaybackRepeatMode.values.where((value) => value.name == repeatName);
    return PlaybackSessionSnapshot(
      items: List.unmodifiable(items),
      currentIndex: (json['currentIndex'] as num?)?.toInt() ?? 0,
      position: Duration(
        milliseconds: (json['positionMs'] as num?)?.toInt() ?? 0,
      ),
      shuffleEnabled: json['shuffleEnabled'] as bool? ?? false,
      repeatMode:
          repeats.isEmpty ? PlaybackRepeatMode.off : repeats.first,
      savedAt: DateTime.tryParse(json['savedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
