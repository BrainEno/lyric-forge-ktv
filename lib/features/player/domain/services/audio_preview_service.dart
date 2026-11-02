import '../models/audio_preview_state.dart';

/// Plays one loose audio file on demand — a KTV take, an exported mix — without
/// touching the queue that [AudioPlayerService] is bound to.
///
/// Why this exists next to [AudioPlayerService] instead of inside it: the app
/// player is always describing "the current queue item". Loading a recording
/// into that player would leave the player bar, the lyric editor and the queue
/// pointing at a song that is no longer the audio being heard, and every
/// `seek` in the app would seek inside the recording. An audition therefore
/// gets its own channel, and the two are kept from sounding at once by
/// [ExclusiveAudioPreviewService].
///
/// Presentation code depends on this interface, never on `just_audio`.
abstract class AudioPreviewService {
  Stream<AudioPreviewState> get stateStream;
  AudioPreviewState get currentState;

  /// Loads a local file and returns its duration when the decoder reports one.
  ///
  /// Throws when the file cannot be decoded, so callers can show the reason.
  Future<Duration?> loadFile(String path);

  /// Starts (or resumes) playback. Completes as soon as playback has started —
  /// it does not wait for the file to finish.
  Future<void> play();

  Future<void> pause();

  /// Pauses and rewinds to the start, keeping the loaded file.
  Future<void> stop();

  Future<void> seek(Duration position);

  Future<void> dispose();
}
