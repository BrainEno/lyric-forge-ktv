import '../../../project/domain/models/lyric_document.dart';
import 'lyric_karaoke_timing_service.dart';

/// File formats the editor can export.
enum LyricExportFormat {
  /// Synchronised lyrics for music players and KTV software.
  lrc,

  /// Word-timed LRC (the "enhanced" `<mm:ss.mmm>` extension): every sung
  /// unit carries its own estimated time, for players that highlight
  /// syllable by syllable.
  karaokeLrc,

  /// Advanced SubStation Alpha subtitles with `\kf` karaoke sweeps, for
  /// karaoke video tools (Aegisub, video editors, libass players).
  ass,

  /// SubRip subtitles, for video editors and karaoke video tools.
  srt,

  /// WebVTT subtitles, for browsers and web players.
  vtt,

  /// Plain lyric text without timestamps, for sharing or reference.
  plainText;

  String get extension => switch (this) {
    LyricExportFormat.lrc => 'lrc',
    LyricExportFormat.karaokeLrc => 'lrc',
    LyricExportFormat.ass => 'ass',
    LyricExportFormat.srt => 'srt',
    LyricExportFormat.vtt => 'vtt',
    LyricExportFormat.plainText => 'txt',
  };

  String get label => switch (this) {
    LyricExportFormat.lrc => 'LRC 同步歌词',
    LyricExportFormat.karaokeLrc => '逐字 LRC',
    LyricExportFormat.ass => 'ASS 卡拉 OK 字幕',
    LyricExportFormat.srt => 'SRT 字幕',
    LyricExportFormat.vtt => 'WebVTT 字幕',
    LyricExportFormat.plainText => '纯文本歌词',
  };

  String get description => switch (this) {
    LyricExportFormat.lrc => '音乐播放器、KTV 软件通用；只记录每行开始时间',
    LyricExportFormat.karaokeLrc => '支持逐字高亮的播放器使用；字的时间按字数在行内估算',
    LyricExportFormat.ass => '卡拉 OK 视频制作用；逐字填色扫过，字的时间按字数在行内估算',
    LyricExportFormat.srt => '视频剪辑、卡拉 OK 视频制作常用；带开始和结束时间',
    LyricExportFormat.vtt => '网页播放器使用；带开始和结束时间',
    LyricExportFormat.plainText => '不带时间，按间奏自动分段，便于分享或核对',
  };

  /// Whether the format carries timestamps.
  bool get timed => this != LyricExportFormat.plainText;

  /// Whether the format times every syllable. Those times are estimated
  /// inside each row, so the dialog says so.
  bool get syllableTimed =>
      this == LyricExportFormat.karaokeLrc || this == LyricExportFormat.ass;
}

/// Options that change how an export is written.
class LyricExportOptions {
  /// LRC only: after a row followed by a pause of at least [pauseThreshold]
  /// (and after the last row), write an empty timestamped line at the row's
  /// end so players clear the lyric during interludes instead of showing it
  /// until the next verse.
  final bool lrcEndMarkers;

  /// Plain text only: start a new paragraph at pauses of at least
  /// [paragraphGap].
  final bool paragraphsAtPauses;

  /// A gap this long counts as a pause for [lrcEndMarkers].
  final Duration pauseThreshold;

  /// A gap this long starts a new paragraph for [paragraphsAtPauses].
  final Duration paragraphGap;

  /// ASS only: show each row up to this long before it is sung (never
  /// before the previous row has finished), so the singer can read ahead.
  /// The lead-in is an unhighlighted `\k` at the start of the row.
  final Duration assLeadIn;

  const LyricExportOptions({
    this.lrcEndMarkers = false,
    this.paragraphsAtPauses = true,
    this.pauseThreshold = const Duration(milliseconds: 1500),
    this.paragraphGap = const Duration(seconds: 4),
    this.assLeadIn = const Duration(seconds: 1),
  });
}

/// Song metadata written into formats that carry it.
class LyricExportMetadata {
  final String? title;
  final String? artist;
  final String? album;

  const LyricExportMetadata({this.title, this.artist, this.album});
}

/// One row as it is exported: effective times (global offset applied,
/// clamped to 0:00), single-line text.
class LyricExportCue {
  final Duration start;
  final Duration end;
  final String text;

  const LyricExportCue({
    required this.start,
    required this.end,
    required this.text,
  });
}

