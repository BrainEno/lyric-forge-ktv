import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/ktv_backing_mode.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

void main() {
  group('KTV backing modes', () {
    test('always exposes guide vocal through the original mix', () {
      const asset = AudioAsset(
        originalPath: '/music/song.wav',
        format: 'wav',
      );

      expect(
        availableKtvBackingModes(asset),
        const <KtvBackingMode>[KtvBackingMode.guideVocal],
      );
      expect(
        KtvBackingMode.guideVocal.source,
        AudioSourceType.original,
      );
    });

    test('adds pure accompaniment when an instrumental track exists', () {
      const asset = AudioAsset(
        originalPath: '/music/song.wav',
        instrumentalPath: '/music/song_instrumental.wav',
        vocalPath: '/music/song_vocals.wav',
        format: 'wav',
      );

      expect(
        availableKtvBackingModes(asset),
        const <KtvBackingMode>[
          KtvBackingMode.guideVocal,
          KtvBackingMode.instrumental,
        ],
      );
      expect(
        KtvBackingMode.instrumental.source,
        AudioSourceType.instrumental,
      );
    });

    test('does not expose isolated vocals as a KTV backing choice', () {
      expect(
        ktvBackingModeForSource(AudioSourceType.vocals),
        isNull,
      );
      expect(
        ktvBackingModeForSource(AudioSourceType.original),
        KtvBackingMode.guideVocal,
      );
      expect(
        ktvBackingModeForSource(AudioSourceType.instrumental),
        KtvBackingMode.instrumental,
      );
    });
  });
}
