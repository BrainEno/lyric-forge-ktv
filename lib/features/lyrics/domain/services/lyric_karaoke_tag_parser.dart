import '../../../project/domain/models/lyric_document.dart';
import 'lyric_word_timing_service.dart';

/// One timed piece of karaoke-tagged text: [text] is sung from [start]. An
/// explicit [end] comes from formats that give durations (ASS `\k`);
/// otherwise the piece lasts until the next one starts.
typedef LyricKaraokePiece = ({Duration start, Duration? end, String text});

/// A row of karaoke-tagged lyrics with the tags taken out.
class LyricKaraokeTags {
  const LyricKaraokeTags({
    required this.text,
    this.pieces = const [],
    this.end,
  });

  /// The row text without any tags.
  final String text;

  /// The timed pieces in order; empty when the row had no word tags.
  final List<LyricKaraokePiece> pieces;

  /// A closing stamp after the last piece (word-timed LRC writes the row's
  /// end this way), or null.
  final Duration? end;

  /// The same tags moved by [delta], for an LRC row listed under several
  /// line timestamps.
  LyricKaraokeTags shifted(Duration delta) {
    if (delta == Duration.zero) return this;
    return LyricKaraokeTags(
      text: text,
      pieces: [
        for (final piece in pieces)
          (
            start: piece.start + delta,
            end: piece.end == null ? null : piece.end! + delta,
            text: piece.text,
          ),
      ],
      end: end == null ? null : end! + delta,
    );
  }
}

/// Reads the word timing that karaoke lyric files carry inline, so an
/// imported karaoke file keeps its timing instead of losing it to the
/// estimate (D-023):
///
/// * **LRC**: enhanced `<mm:ss.xx>` stamps (`[00:12.00]<00:12.00>你<00:12.40>好`)
///   and the inline square-bracket variant (`[00:12.00]你[00:12.40]好`). A
///   stamp with nothing after it closes the row.
/// * **ASS**: `\k`, `\K`, `\kf` and `\ko` durations in centiseconds, counted
///   from the event start. An untexted leading `\k` is the lead-in before the
///   row is sung.
/// * **WebVTT**: inline `<hh:mm:ss.mmm>` cue timestamps; the text before the
///   first one starts with the cue.
///
/// Each piece with sung text becomes one [LyricWordTiming]; punctuation
/// joins the word before it and spaces are dropped. Pieces whose starts go
/// backwards make the whole row untimed rather than wrongly timed.
class LyricKaraokeTagParser {
  const LyricKaraokeTagParser({
    this.wordTiming = const LyricWordTimingService(),
  });

  final LyricWordTimingService wordTiming;

  static final RegExp _lrcStamp = RegExp(
    r'<(\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?)>|\[(\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?)\]',
  );
  static final RegExp _assBlock = RegExp(r'\{([^}]*)\}');
  static final RegExp _assKaraoke = RegExp(r'\\(?:kf|ko|k|K)(\d+(?:\.\d+)?)');
  static final RegExp _vttStamp = RegExp(
    r'<((?:\d+:)?\d{1,2}:\d{2}(?:\.\d{1,3})?)>',
  );
  static final RegExp _vttTag = RegExp(r'<[^>]+>');

  /// The text of an LRC row after its leading line stamps.
  LyricKaraokeTags lrc(String body, Duration rowStart) {
    final matches = _lrcStamp.allMatches(body).toList(growable: false);
    if (matches.isEmpty) return LyricKaraokeTags(text: body.trim());
    final pieces = <LyricKaraokePiece>[];
    final text = StringBuffer();
    final lead = body.substring(0, matches.first.start);
    if (lead.trim().isNotEmpty) {
      pieces.add((start: rowStart, end: null, text: lead));
    }
    text.write(lead);
    Duration? closing;
    for (var index = 0; index < matches.length; index++) {
      final match = matches[index];
      final stamp = lrcStamp(match.group(1) ?? match.group(2)!);
      final until = index + 1 < matches.length
          ? matches[index + 1].start
          : body.length;
      final piece = body.substring(match.end, until);
      text.write(piece);
      if (stamp == null) continue;
      if (index == matches.length - 1 && piece.trim().isEmpty) {
        closing = stamp;
      } else {
        pieces.add((start: stamp, end: null, text: piece));
      }
    }
    return LyricKaraokeTags(
      text: text.toString().trim(),
      pieces: List.unmodifiable(pieces),
      end: closing,
    );
  }

  /// The `Text` field of an ASS `Dialogue` event starting at [rowStart].
  LyricKaraokeTags ass(String field, Duration rowStart) {
    final pieces = <({Duration start, Duration end, StringBuffer text})>[];
    final text = StringBuffer();
    final prefix = StringBuffer();
    var cursor = rowStart;
    var position = 0;

    void addText(String raw) {
      if (raw.isEmpty) return;
      final value = raw
          .replaceAll(r'\N', '\n')
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\h', ' ');
      text.write(value);
      if (pieces.isEmpty) {
        prefix.write(value);
      } else {
        pieces.last.text.write(value);
      }
    }

    for (final block in _assBlock.allMatches(field)) {
      addText(field.substring(position, block.start));
      position = block.end;
      for (final tag in _assKaraoke.allMatches(block.group(1)!)) {
        final centiseconds = double.parse(tag.group(1)!);
        final length = Duration(milliseconds: (centiseconds * 10).round());
        pieces.add((start: cursor, end: cursor + length, text: StringBuffer()));
        cursor += length;
      }
    }
    addText(field.substring(position));
    if (pieces.isNotEmpty && prefix.isNotEmpty) {
      final first = pieces.first;
      pieces[0] = (
        start: first.start,
        end: first.end,
        text: StringBuffer('$prefix${first.text}'),
      );
    }
    return LyricKaraokeTags(
      text: text.toString().trim(),
      pieces: List.unmodifiable([
        for (final piece in pieces)
          (start: piece.start, end: piece.end, text: piece.text.toString()),
      ]),
    );
  }

