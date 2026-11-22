import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/local_lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/online/online_lyric_candidate.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/online/online_lyric_query.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/online/song_lyrics_lookup.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/song_lyrics_preview_dialog.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_timing.dart';

import '../../../lyrics/domain/online/online_lyric_test_support.dart';

const _query = OnlineLyricQuery(
  title: '夜航',
  artist: '林小雨',
  duration: Duration(seconds: 56),
);

SongLyricsLookup _lookup(List<OnlineLyricCandidate> candidates) =>
    SongLyricsLookup(
      search: OnlineLyricSearchService(
        sources: [
          FakeLyricSource(OnlineLyricSourceKind.netease, results: candidates),
        ],
      ),
      importer: LocalLyricFileImportService(),
    );

class _Playback {
  final positions = StreamController<Duration>.broadcast();
  final seeks = <Duration>[];
  bool current = true;
  int plays = 0;

  SongLyricsPreviewPlayback build({bool canPlay = false}) =>
      SongLyricsPreviewPlayback(
        positionStream: positions.stream,
        currentPosition: () => Duration.zero,
        isCurrentSong: () => current,
        seek: (position) async => seeks.add(position),
        playSong: canPlay
            ? () async {
                plays++;
                current = true;
              }
            : null,
      );
}

Future<SongLyricsChoice?> Function() _open(
  WidgetTester tester,
  SongLyricsLookup lookup, {
  SongLyricsPreviewPlayback? playback,
}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 1000);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  late Future<SongLyricsChoice?> future;
  return () {
    final context = tester.element(find.byType(Scaffold));
    future = showSongLyricsPreviewDialog(
      context,
      lookup: lookup,
      query: _query,
      playback: playback,
    );
    return future;
  };
}

Future<void> _pumpHost(WidgetTester tester) => tester.pumpWidget(
  const MaterialApp(home: Scaffold(body: SizedBox.expand())),
);

/// Finds the song only when searched by its real title.
class _TitleOnlySource implements OnlineLyricSource {
  final queries = <OnlineLyricQuery>[];

  @override
  OnlineLyricSourceKind get kind => OnlineLyricSourceKind.netease;

  @override
  Future<List<OnlineLyricCandidate>> search(OnlineLyricQuery query) async {
    queries.add(query);
    return query.title == '夜航' ? [candidate()] : const [];
  }
}

