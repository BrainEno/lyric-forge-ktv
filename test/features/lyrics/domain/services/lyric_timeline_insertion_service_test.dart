import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_timeline_insertion_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const service = LyricTimelineInsertionService();

  LyricLine line(int startMs, int endMs, String text) {
    return LyricLine(
      text: text,
      startTime: Duration(milliseconds: startMs),
      endTime: Duration(milliseconds: endMs),
    );
  }

  test('inserts before the next line and spans the gap', () {
    final insertion = service.insertAtPlayback(
      lines: [line(0, 4000, '第一行'), line(20000, 24000, '第二行')],
      position: const Duration(seconds: 10),
    );

    expect(insertion.index, 1);
    expect(insertion.line.text, '');
    expect(insertion.line.startTime, const Duration(seconds: 10));
    expect(insertion.line.endTime, const Duration(seconds: 20));
  });

  test('appends when playback is past the last line start', () {
    final insertion = service.insertAtPlayback(
      lines: [line(0, 4000, '第一行'), line(5000, 9000, '第二行')],
      position: const Duration(seconds: 30),
    );

    expect(insertion.index, 2);
    expect(insertion.line.startTime, const Duration(seconds: 30));
    expect(insertion.line.endTime, const Duration(seconds: 35));
  });

  test('starts a new document when there are no lines', () {
    final insertion = service.insertAtPlayback(
      lines: const [],
      position: const Duration(seconds: 8),
    );

    expect(insertion.index, 0);
    expect(insertion.line.startTime, const Duration(seconds: 8));
    expect(insertion.line.endTime, const Duration(seconds: 13));
  });

  test('enforces a minimum 10ms duration before an almost immediate line', () {
    final insertion = service.insertAtPlayback(
      lines: [line(10005, 14000, '下一行')],
      position: const Duration(milliseconds: 10000),
    );

    expect(insertion.index, 0);
    expect(insertion.line.startTime, const Duration(milliseconds: 10000));
    expect(insertion.line.endTime, const Duration(milliseconds: 10010));
  });

  test('clamps negative playback positions to zero', () {
    final insertion = service.insertAtPlayback(
      lines: [line(3000, 6000, '第一行')],
      position: const Duration(seconds: -2),
    );

    expect(insertion.index, 0);
    expect(insertion.line.startTime, Duration.zero);
    expect(insertion.line.endTime, const Duration(seconds: 3));
  });

  test('inserts after a line that starts exactly at the playback position', () {
    final insertion = service.insertAtPlayback(
      lines: [
        line(0, 4000, '第一行'),
        line(10000, 14000, '当前行'),
        line(20000, 24000, '下一行'),
      ],
      position: const Duration(seconds: 10),
    );

    expect(insertion.index, 2);
    expect(insertion.line.startTime, const Duration(seconds: 10));
    expect(insertion.line.endTime, const Duration(seconds: 20));
  });

  group('音频时长边界（尾部插入）', () {
    const audioDuration = Duration(seconds: 30);

    test('尾部插入结束时间不超过音频总时长', () {
      final insertion = service.insertAtPlayback(
        lines: [line(0, 4000, '第一行'), line(20000, 24000, '第二行')],
        position: const Duration(seconds: 28),
        audioDuration: audioDuration,
      );

      expect(insertion.index, 2);
      expect(insertion.line.startTime, const Duration(seconds: 28));
      expect(insertion.line.endTime, audioDuration);
    });

    test('播放位置已超出音频时结束时间被限制到音频末尾，供校验器标记需校准', () {
      final insertion = service.insertAtPlayback(
        lines: [line(0, 4000, '第一行')],
        position: const Duration(seconds: 32),
        audioDuration: audioDuration,
      );

      expect(insertion.index, 1);
      expect(insertion.line.startTime, const Duration(seconds: 32));
      expect(insertion.line.endTime, audioDuration);
    });

    test('非尾部插入不受音频时长边界限制', () {
      final insertion = service.insertAtPlayback(
        lines: [
          line(0, 4000, '第一行'),
          line(20000, 24000, '第二行'),
          line(40000, 44000, '第三行'),
        ],
        position: const Duration(seconds: 10),
        audioDuration: audioDuration,
      );

      expect(insertion.index, 1);
      expect(insertion.line.startTime, const Duration(seconds: 10));
      expect(insertion.line.endTime, const Duration(seconds: 20));
    });

    test('未提供音频时长时不做边界检查', () {
      final insertion = service.insertAtPlayback(
        lines: [line(0, 4000, '第一行')],
        position: const Duration(seconds: 40),
      );

      expect(insertion.line.endTime, const Duration(seconds: 45));
    });
  });
}
