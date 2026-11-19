import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lyric_forge_ktv/features/player/presentation/screens/local_music_library_shell.dart';

void main() {
  Future<void> pumpAt(
    WidgetTester tester,
    Size size, {
    int initialIndex = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: LocalMusicLibraryShell(
          initialIndex: initialIndex,
          sections: const [
            Center(child: Text('歌曲内容')),
            Center(child: Text('艺人内容')),
            Center(child: Text('专辑内容')),
            Center(child: Text('收藏内容')),
            Center(child: Text('歌单内容')),
          ],
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('五个分区都在，且不再自带第二套导航', (tester) async {
    await pumpAt(tester, const Size(1400, 900));

    for (final label in ['歌曲', '艺人', '专辑', '收藏', '歌单']) {
      expect(find.text(label), findsWidgets, reason: '缺少分区 $label');
    }

    // The shell used to have its own rail and its own bottom bar; with the
    // app-level navigation in place those stacked and 设置 appeared twice.
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('点击分区切换内容', (tester) async {
    await pumpAt(tester, const Size(1400, 900));

    ChoiceChip chipFor(String label) => tester.widget<ChoiceChip>(
      find.ancestor(of: find.text(label), matching: find.byType(ChoiceChip)),
    );

    expect(chipFor('歌曲').selected, isTrue);
    expect(chipFor('专辑').selected, isFalse);

    await tester.tap(find.text('专辑'));
    await tester.pumpAndSettle();

    expect(chipFor('专辑').selected, isTrue);
    expect(chipFor('歌曲').selected, isFalse);
    // The section body actually swapped, not just the chip.
    expect(find.text('专辑内容'), findsOneWidget);
  });

  testWidgets('initialIndex 打开对应分区', (tester) async {
    await pumpAt(tester, const Size(1400, 900), initialIndex: 4);

    final chip = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('歌单'), matching: find.byType(ChoiceChip)),
    );
    expect(chip.selected, isTrue);
  });

  testWidgets('窄屏也保留分区条，传输入口不重复', (tester) async {
    await pumpAt(tester, const Size(390, 844));

    expect(find.byType(ChoiceChip), findsNWidgets(5));
    expect(find.byTooltip('跨设备传输'), findsOneWidget);
  });

  testWidgets('窄屏传输入口在分区条里，不再用会遮挡列表的小浮动按钮', (tester) async {
    await pumpAt(tester, const Size(390, 844));

    // The 40 dp small FAB covered the last rows and missed the 48 dp target.
    expect(find.byType(FloatingActionButton), findsNothing);
    final button = find.byKey(LocalMusicLibraryShell.transferButtonKey);
    expect(button, findsOneWidget);
    final size = tester.getSize(button);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    // It shares the strip row with the chips instead of floating over content.
    expect(
      tester.getCenter(button).dy,
      moreOrLessEquals(tester.getCenter(find.text('歌曲')).dy, epsilon: 1),
    );
  });

  testWidgets('宽屏传输入口同样在分区条末尾', (tester) async {
    await pumpAt(tester, const Size(1400, 900));

    final button = find.byKey(LocalMusicLibraryShell.transferButtonKey);
    expect(button, findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(
      tester.getTopLeft(button).dx,
      greaterThan(tester.getTopRight(find.text('歌单')).dx),
    );
  });

  testWidgets('点击传输入口打开传输页面', (tester) async {
    final opened = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: (settings) {
          opened.add(settings.name);
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (context) => const Text('传输页面'),
          );
        },
        home: const LocalMusicLibraryShell(
          sections: [
            Text('歌曲内容'),
            Text('艺人内容'),
            Text('专辑内容'),
            Text('收藏内容'),
            Text('歌单内容'),
          ],
        ),
      ),
    );

    await tester.tap(find.byKey(LocalMusicLibraryShell.transferButtonKey));
    await tester.pumpAndSettle();

    expect(opened, hasLength(1));
    expect(find.text('传输页面'), findsOneWidget);
  });
}
