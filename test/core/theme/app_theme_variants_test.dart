import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/app_palette.dart';
import 'package:lyric_forge_ktv/core/theme/app_theme.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';

const _disabled = {WidgetState.disabled};
const _selected = {WidgetState.selected};
const _pressed = {WidgetState.pressed};
const _hovered = {WidgetState.hovered};

void main() {
  tearDown(() => AppColors.usePalette(AppPalette.dark));

  group('AppTheme.themeFor', () {
    test('darkTheme and lightTheme are the two palettes', () {
      expect(AppTheme.darkTheme.brightness, Brightness.dark);
      expect(AppTheme.lightTheme.brightness, Brightness.light);
      expect(
        AppTheme.darkTheme.scaffoldBackgroundColor,
        AppPalette.dark.bgBase,
      );
      expect(
        AppTheme.lightTheme.scaffoldBackgroundColor,
        AppPalette.light.bgBase,
      );
    });

    test('current follows the palette in use', () {
      expect(AppTheme.current.brightness, Brightness.dark);
      AppColors.usePalette(AppPalette.light);
      expect(AppTheme.current.brightness, Brightness.light);
      expect(AppTheme.current.colorScheme.primary, AppPalette.light.accent);
    });

    for (final variant in AppThemeVariant.values) {
      final p = variant.palette;

      group('for ${variant.id}', () {
        // Built while the *other* palette is in use: every colour must come
        // from the palette passed in, not from AppColors.
        late ThemeData theme;
        setUp(() {
          AppColors.usePalette(
            variant == AppThemeVariant.dark
                ? AppPalette.light
                : AppPalette.dark,
          );
          theme = AppTheme.themeFor(p);
        });

        test('the colour scheme maps the palette', () {
          final scheme = theme.colorScheme;
          expect(scheme.brightness, p.brightness);
          expect(scheme.primary, p.accent);
          expect(scheme.onPrimary, p.onAccent);
          expect(scheme.primaryContainer, p.accentContainer);
          expect(scheme.onPrimaryContainer, p.onAccentContainer);
          expect(scheme.secondaryContainer, p.accentContainer);
          expect(scheme.onSecondaryContainer, p.onAccentContainer);
          expect(scheme.surface, p.bgSurface);
          expect(scheme.onSurface, p.textPrimary);
          expect(scheme.onSurfaceVariant, p.textSecondary);
          expect(scheme.error, p.error);
          expect(scheme.onError, p.onError);
          expect(scheme.outline, p.borderStrong);
          expect(scheme.surfaceTint, Colors.transparent);
        });

        test('pages, cards and dialogs use the palette greys', () {
          expect(theme.scaffoldBackgroundColor, p.bgBase);
          expect(theme.canvasColor, p.bgElevated);
          expect(theme.cardTheme.color, p.bgElevated);
          expect(theme.dialogTheme.backgroundColor, p.bgElevated);
          expect(theme.appBarTheme.backgroundColor, p.bgBase);
          expect(theme.appBarTheme.foregroundColor, p.textPrimary);
        });

        test('status bar icons contrast with the app bar', () {
          expect(
            theme.appBarTheme.systemOverlayStyle,
            p.brightness == Brightness.light
                ? SystemUiOverlayStyle.dark
                : SystemUiOverlayStyle.light,
          );
        });

        test('every text style is in a palette text colour', () {
          final allowed = {p.textPrimary, p.textSecondary, p.textTertiary};
          final styles = theme.textTheme;
          for (final style in [
            styles.displayLarge,
            styles.headlineMedium,
            styles.titleLarge,
            styles.titleSmall,
            styles.bodyLarge,
            styles.bodyMedium,
            styles.bodySmall,
            styles.labelLarge,
            styles.labelSmall,
          ]) {
            expect(allowed, contains(style!.color));
          }
          expect(styles.bodyLarge!.color, p.textPrimary);
          expect(styles.bodyMedium!.color, p.textSecondary);
          expect(styles.bodySmall!.color, p.textTertiary);
        });

        test('elevated buttons fill with the accent in each state', () {
          final style = theme.elevatedButtonTheme.style!;
          expect(style.backgroundColor!.resolve({}), p.accent);
          expect(style.backgroundColor!.resolve(_pressed), p.accentPressed);
          expect(style.backgroundColor!.resolve(_hovered), p.accentHover);
          expect(style.backgroundColor!.resolve(_disabled), p.bgHighlight);
          expect(style.foregroundColor!.resolve({}), p.onAccent);
          expect(style.foregroundColor!.resolve(_disabled), p.textTertiary);
        });

        test('filled buttons fall back to the palette when disabled', () {
          final style = theme.filledButtonTheme.style!;
          expect(style.backgroundColor!.resolve(_disabled), p.bgHighlight);
          expect(style.foregroundColor!.resolve(_disabled), p.textTertiary);
          expect(style.backgroundColor!.resolve({}), isNull);
          expect(style.overlayColor!.resolve(_pressed), p.pressedOverlay);
        });

        test('outlined buttons outline in borderStrong', () {
          final style = theme.outlinedButtonTheme.style!;
          expect(style.side!.resolve({})!.color, p.borderStrong);
          expect(style.side!.resolve(_disabled)!.color, p.borderSubtle);
          expect(style.foregroundColor!.resolve({}), p.textPrimary);
        });

        test('selected segments and chips take the accent container', () {
          final segment = theme.segmentedButtonTheme.style!;
          expect(
            segment.backgroundColor!.resolve(_selected),
            p.accentContainer,
          );
          expect(
            segment.foregroundColor!.resolve(_selected),
            p.onAccentContainer,
          );
          expect(theme.chipTheme.selectedColor, p.accentContainer);
          expect(theme.chipTheme.checkmarkColor, p.onAccentContainer);
          final side = theme.chipTheme.side! as WidgetStateBorderSide;
          expect(side.resolve(_selected)!.color, p.accent);
          expect(side.resolve({})!.color, p.borderSubtle);
        });

        test('switches, checkboxes and radios use the accent', () {
          final switches = theme.switchTheme;
          expect(switches.trackColor!.resolve(_selected), p.accent);
          expect(switches.thumbColor!.resolve(_selected), p.onAccent);
          expect(switches.trackColor!.resolve({}), p.bgHighlight);
          expect(theme.checkboxTheme.fillColor!.resolve(_selected), p.accent);
          expect(theme.checkboxTheme.checkColor!.resolve({}), p.onAccent);
          expect(theme.radioTheme.fillColor!.resolve(_selected), p.accent);
        });

        test('navigation shows the accent container pill', () {
          expect(theme.navigationBarTheme.backgroundColor, p.bgElevated);
          expect(theme.navigationBarTheme.indicatorColor, p.accentContainer);
          expect(
            theme.navigationBarTheme.iconTheme!.resolve(_selected)!.color,
            p.onAccentContainer,
          );
          expect(
            theme.navigationBarTheme.labelTextStyle!.resolve(_selected)!.color,
            p.textPrimary,
          );
          expect(theme.navigationRailTheme.backgroundColor, p.bgElevated);
          expect(
            theme.navigationRailTheme.unselectedLabelTextStyle!.color,
            p.textSecondary,
          );
        });

        test('inputs, sliders, progress and dividers use the palette', () {
          expect(theme.inputDecorationTheme.fillColor, p.bgSurface);
          expect(theme.inputDecorationTheme.hintStyle!.color, p.textTertiary);
          expect(theme.inputDecorationTheme.errorStyle!.color, p.errorText);
          expect(theme.sliderTheme.activeTrackColor, p.accent);
          expect(theme.sliderTheme.thumbColor, p.textPrimary);
          expect(theme.progressIndicatorTheme.color, p.accent);
          expect(theme.dividerTheme.color, p.borderSubtle);
          expect(theme.tabBarTheme.indicatorColor, p.accent);
        });

        test('snack bars and tooltips read on their fill', () {
          expect(theme.snackBarTheme.backgroundColor, p.bgHighlight);
          expect(theme.snackBarTheme.contentTextStyle!.color, p.textPrimary);
          expect(theme.tooltipTheme.textStyle!.color, p.textPrimary);
          final decoration = theme.tooltipTheme.decoration! as BoxDecoration;
          expect(decoration.color, p.bgSurface);
        });
      });
    }
  });

  group('shared styles', () {
    for (final variant in AppThemeVariant.values) {
      final p = variant.palette;

      test('the For builders use the palette given (${variant.id})', () {
        expect(AppTheme.accentFillFor(p).resolve({}), p.accent);
        expect(AppTheme.accentForegroundFor(p).resolve({}), p.onAccent);
        expect(AppTheme.fillOverlayFor(p).resolve(_hovered), p.hoverOverlay);
        expect(AppTheme.fillOverlayFor(p).resolve({}), isNull);
        expect(AppTheme.outlinedSideFor(p).resolve({})!.color, p.borderStrong);
        expect(AppTheme.disabledFillFor(p).resolve(_disabled), p.bgHighlight);
        expect(
          AppTheme.disabledForegroundFor(p).resolve(_disabled),
          p.textTertiary,
        );
        expect(AppTheme.navigationLabelFor(p).color, p.textSecondary);
        expect(AppTheme.navigationLabelSelectedFor(p).color, p.textPrimary);
      });

      test('the play disc and its busy state (${variant.id})', () {
        final style = AppTheme.playDiscFor(p);
        expect(style.backgroundColor!.resolve({}), p.playDisc);
        expect(style.foregroundColor!.resolve({}), p.onPlayDisc);
        expect(style.backgroundColor!.resolve(_disabled), p.playDiscBusy);
        expect(style.foregroundColor!.resolve(_disabled), p.onPlayDisc);
      });

      test('the brass buttons keep brass under a spinner (${variant.id})', () {
        final disc = AppTheme.vinylPlayDiscFor(p);
        expect(disc.backgroundColor!.resolve({}), p.vinylBrass);
        expect(disc.backgroundColor!.resolve(_disabled), p.vinylBrass);
        expect(disc.foregroundColor!.resolve(_disabled), p.onVinylBrass);
        final filled = AppTheme.vinylFilledFor(p);
        expect(filled.backgroundColor!.resolve({}), p.vinylBrass);
        expect(filled.foregroundColor!.resolve({}), p.onVinylBrass);
      });

      test('the busy accent disc stays the accent (${variant.id})', () {
        final style = AppTheme.busyAccentDiscFor(p);
        expect(style.backgroundColor!.resolve(_disabled), p.accent);
        expect(style.foregroundColor!.resolve(_disabled), p.onAccent);
      });
    }

    test('the getters follow the palette in use', () {
      AppColors.usePalette(AppPalette.light);
      expect(AppTheme.accentFill.resolve({}), AppPalette.light.accent);
      expect(
        AppTheme.playDisc.backgroundColor!.resolve({}),
        AppPalette.light.playDisc,
      );
      expect(
        AppTheme.vinylPlayDisc.foregroundColor!.resolve({}),
        AppPalette.light.onVinylBrass,
      );
      expect(
        AppTheme.chipSide.resolve(_selected)!.color,
        AppPalette.light.accent,
      );
      AppColors.usePalette(AppPalette.dark);
      expect(AppTheme.accentFill.resolve({}), AppPalette.dark.accent);
      expect(
        AppTheme.playDisc.backgroundColor!.resolve({}),
        AppPalette.dark.playDisc,
      );
    });
  });
}