void main() {
  testWidgets('a placeholder name falls back to the tag title (D-055)', (
    tester,
  ) async {
    final source = _TitleOnlySource();
    final lookup = SongLyricsLookup(
      search: OnlineLyricSearchService(sources: [source]),
      importer: LocalLyricFileImportService(),
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 1000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await _pumpHost(tester);
    final context = tester.element(find.byType(Scaffold));
    unawaited(
      showSongLyricsPreviewDialog(
        context,
        lookup: lookup,
        query: const OnlineLyricQuery(title: '新录音 12'),
        fallbackQueries: const [_query],
      ),
    );
    await tester.pumpAndSettle();

    expect(source.queries.map((query) => query.title), ['新录音 12', '夜航']);
    expect(find.text('窗外的雨停了又下'), findsOneWidget);
    // The fields show the search that worked, so 重新搜索 starts from it.
    expect(find.widgetWithText(TextField, '夜航'), findsOneWidget);
  });

  testWidgets('timed lyrics can be taken with their timing', (tester) async {
    final open = _open(tester, _lookup([candidate()]));
    await _pumpHost(tester);
    final future = open();
    await tester.pumpAndSettle();

    expect(find.text('联网获取歌词'), findsOneWidget);
    expect(find.text('带时间轴'), findsOneWidget);
    expect(find.text('窗外的雨停了又下'), findsOneWidget);
    expect(find.text('00:10'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('song-lyrics-use-timed')));
    await tester.pumpAndSettle();
    final choice = await future;
    expect(choice, isNotNull);
    expect(choice!.timed, isTrue);
    expect(
      choice.result.document.lines.first.startTime,
      const Duration(seconds: 10),
    );
  });

  testWidgets('the timestamps can be dropped to keep only the words', (
    tester,
  ) async {
    final open = _open(tester, _lookup([candidate()]));
    await _pumpHost(tester);
    final future = open();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('song-lyrics-use-plain')));
    await tester.pumpAndSettle();
    final choice = await future;
    expect(choice!.timed, isFalse);
    expect(choice.result.document.isUntimed, isTrue);
    expect(
      choice.result.document.lines.map((line) => line.text),
      kNightFlightLyric,
    );
  });

  testWidgets('a plain-text lyric offers only plain text', (tester) async {
    final open = _open(
      tester,
      _lookup([
        candidate(
          source: OnlineLyricSourceKind.lrclib,
          lyricText: kNightFlightLyric.join('\n'),
        ),
      ]),
    );
    await _pumpHost(tester);
    final future = open();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('song-lyrics-use-timed')), findsNothing);
    expect(find.text('采用纯文本歌词'), findsOneWidget);
    expect(find.textContaining('没有时间轴'), findsOneWidget);
    await tester.tap(find.text('采用纯文本歌词'));
    await tester.pumpAndSettle();
    expect((await future)!.timed, isFalse);
  });

  testWidgets('nothing found explains what to do next', (tester) async {
    final open = _open(tester, _lookup(const []));
    await _pumpHost(tester);
    final future = open();
    await tester.pumpAndSettle();

    expect(find.text('没有找到这首歌的歌词'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await future, isNull);
  });

  testWidgets('tapping a line seeks there, with the previewed shift', (
    tester,
  ) async {
    final playback = _Playback();
    addTearDown(playback.positions.close);
    final open = _open(
      tester,
      _lookup([candidate()]),
      playback: playback.build(),
    );
    await _pumpHost(tester);
    final future = open();
    await tester.pumpAndSettle();

    await tester.tap(find.text('城市的灯一盏盏亮起'));
    await tester.pumpAndSettle();
    expect(playback.seeks, [const Duration(seconds: 20)]);

    await tester.tap(find.byKey(const ValueKey('song-lyrics-later')));
    await tester.pumpAndSettle();
    expect(find.text('偏移 +0.5 秒'), findsOneWidget);
    await tester.tap(find.text('城市的灯一盏盏亮起'));
    await tester.pumpAndSettle();
    expect(playback.seeks.last, const Duration(milliseconds: 20500));

    playback.positions.add(const Duration(seconds: 21));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('song-lyrics-use-timed')));
    await tester.pumpAndSettle();
    final choice = await future;
    expect(
      choice!.result.document.globalOffset,
      const Duration(milliseconds: 500),
    );
  });

  testWidgets('another song playing is started before checking', (
    tester,
  ) async {
    final playback = _Playback()..current = false;
    addTearDown(playback.positions.close);
    final open = _open(
      tester,
      _lookup([candidate()]),
      playback: playback.build(canPlay: true),
    );
    await _pumpHost(tester);
    open();
    await tester.pumpAndSettle();

    expect(find.text('播放这首歌来核对'), findsOneWidget);
    await tester.tap(find.text('播放这首歌来核对'));
    await tester.pumpAndSettle();
    expect(playback.plays, 1);
    expect(find.text('播放这首歌来核对'), findsNothing);
  });

  testWidgets('the lyric can be converted to traditional script', (
    tester,
  ) async {
    final open = _open(tester, _lookup([candidate()]));
    await _pumpHost(tester);
    final future = open();
    await tester.pumpAndSettle();

    await tester.tap(find.text('繁體'));
    await tester.pumpAndSettle();
    expect(find.text('城市的燈一盞盞亮起'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('song-lyrics-use-timed')));
    await tester.pumpAndSettle();
    final choice = await future;
    expect(choice!.result.document.lines[2].text, '城市的燈一盞盞亮起');
  });

  test('formatLyricOffset', () {
    expect(formatLyricOffset(Duration.zero), '0 秒');
    expect(formatLyricOffset(const Duration(milliseconds: 500)), '+0.5 秒');
    expect(formatLyricOffset(const Duration(milliseconds: -1500)), '-1.5 秒');
  });
}
