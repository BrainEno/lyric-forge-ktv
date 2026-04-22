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
  static const Color textTertiary = Color(0xFF6A6A6A);
  static const Color textDisabled = Color(0xFF535353);

  // Accent (Spotify green as reference, adjusted)
  static const Color accent = Color(0xFF1DB954);
  static const Color accentHover = Color(0xFF1ED760);
  static const Color accentPressed = Color(0xFF169C45);

  // Semantic colors
  static const Color error = Color(0xFFE22134);
  static const Color warning = Color(0xFFFFA42B);
  static const Color success = Color(0xFF1DB954);
  static const Color info = Color(0xFF2E77D0);

  // Interactive states
  static const Color hoverOverlay = Color(0x1AFFFFFF);
  static const Color pressedOverlay = Color(0x33FFFFFF);
  static const Color focusRing = Color(0x80FFFFFF);

  // Borders (subtle, used sparingly)
  static const Color borderSubtle = Color(0x1AFFFFFF);
  static const Color borderMuted = Color(0x0DFFFFFF);

  // Gradients
  static const LinearGradient playerGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF282828),
      Color(0xFF121212),
    ],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF282828),
      Color(0xFF181818),
    ],
  );
}
