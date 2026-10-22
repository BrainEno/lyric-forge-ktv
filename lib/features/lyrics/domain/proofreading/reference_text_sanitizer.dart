import 'lyric_tokenizer.dart';

enum RemovedReason { sectionHeader, titleLine, pageNoise, creditLine, lrcTag }

class RemovedLine {
  final int originalIndex;
  final String text;
  final RemovedReason reason;
  const RemovedLine(this.originalIndex, this.text, this.reason);
}

class SanitizedReference {
  final List<String> lines;
  final List<RemovedLine> removed;
  const SanitizedReference(this.lines, this.removed);
}

class ReferenceTextSanitizer {
  const ReferenceTextSanitizer();
  static const _tokenizer = LyricTokenizer();
  static const _sectionKeywords = [
    'verse',
    'chorus',
    'bridge',
    'intro',
    'outro',
    'hook',
    'pre-chorus',
    'refrain',
    'instrumental',
    'solo',
    '主歌',
    '副歌',
    '导歌',
    '间奏',
    '前奏',
    '尾奏',
    '桥段',
    '歌词',
  ];
  static const _pageNoise = {
    'embed',
    'you might also like',
    'see more',
    'share',
    'read more',
    'translations',
  };
  static const _creditPrefixes = [
    '作词',
    '作曲',
    '词',
    '曲',
    '编曲',
    '制作人',
    'lyrics by',
    'written by',
    'composed by',
    'music by',
  ];
  static const _lrcPrefixes = ['[ti:', '[ar:', '[al:', '[by:', '[offset:'];
  // RegExp has no const constructor, so these are hoisted statics instead of
  // per-line literals.
  static final RegExp _numericEmbed = RegExp(r'^\d+\s*embed$');
  static final RegExp _numericContributor = RegExp(r'^\d+\s*contributor');
  static final RegExp _whitespaceRun = RegExp(r'\s+');

  SanitizedReference sanitize(String raw, {String? title, String? artist}) {
    final lines = <String>[];
    final removed = <RemovedLine>[];
    var nonEmptyIndex = 0;
    final sourceLines = raw.split('\n');
    for (var index = 0; index < sourceLines.length; index++) {
      final line = sourceLines[index].trim().replaceAll(_whitespaceRun, ' ');
      if (line.isEmpty) continue;
      final checkTitle = nonEmptyIndex < 3;
      nonEmptyIndex++;
      final reason = _reason(line, title, checkTitle);
      if (reason == null) {
        lines.add(line);
      } else {
        removed.add(RemovedLine(index, line, reason));
      }
    }
    return SanitizedReference(lines, removed);
  }

  RemovedReason? _reason(String line, String? title, bool checkTitle) {
    if (_isSectionHeader(line)) return RemovedReason.sectionHeader;
    if (checkTitle && _isTitleLine(line, title)) return RemovedReason.titleLine;
    final lower = line.toLowerCase();
    if (_pageNoise.contains(lower) ||
        _numericEmbed.hasMatch(lower) ||
        _numericContributor.hasMatch(lower)) {
      return RemovedReason.pageNoise;
    }
    if (_creditPrefixes.any(
      (prefix) =>
          lower.startsWith(prefix) &&
          (lower.substring(prefix.length).startsWith(':') ||
              lower.substring(prefix.length).startsWith('：')),
    )) {
      return RemovedReason.creditLine;
    }
    if (lower.endsWith(']') && _lrcPrefixes.any(lower.startsWith)) {
      return RemovedReason.lrcTag;
    }
    return null;
  }

  bool _isSectionHeader(String line) {
    if (line.runes.length > 40) return false;
    final wrapped =
        (line.startsWith('[') && line.endsWith(']')) ||
        (line.startsWith('(') && line.endsWith(')')) ||
        (line.startsWith('（') && line.endsWith('）')) ||
        (line.startsWith('［') && line.endsWith('］')) ||
        (line.startsWith('｛') && line.endsWith('｝')) ||
        (line.startsWith('〔') && line.endsWith('〕')) ||
        (line.startsWith('【') && line.endsWith('】'));
    if (!wrapped) return false;
    final inner = line.substring(1, line.length - 1).toLowerCase();
    return _sectionKeywords.any((keyword) => inner.contains(keyword));
  }

  bool _isTitleLine(String line, String? title) {
    final normalized = _tokenizer.normalize(line);
    if (normalized == 'lyrics') return true;
    final normalizedTitle = title == null ? '' : _tokenizer.normalize(title);
    if (normalizedTitle.isNotEmpty &&
        (normalized == normalizedTitle ||
            normalized == _tokenizer.normalize('$title lyrics'))) {
      return true;
    }
    return normalized.endsWith(' lyrics') &&
        _tokenizer.tokenize(normalized).length <= 8;
  }
}
