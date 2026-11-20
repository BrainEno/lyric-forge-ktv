import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/diagnostics/app_build_info.dart';
import 'package:lyric_forge_ktv/core/theme/app_palette.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/core/widgets/app_brand_mark.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

Finder get _canvas => find.descendant(
  of: find.byType(AppBrandMark),
  matching: find.byType(CustomPaint),
);

void main() {
  test('the bars fade from left to right like the icon', () {
    const heights = AppBrandMark.barHeights;
    expect(heights.first, 1.0);
    for (var index = 1; index < heights.length; index++) {
      expect(heights[index], lessThan(heights[index - 1]));
    }
    expect(AppBrandMark.barWidths, hasLength(heights.length));
    expect(AppBrandMark.accentBar, inInclusiveRange(1, heights.length - 2));
  });

  test('Forge Red is visible on every dark surface it can sit on', () {
    // Graphics need 3:1 (WCAG 1.4.11).
    for (final surface in [
      AppColors.bgBase,
      AppColors.bgElevated,
      AppColors.bgSurface,
    ]) {
      expect(_contrast(AppColors.brand, surface), greaterThanOrEqualTo(3));
      expect(_contrast(AppColors.brandPaper, surface), greaterThan(10));
    }
  });

  test('Forge Red is not the error color', () {
    expect(AppColors.brand, isNot(AppColors.error));
  });

  testWidgets('sizes itself from its height', (tester) async {
    await tester.pumpWidget(_host(const AppBrandMark(size: 40)));

    final size = tester.getSize(_canvas);
    expect(size.height, 40);
    expect(size.width, moreOrLessEquals(40 * AppBrandMark.aspectRatio));
    expect(size.width, lessThan(size.height));
  });

  testWidgets('paints one Forge Red bar among paper-white ones', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const AppBrandMark()));

    final expected = paints;
    for (var index = 0; index < AppBrandMark.barHeights.length; index++) {
      expected.rect(
        color: index == AppBrandMark.accentBar
            ? AppColors.brand
            : AppColors.brandPaper,
      );
    }
    expect(tester.renderObject(_canvas), expected);
  });

  testWidgets('is labelled with the product name by default', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(const AppBrandMark()));

    expect(find.bySemanticsLabel(appDisplayName), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('an empty label keeps it out of the semantics tree', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBrandMark(semanticLabel: ''),
            Text(appDisplayName),
          ],
        ),
      ),
    );

    // Only the visible name is read.
    expect(find.bySemanticsLabel(appDisplayName), findsOneWidget);
    expect(
      find.ancestor(of: _canvas, matching: find.byType(ExcludeSemantics)),
      findsWidgets,
    );
    semantics.dispose();
  });

  group('in the light theme (D-042)', () {
    setUp(() => AppColors.usePalette(AppPalette.light));
    tearDown(() => AppColors.usePalette(AppPalette.dark));

    test('the bars turn to ink, legible on the paper page', () {
      expect(AppColors.brandBars, AppPalette.light.textPrimary);
      for (final surface in [
        AppColors.bgBase,
        AppColors.bgElevated,
        AppColors.bgSurface,
      ]) {
        expect(_contrast(AppColors.brandBars, surface), greaterThan(10));
        expect(_contrast(AppColors.brand, surface), greaterThanOrEqualTo(3));
      }
    });

    testWidgets('paints one Forge Red bar among ink ones', (tester) async {
      await tester.pumpWidget(_host(const AppBrandMark()));

      final expected = paints;
      for (var index = 0; index < AppBrandMark.barHeights.length; index++) {
        expected.rect(
          color: index == AppBrandMark.accentBar
              ? AppColors.brand
              : AppPalette.light.brandBars,
        );
      }
      expect(tester.renderObject(_canvas), expected);
    });

    testWidgets('repaints in the new colours when the theme changes', (
      tester,
    ) async {
      AppColors.usePalette(AppPalette.dark);
      await tester.pumpWidget(_host(const AppBrandMark(key: ValueKey(1))));
      AppColors.usePalette(AppPalette.light);
      await tester.pumpWidget(_host(const AppBrandMark(key: ValueKey(1))));
      // A const widget is not rebuilt by pumping it again; the appearance
      // host marks it dirty. Do the same here.
      tester.element(find.byType(AppBrandMark)).markNeedsBuild();
      await tester.pump();

      expect(
        tester.renderObject(_canvas),
        paints..rect(color: AppPalette.light.brandBars),
      );
      expect(
        tester.renderObject(_canvas),
        isNot(paints..rect(color: AppPalette.dark.brandBars)),
      );
    });
  });
}
