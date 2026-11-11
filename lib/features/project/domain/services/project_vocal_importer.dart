import '../models/project_manifest.dart';

/// Selects and attaches an existing vocal stem to an unchanged project.
abstract class ProjectVocalImporter {
  /// Returns null when the user cancels. Throws on copy or save failure.
  Future<ProjectManifest?> importVocalFor(ProjectManifest project);
}
