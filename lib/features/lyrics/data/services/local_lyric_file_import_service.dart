import 'dart:convert' as convert;
import 'dart:io';

import 'package:charset/charset.dart' as charset;

import '../../../project/domain/models/lyric_document.dart';
import '../../domain/services/lyric_file_import_service.dart';

class LocalLyricFileImportService implements LyricFileImportService {
  static const Set<String> _extensions = {
    'lrc',
    'srt',
    'vtt',
    'ass',
    'ssa',
    'txt',
    'text',
  };

  @override
  Set<String> get supportedExtensions => _extensions;

  @override
  Future<LyricImportResult> importFile(
    String path, {
    String? encodingHint,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      throw LyricImportException('歌词文件不存在: $path');
    }

    final extension = _extension(path);
    if (!_extensions.contains(extension)) {
      throw LyricImportException(
        '暂不支持 .$extension 歌词文件。支持: ${_extensions.join(', ')}',
      );
    }

    final bytes = await file.readAsBytes();
    final decoded = _decodeText(bytes, encodingHint: encodingHint);
    return parseText(
      decoded.text,
      extension: extension,
      sourcePath: file.absolute.path,
      detectedEncoding: decoded.encoding,
    );
  }

  @override
  LyricImportResult parseText(
    String text, {
    required String extension,
    String sourcePath = '',
    String detectedEncoding = 'unicode',
  }) {
    final normalizedExtension = extension.toLowerCase().replaceFirst('.', '');
    final normalizedText = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    return switch (normalizedExtension) {
      'lrc' => _parseLrc(normalizedText, sourcePath, detectedEncoding),
      'srt' => _parseSrt(normalizedText, sourcePath, detectedEncoding),
      'vtt' => _parseVtt(normalizedText, sourcePath, detectedEncoding),
      'ass' || 'ssa' =>
        _parseAss(normalizedText, sourcePath, detectedEncoding),
      'txt' || 'text' =>
        _parsePlainText(normalizedText, sourcePath, detectedEncoding),
      _ => throw LyricImportException(
          '暂不支持 .$normalizedExtension 歌词文件。',
        ),
    };
  }

  _DecodedText _decodeText(
    List<int> bytes, {
    String? encodingHint,
  }) {
    if (bytes.isEmpty) return const _DecodedText('', 'utf-8');

    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return _DecodedText(
        convert.utf8.decode(bytes.sublist(3), allowMalformed: false),
        'utf-8',
      );
    }

    if (charset.hasUtf16Bom(bytes)) {
      return _DecodedText(charset.utf16.decode(bytes), 'utf-16');
    }

    if (encodingHint != null && encodingHint.trim().isNotEmpty) {
      final encoding = charset.Charset.getByName(encodingHint.trim());
      if (encoding == null) {
        throw LyricImportException('未知歌词编码: $encodingHint');
      }
      try {
        return _DecodedText(encoding.decode(bytes), encoding.name);
      } catch (error) {
        throw LyricImportException(
          '无法使用 $encodingHint 解码歌词文件',
          cause: error,
        );
      }
    }

    try {
      return _DecodedText(
        convert.utf8.decode(bytes, allowMalformed: false),
        'utf-8',
      );
    } on FormatException {
      // Continue with encodings commonly found in older Chinese/Japanese
      // Windows music collections.
    }

    final detected = charset.Charset.detect(
      bytes,
      orders: [
        charset.gbk,
        charset.shiftJis,
        charset.eucJp,
        charset.windows1252,
      ],
    );
    if (detected == null) {
      throw const LyricImportException(
        '无法识别歌词文本编码。请尝试指定 UTF-8、GBK 或 Shift-JIS。',
      );
    }

