import '../../../project/domain/models/audio_asset.dart';

/// 播放历史记录
class PlayHistory {
  final String id;
  final String name;
  final String? artist;
  final String filePath;
  final DateTime playedAt;
  final Duration? lastPosition;
  final Duration? duration;
  final AudioSourceType lastSource;

  const PlayHistory({
    required this.id,
    required this.name,
    this.artist,
    required this.filePath,
    required this.playedAt,
    this.lastPosition,
    this.duration,
    this.lastSource = AudioSourceType.original,
  });

  PlayHistory copyWith({
    String? id,
    String? name,
    String? artist,
    String? filePath,
    DateTime? playedAt,
    Duration? lastPosition,
    Duration? duration,
    AudioSourceType? lastSource,
  }) {
    return PlayHistory(
      id: id ?? this.id,
      name: name ?? this.name,
      artist: artist ?? this.artist,
      filePath: filePath ?? this.filePath,
      playedAt: playedAt ?? this.playedAt,
      lastPosition: lastPosition ?? this.lastPosition,
      duration: duration ?? this.duration,
      lastSource: lastSource ?? this.lastSource,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'artist': artist,
      'filePath': filePath,
      'playedAt': playedAt.toIso8601String(),
      'lastPosition': lastPosition?.inMilliseconds,
      'duration': duration?.inMilliseconds,
      'lastSource': lastSource.name,
    };
  }

  factory PlayHistory.fromJson(Map<String, dynamic> json) {
    return PlayHistory(
      id: json['id'] as String,
      name: json['name'] as String,
      artist: json['artist'] as String?,
      filePath: json['filePath'] as String,
      playedAt: DateTime.parse(json['playedAt'] as String),
      lastPosition: json['lastPosition'] != null
          ? Duration(milliseconds: json['lastPosition'] as int)
          : null,
      duration: json['duration'] != null
          ? Duration(milliseconds: json['duration'] as int)
          : null,
      lastSource: AudioSourceType.values.byName(json['lastSource'] as String),
    );
  }

  /// 格式化播放时间
  String get formattedPlayedAt {
    final now = DateTime.now();
    final diff = now.difference(playedAt);

    if (diff.inMinutes < 1) {
      return '刚刚';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}分钟前';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}小时前';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    } else {
      return '${playedAt.month}/${playedAt.day}';
    }
  }
}
