import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/navigation/app_chrome_scope.dart';
import 'package:lyric_forge_ktv/core/navigation/app_command_keys.dart';
import 'package:lyric_forge_ktv/core/navigation/app_navigation_shell.dart';
import 'package:lyric_forge_ktv/core/navigation/routes.dart';
import 'package:lyric_forge_ktv/core/theme/app_theme.dart';
import 'package:lyric_forge_ktv/core/widgets/app_search_button.dart';

void main() {
  late List<String> calls;

  setUp(() => calls = []);

  Widget scoped(Widget child, {bool search = true, bool shortcuts = true}) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: AppChromeScope(
        navigatorKey: GlobalKey<NavigatorState>(),
        currentRoute: ValueNotifier<String?>(Routes.home),
        onOpenSearch: search ? () => calls.add('search') : null,
        onShowShortcuts: shortcuts ? () => calls.add('shortcuts') : null,
        child: child,
      ),
    );
  }

  Future<void> pumpAt(WidgetTester tester, Widget widget, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
  }

  group('AppCommandKeys', () {
    test('names ⌘ on Apple platforms and Ctrl elsewhere', () {
      expect(AppCommandKeys.search(TargetPlatform.macOS), '⌘K');
      expect(AppCommandKeys.search(TargetPlatform.windows), 'Ctrl+K');
      expect(AppCommandKeys.modifier(TargetPlatform.iOS), '⌘');
      expect(AppCommandKeys.modifier(TargetPlatform.linux), 'Ctrl');
      expect(AppCommandKeys.hint('搜索', 'Ctrl+K'), '搜索（Ctrl+K）');
    });
  });

  group('AppSearchButton', () {
    testWidgets('is hidden where the app has no search', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AppSearchButton())),
      );
      expect(find.byKey(AppSearchButton.buttonKey), findsNothing);
    });

    testWidgets('opens the search', (tester) async {
      await tester.pumpWidget(
        scoped(const Scaffold(body: Center(child: AppSearchButton()))),
      );
      await tester.tap(find.byKey(AppSearchButton.buttonKey));
      expect(calls, ['search']);
    });

    test('names the shortcut only where there is a keyboard', () {
      expect(
        AppSearchButton.tooltipFor(TargetPlatform.windows),
        '搜索工程、歌曲、歌单和操作（Ctrl+K）',
      );
      expect(
        AppSearchButton.tooltipFor(TargetPlatform.macOS),
        endsWith('（⌘K）'),
      );
      expect(AppSearchButton.tooltipFor(TargetPlatform.iOS), '搜索工程、歌曲、歌单和操作');
    });
  });

  group('the rail', () {
    Widget rail({bool search = true, bool shortcuts = true}) => scoped(
      AppNavigationShell(
        currentRoute: Routes.home,
        onSelect: (_) {},
        child: const Scaffold(body: Text('内容')),
      ),
      search: search,
      shortcuts: shortcuts,
    );

    testWidgets('a collapsed rail has a search icon above the places', (
      tester,
    ) async {
      await pumpAt(tester, rail(), const Size(1000, 900));
      final search = find.byKey(AppNavigationRail.searchKey);
      expect(search, findsOneWidget);
      expect(find.byTooltip('搜索（Ctrl+K）'), findsOneWidget);
      await tester.tap(search);
      await tester.tap(find.byKey(AppNavigationRail.shortcutsKey));
      expect(calls, ['search', 'shortcuts']);
    });

    testWidgets('an extended rail has a search field with its keys', (
      tester,
    ) async {
      await pumpAt(tester, rail(), const Size(1400, 900));
      expect(
        find.descendant(
          of: find.byKey(AppNavigationRail.searchKey),
          matching: find.text('Ctrl+K'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('neither button without the launchers', (tester) async {
      await pumpAt(
        tester,
        rail(search: false, shortcuts: false),
        const Size(1400, 900),
      );
      expect(find.byKey(AppNavigationRail.searchKey), findsNothing);
      expect(find.byKey(AppNavigationRail.shortcutsKey), findsNothing);
    });
  });
}
