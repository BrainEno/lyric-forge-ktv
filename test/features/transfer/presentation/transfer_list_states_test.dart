import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/app_theme.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/core/widgets/app_empty_state.dart';
import 'package:lyric_forge_ktv/core/widgets/app_loading_state.dart';
import 'package:lyric_forge_ktv/features/transfer/presentation/widgets/transfer_list_states.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.darkTheme,
  home: Scaffold(body: ListView(children: [child])),
);

void main() {
  group('TransferErrorBanner', () {
    testWidgets('writes the message in the readable error red', (tester) async {
      await tester.pumpWidget(
        _host(const TransferErrorBanner(message: '播放失败：连接已断开')),
      );

      final text = tester.widget<Text>(find.text('播放失败：连接已断开'));
      expect(text.style?.color, AppColors.errorText);
      final icon = tester.widget<Icon>(
        find.byIcon(Icons.error_outline_rounded),
      );
      expect(icon.color, AppColors.errorText);
      expect(find.byTooltip(TransferErrorBanner.dismissTooltip), findsNothing);
    });

    testWidgets('the close button dismisses it', (tester) async {
      var dismissed = 0;
      await tester.pumpWidget(
        _host(
          TransferErrorBanner(message: '刷新音乐库失败', onDismiss: () => dismissed++),
        ),
      );

      await tester.tap(find.byTooltip(TransferErrorBanner.dismissTooltip));
      await tester.pump();

      expect(dismissed, 1);
    });

    testWidgets('is announced when it appears', (tester) async {
      await tester.pumpWidget(
        _host(const TransferErrorBanner(message: '读取下载内容失败')),
      );

      final semantics = tester.widgetList<Semantics>(
        find.ancestor(
          of: find.text('读取下载内容失败'),
          matching: find.byType(Semantics),
        ),
      );
      expect(
        semantics.any((widget) => widget.properties.liveRegion == true),
        isTrue,
      );
    });
  });

  group('TransferListLoading', () {
    testWidgets('says what is loading', (tester) async {
      await tester.pumpWidget(
        _host(
          const TransferListLoading(message: TransferListText.libraryLoading),
        ),
      );

      expect(find.byType(AppInlineLoading), findsOneWidget);
      expect(find.text(TransferListText.libraryLoading), findsOneWidget);
    });
  });

  group('TransferEmptyResult.reasonFor', () {
    test('a search wins over a filter', () {
      expect(
        TransferEmptyResult.reasonFor(query: '晴天', filtered: true),
        TransferEmptyReason.search,
      );
    });

    test('blank search text is not a search', () {
      expect(
        TransferEmptyResult.reasonFor(query: '   ', filtered: true),
        TransferEmptyReason.filter,
      );
      expect(
        TransferEmptyResult.reasonFor(query: '', filtered: false),
        TransferEmptyReason.nothing,
      );
    });

    test('the search title quotes the trimmed query', () {
      expect(TransferEmptyResult.searchTitle('  晴天 ', '歌曲'), '没有匹配“晴天”的歌曲');
    });
  });

  group('TransferEmptyResult', () {
    TransferEmptyResult build({
      String query = '',
      VoidCallback? onClearSearch,
      String? filteredTitle,
      VoidCallback? onShowAll,
    }) {
      return TransferEmptyResult(
        icon: Icons.library_music_outlined,
        noun: '歌曲',
        emptyTitle: TransferListText.libraryEmptyTitle,
        emptyMessage: TransferListText.libraryEmptyMessage,
        query: query,
        onClearSearch: onClearSearch,
        filteredTitle: filteredTitle,
        onShowAll: onShowAll,
      );
    }

    testWidgets('an empty library explains how to fill it', (tester) async {
      await tester.pumpWidget(_host(build()));

      final state = tester.widget<AppEmptyState>(find.byType(AppEmptyState));
      expect(state.title, TransferListText.libraryEmptyTitle);
      expect(state.message, TransferListText.libraryEmptyMessage);
      expect(state.density, AppEmptyStateDensity.panel);
      expect(state.icon, Icons.library_music_outlined);
      expect(state.actions, isEmpty);
    });

    testWidgets('a search without matches offers to clear it', (tester) async {
      var cleared = 0;
      await tester.pumpWidget(
        _host(
          build(
            query: '晴天',
            onClearSearch: () => cleared++,
            filteredTitle: TransferListText.downloadedFilterTitle,
            onShowAll: () {},
          ),
        ),
      );

      expect(find.text('没有匹配“晴天”的歌曲'), findsOneWidget);
      expect(find.text(TransferEmptyResult.searchMessage), findsOneWidget);
      expect(find.text(TransferEmptyResult.showAllLabel), findsNothing);
      final state = tester.widget<AppEmptyState>(find.byType(AppEmptyState));
      expect(state.icon, Icons.search_off_rounded);

      await tester.tap(find.text(TransferEmptyResult.clearSearchLabel));
      await tester.pump();
      expect(cleared, 1);
    });

    testWidgets('a filter that hides everything offers to show all', (
      tester,
    ) async {
      var shown = 0;
      await tester.pumpWidget(
        _host(
          build(
            filteredTitle: TransferListText.lyricsFilterTitle,
            onShowAll: () => shown++,
          ),
        ),
      );

      expect(find.text(TransferListText.lyricsFilterTitle), findsOneWidget);
      expect(find.text(TransferEmptyResult.filterMessage), findsOneWidget);
      expect(find.text(TransferEmptyResult.clearSearchLabel), findsNothing);

      await tester.tap(find.text(TransferEmptyResult.showAllLabel));
      await tester.pump();
      expect(shown, 1);
    });

    testWidgets('no button without a callback', (tester) async {
      await tester.pumpWidget(_host(build(query: '晴天')));

      expect(find.text('没有匹配“晴天”的歌曲'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
    });
  });

  group('screens', () {
    const screens = [
      'lib/features/transfer/presentation/screens/'
          'mobile_remote_music_library_screen.dart',
      'lib/features/transfer/presentation/screens/'
          'mobile_remote_grouped_library_screen.dart',
      'lib/features/transfer/presentation/screens/'
          'mobile_download_manager_screen.dart',
    ];

    for (final path in screens) {
      test('${path.split('/').last} uses the shared states', () {
        final source = File(path).readAsStringSync();
        expect(source, contains('TransferErrorBanner('));
        expect(source, contains('TransferListLoading('));
        expect(source, contains('TransferEmptyResult('));
        expect(source, contains('onClearSearch: _searchController.clear'));
        expect(source, isNot(contains('CircularProgressIndicator()')));
        expect(source, isNot(contains('没有匹配')));
        expect(
          source,
          isNot(contains('Text(_error!')),
          reason: 'errors go through TransferErrorBanner',
        );
      });
    }

    test('the songs list can drop its filter from the empty state', () {
      final source = File(screens.first).readAsStringSync();
      expect(source, contains('TransferListText.downloadedFilterTitle'));
      expect(source, contains('TransferListText.lyricsFilterTitle'));
      expect(source, contains('_filter = _RemoteLibraryFilter.all'));
    });
  });
}
