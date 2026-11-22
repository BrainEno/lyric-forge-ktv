import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/automatic_accompaniment.dart';

const _backing = '/p/stems/run-1/accompaniment.wav';
final _at = DateTime.utc(2026, 11, 22, 9);

AudioAsset _audio({String? instrumental, bool marked = false}) => AudioAsset(
  originalPath: '/music/song.flac',
  format: 'flac',
  instrumentalPath: instrumental,
  metadata: {
    'title': 'Song',
    if (marked)
      AutomaticAccompaniment.metadataKey: AutomaticAccompaniment(
        path: _backing,
        separatorRevision: 'v1',
        generatedAt: _at,
      ).toJson(),
  },
);

void main() {
  group('AutomaticAccompaniment marker', () {
    test('round-trips through the audio metadata', () {
      final marker = AutomaticAccompaniment.fromAudioMetadata(
        _audio(marked: true).metadata,
      )!;
      expect(marker.path, _backing);
      expect(marker.separatorRevision, 'v1');
      expect(marker.generatedAt, _at);
    });

    test('ignores markers that are not ours or are incomplete', () {
      for (final raw in <Object?>[
        null,
        'text',
        {'source': 'user', 'path': _backing, 'generatedAt': '$_at'},
        {'source': 'auto-separation', 'generatedAt': '$_at'},
        {'source': 'auto-separation', 'path': ' ', 'generatedAt': '$_at'},
        {'source': 'auto-separation', 'path': _backing, 'generatedAt': 'x'},
      ]) {
        expect(
          AutomaticAccompaniment.fromAudioMetadata({
            AutomaticAccompaniment.metadataKey: raw,
          }),
          isNull,
          reason: '$raw',
        );
      }
    });
  });

  group('which accompaniment a project has', () {
    test('a marked path is automatic, anything else is the user\'s', () {
      final automatic = _audio(instrumental: _backing, marked: true);
      expect(automatic.hasAutomaticAccompaniment, isTrue);
      expect(automatic.hasUserAccompaniment, isFalse);

      final imported = _audio(instrumental: '/imported.mp3', marked: true);
      expect(imported.hasAutomaticAccompaniment, isFalse);
      expect(imported.hasUserAccompaniment, isTrue);

      final unmarked = _audio(instrumental: _backing);
      expect(unmarked.hasUserAccompaniment, isTrue);

      final none = _audio(marked: true);
      expect(none.hasAutomaticAccompaniment, isFalse);
      expect(none.hasUserAccompaniment, isFalse);
    });

    test('the player opens a separated accompaniment on the original', () {
      expect(
        _audio(
          instrumental: _backing,
          marked: true,
        ).preferredProjectPlaybackSource,
        AudioSourceType.original,
      );
      expect(
        _audio(instrumental: '/imported.mp3').preferredProjectPlaybackSource,
        AudioSourceType.instrumental,
        reason: 'an imported accompaniment keeps its priority',
      );
      expect(_audio().preferredProjectPlaybackSource, AudioSourceType.original);
    });

    test('the marker can be dropped without touching other metadata', () {
      final cleaned = _audio(
        instrumental: _backing,
        marked: true,
      ).metadataWithoutAutomaticAccompaniment;
      expect(cleaned.containsKey(AutomaticAccompaniment.metadataKey), isFalse);
      expect(cleaned['title'], 'Song');
    });
  });

  group('linkAutomaticAccompaniment', () {
    test('links into a project without an accompaniment', () {
      final linked = linkAutomaticAccompaniment(
        _audio(),
        path: _backing,
        separatorRevision: 'v1',
        generatedAt: _at,
      )!;
      expect(linked.instrumentalPath, _backing);
      expect(linked.hasAutomaticAccompaniment, isTrue);
      expect(linked.metadata['title'], 'Song');
    });

    test('replaces an older separated accompaniment', () {
      final linked = linkAutomaticAccompaniment(
        _audio(instrumental: _backing, marked: true),
        path: '/p/stems/run-2/accompaniment.wav',
        generatedAt: _at,
      )!;
      expect(linked.instrumentalPath, '/p/stems/run-2/accompaniment.wav');
      expect(linked.hasAutomaticAccompaniment, isTrue);
    });

    test('never replaces an imported accompaniment', () {
      expect(
        linkAutomaticAccompaniment(
          _audio(instrumental: '/imported.mp3'),
          path: _backing,
          generatedAt: _at,
        ),
        isNull,
      );
    });

    test('reports no change for the same file or no file', () {
      expect(
        linkAutomaticAccompaniment(
          _audio(instrumental: _backing, marked: true),
          path: _backing,
          generatedAt: _at,
        ),
        isNull,
      );
      expect(
        linkAutomaticAccompaniment(_audio(), path: null, generatedAt: _at),
        isNull,
      );
      expect(
        linkAutomaticAccompaniment(_audio(), path: '  ', generatedAt: _at),
        isNull,
      );
    });
  });
}
