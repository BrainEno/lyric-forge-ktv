import 'dart:math' as math;

import '../../../project/domain/models/lyric_document.dart';
import '../models/reference_lyric_line.dart';

/// 单个参考行的对齐结果。
enum ReferenceLineAlignmentStatus {
  /// 归一化后与 ASR 行完全一致，不需要改文本。
  identical,

  /// 匹配到 ASR 行，相似度达到[autoReplaceThreshold]，建议用参考文本纠正，可自动采纳。
  replace,

  /// 匹配到 ASR 行，但相似度低于[autoReplaceThreshold]，属于低置信度匹配。
  /// 不应自动替换，需要用户在审核界面确认是否替换，还是作为漏行另行插入。
  lowConfidence,

  /// 匹配到 ASR 行，但存在另一条 ASR 行的相似度接近（在[ambiguityMargin]之内），
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

  /// 有参考行对应但存在歧义候选，可能是 ASR 合并/拆分。
  ambiguous,

  /// 参考歌词中没有对应行（多余识别/幻觉）。
  unmatched,
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

  /// 是否为歧义匹配：存在另一条 ASR 行与本参考行的相似度接近（在
  /// [ambiguityMargin] 之内），可能是 ASR 合并/拆分。
  final bool ambiguous;

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

  /// 是否为歧义匹配：存在另一条参考行与本 ASR 行的相似度接近。
  final bool ambiguous;

  final AsrLineAlignmentStatus status;

  const AsrLineAlignment({
    required this.asrLineIndex,
    required this.referenceIndex,
    required this.similarity,
    required this.ambiguous,
    required this.status,
  });
}

class LyricAlignmentResult {
  /// 参考行视角的结果，按参考行顺序排列。
  final List<LyricAlignmentEntry> entries;

  /// ASR 行视角的结果，按 ASR 行顺序排列。
  final List<AsrLineAlignment> asrLines;

  const LyricAlignmentResult({required this.entries, required this.asrLines});

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

  bool get hasMissingReferences => missingReferenceIndices.isNotEmpty;

  bool get hasUnmatchedAsrLines => unmatchedAsrIndices.isNotEmpty;
}

/// 把 ASR 歌词草稿与用户提供的参考歌词做行级序列对齐。
///
/// 只做纯计算，不修改任何输入；应用纠正、写 metadata、备份由上层负责。
///
/// 算法：
/// - 文本归一化：全角转半角、去空白/标点/符号、大小写折叠；
/// - 相似度：归一化文本的字符级 Levenshtein 比率；
/// - 对齐：全局 Needleman-Wunsch，单行配对得分 = 相似度，跳过一行的代价 =
///   [gapPenalty]；相似度低于 [minimumPairSimilarity] 的行不允许配对；
/// - 重复段（副歌）依靠整段序列顺序约束，不会把第二次副歌错配到第一次；
/// - 空行（归一化后为空）不参与对齐，也不出现在结果中；
/// - 带时间戳的参考行直接采用自己的时间，未带时间戳的行采用匹配到的 ASR 行时间；
/// - 漏行的参考行不自动插入，只标记为 [ReferenceLineAlignmentStatus.missing]。
class LyricAlignmentService {
  /// 低于该相似度不允许配对。ASR 错字通常仍高于该值。
  final double minimumPairSimilarity;

  /// 跳过一行的得分代价（正数）。
  final double gapPenalty;

  const LyricAlignmentService({
    this.minimumPairSimilarity = 0.5,
    this.gapPenalty = 0.35,
  }) : assert(minimumPairSimilarity > 0 && minimumPairSimilarity <= 1),
       assert(gapPenalty > 0);

  static const double _epsilon = 1e-9;

