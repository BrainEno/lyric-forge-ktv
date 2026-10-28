import '../models/media_hub_session.dart';
import '../models/shared_audio_track.dart';

abstract class MediaHubService {
  Future<MediaHubSession> startSharing(List<SharedAudioTrack> tracks);

  Future<void> stopSharing();

  Stream<MediaHubState> get stateStream;

  MediaHubState get currentState;

  MediaHubSession? get currentSession;

  bool get isRunning;
}
