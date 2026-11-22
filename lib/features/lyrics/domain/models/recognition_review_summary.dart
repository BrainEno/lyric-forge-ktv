import '../../../project/domain/models/lyric_document.dart';
import '../services/lyric_review_decision_service.dart';
import 'lyric_review_queue.dart';
import 'secondary_only_suggestion.dart';
import 'vocal_check_record.dart';
import 'vocal_gap_fill_record.dart';

/// What the editor can honestly say about a recognised draft right after
/// recognition: who produced it, how many rows the engines disagreed on, how
/// many rows only the second engine heard, and how much is left to review.
///
/// Every count is nullable. Null means "this run did not collect it" (an old
/// project, a single-engine run, a degraded run) and the UI must say so; it is
/// never turned into a zero or a percentage. Nothing here is a probability.
class RecognitionReviewSummary {
  /// Metadata key the Whisper adapter writes its decoding profile under.
  static const String whisperDecodingKey = 'whisperDecoding';

  /// Engine identity of the row text (for example `qwen3-asr-1.7b`).
  final String? primaryEngine;

  /// Engine identity of the second opinion, when one ran.
  final String? secondaryEngine;

  /// `highestQuality` when two engines were requested.
  final String? qualityMode;

  /// True when a requested second engine did not contribute.
  final bool degraded;

  /// Whisper decoding profile the run actually used, e.g.
  /// `whisper-lyrics-v2`, and the one that was requested.
  final String? whisperEffectiveProfile;
  final String? whisperRequestedProfile;

  /// Why the requested Whisper profile was not fully applied, when it wasn't.
  final String? whisperFallbackReason;

  final int totalLines;

  /// Rows that still carry a disagreement between the two engines.
  final int? disagreementLines;

  /// "建议补入" rows still showing the second engine's exact text and timing.
  final int? secondaryOnlySuggestions;

  /// Of [secondaryOnlySuggestions], how many nobody has decided on yet.
  final int? pendingSecondaryOnlySuggestions;

  /// Second-engine rows that only re-segmented words already on screen and
  /// were therefore not inserted twice.
  final int? segmentationOnlySecondary;

  /// The editor's review queue size ("待复核").
  final int pendingReview;

  final int reviewedLines;

  /// What the check against the vocal stem did (D-044); null when it did
  /// not run, as for recognition of a mix or older projects.
  final LyricVocalCheckRecord? vocalCheck;

  /// Of the vocal check's stretches with singing but no row, those the
  /// document still has no row for.
  final List<LyricVocalCheckSpan> openVocalSpans;

  /// Rows recognition filled into missed stretches on its own (D-047); null
  /// when the step inserted nothing or did not run.
  final LyricVocalGapFillRecord? vocalGapFill;

  /// Of those rows, how many the document still has.
  final int autoFilledLines;

  /// Of [autoFilledLines], how many nobody has confirmed yet.
  final int pendingAutoFilledLines;

  /// The language the run was told to recognise in (D-061, D-062), from the
  /// draft's `spokenLanguage` record; null when the engines chose.
  final String? sungLanguage;

  /// How [sungLanguage] was found: `detected`, `songInfo`, `project` or
  /// `configured`.
  final String? sungLanguageSource;

  /// The language the engines report the draft is in.
  final String? recognizedLanguage;

  const RecognitionReviewSummary({
    required this.primaryEngine,
    required this.secondaryEngine,
    required this.qualityMode,
    required this.degraded,
    required this.whisperEffectiveProfile,
    required this.whisperRequestedProfile,
    required this.whisperFallbackReason,
    required this.totalLines,
    required this.disagreementLines,
    required this.secondaryOnlySuggestions,
    required this.pendingSecondaryOnlySuggestions,
    required this.segmentationOnlySecondary,
    required this.pendingReview,
    required this.reviewedLines,
    this.vocalCheck,
    this.openVocalSpans = const [],
    this.vocalGapFill,
    this.autoFilledLines = 0,
    this.pendingAutoFilledLines = 0,
    this.sungLanguage,
    this.sungLanguageSource,
    this.recognizedLanguage,
  });

  /// Metadata key of the recognition's language record, written by the
  /// recognition workflow (`SpokenLanguageResolution.metadataKey`).
  static const String spokenLanguageKey = 'spokenLanguage';

  /// A draft with at most this many rows is almost certainly a failed
  /// recognition of a song, not a song with three lines.
  static const int failedDraftLines = 3;

  /// Languages Whisper reports for silence and instruments far more often
  /// than anybody sings in them; the same list as the recognition's
  /// `SpokenLanguagePolicy.hallucinationProne` (a test keeps them equal).
  static final Set<String> misdetectedLanguages = Set.unmodifiable(
    ('nn no cy la haw mi jw su sn yo ln ha ba tt tk br oc bo sa fo ht lb '
            'mt my lo sd am mg as tl ps yi sw')
        .split(' '),
  );

  /// Whether the draft is in a language Whisper typically makes up, and
  /// nobody chose it on purpose.
  bool get languageLooksMisdetected {
    final language = recognizedLanguage;
    if (language == null || !misdetectedLanguages.contains(language)) {
      return false;
    }
    return sungLanguageSource != 'project' &&
        sungLanguageSource != 'configured';
  }

  /// Whether the draft looks like a failed recognition worth redoing with
  /// the right language: almost no rows, or a typically misdetected
  /// language. Never once the user has started reviewing.
  bool get looksFailed =>
      hasRecognitionData &&
      reviewedLines == 0 &&
      (totalLines <= failedDraftLines || languageLooksMisdetected);

