import '../models/project_manifest.dart';

/// Selects and attaches an existing accompaniment to an unchanged project.
abstract class ProjectAccompanimentImporter {
  /// Returns null when the user cancels. Throws on copy or save failure.
  Future<ProjectManifest?> importFor(ProjectManifest project);
}
