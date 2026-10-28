import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/local_lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_file_import_service.dart';

void main() {
  final service = LocalLyricFileImportService();

  LyricImportResult parse(String text) =>
      service.parseText(text, extension: 'lrc', sourcePath: 'test.lrc');

  group('LRC 时间戳冲突处理', () {
    test('正常 LRC 无冲突，conflicts 为空', () {
      final result = parse('[00:01.000]第一行\n[00:06.000]第二行\n');

      expect(result.conflicts, isEmpty);
      expect(result.document.lines, hasLength(2));
    });

    test('重复时间戳产生零时长冲突，明确提示且不静默删除', () {
      final result = parse('[00:01.000]第一行\n[00:01.000]第二行\n');

      expect(result.conflicts, isNotEmpty);
      expect(result.document.lines, hasLength(2));
      // 两行保留，不静默删除。
      expect(result.document.lines[0].text, '第一行');
      expect(result.document.lines[1].text, '第二行');
      // 冲突说明应指向两行重叠。
      expect(result.conflicts.any((c) => c.contains('重叠')), isTrue);
    });

    test('三行相同时间戳产生多个冲突，均明确提示', () {
      final result = parse('[00:01.000]第一行\n[00:01.000]第二行\n[00:01.000]第三行\n');

      expect(result.conflicts.length, greaterThanOrEqualTo(2));
      expect(result.document.lines, hasLength(3));
    });

    test('时间间隔合理时无冲突', () {
      final result = parse('[00:01.000]第一行\n[00:06.000]第二行\n');

      expect(result.conflicts, isEmpty);
      expect(result.document.lines, hasLength(2));
    });

    test('倒序时间戳在排序后无冲突，原始顺序不影响结果', () {
      final result = parse('[00:06.000]第二行\n[00:01.000]第一行\n');

      expect(result.conflicts, isEmpty);
      expect(result.document.lines[0].text, '第一行');
      expect(result.document.lines[1].text, '第二行');
    });
  });
}
