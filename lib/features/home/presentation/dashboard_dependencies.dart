import '../../player/domain/repositories/play_history_repository.dart';
import '../../player/domain/services/audio_player_service.dart';
import '../../player/domain/services/playback_session_service.dart';
import '../../project/domain/repositories/project_repository.dart';
import '../../transcription/domain/services/batch_transcription_queue.dart';
import '../../transcription/domain/services/transcription_settings_store.dart';

/// Collaborators used by the dashboard's recent activity and playback actions.
class DashboardDependencies {
  final ProjectRepository projectRepository;
  final PlayHistoryRepository playHistoryRepository;
  final PlaybackSessionService playbackSession;
  final AudioPlayerService audioPlayer;
  final BatchTranscriptionQueue transcriptionQueue;
  final TranscriptionSettingsStore transcriptionSettingsStore;

  const DashboardDependencies({
    required this.projectRepository,
    required this.playHistoryRepository,
    required this.playbackSession,
    required this.audioPlayer,
    required this.transcriptionQueue,
    required this.transcriptionSettingsStore,
  });
}
