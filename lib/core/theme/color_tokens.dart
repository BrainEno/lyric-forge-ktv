// Spotify-inspired dark theme color tokens
// Core palette for media-centric, immersive player UI

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

  // Accent (Spotify green as reference, adjusted)
  static const Color accent = Color(0xFF1DB954);
  static const Color accentHover = Color(0xFF1ED760);
  static const Color accentPressed = Color(0xFF169C45);

  // Accent at 16 % for selected chips and tabs: white text on it over the
  // elevated background stays above 12:1.
  static const Color accentMuted = Color(0x291DB954);

  // Text and icons on accent fills. White on #1DB954 is only 2.6:1; black is
  // 8.1:1.
  static const Color onAccent = pureBlack;

  // Semantic colors
  static const Color error = Color(0xFFE22134);
  static const Color warning = Color(0xFFFFA42B);
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
