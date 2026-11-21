import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/app_palette.dart';
import 'package:lyric_forge_ktv/core/theme/app_theme.dart';
import 'package:lyric_forge_ktv/core/theme/app_typography.dart';

// One Chinese label used to mix two typefaces on Windows set to zh-TW: 音
// from Microsoft JhengHei, 乐库 from Microsoft YaHei. Every interface text
// style now names a Simplified Chinese font before the system fallback.

void _expectInterfaceFonts(TextStyle? style, String name) {
  expect(style, isNotNull, reason: name);
  expect(style!.fontFamily, AppTypography.family, reason: name);
  expect(style.fontFamilyFallback, AppTypography.fallback, reason: name);
}

void main() {
  group('AppTypography', () {
    test(
      'Windows: Segoe UI for Latin, Microsoft YaHei UI first for Chinese',
      () {
        expect(AppTypography.familyFor(TargetPlatform.windows), 'Segoe UI');
        final fallback = AppTypography.fallbackFor(TargetPlatform.windows);
        expect(fallback.first, 'Microsoft YaHei UI');
        expect(fallback, contains('Microsoft YaHei'));
        // No Traditional Chinese or Japanese font may come before them.
        expect(fallback, isNot(contains('Microsoft JhengHei')));
        expect(fallback, isNot(contains('Yu Gothic')));
      },
    );

    test('macOS and iOS prefer PingFang SC', () {
      for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
        expect(
          AppTypography.fallbackFor(platform).first,
          'PingFang SC',
          reason: '$platform',
        );
      }
    });

    test('Android and Linux prefer Noto Sans CJK SC', () {
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          AppTypography.fallbackFor(platform).first,
          'Noto Sans CJK SC',
          reason: '$platform',
        );
      }
    });

    test('every platform lists only Simplified Chinese fonts first', () {
      for (final platform in TargetPlatform.values) {
        final chinese = AppTypography.chineseFontsFor(platform);
        expect(chinese, isNotEmpty, reason: '$platform');
        expect(
          AppTypography.fallbackFor(platform).take(chinese.length),
          chinese,
          reason: '$platform',
        );
      }
    });

    test("the platform typography's own fallback is kept, once", () {
      final platformFallback =
          Typography.material2021(
            platform: TargetPlatform.linux,
          ).black.bodyMedium?.fontFamilyFallback ??
          const <String>[];
      final fallback = AppTypography.fallbackFor(TargetPlatform.linux);
      for (final family in platformFallback) {
        expect(fallback, contains(family));
      }
      expect(fallback.toSet(), hasLength(fallback.length));
    });

    test('apply keeps the rest of the style', () {
      final style = AppTypography.apply(
        const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      );
      expect(style.fontSize, 13);
      expect(style.fontWeight, FontWeight.w700);
      expect(style.fontFamilyFallback, AppTypography.fallback);
    });

    test('the current platform is followed', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        expect(AppTypography.family, 'Segoe UI');
        expect(AppTypography.fallback.first, 'Microsoft YaHei UI');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('the theme names the interface fonts everywhere', () {
    for (final palette in [AppPalette.dark, AppPalette.light]) {
      final name = palette.brightness.name;

      test('text themes ($name)', () {
        final theme = AppTheme.themeFor(palette);
        final text = theme.textTheme;
        for (final entry in {
          'displayLarge': text.displayLarge,
          'headlineSmall': text.headlineSmall,
          'titleMedium': text.titleMedium,
          'bodyMedium': text.bodyMedium,
          'bodySmall': text.bodySmall,
          'labelLarge': text.labelLarge,
          'labelMedium': text.labelMedium,
          'primary bodyMedium': theme.primaryTextTheme.bodyMedium,
        }.entries) {
          _expectInterfaceFonts(entry.value, '${entry.key} ($name)');
        }
      });

      test(
        'component styles that do not merge with the text theme ($name)',
        () {
          final theme = AppTheme.themeFor(palette);
          _expectInterfaceFonts(
            theme.navigationRailTheme.selectedLabelTextStyle,
            'rail selected',
          );
          _expectInterfaceFonts(
            theme.navigationRailTheme.unselectedLabelTextStyle,
            'rail unselected',
          );
          _expectInterfaceFonts(theme.appBarTheme.titleTextStyle, 'app bar');
          _expectInterfaceFonts(theme.tooltipTheme.textStyle, 'tooltip');
          _expectInterfaceFonts(
            theme.snackBarTheme.contentTextStyle,
            'snack bar',
          );
          _expectInterfaceFonts(
            theme.inputDecorationTheme.hintStyle,
            'input hint',
          );
          _expectInterfaceFonts(
            theme.inputDecorationTheme.errorStyle,
            'input error',
          );
          _expectInterfaceFonts(
            AppTheme.navigationLabelFor(palette),
            'navigation label',
          );
        },
      );
    }
  });

  testWidgets('a navigation rail label is drawn with the Chinese fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.themeFor(AppPalette.light),
        home: Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: 0,
                labelType: NavigationRailLabelType.all,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.folder),
                    label: Text('工程'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.library_music),
                    label: Text('音乐库'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    final label = tester.renderObject<RenderParagraph>(find.text('音乐库'));
    expect(label.text.style?.fontFamilyFallback, AppTypography.fallback);
  });
}
