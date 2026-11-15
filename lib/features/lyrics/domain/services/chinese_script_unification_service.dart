import '../../../project/domain/models/lyric_document.dart';
import '../models/chinese_script_preference.dart';
import '../text/chinese_script_converter.dart';

/// Why a unification plan changes nothing.
enum ChineseScriptNoopReason {
  /// The preference is [ChineseScriptPreference.keep].
  disabled,

  /// The document language is not Chinese, or most lines contain kana or
  /// hangul: kanji and hanja are left exactly as written.
  notChinese,

  /// No Han characters to convert.
  noChineseText,

  /// Every line already uses one script.
  alreadyConsistent,

  /// Automatic mode found as many simplified as traditional lines and the
  /// language tag does not break the tie; guessing would rewrite half of the
  /// lyrics, so the user has to choose a target.
  ambiguousMajority,

  /// Lines needed conversion, but all of them are manually edited.
  onlyProtectedLines,
}

/// One line the plan rewrites.
class ChineseScriptLineChange {
  final int index;
  final String? lineId;
  final String before;
  final String after;
  final ChineseScriptKind beforeKind;

  const ChineseScriptLineChange({
    required this.index,
    required this.lineId,
    required this.before,
    required this.after,
    required this.beforeKind,
  });
}

/// Script statistics over a whole document, counted per line.
class ChineseScriptDocumentProfile {
  final int simplifiedLines;
  final int traditionalLines;
  final int mixedLines;
  final int neutralLines;

  /// Lines with kana or hangul; never converted.
  final int japaneseOrKoreanLines;

  const ChineseScriptDocumentProfile({
    required this.simplifiedLines,
    required this.traditionalLines,
    required this.mixedLines,
    required this.neutralLines,
    required this.japaneseOrKoreanLines,
  });

  int get hanLines =>
      simplifiedLines + traditionalLines + mixedLines + neutralLines;

  /// Lines whose script disagrees with the majority, plus mixed lines; the
  /// "script-inconsistent line" count reported by the quality tool.
  int get inconsistentLines {
    final minority = simplifiedLines < traditionalLines
        ? simplifiedLines
        : traditionalLines;
    return minority + mixedLines;
  }
}

/// A preview of a script unification, applied only on request.
class ChineseScriptUnificationPlan {
  final ChineseScriptPreference preference;

  /// The script lines are converted to; null when nothing will change and
  /// no target could be decided.
  final ChineseScriptTarget? target;
  final List<ChineseScriptLineChange> changes;
  final ChineseScriptDocumentProfile profile;

  /// Lines that would change but are manually edited, so are left alone.
  final List<int> skippedProtectedIndices;
  final ChineseScriptNoopReason? noopReason;
  final String revision;

  const ChineseScriptUnificationPlan({
    required this.preference,
    required this.target,
    required this.changes,
    required this.profile,
    required this.skippedProtectedIndices,
    required this.noopReason,
    required this.revision,
  });

  bool get hasChanges => changes.isNotEmpty;

  /// Applies the plan. Only line text changes; timing, ids, confidence and
  /// line count stay as they were. The conversion is recorded under
  /// [ChineseScriptUnificationService.metadataKey] so independent ASR
  /// evidence can still be matched to the converted draft by replaying it.
  LyricDocument applyTo(LyricDocument document) {
    final target = this.target;
    if (changes.isEmpty || target == null) return document;
    final lines = List<LyricLine>.of(document.lines);
    final convertedIds = <String>[];
    for (final change in changes) {
      final line = lines[change.index];
      if (line.text != change.before) {
        throw StateError(
          'Line ${change.index} changed after the script plan was made.',
        );
      }
      lines[change.index] = line.copyWith(text: change.after);
      if (line.id != null) convertedIds.add(line.id!);
    }
    final previous = ChineseScriptUnificationRecord.tryParse(
      document.metadata[ChineseScriptUnificationService.metadataKey],
    );
    final record = ChineseScriptUnificationRecord(
      target: target,
      preference: preference,
      revision: revision,
      convertedLineCount:
          changes.length +
          (previous != null && previous.target == target
              ? previous.convertedLineCount
              : 0),
      convertedLineIds: {
        if (previous != null && previous.target == target)
          ...previous.convertedLineIds,
        ...convertedIds,
      }.toList()..sort(),
    );
    return document.copyWith(
      lines: lines,
      metadata: {
        ...document.metadata,
        ChineseScriptUnificationService.metadataKey: record.toJson(),
      },
    );
  }
}

