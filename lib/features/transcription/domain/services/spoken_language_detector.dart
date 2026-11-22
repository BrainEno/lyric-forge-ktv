import '../models/spoken_language.dart';
import '../models/transcription_models.dart';

/// Finds the language a song is sung in before it is recognised (D-061).
abstract interface class SpokenLanguageDetector {
  /// The language to recognise [request] in. Never fails the run over a
  /// probe problem: that becomes an unresolved result carrying the error.
  ///
  /// Throws a cancelled `TranscriptionException` after [cancel].
  Future<SpokenLanguageResolution> detect(TranscriptionRequest request);

  /// Stops a running probe.
  Future<void> cancel();
}