/// Encodes a [LyricDocument] into the export formats.
///
/// All formats share the same cue list ([cues]):
///
/// * empty rows are left out and line breaks inside a row become spaces;
/// * the document's global offset is applied, so the file plays in sync
///   even in players that ignore or reverse an `[offset:]` tag;
/// * negative times are clamped to 0:00;
/// * rows are ordered by start time.
///
/// Subtitle formats need an end for every cue. A row whose end is missing
/// (not after its start) gets [fallbackDuration], and an end that runs into
/// the next cue is cut at that cue's start, because most subtitle renderers
/// stack overlapping cues on top of each other.
class LyricExportEncoder {
  const LyricExportEncoder({this.karaoke = const LyricKaraokeTimingService()});

  final LyricKaraokeTimingService karaoke;

  /// Duration given to a cue whose row has no usable end.
  static const Duration fallbackDuration = Duration(seconds: 3);

  /// Shortest subtitle cue written.
  static const Duration minimumCue = Duration(milliseconds: 100);

  String encode(
    LyricDocument document,
    LyricExportFormat format, {
    LyricExportOptions options = const LyricExportOptions(),
    LyricExportMetadata metadata = const LyricExportMetadata(),
  }) {
    return switch (format) {
      LyricExportFormat.lrc => encodeLrc(
        document,
        metadata: metadata,
        endMarkers: options.lrcEndMarkers,
        pauseThreshold: options.pauseThreshold,
      ),
      LyricExportFormat.karaokeLrc => encodeKaraokeLrc(
        document,
        metadata: metadata,
      ),
      LyricExportFormat.ass => encodeAss(
        document,
        metadata: metadata,
        leadIn: options.assLeadIn,
      ),
      LyricExportFormat.srt => encodeSrt(document),
      LyricExportFormat.vtt => encodeVtt(document, metadata: metadata),
      LyricExportFormat.plainText => encodePlainText(
        document,
        paragraphsAtPauses: options.paragraphsAtPauses,
        paragraphGap: options.paragraphGap,
      ),
    };
  }

  /// The rows as exported, in time order.
  List<LyricExportCue> cues(LyricDocument document) {
    final offset = document.globalOffset ?? Duration.zero;
    final cues = <LyricExportCue>[];
    for (final line in document.lines) {
      final text = singleLine(line.text);
      if (text.isEmpty) continue;
      final start = _clamp(line.startTime + offset);
      final end = _clamp(line.endTime + offset);
      cues.add(LyricExportCue(start: start, end: end, text: text));
    }
    // A stable sort keeps rows that share a start in lyric order.
    final indexed = [for (var i = 0; i < cues.length; i++) (i, cues[i])];
    indexed.sort((a, b) {
      final byStart = a.$2.start.compareTo(b.$2.start);
      return byStart != 0 ? byStart : a.$1.compareTo(b.$1);
    });
    return [for (final entry in indexed) entry.$2];
  }

  /// Cues with an end that is after the start and does not run into the
  /// next cue, as subtitle formats need.
  List<LyricExportCue> subtitleCues(LyricDocument document) {
    final source = cues(document);
    final result = <LyricExportCue>[];
    for (var index = 0; index < source.length; index++) {
      final cue = source[index];
      var end = cue.end > cue.start ? cue.end : cue.start + fallbackDuration;
      if (index + 1 < source.length) {
        final nextStart = source[index + 1].start;
        if (nextStart > cue.start && end > nextStart) end = nextStart;
      }
      if (end - cue.start < minimumCue) end = cue.start + minimumCue;
      result.add(LyricExportCue(start: cue.start, end: end, text: cue.text));
    }
    return result;
  }

  String encodeLrc(
    LyricDocument document, {
    LyricExportMetadata metadata = const LyricExportMetadata(),
    bool endMarkers = false,
    Duration pauseThreshold = const Duration(milliseconds: 1500),
  }) {
    final buffer = StringBuffer();
    _writeLrcHeader(buffer, document, metadata);

    final list = cues(document);
    for (var index = 0; index < list.length; index++) {
      final cue = list[index];
      buffer.writeln('[${lrcTimestamp(cue.start)}]${cue.text}');
      if (!endMarkers || cue.end <= cue.start) continue;
      final nextStart = index + 1 < list.length ? list[index + 1].start : null;
      if (nextStart == null || nextStart - cue.end >= pauseThreshold) {
        buffer.writeln('[${lrcTimestamp(cue.end)}]');
      }
    }
    return buffer.toString();
  }

