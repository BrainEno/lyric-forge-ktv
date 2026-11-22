import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/app_palette.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';

/// Every themable getter of AppColors by the palette token it reads.
Map<String, Color Function()> get _getters => {
  'bgBase': () => AppColors.bgBase,
  'bgElevated': () => AppColors.bgElevated,
  'bgSurface': () => AppColors.bgSurface,
  'bgHighlight': () => AppColors.bgHighlight,
  'textPrimary': () => AppColors.textPrimary,
  'textSecondary': () => AppColors.textSecondary,
  'textTertiary': () => AppColors.textTertiary,
  'textDisabled': () => AppColors.textDisabled,
  'accent': () => AppColors.accent,
  'accentHover': () => AppColors.accentHover,
  'accentPressed': () => AppColors.accentPressed,
  'accentMuted': () => AppColors.accentMuted,
  'onAccent': () => AppColors.onAccent,
  'accentContainer': () => AppColors.accentContainer,
  'onAccentContainer': () => AppColors.onAccentContainer,
  'error': () => AppColors.error,
  'errorText': () => AppColors.errorText,
  'onError': () => AppColors.onError,
  'warning': () => AppColors.warning,
  'success': () => AppColors.success,
  'onSuccess': () => AppColors.onSuccess,
  'info': () => AppColors.info,
  'hoverOverlay': () => AppColors.hoverOverlay,
  'pressedOverlay': () => AppColors.pressedOverlay,
  'focusRing': () => AppColors.focusRing,
  'shadowNear': () => AppColors.shadowNear,
  'shadowFar': () => AppColors.shadowFar,
  'borderSubtle': () => AppColors.borderSubtle,
  'borderMuted': () => AppColors.borderMuted,
  'borderStrong': () => AppColors.borderStrong,
  'brandBars': () => AppColors.brandBars,
  'vinylAccent': () => AppColors.vinylAccent,
  'vinylAccentMuted': () => AppColors.vinylAccentMuted,
  'onVinylAccent': () => AppColors.onVinylAccent,
  'vinylDiscCenter': () => AppColors.vinylDiscCenter,
  'vinylSurface': () => AppColors.vinylSurface,
  'vinylSurfaceHigh': () => AppColors.vinylSurfaceHigh,
  'vinylHeroTop': () => AppColors.palette.vinylHeroTop,
  'playDisc': () => AppColors.playDisc,
  'onPlayDisc': () => AppColors.onPlayDisc,
  'playDiscBusy': () => AppColors.playDiscBusy,
  'stage': () => AppColors.stage,
};

void main() {
  tearDown(() => AppColors.usePalette(AppPalette.dark));

  test('the app opens on the dark palette', () {
    expect(AppColors.palette, same(AppPalette.dark));
  });

  test('a getter exists for every palette token', () {
    expect(_getters.keys.toSet(), AppPalette.dark.tokens.keys.toSet());
  });

  for (final variant in AppThemeVariant.values) {
    group('with the ${variant.id} palette in use', () {
      setUp(() => AppColors.usePalette(variant.palette));

      test('palette reports it', () {
        expect(AppColors.palette, same(variant.palette));
      });

      for (final token in variant.palette.tokens.entries) {
        test('${token.key} reads the palette', () {
          expect(_getters[token.key]!(), token.value);
        });
      }

      test('the player gradient runs from the surface to the page', () {
        expect(AppColors.playerGradient.colors, [
          variant.palette.bgSurface,
          variant.palette.bgBase,
        ]);
      });

      test('the card gradient runs from the surface to the card', () {
        expect(AppColors.cardGradient.colors, [
          variant.palette.bgSurface,
          variant.palette.bgElevated,
        ]);
      });

      test('the hero backdrop fades from violet into the page', () {
        final gradient = AppColors.vinylHeroGradient;
        expect(gradient.colors, [
          variant.palette.vinylHeroTop,
          variant.palette.vinylSurface,
          variant.palette.bgBase,
        ]);
        expect(gradient.stops, [0, 0.45, 1]);
        expect(gradient.begin, Alignment.topCenter);
      });

      test('the mini player runs from tinted to the bar colour', () {
        expect(AppColors.vinylBarGradient.colors, [
          variant.palette.vinylSurfaceHigh,
          variant.palette.bgElevated,
        ]);
      });
    });
  }

  group('colours that mean the same on any page stay put', () {
    for (final variant in AppThemeVariant.values) {
      test('under ${variant.id}', () {
        AppColors.usePalette(variant.palette);
        expect(AppColors.pureBlack, const Color(0xFF000000));
        expect(AppColors.pureWhite, const Color(0xFFFFFFFF));
        expect(AppColors.brand, const Color(0xFFF11413));
        expect(AppColors.brandPaper, const Color(0xFFF6F2E8));
        expect(AppColors.vinylDisc, const Color(0xFF0E0C12));
        expect(AppColors.vinylGroove, const Color(0x14FFFFFF));
        expect(AppColors.vinylSheen, const Color(0x2EF0E6FF));
        expect(AppColors.vinylAccentOnDark, const Color(0xFFD4A5FF));
      });
    }

    test('the light violet for dark grounds reads on the record', () {
      final ring = AppColors.vinylAccentOnDark.computeLuminance();
      final record = AppColors.vinylDisc.computeLuminance();
      expect((ring + 0.05) / (record + 0.05), greaterThan(7));
    });
  });

  test('switching back restores every dark value', () {
    AppColors.usePalette(AppPalette.light);
    AppColors.usePalette(AppPalette.dark);
    for (final token in AppPalette.dark.tokens.entries) {
      expect(_getters[token.key]!(), token.value, reason: token.key);
    }
  });
}