  /// The text of a WebVTT cue starting at [cueStart], markup included.
  LyricKaraokeTags vtt(String cue, Duration cueStart) {
    final matches = _vttStamp.allMatches(cue).toList(growable: false);
    if (matches.isEmpty) return LyricKaraokeTags(text: _vttText(cue).trim());
    final pieces = <LyricKaraokePiece>[];
    final text = StringBuffer();
    final lead = _vttText(cue.substring(0, matches.first.start));
    text.write(lead);
    if (lead.trim().isNotEmpty) {
      pieces.add((start: cueStart, end: null, text: lead));
    }
    for (var index = 0; index < matches.length; index++) {
      final match = matches[index];
      final until = index + 1 < matches.length
          ? matches[index + 1].start
          : cue.length;
      final piece = _vttText(cue.substring(match.end, until));
      text.write(piece);
      final stamp = clockStamp(match.group(1)!);
      if (stamp == null) continue;
      pieces.add((start: stamp, end: null, text: piece));
    }
    return LyricKaraokeTags(
      text: text.toString().trim(),
      pieces: List.unmodifiable(pieces),
    );
  }

  /// WebVTT cue text with markup removed and entities decoded; `&amp;` last
  /// so `&amp;lt;` stays the literal text `&lt;`.
  static String _vttText(String value) => value
      .replaceAll(_vttTag, '')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&');

  /// Word timing from [tags] for a row ending at [rowEnd]; empty when the
  /// tags time nothing sung or go backwards.
  List<LyricWordTiming> words(
    LyricKaraokeTags tags, {
    required Duration rowEnd,
  }) {
    final pieces = tags.pieces;
    if (pieces.isEmpty) return const [];
    final words = <({StringBuffer text, Duration start, Duration end})>[];
    var prefix = '';
    for (var index = 0; index < pieces.length; index++) {
      final piece = pieces[index];
      final next = index + 1 < pieces.length
          ? pieces[index + 1].start
          : (tags.end ?? rowEnd);
      var end = piece.end ?? next;
      if (end < piece.start) end = piece.start;
      final trimmed = piece.text.trim();
      if (trimmed.isEmpty) continue;
      if (wordTiming.sungCount(trimmed) == 0) {
        if (words.isEmpty) {
          prefix += trimmed;
        } else {
          words.last.text.write(trimmed);
        }
        continue;
      }
      if (words.isNotEmpty && piece.start < words.last.start) return const [];
      words.add((
        text: StringBuffer('$prefix$trimmed'),
        start: piece.start,
        end: end,
      ));
      prefix = '';
    }
    if (words.isEmpty) return const [];
    return List.unmodifiable([
      for (final word in words)
        LyricWordTiming(
          text: word.text.toString(),
          start: word.start,
          end: word.end,
        ),
    ]);
  }

  /// When the first sung piece starts, or null.
  Duration? firstSungStart(LyricKaraokeTags tags) {
    for (final piece in tags.pieces) {
      if (wordTiming.sungCount(piece.text) > 0) return piece.start;
    }
    return null;
  }

  /// `mm:ss`, `mm:ss.x`, `mm:ss.xx`, `mm:ss.xxx` or `mm:ss:xx`, as LRC
  /// writes it; null when malformed.
  static Duration? lrcStamp(String value) {
    final match = RegExp(
      r'^(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?$',
    ).firstMatch(value.trim());
    if (match == null) return null;
    final seconds = int.parse(match.group(2)!);
    if (seconds >= 60) return null;
    return Duration(
      minutes: int.parse(match.group(1)!),
      seconds: seconds,
      milliseconds: _fraction(match.group(3) ?? ''),
    );
  }

  /// `hh:mm:ss.mmm` or `mm:ss.mmm`, as WebVTT writes it; null when
  /// malformed.
  static Duration? clockStamp(String value) {
    final match = RegExp(
      r'^(?:(\d+):)?(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?$',
    ).firstMatch(value.trim());
    if (match == null) return null;
    final minutes = int.parse(match.group(2)!);
    final seconds = int.parse(match.group(3)!);
    if (seconds >= 60 || (match.group(1) != null && minutes >= 60)) {
      return null;
    }
    return Duration(
      hours: int.parse(match.group(1) ?? '0'),
      minutes: minutes,
      seconds: seconds,
      milliseconds: _fraction(match.group(4) ?? ''),
    );
  }

  static int _fraction(String digits) => switch (digits.length) {
    0 => 0,
    1 => int.parse(digits) * 100,
    2 => int.parse(digits) * 10,
    _ => int.parse(digits.substring(0, 3)),
  };
}
