import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/online/online_lyric_query.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/online/song_tags.dart';

void main() {
  group('isPlaceholderName', () {
    for (final name in [
      '新录音 12',
      '新錄音 3',
      'Recording 12',
      'New Recording 4.m4a',
      'Voice Memo 2',
      'Track 05',
      '未命名',
      'IMG_0034.mp4',
      'VID_20240501_213000',
      'PTT-20240501-WA0003.opus',
      '2024-05-01 21_30',
      '20240501',
      '0123456789abcdef',
      '3f2504e0-4f89-11d3-9a0c-0305e82c3301',
      '   ',
    ]) {
      test('"$name" is a placeholder', () {
        expect(OnlineLyricQuery.isPlaceholderName(name), isTrue);
      });
    }

    for (final name in [
      '晴天',
      '周杰伦 - 晴天',
      '七里香.mp3',
      'Yesterday',
      'Love Story',
      '后来',
      '十年',
    ]) {
      test('"$name" names a song', () {
        expect(OnlineLyricQuery.isPlaceholderName(name), isFalse);
      });
    }

    test('a digits-only song name is still searched, after the tags', () {
      // "1979" is a real song, but only digits looks like a date stamp.
      expect(OnlineLyricQuery.isPlaceholderName('1979'), isTrue);
      final queries = OnlineLyricQuery.candidatesFor(
        name: '1979',
        tags: const SongTags(title: '1979', artist: '许巍'),
      );
      expect(queries.single.title, '1979');
      expect(queries.single.artist, '许巍');
    });
  });

  group('candidatesFor', () {
    const tags = SongTags(
      title: '晴天',
      artist: '周杰伦',
      duration: Duration(seconds: 269),
    );

    test('a placeholder name searches the tag title first', () {
      final queries = OnlineLyricQuery.candidatesFor(
        name: '新录音 12',
        tags: tags,
      );
      expect(queries.first.title, '晴天');
      expect(queries.first.artist, '周杰伦');
      expect(queries.first.duration, const Duration(seconds: 269));
      expect(queries.map((query) => query.title), contains('新录音 12'));
    });

    test('a real name stays first and the tags come second', () {
      final queries = OnlineLyricQuery.candidatesFor(
        name: '七里香',
        tags: tags,
      );
      expect(queries.map((query) => query.title), ['七里香', '晴天']);
      // The missing artist is filled from the tags.
      expect(queries.first.artist, '周杰伦');
    });

    test('the same song from name and tags is searched once', () {
      final queries = OnlineLyricQuery.candidatesFor(
        name: '周杰伦 - 晴天.mp3',
        tags: tags,
      );
      expect(queries, hasLength(1));
      expect(queries.single.title, '晴天');
    });

    test('a typed artist wins over the tag artist', () {
      final queries = OnlineLyricQuery.candidatesFor(
        name: 'IMG_0034',
        artist: '五月天',
        tags: tags,
      );
      expect(queries.first.artist, '五月天');
    });

    test('the project duration wins over the tag duration', () {
      final queries = OnlineLyricQuery.candidatesFor(
        name: '晴天',
        duration: const Duration(seconds: 270),
        tags: tags,
      );
      expect(queries.single.duration, const Duration(seconds: 270));
    });

    test('a placeholder tag title is ignored', () {
      final queries = OnlineLyricQuery.candidatesFor(
        name: '晴天',
        tags: const SongTags(title: 'Track 01'),
      );
      expect(queries.map((query) => query.title), ['晴天']);
    });

    test('no tags keeps the name query alone', () {
      final queries = OnlineLyricQuery.candidatesFor(name: '晴天');
      expect(queries.map((query) => query.title), ['晴天']);
    });

    test('nothing searchable gives an empty list', () {
      expect(OnlineLyricQuery.candidatesFor(name: '  '), isEmpty);
    });
  });

  group('readSongTagsSafely', () {
    test('returns what the reader found', () async {
      final tags = await readSongTagsSafely(
        (_) async => const SongTags(title: '晴天'),
        '/music/a.mp3',
      );
      expect(tags?.title, '晴天');
    });

    test('no reader or no path reads nothing', () async {
      expect(await readSongTagsSafely(null, '/music/a.mp3'), isNull);
      expect(
        await readSongTagsSafely((_) async => const SongTags(title: 'x'), null),
        isNull,
      );
    });

    test('an error becomes null', () async {
      final tags = await readSongTagsSafely(
        (_) async => throw StateError('broken header'),
        '/music/a.mp3',
      );
      expect(tags, isNull);
    });

    test('empty tags become null', () async {
      final tags = await readSongTagsSafely(
        (_) async => const SongTags(),
        '/music/a.mp3',
      );
      expect(tags, isNull);
    });

    test('a slow reader is abandoned', () async {
      final never = Completer<SongTags?>();
      final tags = await readSongTagsSafely(
        (_) => never.future,
        '/music/a.mp3',
        timeout: const Duration(milliseconds: 10),
      );
      expect(tags, isNull);
    });
  });
}
