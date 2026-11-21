// Colour tokens for Elysium Player: neutral greys (or warm paper), a
// lavender accent, the app icon's brand colours and the status colours.
//
// Every themable token is a getter over the palette in use (decision D-042),
// so it follows the theme picked in 设置 › 外观. The values and the contrast
// reasoning live in app_palette.dart; the comments here say what each token
// is for. A getter cannot sit in a `const` expression: build the widget
// without `const` where it paints with a themable token.

import 'package:flutter/material.dart';

import 'app_palette.dart';

abstract class AppColors {
  static AppPalette _palette = AppPalette.dark;

  /// The palette every getter below reads.
  static AppPalette get palette => _palette;

  /// Switches the palette. Only the appearance controller and tests call
  /// this; everything already on screen has to be rebuilt to pick up the
  /// change (see `AppAppearanceHost`).
  static void usePalette(AppPalette palette) => _palette = palette;

  // Base: the same in every theme (scrims, the QR code's quiet zone).
  static const Color pureBlack = Color(0xFF000000);
  static const Color pureWhite = Color(0xFFFFFFFF);

  // Background hierarchy: page, cards and bars, raised panels, highlight
  // (darkest to lightest in the dark theme). Numbers in the comments below
  // are the dark theme's; app_palette.dart has both.
  static Color get bgBase => _palette.bgBase;
  static Color get bgElevated => _palette.bgElevated;
  static Color get bgSurface => _palette.bgSurface;
  static Color get bgHighlight => _palette.bgHighlight;

  // Text hierarchy
  static Color get textPrimary => _palette.textPrimary;
  static Color get textSecondary => _palette.textSecondary;
  // Lifted from #6A6A6A so 12px captions reach WCAG AA (>=4.5:1) on bgBase,
  // bgElevated and bgSurface.
  static Color get textTertiary => _palette.textTertiary;
  static Color get textDisabled => _palette.textDisabled;

  // Accent: Elysium Lavender. The accent used to be Spotify green #1DB954,
  // the same value as `success`, so "selected", "primary action" and "done"
  // all looked alike, and nothing tied the interface to the red, black and
  // paper-white app icon. Lavender is far from every status colour (error
  // red, warning amber, success green, info blue) and sits beside the icon's
  // Forge Red without competing with it; red stays reserved for the brand
  // mark and for errors (audit A-01).
  // test/core/theme/accent_palette_test.dart pins the contrast numbers.
  static Color get accent => _palette.accent;
  static Color get accentHover => _palette.accentHover;
  static Color get accentPressed => _palette.accentPressed;

  // Accent at 16 % for selected chips and tabs: white text on it over the
  // elevated background stays above 12:1.
  static Color get accentMuted => _palette.accentMuted;

  // Text and icons on accent fills: black on #B69CFF is 9.2:1 (7.0:1 on the
  // pressed shade); white would be 2.3:1. The light theme's deep lavender
  // takes white instead (7.3:1).
  static Color get onAccent => _palette.onAccent;

  // Accent container: deep lavender for selected chips, tonal buttons and the
  // navigation indicator, with light lavender on it (9.3:1). Material derives
  // these roles from the accent when they are not set, which put black
  // labels on the translucent selected-chip tint (1.6:1) and turned every
  // tonal button into a second primary button.
  // Every icon button variant used to share the grey icon colour of the
  // theme, so the icon on a filled lavender button was 1.1:1 against it.
  static Color get accentContainer => _palette.accentContainer;
  static Color get onAccentContainer => _palette.onAccentContainer;

  // Brand: Forge Red and paper white, sampled from the app icon. They are
  // kept for icon artwork only (the in-app mark was removed, D-049), so red
  // text and red states keep meaning "error". Forge Red on bgBase is 4.3:1,
  // above the 3:1 that graphics need (audit B-01).
  static const Color brand = Color(0xFFF11413);
  static const Color brandPaper = Color(0xFFF6F2E8);

  // The brand mark's other bars: paper on dark pages, ink on light ones.
  static Color get brandBars => _palette.brandBars;

  // Semantic colors
  // Error fills, borders, tints and large status icons.
  static Color get error => _palette.error;

  // Error messages and the small icons beside them. #E22134 as text was
  // 4.0:1 on bgBase and 3.2:1 on bgSurface, under the 4.5:1 that body text
  // needs, so failures were the hardest lines on screen to read. This
  // lighter red of the same hue is 8.0:1 on bgBase, 6.3:1 on bgSurface and
  // still 4.6:1 on bgHighlight and inside the red-tinted error banners.
  // test/core/theme/error_text_contrast_test.dart pins the numbers.
  static Color get errorText => _palette.errorText;