    try {
      return _DecodedText(detected.decode(bytes), detected.name);
    } catch (error) {
      throw LyricImportException('歌词文本解码失败', cause: error);
    }
  }

  LyricImportResult _parseLrc(
    String text,
    String sourcePath,
    String encoding,
  ) {
    final title = _lrcMetadata(text, 'ti');
    final artist = _lrcMetadata(text, 'ar');
    final album = _lrcMetadata(text, 'al');
    final language = _lrcMetadata(text, 'lang') ??
        _lrcMetadata(text, 'language') ??
        'und';
    final offsetText = _lrcMetadata(text, 'offset');
    final offset = int.tryParse(offsetText ?? '') ?? 0;
    final entries = <_TimedText>[];
    final tagExpression = RegExp(r'\[([^\]]+)\]');

    for (final rawLine in text.split('\n')) {
      final line = rawLine.trimRight();
      if (line.trim().isEmpty) continue;
      final matches = tagExpression.allMatches(line).toList();
      if (matches.isEmpty) continue;

      final timestamps = <Duration>[];
      var textStart = 0;
      for (final match in matches) {
        if (match.start != textStart) break;
        final content = match.group(1) ?? '';
        final timestamp = _parseLrcTimestamp(content);
        if (timestamp != null) timestamps.add(timestamp);
        textStart = match.end;
      }
      if (timestamps.isEmpty) continue;

      final lyricText = line
          .substring(textStart)
          .replaceAll(RegExp(r'<\d+:[^>]+>'), '')
          .trim();
      if (lyricText.isEmpty) continue;
      for (final timestamp in timestamps) {
        entries.add(_TimedText(timestamp, lyricText));
      }
    }

    entries.sort((a, b) => a.start.compareTo(b.start));
    final lines = <LyricLine>[];
    for (var i = 0; i < entries.length; i++) {
      final current = entries[i];
      var end = i + 1 < entries.length
          ? entries[i + 1].start
          : current.start + const Duration(seconds: 5);
      if (end <= current.start) {
        end = current.start + const Duration(milliseconds: 500);
      }
      lines.add(
        LyricLine(
          text: current.text,
          startTime: current.start,
          endTime: end,
        ),
      );
    }

    final document = LyricDocument(
      language: language,
      lines: lines,
      globalOffset: offset == 0 ? null : Duration(milliseconds: offset),
      metadata: _metadata(
        format: 'lrc',
        sourcePath: sourcePath,
        timed: true,
        title: title,
        artist: artist,
        album: album,
      ),
    );
    return LyricImportResult(
      document: document,
      format: LyricImportFormat.lrc,
      sourcePath: sourcePath,
      detectedEncoding: encoding,
      title: title,
      artist: artist,
      album: album,
    );
  }

  LyricImportResult _parseSrt(
    String text,
    String sourcePath,
    String encoding,
  ) {
    final lines = _parseSubtitleBlocks(text, webVtt: false);
    return LyricImportResult(
      document: LyricDocument(
        language: 'und',
        lines: lines,
        metadata: _metadata(
          format: 'srt',
          sourcePath: sourcePath,
          timed: true,
        ),
      ),
      format: LyricImportFormat.srt,
      sourcePath: sourcePath,
      detectedEncoding: encoding,
    );
  }

  LyricImportResult _parseVtt(
    String text,
    String sourcePath,
    String encoding,
  ) {
    final lines = _parseSubtitleBlocks(text, webVtt: true);
    return LyricImportResult(
      document: LyricDocument(
        language: 'und',
        lines: lines,
        metadata: _metadata(
          format: 'vtt',
          sourcePath: sourcePath,
          timed: true,
        ),
      ),
      format: LyricImportFormat.webvtt,
      sourcePath: sourcePath,
      detectedEncoding: encoding,
    );
  }

  LyricImportResult _parseAss(
    String text,
    String sourcePath,
    String encoding,
  ) {
    final lines = <LyricLine>[];
    var inEvents = false;
    List<String> fields = const [
      'Layer',
      'Start',
      'End',
      'Style',
      'Name',
      'MarginL',
      'MarginR',
      'MarginV',
      'Effect',
      'Text',
    ];

    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      final trimmed = line.trim();
      if (trimmed.startsWith('[')) {
        inEvents = trimmed.toLowerCase() == '[events]';
        continue;
      }
      if (!inEvents) continue;
      if (trimmed.toLowerCase().startsWith('format:')) {
        fields = trimmed
            .substring(trimmed.indexOf(':') + 1)
            .split(',')
            .map((entry) => entry.trim())
            .toList();
        continue;
      }
      if (!trimmed.toLowerCase().startsWith('dialogue:')) continue;

      final payload = line.substring(line.indexOf(':') + 1).trimLeft();
      final values = _splitCsv(payload, fields.length);
      if (values.length < fields.length) continue;
      final startIndex = _caseInsensitiveIndex(fields, 'Start');
      final endIndex = _caseInsensitiveIndex(fields, 'End');
      final textIndex = _caseInsensitiveIndex(fields, 'Text');
      if (startIndex < 0 || endIndex < 0 || textIndex < 0) continue;

      final start = _parseAssTimestamp(values[startIndex]);
      final end = _parseAssTimestamp(values[endIndex]);
      if (start == null || end == null || end <= start) continue;
      final lyricText = values[textIndex]
          .replaceAll(RegExp(r'\{[^}]*\}'), '')
          .replaceAll(r'\N', '\n')
          .replaceAll(r'\n', '\n')
          .trim();
      if (lyricText.isEmpty) continue;
      lines.add(
        LyricLine(text: lyricText, startTime: start, endTime: end),
      );
    }

    lines.sort((a, b) => a.startTime.compareTo(b.startTime));
    return LyricImportResult(
      document: LyricDocument(
        language: 'und',
        lines: lines,
        metadata: _metadata(
          format: 'ass',
          sourcePath: sourcePath,
          timed: true,
        ),
      ),
      format: LyricImportFormat.ass,
      sourcePath: sourcePath,
      detectedEncoding: encoding,
    );
  }

  LyricImportResult _parsePlainText(
    String text,
    String sourcePath,
    String encoding,
  ) {
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map(
          (line) => LyricLine(
            text: line,
            startTime: Duration.zero,
            endTime: Duration.zero,
          ),
        )
        .toList();

    return LyricImportResult(
      document: LyricDocument(
        language: 'und',
        lines: lines,
        metadata: _metadata(
          format: 'txt',
          sourcePath: sourcePath,
          timed: false,
        ),
      ),
      format: LyricImportFormat.plainText,
      sourcePath: sourcePath,
      detectedEncoding: encoding,
    );
  }

  List<LyricLine> _parseSubtitleBlocks(String text, {required bool webVtt}) {
    final cleaned = webVtt
        ? text.replaceFirst(RegExp(r'^\uFEFF?WEBVTT[^\n]*\n?'), '')
        : text;
    final blocks = cleaned.split(RegExp(r'\n\s*\n'));
    final result = <LyricLine>[];

    for (final block in blocks) {
      final rawLines = block.split('\n');
      if (rawLines.isEmpty) continue;
      final first = rawLines.first.trim();
      if (webVtt &&
          (first.startsWith('NOTE') ||
              first.startsWith('STYLE') ||
              first.startsWith('REGION'))) {
        continue;
      }

      final timingIndex = rawLines.indexWhere((line) => line.contains('-->'));
      if (timingIndex < 0) continue;
      final timing = rawLines[timingIndex].split('-->');
      if (timing.length != 2) continue;
      final start = _parseSubtitleTimestamp(timing[0].trim());
      final endToken = timing[1].trim().split(RegExp(r'\s+')).first;
      final end = _parseSubtitleTimestamp(endToken);
      if (start == null || end == null || end <= start) continue;

      final cueText = rawLines
          .skip(timingIndex + 1)
          .join('\n')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .trim();
      if (cueText.isEmpty) continue;
      result.add(
        LyricLine(text: cueText, startTime: start, endTime: end),
      );
    }

    result.sort((a, b) => a.startTime.compareTo(b.startTime));
    return result;
  }

  Duration? _parseLrcTimestamp(String value) {
    final match = RegExp(r'^(\d{1,3}):(\d{1,2})(?:[\.:](\d{1,3}))?$')
        .firstMatch(value.trim());
    if (match == null) return null;
    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    if (seconds >= 60) return null;
    final fraction = match.group(3) ?? '';
    final milliseconds = switch (fraction.length) {
      0 => 0,
      1 => int.parse(fraction) * 100,
      2 => int.parse(fraction) * 10,
      _ => int.parse(fraction.substring(0, 3)),
    };
    return Duration(
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }

  Duration? _parseSubtitleTimestamp(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    final parts = normalized.split(':');
    if (parts.length != 2 && parts.length != 3) return null;

    final secondsPart = parts.last.split('.');
    final seconds = int.tryParse(secondsPart.first);
    if (seconds == null || seconds >= 60) return null;
    final milliseconds = secondsPart.length > 1
        ? _fractionToMilliseconds(secondsPart[1])
        : 0;
    final minutes = int.tryParse(parts[parts.length - 2]);
    if (minutes == null || minutes >= 60) return null;
    final hours = parts.length == 3 ? int.tryParse(parts.first) : 0;
    if (hours == null) return null;

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }

  Duration? _parseAssTimestamp(String value) {
    final match = RegExp(r'^(\d+):(\d{1,2}):(\d{1,2})\.(\d{1,2})$')
        .firstMatch(value.trim());
    if (match == null) return null;
    final hours = int.parse(match.group(1)!);
    final minutes = int.parse(match.group(2)!);
    final seconds = int.parse(match.group(3)!);
    final centiseconds = int.parse(match.group(4)!);
    if (minutes >= 60 || seconds >= 60) return null;
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: centiseconds * 10,
    );
  }

  int _fractionToMilliseconds(String fraction) {
    final digits = fraction.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return 0;
    if (digits.length == 1) return int.parse(digits) * 100;
    if (digits.length == 2) return int.parse(digits) * 10;
    return int.parse(digits.substring(0, 3));
  }

  String? _lrcMetadata(String text, String key) {
    final match = RegExp(
      '^\\[$key:(.*)\\]\\s*\$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(text);
    final value = match?.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Map<String, dynamic> _metadata({
    required String format,
    required String sourcePath,
    required bool timed,
    String? title,
    String? artist,
    String? album,
  }) {
    return {
      'source': 'imported-file',
      'sourceFormat': format,
      'sourcePath': sourcePath,
      'timed': timed,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (album != null) 'album': album,
    };
  }

  List<String> _splitCsv(String value, int expectedColumns) {
    if (expectedColumns <= 1) return [value];
    final result = <String>[];
    var start = 0;
    for (var i = 0;
        i < value.length && result.length < expectedColumns - 1;
        i++) {
      if (value.codeUnitAt(i) == 0x2C) {
        result.add(value.substring(start, i));
        start = i + 1;
      }
    }
    result.add(value.substring(start));
    return result;
  }

  int _caseInsensitiveIndex(List<String> values, String target) {
    final normalized = target.toLowerCase();
    return values.indexWhere((value) => value.toLowerCase() == normalized);
  }

  String _extension(String path) {
    final fileName = path.split(Platform.pathSeparator).last;
    final dot = fileName.lastIndexOf('.');
    return dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  }
}

class _TimedText {
  final Duration start;
  final String text;

  const _TimedText(this.start, this.text);
}

class _DecodedText {
  final String text;
  final String encoding;

  const _DecodedText(this.text, this.encoding);
}
