import '../models/project_manifest.dart';

/// Repository contract for project persistence.
/// Abstracts storage implementation (memory, local file, or database).
abstract class ProjectRepository {
  /// Get all projects, sorted by updatedAt descending.
  Future<List<ProjectManifest>> getAllProjects();

  /// Get a single project by ID.
  Future<ProjectManifest?> getProjectById(String id);

  /// Create a new project.
  Future<ProjectManifest> createProject({
    required String name,
    String? artist,
    String? album,
  });

  /// Update an existing project.
  Future<ProjectManifest> updateProject(ProjectManifest project);

  /// Delete a project by ID.
  Future<void> deleteProject(String id);

  /// Get recently updated projects (for dashboard).
  Future<List<ProjectManifest>> getRecentProjects({int limit = 10});
}

/// Exception thrown when project operations fail.
class ProjectRepositoryException implements Exception {
  final String message;
  final Exception? cause;

  const ProjectRepositoryException(this.message, {this.cause});

  @override
  String toString() => 'ProjectRepositoryException: $message';
}
