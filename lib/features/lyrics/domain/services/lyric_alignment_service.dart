import 'dart:math' as math;

import '../../../project/domain/models/lyric_document.dart';
import '../models/reference_lyric_line.dart';

/// 单个参考行的对齐结果。
enum ReferenceLineAlignmentStatus {
  /// 归一化后与 ASR 行完全一致，不需要改文本。
  identical,

  /// 匹配到 ASR 行，相似度达到 autoReplaceThreshold，建议用参考文本纠正，可自动采纳。
  replace,

  /// 匹配到 ASR 行，但相似度低于 autoReplaceThreshold，属于低置信度匹配。
  /// 不应自动替换，需要用户在审核界面确认是否替换，还是作为漏行另行插入。
  lowConfidence,

  /// 匹配到 ASR 行，但存在另一条全局可行的 ASR 行序列对齐同样接近，
  /// 可能是 ASR 将两行合并或把一行拆成多行，需要用户定点确认是替换还是插入漏行。
  ambiguous,

  /// ASR 中没有对应行（漏识别），不要自动插入。
  missing,
}

/// 单条 ASR 行的对齐结果。
enum AsrLineAlignmentStatus {
  /// 有参考行对应且归一化文本一致。
  matched,

  /// 有参考行对应且相似度达标，可被纠正。
  toBeCorrected,

  /// 有参考行对应但相似度低于自动替换阈值，属于低置信度匹配。
  lowConfidence,

  /// 有参考行对应但存在另一条全局可行的序列对齐同样接近，可能是 ASR 合并/拆分。
  ambiguous,

  /// 参考歌词中没有对应行（多余识别/幻觉）。
  unmatched,
}

/// 一条结构差异诊断：参考与 ASR 可能是一对多或多对一。
enum StructuralAlignmentMismatchKind {
  /// 多条 ASR 行合起来才对应一条参考行（ASR 拆分）。
  mergedAsrLines,

  /// 一条 ASR 行对应多条参考行（ASR 合并）。
  splitAsrLine,
}

class StructuralAlignmentMismatch {
  final StructuralAlignmentMismatchKind kind;

  /// 涉及的参考行原始索引（按参考顺序）。
  final List<int> referenceIndices;

  /// 涉及的 ASR 行原始索引（按 ASR 顺序）。
  final List<int> asrLineIndices;

  final double similarity;

  const StructuralAlignmentMismatch({
    required this.kind,
    required this.referenceIndices,
    required this.asrLineIndices,
    required this.similarity,
  });

  String get message {
    final refs = referenceIndices.map((index) => index + 1).join('、');
    final asr = asrLineIndices.map((index) => index + 1).join('、');
    return switch (kind) {
      StructuralAlignmentMismatchKind.mergedAsrLines =>
        '参考第 $refs 行可能对应草稿第 $asr 行（ASR 把一行拆成了多行），需要确认后再处理。',
      StructuralAlignmentMismatchKind.splitAsrLine =>
        '草稿第 $asr 行可能对应参考第 $refs 行（ASR 把多行合并成了一行），需要确认后再处理。',
    };
  }
}

/// 参考行视角：这条参考歌词对应哪条 ASR 行、相似度多少、映射到什么时间。
class LyricAlignmentEntry {
  /// 在传入的参考行列表中的原始索引（空行已被跳过）。
  final int referenceIndex;

  /// 参考行原文（未归一化）。
  final String referenceText;

  /// 匹配到的 ASR 行在 `LyricDocument.lines` 中的索引；漏行时为 null。
  final int? asrLineIndex;

  /// 归一化后的字符级相似度（0..1）；漏行时为 0。
  final double similarity;

  /// 映射后的开始时间：带时间戳的参考行优先用自己的时间，否则用 ASR 行时间。
  final Duration? startTime;

  /// 映射后的结束时间，规则同上。
  final Duration? endTime;

  /// 这条参考行本身是否带时间戳。
  final bool referenceHasTimestamp;

  /// 是否为歧义匹配：存在另一条全局可行的序列对齐与本行得分接近。
  final bool ambiguous;

  /// 是否可能涉及一对多/多对一结构差异；这类行必须显式确认，
  /// 不能当作普通的一对一替换或自动补行。
  final bool structuralMismatch;

  final ReferenceLineAlignmentStatus status;

