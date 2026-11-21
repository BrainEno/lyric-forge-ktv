import 'lyric_document.dart';
import 'project_manifest.dart';

/// Whether a lyric document can drive a timed display (highlight, auto-scroll,
/// KTV) or is reference text only.
///
/// Decision D-054: lyrics found online or pasted as plain text often have no
/// usable timing. They are still worth keeping — the player shows them as
/// static text the listener scrolls by hand — but nothing that follows the
/// playback position may treat their zero times as "every line starts at
/// 0:00".
///
/// A document is untimed when no line carries a time at all. The
/// `metadata['timed']` flag written at import is deliberately not consulted:
/// it is set once when a plain-text file is imported and stays `false` after
/// the user taps timing in the editor, so trusting it would hide lyrics the
/// user has since timed.
extension LyricDocumentTiming on LyricDocument {
  /// No line has a start, an end or a word time.
  bool get isUntimed => lines.isNotEmpty && lines.every(_lineIsUntimed);

  /// At least one line is timed, so position-following views work.
  bool get isTimed => lines.isNotEmpty && !isUntimed;

  /// Number of lines that carry a timestamp.
  int get timedLineCount =>
      lines.where((line) => !_lineIsUntimed(line)).length;

  /// The same words as reference text: every time, word timing and the
  /// global offset removed, `metadata['timed']` set to false.
  ///
  /// Used when fetched lyrics turn out to be timed for another version of the
  /// song: the words are right, the timestamps are not, and a wrong
  /// highlight is worse than none.
  LyricDocument withoutTimestamps() {
    return LyricDocument(
      language: language,
      lines: [
        for (final line in lines)
          LyricLine(
            text: line.text,
            startTime: Duration.zero,
            endTime: Duration.zero,
            isChorus: line.isChorus,
            confidence: line.confidence,
            confidenceSource: line.confidenceSource,
            id: line.id,
          ),
      ],
      metadata: {...metadata, 'timed': false, 'timestampsRemoved': true},
    );
  }

  /// The line playing at [position], counting [globalOffset] and an
  /// [extraOffset] (a nudge the user is previewing); null when the document
  /// is untimed or empty.
  int? activeLineIndex(Duration position, {Duration extraOffset = Duration.zero}) {
    if (lines.isEmpty || isUntimed) return null;
    for (var index = lines.length - 1; index >= 0; index--) {
      if (position >= effectiveStart(lines[index], extraOffset: extraOffset)) {
        return index;
      }
    }
    return 0;
  }

  /// Where playback has to go to hear [line], never before 0:00.
  Duration effectiveStart(
    LyricLine line, {
    Duration extraOffset = Duration.zero,
  }) {
    final shifted =
        line.startTime + (globalOffset ?? Duration.zero) + extraOffset;
    return shifted.isNegative ? Duration.zero : shifted;
  }

  /// When the last timed line starts, after the global offset; null when the
  /// document is untimed.
  Duration? get lastTimedStart {
    if (isUntimed) return null;
    Duration? latest;
    for (final line in lines) {
      if (_lineIsUntimed(line)) continue;
      final start = effectiveStart(line);
      if (latest == null || start > latest) latest = start;
    }
    return latest;
  }
}

/// Lyric timing questions asked about a whole project.
extension ProjectLyricTiming on ProjectManifest {
  /// Lyrics that can be highlighted, followed and sung to in KTV.
  bool get hasTimedLyrics => hasLyrics && lyricDocument!.isTimed;

  /// Reference lyrics only: shown as static text, not followed.
  bool get hasUntimedLyrics => hasLyrics && lyricDocument!.isUntimed;
}

bool _lineIsUntimed(LyricLine line) =>
    line.startTime == Duration.zero &&
    line.endTime == Duration.zero &&
    line.words.isEmpty;
