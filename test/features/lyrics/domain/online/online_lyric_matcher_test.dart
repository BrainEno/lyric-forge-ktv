import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/local_lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/online/online_lyric_candidate.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/online/online_lyric_matcher.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/online/online_lyric_query.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/reference_lyric_text_parser.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/text/chinese_script_converter.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

import 'online_lyric_test_support.dart';

void main() {
  final matcher = OnlineLyricMatcher(
    parser: ReferenceLyricTextParser(LocalLyricFileImportService()),
  );
  const query = OnlineLyricQuery(
    title: '夜航',
    artist: '林小雨',
    duration: Duration(seconds: 56),
  );

  test('同一首歌的歌词被接受，署名行不进入参考', () {
    final match = matcher.evaluate(
      draft: nightFlightDraft(),
      candidate: candidate(),
      query: query,
    );
    expect(match, isNotNull);
    expect(match!.accepted, isTrue);
    expect(match.draftCoverage, greaterThanOrEqualTo(0.5));
    expect(match.input.lines.map((line) => line.text), kNightFlightLyric);
    expect(match.input.timed, isTrue);
    expect(match.timingOffset, Duration.zero);
  });

  test('整体偏移的时间戳被平移到录音上', () {
    final match = matcher.evaluate(
      draft: nightFlightDraft(),
      candidate: candidate(lyricText: nightFlightLrc(shiftMs: -2000)),
      query: query,
    )!;
    expect(match.accepted, isTrue);
    expect(match.timingOffset, const Duration(seconds: 2));
    expect(match.input.lines.first.startTime, const Duration(seconds: 10));
  });

  test('时间戳与录音对不上时只用文字', () {
    final scrambled = [
      for (var i = 0; i < kNightFlightLyric.length; i++)
        '[0${i % 2 == 0 ? 0 : 3}:${(i * 7 % 50 + 10).toString()}.00]'
            '${kNightFlightLyric[i]}',
    ].join('\n');
    final match = matcher.evaluate(
      draft: nightFlightDraft(),
      candidate: candidate(lyricText: scrambled),
      query: query,
    )!;
    expect(match.timingDropped, isTrue);
    expect(match.input.timed, isFalse);
    expect(match.input.lines.every((line) => line.startTime == null), isTrue);
  });

  test('同名但内容不同的歌不被接受', () {
    final other = candidate(
      id: '2',
      lyricText: ['海风吹过旧码头', '船笛声里有离愁', '我们约好明年再见', '你说要我等你回头'].join('\n'),
    );
    final match = matcher.evaluate(
      draft: nightFlightDraft(),
      candidate: other,
      query: query,
    );
    expect(match?.accepted ?? false, isFalse);
  });

  test('纯音乐候选被跳过', () {
    final match = matcher.evaluate(
      draft: nightFlightDraft(),
      candidate: candidate(lyricText: '[00:00.00]纯音乐，请欣赏'),
      query: query,
    );
    expect(match, isNull);
  });

  test('rank 把被接受的候选排在前面，元数据只用来排同分', () {
    final wrongSong = candidate(
      id: 'wrong',
      title: '夜航',
      artist: '林小雨',
      lyricText: '海风吹过旧码头\n船笛声里有离愁\n我们约好明年再见',
    );
    final cover = candidate(
      id: 'cover',
      artist: '翻唱者',
      duration: const Duration(seconds: 90),
    );
    final original = candidate(id: 'original');
    final ranked = matcher.rank(
      draft: nightFlightDraft(),
      candidates: [wrongSong, cover, original],
      query: query,
    );
    expect(ranked.first.candidate.sourceId, 'original');
    expect(ranked[1].candidate.sourceId, 'cover');
    expect(ranked.last.accepted, isFalse);
  });

  test('繁体歌词按简体草稿转换字形', () {
    const converter = ChineseScriptConverter();
    final traditional = [
      for (final line in kNightFlightLyric)
        converter.convertLine(line, ChineseScriptTarget.traditionalTaiwan),
    ].join('\n');
    final match = matcher.evaluate(
      draft: nightFlightDraft(),
      candidate: candidate(
        source: OnlineLyricSourceKind.lrclib,
        lyricText: traditional,
      ),
      query: query,
      scriptTarget: OnlineLyricMatcher.draftScriptTarget(nightFlightDraft()),
    )!;
    expect(match.accepted, isTrue);
    expect(match.input.lines[2].text, kNightFlightLyric[2]);
  });

  test('只有一行的草稿不自动接受', () {
    final draft = LyricDocument(
      language: 'zh',
      lines: [
        nightFlightDraft().lines.first.copyWith(text: kNightFlightLyric.first),
      ],
    );
    final match = matcher.evaluate(
      draft: draft,
      candidate: candidate(),
      query: query,
    );
    expect(match?.accepted ?? false, isFalse);
  });
}
