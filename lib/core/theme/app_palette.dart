// The colour palettes the app can be shown in (decision D-042): the original
// dark grey and lavender, and a warm light paper. AppColors reads every
// themable token from the palette in use, so a screen that paints with
// `AppColors.textSecondary` follows the chosen theme without knowing there
// is one.

import 'package:flutter/material.dart';

/// Every colour of the interface that changes with the theme.
///
/// Colours that mean the same thing on any background stay constants of
/// `AppColors` instead: pure black and white (scrims and the QR code), the
/// brand red and paper of the app icon, and the black record with its
/// grooves and sheen.
///
/// The contrast numbers in the comments of [dark] and [light] are pinned by
/// `test/core/theme/app_palette_contrast_test.dart`.
@immutable
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.bgBase,
    required this.bgElevated,
    required this.bgSurface,
    required this.bgHighlight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.accent,
    required this.accentHover,
    required this.accentPressed,
    required this.accentMuted,
    required this.onAccent,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.error,
    required this.errorText,
    required this.onError,
    required this.warning,
    required this.success,
    required this.onSuccess,
    required this.info,
    required this.hoverOverlay,
    required this.pressedOverlay,
    required this.focusRing,
    required this.shadowNear,
    required this.shadowFar,
    required this.borderSubtle,
    required this.borderMuted,
    required this.borderStrong,
    required this.brandBars,
    required this.vinylAccent,
    required this.vinylAccentMuted,
    required this.onVinylAccent,
    required this.vinylDiscCenter,
    required this.vinylSurface,
    required this.vinylSurfaceHigh,
    required this.vinylHeroTop,
    required this.playDisc,
    required this.onPlayDisc,
    required this.playDiscBusy,
    required this.stage,
  });

  /// Whether the palette is light text on dark pages or the reverse; it
  /// picks the Material base theme and the status bar icons.
  final Brightness brightness;

  /// Pages, darkest to lightest in the dark palette (lightest to darkest in
  /// the light one): the page, cards and bars, inputs and raised panels,
  /// and the highlight of a selected row or a disabled fill.
  final Color bgBase;
  final Color bgElevated;
  final Color bgSurface;
  final Color bgHighlight;

  /// Text, from titles down to disabled labels.
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;

  /// Elysium Lavender: selection and primary actions.
  final Color accent;
  final Color accentHover;
  final Color accentPressed;

  /// The accent at 14–16 %, behind selected chips and tabs.
  final Color accentMuted;

  /// Labels and icons on [accent], [accentHover] and [accentPressed].
  final Color onAccent;

  /// The tonal accent of selected chips, tonal buttons and the navigation
  /// indicator, with [onAccentContainer] on it.
  final Color accentContainer;
  final Color onAccentContainer;

  /// Error fills and borders; [errorText] for error messages.
  final Color error;
  final Color errorText;
  final Color onError;

  final Color warning;

  /// "Done" green, and the check mark drawn on it.
  final Color success;
  final Color onSuccess;

  final Color info;

  /// Press and hover washes, the focus ring and the two elevation shadows.
  final Color hoverOverlay;
  final Color pressedOverlay;
  final Color focusRing;
  final Color shadowNear;
  final Color shadowFar;

  /// Dividers and card edges; [borderStrong] outlines controls (3:1).
  final Color borderSubtle;
  final Color borderMuted;
  final Color borderStrong;

  /// The bars of the brand mark beside its one red bar: the icon's paper
  /// white on dark pages, ink on light ones.
  final Color brandBars;

  /// Vinyl (D-041, violet since D-058): the orchid violet marks what is
  /// playing, the violet-tinted surfaces carry the listening home and the
  /// mini player.
  final Color vinylAccent;
  final Color vinylAccentMuted;

  /// The play icon and label on a [vinylAccent] fill.
  final Color onVinylAccent;

  /// Where the record's radial gradient starts; it ends on the record black.
  final Color vinylDiscCenter;
  final Color vinylSurface;
  final Color vinylSurfaceHigh;

  /// Top of the listening home's backdrop.
  final Color vinylHeroTop;

  /// The round play/pause button of the player bars and the transport, its
  /// icon, and its fill while playback loads under a spinner.
  final Color playDisc;
  final Color onPlayDisc;
  final Color playDiscBusy;

  /// The full-screen KTV stage under the lyrics, and the scrims that fade
  /// its controls in: black in the dark theme, the page in the light one.
  final Color stage;

  /// The dark palette: neutral greys with the lavender accent. These are the
  /// values the app had before it could change theme, unchanged.
  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    bgBase: Color(0xFF121212),
    bgElevated: Color(0xFF181818),
    bgSurface: Color(0xFF282828),
    bgHighlight: Color(0xFF3E3E3E),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB3B3B3),
    // Lifted from #6A6A6A so 12px captions reach WCAG AA (>=4.5:1) on
    // bgBase, bgElevated and bgSurface.
    textTertiary: Color(0xFF8F8F8F),
    textDisabled: Color(0xFF535353),
    // Lavender is far from every status colour and sits beside the icon's
    // Forge Red without competing with it (audit A-01).
    accent: Color(0xFFB69CFF),
    accentHover: Color(0xFFC7B3FF),
    accentPressed: Color(0xFF9F84F0),
    accentMuted: Color(0x29B69CFF),
    // Black on #B69CFF is 9.2:1 (7.0:1 on the pressed shade).
    onAccent: Color(0xFF000000),
    // Light lavender on deep lavender: 9.3:1.
    accentContainer: Color(0xFF3A2E66),
    onAccentContainer: Color(0xFFE8DEFF),
    error: Color(0xFFE22134),
    // 8.0:1 on bgBase, 6.3:1 on bgSurface, 4.6:1 on bgHighlight.
    errorText: Color(0xFFFF8585),
    // White on #E22134 is 4.7:1.
    onError: Color(0xFFFFFFFF),
    warning: Color(0xFFFFA42B),
    success: Color(0xFF1DB954),
    // Black on the green is 8.1:1.
    onSuccess: Color(0xFF000000),
    info: Color(0xFF2E77D0),
    hoverOverlay: Color(0x1AFFFFFF),
    pressedOverlay: Color(0x33FFFFFF),
    focusRing: Color(0x80FFFFFF),
    shadowNear: Color(0x66000000),
    shadowFar: Color(0x52000000),
    borderSubtle: Color(0x1AFFFFFF),
    borderMuted: Color(0x0DFFFFFF),
    // 4.1:1 on bgElevated.
    borderStrong: Color(0xFF7A7A7A),
    brandBars: Color(0xFFF6F2E8),
    // Orchid violet (D-058; it was brass, which read as brown): 7:1 or more
    // on every dark surface, a little redder and lighter than the lavender
    // accent beside it.
    vinylAccent: Color(0xFFD4A5FF),
    vinylAccentMuted: Color(0x29D4A5FF),
    // The record black on the violet: 9.8:1.
    onVinylAccent: Color(0xFF0E0C12),
    vinylDiscCenter: Color(0xFF1C1828),
    vinylSurface: Color(0xFF1C1828),
    vinylSurfaceHigh: Color(0xFF262036),
    vinylHeroTop: Color(0xFF2E2450),
    playDisc: Color(0xFFFFFFFF),
    onPlayDisc: Color(0xFF000000),
    // A black spinner on light grey: 10:1.
    playDiscBusy: Color(0xFFB3B3B3),
    stage: Color(0xFF000000),
  );

  /// The light palette: warm paper pages, near-black ink and a deep
  /// lavender accent, so selection keeps its colour from the dark theme.
  ///
  /// Every pair was recomputed for light pages rather than inverted: the
  /// accent, the error text, the vinyl violet and the status colours are all darker
  /// shades of the same hues, because the dark palette's light pastels fall
  /// to 1.5–2:1 on paper.
  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    bgBase: Color(0xFFF7F5F2),
    bgElevated: Color(0xFFFFFFFF),
    bgSurface: Color(0xFFEEEBE6),
    bgHighlight: Color(0xFFDEDAD3),
    // 16:1 on the page.
    textPrimary: Color(0xFF1A1817),
    // 8.0:1 on the page, 7.4:1 on bgSurface.
    textSecondary: Color(0xFF4F4A45),
    // 5.3:1 on the page, 4.8:1 on bgSurface.
    textTertiary: Color(0xFF6B655F),
    textDisabled: Color(0xFFA8A29B),
    // 6.7:1 on the page; white on it is 7.3:1.
    accent: Color(0xFF6236C9),
    accentHover: Color(0xFF5429B5),
    accentPressed: Color(0xFF45209A),
    accentMuted: Color(0x246236C9),
    onAccent: Color(0xFFFFFFFF),
    // Deep lavender ink on pale lavender: 12.4:1.
    accentContainer: Color(0xFFE6DEFF),
    onAccentContainer: Color(0xFF22115E),
    error: Color(0xFFC8102E),
    // 6.5:1 on the page, 5.1:1 on bgHighlight.
    errorText: Color(0xFFB0102A),
    onError: Color(0xFFFFFFFF),
    // Amber darkened to stay 4.5:1 or more as text on paper.
    warning: Color(0xFF9A5B00),
    success: Color(0xFF1E7B3A),
    // White on the deep green is 5.3:1.
    onSuccess: Color(0xFFFFFFFF),
    info: Color(0xFF1F62C2),
    hoverOverlay: Color(0x0F000000),
    pressedOverlay: Color(0x1F000000),
    focusRing: Color(0x99000000),
    shadowNear: Color(0x33000000),
    shadowFar: Color(0x24000000),
    borderSubtle: Color(0x1F000000),
    borderMuted: Color(0x0F000000),
    // 3.7:1 on white cards.
    borderStrong: Color(0xFF8A847D),
    brandBars: Color(0xFF1A1817),
    // The violet deepened for paper: 7.9:1 on the page, white on it 8.6:1.
    vinylAccent: Color(0xFF6A1FB0),
    vinylAccentMuted: Color(0x246A1FB0),
    onVinylAccent: Color(0xFFFFFFFF),
    // The record stays black in daylight; only its centre takes the tint.
    vinylDiscCenter: Color(0xFF261F33),
    vinylSurface: Color(0xFFF5F1FB),
    vinylSurfaceHigh: Color(0xFFEFE9F9),
    vinylHeroTop: Color(0xFFE4D9F7),
    // An ink disc with a white icon (17.7:1); white spinner on the busy disc
    // 7.0:1.
    playDisc: Color(0xFF1A1817),
    onPlayDisc: Color(0xFFFFFFFF),
    playDiscBusy: Color(0xFF5E5852),
    stage: Color(0xFFF7F5F2),
  );

  /// Every token by name, for tests and diagnostics.
  Map<String, Color> get tokens => {
    'bgBase': bgBase,
    'bgElevated': bgElevated,
    'bgSurface': bgSurface,
    'bgHighlight': bgHighlight,
    'textPrimary': textPrimary,
    'textSecondary': textSecondary,
    'textTertiary': textTertiary,
    'textDisabled': textDisabled,
    'accent': accent,
    'accentHover': accentHover,
    'accentPressed': accentPressed,
    'accentMuted': accentMuted,
    'onAccent': onAccent,
    'accentContainer': accentContainer,
    'onAccentContainer': onAccentContainer,
    'error': error,
    'errorText': errorText,
    'onError': onError,
    'warning': warning,
    'success': success,
    'onSuccess': onSuccess,
    'info': info,
    'hoverOverlay': hoverOverlay,
    'pressedOverlay': pressedOverlay,
    'focusRing': focusRing,
    'shadowNear': shadowNear,
    'shadowFar': shadowFar,
    'borderSubtle': borderSubtle,
    'borderMuted': borderMuted,
    'borderStrong': borderStrong,
    'brandBars': brandBars,
    'vinylAccent': vinylAccent,
    'vinylAccentMuted': vinylAccentMuted,
    'onVinylAccent': onVinylAccent,
    'vinylDiscCenter': vinylDiscCenter,
    'vinylSurface': vinylSurface,
    'vinylSurfaceHigh': vinylSurfaceHigh,
    'vinylHeroTop': vinylHeroTop,
    'playDisc': playDisc,
    'onPlayDisc': onPlayDisc,
    'playDiscBusy': playDiscBusy,
    'stage': stage,
  };
}

/// The themes the user can pick in 设置 › 外观 and from the rail.
enum AppThemeVariant {
  dark(
    id: 'dark',
    label: '深色',
    description: '深灰底色，适合夜间与暗光环境',
    icon: Icons.dark_mode_outlined,
    palette: AppPalette.dark,
  ),
  light(
    id: 'light',
    label: '浅色',
    description: '暖白纸张底色，适合白天与明亮环境',
    icon: Icons.light_mode_outlined,
    palette: AppPalette.light,
  );

  const AppThemeVariant({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.palette,
  });

  /// What the preference file stores; never change an existing id.
  final String id;

  /// The name shown in the settings card and the rail menu.
  final String label;
  final String description;
  final IconData icon;
  final AppPalette palette;

  /// The theme the app opens in until the user picks one.
  static const AppThemeVariant fallback = AppThemeVariant.dark;

  /// The variant stored as [id], or null for an unknown or missing id.
  static AppThemeVariant? fromId(Object? id) {
    for (final variant in values) {
      if (variant.id == id) return variant;
    }
    return null;
  }
}
