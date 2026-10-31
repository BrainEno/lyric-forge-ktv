import '../models/shared_audio_track.dart';

/// Builds the track list that desktop Media Hub sharing can expose.
abstract class MediaShareCatalog {
  Future<List<SharedAudioTrack>> build();
}
