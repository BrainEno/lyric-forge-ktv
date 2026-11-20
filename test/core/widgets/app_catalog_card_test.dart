import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/layout/app_responsive.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/core/theme/spacing_tokens.dart';
import 'package:lyric_forge_ktv/core/widgets/app_artwork.dart';
import 'package:lyric_forge_ktv/core/widgets/app_catalog_card.dart';
import 'package:lyric_forge_ktv/core/widgets/app_tap_target.dart';

// AppCatalogCard is the one grid card of the music catalogs (audit L-04,
// T-03): the local artists, albums, songs and playlists and the phone's view
// of the desktop library used to draw four slightly different cards.

Future<void> _pump(
  WidgetTester tester,
  Widget card, {
  Size size = const Size(190, 260),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: size.width, height: size.height, child: card),
        ),
      ),
    ),
  );
}

AppCatalogCard _card({
  VoidCallback? onTap,
  bool enabled = true,
  bool unavailable = false,
  bool subtitleIsAlert = false,
  String? subtitle = '周杰伦 · 10 首',
  String? caption,
  Map<String, VoidCallback?> actions = const {},
  Widget? titleTrailing,
  Widget? artworkOverlay,
  bool compact = false,
}) {
  return AppCatalogCard(
    artwork: const AppArtwork(borderRadius: AppArtwork.tileRadius),
    title: '叶惠美',
    subtitle: subtitle,
    caption: caption,
    semanticLabel: '叶惠美，周杰伦 · 10 首',
    semanticHint: '打开专辑',
    onTap: onTap,
    enabled: enabled,
    unavailable: unavailable,
    subtitleIsAlert: subtitleIsAlert,
    semanticActions: actions,
    titleTrailing: titleTrailing,
    artworkOverlay: artworkOverlay,
    compact: compact,
  );
}

Material _surface(WidgetTester tester) => tester.widget<Material>(
  find
      .descendant(
        of: find.byType(AppCatalogCard),
        matching: find.byType(Material),
      )
      .first,
);

BorderSide _border(WidgetTester tester) =>
    (_surface(tester).shape! as RoundedRectangleBorder).side;

Text _text(WidgetTester tester, String data) =>
    tester.widget<Text>(find.text(data));

