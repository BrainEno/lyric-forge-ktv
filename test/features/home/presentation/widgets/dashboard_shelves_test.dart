import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/home/presentation/widgets/dashboard_shelves.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/play_history.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';

// The dashboard's lower sections, now public widgets in their own file (audit
// D-06), can be pumped without the whole dashboard and its eight services.

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1200, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
  await tester.pump();
}

ProjectManifest _project(
  String id, {
  String? artist,
  ProcessingStage stage = ProcessingStage.none,
}) => ProjectManifest(
  id: id,
  name: '工程 $id',
  artist: artist,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  currentStage: stage,
);

Finder badge(String label) => find.text(label, findRichText: true);

void main() {
  group('DashboardSectionHeader', () {
    testWidgets('without an action it is only the title block', (tester) async {
      await _pump(
        tester,
        const DashboardSectionHeader(title: '最近听过', subtitle: '接着上次的进度'),
      );

      expect(find.text('最近听过'), findsOneWidget);
      expect(find.text('接着上次的进度'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('a wide window puts the action beside the title', (
      tester,
    ) async {
      var taps = 0;
      await _pump(
        tester,
        DashboardSectionHeader(
          title: '歌词工程',
          subtitle: '最近修改',
          action: '全部工程',
          onAction: () => taps++,
        ),
      );

      final title = tester.getCenter(find.text('歌词工程'));
      final action = tester.getCenter(find.text('全部工程'));
      expect(action.dx, greaterThan(title.dx));
      await tester.tap(find.text('全部工程'));
      expect(taps, 1);
    });

    testWidgets('a phone puts the action under the title', (tester) async {
      await _pump(
        tester,
        DashboardSectionHeader(
          title: '歌词工程',
          subtitle: '最近修改',
          action: '全部工程',
          onAction: () {},
        ),
        size: const Size(390, 844),
      );

      final subtitle = tester.getBottomLeft(find.text('最近修改'));
      final action = tester.getTopLeft(find.byType(TextButton));
      expect(action.dy, greaterThanOrEqualTo(subtitle.dy));
    });
  });

  group('DashboardEmptyCard', () {
    testWidgets('a null action leaves the card without a button', (
      tester,
    ) async {
      await _pump(
        tester,
        DashboardEmptyCard(
          icon: Icons.history_rounded,
          title: '还没有播放记录',
          message: '播放过的歌曲会出现在这里',
          action: null,
          onAction: () {},
        ),
      );

      expect(find.text('还没有播放记录'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('the action button runs the callback', (tester) async {
      var retries = 0;
      await _pump(
        tester,
        DashboardEmptyCard(
          icon: Icons.error_outline_rounded,
          title: '读取失败',
          message: '请重试',
          action: '重试',
          onAction: () => retries++,
          isError: true,
        ),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, '重试'));
      expect(retries, 1);
    });
  });

  group('DashboardProjectGrid', () {
    testWidgets('cards show the artist fallback and the stage', (tester) async {
      await _pump(
        tester,
        DashboardProjectGrid(
          projects: [
            _project('a', artist: '歌手甲', stage: ProcessingStage.exported),
            _project('b', artist: '  '),
          ],
          onOpen: (_) {},
        ),
      );

      expect(find.text('工程 a'), findsOneWidget);
      expect(find.text('歌手甲'), findsOneWidget);
      // A blank artist falls back to the generic label.
      expect(find.text('歌词工程'), findsOneWidget);
      // Badges lay their icon out inside a rich text.
      expect(badge('已导出'), findsOneWidget);
      expect(badge('待开始'), findsOneWidget);
      expect(badge('待生成歌词'), findsNWidgets(2));
    });

    testWidgets('tapping a card opens that project', (tester) async {
      final opened = <String>[];
      await _pump(
        tester,
        DashboardProjectGrid(
          projects: [_project('a'), _project('b')],
          onOpen: (project) => opened.add(project.id),
        ),
      );

      await tester.tap(find.text('工程 b'));
      expect(opened, ['b']);
    });

    testWidgets('a phone gets one column', (tester) async {
      await _pump(
        tester,
        DashboardProjectGrid(
          projects: [_project('a'), _project('b')],
          onOpen: (_) {},
        ),
        size: const Size(390, 844),
      );

      final first = tester.getTopLeft(find.text('工程 a'));
      final second = tester.getTopLeft(find.text('工程 b'));
      expect(second.dx, moreOrLessEquals(first.dx, epsilon: 1));
      expect(second.dy, greaterThan(first.dy));
    });
  });

  group('DashboardRecentShelf', () {
    testWidgets('tapping a card plays that entry', (tester) async {
      final entries = [
        PlayHistory(
          id: 'one',
          name: '第一首',
          artist: '歌手乙',
          filePath: '/music/one.mp3',
          playedAt: DateTime(2026),
        ),
        PlayHistory(
          id: 'two',
          name: '第二首',
          filePath: '/music/two.mp3',
          playedAt: DateTime(2026),
        ),
      ];
      final played = <String>[];
      await _pump(
        tester,
        DashboardRecentShelf(
          histories: entries,
          onPlay: (entry) => played.add(entry.id),
        ),
      );

      expect(find.text('歌手乙'), findsOneWidget);
      await tester.tap(find.text('第二首'));
      expect(played, ['two']);
    });
  });

  testWidgets('DashboardLoadingBlock reserves its height', (tester) async {
    await _pump(tester, const DashboardLoadingBlock(height: 120));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.getSize(find.byType(DashboardLoadingBlock)).height, 120);
  });
}