  const LyricAlignmentEntry({
    required this.referenceIndex,
    required this.referenceText,
    required this.asrLineIndex,
    required this.similarity,
    required this.startTime,
    required this.endTime,
    required this.referenceHasTimestamp,
    required this.ambiguous,
    this.structuralMismatch = false,
    required this.status,
  });
}

/// ASR 行视角：该行是否被参考歌词覆盖、是否需要纠正。
class AsrLineAlignment {
  /// 在 `LyricDocument.lines` 中的原始索引。
  final int asrLineIndex;

  /// 对应的参考行原始索引；没有对应时为 null。
  final int? referenceIndex;

  /// 与参考行的相似度；未匹配时为 0。
  final double similarity;

  /// 是否为歧义匹配：存在另一条全局可行的序列对齐与本行得分接近。
  final bool ambiguous;

  /// 是否可能属于一对多/多对一结构差异。
  final bool structuralMismatch;

  final AsrLineAlignmentStatus status;

  const AsrLineAlignment({
    required this.asrLineIndex,
    required this.referenceIndex,
    required this.similarity,
    required this.ambiguous,
    this.structuralMismatch = false,
    required this.status,
  });
}

class LyricAlignmentResult {
  /// 参考行视角的结果，按参考行顺序排列。
  final List<LyricAlignmentEntry> entries;

  /// ASR 行视角的结果，按 ASR 行顺序排列。
  final List<AsrLineAlignment> asrLines;

  /// 一对多/多对一结构差异诊断，供审核界面单独提示。
  final List<StructuralAlignmentMismatch> structuralMismatches;

  const LyricAlignmentResult({
    required this.entries,
    required this.asrLines,
    this.structuralMismatches = const [],
  });

  /// 在 ASR 中找不到对应行的参考行索引。
  List<int> get missingReferenceIndices => [
    for (final entry in entries)
      if (entry.status == ReferenceLineAlignmentStatus.missing)
        entry.referenceIndex,
  ];

  /// 没有被任何参考行覆盖的 ASR 行索引。
  List<int> get unmatchedAsrIndices => [
    for (final line in asrLines)
      if (line.status == AsrLineAlignmentStatus.unmatched) line.asrLineIndex,
  ];

  /// 低置信或歧义匹配的参考行索引。
  List<int> get uncertainReferenceIndices => [
    for (final entry in entries)
      if (entry.status == ReferenceLineAlignmentStatus.lowConfidence ||
          entry.status == ReferenceLineAlignmentStatus.ambiguous ||
          entry.structuralMismatch)
        entry.referenceIndex,
  ];

  bool get hasMissingReferences => missingReferenceIndices.isNotEmpty;

  bool get hasUnmatchedAsrLines => unmatchedAsrIndices.isNotEmpty;

  bool get hasStructuralMismatches => structuralMismatches.isNotEmpty;
}

/// 把 ASR 歌词草稿与用户提供的参考歌词做行级序列对齐。
///
/// 只做纯计算，不修改任何输入；应用纠正、写 metadata、备份由上层负责。
///
/// 打分模型（不是简单的相似度累加）：
/// - 配对得分 = 相似度 - [matchBias]；只有相似度严格高于 [matchBias] 的配对
///   才会带来正收益；
/// - 跳过一次参考行或一次 ASR 行的代价为 [gapPenalty]（默认 0，仅用于打破平局）；
/// - 因此一条弱匹配（相似度接近 [minimumPairSimilarity]）会输给"跳过参考行 +
///   跳过 ASR 行"两条 gap，被归类为漏行/多余行，而不是被强行替换；
/// - 精确匹配和高相似度匹配的收益明显高于两条 gap，仍会优先配对。
///
/// 对齐仍然全局保序（Needleman-Wunsch）。歧义判定使用前向/后向 DP 的全局
/// 证据：如果同一参考行（或 ASR 行）换成另一条可行配对后，整段序列的最优
/// 得分仍然接近，才标记为歧义，而不是只看单行相似度。
class LyricAlignmentService {
  /// 允许进入配对候选的最低相似度。低于该值直接视为不可配对。
  final double minimumPairSimilarity;

  /// 配对收益偏移：配对得分 = 相似度 - [matchBias]。
  ///
  /// 默认 0.7，意味着相似度 0.7 以下的弱匹配会输给两条 gap；0.8 以上的
  /// 高置信匹配仍有明显正收益。
  final double matchBias;

