import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/local_lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/online/online_lyric_candidate.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/online/online_lyric_query.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/online/song_lyrics_lookup.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/text/chinese_script_converter.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_timing.dart';

import 'online_lyric_test_support.dart';

const _query = OnlineLyricQuery(
  title: '夜航',
  artist: '林小雨',
  duration: Duration(seconds: 56),
);

SongLyricsLookup _lookup(List<OnlineLyricSource> sources) => SongLyricsLookup(
  search: OnlineLyricSearchService(sources: sources),
  importer: LocalLyricFileImportService(),
);

void main() {
  group('evaluate', () {
    final lookup = _lookup(const []);

    test('a synced lyric yields timed and plain twins without credits', () {
      final option = lookup.evaluate(candidate(), _query)!;
      expect(option.hasTiming, isTrue);
      final timed = option.timed!.document;
      expect(timed.isTimed, isTrue);
      expect(timed.lines.map((line) => line.text), kNightFlightLyric);
      expect(timed.lines.first.startTime, const Duration(seconds: 10));
      final plain = option.plain.document;
      expect(plain.isUntimed, isTrue);
      expect(plain.lines.map((line) => line.text), kNightFlightLyric);
      expect(option.plain.format, LyricImportFormat.plainText);
    });

    test('records where the lyric came from', () {
      final option = lookup.evaluate(
        candidate(source: OnlineLyricSourceKind.kugou, id: 'k9'),
        _query,
      )!;
      final metadata = option.timed!.document.metadata;
      expect(metadata['source'], onlineLyricsSource);
      expect(metadata['onlineSource'], 'kugou');
      expect(metadata['onlineSourceLabel'], '酷狗音乐');
      expect(metadata['onlineSourceId'], 'k9');
      expect(option.plain.document.metadata['onlineSource'], 'kugou');
    });

    test('a plain lyric is offered as plain text only', () {
      final option = lookup.evaluate(
        candidate(
          source: OnlineLyricSourceKind.lrclib,
          lyricText: kNightFlightLyric.join('\n'),
        ),
        _query,
      )!;
      expect(option.hasTiming, isFalse);
      expect(option.plain.document.lines.length, kNightFlightLyric.length);
      expect(option.notes, contains('纯文本'));
    });

    test('LRC metadata rows without timestamps are not sung lines', () {
      final option = lookup.evaluate(
        candidate(lyricText: '[ti:夜航]\n[ar:林小雨]\n窗外的雨停了又下\n我还在等你的回答'),
        _query,
      )!;
      expect(option.plain.document.lines.map((line) => line.text), [
        '窗外的雨停了又下',
        '我还在等你的回答',
      ]);
    });

    test('an instrumental notice is not a lyric', () {
      expect(
        lookup.evaluate(candidate(lyricText: '[00:00.00]纯音乐，请欣赏'), _query),
        isNull,
      );
    });

    test('flags a recording of another length', () {
      final option = lookup.evaluate(
        candidate(duration: const Duration(seconds: 80)),
        _query,
      )!;
      expect(option.durationDifference, const Duration(seconds: 24));
      expect(option.durationMismatch, isTrue);
      expect(option.notes, contains('时长相差 24 秒'));
    });

    test('a close length is not flagged', () {
      final option = lookup.evaluate(
        candidate(duration: const Duration(seconds: 58)),
        _query,
      )!;
      expect(option.durationMismatch, isFalse);
      expect(option.titleMatches, isTrue);
      expect(option.artistMatches, isTrue);
    });
  });

  group('rank', () {
    final lookup = _lookup(const []);

    test('prefers the same song, then timing', () {
      final options = lookup.rank([
        candidate(
          id: 'other',
          title: '夜航（翻唱）',
          artist: '路人',
          lyricText: '[00:01.00]别的歌词第一句\n[00:03.00]别的歌词第二句',
        ),
        candidate(
          id: 'plain',
          source: OnlineLyricSourceKind.lrclib,
          lyricText: kNightFlightLyric.reversed.join('\n'),
        ),
        candidate(id: 'best'),
      ], _query);
      expect(options.first.candidate.sourceId, 'best');
      expect(options.last.candidate.sourceId, 'other');
    });

    test('collapses identical lyrics from several sites', () {
      final options = lookup.rank([
        candidate(id: '1'),
        candidate(id: '2', source: OnlineLyricSourceKind.kugou),
      ], _query);
      expect(options, hasLength(1));
    });

    test('keeps at most maxOptions', () {
      final small = SongLyricsLookup(
        search: const OnlineLyricSearchService(sources: []),
        importer: LocalLyricFileImportService(),
        maxOptions: 2,
      );
      final options = small.rank([
        for (var i = 0; i < 5; i++)
          candidate(id: '$i', lyricText: '[00:01.00]第$i句\n[00:03.00]下一句$i'),
      ], _query);
      expect(options, hasLength(2));
    });
  });

  test('find searches every source and reports failures', () async {
    final lookup = _lookup([
      FakeLyricSource(OnlineLyricSourceKind.netease, results: [candidate()]),
      FakeLyricSource(OnlineLyricSourceKind.kugou, error: Exception('down')),
    ]);
    final result = await lookup.find(_query);
    expect(result.options, hasLength(1));
    expect(result.best!.hasTiming, isTrue);
    expect(result.failures.keys, [OnlineLyricSourceKind.kugou]);
    expect(result.allSourcesFailed, isFalse);
  });

  test('find with every source down says so', () async {
    final lookup = _lookup([
      FakeLyricSource(OnlineLyricSourceKind.netease, error: Exception('down')),
    ]);
    final result = await lookup.find(_query);
    expect(result.isEmpty, isTrue);
    expect(result.allSourcesFailed, isTrue);
  });

  group('result helpers', () {
    final option = _lookup(const []).evaluate(candidate(), _query)!;

    test('shiftedImportResult moves the whole lyric', () {
      final shifted = shiftedImportResult(
        option.timed!,
        const Duration(milliseconds: 500),
      );
      expect(shifted.document.globalOffset, const Duration(milliseconds: 500));
      expect(shifted.document.metadata['previewOffsetMs'], 500);
      expect(
        shiftedImportResult(option.timed!, Duration.zero),
        same(option.timed!),
      );
      expect(
        shiftedImportResult(option.plain, const Duration(seconds: 1)),
        same(option.plain),
      );
    });

    test('untimedImportResult strips the timestamps', () {
      final plain = untimedImportResult(option.timed!);
      expect(plain.document.isUntimed, isTrue);
      expect(plain.format, LyricImportFormat.plainText);
    });

    test('scriptConvertedImportResult converts Chinese lines', () {
      final converted = scriptConvertedImportResult(
        option.plain,
        ChineseScriptTarget.traditionalTaiwan,
      );
      expect(converted.document.lines[2].text, '城市的燈一盞盞亮起');
      expect(
        converted.document.metadata['scriptConvertedTo'],
        'traditionalTaiwan',
      );
      expect(scriptConvertedImportResult(option.plain, null), same(option.plain));
    });
  });
}
