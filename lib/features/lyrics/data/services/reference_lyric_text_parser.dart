import '../../../project/domain/models/lyric_document.dart';
import '../../domain/models/reference_lyric_input.dart';
import '../../domain/models/reference_lyric_line.dart';
import '../../domain/services/lyric_file_import_service.dart';

/// 参考歌词解析失败时抛出的可展示错误。
class ReferenceLyricParseException implements Exception {
  final String message;
  final Object? cause;

  const ReferenceLyricParseException(this.message, {this.cause});

  @override
  String toString() => message;
}

/// 把粘贴文本或本地歌词文件转换成对齐服务需要的参考行。
///
/// 纯文本没有时间戳；LRC/SRT/WebVTT/ASS 保留并整体偏移原始时间轴。
class ReferenceLyricTextParser {
  final LyricFileImportService importer;

  const ReferenceLyricTextParser(this.importer);

  Set<String> get supportedExtensions => importer.supportedExtensions;

  /// 粘贴文本：自动判别 LRC / SRT / WebVTT / ASS / 纯文本。
  ReferenceLyricInput parsePasted(
    String text, {
    Duration offset = Duration.zero,
    String? title,
    String? artist,
  }) {
    if (text.trim().isEmpty) {
      throw const ReferenceLyricParseException('请先粘贴参考歌词文本');
    }

    final extension = detectExtension(text);
    try {
      final result = importer.parseText(
        text,
        extension: extension,
        sourcePath: '',
      );
      return _fromResult(result, offset: offset, title: title, artist: artist);
    } on LyricImportException catch (error) {
      throw ReferenceLyricParseException(error.message, cause: error);
    }
  }

  /// 本地文件：复用导入服务的编码自动检测；失败时保留原始错误信息。
  Future<ReferenceLyricInput> parseFile(
    String path, {
    String? encodingHint,
    Duration offset = Duration.zero,
    String? title,
    String? artist,
  }) async {
    try {
      final result = await importer.importFile(
        path,
        encodingHint: encodingHint,
      );
      return _fromResult(result, offset: offset, title: title, artist: artist);
    } on LyricImportException catch (error) {
      throw ReferenceLyricParseException(error.message, cause: error);
    }
  }

  static final RegExp _lrcTimestamp = RegExp(
    r'\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\]',
  );
  static final RegExp _lrcMetadata = RegExp(
    r'^\[(?:ti|ar|al|by|offset|length|lang|language):',
    caseSensitive: false,
    multiLine: true,
  );
  static final RegExp _subtitleCue = RegExp(r'-->');
  static final RegExp _assEvents = RegExp(
    r'^\s*\[events\]',
    caseSensitive: false,
    multiLine: true,
  );
  static final RegExp _assDialogue = RegExp(
    r'^\s*dialogue:',
    caseSensitive: false,
    multiLine: true,
  );

  /// 根据文本内容猜测导入服务需要的扩展名。
  static String detectExtension(String text) {
    if (_assEvents.hasMatch(text) && _assDialogue.hasMatch(text)) {
      return 'ass';
    }
    if (_subtitleCue.hasMatch(text)) {
      return text.trimLeft().toUpperCase().startsWith('WEBVTT') ? 'vtt' : 'srt';
    }
    if (_lrcTimestamp.hasMatch(text) || _lrcMetadata.hasMatch(text)) {
      return 'lrc';
    }
    return 'txt';
  }

  ReferenceLyricInput _fromResult(
    LyricImportResult result, {
    required Duration offset,
    String? title,
    String? artist,
  }) {
    final timed = result.document.metadata['timed'] == true;
    final sourceOffset = timed
        ? result.document.globalOffset ?? Duration.zero
        : Duration.zero;
    final totalOffset = timed ? sourceOffset + offset : Duration.zero;

    final lines = timed
        ? _timedLines(result.document.lines, totalOffset)
        : _plainLines(result.document.lines);

    if (lines.isEmpty) {
      throw ReferenceLyricParseException(timed ? '没有识别到带时间戳的歌词行' : '没有识别到歌词文本');
    }

    return ReferenceLyricInput(
      lines: lines,
      timed: timed,
      format: result.format.name,
      offset: totalOffset,
      sourcePath: result.sourcePath.isEmpty ? null : result.sourcePath,
      title: title ?? result.title,
      artist: artist ?? result.artist,
    );
  }

  List<ReferenceLyricLine> _plainLines(List<LyricLine> source) {
    final lines = <ReferenceLyricLine>[];
    for (final line in source) {
      final text = line.text.trim();
      if (text.isEmpty) continue;
      lines.add(ReferenceLyricLine(text: text));
    }
    return lines;
  }

  List<ReferenceLyricLine> _timedLines(
    List<LyricLine> source,
    Duration offset,
  ) {
    final shifted = <({String text, Duration start, Duration end})>[];
    for (final line in source) {
      final text = line.text.trim();
      if (text.isEmpty) continue;
      shifted.add((
        text: text,
        start: _shift(line.startTime, offset),
        end: _shift(line.endTime, offset),
      ));
    }

    final lines = <ReferenceLyricLine>[];
    for (var index = 0; index < shifted.length; index++) {
      final current = shifted[index];
      var start = current.start;
      var end = current.end;
      if (end <= start) {
        end = index + 1 < shifted.length
            ? shifted[index + 1].start
            : start + const Duration(seconds: 5);
        if (end <= start) {
          end = start + const Duration(milliseconds: 500);
        }
      }
      lines.add(
        ReferenceLyricLine(text: current.text, startTime: start, endTime: end),
      );
    }
    return lines;
  }

  static Duration _shift(Duration value, Duration offset) {
    final shifted = value + offset;
    return shifted.isNegative ? Duration.zero : shifted;
  }
}
