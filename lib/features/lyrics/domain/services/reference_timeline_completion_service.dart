import '../../../project/domain/models/lyric_document.dart';
import 'lyric_alignment_service.dart';

/// 一条准备补进歌词文档的漏行。
///
/// 时间来源：
/// - 参考行本身带时间戳时优先使用参考时间；
/// - 纯文本参考按前后已匹配草稿行之间的空隙平均分配；
/// - 末尾漏行从上一行结束时间开始，每行默认 5 秒。
class ReferenceLineCompletionInsertion {
  /// 参考行在原始参考列表中的索引。
  final int referenceIndex;

  /// 要插入的参考文本。
  final String text;

  /// 插入到该 ASR 行之前；等于文档行数时表示追加到末尾。
  final int insertBeforeAsrLineIndex;

  final Duration startTime;
  final Duration endTime;

  /// 前后锚点之间夹着未匹配的 ASR 行，或时间空隙不足。
  ///
  /// 这通常意味着 ASR 把参考行合并/拆分成了别的行，直接插入可能产生重复，
  /// 因此默认不在逐行确认里勾选，需要用户显式确认。
  final bool requiresConfirmation;

  /// 前一个已匹配的 ASR 行索引；没有时为 null。
  final int? previousAsrLineIndex;

  /// 后一个已匹配的 ASR 行索引；没有时为 null。
  final int? nextAsrLineIndex;

  const ReferenceLineCompletionInsertion({
    required this.referenceIndex,
    required this.text,
    required this.insertBeforeAsrLineIndex,
    required this.startTime,
    required this.endTime,
    required this.requiresConfirmation,
    this.previousAsrLineIndex,
    this.nextAsrLineIndex,
  });
}

/// 当前对齐结果下所有漏行的插入计划。
class ReferenceLineCompletionPlan {
  final List<ReferenceLineCompletionInsertion> insertions;

  const ReferenceLineCompletionPlan({required this.insertions});

  static const empty = ReferenceLineCompletionPlan(insertions: []);

  bool get isEmpty => insertions.isEmpty;

  bool get isNotEmpty => insertions.isNotEmpty;

  /// 按参考行索引查找插入项；不存在时返回 null。
  ReferenceLineCompletionInsertion? forReferenceIndex(int referenceIndex) {
    for (final insertion in insertions) {
      if (insertion.referenceIndex == referenceIndex) return insertion;
    }
    return null;
  }
}

/// 为对齐结果中的漏行计算插入位置与推断时间，不修改任何输入。
///
/// 插入规则：
/// - 漏行插到后一个已匹配 ASR 行之前；没有后锚点时追加到末尾；
/// - 连续漏行保持参考行顺序；
/// - 两个锚点之间的空隙按漏行数平均分配，至少 10ms；
/// - 锚点之间出现未匹配 ASR 行、或空隙不足时标记 [requiresConfirmation]，
///   由逐行确认界面决定是否采纳。
class ReferenceTimelineCompletionService {
  static const Duration minimumDuration = Duration(milliseconds: 10);
  static const Duration defaultDuration = Duration(seconds: 5);

  const ReferenceTimelineCompletionService();

  ReferenceLineCompletionPlan buildPlan({
    required LyricDocument document,
    required LyricAlignmentResult alignment,
  }) {
    if (!alignment.hasMissingReferences) {
      return ReferenceLineCompletionPlan.empty;
    }

    final entries = alignment.entries;
    final unmatchedAsrIndices = alignment.unmatchedAsrIndices;
    final insertions = <ReferenceLineCompletionInsertion>[];

    LyricAlignmentEntry? previousMatched;
    var index = 0;
    while (index < entries.length) {
      final entry = entries[index];
      if (entry.asrLineIndex != null) {
        previousMatched = entry;
        index++;
        continue;
      }

      final groupStart = index;
      while (index < entries.length && entries[index].asrLineIndex == null) {
        index++;
      }
      final nextMatched = index < entries.length ? entries[index] : null;
      insertions.addAll(
        _buildGroup(
          group: entries.sublist(groupStart, index),
          previousMatched: previousMatched,
          nextMatched: nextMatched,
          document: document,
          unmatchedAsrIndices: unmatchedAsrIndices,
        ),
      );
    }

    return ReferenceLineCompletionPlan(insertions: insertions);
  }

