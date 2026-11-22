import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lyric_forge_ktv/features/player/data/services/just_audio_player_service.dart';

/// D-059: what the app calls "playing", and when `play()` returns.
void main() {
  group('reportsPlaying', () {
    test('a song that plays is playing', () {
      expect(
        JustAudioPlayerService.reportsPlaying(
          playing: true,
          processingState: ProcessingState.ready,
        ),
        isTrue,
      );
    });

    test('a paused song is not', () {
      expect(
        JustAudioPlayerService.reportsPlaying(
          playing: false,
          processingState: ProcessingState.ready,
        ),
        isFalse,
      );
    });

    test('a finished queue is not, although just_audio keeps playing true', () {
      expect(
        JustAudioPlayerService.reportsPlaying(
          playing: true,
          processingState: ProcessingState.completed,
        ),
        isFalse,
      );
    });

    test('a song still loading or buffering counts as playing', () {
      for (final state in [ProcessingState.loading, ProcessingState.buffering]) {
        expect(
          JustAudioPlayerService.reportsPlaying(
            playing: true,
            processingState: state,
          ),
          isTrue,
          reason: '$state',
        );
      }
    });
  });

  group('untilStarted', () {
    test('returns once the player plays, without waiting for a pause', () async {
      final states = StreamController<PlayerState>.broadcast();
      // just_audio's play() future: done only when playback stops.
      final playback = Completer<void>();
      var returned = false;
      final started = JustAudioPlayerService.untilStarted(
        playback.future,
        states.stream,
      ).then((_) => returned = true);

      states.add(PlayerState(true, ProcessingState.loading));
      await pumpEventQueue();
      expect(returned, isFalse, reason: 'still loading');

      states.add(PlayerState(true, ProcessingState.ready));
      await started;
      expect(returned, isTrue);
      expect(playback.isCompleted, isFalse);
      await states.close();
    });

    test('a start failure reaches the caller', () async {
      final states = StreamController<PlayerState>.broadcast();
      final playback = Completer<void>();
      final started = JustAudioPlayerService.untilStarted(
        playback.future,
        states.stream,
      );
      playback.completeError(StateError('cannot decode'));
      await expectLater(started, throwsStateError);
      await states.close();
    });

    test('a pause before the song was ready also returns', () async {
      final states = StreamController<PlayerState>.broadcast();
      final playback = Completer<void>();
      final started = JustAudioPlayerService.untilStarted(
        playback.future,
        states.stream,
      );
      playback.complete();
      await expectLater(started, completes);
      await states.close();
    });

    test('an error after the start is not thrown at anyone', () async {
      final states = StreamController<PlayerState>.broadcast();
      final playback = Completer<void>();
      final started = JustAudioPlayerService.untilStarted(
        playback.future,
        states.stream,
      );
      states.add(PlayerState(true, ProcessingState.ready));
      await started;
      playback.completeError(StateError('later'));
      await pumpEventQueue();
      await states.close();
    });
  });
}
