import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/navigation/app_chrome_scope.dart';
import 'package:lyric_forge_ktv/core/navigation/routes.dart';
import 'package:lyric_forge_ktv/core/theme/app_theme.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/core/widgets/app_tap_pulse.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/player_bar_destination_button.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.darkTheme,
  home: Scaffold(body: Center(child: child)),
);

double _pulseScale(WidgetTester tester, PlayerBarLink link) {
  final transform = tester.widget<Transform>(
    find
        .ancestor(of: find.byKey(link.key), matching: find.byType(Transform))
        .first,
  );
  return transform.transform.getMaxScaleOnAxis();
}

Color? _fill(WidgetTester tester, PlayerBarLink link) {
  return tester
      .widget<Material>(
        find
            .descendant(
              of: find.byKey(link.key),
              matching: find.byType(Material),
            )
            .first,
      )
      .color;
}

/// The `selected` flag announced around [link].
bool? _selectedSemantics(WidgetTester tester, PlayerBarLink link) {
  final semantics = tester.widget<Semantics>(
    find
        .ancestor(
          of: find.byKey(link.key),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.selected != null,
          ),
        )
        .first,
  );
  return semantics.properties.selected;
}

void main() {
  group('PlayerBarLink', () {
    test('音乐库 covers the song, artist and album sections', () {
      const link = PlayerBarLink.library;
      expect(link.isActiveFor(Routes.library), isTrue);
      expect(link.isActiveFor(Routes.libraryArtists), isTrue);
      expect(link.isActiveFor(Routes.libraryAlbums), isTrue);
      expect(link.isActiveFor(Routes.collections), isFalse);
      expect(link.isActiveFor(Routes.home), isFalse);
      expect(link.isActiveFor(null), isFalse);
    });

    test('收藏与播放列表 covers favourites and playlists', () {
      const link = PlayerBarLink.collections;
      expect(link.isActiveFor(Routes.collections), isTrue);
      expect(link.isActiveFor(Routes.playlists), isTrue);
      expect(link.isActiveFor(Routes.library), isFalse);
    });

    test('only its own page counts as already open', () {
      expect(PlayerBarLink.library.isOpenAt(Routes.library), isTrue);
      expect(PlayerBarLink.library.isOpenAt(Routes.libraryArtists), isFalse);
      expect(PlayerBarLink.collections.isOpenAt(Routes.playlists), isFalse);
      expect(PlayerBarLink.collections.isOpenAt('/collections?x=1'), isTrue);
      expect(PlayerBarLink.collections.isOpenAt(''), isFalse);
    });
  });

  group('PlayerBarDestinationButton', () {
    testWidgets('marks the page the user is on', (tester) async {
      await tester.pumpWidget(
        _host(
          PlayerBarDestinationButton(
            link: PlayerBarLink.library,
            currentRoute: Routes.libraryAlbums,
            onOpen: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.library_music_rounded), findsOneWidget);
      expect(find.byIcon(Icons.library_music_outlined), findsNothing);
      expect(_fill(tester, PlayerBarLink.library), AppColors.accentContainer);
      expect(_selectedSemantics(tester, PlayerBarLink.library), isTrue);
    });

    testWidgets('stays grey elsewhere and opens its page', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        _host(
          PlayerBarDestinationButton(
            link: PlayerBarLink.collections,
            currentRoute: Routes.home,
            onOpen: () => opened++,
          ),
        ),
      );

      expect(find.byIcon(Icons.collections_bookmark_outlined), findsOneWidget);
      expect(
        _fill(tester, PlayerBarLink.collections),
        isNot(AppColors.accentContainer),
      );
      expect(_selectedSemantics(tester, PlayerBarLink.collections), isFalse);

      await tester.tap(find.byKey(PlayerBarLink.collections.key));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });

    testWidgets('pressing the open page pulses instead of pushing it again', (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(
        _host(
          PlayerBarDestinationButton(
            link: PlayerBarLink.collections,
            currentRoute: Routes.collections,
            onOpen: () => opened++,
          ),
        ),
      );
      expect(_pulseScale(tester, PlayerBarLink.collections), 1);

      await tester.tap(find.byKey(PlayerBarLink.collections.key));
      // The press rebuilds on this frame; the pulse starts ticking after it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(opened, 0);
      expect(_pulseScale(tester, PlayerBarLink.collections), greaterThan(1.05));
      await tester.pumpAndSettle();
      expect(_pulseScale(tester, PlayerBarLink.collections), closeTo(1, 1e-9));
    });

    testWidgets('every press clicks', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        _host(
          PlayerBarDestinationButton(
            link: PlayerBarLink.library,
            currentRoute: Routes.library,
            onOpen: () {},
          ),
        ),
      );

      await tester.tap(find.byKey(PlayerBarLink.library.key));
      await tester.pumpAndSettle();

      expect(
        calls.where(
          (call) =>
              call.method == 'HapticFeedback.vibrate' &&
              call.arguments == 'HapticFeedbackType.selectionClick',
        ),
        isNotEmpty,
      );
    });
  });

  group('PlayerBarLinks', () {
    testWidgets('the highlight follows the route of the app shell', (
      tester,
    ) async {
      final route = ValueNotifier<String?>(Routes.home);
      addTearDown(route.dispose);
      final opened = <PlayerBarLink>[];
      await tester.pumpWidget(
        _host(
          AppChromeScope(
            navigatorKey: GlobalKey<NavigatorState>(),
            currentRoute: route,
            child: PlayerBarLinks(onOpen: opened.add),
          ),
        ),
      );

      expect(find.byIcon(Icons.library_music_outlined), findsOneWidget);
      expect(find.byIcon(Icons.collections_bookmark_outlined), findsOneWidget);

      route.value = Routes.playlists;
      await tester.pump();
      expect(find.byIcon(Icons.collections_bookmark_rounded), findsOneWidget);
      expect(find.byIcon(Icons.library_music_outlined), findsOneWidget);

      route.value = Routes.library;
      await tester.pump();
      expect(find.byIcon(Icons.library_music_rounded), findsOneWidget);

      await tester.tap(find.byKey(PlayerBarLink.collections.key));
      await tester.pumpAndSettle();
      expect(opened, [PlayerBarLink.collections]);
    });

    testWidgets('nothing is highlighted outside the app shell', (tester) async {
      await tester.pumpWidget(_host(PlayerBarLinks(onOpen: (_) {})));

      expect(find.byIcon(Icons.library_music_outlined), findsOneWidget);
      expect(find.byIcon(Icons.collections_bookmark_outlined), findsOneWidget);
      expect(find.byType(AppTapPulse), findsNWidgets(2));
    });
  });
}
