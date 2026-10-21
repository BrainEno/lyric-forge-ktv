import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  group('LyricLine 稳定行标识 id', () {
    test('默认构造没有 id（旧调用方不受影响）', () {
      const line = LyricLine(
        text: '月亮代表我的心',
        startTime: Duration.zero,
        endTime: Duration(seconds: 4),
      );
      expect(line.id, isNull);
    });

    test('带 id 的行 JSON 往返后 id 保持不变', () {
      const line = LyricLine(
        text: '月亮代表我的心',
        startTime: Duration(seconds: 1),
        endTime: Duration(seconds: 5),
        confidence: 80,
        isChorus: true,
        id: 'line-abc-123',
      );

      final restored = LyricLine.fromJson(line.toJson());

      expect(restored.id, 'line-abc-123');
      expect(restored.text, line.text);
      expect(restored.startTime, line.startTime);
      expect(restored.endTime, line.endTime);
      expect(restored.confidence, line.confidence);
      expect(restored.isChorus, line.isChorus);
    });

    test('旧数据没有 id 字段时解析为 null', () {
      final restored = LyricLine.fromJson(const {
        'text': '旧数据行',
        'startTime': 0,
        'endTime': 4000,
      });
      expect(restored.id, isNull);
    });

    test('没有 id 的行 toJson 不写入 id 字段', () {
      const line = LyricLine(
        text: '无标识行',
        startTime: Duration.zero,
        endTime: Duration(seconds: 4),
      );
      expect(line.toJson().containsKey('id'), isFalse);
    });

    test('copyWith 保留原 id', () {
      const line = LyricLine(
        text: '第一句',
        startTime: Duration.zero,
        endTime: Duration(seconds: 4),
        id: 'line-keep',
      );

      final updated = line.copyWith(text: '第一句改词');

      expect(updated.id, 'line-keep');
      expect(updated.text, '第一句改词');
    });

    test('LyricDocument 整体 JSON 往返保留每行 id', () {
      final document = LyricDocument(
        language: 'zh',
        lines: const [
          LyricLine(
            text: '第一句',
            startTime: Duration.zero,
            endTime: Duration(seconds: 4),
            id: 'line-1',
          ),
          LyricLine(
            text: '第二句',
            startTime: Duration(seconds: 4),
            endTime: Duration(seconds: 8),
            id: 'line-2',
          ),
        ],
        metadata: const {
          'manuallyEditedLineIds': ['line-1'],
        },
      );

      final restored = LyricDocument.fromJson(document.toJson());

      expect(restored.lines[0].id, 'line-1');
      expect(restored.lines[1].id, 'line-2');
      expect(restored.metadata['manuallyEditedLineIds'], ['line-1']);
    });
  });
}