  /// 跳过一行的分数代价（正数或 0）。默认 0，仅用于打破完全平局。
  final double gapPenalty;

  /// 自动替换阈值；与 [ReferenceAlignmentApplier.minimumSimilarity] 共用同一语义。
  static const double defaultAutoReplaceThreshold = 0.8;

  const LyricAlignmentService({
    this.minimumPairSimilarity = 0.5,
    this.matchBias = 0.7,
    this.gapPenalty = 0,
  }) : assert(minimumPairSimilarity > 0 && minimumPairSimilarity <= 1),
       assert(matchBias >= 0 && matchBias <= 1),
       assert(gapPenalty >= 0);

  static const double _epsilon = 1e-9;

  double get _effectivePairFloor => math.max(minimumPairSimilarity, matchBias);

  bool _canPair(double similarity) =>
      similarity >= minimumPairSimilarity && similarity > matchBias;

  LyricAlignmentResult align({
    required LyricDocument document,
    required List<ReferenceLyricLine> referenceLines,
    double autoReplaceThreshold = defaultAutoReplaceThreshold,
    double ambiguityScoreMargin = 0.05,
  }) {
    assert(autoReplaceThreshold >= 0 && autoReplaceThreshold <= 1);
    assert(ambiguityScoreMargin >= 0);

    final references = <_PreparedLine>[];
    for (var index = 0; index < referenceLines.length; index++) {
      final normalized = normalizeLine(referenceLines[index].text);
      if (normalized.isEmpty) continue;
      references.add(
        _PreparedLine(originalIndex: index, normalized: normalized),
      );
    }

    final asrLines = <_PreparedLine>[];
    for (var index = 0; index < document.lines.length; index++) {
      final normalized = normalizeLine(document.lines[index].text);
      if (normalized.isEmpty) continue;
      asrLines.add(_PreparedLine(originalIndex: index, normalized: normalized));
    }

    final referenceCount = references.length;
    final asrCount = asrLines.length;
    final similarities = _buildSimilarityMatrix(references, asrLines);

    final refToAsr = List<int?>.filled(referenceCount, null);
    final asrToRef = List<int?>.filled(asrCount, null);
    List<List<double>>? forward;

    if (referenceCount > 0 && asrCount > 0) {
      forward = _fillForward(
        similarities: similarities,
        referenceCount: referenceCount,
        asrCount: asrCount,
      );
      _traceback(
        forward: forward,
        similarities: similarities,
        referenceCount: referenceCount,
        asrCount: asrCount,
        refToAsr: refToAsr,
        asrToRef: asrToRef,
      );
    }

    // 歧义：用前向/后向 DP 的全局得分判断"换一条可行配对是否同样合理"。
    final ambiguousReferences = <int>{};
    final ambiguousAsrLines = <int>{};
    if (forward != null && referenceCount > 0 && asrCount > 0) {
      final backward = _fillBackward(
        similarities: similarities,
        referenceCount: referenceCount,
        asrCount: asrCount,
      );
      final optimal = forward[referenceCount][asrCount];

      for (var r = 0; r < referenceCount; r++) {
        final matched = refToAsr[r];
        if (matched == null) continue;
        final top = _topTwoForReference(
          r: r,
          forward: forward,
          backward: backward,
          similarities: similarities,
          asrCount: asrCount,
        );
        final competitor = top.firstIndex == matched
            ? top.secondScore
            : top.firstScore;
        if (_isCompetitive(optimal, competitor, ambiguityScoreMargin)) {
          ambiguousReferences.add(r);
        }
      }

      for (var a = 0; a < asrCount; a++) {
        final matched = asrToRef[a];
        if (matched == null) continue;
        final top = _topTwoForAsrLine(
          a: a,
          forward: forward,
          backward: backward,
          similarities: similarities,
          referenceCount: referenceCount,
        );
        final competitor = top.firstIndex == matched
            ? top.secondScore
            : top.firstScore;
        if (_isCompetitive(optimal, competitor, ambiguityScoreMargin)) {
          ambiguousAsrLines.add(a);
        }
      }
    }

    // 结构差异：一对多/多对一不做隐式多行合并，只标记为需确认。
    final structural = _detectStructuralMismatches(
      references: references,
      asrLines: asrLines,
      refToAsr: refToAsr,
      asrToRef: asrToRef,
    );
    final structuralReferenceIndices = <int>{};
    final structuralAsrIndices = <int>{};
    for (final mismatch in structural) {
      structuralReferenceIndices.addAll(mismatch.referenceIndices);
      structuralAsrIndices.addAll(mismatch.asrLineIndices);
    }

    final entries = <LyricAlignmentEntry>[];
    for (var r = 0; r < referenceCount; r++) {
      final preparedReference = references[r];
      final reference = referenceLines[preparedReference.originalIndex];
      final matchedAsr = refToAsr[r];
      final referenceHasTimestamp = reference.hasTimestamp;
      final structuralMismatch = structuralReferenceIndices.contains(
        preparedReference.originalIndex,
      );

      if (matchedAsr == null) {
        entries.add(
          LyricAlignmentEntry(
            referenceIndex: preparedReference.originalIndex,
            referenceText: reference.text.trim(),
            asrLineIndex: null,
            similarity: 0,
            startTime: referenceHasTimestamp
                ? _nonNegative(reference.startTime)
                : null,
            endTime: referenceHasTimestamp
                ? _nonNegative(reference.endTime)
                : null,
            referenceHasTimestamp: referenceHasTimestamp,
            ambiguous: false,
            structuralMismatch: structuralMismatch,
            status: ReferenceLineAlignmentStatus.missing,
          ),
        );
        continue;
      }

      final asr = asrLines[matchedAsr];
      final asrLine = document.lines[asr.originalIndex];
      final identical = preparedReference.normalized == asr.normalized;
      final similarity = similarities[r][matchedAsr];
      final ambiguous = ambiguousReferences.contains(r);

      final status = identical
          ? ReferenceLineAlignmentStatus.identical
          : ambiguous
          ? ReferenceLineAlignmentStatus.ambiguous
          : similarity < autoReplaceThreshold
          ? ReferenceLineAlignmentStatus.lowConfidence
          : ReferenceLineAlignmentStatus.replace;
      entries.add(
        LyricAlignmentEntry(
          referenceIndex: preparedReference.originalIndex,
          referenceText: reference.text.trim(),
          asrLineIndex: asr.originalIndex,
          similarity: similarity,
          startTime: referenceHasTimestamp
              ? _nonNegative(reference.startTime)
              : asrLine.startTime,
          endTime: referenceHasTimestamp
              ? _nonNegative(reference.endTime)
              : asrLine.endTime,
          referenceHasTimestamp: referenceHasTimestamp,
          ambiguous: ambiguous,
          structuralMismatch: structuralMismatch,
          status: status,
        ),
      );
    }

    final asrResults = <AsrLineAlignment>[];
    for (var a = 0; a < asrCount; a++) {
      final preparedAsr = asrLines[a];
      final matchedReference = asrToRef[a];
      final structuralMismatch = structuralAsrIndices.contains(
        preparedAsr.originalIndex,
      );
      if (matchedReference == null) {
        asrResults.add(
          AsrLineAlignment(
            asrLineIndex: preparedAsr.originalIndex,
            referenceIndex: null,
            similarity: 0,
            ambiguous: false,
            structuralMismatch: structuralMismatch,
            status: AsrLineAlignmentStatus.unmatched,
          ),
        );
        continue;
      }

      final reference = references[matchedReference];
      final identical = reference.normalized == preparedAsr.normalized;
      final similarity = similarities[matchedReference][a];
      final asrAmbiguous = ambiguousAsrLines.contains(a);

      final asrStatus = identical
          ? AsrLineAlignmentStatus.matched
          : asrAmbiguous
          ? AsrLineAlignmentStatus.ambiguous
          : similarity < autoReplaceThreshold
          ? AsrLineAlignmentStatus.lowConfidence
          : AsrLineAlignmentStatus.toBeCorrected;
      asrResults.add(
        AsrLineAlignment(
          asrLineIndex: preparedAsr.originalIndex,
          referenceIndex: reference.originalIndex,
          similarity: similarity,
          ambiguous: asrAmbiguous,
          structuralMismatch: structuralMismatch,
          status: asrStatus,
        ),
      );
    }

    return LyricAlignmentResult(
      entries: entries,
      asrLines: asrResults,
      structuralMismatches: structural,
    );
  }

