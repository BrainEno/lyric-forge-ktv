import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/play_history.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

// Play history records the cover the player showed, so the dashboard's recent
// listening shelf can show it too (audit D-04).

PlayHistory _history({String? artworkPath}) => PlayHistory(
  id: 'song',
  name: '月亮代表我的心',
  artist: '邓丽君',
  filePath: '/music/song.mp3',
  playedAt: DateTime.utc(2026, 11, 25, 11, 50),
  lastPosition: const Duration(seconds: 42),
  duration: const Duration(minutes: 3),
  artworkPath: artworkPath,
);

PlaybackItem _item({String? artworkPath, String? thumbnailPath}) =>
    PlaybackItem(
      id: 'local:song',
      title: 'song',
      artworkPath: artworkPath,
      audioAsset: AudioAsset(
        originalPath: '/music/song.mp3',
        format: 'mp3',
        thumbnailPath: thumbnailPath,
      ),
    );

void main() {
  group('PlayHistory artwork', () {
    test('survives a JSON round trip', () {
      final restored = PlayHistory.fromJson(
        _history(artworkPath: '/covers/song.jpg').toJson(),
      );

      expect(restored.artworkPath, '/covers/song.jpg');
      expect(restored.name, '月亮代表我的心');
      expect(restored.lastPosition, const Duration(seconds: 42));
    });

    test('is left out of the JSON when there is none', () {
      final json = _history().toJson();

      expect(json.containsKey('artworkPath'), isFalse);
      expect(PlayHistory.fromJson(json).artworkPath, isNull);
    });

    test('history files written before covers were recorded still load', () {
      final legacy = <String, dynamic>{
        'id': 'old',
        'name': '旧记录',
        'artist': null,
        'filePath': '/music/old.mp3',
        'playedAt': '2026-01-01T00:00:00.000Z',
        'lastPosition': 1000,
        'duration': null,
        'lastSource': 'original',
      };

      final history = PlayHistory.fromJson(legacy);

      expect(history.name, '旧记录');
      expect(history.artworkPath, isNull);
    });

    test('blank or malformed values read as no cover', () {
      for (final value in <Object?>['', '   ', 42, true]) {
        final json = _history().toJson()..['artworkPath'] = value;
        expect(
          PlayHistory.fromJson(json).artworkPath,
          isNull,
          reason: '$value',
        );
      }
      final padded = _history().toJson()..['artworkPath'] = '  /c/a.png ';
      expect(PlayHistory.fromJson(padded).artworkPath, '/c/a.png');
    });

    test('copyWith keeps, replaces or clears the cover', () {
      final history = _history(artworkPath: '/covers/a.jpg');

      expect(history.copyWith(name: '新名字').artworkPath, '/covers/a.jpg');
      expect(
        history.copyWith(artworkPath: '/covers/b.jpg').artworkPath,
        '/covers/b.jpg',
      );
      expect(history.copyWith(clearArtwork: true).artworkPath, isNull);
    });
  });

  group('PlaybackItem.localArtworkPath', () {
    test('prefers the item cover', () {
      final item = _item(
        artworkPath: '/covers/own.jpg',
        thumbnailPath: '/thumbs/file.jpg',
      );
      expect(item.localArtworkPath, '/covers/own.jpg');
    });

    test('falls back to the audio thumbnail', () {
      expect(
        _item(thumbnailPath: '/thumbs/file.jpg').localArtworkPath,
        '/thumbs/file.jpg',
      );
      expect(
        _item(
          artworkPath: '  ',
          thumbnailPath: '/thumbs/file.jpg',
        ).localArtworkPath,
        '/thumbs/file.jpg',
      );
    });

    test('is null without any cover', () {
      expect(_item().localArtworkPath, isNull);
      expect(
        _item(artworkPath: '', thumbnailPath: ' ').localArtworkPath,
        isNull,
      );
    });

    test('trims the item cover', () {
      expect(
        _item(artworkPath: ' /covers/own.jpg ').localArtworkPath,
        '/covers/own.jpg',
      );
    });
  });
}
