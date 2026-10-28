/// 一行歌词时间的来源，写入 metadata 后可在后续编辑中追溯。
///
/// 文字置信度与时间来源是两件事：即使文本是低置信度匹配，只要采用了参考
/// 时间戳，时间来源仍然是 [reference]。
enum LyricTimingProvenance {
  /// 直接采用参考歌词自带的时间戳。
  reference,

  /// 参考行没有时间戳，沿用 ASR 草稿行的已有时间。
  mappedAsr,

  /// 纯文本参考漏行，按前后锚点空隙插值推断。
  interpolated,

  /// 末尾漏行没有后锚点，按默认时长估算。
  estimatedTail,

  /// 自动收紧了结束时间以消除明确的重叠或音频边界冲突。
  autoRepaired,

  /// 用户在编辑器中手动校准过的时间。
  manual;

  static LyricTimingProvenance? fromName(Object? value) {
    if (value is! String) return null;
    for (final provenance in values) {
      if (provenance.name == value) return provenance;
    }
    return null;
  }
}

/// 时间来源在文档 metadata 中的键；值为 `lineId -> provenance.name`。
const String kLyricTimingProvenanceKey = 'timingProvenance';
