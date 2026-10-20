import 'dart:math' as math;

/// 单个字符差异片段的类型。
enum CharacterDiffType { equal, insert, delete }

/// 一段连续且类型相同的字符差异。
class CharacterDiffSegment {
  final CharacterDiffType type;
  final String text;

  const CharacterDiffSegment({required this.type, required this.text});

  bool get isEqual => type == CharacterDiffType.equal;
}

/// 计算两段歌词文本的字符级差异，供逐行确认界面高亮。
///
/// 只做纯计算，不依赖 Flutter。按 Unicode 码点比较，避免把一个汉字或
/// emoji 拆成半个代理对。
class CharacterDiffService {
  /// 差异矩阵的最大单元数；超过后整行标记为替换，防止超长行占用过多内存。
  static const int _maximumCells = 250000;

  const CharacterDiffService();

  List<CharacterDiffSegment> diff(String oldText, String newText) {
    if (oldText == newText) {
      return oldText.isEmpty
          ? const []
          : [
              CharacterDiffSegment(
                type: CharacterDiffType.equal,
                text: oldText,
              ),
            ];
    }

    final oldRunes = oldText.runes.toList(growable: false);
    final newRunes = newText.runes.toList(growable: false);
    if (oldRunes.isEmpty ||
        newRunes.isEmpty ||
        (oldRunes.length + 1) * (newRunes.length + 1) > _maximumCells) {
      return [
        if (oldText.isNotEmpty)
          CharacterDiffSegment(type: CharacterDiffType.delete, text: oldText),
        if (newText.isNotEmpty)
          CharacterDiffSegment(type: CharacterDiffType.insert, text: newText),
      ];
    }

    final rows = oldRunes.length;
    final columns = newRunes.length;
    // suffix[i][j] = oldRunes[i..] 与 newRunes[j..] 的最长公共子序列长度。
    final suffix = List<List<int>>.generate(
      rows + 1,
      (_) => List<int>.filled(columns + 1, 0),
      growable: false,
    );
    for (var i = rows - 1; i >= 0; i--) {
      for (var j = columns - 1; j >= 0; j--) {
        suffix[i][j] = oldRunes[i] == newRunes[j]
            ? suffix[i + 1][j + 1] + 1
            : math.max(suffix[i + 1][j], suffix[i][j + 1]);
      }
    }

    final segments = <CharacterDiffSegment>[];
    final buffer = StringBuffer();
    CharacterDiffType? currentType;

    void flush() {
      if (currentType != null && buffer.isNotEmpty) {
        segments.add(
          CharacterDiffSegment(type: currentType!, text: buffer.toString()),
        );
      }
      buffer.clear();
    }

    void append(CharacterDiffType type, int rune) {
      if (currentType != null && currentType != type) flush();
      currentType = type;
      buffer.writeCharCode(rune);
    }

    var i = 0;
    var j = 0;
    while (i < rows && j < columns) {
      if (oldRunes[i] == newRunes[j]) {
        append(CharacterDiffType.equal, oldRunes[i]);
        i++;
        j++;
      } else if (suffix[i + 1][j] >= suffix[i][j + 1]) {
        append(CharacterDiffType.delete, oldRunes[i]);
        i++;
      } else {
        append(CharacterDiffType.insert, newRunes[j]);
        j++;
      }
    }
    while (i < rows) {
      append(CharacterDiffType.delete, oldRunes[i]);
      i++;
    }
    while (j < columns) {
      append(CharacterDiffType.insert, newRunes[j]);
      j++;
    }
    flush();

    return segments;
  }
}
