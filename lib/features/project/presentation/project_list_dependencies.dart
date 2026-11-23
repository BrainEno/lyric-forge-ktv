import '../domain/repositories/project_repository.dart';
import '../domain/services/project_deletion_service.dart';

/// Services the 全部工程 page uses (D-063).
class ProjectListDependencies {
  const ProjectListDependencies({
    required this.projectRepository,
    required this.deletionService,
    this.canonicalizeAudioPath = _identity,
  });

  final ProjectRepository projectRepository;
  final ProjectDeletionService deletionService;

  /// Makes two spellings of one audio path equal, for duplicate detection.
  final String Function(String path) canonicalizeAudioPath;

  static String _identity(String path) => path;
}
