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

  // Brand: Forge Red and paper white, sampled from the app icon. They draw
  // the brand mark (AppBrandMark) and nothing else, so red text and red
  // states keep meaning "error". Forge Red on bgBase is 4.3:1, above the 3:1
  // that graphics need (audit B-01).
  static const Color brand = Color(0xFFF11413);
  static const Color brandPaper = Color(0xFFF6F2E8);

  // Semantic colors
  static const Color error = Color(0xFFE22134);

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
}