  List<ReferenceLineCompletionInsertion> _buildGroup({
    required List<LyricAlignmentEntry> group,
    required LyricAlignmentEntry? previousMatched,
    required LyricAlignmentEntry? nextMatched,
    required LyricDocument document,
    required List<int> unmatchedAsrIndices,
  }) {
    final previousIndex = previousMatched?.asrLineIndex;
    final nextIndex = nextMatched?.asrLineIndex;
    final insertBefore = nextIndex ?? document.lines.length;
    final previousLine = previousIndex == null
        ? null
        : document.lines[previousIndex];
    final nextLine = nextIndex == null ? null : document.lines[nextIndex];

    final hasUnmatchedInGap = unmatchedAsrIndices.any(
      (index) =>
          (previousIndex == null || index > previousIndex) &&
          (nextIndex == null || index < nextIndex),
    );

    var gapStart = previousLine?.endTime ?? Duration.zero;
    if (gapStart.isNegative) gapStart = Duration.zero;
    if (previousLine != null && gapStart < previousLine.startTime) {
      gapStart = previousLine.startTime;
    }

    final untimedCount = group
        .where((entry) => !_hasUsableReferenceTime(entry))
        .length;
    final distribution = _distribute(
      count: untimedCount,
      gapStart: gapStart,
      gapEnd: nextLine?.startTime,
    );

    final result = <ReferenceLineCompletionInsertion>[];
    var untimedCursor = 0;
    for (var entryIndex = 0; entryIndex < group.length; entryIndex++) {
      final entry = group[entryIndex];
      final Duration start;
      final Duration end;
      var requiresConfirmation =
          hasUnmatchedInGap ||
          (previousLine == null && nextLine == null) ||
          distribution.tooTight;

      if (_hasUsableReferenceTime(entry)) {
        start = _nonNegative(entry.startTime!);
        final rawEnd = entry.endTime;
        if (rawEnd == null || rawEnd <= start) {
          end =
              _nextReferenceStart(group, entryIndex + 1, start) ??
              start + defaultDuration;
        } else {
          end = rawEnd;
        }
        if (previousLine != null && start < previousLine.startTime) {
          requiresConfirmation = true;
        }
        if (nextLine != null && start >= nextLine.startTime) {
          requiresConfirmation = true;
        }
      } else {
        final slot = distribution.slots[untimedCursor++];
        start = slot.start;
        end = slot.end;
      }

      result.add(
        ReferenceLineCompletionInsertion(
          referenceIndex: entry.referenceIndex,
          text: entry.referenceText,
          insertBeforeAsrLineIndex: insertBefore,
          startTime: start,
          endTime: end,
          requiresConfirmation: requiresConfirmation,
          previousAsrLineIndex: previousIndex,
          nextAsrLineIndex: nextIndex,
        ),
      );
    }
    return result;
  }

  static bool _hasUsableReferenceTime(LyricAlignmentEntry entry) =>
      entry.referenceHasTimestamp && entry.startTime != null;

  static Duration _nonNegative(Duration value) =>
      value.isNegative ? Duration.zero : value;

  static Duration? _nextReferenceStart(
    List<LyricAlignmentEntry> group,
    int fromIndex,
    Duration currentStart,
  ) {
    for (var index = fromIndex; index < group.length; index++) {
      final entry = group[index];
      final start = entry.startTime;
      if (entry.referenceHasTimestamp &&
          start != null &&
          start > currentStart) {
        return start;
      }
    }
    return null;
  }

  _TimeDistribution _distribute({
    required int count,
    required Duration gapStart,
    required Duration? gapEnd,
  }) {
    if (count == 0) {
      return const _TimeDistribution(slots: [], tooTight: false);
    }

    final slots = <({Duration start, Duration end})>[];
    if (gapEnd == null) {
      for (var index = 0; index < count; index++) {
        final start = gapStart + defaultDuration * index;
        slots.add((start: start, end: start + defaultDuration));
      }
      return _TimeDistribution(slots: slots, tooTight: false);
    }

    final endBoundary = gapEnd < gapStart ? gapStart : gapEnd;
    var tooTight = gapEnd <= gapStart;
    final availableMicros =
        endBoundary.inMicroseconds - gapStart.inMicroseconds;
    var perMicros = availableMicros ~/ count;
    if (perMicros < minimumDuration.inMicroseconds) {
      perMicros = minimumDuration.inMicroseconds;
      tooTight = true;
    }

    for (var index = 0; index < count; index++) {
      final startMicros = gapStart.inMicroseconds + perMicros * index;
      var endMicros = startMicros + perMicros;
      if (index == count - 1) {
        endMicros = endBoundary.inMicroseconds;
      }
      if (endMicros - startMicros < minimumDuration.inMicroseconds) {
        endMicros = startMicros + minimumDuration.inMicroseconds;
        tooTight = true;
      }
      slots.add((
        start: Duration(microseconds: startMicros),
        end: Duration(microseconds: endMicros),
      ));
    }

    return _TimeDistribution(slots: slots, tooTight: tooTight);
  }
}

class _TimeDistribution {
  final List<({Duration start, Duration end})> slots;
  final bool tooTight;

  const _TimeDistribution({required this.slots, required this.tooTight});
}
