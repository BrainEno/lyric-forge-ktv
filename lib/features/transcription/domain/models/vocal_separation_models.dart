/// Automatic vocal separation before lyric recognition (D-043).
///
/// Separation turns the song into a lead-vocal stem so Whisper and Qwen hear
/// the singer instead of the band. It is an optimisation, never a gate: every
/// outcome other than [VocalSeparationStatus.separated] and
/// [VocalSeparationStatus.reused] leaves recognition on the original mix.
library;

/// Whether recognition separates the vocal first.
enum VocalSeparationPreference {
  /// Separate when the platform has a separator and the project has no
  /// vocal stem of its own.
  automatic,

  /// Always recognise the mix (or a stem the user imported).
  off;

  /// Unknown or missing values keep the default.
  static VocalSeparationPreference fromName(Object? name) =>
      VocalSeparationPreference.values.asNameMap()[name] ??
      VocalSeparationPreference.automatic;
}

enum VocalSeparationStatus {
  /// A new stem was produced in this run.
  separated,

  /// A stem from an earlier run still matches the song and separator.
  reused,

  /// Separation was not attempted; see [VocalSeparationSkipReason].
  skipped,

  /// Separation was attempted and did not produce a usable stem; see
  /// [VocalSeparationFailure]. Recognition continues on the mix.
  failed,
}

enum VocalSeparationSkipReason {
  disabled,
  unsupportedPlatform,

  /// The project already has a vocal stem the user imported; it is never
  /// replaced automatically.
  userProvidedVocal,
  tooLong,
  sourceMissing,
}

enum VocalSeparationFailure {
  /// The separator bundle could not be downloaded, verified or installed.
  installFailed,

  /// FFmpeg could not decode the song into the separator's input format.
  conversionFailed,

  /// The separator exited with an error.
  separatorFailed,

  /// The stem is nearly silent compared with the mix: an instrumental, or a
  /// broken separation. Recognising it would lose every lyric.
  silentStem,

  /// The separator reported success but its files are missing or empty.
  invalidOutput,
}

/// Loudness figures the separator prints (`LF_STATS`), as linear RMS.
class SeparatorStemStats {
  final double mixRms;
  final double vocalsRms;
  final double accompanimentRms;
  final double seconds;

  const SeparatorStemStats({
    required this.mixRms,
    required this.vocalsRms,
    required this.accompanimentRms,
    required this.seconds,
  });

  /// Vocal stem level relative to the mix; null when the mix is silent.
  double? get vocalsToMixRatio => mixRms <= 0 ? null : vocalsRms / mixRms;

  Map<String, Object?> toJson() => {
    'mixRms': mixRms,
    'vocalsRms': vocalsRms,
    'accompanimentRms': accompanimentRms,
    'seconds': seconds,
  };
}

/// What separation did for one recognition run; stored under
/// `metadata.transcription.vocalSeparation` of the project.
class VocalSeparationOutcome {
  final VocalSeparationStatus status;
  final VocalSeparationSkipReason? skipReason;
  final VocalSeparationFailure? failure;

  /// Short technical detail for diagnostics (not shown as the main message).
  final String? detail;
  final String? vocalPath;
  final String? accompanimentPath;

  /// Execution provider the separator ended up on (`dml` or `cpu`).
  final String? provider;

  /// Providers that were tried and abandoned before [provider].
  final List<String> fallbacks;
  final SeparatorStemStats? stats;
  final Duration? elapsed;
  final String? separatorRevision;

  const VocalSeparationOutcome._({
    required this.status,
    this.skipReason,
    this.failure,
    this.detail,
    this.vocalPath,
    this.accompanimentPath,
    this.provider,
    this.fallbacks = const [],
    this.stats,
    this.elapsed,
    this.separatorRevision,
  });

  const VocalSeparationOutcome.skipped(VocalSeparationSkipReason reason)
    : this._(status: VocalSeparationStatus.skipped, skipReason: reason);

  const VocalSeparationOutcome.failed(
    VocalSeparationFailure failure, {
    String? detail,
    String? provider,
    List<String> fallbacks = const [],
    SeparatorStemStats? stats,
    Duration? elapsed,
  }) : this._(
         status: VocalSeparationStatus.failed,
         failure: failure,
         detail: detail,
         provider: provider,
         fallbacks: fallbacks,
         stats: stats,
         elapsed: elapsed,
       );

  const VocalSeparationOutcome.separated({
    required String vocalPath,
    String? accompanimentPath,
    required String provider,
    List<String> fallbacks = const [],
    SeparatorStemStats? stats,
    required Duration elapsed,
    required String separatorRevision,
  }) : this._(
         status: VocalSeparationStatus.separated,
         vocalPath: vocalPath,
         accompanimentPath: accompanimentPath,
         provider: provider,
         fallbacks: fallbacks,
         stats: stats,
         elapsed: elapsed,
         separatorRevision: separatorRevision,
       );

