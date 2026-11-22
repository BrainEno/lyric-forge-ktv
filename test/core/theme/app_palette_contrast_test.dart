import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/app_palette.dart';

/// WCAG contrast ratio of two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// [over] laid on the opaque [base].
Color _over(Color over, Color base) => Color.alphaBlend(over, base);

/// Distance between two hues on the colour wheel, 0 to 180 degrees.
double _hueDistance(Color a, Color b) {
  final difference = (HSLColor.fromColor(a).hue - HSLColor.fromColor(b).hue)
      .abs();
  return difference > 180 ? 360 - difference : difference;
}

const _palettes = {'dark': AppPalette.dark, 'light': AppPalette.light};

Map<String, Color> _pages(AppPalette p) => {
  'bgBase': p.bgBase,
  'bgElevated': p.bgElevated,
  'bgSurface': p.bgSurface,
};

void main() {
  for (final entry in _palettes.entries) {
    final name = entry.key;
    final p = entry.value;

    group('$name palette: text on every page', () {
      for (final page in _pages(p).entries) {
        test('primary text on ${page.key} is 7:1 or more', () {
          expect(_contrast(p.textPrimary, page.value), greaterThan(7));
        });

        test('secondary text on ${page.key} is 4.5:1 or more', () {
          expect(_contrast(p.textSecondary, page.value), greaterThan(4.5));
        });

        test('tertiary captions on ${page.key} reach AA (4.5:1)', () {
          expect(_contrast(p.textTertiary, page.value), greaterThan(4.5));
        });

        test('error text on ${page.key} reaches AA', () {
          expect(_contrast(p.errorText, page.value), greaterThan(4.5));
        });

        test('the accent as text or a selected outline on ${page.key}', () {
          expect(_contrast(p.accent, page.value), greaterThan(4.5));
        });

        test('the vinyl violet as the playing title on ${page.key}', () {
          expect(_contrast(p.vinylAccent, page.value), greaterThan(4.5));
        });

        for (final status in {
          'error': p.error,
          'warning': p.warning,
          'success': p.success,
          'info': p.info,
        }.entries) {
          test('${status.key} icons on ${page.key} reach 3:1', () {
            expect(_contrast(status.value, page.value), greaterThan(3));
          });
        }
      }

      test('secondary text on the base page is 7:1 or more', () {
        expect(_contrast(p.textSecondary, p.bgBase), greaterThan(7));
      });

      test('primary text on the highlight (snack bars) is 7:1 or more', () {
        expect(_contrast(p.textPrimary, p.bgHighlight), greaterThan(7));
      });

      test('error text stays readable on the highlight', () {
        expect(_contrast(p.errorText, p.bgHighlight), greaterThan(4.5));
      });

      test('disabled labels on a disabled fill still read (3:1)', () {
        expect(_contrast(p.textTertiary, p.bgHighlight), greaterThan(3));
      });

      test('disabled text is quieter than tertiary text', () {
        expect(
          _contrast(p.textDisabled, p.bgBase),
          lessThan(_contrast(p.textTertiary, p.bgBase)),
        );
      });
    });

    group('$name palette: labels on fills', () {
      for (final fill in {
        'accent': p.accent,
        'accentHover': p.accentHover,
        'accentPressed': p.accentPressed,
      }.entries) {
        test('onAccent on ${fill.key} is 4.5:1 or more', () {
          expect(_contrast(p.onAccent, fill.value), greaterThan(4.5));
        });
      }

      test('onAccentContainer on accentContainer is 7:1 or more', () {
        expect(
          _contrast(p.onAccentContainer, p.accentContainer),
          greaterThan(7),
        );
      });

      test('onError on error fills is 4.5:1 or more', () {
        expect(_contrast(p.onError, p.error), greaterThan(4.5));
      });

      test('the check mark on a done step is 4.5:1 or more', () {
        expect(_contrast(p.onSuccess, p.success), greaterThan(4.5));
      });

      test('the play icon on the vinyl violet is 4.5:1 or more', () {
        expect(_contrast(p.onVinylAccent, p.vinylAccent), greaterThan(4.5));
      });

      test('the play disc icon is 7:1 or more', () {
        expect(_contrast(p.onPlayDisc, p.playDisc), greaterThan(7));
      });

      test('the spinner on the busy play disc is 4.5:1 or more', () {
        expect(_contrast(p.onPlayDisc, p.playDiscBusy), greaterThan(4.5));
      });

      for (final bar in {
        'bgElevated': p.bgElevated,
        'bgSurface': p.bgSurface,
      }.entries) {
        test('the play disc stands out from the ${bar.key} bar', () {
          expect(_contrast(p.playDisc, bar.value), greaterThan(3));
          expect(_contrast(p.playDiscBusy, bar.value), greaterThan(3));
        });
      }
    });

    group('$name palette: outlines and marks', () {
      test('control outlines reach 3:1 on cards and the page', () {
        expect(_contrast(p.borderStrong, p.bgElevated), greaterThan(3));
        expect(_contrast(p.borderStrong, p.bgBase), greaterThan(3));
      });

      test('the brand mark bars stand out from the page', () {
        expect(_contrast(p.brandBars, p.bgBase), greaterThan(7));
      });

      test('the subtle border is fainter than the strong one', () {
        expect(
          _contrast(_over(p.borderSubtle, p.bgElevated), p.bgElevated),
          lessThan(_contrast(p.borderStrong, p.bgElevated)),
        );
      });

      test('hover and press washes are visible and ordered', () {
        final hovered = _over(p.hoverOverlay, p.bgElevated);
        final pressed = _over(p.pressedOverlay, p.bgElevated);
        expect(hovered, isNot(p.bgElevated));
        expect(
          _contrast(pressed, p.bgElevated),
          greaterThan(_contrast(hovered, p.bgElevated)),
        );
      });

      test('the focus ring reaches 3:1 on cards', () {
        expect(
          _contrast(_over(p.focusRing, p.bgElevated), p.bgElevated),
          greaterThan(3),
        );
      });
    });

    group('$name palette: the tinted vinyl surfaces', () {
      final wash = _over(p.vinylAccentMuted, p.bgBase);
      final surfaces = {
        'vinylSurface': p.vinylSurface,
        'vinylSurfaceHigh': p.vinylSurfaceHigh,
        'violet wash': wash,
      };
      for (final surface in surfaces.entries) {
        test('text and the violet read on ${surface.key}', () {
          expect(_contrast(p.textPrimary, surface.value), greaterThan(7));
          expect(_contrast(p.textSecondary, surface.value), greaterThan(4.5));
          expect(_contrast(p.vinylAccent, surface.value), greaterThan(4.5));
        });
      }

      test('tertiary text reads on the tinted surfaces', () {
        expect(_contrast(p.textTertiary, p.vinylSurface), greaterThan(4.5));
        expect(_contrast(p.textTertiary, p.vinylSurfaceHigh), greaterThan(4.5));
      });

      test('the top of the hero backdrop keeps the title readable', () {
        expect(_contrast(p.textPrimary, p.vinylHeroTop), greaterThan(7));
        expect(_contrast(p.textSecondary, p.vinylHeroTop), greaterThan(4.5));
      });

      test('the record centre is dark, as a record is', () {
        expect(p.vinylDiscCenter.computeLuminance(), lessThan(0.05));
      });
    });

    group('$name palette: the KTV stage', () {
      test('lyrics read on the stage', () {
        expect(_contrast(p.textPrimary, p.stage), greaterThan(7));
        expect(_contrast(p.textSecondary, p.stage), greaterThan(4.5));
        expect(_contrast(p.textTertiary, p.stage), greaterThan(4.5));
      });

      test('the sung colour stands out from the stage', () {
        expect(_contrast(p.accent, p.stage), greaterThan(4.5));
      });
    });

    group('$name palette: colours keep their meanings apart', () {
      for (final status in {
        'error': p.error,
        'warning': p.warning,
        'success': p.success,
        'info': p.info,
      }.entries) {
        test('the accent is at least 40° from ${status.key}', () {
          expect(_hueDistance(p.accent, status.value), greaterThan(40));
        });
      }

      // D-058: the vinyl colour joined the accent's violet family instead
      // of standing against it as brass, but stays a colour of its own.
      test('the vinyl violet is near the accent hue but not the accent', () {
        expect(p.vinylAccent, isNot(p.accent));
        expect(_hueDistance(p.vinylAccent, p.accent), inInclusiveRange(8, 40));
      });

      test('the vinyl violet is far from the warning colour', () {
        expect(_hueDistance(p.vinylAccent, p.warning), greaterThan(90));
      });

      test('error text keeps the hue of the error fill', () {
        expect(_hueDistance(p.errorText, p.error), lessThan(15));
      });
    });

    group('$name palette: brightness', () {
      final pageIsLight = p.bgBase.computeLuminance() > 0.5;

      test('says which way round it is', () {
        expect(p.brightness, pageIsLight ? Brightness.light : Brightness.dark);
      });

      test('pages run from the page to raised panels in one direction', () {
        final base = p.bgBase.computeLuminance();
        final surface = p.bgSurface.computeLuminance();
        final highlight = p.bgHighlight.computeLuminance();
        if (pageIsLight) {
          expect(highlight, lessThan(surface));
          expect(surface, lessThan(base));
        } else {
          expect(base, lessThan(surface));
          expect(surface, lessThan(highlight));
        }
      });

      test('text runs from primary to disabled in one direction', () {
        final ratios = [
          p.textPrimary,
          p.textSecondary,
          p.textTertiary,
          p.textDisabled,
        ].map((c) => _contrast(c, p.bgBase)).toList();
        for (var i = 1; i < ratios.length; i++) {
          expect(ratios[i], lessThan(ratios[i - 1]));
        }
      });

      test('every token is opaque except the washes and overlays', () {
        const translucent = {
          'accentMuted',
          'hoverOverlay',
          'pressedOverlay',
          'focusRing',
          'shadowNear',
          'shadowFar',
          'borderSubtle',
          'borderMuted',
          'vinylAccentMuted',
        };
        for (final token in p.tokens.entries) {
          if (translucent.contains(token.key)) {
            expect(token.value.a, lessThan(1), reason: token.key);
          } else {
            expect(token.value.a, 1, reason: token.key);
          }
        }
      });
    });
  }

  group('the two palettes', () {
    test('list the same tokens', () {
      expect(
        AppPalette.light.tokens.keys.toList(),
        AppPalette.dark.tokens.keys.toList(),
      );
    });

    test('differ in every page and text token', () {
      for (final token in const [
        'bgBase',
        'bgElevated',
        'bgSurface',
        'bgHighlight',
        'textPrimary',
        'textSecondary',
        'textTertiary',
        'textDisabled',
        'accent',
        'onAccent',
        'accentContainer',
        'onAccentContainer',
        'errorText',
        'vinylAccent',
        'vinylSurface',
        'playDisc',
        'onPlayDisc',
        'stage',
      ]) {
        expect(
          AppPalette.light.tokens[token],
          isNot(AppPalette.dark.tokens[token]),
          reason: token,
        );
      }
    });

    test('the dark palette keeps the colours the app had before themes', () {
      // Picking 深色 must leave the app exactly as it was before D-042.
      const before = {
        'bgBase': 0xFF121212,
        'bgElevated': 0xFF181818,
        'bgSurface': 0xFF282828,
        'bgHighlight': 0xFF3E3E3E,
        'textPrimary': 0xFFFFFFFF,
        'textSecondary': 0xFFB3B3B3,
        'textTertiary': 0xFF8F8F8F,
        'textDisabled': 0xFF535353,
        'accent': 0xFFB69CFF,
        'accentHover': 0xFFC7B3FF,
        'accentPressed': 0xFF9F84F0,
        'accentMuted': 0x29B69CFF,
        'onAccent': 0xFF000000,
        'accentContainer': 0xFF3A2E66,
        'onAccentContainer': 0xFFE8DEFF,
        'error': 0xFFE22134,
        'errorText': 0xFFFF8585,
        'onError': 0xFFFFFFFF,
        'warning': 0xFFFFA42B,
        'success': 0xFF1DB954,
        'info': 0xFF2E77D0,
        'hoverOverlay': 0x1AFFFFFF,
        'pressedOverlay': 0x33FFFFFF,
        'focusRing': 0x80FFFFFF,
        'shadowNear': 0x66000000,
        'shadowFar': 0x52000000,
        'borderSubtle': 0x1AFFFFFF,
        'borderMuted': 0x0DFFFFFF,
        'borderStrong': 0xFF7A7A7A,
        'brandBars': 0xFFF6F2E8,
        // The vinyl tokens turned violet in D-058.
        'vinylAccent': 0xFFD4A5FF,
        'vinylAccentMuted': 0x29D4A5FF,
        'onVinylAccent': 0xFF0E0C12,
        'vinylDiscCenter': 0xFF1C1828,
        'vinylSurface': 0xFF1C1828,
        'vinylSurfaceHigh': 0xFF262036,
        'vinylHeroTop': 0xFF2E2450,
        'playDisc': 0xFFFFFFFF,
        'onPlayDisc': 0xFF000000,
        'playDiscBusy': 0xFFB3B3B3,
        'stage': 0xFF000000,
      };
      for (final token in before.entries) {
        expect(
          AppPalette.dark.tokens[token.key],
          Color(token.value),
          reason: token.key,
        );
      }
    });

    test('the light accent keeps the lavender hue of the dark one', () {
      expect(
        _hueDistance(AppPalette.light.accent, AppPalette.dark.accent),
        lessThan(10),
      );
    });

    test('the light vinyl violet keeps the hue of the dark one', () {
      expect(
        _hueDistance(AppPalette.light.vinylAccent, AppPalette.dark.vinylAccent),
        lessThan(10),
      );
    });
  });

  group('AppThemeVariant', () {
    test('offers dark and light, dark first', () {
      expect(AppThemeVariant.values, [
        AppThemeVariant.dark,
        AppThemeVariant.light,
      ]);
      expect(AppThemeVariant.fallback, AppThemeVariant.dark);
    });

    test('each variant carries its palette', () {
      expect(AppThemeVariant.dark.palette, same(AppPalette.dark));
      expect(AppThemeVariant.light.palette, same(AppPalette.light));
    });

    test('ids are stable and unique', () {
      expect(AppThemeVariant.dark.id, 'dark');
      expect(AppThemeVariant.light.id, 'light');
      final ids = AppThemeVariant.values.map((v) => v.id).toSet();
      expect(ids, hasLength(AppThemeVariant.values.length));
    });

    test('labels are the Chinese names users pick from', () {
      expect(AppThemeVariant.dark.label, '深色');
      expect(AppThemeVariant.light.label, '浅色');
      for (final variant in AppThemeVariant.values) {
        expect(variant.description, isNotEmpty);
      }
    });

    test('icons tell the two apart', () {
      expect(AppThemeVariant.dark.icon, isNot(AppThemeVariant.light.icon));
    });

    test('fromId reads back every id', () {
      for (final variant in AppThemeVariant.values) {
        expect(AppThemeVariant.fromId(variant.id), variant);
      }
    });

    test('fromId rejects unknown, empty and non-string ids', () {
      expect(AppThemeVariant.fromId('sepia'), isNull);
      expect(AppThemeVariant.fromId(''), isNull);
      expect(AppThemeVariant.fromId(null), isNull);
      expect(AppThemeVariant.fromId(1), isNull);
      expect(AppThemeVariant.fromId('Dark'), isNull);
    });
  });
}
