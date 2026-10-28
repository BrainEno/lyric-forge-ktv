// Spacing tokens for consistent rhythm
// Following 4px base grid system

abstract class AppSpacing {
  // Base unit
  static const double unit = 4.0;

  // Scale
  static const double xs = unit;
  static const double sm = unit * 2;
  static const double md = unit * 4;
  static const double lg = unit * 6;
  static const double xl = unit * 8;
  static const double xxl = unit * 12;
  static const double xxxl = unit * 16;

  // Section spacing
  static const double sectionSmall = unit * 6;
  static const double sectionMedium = unit * 8;
  static const double sectionLarge = unit * 12;

  // Content padding
  static const double contentPadding = unit * 4;
  static const double screenPadding = unit * 6;

  // Component specific
  static const double cardPadding = unit * 4;
  static const double cardGap = unit * 3;
  static const double listItemGap = unit * 2;
  static const double buttonPaddingHorizontal = unit * 6;
  static const double buttonPaddingVertical = unit * 3;
  static const double iconSizeSmall = unit * 5;
  static const double iconSizeMedium = unit * 6;
  static const double iconSizeLarge = unit * 8;

  // Border radius
  static const double radiusSmall = unit;
  static const double radiusMedium = unit * 2;
  static const double radiusLarge = unit * 3;
  static const double radiusXLarge = unit * 4;
  static const double radiusCircular = 999.0;

  // Player specific
  static const double playerArtworkSize = unit * 64;
  static const double playerArtworkSizeSmall = unit * 40;
  static const double playerControlSize = unit * 16;
  static const double progressBarHeight = unit;
}
