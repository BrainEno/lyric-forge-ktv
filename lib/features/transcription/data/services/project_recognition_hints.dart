import '../../../project/domain/models/project_manifest.dart';
import '../../domain/models/transcription_models.dart';

/// Project metadata the recognisers may use as decoding hints: the title,
/// artist and album shown on the project card, plus proper nouns the user
/// stored under `recognitionTerms`. Never lyric text, and never the reference
/// lyrics a proofreading step compares against.
RecognitionHints recognitionHintsForProject(ProjectManifest project) {
  final rawTerms = project.metadata['recognitionTerms'];
  return RecognitionHints(
    songTitle: project.name,
    artist: project.artist ?? '',
    album: project.album ?? '',
    terms: rawTerms is List
        ? [
            for (final term in rawTerms)
              if (term is String && term.trim().isNotEmpty) term.trim(),
          ]
        : const <String>[],
  );
}
