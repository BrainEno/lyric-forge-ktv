import 'dart:convert';

import '../../../project/domain/models/lyric_document.dart';

class TimingEvidenceJsonParser {
  const TimingEvidenceJsonParser();

  LyricDocument parse(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('JSON 顶层必须是对象');
    }
    final root = decoded['lyricDocument'] is Map<String, dynamic>
        ? decoded['lyricDocument'] as Map<String, dynamic>
        : decoded;
    if (root['lines'] is! List) {
      throw const FormatException(
        '找不到 lines 数组；请选择歌词文档或工程 manifest JSON',
      );
    }
    final document = LyricDocument.fromJson(root);
    if (document.lines.isEmpty) {
      throw const FormatException('时间证据没有歌词行');
    }
    for (var index = 0; index < document.lines.length; index++) {
      final line = document.lines[index];
      if (line.text.trim().isEmpty ||
          line.startTime.isNegative ||
          line.endTime <= line.startTime ||
          line.confidence < 0 ||
          line.confidence > 100) {
        throw FormatException('第 ${index + 1} 行的文字、时间或置信度无效');
      }
    }
    return document;
  }
}