  /// Word-timed LRC: `[start]<t1>unit<t2>unit…<end>` per row.
  ///
  /// Each row keeps its plain `[mm:ss.mmm]` line timestamp, so players
  /// without word support still show the row in time; the inline `<…>`
  /// stamps are estimated by [LyricKaraokeTimingService]. The closing stamp
  /// is the row's end, which tells word-aware players when to finish the
  /// sweep.
  String encodeKaraokeLrc(
    LyricDocument document, {
    LyricExportMetadata metadata = const LyricExportMetadata(),
  }) {
    final buffer = StringBuffer();
    _writeLrcHeader(buffer, document, metadata);
    for (final cue in subtitleCues(document)) {
      buffer.write('[${lrcTimestamp(cue.start)}]');
      for (final syllable in karaoke.syllables(cue.text, cue.start, cue.end)) {
        buffer.write('<${lrcTimestamp(syllable.start)}>${syllable.text}');
      }
      buffer.writeln('<${lrcTimestamp(cue.end)}>');
    }
    return buffer.toString();
  }

  /// ASS subtitles with one `Dialogue` per row and a `\kf` sweep per unit.
  ///
  /// The style highlights in the KTV convention: white before a syllable is
  /// sung, blue after, with a dark outline so the text reads on any video.
  /// A row may appear up to [leadIn] early (but not before the previous
  /// row's end); the early part is an empty `\k` so nothing is highlighted
  /// before the singer starts.
  String encodeAss(
    LyricDocument document, {
    LyricExportMetadata metadata = const LyricExportMetadata(),
    Duration leadIn = const Duration(seconds: 1),
  }) {
    final title = [metadata.title, metadata.artist]
        .whereType<String>()
        .map(singleLine)
        .where((t) => t.isNotEmpty)
        .join(' - ');
    final buffer = StringBuffer()
      ..writeln('[Script Info]')
      ..writeln('; Generated by LyricForge')
      ..writeln('Title: ${title.isEmpty ? 'LyricForge' : _escapeAss(title)}')
      ..writeln('ScriptType: v4.00+')
      ..writeln('WrapStyle: 0')
      ..writeln('ScaledBorderAndShadow: yes')
      ..writeln('PlayResX: 1920')
      ..writeln('PlayResY: 1080')
      ..writeln()
      ..writeln('[V4+ Styles]')
      ..writeln(
        'Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, '
        'OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, '
        'ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, '
        'Alignment, MarginL, MarginR, MarginV, Encoding',
      )
      ..writeln(
        'Style: $assStyleName,Noto Sans CJK SC,72,&H00FF9A2E,&H00FFFFFF,'
        '&H00202020,&H80000000,-1,0,0,0,100,100,0,0,1,4,2,2,80,80,90,1',
      )
      ..writeln()
      ..writeln('[Events]')
      ..writeln(
        'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, '
        'Effect, Text',
      );

    final list = subtitleCues(document);
    for (var index = 0; index < list.length; index++) {
      final cue = list[index];
      final earliest = index == 0 ? Duration.zero : list[index - 1].end;
      var shownFrom = cue.start - (leadIn.isNegative ? Duration.zero : leadIn);
      if (shownFrom < earliest) shownFrom = earliest;
      if (shownFrom > cue.start) shownFrom = cue.start;
      final text = StringBuffer();
      final lead = _centiseconds(cue.start) - _centiseconds(shownFrom);
      if (lead > 0) text.write('{\\k$lead}');
      for (final syllable in karaoke.syllables(cue.text, cue.start, cue.end)) {
        final length = (syllable.duration.inMilliseconds / 10).round();
        text.write('{\\kf$length}${_escapeAss(syllable.text)}');
      }
      buffer.writeln(
        'Dialogue: 0,${assTimestamp(shownFrom)},${assTimestamp(cue.end)},'
        '$assStyleName,,0,0,0,,$text',
      );
    }
    return buffer.toString();
  }

  /// The style every ASS row uses.
  static const String assStyleName = 'Karaoke';

  /// `h:mm:ss.cc`, as ASS reads it.
  static String assTimestamp(Duration value) {
    final total = _centiseconds(value);
    final hours = total ~/ 360000;
    final minutes = (total ~/ 6000).remainder(60).toString().padLeft(2, '0');
    final seconds = (total ~/ 100).remainder(60).toString().padLeft(2, '0');
    final centis = total.remainder(100).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds.$centis';
  }