  // Text and icons on error fills (destructive buttons, recording). White on
  // #E22134 is 4.7:1.
  static Color get onError => _palette.onError;
  static Color get warning => _palette.warning;
  // Green now means "done" and nothing else; it is no longer the accent.
  static Color get success => _palette.success;

  // The check mark on a `success` fill.
  static Color get onSuccess => _palette.onSuccess;

  static Color get info => _palette.info;

  // Interactive states
  static Color get hoverOverlay => _palette.hoverOverlay;
  static Color get pressedOverlay => _palette.pressedOverlay;
  static Color get focusRing => _palette.focusRing;

  // Elevation shadows: a floating label close to its anchor, and a card
  // lifted well above the page.
  static Color get shadowNear => _palette.shadowNear;
  static Color get shadowFar => _palette.shadowFar;

  // Borders (subtle, used sparingly)
  static Color get borderSubtle => _palette.borderSubtle;
  static Color get borderMuted => _palette.borderMuted;

  // Outlines of controls (outlined buttons, unselected segments, switch
  // tracks), which need 3:1 against the page: 4.1:1 on bgElevated. Material
  // used white for them, which outshone the filled buttons beside them.
  static Color get borderStrong => _palette.borderStrong;

  // Vinyl: the warm, record-sleeve palette of the phone's listening surfaces
  // (decision D-041). Brass marks what is playing — the spinning record's
  // label ring, the rhythm bars, the playing row's title — and the warm
  // browns tint the surfaces around it. They are decoration and "now
  // playing" only: lavender stays the colour of selection and primary
  // actions, and amber `warning` keeps meaning "needs attention".
  // test/core/theme/vinyl_palette_test.dart pins the contrast numbers.
  static Color get vinylBrass => _palette.vinylBrass;

  // Brass at 16 %: the wash behind the playing row and the glow behind the
  // record.
  static Color get vinylBrassMuted => _palette.vinylBrassMuted;

  // The play icon and label on a brass fill: the record black on the light
  // brass of the dark theme, white on the bronze of the light theme.
  static Color get onVinylBrass => _palette.onVinylBrass;

  // The record itself: near-black with a warm cast, and the faint light
  // grooves and sheen drawn on it.
  static const Color vinylDisc = Color(0xFF0E0C0B);
  static const Color vinylGroove = Color(0x14FFFFFF);
  static const Color vinylSheen = Color(0x2EFFE8C7);

  // Brass for marks drawn on something dark in every theme — the ring round
  // the record's label, the rhythm bars over a dimmed cover — so it keeps
  // the light brass even where text brass turns bronze.
  static const Color vinylBrassOnDark = Color(0xFFE6B87A);

  // Where the record's radial gradient starts.
  static Color get vinylDiscCenter => _palette.vinylDiscCenter;

  // Warm surfaces: the hero card and the mini player sit on these instead of
  // the neutral greys. Secondary text (#B3B3B3) stays above 7:1 on both and
  // tertiary text (#8F8F8F) above 4.5:1.
  static Color get vinylSurface => _palette.vinylSurface;
  static Color get vinylSurfaceHigh => _palette.vinylSurfaceHigh;

  // The round play/pause button of the player bars and the transport: a
  // white disc with a black icon in the dark theme, an ink disc with a white
  // icon in the light one, and a quieter disc under the spinner while
  // playback loads.
  static Color get playDisc => _palette.playDisc;
  static Color get onPlayDisc => _palette.onPlayDisc;
  static Color get playDiscBusy => _palette.playDiscBusy;

  // The full-screen KTV stage and the scrims of its controls.
  static Color get stage => _palette.stage;

  // Gradients
  static LinearGradient get playerGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bgSurface, bgBase],
  );

  static LinearGradient get cardGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [bgSurface, bgElevated],
  );

  // The listening home's backdrop: a warm brown (a warm tan in the light
  // theme) that fades into the page.
  static LinearGradient get vinylHeroGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [_palette.vinylHeroTop, vinylSurface, bgBase],
    stops: const [0, 0.45, 1],
  );

  // The mobile mini player: warm on the artwork side, neutral at the
  // controls.
  static LinearGradient get vinylBarGradient => LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [vinylSurfaceHigh, bgElevated],
  );
}
