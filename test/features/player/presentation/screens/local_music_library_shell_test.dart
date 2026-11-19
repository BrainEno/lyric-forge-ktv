import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lyric_forge_ktv/core/navigation/routes.dart';
import 'package:lyric_forge_ktv/core/widgets/app_tap_pulse.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_library_browse_item.dart';
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

  group('分区切换反馈', () {
    const bodies = [
      Center(child: Text('歌曲内容')),
      Center(child: Text('艺人内容')),
      Center(child: Text('专辑内容')),
      Center(child: Text('收藏内容')),
      Center(child: Text('歌单内容')),
    ];

    Widget shellApp({int initialIndex = 0, bool reduceMotion = false}) {
      return MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: LocalMusicLibraryShell(
              initialIndex: initialIndex,
              sections: bodies,
            ),
          ),
        ),
      );
    }

    void useSize(WidgetTester tester, Size size) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    List<String?> recordHaptics(WidgetTester tester) {
      final calls = <String?>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          calls.add(call.arguments as String?);
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      return calls;
    }

    AppTapPulse pulseFor(WidgetTester tester, String label) {
      final chip = find.ancestor(
        of: find.text(label),
        matching: find.byType(ChoiceChip),
      );
      final pulse = find.descendant(
        of: chip,
        matching: find.byType(AppTapPulse),
      );
      return tester.widget<AppTapPulse>(pulse);
    }

    double bodyOpacity(WidgetTester tester, String body) {
      final fade = find.ancestor(
        of: find.text(body),
        matching: find.byType(FadeTransition),
      );
      return tester.widget<FadeTransition>(fade.first).opacity.value;
    }

    testWidgets('每个分区图标都包在按压脉冲里', (tester) async {
      useSize(tester, const Size(1400, 900));
      await tester.pumpWidget(shellApp());

      for (final label in ['歌曲', '艺人', '专辑', '收藏', '歌单']) {
        expect(pulseFor(tester, label).trigger, 0, reason: label);
      }
    });

    testWidgets('点击分区时图标脉冲并给出选择触感', (tester) async {
      useSize(tester, const Size(1400, 900));
      final haptics = recordHaptics(tester);
      await tester.pumpWidget(shellApp());

      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();

      expect(pulseFor(tester, '收藏').trigger, 1);
      expect(pulseFor(tester, '歌曲').trigger, 0);
      expect(haptics, ['HapticFeedbackType.selectionClick']);
    });

    testWidgets('再次点击已选分区也有反馈，内容不变', (tester) async {
      useSize(tester, const Size(1400, 900));
      final haptics = recordHaptics(tester);
      await tester.pumpWidget(shellApp(initialIndex: 4));

      await tester.tap(find.text('歌单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('歌单'));
      await tester.pumpAndSettle();

      // Pressing the open section used to do nothing at all.
      expect(pulseFor(tester, '歌单').trigger, 2);
      expect(haptics, hasLength(2));
      final chip = tester.widget<ChoiceChip>(
        find.ancestor(of: find.text('歌单'), matching: find.byType(ChoiceChip)),
      );
      expect(chip.selected, isTrue);
      expect(find.text('歌单内容'), findsOneWidget);
    });

    testWidgets('切换分区时内容淡入，而不是一帧硬切', (tester) async {
      useSize(tester, const Size(1400, 900));
      await tester.pumpWidget(shellApp());
      expect(bodyOpacity(tester, '歌曲内容'), 1);

      await tester.tap(find.text('专辑'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(bodyOpacity(tester, '专辑内容'), lessThan(1));
      expect(bodyOpacity(tester, '专辑内容'), greaterThanOrEqualTo(0.4));

      await tester.pumpAndSettle();
      expect(bodyOpacity(tester, '专辑内容'), 1);
    });

    testWidgets('再次点击已选分区不会让内容闪一下', (tester) async {
      useSize(tester, const Size(1400, 900));
      await tester.pumpWidget(shellApp());

      await tester.tap(find.text('歌曲'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(bodyOpacity(tester, '歌曲内容'), 1);
    });

    testWidgets('减少动态效果时直接切换', (tester) async {
      useSize(tester, const Size(1400, 900));
      await tester.pumpWidget(shellApp(reduceMotion: true));

      await tester.tap(find.text('专辑'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(bodyOpacity(tester, '专辑内容'), 1);
    });

    testWidgets('从别处打开分区时，窄屏分区条滚到该分区', (tester) async {
      useSize(tester, const Size(320, 700));
      await tester.pumpWidget(shellApp());
      await tester.pumpAndSettle();

      // 歌单 starts past the right edge of a narrow strip.
      final width = tester.view.physicalSize.width;
      expect(tester.getTopRight(find.text('歌单')).dx, greaterThan(width));

      // The router reuses the shell and changes initialIndex when the player
      // bar opens 歌单.
      await tester.pumpWidget(shellApp(initialIndex: 4));
      await tester.pumpAndSettle();

      final chip = find.ancestor(
        of: find.text('歌单'),
        matching: find.byType(ChoiceChip),
      );
      expect(tester.getTopRight(chip).dx, lessThanOrEqualTo(width));
      expect(tester.getTopLeft(chip).dx, greaterThanOrEqualTo(0));
    });
  });

  group('library routes', () {
    test('each route opens its own section', () {
      expect(
        LocalMusicLibraryShell.targetFor(Routes.library),
        const LibraryShellTarget(0),
      );
      expect(
        LocalMusicLibraryShell.targetFor(Routes.libraryArtists),
        const LibraryShellTarget(1),
      );
      expect(
        LocalMusicLibraryShell.targetFor(Routes.libraryAlbums),
        const LibraryShellTarget(2),
      );
      expect(
        LocalMusicLibraryShell.targetFor(Routes.collections),
        const LibraryShellTarget(3),
      );
      expect(
        LocalMusicLibraryShell.targetFor(Routes.playlists),
        const LibraryShellTarget(4),
      );
    });

    test('the auto-paired route opens songs on the 自动配对 view', () {
      final target = LocalMusicLibraryShell.targetFor(Routes.libraryAutoPaired);

      expect(target?.index, 0);
      expect(target?.smartView, LocalLibrarySmartView.autoPairedLyrics);
      // Plain 歌曲 does not filter.
      expect(
        LocalMusicLibraryShell.targetFor(Routes.library)?.smartView,
        isNull,
      );
    });

    test('other routes are not library routes', () {
      expect(LocalMusicLibraryShell.targetFor(Routes.settings), isNull);
      expect(LocalMusicLibraryShell.targetFor('/library/unknown'), isNull);
      expect(LocalMusicLibraryShell.targetFor(Routes.home), isNull);
    });
  });
}
