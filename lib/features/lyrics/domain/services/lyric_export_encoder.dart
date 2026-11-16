import '../../../project/domain/models/lyric_document.dart';

/// File formats the editor can export.
enum LyricExportFormat {
  /// Synchronised lyrics for music players and KTV software.
  lrc,

  /// SubRip subtitles, for video editors and karaoke video tools.
  srt,

  /// WebVTT subtitles, for browsers and web players.
  vtt,

  /// Plain lyric text without timestamps, for sharing or reference.
  plainText;

  String get extension => switch (this) {
    LyricExportFormat.lrc => 'lrc',
    LyricExportFormat.srt => 'srt',
    LyricExportFormat.vtt => 'vtt',
    LyricExportFormat.plainText => 'txt',
  };

  String get label => switch (this) {
    LyricExportFormat.lrc => 'LRC 同步歌词',
    LyricExportFormat.srt => 'SRT 字幕',
    LyricExportFormat.vtt => 'WebVTT 字幕',
    LyricExportFormat.plainText => '纯文本歌词',
  };

  String get description => switch (this) {
    LyricExportFormat.lrc => '音乐播放器、KTV 软件通用；只记录每行开始时间',
    LyricExportFormat.srt => '视频剪辑、卡拉 OK 视频制作常用；带开始和结束时间',
    LyricExportFormat.vtt => '网页播放器使用；带开始和结束时间',
    LyricExportFormat.plainText => '不带时间，按间奏自动分段，便于分享或核对',
  };

  /// Whether the format carries timestamps.
  bool get timed => this != LyricExportFormat.plainText;
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

  const LyricExportOptions({
    this.lrcEndMarkers = false,
    this.paragraphsAtPauses = true,
    this.pauseThreshold = const Duration(milliseconds: 1500),
    this.paragraphGap = const Duration(seconds: 4),
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
  const LyricExportEncoder();

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
