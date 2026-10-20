import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_timeline_validator.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  LyricLine line({
    required int startMs,
    required int endMs,
    String text = '歌词',
  }) {
    return LyricLine(
      text: text,
      startTime: Duration(milliseconds: startMs),
      endTime: Duration(milliseconds: endMs),
    );
  }

  LyricTimelineValidationResult validate(
    List<LyricLine> lines, {
    Duration? audioDuration,
  }) {
    return const LyricTimelineValidator().validate(
      lines: lines,
      audioDuration: audioDuration,
    );
  }

  group('正常时间轴', () {
    test('间隔合理的多行通过验证', () {
      final result = validate([
        line(startMs: 0, endMs: 4000),
        line(startMs: 5000, endMs: 9000),
        line(startMs: 10000, endMs: 14000),
      ]);

      expect(result.isValid, isTrue);
      expect(result.issues, isEmpty);
      expect(result.needsCalibration, isEmpty);
    });
  });

  group('负时间', () {
    test('负开始时间被检测并标记需校准', () {
      final result = validate([line(startMs: -1000, endMs: 4000)]);

      expect(result.isValid, isFalse);
      expect(result.issues, hasLength(1));
      expect(result.issues.single.type, TimelineIssueType.negativeStart);
      expect(result.issues.single.canAutoFix, isTrue);
      expect(result.needsCalibration, {0});
    });
  });

  group('零时长', () {
    test('结束等于开始被判为零时长并标记需校准', () {
      final result = validate([line(startMs: 2000, endMs: 2000)]);

      expect(result.isValid, isFalse);
      expect(
        result.issues.single.type,
        TimelineIssueType.zeroOrNegativeDuration,
      );
      expect(result.issues.single.canAutoFix, isFalse);
      expect(result.needsCalibration, {0});
    });

    test('结束早于开始被判为负时长并标记需校准', () {
      final result = validate([line(startMs: 3000, endMs: 2000)]);

      expect(result.isValid, isFalse);
      expect(
        result.issues.single.type,
        TimelineIssueType.zeroOrNegativeDuration,
      );
      expect(result.needsCalibration, {0});
    });
  });

  group('极短空隙', () {
    test('相邻行空隙小于阈值被标记极短空隙', () {
      final result = validate([
        line(startMs: 0, endMs: 4000),
        line(startMs: 4050, endMs: 8000), // 50ms 空隙 < 100ms
      ]);

      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.type == TimelineIssueType.extremelyShortGap),
        isTrue,
      );
      // 极短空隙可自动修复，不加入 needsCalibration。
      expect(result.needsCalibration, isEmpty);
    });

    test('空隙等于阈值不判定为极短', () {
      final result = validate([
        line(startMs: 0, endMs: 4000),
        line(startMs: 4100, endMs: 8000), // 100ms 空隙 = 阈值
      ]);

      expect(
        result.issues.any((i) => i.type == TimelineIssueType.extremelyShortGap),
        isFalse,
      );
    });
  });

  group('前后行重叠', () {
    test('本行开始早于前行结束，检测 overlapsPrevious', () {
      final result = validate([
        line(startMs: 0, endMs: 5000),
        line(startMs: 3000, endMs: 8000),
      ]);

      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.type == TimelineIssueType.overlapsPrevious),
        isTrue,
      );
      expect(result.needsCalibration, {0, 1});
    });

    test('本行结束晚于下行开始，检测 overlapsNext', () {
      final result = validate([
        line(startMs: 0, endMs: 5000),
        line(startMs: 3000, endMs: 8000),
      ]);

      expect(result.isValid, isFalse);
      expect(
        result.issues.any((i) => i.type == TimelineIssueType.overlapsNext),
        isTrue,
      );
      expect(result.needsCalibration, {0, 1});
    });

    test('重叠问题不可自动修复，需定点校准', () {
      final result = validate([
        line(startMs: 0, endMs: 5000),
        line(startMs: 3000, endMs: 8000),
      ]);

      final overlapIssues = result.issues
          .where(
            (i) =>
                i.type == TimelineIssueType.overlapsPrevious ||
                i.type == TimelineIssueType.overlapsNext,
          )
          .toList();
      expect(overlapIssues.every((i) => i.canAutoFix == false), isTrue);
    });
  });

  group('音频时长边界（尾部插入）', () {
    const duration = Duration(seconds: 30);

    test('开始时间超出音频总时长被标记并需校准', () {
      final result = validate([
        line(startMs: 31000, endMs: 35000),
      ], audioDuration: duration);

      expect(result.isValid, isFalse);
      expect(
        result.issues.any(
          (i) => i.type == TimelineIssueType.beyondAudioDuration,
        ),
        isTrue,
      );
      expect(result.needsCalibration, {0});
    });

    test('结束时间超出音频总时长被标记，可自动修复', () {
      final result = validate([
        line(startMs: 28000, endMs: 35000),
      ], audioDuration: duration);

      expect(result.isValid, isFalse);
      expect(
        result.issues.any(
          (i) => i.type == TimelineIssueType.endBeyondAudioDuration,
        ),
        isTrue,
      );
      expect(result.issues.single.canAutoFix, isTrue);
      expect(result.needsCalibration, isEmpty);
    });

    test('完全在音频时长内不报边界问题', () {
      final result = validate([
        line(startMs: 0, endMs: 5000),
        line(startMs: 25000, endMs: 30000),
      ], audioDuration: duration);

      expect(result.isValid, isTrue);
      expect(result.issues, isEmpty);
    });

    test('未提供音频时长时不做边界检查', () {
      final result = validate([line(startMs: 50000, endMs: 55000)]);

      expect(result.isValid, isTrue);
      expect(result.issues, isEmpty);
    });
  });

  group('带时间戳漏行与无时间戳末尾漏行（保守原则）', () {
    test('多重叠与零时长并发时，所有问题均明确提示，不静默裁剪', () {
      final result = validate([
        line(startMs: 0, endMs: 0), // 零时长
        line(startMs: 1000, endMs: 4000), // 与上一行无重叠，但上一行已零时长
        line(startMs: 3000, endMs: 6000), // 与第 2 行重叠
      ]);

      expect(result.isValid, isFalse);
      // 零时长 + 重叠，应至少 2 个问题，且都明确提示。
      expect(result.issues.length, greaterThanOrEqualTo(2));
      expect(result.issues.every((i) => i.message.isNotEmpty), isTrue);
      // 需校准的行都被标记，不静默删除或裁剪。
      expect(result.needsCalibration, contains(0));
      expect(result.needsCalibration, contains(2));
    });

    test('带冲突的末尾行不被静默裁剪，标记为需校准', () {
      final result = validate([
        line(startMs: 0, endMs: 4000),
        line(startMs: 5000, endMs: 5000), // 末尾零时长漏行
      ]);

      expect(result.isValid, isFalse);
      expect(
        result.issues.single.type,
        TimelineIssueType.zeroOrNegativeDuration,
      );
      expect(result.needsCalibration, {1});
    });
  });
}
