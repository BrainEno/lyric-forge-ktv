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

/// [overlay] composited over the opaque [base], as the screen shows it.
Color _over(Color overlay, Color base) => Color.alphaBlend(overlay, base);

/// Distance between two hues on the colour wheel, 0 to 180 degrees.
double _hueDistance(Color a, Color b) {
  final difference = (HSLColor.fromColor(a).hue - HSLColor.fromColor(b).hue)
      .abs();
  return difference > 180 ? 360 - difference : difference;
}

void main() {
  const pages = {
    'bgBase': AppColors.bgBase,
    'bgElevated': AppColors.bgElevated,
    'vinylSurface': AppColors.vinylSurface,
    'vinylSurfaceHigh': AppColors.vinylSurfaceHigh,
  };

  group('brass, the colour of what is playing', () {
    for (final entry in pages.entries) {
      test('reads as text on ${entry.key} (AAA)', () {
        expect(
          _contrast(AppColors.vinylBrass, entry.value),
          greaterThanOrEqualTo(7),
        );
      });
    }

    test('the playing row title stays AA on its own brass wash', () {
      final wash = _over(AppColors.vinylBrassMuted, AppColors.bgBase);
      expect(_contrast(AppColors.vinylBrass, wash), greaterThanOrEqualTo(4.5));
      expect(_contrast(AppColors.textPrimary, wash), greaterThanOrEqualTo(7));
    });

    test('the playing row subtitle uses secondary text, which stays AA', () {
      final wash = _over(AppColors.vinylBrassMuted, AppColors.bgBase);
      expect(
        _contrast(AppColors.textSecondary, wash),
        greaterThanOrEqualTo(4.5),
      );
      // The reason the row switches: tertiary text would drop below AA.
      expect(_contrast(AppColors.textTertiary, wash), lessThan(4.5));
    });

    test('the muted wash is brass at low opacity, not a new hue', () {
      expect(AppColors.vinylBrassMuted.withAlpha(255), AppColors.vinylBrass);
      expect(AppColors.vinylBrassMuted.a, lessThan(0.2));
    });

    test('it is not the warning amber, which keeps meaning attention', () {
      expect(AppColors.vinylBrass, isNot(AppColors.warning));
      // Same family, so a lightness gap keeps them apart.
      expect(
        HSLColor.fromColor(AppColors.vinylBrass).saturation,
        lessThan(HSLColor.fromColor(AppColors.warning).saturation),
      );
    });

    test('it stays far from the lavender accent of selection', () {
      expect(
        _hueDistance(AppColors.vinylBrass, AppColors.accent),
        greaterThanOrEqualTo(90),
      );
    });
  });

  group('warm surfaces', () {
    for (final surface in [
      AppColors.vinylSurface,
      AppColors.vinylSurfaceHigh,
    ]) {
      test('keep body text readable on $surface', () {
        expect(_contrast(AppColors.textPrimary, surface), greaterThan(12));
        expect(_contrast(AppColors.textSecondary, surface), greaterThan(7));
        expect(
          _contrast(AppColors.textTertiary, surface),
          greaterThanOrEqualTo(4.5),
        );
      });
    }

    test('the record stays darker than the page it sits on', () {
      expect(
        AppColors.vinylDisc.computeLuminance(),
        lessThan(AppColors.bgBase.computeLuminance()),
      );
    });

    test('grooves and sheen are faint overlays', () {
      expect(AppColors.vinylGroove.a, lessThan(0.15));
      expect(AppColors.vinylSheen.a, lessThan(0.25));
    });

    test('the hero gradient fades into the page colour', () {
      expect(AppColors.vinylHeroGradient.colors.last, AppColors.bgBase);
      expect(
        AppColors.vinylHeroGradient.colors,
        hasLength(AppColors.vinylHeroGradient.stops!.length),
      );
    });

    test('the bar gradient ends on the elevated surface of the controls', () {
      expect(
        AppColors.vinylBarGradient.colors.first,
        AppColors.vinylSurfaceHigh,
      );
      expect(AppColors.vinylBarGradient.colors.last, AppColors.bgElevated);
    });
  });

  group('brass buttons', () {
    test('the play disc icon on brass reaches AAA, busy or not', () {
      final style = AppTheme.vinylPlayDisc;
      final enabled = <WidgetState>{};
      final disabled = {WidgetState.disabled};
      for (final states in [enabled, disabled]) {
        final background = style.backgroundColor!.resolve(states)!;
        final foreground = style.foregroundColor!.resolve(states)!;
        expect(background, AppColors.vinylBrass);
        expect(_contrast(foreground, background), greaterThanOrEqualTo(7));
      }
    });

    test('the filled brass button reaches AAA', () {
      final style = AppTheme.vinylFilled;
      final background = style.backgroundColor!.resolve(<WidgetState>{})!;
      final foreground = style.foregroundColor!.resolve(<WidgetState>{})!;
      expect(background, AppColors.vinylBrass);
      expect(_contrast(foreground, background), greaterThanOrEqualTo(7));
    });
  });
}
