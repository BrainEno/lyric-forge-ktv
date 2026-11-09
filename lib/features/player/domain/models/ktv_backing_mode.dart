import '../../../project/domain/models/audio_asset.dart';

/// User-facing KTV backing choices.
///
/// `guideVocal` keeps the original mix so the singer can follow the recorded
/// lead vocal. `instrumental` uses an accompaniment track referenced by the
/// project and is available when its path is present.
enum KtvBackingMode { guideVocal, instrumental }

extension KtvBackingModeX on KtvBackingMode {
  AudioSourceType get source => switch (this) {
    KtvBackingMode.guideVocal => AudioSourceType.original,
    KtvBackingMode.instrumental => AudioSourceType.instrumental,
  };

  String get label => switch (this) {
    KtvBackingMode.guideVocal => '原唱伴唱',
    KtvBackingMode.instrumental => '纯伴奏',
  };

  String get description => switch (this) {
    KtvBackingMode.guideVocal => '保留原唱人声，适合刚开始跟唱或不熟悉旋律时使用',
    KtvBackingMode.instrumental => '播放工程中的伴奏轨',
  };
}

List<KtvBackingMode> availableKtvBackingModes(AudioAsset? asset) {
  if (asset == null) return const <KtvBackingMode>[];
  return <KtvBackingMode>[
    KtvBackingMode.guideVocal,
    if (asset.hasSource(AudioSourceType.instrumental))
      KtvBackingMode.instrumental,
  ];
}

KtvBackingMode? ktvBackingModeForSource(AudioSourceType? source) {
  return switch (source) {
    AudioSourceType.original => KtvBackingMode.guideVocal,
    AudioSourceType.instrumental => KtvBackingMode.instrumental,
    AudioSourceType.vocals => null,
    null => null,
  };
}
