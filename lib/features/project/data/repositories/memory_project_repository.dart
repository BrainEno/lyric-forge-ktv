import '../../domain/models/project_manifest.dart';
import '../../domain/repositories/project_repository.dart';

/// In-memory implementation of ProjectRepository.
/// Used for MVP before introducing persistent storage (Drift/Hive).
/// All data is lost on app restart.
class MemoryProjectRepository implements ProjectRepository {
  final Map<String, ProjectManifest> _projects = {};

  @override
  Future<List<ProjectManifest>> getAllProjects() async {
    final projects = _projects.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  @override
  Future<ProjectManifest?> getProjectById(String id) async {
    return _projects[id];
  }

  @override
  Future<ProjectManifest> createProject({
    required String name,
    String? artist,
    String? album,
  }) async {
    final now = DateTime.now();
    final project = ProjectManifest(
      id: _generateId(),
      name: name,
      artist: artist,
      album: album,
      createdAt: now,
      updatedAt: now,
    );
    _projects[project.id] = project;
    return project;
  }

  @override
  Future<ProjectManifest> updateProject(ProjectManifest project) async {
    if (!_projects.containsKey(project.id)) {
      throw ProjectRepositoryException(
        'Project not found: ${project.id}',
      );
    }
    final updated = project.copyWith(updatedAt: DateTime.now());
    _projects[project.id] = updated;
    return updated;
  }

  @override
  Future<void> deleteProject(String id) async {
    _projects.remove(id);
  }

  @override
  Future<List<ProjectManifest>> getRecentProjects({int limit = 10}) async {
    final projects = await getAllProjects();
    return projects.take(limit).toList();
  }

  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
}