  /// Chinese name of a language code, as the recognition settings show it.
  static String languageLabel(String code) => switch (code) {
    'zh' => '中文',
    'yue' => '粤语',
    'en' => '英文',
    'ja' => '日文',
    'ko' => '韩文',
    'fr' => '法语',
    'de' => '德语',
    'es' => '西班牙语',
    'pt' => '葡萄牙语',
    'it' => '意大利语',
    'ru' => '俄语',
    'th' => '泰语',
    'vi' => '越南语',
    'nn' || 'no' => '挪威语',
    'cy' => '威尔士语',
    'la' => '拉丁语',
    _ => code,
  };

  /// `英文（自动判断）`, or null when the run did not settle on a language.
  String? get sungLanguageLine {
    final language = sungLanguage;
    if (language == null) return null;
    final source = switch (sungLanguageSource) {
      'detected' => '自动判断',
      'songInfo' => '按歌名判断',
      'project' => '本首歌设置',
      'configured' => '识别设置',
      _ => null,
    };
    final label = languageLabel(language);
    return source == null ? label : '$label（$source）';
  }

  /// Whether this document carries any recognition metadata at all. Imported
  /// or hand-typed lyrics have none, and get no recognition summary.
  bool get hasRecognitionData =>
      primaryEngine != null ||
      qualityMode != null ||
      whisperEffectiveProfile != null;

  bool get ranTwoEngines => secondaryEngine != null && !degraded;

  bool get whisperProfileDegraded =>
      whisperRequestedProfile != null &&
      whisperEffectiveProfile != null &&
      whisperRequestedProfile != whisperEffectiveProfile;

  factory RecognitionReviewSummary.fromDocument(
    LyricDocument document,
    LyricReviewQueue queue, {
    LyricReviewDecisionService decisionService =
        const LyricReviewDecisionService(),
  }) {
    final metadata = document.metadata;
    final reviewed = decisionService.reviewedIndices(document);

    String? text(Object? value) =>
        value is String && value.trim().isNotEmpty ? value.trim() : null;

    final whisper = metadata[whisperDecodingKey];
    final whisperMap = whisper is Map ? whisper : const {};

    int? disagreements;
    final rawCandidates = metadata['fallbackCandidates'];
    if (rawCandidates is List) {
      final indices = <int>{};
      for (final entry in rawCandidates) {
        if (entry is! Map) continue;
        final index = entry['lineIndex'];
        if (index is! int || index < 0 || index >= document.lines.length) {
          continue;
        }
        final alternative =
            text(entry['alternativeText']) ?? text(entry['whisperText']);
        final primary = text(entry['primaryText']) ?? text(entry['qwenText']);
        if (alternative == null) continue;
        if (primary != null && primary == alternative) continue;
        indices.add(index);
      }
      disagreements = indices.length;
    }

    int? suggestions;
    int? pendingSuggestions;
    if (metadata.containsKey(SecondaryOnlySuggestion.metadataKey)) {
      final resolved = SecondaryOnlySuggestion.resolve(document);
      suggestions = resolved.length;
      pendingSuggestions = resolved.keys
          .where((index) => !reviewed.contains(index))
          .length;
    }

    final spoken = metadata[spokenLanguageKey];
    final spokenMap = spoken is Map ? spoken : const {};
    final spokenSource = text(spokenMap['source']);
    String? code(Object? value) {
      final raw = text(value)?.toLowerCase();
      if (raw == null || !RegExp(r'^[a-z]{2,3}$').hasMatch(raw)) return null;
      return raw;
    }

    final segmentation = metadata['segmentationOnlySecondaryCount'];
    final vocalCheck = LyricVocalCheckRecord.fromMetadata(metadata);
    final gapFill = LyricVocalGapFillRecord.fromMetadata(metadata);
    final autoFilled = gapFill?.insertedIndices(document) ?? const <int>[];

    return RecognitionReviewSummary(
      primaryEngine:
          text(metadata['primaryEngine']) ?? text(metadata['generatedBy']),
      secondaryEngine: metadata['fallbackStatus'] == 'completed'
          ? text(metadata['fallbackEngine'])
          : null,
      qualityMode: text(metadata['qualityMode']),
      degraded: metadata['degraded'] == true,
      whisperEffectiveProfile: text(whisperMap['effectiveProfile']),
      whisperRequestedProfile: text(whisperMap['requestedProfile']),
      whisperFallbackReason: text(whisperMap['fallbackReason']),
      totalLines: document.lines.length,
      disagreementLines: disagreements,
      secondaryOnlySuggestions: suggestions,
      pendingSecondaryOnlySuggestions: pendingSuggestions,
      segmentationOnlySecondary: segmentation is int && segmentation >= 0
          ? segmentation
          : null,
      pendingReview: queue.needsReviewCount,
      reviewedLines: reviewed.length,
      vocalCheck: vocalCheck,
      openVocalSpans: vocalCheck?.openSpans(document) ?? const [],
      vocalGapFill: gapFill == null || gapFill.isEmpty ? null : gapFill,
      autoFilledLines: autoFilled.length,
      pendingAutoFilledLines: autoFilled
          .where((index) => !reviewed.contains(index))
          .length,
      sungLanguage: spokenSource == null || spokenSource == 'unresolved'
          ? null
          : code(spokenMap['language']),
      sungLanguageSource: spokenSource,
      recognizedLanguage: code(document.language),
    );
  }
}
