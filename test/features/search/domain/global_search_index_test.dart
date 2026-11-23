import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/navigation/routes.dart';
import 'package:lyric_forge_ktv/features/search/domain/global_search_actions.dart';
import 'package:lyric_forge_ktv/features/search/domain/global_search_index.dart';
import 'package:lyric_forge_ktv/features/search/domain/global_search_item.dart';

GlobalSearchItem _item(
  GlobalSearchKind kind,
  String title, {
  String? subtitle,
  List<String> keywords = const [],
  List<String> lyrics = const [],
}) => GlobalSearchItem(
  kind: kind,
  id: title,
  title: title,
  subtitle: subtitle,
  keywords: keywords,
  lyricLines: lyrics,
  target: const OpenRouteTarget('/'),
);

List<String> _titles(GlobalSearchResults results) =>
    results.hits.map((hit) => hit.item.title).toList();

void main() {
  group('normalizeSearchText', () {
    test('folds case, full-width forms and white space', () {
      expect(normalizeSearchText('  ＡＢＣ　 Song\tＯｎｅ '), 'abc song one');
      expect(normalizeSearchText('红豆'), '红豆');
    });

    test('findSearchMatch points into the original text', () {
      expect(findSearchMatch('Light My Fire', 'my f'), (start: 6, end: 10));
      expect(findSearchMatch('ＢＥＹＯＮＤ 海阔天空', 'beyond'), (start: 0, end: 6));
      expect(findSearchMatch('海阔天空', '光辉'), isNull);
      expect(findSearchMatch('海阔天空', ''), isNull);
    });
  });

  group('ranking', () {
    test('a whole title beats a prefix, a word and a substring', () {
      final index = GlobalSearchIndex([
        _item(GlobalSearchKind.song, 'Fireworks'),
        _item(GlobalSearchKind.song, 'Light My Fire'),
        _item(GlobalSearchKind.song, 'Campfire'),
        _item(GlobalSearchKind.song, 'Fire'),
      ]);
      expect(_titles(index.search('fire')), [
        'Fire',
        'Fireworks',
        'Light My Fire',
        'Campfire',
      ]);
    });

    test('every word has to appear, in the title or the subtitle', () {
      final index = GlobalSearchIndex([
        _item(GlobalSearchKind.song, '海阔天空', subtitle: 'Beyond · 乐与怒'),
        _item(GlobalSearchKind.song, '光辉岁月', subtitle: 'Beyond'),
        _item(GlobalSearchKind.song, '天空之城', subtitle: '李志'),
      ]);
      expect(_titles(index.search('beyond 天空')), ['海阔天空']);
      expect(_titles(index.search('天空')), ['天空之城', '海阔天空']);
    });

    test('keywords find pages by pinyin and English', () {
      final index = GlobalSearchIndex(globalSearchActions(phone: false));
      for (final query in ['shezhi', 'settings', 'sz']) {
        expect(index.search(query).hits.first.item.title, '设置', reason: query);
      }
      expect(index.search('回收站').hits.first.item.title, '最近删除');
    });

    test('a project found only in its lyrics is listed with the line', () {
      final index = GlobalSearchIndex([
        _item(
          GlobalSearchKind.project,
          '海阔天空',
          lyrics: ['今天我 寒夜里看雪飘过', '原谅我这一生不羁放纵爱自由'],
        ),
        _item(GlobalSearchKind.project, '自由行'),
      ]);
      final results = index.search('爱自由');
      final hit = results.hits.single;
      expect(hit.kind, GlobalSearchKind.lyric);
      expect(hit.lyricLine, '原谅我这一生不羁放纵爱自由');
      expect(hit.detail, '原谅我这一生不羁放纵爱自由');

      // A title match keeps the project in 工程, not twice.
      final both = index.search('自由');
      expect(both.groups.map((group) => group.kind), [
        GlobalSearchKind.project,
        GlobalSearchKind.lyric,
      ]);
    });

    test('groups are capped and say how many more there are', () {
      final index = GlobalSearchIndex([
        for (var i = 0; i < 12; i++) _item(GlobalSearchKind.song, '情歌 $i'),
      ]);
      final group = index.search('情歌').groups.single;
      expect(group.hits, hasLength(GlobalSearchKind.song.limit));
      expect(group.hidden, 12 - GlobalSearchKind.song.limit);
    });

    test('the group with the best match comes first', () {
      final index = GlobalSearchIndex([
        _item(GlobalSearchKind.action, '设置'),
        _item(GlobalSearchKind.song, '设置你的心情'),
        _item(GlobalSearchKind.playlist, '心情'),
      ]);
      expect(index.search('心情').groups.first.kind, GlobalSearchKind.playlist);
      expect(index.search('设置').groups.first.kind, GlobalSearchKind.action);
    });

    test('nothing found is empty', () {
      final index = GlobalSearchIndex([_item(GlobalSearchKind.song, 'A')]);
      expect(index.search('zzz').isEmpty, isTrue);
    });
  });

  group('browse', () {
    test('a blank query lists the pages, then the newest projects', () {
      final index = GlobalSearchIndex([
        ...globalSearchActions(phone: false),
        for (var i = 0; i < 8; i++) _item(GlobalSearchKind.project, 'P$i'),
        _item(GlobalSearchKind.song, 'Song'),
      ]);
      final results = index.search('   ');
      expect(results.groups.map((group) => group.kind), [
        GlobalSearchKind.action,
        GlobalSearchKind.project,
      ]);
      expect(results.groups.last.hits.map((hit) => hit.item.title), [
        'P0',
        'P1',
        'P2',
        'P3',
        'P4',
      ]);
    });
  });

  group('actions', () {
    test('the phone gets no recognition or project pages', () {
      final phone = globalSearchActions(phone: true);
      final routes = [
        for (final item in phone)
          if (item.target case OpenRouteTarget(:final route)) route,
      ];
      expect(routes, isNot(contains(Routes.import)));
      expect(routes, isNot(contains(Routes.projectTrash)));
      expect(phone.map((item) => item.id), isNot(contains('shortcuts')));
      expect(routes, contains(Routes.remoteLibrary));
    });

    test('the desktop opens 最近删除 and the shortcut panel', () {
      final desktop = globalSearchActions(phone: false);
      final trash = desktop.singleWhere((item) => item.id == 'trash');
      expect((trash.target as OpenRouteTarget).route, Routes.projectTrash);
      expect(
        desktop.singleWhere((item) => item.id == 'shortcuts').target,
        isA<ShowShortcutsTarget>(),
      );
      final ids = desktop.map((item) => item.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });
  });
}
