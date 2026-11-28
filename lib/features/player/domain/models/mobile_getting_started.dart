import '../../../../core/onboarding/getting_started.dart';
import '../services/playback_session_service.dart';

/// The phone's three steps (D-071): songs on the phone, lyrics for one of
/// them, and listening along.
///
/// A phone cannot run recognition (D-058), so these are not the desktop's
/// import → review → KTV steps (D-070) but the phone's own work.
enum MobileGettingStartedStep { addSongs, addLyrics, playWithLyrics }

/// How far the phone user has got, worked out from the library, the lyric
/// pairings and the recent plays.
class MobileGettingStartedProgress {
  /// Songs in the library whose file is there.
  final int songCount;

  /// Of those, the songs with lyrics.
  final int lyricSongCount;

  /// A song with lyrics for 跟着歌词播放一首; null while there is none.
  final PlaybackItem? lyricSong;

  /// A song with lyrics is among the recent plays, or playing now.
  final bool playedWithLyrics;

  const MobileGettingStartedProgress({
    required this.songCount,
    required this.lyricSongCount,
    this.lyricSong,
    this.playedWithLyrics = false,
  });

  /// The same progress with what is playing now taken into account: a song
  /// with lyrics on the turntable finishes the last step before it reaches
  /// the history.
  MobileGettingStartedProgress whilePlaying(PlaybackItem? current) {
    if (playedWithLyrics || current == null || !current.hasLyrics) {
      return this;
    }
    return MobileGettingStartedProgress(
      songCount: songCount,
      lyricSongCount: lyricSongCount,
      lyricSong: lyricSong,
      playedWithLyrics: true,
    );
  }

  GettingStartedStepState stateOf(MobileGettingStartedStep step) {
    switch (step) {
      case MobileGettingStartedStep.addSongs:
        return songCount > 0
            ? GettingStartedStepState.done
            : GettingStartedStepState.ready;
      case MobileGettingStartedStep.addLyrics:
        if (lyricSongCount > 0) return GettingStartedStepState.done;
        return songCount > 0
            ? GettingStartedStepState.ready
            : GettingStartedStepState.locked;
      case MobileGettingStartedStep.playWithLyrics:
        if (playedWithLyrics) return GettingStartedStepState.done;
        return lyricSong != null
            ? GettingStartedStepState.ready
            : GettingStartedStepState.locked;
    }
  }

  int get doneCount => MobileGettingStartedStep.values
      .where((step) => stateOf(step) == GettingStartedStepState.done)
      .length;

  bool get allDone => doneCount == MobileGettingStartedStep.values.length;
}
