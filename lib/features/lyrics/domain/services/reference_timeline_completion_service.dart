import 'dart:math' as math;

import '../../../project/domain/models/lyric_document.dart';
import '../models/timing_provenance.dart';
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

  /// 时间的来源：参考时间戳、空隙插值或末尾估算。
  final LyricTimingProvenance timingProvenance;

  const ReferenceLineCompletionInsertion({
    required this.referenceIndex,
    required this.text,
    required this.insertBeforeAsrLineIndex,
    required this.startTime,
    required this.endTime,
    required this.requiresConfirmation,
    this.previousAsrLineIndex,
    this.nextAsrLineIndex,
    this.timingProvenance = LyricTimingProvenance.interpolated,
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

  /// 参考行时间的来源；没有可用参考时间时按插入位置再细分。
  static LyricTimingProvenance provenanceFor(LyricAlignmentEntry entry) =>
      _hasUsableReferenceTime(entry)
      ? LyricTimingProvenance.reference
      : LyricTimingProvenance.interpolated;

  ReferenceLineCompletionPlan buildPlan({
    required LyricDocument document,
    required LyricAlignmentResult alignment,
    Duration? audioDuration,
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
          audioDuration: audioDuration,
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
    Duration? audioDuration,
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

    final untimedEntries = group
        .where((entry) => !_hasUsableReferenceTime(entry))
        .toList(growable: false);
    final distribution = _distribute(
      weights: [
        for (final entry in untimedEntries) _textWeight(entry.referenceText),
      ],
      gapStart: gapStart,
      gapEnd: nextLine?.startTime,
    );
    final isTail = nextLine == null;

    final result = <ReferenceLineCompletionInsertion>[];
    var untimedCursor = 0;
    for (var entryIndex = 0; entryIndex < group.length; entryIndex++) {
      final entry = group[entryIndex];
      var start = Duration.zero;
      var end = Duration.zero;
      var provenance = provenanceFor(entry);
      var requiresConfirmation =
          hasUnmatchedInGap ||
          entry.structuralMismatch ||
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
        if (isTail) provenance = LyricTimingProvenance.estimatedTail;
      }

      // 音频末尾：能收尾就收尾，不能收尾时明确要求确认，由校验器提示。
      if (audioDuration != null && start >= audioDuration) {
        requiresConfirmation = true;
      } else if (audioDuration != null && end > audioDuration) {
        end = audioDuration;
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
          timingProvenance: provenance,
        ),
      );
    }
    return result;
  }

  /// 按文字视觉长度估算演唱时长权重：CJK/假名/谚文每字计 2，其它可见字符计 1。
  ///
  /// 只用于没有参考时间戳时在固定空隙内分配时长，不宣称与实际语速一致。
  static int _textWeight(String text) {
    var weight = 0;
    for (final rune in text.runes) {
      if (rune <= 0x20) continue;
      final isWide =
          (rune >= 0x3040 && rune <= 0x30FF) ||
          (rune >= 0x3400 && rune <= 0x9FFF) ||
          (rune >= 0xAC00 && rune <= 0xD7AF) ||
          (rune >= 0xFF01 && rune <= 0xFF60);
      if (isWide) {
        weight += 2;
      } else if (rune >= 0x21) {
        weight += 1;
      }
    }
    return weight < 1 ? 1 : weight;
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
    required List<int> weights,
    required Duration gapStart,
    required Duration? gapEnd,
  }) {
    final count = weights.length;
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
    final availableMicros = math.max(
      0,
      endBoundary.inMicroseconds - gapStart.inMicroseconds,
    );
    final totalWeight = weights.fold<int>(0, (sum, weight) => sum + weight);
    var cursorMicros = gapStart.inMicroseconds;
    var remainingMicros = availableMicros;

    for (var index = 0; index < count; index++) {
      final isLast = index == count - 1;
      var durationMicros = isLast
          ? remainingMicros
          : (availableMicros * weights[index]) ~/ math.max(1, totalWeight);
      if (durationMicros < minimumDuration.inMicroseconds) {
        durationMicros = minimumDuration.inMicroseconds;
        tooTight = true;
      }
      final startMicros = cursorMicros;
      var endMicros = startMicros + durationMicros;
      if (endMicros > endBoundary.inMicroseconds) {
        // 极窄空隙：保证最小时长，同时标记需确认，不静默重叠。
        endMicros = math.max(
          startMicros + minimumDuration.inMicroseconds,
          endBoundary.inMicroseconds,
        );
        tooTight = true;
      }
      remainingMicros = math.max(0, endBoundary.inMicroseconds - endMicros);
      cursorMicros = endMicros;
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