/// What the last unification did, stored in document metadata.
class ChineseScriptUnificationRecord {
  final ChineseScriptTarget target;
  final ChineseScriptPreference preference;
  final String revision;
  final int convertedLineCount;
  final List<String> convertedLineIds;

  const ChineseScriptUnificationRecord({
    required this.target,
    required this.preference,
    required this.revision,
    required this.convertedLineCount,
    required this.convertedLineIds,
  });

  Map<String, Object?> toJson() => {
    'target': target.name,
    'preference': preference.name,
    'revision': revision,
    'convertedLineCount': convertedLineCount,
    'convertedLineIds': convertedLineIds,
  };

  static ChineseScriptUnificationRecord? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final target = ChineseScriptTarget.values.asNameMap()[raw['target']];
    final revision = raw['revision'];
    if (target == null || revision is! String || revision.isEmpty) {
      return null;
    }
    final ids = raw['convertedLineIds'];
    final count = raw['convertedLineCount'];
    return ChineseScriptUnificationRecord(
      target: target,
      preference: ChineseScriptPreference.fromName(raw['preference']),
      revision: revision,
      convertedLineCount: count is int && count >= 0 ? count : 0,
      convertedLineIds: [
        if (ids is List)
          for (final id in ids)
            if (id is String) id,
      ],
    );
  }

  /// Whether [current] is exactly what this record's conversion produces from
  /// [original]. Only trusted when the converter tables are the ones that
  /// made the record, so a dictionary update cannot validate stale text.
  bool explains({
    required String original,
    required String current,
    ChineseScriptConverter converter = const ChineseScriptConverter(),
  }) {
    if (original == current) return true;
    if (revision != converter.revision) return false;
    return converter.convertLine(original, target) == current;
  }
}

/// Plans simplified/traditional unification for a lyric document.
///
/// Automatic mode only rewrites lines in the minority script (and lines that
/// mix both), so a consistent draft is never touched. Lines with kana or
/// hangul, non-Chinese documents and manually edited lines are skipped.
class ChineseScriptUnificationService {
  final ChineseScriptConverter converter;

  const ChineseScriptUnificationService({
    this.converter = const ChineseScriptConverter(),
  });

  static const String metadataKey = 'chineseScriptUnification';

  /// A document counts as Japanese/Korean when at least this share of its
  /// Han-bearing lines also carry kana or hangul; kanji-only lines in such a
  /// song must not be converted either.
  static const double japaneseOrKoreanLineShare = 0.3;

  ChineseScriptUnificationPlan plan(
    LyricDocument document, {
    required ChineseScriptPreference preference,
    Set<int> protectedIndices = const {},
  }) {
    final profiles = [
      for (final line in document.lines) converter.profile(line.text),
    ];
    final documentProfile = _summarize(profiles);

    ChineseScriptUnificationPlan noop(
      ChineseScriptNoopReason reason, {
      ChineseScriptTarget? target,
    }) => ChineseScriptUnificationPlan(
      preference: preference,
      target: target,
      changes: const [],
      profile: documentProfile,
      skippedProtectedIndices: const [],
      noopReason: reason,
      revision: converter.revision,
    );

    if (preference == ChineseScriptPreference.keep) {
      return noop(ChineseScriptNoopReason.disabled);
    }
    if (!_isChineseDocument(document.language, profiles)) {
      return noop(ChineseScriptNoopReason.notChinese);
    }
    if (documentProfile.hanLines == 0) {
      return noop(ChineseScriptNoopReason.noChineseText);
    }

    final explicit = preference.explicitTarget;
    final target = explicit ?? _majorityTarget(document, documentProfile);
    if (target == null) {
      return noop(
        documentProfile.inconsistentLines == 0
            ? ChineseScriptNoopReason.alreadyConsistent
            : ChineseScriptNoopReason.ambiguousMajority,
      );
    }

    final changes = <ChineseScriptLineChange>[];
    final skipped = <int>[];
    for (var index = 0; index < document.lines.length; index++) {
      final profile = profiles[index];
      if (profile.hasKanaOrHangul) continue;
      final kind = profile.kind;
      if (!_shouldConvert(kind, target, automatic: explicit == null)) {
        continue;
      }
      final line = document.lines[index];
      final after = converter.convertLine(line.text, target);
      if (after == line.text) continue;
      if (protectedIndices.contains(index)) {
        skipped.add(index);
        continue;
      }
      changes.add(
        ChineseScriptLineChange(
          index: index,
          lineId: line.id,
          before: line.text,
          after: after,
          beforeKind: kind,
        ),
      );
    }

    return ChineseScriptUnificationPlan(
      preference: preference,
      target: target,
      changes: List.unmodifiable(changes),
      profile: documentProfile,
      skippedProtectedIndices: List.unmodifiable(skipped),
      noopReason: changes.isNotEmpty
          ? null
          : skipped.isNotEmpty
          ? ChineseScriptNoopReason.onlyProtectedLines
          : ChineseScriptNoopReason.alreadyConsistent,
      revision: converter.revision,
    );
  }

