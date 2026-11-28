import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/onboarding/getting_started.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/mobile_getting_started.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

PlaybackItem _item({bool lyrics = true}) => PlaybackItem(
  id: 'local:/m/a.mp3',
  title: '晴天',
  hasLyrics: lyrics,
  audioAsset: const AudioAsset(originalPath: '/m/a.mp3', format: 'mp3'),
);

void main() {
  test('an empty phone can only add songs (D-071)', () {
    const progress = MobileGettingStartedProgress(
      songCount: 0,
      lyricSongCount: 0,
    );

    expect(
      progress.stateOf(MobileGettingStartedStep.addSongs),
      GettingStartedStepState.ready,
    );
    expect(
      progress.stateOf(MobileGettingStartedStep.addLyrics),
      GettingStartedStepState.locked,
    );
    expect(
      progress.stateOf(MobileGettingStartedStep.playWithLyrics),
      GettingStartedStepState.locked,
    );
    expect(progress.doneCount, 0);
  });

  test('songs finish the first step and open the second', () {
    const progress = MobileGettingStartedProgress(
      songCount: 3,
      lyricSongCount: 0,
    );

    expect(
      progress.stateOf(MobileGettingStartedStep.addSongs),
      GettingStartedStepState.done,
    );
    expect(
      progress.stateOf(MobileGettingStartedStep.addLyrics),
      GettingStartedStepState.ready,
    );
    expect(
      progress.stateOf(MobileGettingStartedStep.playWithLyrics),
      GettingStartedStepState.locked,
    );
  });

  test('a song with lyrics opens the last step', () {
    final progress = MobileGettingStartedProgress(
      songCount: 3,
      lyricSongCount: 1,
      lyricSong: _item(),
    );

    expect(progress.doneCount, 2);
    expect(
      progress.stateOf(MobileGettingStartedStep.playWithLyrics),
      GettingStartedStepState.ready,
    );
  });

  test('playing a song with lyrics finishes it before the history does', () {
    final progress = MobileGettingStartedProgress(
      songCount: 3,
      lyricSongCount: 1,
      lyricSong: _item(),
    );

    expect(progress.whilePlaying(_item(lyrics: false)).allDone, isFalse);
    expect(progress.whilePlaying(null).allDone, isFalse);
    expect(progress.whilePlaying(_item()).allDone, isTrue);
  });

  test('a recent play with lyrics counts as done', () {
    final progress = MobileGettingStartedProgress(
      songCount: 1,
      lyricSongCount: 1,
      lyricSong: _item(),
      playedWithLyrics: true,
    );

    expect(progress.allDone, isTrue);
  });
}
