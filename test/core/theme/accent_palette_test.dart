import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/app_theme.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// Distance between two hues on the colour wheel, 0 to 180 degrees.
double _hueDistance(Color a, Color b) {
  final difference = (HSLColor.fromColor(a).hue - HSLColor.fromColor(b).hue)
      .abs();
  return difference > 180 ? 360 - difference : difference;
}

const _surfaces = {
  'bgBase': AppColors.bgBase,
  'bgElevated': AppColors.bgElevated,
  'bgSurface': AppColors.bgSurface,
};

void main() {
  group('the accent stays apart from every status colour', () {
    const statuses = {
      'error': AppColors.error,
      'warning': AppColors.warning,
      'success': AppColors.success,
      'info': AppColors.info,
      'brand': AppColors.brand,
    };

    for (final entry in statuses.entries) {
      test(entry.key, () {
        expect(AppColors.accent, isNot(entry.value));
        expect(
          _hueDistance(AppColors.accent, entry.value),
          greaterThanOrEqualTo(40),
          reason: 'the accent must not read as ${entry.key}',
        );
      });
    }

    test('it is no longer the success green', () {
      expect(AppColors.accent, isNot(AppColors.success));
      expect(AppColors.accentMuted.withAlpha(255), AppColors.accent);
    });
  });

  group('contrast', () {
    test('labels on accent fills reach AAA', () {
      for (final fill in [
        AppColors.accent,
        AppColors.accentHover,
        AppColors.accentPressed,
      ]) {
        expect(_contrast(AppColors.onAccent, fill), greaterThanOrEqualTo(7));
      }
    });

    test('accent text and icons reach AA on every surface', () {
      for (final entry in _surfaces.entries) {
        expect(
          _contrast(AppColors.accent, entry.value),
          greaterThanOrEqualTo(4.5),
          reason: entry.key,
        );
      }
    });

    test('white text stays readable on the muted accent', () {
      for (final entry in _surfaces.entries) {
        final tint = Color.alphaBlend(AppColors.accentMuted, entry.value);
        expect(
          _contrast(AppColors.textPrimary, tint),
          greaterThanOrEqualTo(7),
          reason: entry.key,
        );
      }
    });

    test('hover is lighter and pressed darker than the accent', () {
      final accent = AppColors.accent.computeLuminance();
      expect(AppColors.accentHover.computeLuminance(), greaterThan(accent));
      expect(AppColors.accentPressed.computeLuminance(), lessThan(accent));
    });
  });

  group('theme wiring', () {
    final theme = AppTheme.darkTheme;

    test('primary and secondary are the accent', () {
      expect(theme.colorScheme.primary, AppColors.accent);
      expect(theme.colorScheme.secondary, AppColors.accent);
      expect(theme.colorScheme.onPrimary, AppColors.onAccent);
    });

    test('errors keep their own colour', () {
      expect(theme.colorScheme.error, AppColors.error);
      expect(theme.colorScheme.error, isNot(theme.colorScheme.primary));
    });

    test('progress, sliders and focus use the accent', () {
      expect(theme.progressIndicatorTheme.color, AppColors.accent);
      expect(theme.sliderTheme.activeTrackColor, AppColors.accent);
      final focused = theme.inputDecorationTheme.focusedBorder;
      expect(focused, isA<OutlineInputBorder>());
      expect(
        (focused! as OutlineInputBorder).borderSide.color,
        AppColors.accent,
      );
    });
  });
}