  const VocalSeparationOutcome.reused({
    required String vocalPath,
    String? accompanimentPath,
    String? provider,
    required String separatorRevision,
  }) : this._(
         status: VocalSeparationStatus.reused,
         vocalPath: vocalPath,
         accompanimentPath: accompanimentPath,
         provider: provider,
         separatorRevision: separatorRevision,
       );

  /// True when recognition will hear a separated vocal stem.
  bool get usesSeparatedVocal =>
      status == VocalSeparationStatus.separated ||
      status == VocalSeparationStatus.reused;

  /// One line for the progress area and diagnostics.
  String get summary => switch (status) {
    VocalSeparationStatus.separated =>
      '已自动分离人声（${_providerLabel(provider)}'
          '${elapsed == null ? '' : '，${_seconds(elapsed!)}'}）',
    VocalSeparationStatus.reused => '复用已分离的人声',
    VocalSeparationStatus.skipped => switch (skipReason!) {
      VocalSeparationSkipReason.disabled => '未启用自动人声分离',
      VocalSeparationSkipReason.unsupportedPlatform => '当前平台暂不支持自动人声分离',
      VocalSeparationSkipReason.userProvidedVocal => '使用已导入的人声轨',
      VocalSeparationSkipReason.tooLong => '歌曲过长，跳过人声分离',
      VocalSeparationSkipReason.sourceMissing => '原始音频不可用，跳过人声分离',
    },
    VocalSeparationStatus.failed => switch (failure!) {
      VocalSeparationFailure.installFailed => '人声分离组件安装失败，改用原曲识别',
      VocalSeparationFailure.conversionFailed => '音频转换失败，改用原曲识别',
      VocalSeparationFailure.separatorFailed => '人声分离失败，改用原曲识别',
      VocalSeparationFailure.silentStem => '未分离出明显人声（可能是纯音乐），改用原曲识别',
      VocalSeparationFailure.invalidOutput => '人声分离结果无效，改用原曲识别',
    },
  };

  Map<String, Object?> toJson() => {
    'status': status.name,
    'skipReason': skipReason?.name,
    'failure': failure?.name,
    'detail': detail,
    'vocalPath': vocalPath,
    'accompanimentPath': accompanimentPath,
    'provider': provider,
    'fallbacks': fallbacks,
    'stats': stats?.toJson(),
    'elapsedMs': elapsed?.inMilliseconds,
    'separatorRevision': separatorRevision,
    'summary': summary,
  };

  static String _providerLabel(String? provider) => switch (provider) {
    'dml' => 'GPU',
    'cpu' => 'CPU',
    _ => provider ?? '未知设备',
  };

  static String _seconds(Duration duration) {
    final seconds = duration.inMilliseconds / 1000;
    return seconds < 10
        ? '${seconds.toStringAsFixed(1)} 秒'
        : '${seconds.round()} 秒';
  }
}

/// Provenance of an automatically separated stem, kept in
/// `AudioAsset.metadata[VocalStemMarker.metadataKey]`.
///
/// A vocal path without this marker was imported by the user and is never
/// replaced. With it, the stem is reused only while the song file and the
/// separator revision are unchanged.
class VocalStemMarker {
  static const String metadataKey = 'vocalSeparation';
  static const String automaticSource = 'auto-separation';

  final String separatorRevision;
  final String sourceFingerprint;
  final String vocalPath;
  final String? accompanimentPath;
  final String? provider;
  final DateTime generatedAt;

  const VocalStemMarker({
    required this.separatorRevision,
    required this.sourceFingerprint,
    required this.vocalPath,
    this.accompanimentPath,
    this.provider,
    required this.generatedAt,
  });

  Map<String, Object?> toJson() => {
    'source': automaticSource,
    'separatorRevision': separatorRevision,
    'sourceFingerprint': sourceFingerprint,
    'vocalPath': vocalPath,
    'accompanimentPath': accompanimentPath,
    'provider': provider,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
  };

  /// The marker in [metadata], or null when absent or not ours.
  static VocalStemMarker? fromAudioMetadata(Map<String, dynamic> metadata) {
    final raw = metadata[metadataKey];
    if (raw is! Map) return null;
    if (raw['source'] != automaticSource) return null;
    final revision = raw['separatorRevision'];
    final fingerprint = raw['sourceFingerprint'];
    final vocalPath = raw['vocalPath'];
    final generatedAt = DateTime.tryParse('${raw['generatedAt']}');
    if (revision is! String ||
        fingerprint is! String ||
        vocalPath is! String ||
        generatedAt == null) {
      return null;
    }
    final accompaniment = raw['accompanimentPath'];
    final provider = raw['provider'];
    return VocalStemMarker(
      separatorRevision: revision,
      sourceFingerprint: fingerprint,
      vocalPath: vocalPath,
      accompanimentPath: accompaniment is String ? accompaniment : null,
      provider: provider is String ? provider : null,
      generatedAt: generatedAt,
    );
  }
}