  static int _centiseconds(Duration value) =>
      (_clamp(value).inMilliseconds / 10).round();

  /// Braces open ASS override blocks and a backslash starts `\N`-style
  /// escapes; neither has a portable escape, so they become their
  /// full-width forms.
  static String _escapeAss(String text) =>
      text.replaceAll('\\', '＼').replaceAll('{', '｛').replaceAll('}', '｝');

  void _writeLrcHeader(
    StringBuffer buffer,
    LyricDocument document,
    LyricExportMetadata metadata,
  ) {
    void tag(String key, String? value) {
      final normalized = value == null ? null : singleLine(value);
      if (normalized == null || normalized.isEmpty) return;
      buffer.writeln('[$key:$normalized]');
    }

    tag('ti', metadata.title);
    tag('ar', metadata.artist);
    tag('al', metadata.album);
    tag('lang', document.language);
    buffer.writeln('[re:LyricForge]');
    buffer.writeln('[ve:1]');
  }

  String encodeSrt(LyricDocument document) {
    final buffer = StringBuffer();
    final list = subtitleCues(document);
    for (var index = 0; index < list.length; index++) {
      final cue = list[index];
      if (index > 0) buffer.writeln();
      buffer
        ..writeln(index + 1)
        ..writeln(
          '${subtitleTimestamp(cue.start, separator: ',')} --> '
          '${subtitleTimestamp(cue.end, separator: ',')}',
        )
        ..writeln(cue.text);
    }
    return buffer.toString();
  }

  String encodeVtt(
    LyricDocument document, {
    LyricExportMetadata metadata = const LyricExportMetadata(),
  }) {
    final buffer = StringBuffer('WEBVTT\n');
    final title = metadata.title == null ? '' : singleLine(metadata.title!);
    final artist = metadata.artist == null ? '' : singleLine(metadata.artist!);
    if (title.isNotEmpty || artist.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('NOTE')
        ..writeln([title, artist].where((part) => part.isNotEmpty).join(' - '));
    }
    for (final cue in subtitleCues(document)) {
      buffer
        ..writeln()
        ..writeln(
          '${subtitleTimestamp(cue.start, separator: '.')} --> '
          '${subtitleTimestamp(cue.end, separator: '.')}',
        )
        ..writeln(_escapeVtt(cue.text));
    }
    return buffer.toString();
  }

  String encodePlainText(
    LyricDocument document, {
    bool paragraphsAtPauses = true,
    Duration paragraphGap = const Duration(seconds: 4),
  }) {
    final buffer = StringBuffer();
    final list = cues(document);
    for (var index = 0; index < list.length; index++) {
      final cue = list[index];
      if (index > 0 && paragraphsAtPauses) {
        final previous = list[index - 1];
        final previousEnd = previous.end > previous.start
            ? previous.end
            : previous.start;
        if (cue.start - previousEnd >= paragraphGap) buffer.writeln();
      }
      buffer.writeln(cue.text);
    }
    return buffer.toString();
  }

  /// `mm:ss.mmm`, as LRC players read it.
  static String lrcTimestamp(Duration value) {
    final safe = _clamp(value);
    final minutes = safe.inMinutes.toString().padLeft(2, '0');
    final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
    final milliseconds = safe.inMilliseconds
        .remainder(1000)
        .toString()
        .padLeft(3, '0');
    return '$minutes:$seconds.$milliseconds';
  }

  /// `hh:mm:ss,mmm` (SRT) or `hh:mm:ss.mmm` (WebVTT).
  static String subtitleTimestamp(Duration value, {required String separator}) {
    final safe = _clamp(value);
    final hours = safe.inHours.toString().padLeft(2, '0');
    final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
    final milliseconds = safe.inMilliseconds
        .remainder(1000)
        .toString()
        .padLeft(3, '0');
    return '$hours:$minutes:$seconds$separator$milliseconds';
  }

  /// Collapses line breaks and surrounding whitespace into one line.
  static String singleLine(String text) =>
      text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();

  /// `-->` would end a WebVTT cue timing line and `<`/`&` start markup.
  static String _escapeVtt(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static Duration _clamp(Duration value) =>
      value.isNegative ? Duration.zero : value;
}
