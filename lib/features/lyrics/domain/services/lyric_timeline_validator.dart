import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

/// 歌词时间轴单行问题类型。
enum TimelineIssueType {
  /// 开始时间为负。
  negativeStart,

  /// 结束时间不晚于开始时间（零或负时长），无法可靠确定展示区间。
  zeroOrNegativeDuration,

  /// 与前一行重叠：本行开始时间早于前一行结束时间。
  overlapsPrevious,

  /// 与下一行重叠：本行结束时间晚于下一行开始时间。
  overlapsNext,

  /// 与下一行之间空隙极短，可能产生不可靠的切换。
  extremelyShortGap,

  /// 开始时间超出音频总时长。
  beyondAudioDuration,

  /// 结束时间超出音频总时长。
  endBeyondAudioDuration,
}

/// 歌词时间轴单行问题记录。
class TimelineIssue {
  /// 出现问题的行索引。
  final int lineIndex;

  /// 问题类型。
  final TimelineIssueType type;

  /// 人类可读的中文问题说明，可直接展示在 UI 中。
  final String message;

  /// 是否可由规则自动修复；为 false 时应让用户定点校准。
  final bool canAutoFix;

  const TimelineIssue({
    required this.lineIndex,
    required this.type,
    required this.message,
    this.canAutoFix = false,
  });
}

/// 歌词时间轴验证结果。
class LyricTimelineValidationResult {
  /// 时间轴是否无明显冲突（仅作为参考，UI 应逐条展示 issues）。
  final bool isValid;

  /// 所有检测到的问题，按行索引升序排列。
  final List<TimelineIssue> issues;

  /// 建议用户定点校准的行索引（无法可靠推断、或不应静默裁剪的行）。
  final Set<int> needsCalibration;

  const LyricTimelineValidationResult({
    required this.isValid,
    required this.issues,
    this.needsCalibration = const {},
  });
}

/// 歌词时间轴正确性校验器。
///
/// 纯 Dart、无 Flutter 依赖，不修改任何输入。仅做只读检测，冲突
/// 时明确提示，不擅自删除旧歌词、不静默裁剪相邻行；确实不能
/// 推断时，由调用方让用户进行定点校准。
///
/// 检查项：
/// - 负开始时间；
/// - 零或负时长（end <= start）；
/// - 与前后行重叠；
/// - 极短空隙；
/// - 超出音频总时长（尾部插入边界）。
///
/// [minGapMs] 为判定"极短空隙"的阈值，默认 100 毫秒。
class LyricTimelineValidator {
  /// 相邻行之间判定为极短空隙的最小间隔（毫秒）。
  static const Duration defaultMinGap = Duration(milliseconds: 100);

  /// 零时长行的最小可接受时长，低于此值按零时长处理。
  static const Duration minimumDuration = Duration(milliseconds: 10);

  final Duration minGap;

  const LyricTimelineValidator({this.minGap = defaultMinGap});

  /// 校验歌词行时间轴。
  ///
  /// [lines] 应按开始时间排序（调用方可先行排序，本校验器不排序，
  /// 以免静默改变用户顺序）。
  /// [audioDuration] 为音频总时长，提供后会对尾部插入做时长边界检查；
  /// 未提供时不做音频边界检查。
  LyricTimelineValidationResult validate({
    required List<LyricLine> lines,
    Duration? audioDuration,
  }) {
    final issues = <TimelineIssue>[];
    final needsCalibration = <int>{};

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];

      // 负开始时间。
      if (line.startTime.isNegative) {
        issues.add(
          TimelineIssue(
            lineIndex: index,
            type: TimelineIssueType.negativeStart,
            message: '第 ${index + 1} 行开始时间为负，无法定位。',
            canAutoFix: true,
          ),
        );
        needsCalibration.add(index);
        continue;
      }

      // 零或负时长。
      if (line.endTime <= line.startTime) {
        issues.add(
          TimelineIssue(
            lineIndex: index,
            type: TimelineIssueType.zeroOrNegativeDuration,
            message: '第 ${index + 1} 行结束时间不晚于开始时间（零或负时长），无法可靠展示，需定点校准。',
            canAutoFix: false,
          ),
        );
        needsCalibration.add(index);
        continue;
      }

      // 与前一行重叠。
      if (index > 0) {
        final previous = lines[index - 1];
        if (line.startTime < previous.endTime) {
          issues.add(
            TimelineIssue(
              lineIndex: index,
              type: TimelineIssueType.overlapsPrevious,
              message: '第 ${index + 1} 行开始时间早于第 $index 行结束时间，两行重叠，需定点校准。',
              canAutoFix: false,
            ),
          );
          needsCalibration.add(index);
        }
      }

      // 与下一行重叠。
      if (index < lines.length - 1) {
        final next = lines[index + 1];
        if (line.endTime > next.startTime) {
          issues.add(
            TimelineIssue(
              lineIndex: index,
              type: TimelineIssueType.overlapsNext,
              message: '第 ${index + 1} 行结束时间晚于第 ${index + 2} 行开始时间，两行重叠，需定点校准。',
              canAutoFix: false,
            ),
          );
          needsCalibration.add(index);
        }
      }

      // 极短空隙。
      if (index < lines.length - 1) {
        final next = lines[index + 1];
        final gap = next.startTime - line.endTime;
        if (gap > Duration.zero && gap < minGap) {
          issues.add(
            TimelineIssue(
              lineIndex: index,
              type: TimelineIssueType.extremelyShortGap,
              message:
                  '第 ${index + 1} 行与第 ${index + 2} 行之间空隙极短（${gap.inMilliseconds} ms），切换可能不可靠。',
              canAutoFix: true,
            ),
          );
        }
      }

      // 音频时长边界。
      if (audioDuration != null) {
        if (line.startTime >= audioDuration) {
          issues.add(
            TimelineIssue(
              lineIndex: index,
              type: TimelineIssueType.beyondAudioDuration,
              message: '第 ${index + 1} 行开始时间已超出音频总时长，需定点校准。',
              canAutoFix: false,
            ),
          );
          needsCalibration.add(index);
        } else if (line.endTime > audioDuration) {
          issues.add(
            TimelineIssue(
              lineIndex: index,
              type: TimelineIssueType.endBeyondAudioDuration,
              message: '第 ${index + 1} 行结束时间超出音频总时长，建议收尾到音频末尾。',
              canAutoFix: true,
            ),
          );
        }
      }
    }

    return LyricTimelineValidationResult(
      isValid: issues.isEmpty,
      issues: issues..sort((a, b) => a.lineIndex.compareTo(b.lineIndex)),
      needsCalibration: needsCalibration,
    );
  }
}