  LyricAlignmentResult align({
    required LyricDocument document,
    required List<ReferenceLyricLine> referenceLines,
    double autoReplaceThreshold = 0.8,
    double ambiguityMargin = 0.15,
  }) {
    assert(autoReplaceThreshold >= 0 && autoReplaceThreshold <= 1);
    assert(ambiguityMargin >= 0 && ambiguityMargin <= 1);
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

    // refToAsr[r] = 匹配到的 asr 预处理数组下标。
    final refToAsr = List<int?>.filled(referenceCount, null);
    final asrToRef = List<int?>.filled(asrCount, null);

    if (referenceCount > 0 && asrCount > 0) {
      _traceback(
        similarities: similarities,
        referenceCount: referenceCount,
        asrCount: asrCount,
        refToAsr: refToAsr,
        asrToRef: asrToRef,
      );
    }

    final entries = <LyricAlignmentEntry>[];
    for (var r = 0; r < referenceCount; r++) {
      final preparedReference = references[r];
      final reference = referenceLines[preparedReference.originalIndex];
      final matchedAsr = refToAsr[r];
      final referenceHasTimestamp = reference.hasTimestamp;

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
            status: ReferenceLineAlignmentStatus.missing,
          ),
        );
        continue;
      }

      final asr = asrLines[matchedAsr];
      final asrLine = document.lines[asr.originalIndex];
      final identical = preparedReference.normalized == asr.normalized;
      final similarity = similarities[r][matchedAsr];

      // 歧义匹配：另一条 ASR 行与本参考行的相似度接近（在 ambiguityMargin 之内），
      // 且本身也达到了匹配阈值，可能是 ASR 合并/拆分。
      var ambiguous = false;
      for (var a2 = 0; a2 < asrCount; a2++) {
        if (a2 == matchedAsr) continue;
        final otherSimilarity = similarities[r][a2];
        if (otherSimilarity >= minimumPairSimilarity &&
            otherSimilarity >= similarity - ambiguityMargin) {
          ambiguous = true;
          break;
        }
      }

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
          status: status,
        ),
      );
    }

    final asrResults = <AsrLineAlignment>[];
    for (var a = 0; a < asrCount; a++) {
      final preparedAsr = asrLines[a];
      final matchedReference = asrToRef[a];
      if (matchedReference == null) {
        asrResults.add(
          AsrLineAlignment(
            asrLineIndex: preparedAsr.originalIndex,
            referenceIndex: null,
            similarity: 0,
            ambiguous: false,
            status: AsrLineAlignmentStatus.unmatched,
          ),
        );
        continue;
      }

      final reference = references[matchedReference];
      final identical = reference.normalized == preparedAsr.normalized;
      final similarity = similarities[matchedReference][a];

      var asrAmbiguous = false;
      for (var r2 = 0; r2 < referenceCount; r2++) {
        if (r2 == matchedReference) continue;
        final otherSimilarity = similarities[r2][a];
        if (otherSimilarity >= minimumPairSimilarity &&
            otherSimilarity >= similarity - ambiguityMargin) {
          asrAmbiguous = true;
          break;
        }
      }

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
          status: asrStatus,
        ),
      );
    }

    return LyricAlignmentResult(entries: entries, asrLines: asrResults);
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
    for (var r = 0; r < references.length; r++) {
      for (var a = 0; a < asrLines.length; a++) {
        // 长度差已经决定了相似度上限低于阈值，提前跳过。
        final maxLength = math.max(
          references[r].runes.length,
          asrLines[a].runes.length,
        );
        if (maxLength > 0) {
          final lengthGap =
              (references[r].runes.length - asrLines[a].runes.length).abs();
          if (lengthGap / maxLength > 1 - minimumPairSimilarity) continue;
        }
        matrix[r][a] = _similarity(references[r].runes, asrLines[a].runes);
      }
    }
    return matrix;
  }

  void _traceback({
    required List<List<double>> similarities,
    required int referenceCount,
    required int asrCount,
    required List<int?> refToAsr,
    required List<int?> asrToRef,
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
        if (similarity >= minimumPairSimilarity) {
          final pair = dp[r - 1][a - 1] + similarity;
          if (pair > best) best = pair;
        }
        dp[r][a] = best;
      }
    }

    var r = referenceCount;
    var a = asrCount;
    while (r > 0 || a > 0) {
      if (r > 0 && a > 0) {
        final similarity = similarities[r - 1][a - 1];
        if (similarity >= minimumPairSimilarity &&
            (dp[r][a] - (dp[r - 1][a - 1] + similarity)).abs() < _epsilon) {
          refToAsr[r - 1] = a - 1;
          asrToRef[a - 1] = r - 1;
          r--;
          a--;
          continue;
        }
      }

      if (r > 0 &&
          (a == 0 ||
              (dp[r][a] - (dp[r - 1][a] - gapPenalty)).abs() < _epsilon)) {
        r--;
        continue;
      }

      a--;
    }
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
