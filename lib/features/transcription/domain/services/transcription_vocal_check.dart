import '../../../project/domain/models/lyric_document.dart';
import 'vocal_activity_lyric_gate.dart';

/// Checks a fresh draft against the vocal stem it was recognised from
/// (D-044): deletes rows nobody sings, pulls row boundaries onto the singing
/// and records singing no row covers.
abstract interface class TranscriptionVocalCheck {
  /// [audioPaths] are tried in order; the first readable one is used.
  ///
  /// Never throws: whatever goes wrong leaves [draft] unchanged, with a
  /// report saying why.
  Future<VocalCheckResult> check(
    LyricDocument draft, {
    required List<String> audioPaths,
  });
}
