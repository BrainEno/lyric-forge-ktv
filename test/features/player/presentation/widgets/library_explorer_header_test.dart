import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_library_browse_item.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/library_explorer_header.dart';

/// D-059: the 歌曲 section's header, one toolbar at one height.
void main() {
  Future<_Taps> pump(
    WidgetTester tester, {
    int total = 128,
    int visible = 128,
    int playable = 128,
    bool withMenu = true,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final taps = _Taps();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => LibraryExplorerHeader(
              controller: TextEditingController(),
              query: '',
              total: total,
              visible: visible,
              playable: playable,
              smartView: LocalLibrarySmartView.all,
              sortMode: taps.sort,
              grid: taps.grid,
              countFor: (_) => total,
              onQuery: (_) {},
              onClearQuery: () {},
              onSmartView: (_) {},
              onSortMode: (mode) => setState(() => taps.sort = mode),
              onGrid: (grid) => setState(() => taps.grid = grid),
              onPlayAll: () => taps.playAll++,
              onShuffle: () => taps.shuffle++,
              onCleanMissing: null,
              menu: withMenu
                  ? IconButton(
                      key: const ValueKey('menu'),
                      onPressed: () {},
                      icon: const Icon(Icons.more_vert_rounded),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
    return taps;
  }

  testWidgets('every toolbar control stands the same touch height', (
    tester,
  ) async {
    await pump(tester);
    final heights = {
      for (final key in [
        LibraryExplorerHeader.playAllKey,
        LibraryExplorerHeader.shuffleKey,
        LibraryExplorerHeader.sortKey,
        LibraryExplorerHeader.viewKey,
        const ValueKey('menu'),
      ])
        key: tester.getSize(find.byKey(key)).height,
    };
    expect(heights.values.toSet(), {48.0}, reason: '$heights');
    // And on one line.
    final centres = {
      for (final key in heights.keys)
        tester.getCenter(find.byKey(key)).dy.roundToDouble(),
    };
    expect(centres, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('播放全部 is the one violet filled button', (tester) async {
    final taps = await pump(tester);
    final play = tester.widget<FilledButton>(
      find.byKey(LibraryExplorerHeader.playAllKey),
    );
    expect(
      play.style?.backgroundColor?.resolve(const <WidgetState>{}),
      AppColors.vinylAccent,
    );
    expect(
      find.byWidgetPredicate((widget) => widget is FilledButton),
      findsOneWidget,
    );
    expect(find.text(LibraryExplorerHeader.playAllLabel), findsOneWidget);

    await tester.tap(find.byKey(LibraryExplorerHeader.playAllKey));
    await tester.tap(find.byKey(LibraryExplorerHeader.shuffleKey));
    expect(taps.playAll, 1);
    expect(taps.shuffle, 1);
  });

  testWidgets('a narrowed list plays its results', (tester) async {
    await pump(tester, visible: 12, playable: 12);
    expect(find.text(LibraryExplorerHeader.playResultsLabel), findsOneWidget);
    expect(find.text('12 / 128 首'), findsOneWidget);
  });

  testWidgets('sort is a menu that marks the order in use', (tester) async {
    final taps = await pump(tester);
    await tester.tap(find.byKey(LibraryExplorerHeader.sortKey));
    await tester.pumpAndSettle();
    expect(find.byType(CheckedPopupMenuItem<LocalLibrarySortMode>), findsNWidgets(
      LocalLibrarySortMode.values.length,
    ));
    await tester.tap(find.text('按艺人'));
    await tester.pumpAndSettle();
    expect(taps.sort, LocalLibrarySortMode.artist);
    expect(
      find.byTooltip('排序：${LibraryExplorerHeader.sortLabel(taps.sort)}'),
      findsOneWidget,
    );
  });

  testWidgets('the view button switches between grid and list', (
    tester,
  ) async {
    final taps = await pump(tester);
    expect(find.byTooltip('网格显示'), findsOneWidget);
    await tester.tap(find.byKey(LibraryExplorerHeader.viewKey));
    await tester.pump();
    expect(taps.grid, isTrue);
    expect(find.byTooltip('列表显示'), findsOneWidget);
  });

  testWidgets('fits a small phone without overflow', (tester) async {
    await pump(tester, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
  });

  test('the counts line names what cannot be played only when some cannot', () {
    expect(
      LibraryExplorerHeader.countsLabel(total: 128, visible: 128, playable: 128),
      '128 首歌曲',
    );
    expect(
      LibraryExplorerHeader.countsLabel(total: 128, visible: 128, playable: 126),
      '128 首歌曲 · 2 首不可播放',
    );
    expect(
      LibraryExplorerHeader.countsLabel(total: 128, visible: 12, playable: 12),
      '12 / 128 首',
    );
  });
}

class _Taps {
  int playAll = 0;
  int shuffle = 0;
  LocalLibrarySortMode sort = LocalLibrarySortMode.title;
  bool grid = false;
}
