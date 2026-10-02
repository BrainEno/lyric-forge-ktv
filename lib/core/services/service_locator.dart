import '../../features/player/data/repositories/memory_play_history_repository.dart';
import '../../features/player/data/services/just_audio_player_service.dart';
import '../../features/player/domain/repositories/play_history_repository.dart';
import '../../features/player/domain/services/audio_player_service.dart';
import '../../features/project/data/repositories/memory_project_repository.dart';
import '../../features/project/domain/repositories/project_repository.dart';
import '../../features/transfer/data/services/http_media_hub_service.dart';
import '../../features/transfer/domain/services/media_hub_service.dart';

/// Simple service locator for dependency injection.
/// Replaced with proper DI (e.g., get_it, injectable) as project grows.
class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  ServiceLocator._internal();

  late final ProjectRepository projectRepository;
  late final AudioPlayerService audioPlayerService;
  late final PlayHistoryRepository playHistoryRepository;
  late final MediaHubService mediaHubService;

  void initialize() {
    projectRepository = MemoryProjectRepository();
    audioPlayerService = JustAudioPlayerService();
    playHistoryRepository = MemoryPlayHistoryRepository();
    mediaHubService = HttpMediaHubService();
  }
}

/// Global accessor for services.
/// Usage: `ServiceLocator.I.projectRepository`
extension ServiceLocatorGlobal on ServiceLocator {
  static ServiceLocator get I => ServiceLocator();
}