  /// 全角转半角、去空白与标点、大小写折叠后的文本。
  ///
  /// 空行或纯标点行会得到空字符串。
  static String normalizeLine(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      var code = rune;
      if (code >= 0xFF01 && code <= 0xFF5E) {
        code -= 0xFEE0;
      } else if (code == 0x3000) {
        code = 0x20;
      }
      if (_isIgnorable(code)) continue;
      buffer.write(String.fromCharCode(code).toLowerCase());
    }
    return buffer.toString();
  }

  /// 两段文本归一化后的字符级相似度（0..1）。
  static double lineSimilarity(String a, String b) {
    final left = normalizeLine(a).runes.toList(growable: false);
    final right = normalizeLine(b).runes.toList(growable: false);
    return _similarity(left, right);
  }

  static bool _isIgnorable(int code) {
    if (code <= 0x20) return true;
    // ASCII 标点与符号（全角标点已在上方折叠为 ASCII）。
    if (code >= 0x21 && code <= 0x2F) return true;
    if (code >= 0x3A && code <= 0x40) return true;
    if (code >= 0x5B && code <= 0x60) return true;
    if (code >= 0x7B && code <= 0x7E) return true;
    // 常用中文/西文标点、引号、破折号、省略号等。
    if (code >= 0x2000 && code <= 0x206F) return true;
    // CJK 符号与标点。
    if (code >= 0x3000 && code <= 0x303F) return true;
    // 全角符号区中未被上面折叠覆盖的部分。
    if (code >= 0xFF00 && code <= 0xFF0F) return true;
    // 间隔号、音符等歌词装饰符号。
    if (code == 0x00B7 || code == 0x266A || code == 0x266B) return true;
    return false;
  }

  List<List<double>> _buildSimilarityMatrix(
    List<_PreparedLine> references,
    List<_PreparedLine> asrLines,
  ) {
    final matrix = List<List<double>>.generate(
      references.length,
      (_) => List<double>.filled(asrLines.length, 0),
      growable: false,
    );
    final floor = _effectivePairFloor;
    for (var r = 0; r < references.length; r++) {
      for (var a = 0; a < asrLines.length; a++) {
        final left = references[r];
        final right = asrLines[a];
        if (left.normalized == right.normalized) {
          matrix[r][a] = 1;
          continue;
        }
        // 长度差已经决定了相似度上限低于可配对阈值，提前跳过。
        final maxLength = math.max(left.runes.length, right.runes.length);
        if (maxLength > 0) {
          final lengthGap = (left.runes.length - right.runes.length).abs();
          if (lengthGap / maxLength > 1 - floor) continue;
        }
        final similarity = _similarity(left.runes, right.runes);
        if (similarity >= floor) matrix[r][a] = similarity;
      }
    }
    return matrix;
  }

  List<List<double>> _fillForward({
    required List<List<double>> similarities,
    required int referenceCount,
    required int asrCount,
  }) {
    final dp = List<List<double>>.generate(
      referenceCount + 1,
      (_) => List<double>.filled(asrCount + 1, 0),
      growable: false,
    );
    for (var r = 1; r <= referenceCount; r++) {
      dp[r][0] = dp[r - 1][0] - gapPenalty;
    }
    for (var a = 1; a <= asrCount; a++) {
      dp[0][a] = dp[0][a - 1] - gapPenalty;
    }

    for (var r = 1; r <= referenceCount; r++) {
      for (var a = 1; a <= asrCount; a++) {
        var best = dp[r - 1][a] - gapPenalty;
        final skipAsr = dp[r][a - 1] - gapPenalty;
        if (skipAsr > best) best = skipAsr;

        final similarity = similarities[r - 1][a - 1];
        if (_canPair(similarity)) {
          final pair = dp[r - 1][a - 1] + similarity - matchBias;
          if (pair > best) best = pair;
        }
        dp[r][a] = best;
      }
    }
    return dp;
  }

  List<List<double>> _fillBackward({
    required List<List<double>> similarities,
    required int referenceCount,
    required int asrCount,
  }) {
    final dp = List<List<double>>.generate(
      referenceCount + 1,
      (_) => List<double>.filled(asrCount + 1, 0),
      growable: false,
    );
    for (var r = referenceCount - 1; r >= 0; r--) {
      dp[r][asrCount] = dp[r + 1][asrCount] - gapPenalty;
    }
    for (var a = asrCount - 1; a >= 0; a--) {
      dp[referenceCount][a] = dp[referenceCount][a + 1] - gapPenalty;
    }
    for (var r = referenceCount - 1; r >= 0; r--) {
      for (var a = asrCount - 1; a >= 0; a--) {
        var best = dp[r + 1][a] - gapPenalty;
        final skipAsr = dp[r][a + 1] - gapPenalty;
        if (skipAsr > best) best = skipAsr;

        final similarity = similarities[r][a];
        if (_canPair(similarity)) {
          final pair = similarity - matchBias + dp[r + 1][a + 1];
          if (pair > best) best = pair;
        }
        dp[r][a] = best;
      }
    }
    return dp;
  }

  ({int? firstIndex, double firstScore, double? secondScore})
  _topTwoForReference({
    required int r,
    required List<List<double>> forward,
    required List<List<double>> backward,
    required List<List<double>> similarities,
    required int asrCount,
  }) {
    int? firstIndex;
    var firstScore = double.negativeInfinity;
    double? secondScore;
    for (var a = 0; a < asrCount; a++) {
      final similarity = similarities[r][a];
      if (!_canPair(similarity)) continue;
      final score =
          forward[r][a] + similarity - matchBias + backward[r + 1][a + 1];
      if (score > firstScore + _epsilon) {
        if (firstIndex != null) secondScore = firstScore;
        firstScore = score;
        firstIndex = a;
      } else if (secondScore == null || score > secondScore + _epsilon) {
        secondScore = score;
      }
    }
    return (
      firstIndex: firstIndex,
      firstScore: firstIndex == null ? 0 : firstScore,
      secondScore: secondScore,
    );
  }

  ({int? firstIndex, double firstScore, double? secondScore})
  _topTwoForAsrLine({
    required int a,
    required List<List<double>> forward,
    required List<List<double>> backward,
    required List<List<double>> similarities,
    required int referenceCount,
  }) {
    int? firstIndex;
    var firstScore = double.negativeInfinity;
    double? secondScore;
    for (var r = 0; r < referenceCount; r++) {
      final similarity = similarities[r][a];
      if (!_canPair(similarity)) continue;
      final score =
          forward[r][a] + similarity - matchBias + backward[r + 1][a + 1];
      if (score > firstScore + _epsilon) {
        if (firstIndex != null) secondScore = firstScore;
        firstScore = score;
        firstIndex = r;
      } else if (secondScore == null || score > secondScore + _epsilon) {
        secondScore = score;
      }
    }
    return (
      firstIndex: firstIndex,
      firstScore: firstIndex == null ? 0 : firstScore,
      secondScore: secondScore,
    );
  }

  static bool _isCompetitive(
    double optimal,
    double? competitor,
    double margin,
  ) {
    if (competitor == null || competitor == double.negativeInfinity) {
      return false;
    }
    return optimal - competitor <= margin + _epsilon;
  }

  void _traceback({
    required List<List<double>> forward,
    required List<List<double>> similarities,
    required int referenceCount,
    required int asrCount,
    required List<int?> refToAsr,
    required List<int?> asrToRef,
  }) {
    var r = referenceCount;
    var a = asrCount;
    while (r > 0 || a > 0) {
      if (r > 0 && a > 0) {
        final similarity = similarities[r - 1][a - 1];
        if (_canPair(similarity)) {
          final pair = forward[r - 1][a - 1] + similarity - matchBias;
          if ((forward[r][a] - pair).abs() < _epsilon) {
            refToAsr[r - 1] = a - 1;
            asrToRef[a - 1] = r - 1;
            r--;
            a--;
            continue;
          }
        }
      }

      if (r > 0 &&
          (a == 0 ||
              (forward[r][a] - (forward[r - 1][a] - gapPenalty)).abs() <
                  _epsilon)) {
        r--;
        continue;
      }

      a--;
    }
  }

  List<StructuralAlignmentMismatch> _detectStructuralMismatches({
    required List<_PreparedLine> references,
    required List<_PreparedLine> asrLines,
    required List<int?> refToAsr,
    required List<int?> asrToRef,
  }) {
    const maxWindow = 3;
    final mismatches = <StructuralAlignmentMismatch>[];
    final seenKeys = <String>{};

    // 多条未匹配 ASR 行合起来接近一条漏掉的参考行。
    for (var r = 0; r < references.length; r++) {
      if (refToAsr[r] != null) continue;
      final reference = references[r];
      double? bestSimilarity;
      List<int>? bestAsr;
      for (var start = 0; start < asrLines.length; start++) {
        final runes = <int>[];
        for (var length = 1; length <= maxWindow; length++) {
          final index = start + length - 1;
          if (index >= asrLines.length) break;
          if (asrToRef[index] != null) break;
          runes.addAll(asrLines[index].runes);
          if (length < 2) continue;
          final similarity = _similarity(reference.runes, runes);
          if (similarity < minimumPairSimilarity) continue;
          if (bestSimilarity == null || similarity > bestSimilarity) {
            bestSimilarity = similarity;
            bestAsr = [
              for (var i = start; i <= index; i++) asrLines[i].originalIndex,
            ];
          }
        }
      }
      if (bestAsr != null && bestSimilarity != null) {
        final key = 'm:${reference.originalIndex}:${bestAsr.join(',')}';
        if (seenKeys.add(key)) {
          mismatches.add(
            StructuralAlignmentMismatch(
              kind: StructuralAlignmentMismatchKind.mergedAsrLines,
              referenceIndices: [reference.originalIndex],
              asrLineIndices: bestAsr,
              similarity: bestSimilarity,
            ),
          );
        }
      }
    }

    // 多条漏掉的参考行合起来接近一条未匹配的 ASR 行。
    for (var a = 0; a < asrLines.length; a++) {
      if (asrToRef[a] != null) continue;
      final asr = asrLines[a];
      double? bestSimilarity;
      List<int>? bestReference;
      for (var start = 0; start < references.length; start++) {
        final runes = <int>[];
        for (var length = 1; length <= maxWindow; length++) {
          final index = start + length - 1;
          if (index >= references.length) break;
          if (refToAsr[index] != null) break;
          runes.addAll(references[index].runes);
          if (length < 2) continue;
          final similarity = _similarity(asr.runes, runes);
          if (similarity < minimumPairSimilarity) continue;
          if (bestSimilarity == null || similarity > bestSimilarity) {
            bestSimilarity = similarity;
            bestReference = [
              for (var i = start; i <= index; i++) references[i].originalIndex,
            ];
          }
        }
      }
      if (bestReference != null && bestSimilarity != null) {
        final key = 's:${asr.originalIndex}:${bestReference.join(',')}';
        if (seenKeys.add(key)) {
          mismatches.add(
            StructuralAlignmentMismatch(
              kind: StructuralAlignmentMismatchKind.splitAsrLine,
              referenceIndices: bestReference,
              asrLineIndices: [asr.originalIndex],
              similarity: bestSimilarity,
            ),
          );
        }
      }
    }

    mismatches.sort((a, b) {
      final left = a.referenceIndices.isEmpty ? 0 : a.referenceIndices.first;
      final right = b.referenceIndices.isEmpty ? 0 : b.referenceIndices.first;
      return left.compareTo(right);
    });
    return mismatches;
  }

  static double _similarity(List<int> a, List<int> b) {
    if (a.isEmpty && b.isEmpty) return 1;
    if (a.isEmpty || b.isEmpty) return 0;
    if (a.length == b.length) {
      var same = true;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) {
          same = false;
          break;
        }
      }
      if (same) return 1;
    }

    var previous = List<int>.generate(b.length + 1, (index) => index);
    var current = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      current[0] = i;
      final aCode = a[i - 1];
      for (var j = 1; j <= b.length; j++) {
        final cost = aCode == b[j - 1] ? 0 : 1;
        final deletion = previous[j] + 1;
        final insertion = current[j - 1] + 1;
        final substitution = previous[j - 1] + cost;
        current[j] = _min3(deletion, insertion, substitution);
      }
      final swap = previous;
      previous = current;
      current = swap;
    }

    final distance = previous[b.length];
    return 1 - distance / math.max(a.length, b.length);
  }

  static int _min3(int a, int b, int c) {
    var min = a;
    if (b < min) min = b;
    if (c < min) min = c;
    return min;
  }

  static Duration? _nonNegative(Duration? value) {
    if (value == null) return null;
    return value.isNegative ? Duration.zero : value;
  }
}

class _PreparedLine {
  final int originalIndex;
  final String normalized;
  final List<int> runes;

  _PreparedLine({required this.originalIndex, required this.normalized})
    : runes = normalized.runes.toList(growable: false);
}