void main() {
  group('style', () {
    test('available items keep the muted border, missing ones turn red', () {
      expect(
        AppCatalogCard.borderColorFor(unavailable: false),
        AppColors.borderMuted,
      );
      expect(
        AppCatalogCard.borderColorFor(unavailable: true),
        AppColors.error.withAlpha(80),
      );
    });

    test('the subtitle is secondary text unless it reports a problem', () {
      expect(
        AppCatalogCard.subtitleColorFor(alert: false),
        AppColors.textSecondary,
      );
      expect(AppCatalogCard.subtitleColorFor(alert: true), AppColors.errorText);
    });

    test('phones get the tighter padding', () {
      expect(AppCatalogCard.paddingFor(compact: true), AppSpacing.sm);
      expect(AppCatalogCard.paddingFor(compact: false), AppSpacing.md);
    });

    test('one corner radius for every catalog card', () {
      expect(AppCatalogCard.radius, AppSpacing.radiusXLarge);
    });
  });

  group('grid', () {
    AppLayoutSpec layout(double width) =>
        AppResponsive.fromConstraints(BoxConstraints.tight(Size(width, 800)));

    test('a phone shows two columns and a wide window up to seven', () {
      expect(AppCatalogCard.columnsFor(layout(360)), 2);
      expect(AppCatalogCard.columnsFor(layout(4000)), 7);
    });

    test('every width gets between two and seven columns', () {
      for (var width = 280.0; width <= 3000; width += 40) {
        final columns = AppCatalogCard.columnsFor(layout(width));
        expect(columns, inInclusiveRange(2, 7), reason: '$width');
      }
    });

    test('within one width class more width never means fewer columns', () {
      var previous = 0;
      for (var width = 1300.0; width <= 1500; width += 20) {
        final columns = AppCatalogCard.columnsFor(layout(width));
        expect(columns, greaterThanOrEqualTo(previous), reason: '$width');
        previous = columns;
      }
    });

    test('the delegate uses the shared columns, ratio and spacing', () {
      final spec = layout(1280);
      final delegate =
          AppCatalogCard.gridDelegateFor(spec)
              as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, AppCatalogCard.columnsFor(spec));
      expect(delegate.childAspectRatio, AppCatalogCard.aspectRatioFor(spec));
      expect(delegate.crossAxisSpacing, AppSpacing.md);
      expect(delegate.mainAxisSpacing, AppSpacing.md);
    });

    test('cards are a little taller than wide on every width class', () {
      for (final width in [360.0, 700.0, 1100.0, 1500.0, 2000.0]) {
        final ratio = AppCatalogCard.aspectRatioFor(layout(width));
        expect(ratio, inExclusiveRange(0.6, 1.0), reason: '$width');
      }
    });

    test('phone tiles may be narrower than desktop tiles', () {
      expect(
        AppCatalogCard.minTileWidthFor(layout(360)),
        lessThan(AppCatalogCard.minTileWidthFor(layout(1400))),
      );
    });
  });

  group('layout', () {
    testWidgets('shows the title, subtitle and caption', (tester) async {
      await _pump(tester, _card(caption: 'FLAC · 有歌词'));

      expect(find.text('叶惠美'), findsOneWidget);
      expect(find.text('周杰伦 · 10 首'), findsOneWidget);
      expect(find.text('FLAC · 有歌词'), findsOneWidget);
      expect(_text(tester, '叶惠美').maxLines, 1);
      expect(_text(tester, '叶惠美').style?.fontWeight, FontWeight.w700);
    });

    testWidgets('leaves out an empty caption and a missing subtitle', (
      tester,
    ) async {
      await _pump(tester, _card(subtitle: null, caption: ''));

      expect(find.byType(Text), findsOneWidget);
      expect(find.text('叶惠美'), findsOneWidget);
    });

    testWidgets('the cover is the largest centred square above the text', (
      tester,
    ) async {
      await _pump(tester, _card(), size: const Size(190, 300));

      final cover = tester.getRect(find.byType(AppArtwork));
      expect(cover.width, moreOrLessEquals(cover.height));
      final card = tester.getRect(find.byType(AppCatalogCard));
      expect(cover.center.dx, moreOrLessEquals(card.center.dx));
      expect(
        cover.width,
        moreOrLessEquals(card.width - 2 * AppCatalogCard.paddingFor(compact: false)),
      );
      expect(cover.bottom, lessThan(tester.getTopLeft(find.text('叶惠美')).dy));
    });

    testWidgets('a short card shrinks the cover instead of overflowing', (
      tester,
    ) async {
      await _pump(tester, _card(caption: 'FLAC'), size: const Size(190, 170));

      expect(tester.takeException(), isNull);
      final cover = tester.getSize(find.byType(AppArtwork));
      expect(cover.width, moreOrLessEquals(cover.height));
      expect(cover.width, lessThan(190 - 2 * AppSpacing.md));
    });

    testWidgets('compact cards use the tighter padding', (tester) async {
      await _pump(tester, _card(compact: true), size: const Size(160, 260));

      final padding = tester.widget<Padding>(
        find
            .descendant(
              of: find.byType(InkWell),
              matching: find.byType(Padding),
            )
            .first,
      );
      expect(padding.padding, const EdgeInsets.all(AppSpacing.sm));
    });

    testWidgets('the surface is the Material so the ripple shows', (
      tester,
    ) async {
      await _pump(tester, _card(onTap: () {}));

      final surface = _surface(tester);
      expect(surface.color, AppColors.bgElevated);
      expect(surface.clipBehavior, Clip.antiAlias);
      final shape = surface.shape! as RoundedRectangleBorder;
      expect(
        shape.borderRadius,
        BorderRadius.circular(AppCatalogCard.radius),
      );
      // The InkWell sits inside the Material, not under an opaque box.
      expect(
        find.descendant(
          of: find.byWidget(surface),
          matching: find.byType(InkWell),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a missing item gets the red border', (tester) async {
      await _pump(tester, _card(unavailable: true));
      expect(_border(tester).color, AppColors.error.withAlpha(80));

      await _pump(tester, _card());
      expect(_border(tester).color, AppColors.borderMuted);
    });

    testWidgets('an alert subtitle is red', (tester) async {
      await _pump(
        tester,
        _card(subtitle: '12 首歌曲 · 2 首不可用', subtitleIsAlert: true),
      );
      expect(
        _text(tester, '12 首歌曲 · 2 首不可用').style?.color,
        AppColors.errorText,
      );
    });

    testWidgets('the title trailing control sits at the end of the title row', (
      tester,
    ) async {
      await _pump(
        tester,
        _card(
          titleTrailing: const Icon(Icons.more_horiz_rounded, size: 20),
        ),
      );

      final title = tester.getRect(find.text('叶惠美'));
      final menu = tester.getRect(find.byIcon(Icons.more_horiz_rounded));
      expect(menu.left, greaterThanOrEqualTo(title.right - 0.01));
      expect(menu.center.dy, moreOrLessEquals(title.center.dy, epsilon: 4));
    });

    testWidgets('the overlay sits in the cover top-right corner', (
      tester,
    ) async {
      await _pump(
        tester,
        _card(
          artworkOverlay: const Icon(Icons.more_vert_rounded, size: 24),
        ),
      );

      final cover = tester.getRect(find.byType(AppArtwork));
      final overlay = tester.getRect(find.byIcon(Icons.more_vert_rounded));
      expect(overlay.right, moreOrLessEquals(cover.right));
      expect(overlay.top, moreOrLessEquals(cover.top));
    });
  });

  group('taps', () {
    testWidgets('a tap anywhere on the card calls onTap', (tester) async {
      var taps = 0;
      await _pump(tester, _card(onTap: () => taps++));

      await tester.tap(find.byType(AppArtwork));
      await tester.tap(find.text('周杰伦 · 10 首'));
      expect(taps, 2);
    });

    testWidgets('a disabled card ignores taps', (tester) async {
      var taps = 0;
      await _pump(tester, _card(onTap: () => taps++, enabled: false));

      await tester.tap(find.text('叶惠美'));
      expect(taps, 0);
      expect(
        tester.widget<InkWell>(find.byType(InkWell)).onTap,
        isNull,
      );
    });
  });

  group('semantics', () {
    testWidgets('reads as one button with the label and hint', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await _pump(tester, _card(onTap: () => taps++, caption: 'FLAC'));

      expect(find.bySemanticsLabel('叶惠美，周杰伦 · 10 首'), findsOneWidget);
      expect(find.bySemanticsLabel('FLAC'), findsNothing);

      final target = tester.widget<AppTapTarget>(find.byType(AppTapTarget));
      expect(target.hint, '打开专辑');
      expect(target.enabled, isTrue);

      final data = tester
          .getSemantics(find.bySemanticsLabel('叶惠美，周杰伦 · 10 首'))
          .getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      final semantics = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byType(AppTapTarget),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(semantics.properties.button, isTrue);
      semantics.properties.onTap!();
      expect(taps, 1);
      handle.dispose();
    });

    testWidgets('the inner buttons become custom actions', (tester) async {
      final handle = tester.ensureSemantics();
      final calls = <String>[];
      await _pump(
        tester,
        _card(
          onTap: () {},
          actions: {
            '重命名': () => calls.add('rename'),
            '加入播放队列': null,
            '删除播放列表': () => calls.add('delete'),
          },
        ),
      );

      final target = tester.widget<AppTapTarget>(find.byType(AppTapTarget));
      expect(target.actions.keys, ['重命名', '加入播放队列', '删除播放列表']);
      final data = tester
          .getSemantics(find.bySemanticsLabel('叶惠美，周杰伦 · 10 首'))
          .getSemanticsData();
      expect(data.hasAction(SemanticsAction.customAction), isTrue);
      expect(data.customSemanticsActionIds, hasLength(2));
      handle.dispose();
    });

    testWidgets('a disabled card is read as disabled but keeps its actions', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        _card(
          onTap: () {},
          enabled: false,
          actions: {'重新定位文件': () {}},
        ),
      );

      final data = tester
          .getSemantics(find.bySemanticsLabel('叶惠美，周杰伦 · 10 首'))
          .getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(data.hasAction(SemanticsAction.customAction), isTrue);
      final target = tester.widget<AppTapTarget>(find.byType(AppTapTarget));
      expect(target.enabled, isFalse);
      expect(target.hint, '打开专辑');
      handle.dispose();
    });
  });
}
