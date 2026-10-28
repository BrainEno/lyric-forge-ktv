import '../models/playback_session_snapshot.dart';

abstract class PlaybackSessionStore {
  Future<PlaybackSessionSnapshot?> load();

  Future<void> save(PlaybackSessionSnapshot snapshot);

  Future<void> clear();
}
