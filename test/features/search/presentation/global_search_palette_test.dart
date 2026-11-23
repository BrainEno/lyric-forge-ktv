import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/search/domain/global_search_actions.dart';
import 'package:lyric_forge_ktv/features/search/domain/global_search_item.dart';
import 'package:lyric_forge_ktv/features/search/domain/global_search_source.dart';
import 'package:lyric_forge_ktv/features/search/presentation/global_search_dependencies.dart';
import 'package:lyric_forge_ktv/features/search/presentation/widgets/global_search_palette.dart';
import 'package:lyric_forge_ktv/features/search/presentation/widgets/keyboard_shortcuts_panel.dart';

PlaybackItem _song(String title) => PlaybackItem(
  id: 'local:/music/$title.mp3',
  title: title,
  audioAsset: AudioAsset(originalPath: '/music/$title.mp3', format: 'mp3'),
);

final _items = <GlobalSearchItem>[
  ...globalSearchActions(phone: false),
  const GlobalSearchItem(
    kind: GlobalSearchKind.project,
    id: 'p1',
    title: '海阔天空',
    subtitle: 'Beyond',
    lyricLines: ['原谅我这一生不羁放纵爱自由'],
    target: OpenRouteTarget('/project/p1'),
  ),
  for (final title in ['Light My Fire', 'Fire'])
    GlobalSearchItem(
      kind: GlobalSearchKind.song,
      id: 'local:$title',
      title: title,
      subtitle: 'The Doors',
      target: PlaySongTarget(_song(title)),
    ),
  GlobalSearchItem(
    kind: GlobalSearchKind.playlist,
    id: 'drive',
    title: '开车听',
    subtitle: '2 首',
    target: OpenPlaylistTarget(
      playlistId: 'drive',
      route: '/playlists?playlist=drive',
      songs: [_song('A'), _song('B')],
    ),
  ),
];

void main() {
  late _Session session;
  late List<String> opened;

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    double textScale = 1,
    GlobalSearchSource? source,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dependencies = GlobalSearchDependencies(
      source: source ?? _Source(_items),
      playbackSession: session,
      openRoute: opened.add,
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showGlobalSearch(context, dependencies),
                child: const Text('open search'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open search'));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(GlobalSearchPalette.fieldKey), text);
    await tester.pumpAndSettle();
  }

  setUp(() {
    session = _Session();
    opened = [];
  });

  testWidgets('opens on the pages and recent projects', (tester) async {
    await pump(tester);
    expect(find.byType(GlobalSearchPalette), findsOneWidget);
    expect(find.text('常用'), findsOneWidget);
    expect(find.text('最近的工程'), findsOneWidget);
    expect(find.text('导入并识别'), findsOneWidget);
    expect(find.text('海阔天空'), findsOneWidget);
  });

  testWidgets('Enter plays the best match', (tester) async {
    await pump(tester);
    await type(tester, 'fire');
    expect(find.text('歌曲'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.byType(GlobalSearchPalette), findsNothing);
    expect(session.queued.single.map((item) => item.title), ['Fire']);
  });

  testWidgets('arrows move the selection, Shift+Enter queues', (tester) async {
    await pump(tester);
    await type(tester, 'fire');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(session.enqueued.map((item) => item.title), ['Light My Fire']);
    expect(session.queued, isEmpty);
    expect(find.text('已加入播放队列：Light My Fire'), findsOneWidget);
  });

  testWidgets('a page opens through the app shell', (tester) async {
    await pump(tester);
    await type(tester, 'shezhi');
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(opened, ['/settings']);
  });

  testWidgets('a lyric match shows the line and opens the project', (
    tester,
  ) async {
    await pump(tester);
    await type(tester, '爱自由');
    expect(find.text('歌词里提到'), findsOneWidget);
    expect(find.text('原谅我这一生不羁放纵爱自由', findRichText: true), findsOneWidget);
    await tester.tap(find.text('海阔天空'));
    await tester.pumpAndSettle();
    expect(opened, ['/project/p1']);
  });

  testWidgets('a playlist opens, or plays from its button', (tester) async {
    await pump(tester);
    await type(tester, '开车');
    final hit = GlobalSearchHit(
      item: _items.last,
      kind: GlobalSearchKind.playlist,
      score: 0,
    );
    await tester.tap(find.byKey(GlobalSearchPalette.secondaryKey(hit)));
    await tester.pumpAndSettle();
    expect(session.queued.single.map((item) => item.title), ['A', 'B']);
    expect(find.text('正在播放歌单“开车听”（2 首）'), findsOneWidget);

    await tester.tap(find.text('open search'));
    await tester.pumpAndSettle();
    await type(tester, '开车');
    await tester.tap(find.text('开车听', findRichText: true));
    await tester.pumpAndSettle();
    expect(opened, ['/playlists?playlist=drive']);
  });

  testWidgets('says when nothing is found', (tester) async {
    await pump(tester);
    await type(tester, 'zzzz');
    expect(find.byKey(GlobalSearchPalette.emptyKey), findsOneWidget);
    expect(find.text('没有找到“zzzz”'), findsOneWidget);
  });

  testWidgets('快捷键 opens the shortcut panel', (tester) async {
    await pump(tester);
    await type(tester, 'kuaijiejian');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.byType(KeyboardShortcutsPanel), findsOneWidget);
  });

  testWidgets('a source that fails can be retried', (tester) async {
    final source = _Source(_items)..failures = 1;
    await pump(tester, source: source);
    expect(find.text('没能读取搜索内容'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('常用'), findsOneWidget);
  });

  testWidgets('fills a narrow phone screen without overflow', (tester) async {
    await pump(tester, size: const Size(320, 568), textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('取消'), findsOneWidget);
    await type(tester, 'fire');
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(GlobalSearchPalette), findsNothing);
  });
}

class _Source implements GlobalSearchSource {
  _Source(this.items);

  final List<GlobalSearchItem> items;
  int failures = 0;

  @override
  Future<List<GlobalSearchItem>> load() async {
    if (failures > 0) {
      failures--;
      throw StateError('store is locked');
    }
    return items;
  }
}

class _Session extends Fake implements PlaybackSessionService {
  final List<List<PlaybackItem>> queued = [];
  final List<PlaybackItem> enqueued = [];

  @override
  Future<void> setQueue(List<PlaybackItem> items, {int startIndex = 0}) async {
    queued.add(items);
  }

  @override
  Future<void> enqueue(PlaybackItem item) async {
    enqueued.add(item);
  }
}
