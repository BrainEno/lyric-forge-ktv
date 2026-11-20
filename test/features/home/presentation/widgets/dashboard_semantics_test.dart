import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/home/presentation/widgets/dashboard_semantics.dart';
import 'package:lyric_forge_ktv/features/home/presentation/widgets/dashboard_shelves.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/play_history.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';

// The dashboard's cards as a screen reader meets them (audit A-04): one
// button each, with what the colours and dots were showing said out loud.

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1200, 900);
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

Semantics _labelled(WidgetTester tester, String label) =>
    tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == label,
      ),
    );

void main() {
  group('statusLabel', () {
    test('every status has a word', () {
      final words = ProjectStatus.values
          .map(DashboardSemantics.statusLabel)
          .toList();
      expect(words, ['草稿', '导入中', '处理中', '识别中', '待校对', '就绪', '需要处理']);
      expect(words.toSet(), hasLength(ProjectStatus.values.length));
    });
  });

  group('listeningCard', () {
    test('title, artist and when it was played', () {
      expect(
        DashboardSemantics.listeningCard(
          title: '晴天',
          artist: '周杰伦',
          playedAt: '3分钟前',
        ),
        '晴天，周杰伦，3分钟前播放',
      );
    });

    test('a blank artist is left out', () {
      expect(
        DashboardSemantics.listeningCard(
          title: '晴天',
          artist: '  ',
          playedAt: '刚刚',
        ),
        '晴天，刚刚播放',
      );
    });

    test('a blank title still names the card', () {
      expect(
        DashboardSemantics.listeningCard(
          title: ' ',
          artist: null,
          playedAt: '昨天',
        ),
        '未命名歌曲，昨天播放',
      );
    });
  });

  group('projectCard', () {
    test('says the status the dot only showed as a colour', () {
      expect(
        DashboardSemantics.projectCard(
          name: '晴天',
          artist: '周杰伦',
          status: ProjectStatus.editing,
          lyricLines: 32,
          stage: '歌词已识别',
          progress: 4 / 6,
        ),
        '晴天，周杰伦，待校对，32 行歌词，歌词已识别，进度 67%',
      );
    });

    test('no lyrics yet and no artist', () {
      expect(
        DashboardSemantics.projectCard(
          name: '新工程',
          artist: null,
          status: ProjectStatus.draft,
          lyricLines: 0,
          stage: '待开始',
          progress: 0,
        ),
        '新工程，草稿，待生成歌词，待开始，进度 0%',
      );
    });

    test('progress is clamped to 0–100%', () {
      String withProgress(double progress) => DashboardSemantics.projectCard(
        name: 'x',
        artist: null,
        status: ProjectStatus.ready,
        lyricLines: 1,
        stage: '已导出',
        progress: progress,
      );
      expect(withProgress(1.4), endsWith('进度 100%'));
      expect(withProgress(-0.2), endsWith('进度 0%'));
    });
  });

  group('queueRow', () {
    test('the current song says it is playing', () {
      expect(
        DashboardSemantics.queueRow(title: '晴天', source: '周杰伦', current: true),
        '晴天，周杰伦，正在播放',
      );
      expect(
        DashboardSemantics.queueRow(
          title: '七里香',
          source: '本地音乐',
          current: false,
        ),
        '七里香，本地音乐',
      );
    });
  });

  group('cards', () {
    testWidgets('a project card is one button that opens the project', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final opened = <String>[];
      await _pump(
        tester,
        DashboardProjectGrid(
          projects: [
            ProjectManifest(
              id: 'a',
              name: '工程 a',
              artist: '歌手甲',
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
              status: ProjectStatus.ready,
              currentStage: ProcessingStage.exported,
            ),
          ],
          onOpen: (project) => opened.add(project.id),
        ),
      );

      const label = '工程 a，歌手甲，就绪，待生成歌词，已导出，进度 100%';
      expect(find.bySemanticsLabel(label), findsOneWidget);
      // The name is not read again on its own.
      expect(find.bySemanticsLabel('工程 a'), findsNothing);

      final card = _labelled(tester, label);
      expect(card.properties.button, isTrue);
      expect(card.properties.hint, DashboardSemantics.openProjectHint);
      card.properties.onTap!();
      expect(opened, ['a']);
      handle.dispose();
    });

    testWidgets('a listening card is one button that plays the entry', (
      tester,
    ) async {
      final played = <String>[];
      final entry = PlayHistory(
        id: 'one',
        name: '第一首',
        artist: '歌手乙',
        filePath: '/music/one.mp3',
        playedAt: DateTime.now(),
      );
      await _pump(
        tester,
        DashboardRecentShelf(
          histories: [entry],
          onPlay: (history) => played.add(history.id),
        ),
      );

      final label = DashboardSemantics.listeningCard(
        title: entry.name,
        artist: entry.artist,
        playedAt: entry.formattedPlayedAt,
      );
      final card = _labelled(tester, label);
      expect(card.properties.button, isTrue);
      expect(card.properties.hint, DashboardSemantics.playHint);
      card.properties.onTap!();
      expect(played, ['one']);
    });
  });
}