  /// Script statistics for [document], for diagnostics and quality reports.
  ChineseScriptDocumentProfile profileDocument(LyricDocument document) =>
      profileTexts([for (final line in document.lines) line.text]);

  ChineseScriptDocumentProfile profileTexts(Iterable<String> texts) =>
      _summarize([for (final text in texts) converter.profile(text)]);

  ChineseScriptDocumentProfile _summarize(List<ChineseScriptProfile> profiles) {
    var simplified = 0;
    var traditional = 0;
    var mixed = 0;
    var neutral = 0;
    var japaneseOrKorean = 0;
    for (final profile in profiles) {
      if (profile.hasKanaOrHangul) {
        japaneseOrKorean++;
        continue;
      }
      switch (profile.kind) {
        case ChineseScriptKind.simplified:
          simplified++;
        case ChineseScriptKind.traditional:
          traditional++;
        case ChineseScriptKind.mixed:
          mixed++;
        case ChineseScriptKind.neutral:
          neutral++;
        case ChineseScriptKind.none:
          break;
      }
    }
    return ChineseScriptDocumentProfile(
      simplifiedLines: simplified,
      traditionalLines: traditional,
      mixedLines: mixed,
      neutralLines: neutral,
      japaneseOrKoreanLines: japaneseOrKorean,
    );
  }

  bool _isChineseDocument(
    String language,
    List<ChineseScriptProfile> profiles,
  ) {
    final tagged = ChineseLanguageTag.isChinese(language);
    if (tagged != null) return tagged;
    var hanLines = 0;
    var kanaLines = 0;
    for (final profile in profiles) {
      if (profile.hanCount == 0 && !profile.hasKanaOrHangul) continue;
      hanLines++;
      if (profile.hasKanaOrHangul) kanaLines++;
    }
    if (hanLines == 0) return true;
    return kanaLines / hanLines < japaneseOrKoreanLineShare;
  }

  /// Automatic target: the script most lines use; a tie falls back to the
  /// script the language tag implies, otherwise no target.
  ChineseScriptTarget? _majorityTarget(
    LyricDocument document,
    ChineseScriptDocumentProfile profile,
  ) {
    if (profile.inconsistentLines == 0) return null;
    final implied = ChineseLanguageTag.impliedTarget(document.language);
    final traditionalTarget = implied != null && implied.isTraditional
        ? implied
        : ChineseLanguageTag.isCantonese(document.language)
        ? ChineseScriptTarget.traditionalHongKong
        : ChineseScriptTarget.traditionalTaiwan;
    if (profile.simplifiedLines > profile.traditionalLines) {
      return ChineseScriptTarget.simplified;
    }
    if (profile.traditionalLines > profile.simplifiedLines) {
      return traditionalTarget;
    }
    if (implied == null) return null;
    return implied.isTraditional
        ? traditionalTarget
        : ChineseScriptTarget.simplified;
  }

  /// Automatic mode is deliberately narrow: neutral lines (我在等你), which
  /// contain only characters valid in both scripts, stay as recognised.
  bool _shouldConvert(
    ChineseScriptKind kind,
    ChineseScriptTarget target, {
    required bool automatic,
  }) {
    switch (kind) {
      case ChineseScriptKind.none:
        return false;
      case ChineseScriptKind.mixed:
        return true;
      case ChineseScriptKind.simplified:
        return target.isTraditional;
      case ChineseScriptKind.traditional:
        return automatic ? !target.isTraditional : true;
      case ChineseScriptKind.neutral:
        return !automatic;
    }
  }
}
