// Dark theme colour tokens for Elysium Player: neutral greys, a lavender
// accent, the app icon's brand colours and the status colours.

import 'package:flutter/material.dart';

abstract class AppColors {
  // Base
  static const Color pureBlack = Color(0xFF000000);
  static const Color pureWhite = Color(0xFFFFFFFF);

  // Background hierarchy (darkest to lightest)
  static const Color bgBase = Color(0xFF121212);
  static const Color bgElevated = Color(0xFF181818);
  static const Color bgSurface = Color(0xFF282828);
  static const Color bgHighlight = Color(0xFF3E3E3E);

  // Text hierarchy
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB3B3B3);
  // Lifted from #6A6A6A so 12px captions reach WCAG AA (>=4.5:1) on bgBase,
  // bgElevated and bgSurface.
  static const Color textTertiary = Color(0xFF8F8F8F);
  static const Color textDisabled = Color(0xFF535353);

  // Accent: Elysium Lavender. The accent used to be Spotify green #1DB954,
  // the same value as `success`, so "selected", "primary action" and "done"
  // all looked alike, and nothing tied the interface to the red, black and
  // paper-white app icon. Lavender is far from every status colour (error
  // red, warning amber, success green, info blue) and sits beside the icon's
  // Forge Red without competing with it; red stays reserved for the brand
  // mark and for errors (audit A-01).
  // test/core/theme/accent_palette_test.dart pins the contrast numbers.
  static const Color accent = Color(0xFFB69CFF);
  static const Color accentHover = Color(0xFFC7B3FF);
  static const Color accentPressed = Color(0xFF9F84F0);

  // Accent at 16 % for selected chips and tabs: white text on it over the
  // elevated background stays above 12:1.
  static const Color accentMuted = Color(0x29B69CFF);

  // Text and icons on accent fills: black on #B69CFF is 9.2:1 (7.0:1 on the
  // pressed shade); white would be 2.3:1.
  static const Color onAccent = pureBlack;

  // Accent container: deep lavender for selected chips, tonal buttons and the
  // navigation indicator, with light lavender on it (9.3:1). Material derives
  // these roles from the accent when they are not set, which put black
  // labels on the translucent selected-chip tint (1.6:1) and turned every
  // tonal button into a second primary button.
  // Every icon button variant used to share the grey icon colour of the
  // theme, so the icon on a filled lavender button was 1.1:1 against it.
  static const Color accentContainer = Color(0xFF3A2E66);
  static const Color onAccentContainer = Color(0xFFE8DEFF);

  // Brand: Forge Red and paper white, sampled from the app icon. They draw
  // the brand mark (AppBrandMark) and nothing else, so red text and red
  // states keep meaning "error". Forge Red on bgBase is 4.3:1, above the 3:1
  // that graphics need (audit B-01).
  static const Color brand = Color(0xFFF11413);
  static const Color brandPaper = Color(0xFFF6F2E8);

  // Semantic colors
  // Error fills, borders, tints and large status icons.
  static const Color error = Color(0xFFE22134);

  // Error messages and the small icons beside them. #E22134 as text was
  // 4.0:1 on bgBase and 3.2:1 on bgSurface, under the 4.5:1 that body text
  // needs, so failures were the hardest lines on screen to read. This
  // lighter red of the same hue is 8.0:1 on bgBase, 6.3:1 on bgSurface and
  // still 4.6:1 on bgHighlight and inside the red-tinted error banners.
  // test/core/theme/error_text_contrast_test.dart pins the numbers.
  static const Color errorText = Color(0xFFFF8585);

  // Text and icons on error fills (destructive buttons, recording). White on
  // #E22134 is 4.7:1.
  static const Color onError = pureWhite;
  static const Color warning = Color(0xFFFFA42B);
  // Green now means "done" and nothing else; it is no longer the accent.
  static const Color success = Color(0xFF1DB954);
  static const Color info = Color(0xFF2E77D0);

  // Interactive states
  static const Color hoverOverlay = Color(0x1AFFFFFF);
  static const Color pressedOverlay = Color(0x33FFFFFF);
  static const Color focusRing = Color(0x80FFFFFF);

  // Elevation shadows: a floating label close to its anchor, and a card
  // lifted well above the page.
  static const Color shadowNear = Color(0x66000000);
  static const Color shadowFar = Color(0x52000000);

  // Borders (subtle, used sparingly)
  static const Color borderSubtle = Color(0x1AFFFFFF);
  static const Color borderMuted = Color(0x0DFFFFFF);

  // Outlines of controls (outlined buttons, unselected segments, switch
  // tracks), which need 3:1 against the page: 4.1:1 on bgElevated. Material
  // used white for them, which outshone the filled buttons beside them.
  static const Color borderStrong = Color(0xFF7A7A7A);

  // Vinyl: the warm, record-sleeve palette of the phone's listening surfaces
  // (decision D-041). Brass marks what is playing — the spinning record's
  // label ring, the rhythm bars, the playing row's title — and the warm
  // browns tint the surfaces around it. They are decoration and "now
  // playing" only: lavender stays the colour of selection and primary
  // actions, and amber `warning` keeps meaning "needs attention".
  // test/core/theme/vinyl_palette_test.dart pins the contrast numbers.
  static const Color vinylBrass = Color(0xFFE6B87A);

  // Brass at 16 %: the wash behind the playing row and the glow behind the
  // record.
  static const Color vinylBrassMuted = Color(0x29E6B87A);

  // The record itself: near-black with a warm cast, and the faint light
  // grooves and sheen drawn on it.
  static const Color vinylDisc = Color(0xFF0E0C0B);
  static const Color vinylGroove = Color(0x14FFFFFF);
  static const Color vinylSheen = Color(0x2EFFE8C7);

  // Warm surfaces: the hero card and the mini player sit on these instead of
  // the neutral greys. Secondary text (#B3B3B3) stays above 7:1 on both and
  // tertiary text (#8F8F8F) above 4.5:1.
  static const Color vinylSurface = Color(0xFF1E1915);
  static const Color vinylSurfaceHigh = Color(0xFF2A221C);

  // Gradients
  static const LinearGradient playerGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF282828), Color(0xFF121212)],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF282828), Color(0xFF181818)],
  );

  // The listening home's backdrop: a warm brown that fades into the page.
  static const LinearGradient vinylHeroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF3A2A1E), Color(0xFF1E1915), Color(0xFF121212)],
    stops: [0, 0.45, 1],
  );

  // The mobile mini player: warm on the artwork side, neutral at the
  // controls.
  static const LinearGradient vinylBarGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF2A221C), Color(0xFF181818)],
  );
}
