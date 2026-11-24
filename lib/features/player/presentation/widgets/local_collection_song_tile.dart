import 'package:flutter/material.dart';

import '../../../../core/widgets/app_artwork.dart';
import '../../../../core/widgets/app_song_row.dart';
import '../local_library_dependencies.dart';
import 'local_collection_song.dart';
import 'now_playing_listener.dart';

class LocalCollectionSongTile extends StatelessWidget {
  final LocalCollectionSong song;
  final LocalLibraryDependencies dependencies;
  final VoidCallback? onTap;
  final Widget trailing;
  final int? leadingIndex;

  const LocalCollectionSongTile({
    super.key,
    required this.song,
    required this.dependencies,
    required this.onTap,
    required this.trailing,
    this.leadingIndex,
  });

  @override
  Widget build(BuildContext context) {
    final index = leadingIndex;
    return NowPlayingListener(
      playbackSession: dependencies.playbackSession,
      audioPlayer: dependencies.audioPlayer,
      builder: (context, nowPlaying) => AppSongRow(
        title: song.title,
        subtitle: song.secondary,
        unavailable: !song.canPlay,
        unavailableLabel: song.secondary,
        index: index?.toString(),
        artwork: song.canPlay
            ? AppArtwork(
                path: song.artworkPath,
                borderRadius: AppArtwork.rowRadius,
              )
            : AppArtwork.missing(
                path: song.artworkPath,
                borderRadius: AppArtwork.rowRadius,
              ),
        playback: song.canPlay
            ? nowPlaying.playbackForPath(song.sourcePath)
            : AppSongRowPlayback.none,
        onTap: onTap,
        trailing: trailing,
      ),
    );
  }
}
