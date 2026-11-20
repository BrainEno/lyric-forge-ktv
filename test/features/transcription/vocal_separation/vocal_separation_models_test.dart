import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/vocal_separation_models.dart';

void main() {
  group('TranscriptionConfig.vocalSeparation', () {
    const base = TranscriptionConfig(whisperExecutable: 'w', modelPath: 'm');

    test('defaults to automatic and survives a JSON round trip', () {
      expect(base.vocalSeparation, VocalSeparationPreference.automatic);
      for (final value in VocalSeparationPreference.values) {
        final restored = TranscriptionConfig.fromJson(
          base.copyWith(vocalSeparation: value).toJson(),
        );
        expect(restored.vocalSeparation, value);
      }
    });

    test('settings saved before the option existed read as automatic', () {
      final json = base.toJson()..remove('vocalSeparation');
      expect(
        TranscriptionConfig.fromJson(json).vocalSeparation,
        VocalSeparationPreference.automatic,
      );
      expect(
        TranscriptionConfig.fromJson({
          ...json,
          'vocalSeparation': 'sometimes',
        }).vocalSeparation,
        VocalSeparationPreference.automatic,
      );
    });

    test('copyWith keeps the choice when other fields change', () {
      final off = base.copyWith(vocalSeparation: VocalSeparationPreference.off);
      expect(off.copyWith(language: 'ja').vocalSeparation,
          VocalSeparationPreference.off);
    });
  });

  group('VocalStemMarker', () {
    final marker = VocalStemMarker(
      separatorRevision: 'htdemucs-ft-vocals-onnx-v1',
      sourceFingerprint: '123:456:/music/歌.flac',
      vocalPath: '/p/stems/run-1/vocals.wav',
      accompanimentPath: '/p/stems/run-1/accompaniment.wav',
      provider: 'dml',
      generatedAt: DateTime.utc(2026, 11, 18, 10, 30),
    );

    test('round-trips through project JSON', () {
      final metadata =
          jsonDecode(
                jsonEncode({VocalStemMarker.metadataKey: marker.toJson()}),
              )
              as Map<String, dynamic>;
      final restored = VocalStemMarker.fromAudioMetadata(metadata)!;
      expect(restored.separatorRevision, marker.separatorRevision);
      expect(restored.sourceFingerprint, marker.sourceFingerprint);
      expect(restored.vocalPath, marker.vocalPath);
      expect(restored.accompanimentPath, marker.accompanimentPath);
      expect(restored.provider, 'dml');
      expect(restored.generatedAt, marker.generatedAt);
    });

    test('is absent for imported stems and foreign metadata', () {
      expect(VocalStemMarker.fromAudioMetadata(const {}), isNull);
      expect(
        VocalStemMarker.fromAudioMetadata({
          VocalStemMarker.metadataKey: 'yes',
        }),
        isNull,
      );
      expect(
        VocalStemMarker.fromAudioMetadata({
          VocalStemMarker.metadataKey: {
            ...marker.toJson(),
            'source': 'user-import',
          },
        }),
        isNull,
      );
    });

    test('rejects a marker with missing required fields', () {
      for (final key in [
        'separatorRevision',
        'sourceFingerprint',
        'vocalPath',
        'generatedAt',
      ]) {
        final json = marker.toJson()..remove(key);
        expect(
          VocalStemMarker.fromAudioMetadata({
            VocalStemMarker.metadataKey: json,
          }),
          isNull,
          reason: key,
        );
      }
      final optional = marker.toJson()
        ..remove('accompanimentPath')
        ..['provider'] = 7;
      final restored = VocalStemMarker.fromAudioMetadata({
        VocalStemMarker.metadataKey: optional,
      })!;
      expect(restored.accompanimentPath, isNull);
      expect(restored.provider, isNull);
    });
  });

  group('VocalSeparationOutcome', () {
    test('a separation reports device and time', () {
      const outcome = VocalSeparationOutcome.separated(
        vocalPath: '/v.wav',
        provider: 'dml',
        elapsed: Duration(milliseconds: 6400),
        separatorRevision: 'r',
      );
      expect(outcome.usesSeparatedVocal, isTrue);
      expect(outcome.summary, '已自动分离人声（GPU，6.4 秒）');
      const slow = VocalSeparationOutcome.separated(
        vocalPath: '/v.wav',
        provider: 'cpu',
        fallbacks: ['dml unavailable: no adapter'],
        elapsed: Duration(seconds: 95),
        separatorRevision: 'r',
      );
      expect(slow.summary, '已自动分离人声（CPU，95 秒）');
    });

    test('only separated and reused stems are used for recognition', () {
      const reused = VocalSeparationOutcome.reused(
        vocalPath: '/v.wav',
        separatorRevision: 'r',
      );
      expect(reused.usesSeparatedVocal, isTrue);
      expect(reused.summary, '复用已分离的人声');
      for (final reason in VocalSeparationSkipReason.values) {
        final outcome = VocalSeparationOutcome.skipped(reason);
        expect(outcome.usesSeparatedVocal, isFalse);
        expect(outcome.summary, isNotEmpty);
      }
      for (final failure in VocalSeparationFailure.values) {
        final outcome = VocalSeparationOutcome.failed(failure);
        expect(outcome.usesSeparatedVocal, isFalse);
        expect(outcome.summary, contains('原曲'), reason: failure.name);
      }
    });

    test('serialises everything diagnostics need', () {
      const outcome = VocalSeparationOutcome.failed(
        VocalSeparationFailure.silentStem,
        detail: 'vocals/mix RMS ratio 0.0100',
        provider: 'cpu',
        fallbacks: ['dml unavailable: no adapter'],
        stats: SeparatorStemStats(
          mixRms: 0.2,
          vocalsRms: 0.002,
          accompanimentRms: 0.2,
          seconds: 180,
        ),
        elapsed: Duration(seconds: 70),
      );
      final json = jsonDecode(jsonEncode(outcome.toJson())) as Map;
      expect(json['status'], 'failed');
      expect(json['failure'], 'silentStem');
      expect(json['skipReason'], isNull);
      expect(json['provider'], 'cpu');
      expect(json['fallbacks'], ['dml unavailable: no adapter']);
      expect((json['stats'] as Map)['vocalsRms'], 0.002);
      expect(json['elapsedMs'], 70000);
      expect(json['summary'], contains('纯音乐'));
    });
  });
}
