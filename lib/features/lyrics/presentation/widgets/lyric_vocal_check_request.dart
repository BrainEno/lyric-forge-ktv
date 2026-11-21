import '../../domain/models/vocal_check_record.dart';

/// A one-click follow-up of the vocal check (D-045), as the recognition
/// summary card asks for it.
sealed class LyricVocalCheckRequest {
  const LyricVocalCheckRequest();
}

/// Recognise a stretch of singing that has no row; [span] null starts at
/// the first one.
final class LyricVocalGapRequest extends LyricVocalCheckRequest {
  const LyricVocalGapRequest([this.span]);

  final LyricVocalCheckSpan? span;
}

/// Put rows the vocal check removed back: all at once, or after choosing
/// them in a dialog.
final class LyricRestoreRemovedRequest extends LyricVocalCheckRequest {
  const LyricRestoreRemovedRequest({this.all = false});

  final bool all;
}
