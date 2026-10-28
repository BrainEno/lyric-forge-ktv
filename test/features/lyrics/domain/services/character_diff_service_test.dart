import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/character_diff_service.dart';

void main() {
  const service = CharacterDiffService();

  List<String> types(List<CharacterDiffSegment> segments) {
    return [for (final segment in segments) segment.type.name];
  }

  List<String> texts(List<CharacterDiffSegment> segments) {
    return [for (final segment in segments) segment.text];
  }

  test('完全相同的文本只有一个 equal 片段', () {
    final segments = service.diff('月亮代表我的心', '月亮代表我的心');

    expect(segments, hasLength(1));
    expect(segments.single.type, CharacterDiffType.equal);
    expect(segments.single.text, '月亮代表我的心');
  });

  test('空文本不会产生片段', () {
    expect(service.diff('', ''), isEmpty);
  });

  test('标记中间插入的字符', () {
    final segments = service.diff('月亮我的心', '月亮代表我的心');

    expect(types(segments), contains('insert'));
    final inserted = segments
        .where((segment) => segment.type == CharacterDiffType.insert)
        .map((segment) => segment.text)
        .join();
    expect(inserted, '代表');
    expect(
      segments
          .where((segment) => segment.type != CharacterDiffType.delete)
          .map((segment) => segment.text)
          .join(),
      '月亮代表我的心',
    );
  });

  test('标记被删除的字符', () {
    final segments = service.diff('月亮代表我的星', '月亮代表我的心');

    final deleted = segments
        .where((segment) => segment.type == CharacterDiffType.delete)
        .map((segment) => segment.text)
        .join();
    expect(deleted, '星');
    expect(
      segments
          .where((segment) => segment.type != CharacterDiffType.insert)
          .map((segment) => segment.text)
          .join(),
      '月亮代表我的星',
    );
  });

  test('替换字符时同时产生删除与插入', () {
    final segments = service.diff('abcd', 'abXd');

    expect(types(segments), contains('delete'));
    expect(types(segments), contains('insert'));
    expect(
      segments
          .where((segment) => segment.type == CharacterDiffType.delete)
          .map((segment) => segment.text)
          .join(),
      'c',
    );
    expect(
      segments
          .where((segment) => segment.type == CharacterDiffType.insert)
          .map((segment) => segment.text)
          .join(),
      'X',
    );
  });

  test('把相邻同类型片段合并，避免逐字渲染', () {
    final segments = service.diff('abc', 'abXYZc');

    expect(types(segments), ['equal', 'insert', 'equal']);
    expect(texts(segments), ['ab', 'XYZ', 'c']);
  });

  test('按 Unicode 码点处理 emoji', () {
    final segments = service.diff('唱歌🎤', '唱歌🎧');

    final deleted = segments
        .where((segment) => segment.type == CharacterDiffType.delete)
        .map((segment) => segment.text)
        .join();
    final inserted = segments
        .where((segment) => segment.type == CharacterDiffType.insert)
        .map((segment) => segment.text)
        .join();
    expect(deleted, '🎤');
    expect(inserted, '🎧');
  });

  test('接受的文本可通过片段重组', () {
    final segments = service.diff('今天天气真好', '今天天气不错');

    final oldText = segments
        .where((segment) => segment.type != CharacterDiffType.insert)
        .map((segment) => segment.text)
        .join();
    final newText = segments
        .where((segment) => segment.type != CharacterDiffType.delete)
        .map((segment) => segment.text)
        .join();

    expect(oldText, '今天天气真好');
    expect(newText, '今天天气不错');
  });

  test('空旧文本只产生插入片段', () {
    final segments = service.diff('', '第一句');

    expect(segments, hasLength(1));
    expect(segments.single.type, CharacterDiffType.insert);
    expect(segments.single.text, '第一句');
  });

  test('空新文本只产生删除片段', () {
    final segments = service.diff('第一句', '');

    expect(segments, hasLength(1));
    expect(segments.single.type, CharacterDiffType.delete);
    expect(segments.single.text, '第一句');
  });
}
