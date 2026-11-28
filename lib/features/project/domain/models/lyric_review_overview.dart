import 'project_manifest.dart';

/// What the lyric editor's 建议复核 list holds for a project, as plain counts
/// (D-069).
///
/// The project page used to show two numbers written into the draft when it
/// was recognised — 低置信度 and 重点复核 — which never changed as the user
/// confirmed lines and used different words from the editor. The editor's
/// queue lives in the lyrics feature, which already depends on this one, so
/// the app supplies a [ProjectLyricReviewCounter] that builds it instead of
/// this feature importing it.
class ProjectLyricReviewOverview {
  /// Rows the editor lists under 建议复核.
  final int suggested;

  /// Of [suggested], the rows with strong evidence (必看).
  final int mustCheck;

  /// Rows a person has confirmed.
  final int reviewed;

  const ProjectLyricReviewOverview({
    required this.suggested,
    required this.mustCheck,
    required this.reviewed,
  });
}

/// Builds the [ProjectLyricReviewOverview] of a project with lyrics.
typedef ProjectLyricReviewCounter =
    ProjectLyricReviewOverview Function(ProjectManifest project);
