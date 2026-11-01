/// Why a "highest quality" run produced a single-engine draft.
///
/// Highest quality is a capability request, not a prerequisite: the app uses
/// two engines when both are usable and falls back to Whisper when they are
/// not. Every such fallback is recorded so the UI can say what happened
/// instead of silently presenting a weaker result as the best one.
enum TranscriptionDegradationReason {
  qwenNotConfigured('未配置 Qwen3-ASR / ForcedAligner，已用 Whisper large-v3 单引擎识别'),
  qwenUnavailable('Qwen3-ASR 无法运行，已自动降级为 Whisper large-v3 单引擎识别'),
  qwenSecondOpinionFailed('Qwen3-ASR 第二意见识别失败，已保留 Whisper 结果'),
  whisperSecondOpinionFailed('Whisper 第二意见识别失败，已保留 Qwen 结果');

  const TranscriptionDegradationReason(this.message);

  /// Human readable explanation, used when no more specific detail is stored.
  final String message;
}

/// Read/write helpers for the degradation markers on a lyric document.
///
/// The transcription service writes these keys and the UI reads them; keeping
/// both sides on this one class prevents the key names from drifting apart.
abstract final class TranscriptionQualityMetadata {
  /// `true` when the request asked for two engines but only one produced text.
  static const String degradedKey = 'degraded';

  static const String reasonKey = 'degradationReason';

  /// Extra context, usually the engine's own error text.
  static const String detailKey = 'degradationDetail';

  /// The mode the user asked for, kept so the panel can show the difference.
  static const String requestedModeKey = 'requestedQualityMode';

  static Map<String, Object?> degradedFields(
    TranscriptionDegradationReason reason, {
    String? detail,
  }) {
    final trimmed = detail?.trim();
    return {
      degradedKey: true,
      reasonKey: reason.name,
      detailKey: trimmed == null || trimmed.isEmpty ? reason.message : trimmed,
    };
  }

  static bool isDegraded(Map<String, dynamic> metadata) =>
      metadata[degradedKey] == true;

  /// The recorded reason, or a generic one when only the flag survived (older
  /// documents, or metadata that was rewritten by a later step).
  static TranscriptionDegradationReason? reasonOf(
    Map<String, dynamic> metadata,
  ) {
    if (!isDegraded(metadata)) return null;
    final raw = metadata[reasonKey];
    for (final reason in TranscriptionDegradationReason.values) {
      if (reason.name == raw) return reason;
    }
    return TranscriptionDegradationReason.qwenUnavailable;
  }

  /// One line the UI can show verbatim.
  static String? explanationOf(Map<String, dynamic> metadata) {
    final reason = reasonOf(metadata);
    if (reason == null) return null;
    final detail = metadata[detailKey];
    if (detail is String && detail.trim().isNotEmpty) return detail.trim();
    return reason.message;
  }
}
