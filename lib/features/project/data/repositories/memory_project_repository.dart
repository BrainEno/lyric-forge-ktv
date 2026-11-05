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
  Future<ProjectManifest> updateProject(ProjectManifest project) =>
      _writeProject(project);

  @override
  Future<ProjectManifest> updateProjectIfUnchanged(
    ProjectManifest project, {
    required int expectedRevision,
  }) => _writeProject(project, expectedRevision: expectedRevision);

  Future<ProjectManifest> _writeProject(
    ProjectManifest project, {
    int? expectedRevision,
  }) async {
    final current = _projects[project.id];
    if (current == null) {
      if (expectedRevision != null) {
        throw const ProjectUpdateConflictException(currentProject: null);
      }
      throw ProjectRepositoryException('Project not found: ${project.id}');
    }
    if (expectedRevision != null && current.revision != expectedRevision) {
      throw ProjectUpdateConflictException(currentProject: current);
    }
    final updated = project.copyWith(
      updatedAt: DateTime.now(),
      revision: current.revision + 1,
    );
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
