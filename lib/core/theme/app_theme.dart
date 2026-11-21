import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_palette.dart';
import 'app_typography.dart';
import 'color_tokens.dart';
import 'spacing_tokens.dart';

/// The Material theme and the shared control styles of Elysium Player.
///
/// Everything is built from an [AppPalette] (decision D-042): [themeFor]
/// makes the [ThemeData] of one palette, and each shared style has a
/// `…For(palette)` builder plus a getter for the palette in use, which is
/// what screens call. The getters build a fresh style each time, so a style
/// read during a rebuild always matches the current theme.
class AppTheme {
  const AppTheme._();

  /// Chip outline: accent while selected, the subtle border otherwise.
  static WidgetStateBorderSide get chipSide => chipSideFor(AppColors.palette);
  static WidgetStateProperty<Color> get accentFill =>
      accentFillFor(AppColors.palette);
  static WidgetStateProperty<Color> get accentForeground =>
      accentForegroundFor(AppColors.palette);
  static WidgetStateProperty<Color?> get fillOverlay =>
      fillOverlayFor(AppColors.palette);
  static WidgetStateBorderSide get outlinedSide =>
      outlinedSideFor(AppColors.palette);
  static WidgetStateProperty<Color?> get disabledFill =>
      disabledFillFor(AppColors.palette);
  static WidgetStateProperty<Color?> get disabledForeground =>
      disabledForegroundFor(AppColors.palette);
  static ButtonStyle get playDisc => playDiscFor(AppColors.palette);
  static ButtonStyle get busyAccentDisc => busyAccentDiscFor(AppColors.palette);
  static ButtonStyle get vinylPlayDisc => vinylPlayDiscFor(AppColors.palette);
  static ButtonStyle get vinylFilled => vinylFilledFor(AppColors.palette);

  /// Chip outline: accent while selected, the subtle border otherwise.
  static WidgetStateBorderSide chipSideFor(AppPalette p) =>
      WidgetStateBorderSide.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.selected)
              ? p.accent
              : p.borderSubtle,
        ),
      );

  /// Background of accent-filled buttons in each state.
  static WidgetStateProperty<Color> accentFillFor(AppPalette p) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return p.bgHighlight;
        }
        if (states.contains(WidgetState.pressed)) {
          return p.accentPressed;
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return p.accentHover;
        }
        return p.accent;
      });

  /// Label and icon on [accentFill].
  static WidgetStateProperty<Color> accentForegroundFor(AppPalette p) =>
      WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.disabled) ? p.textTertiary : p.onAccent,
      );

  /// Press and hover wash for buttons whose fill stays put: white at 10 %
  /// on hover and 20 % while pressed, so a press always shows.
  static WidgetStateProperty<Color?> fillOverlayFor(AppPalette p) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return p.pressedOverlay;
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return p.hoverOverlay;
        }
        return null;
      });

  /// Outline of outlined buttons: grey, dimmer when disabled.
  static WidgetStateBorderSide outlinedSideFor(AppPalette p) =>
      WidgetStateBorderSide.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.disabled)
              ? p.borderSubtle
              : p.borderStrong,
        ),
      );

  /// Filled and tonal buttons while disabled: the same grey on grey as
  /// [accentFill], and nothing for the enabled states, which fall through to
  /// the colour scheme.
  ///
  /// Material's default disabled colours are white at 12 % and 38 %, which
  /// leaves the label, and the spinner of a busy button, at 2.2:1.
  static WidgetStateProperty<Color?> disabledFillFor(AppPalette p) =>
      WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.disabled) ? p.bgHighlight : null,
      );
  static WidgetStateProperty<Color?> disabledForegroundFor(AppPalette p) =>
      WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.disabled) ? p.textTertiary : null,
      );

  /// The play/pause disc of the player bars and the transport: white with a
  /// black icon in the dark theme, ink with a white icon in the light one.
  ///
  /// The disc is disabled only while playback loads, and then shows a
  /// spinner in the icon colour. The disabled disc used to be transparent
  /// (desktop bar) or #535353 (mobile bar, transport), leaving that spinner
  /// at 1.1:1 or 2.7:1; it now stays a quieter shade of the disc, 10:1 under
  /// black (dark theme) and 7:1 under white (light theme).
  static ButtonStyle playDiscFor(AppPalette p) => IconButton.styleFrom(
    backgroundColor: p.playDisc,
    foregroundColor: p.onPlayDisc,
    disabledBackgroundColor: p.playDiscBusy,
    disabledForegroundColor: p.onPlayDisc,
  );

  /// A filled (accent) icon button that is disabled only while it works,
  /// like the dashboard play button during buffering. It keeps the accent
  /// disc under a black spinner (9.2:1) rather than turning into the grey of
  /// an unavailable control, which read as "cannot play" instead of "loading".
  static ButtonStyle busyAccentDiscFor(AppPalette p) => IconButton.styleFrom(
    disabledBackgroundColor: p.accent,
    disabledForegroundColor: p.onAccent,
  );

  /// The brass play button of the phone's listening surfaces (D-041): the
  /// record-black icon on brass is 10:1, the white icon on the light theme's
  /// bronze 6.1:1. It keeps its brass while it works
  /// under a spinner, for the reason [busyAccentDisc] gives.
  static ButtonStyle vinylPlayDiscFor(AppPalette p) => IconButton.styleFrom(
    backgroundColor: p.vinylBrass,
    foregroundColor: p.onVinylBrass,
    disabledBackgroundColor: p.vinylBrass,
    disabledForegroundColor: p.onVinylBrass,
  );

  /// The brass filled button of the listening home (播放全部).
  static ButtonStyle vinylFilledFor(AppPalette p) => FilledButton.styleFrom(
    backgroundColor: p.vinylBrass,
    foregroundColor: p.onVinylBrass,
  );

  /// Navigation labels: grey, and bold white for the chosen destination.
  static TextStyle navigationLabelFor(AppPalette p) => AppTypography.apply(
    TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: p.textSecondary,
    ),
  );
  static TextStyle navigationLabelSelectedFor(AppPalette p) =>
      AppTypography.apply(
        TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: p.textPrimary,
        ),
      );

  /// The theme of the dark palette, the one the app opens in.
  static ThemeData get darkTheme => themeFor(AppPalette.dark);

  /// The theme of the light palette.
  static ThemeData get lightTheme => themeFor(AppPalette.light);

  /// The theme of the palette in use.
  static ThemeData get current => themeFor(AppColors.palette);

  /// The Material theme of [p]: every colour of every component theme comes
  /// from the palette, never from the palette in use, so the light theme can
  /// be built and inspected while the app is dark.
  static ThemeData themeFor(AppPalette p) {
    final isLight = p.brightness == Brightness.light;
    final navigationLabel = navigationLabelFor(p);
    final navigationLabelSelected = navigationLabelSelectedFor(p);
    final fillOverlay = fillOverlayFor(p);
    final base = isLight ? ThemeData.light() : ThemeData.dark();
    // The Material defaults of the palette's brightness for the roles not
    // named below (inverse surface, scrim, shadow and the like).
    final scheme = isLight
        ? const ColorScheme.light()
        : const ColorScheme.dark();
    return base.copyWith(
      scaffoldBackgroundColor: p.bgBase,
      canvasColor: p.bgElevated,
      colorScheme: scheme.copyWith(
        primary: p.accent,
        secondary: p.accent,
        surface: p.bgSurface,
        surfaceContainerHighest: p.bgBase,
        error: p.error,
        onPrimary: p.onAccent,
        onSecondary: p.onAccent,
        // Selected chips, tonal buttons, segmented buttons and the
        // navigation indicator read these; left unset they copy the accent
        // and its black label.
        primaryContainer: p.accentContainer,
        onPrimaryContainer: p.onAccentContainer,
        secondaryContainer: p.accentContainer,
        onSecondaryContainer: p.onAccentContainer,
        inversePrimary: p.accentHover,
        onSurface: p.textPrimary,
        // Secondary text and icons: standard icon buttons, unselected chips,
        // tabs and navigation entries. Plain icon buttons take their grey
        // from here instead of from the icon button theme, which also
        // painted the icons of filled buttons.
        onSurfaceVariant: p.textSecondary,
        onError: p.onError,
        outline: p.borderStrong,
        outlineVariant: p.bgHighlight,
        // No lavender wash over raised surfaces (menus, sheets, the bottom
        // navigation): the greys stay the greys of the palette.
        surfaceTint: Colors.transparent,
      ),
      // Typography
      // Every text style names the interface fonts, so the characters of one
      // Chinese label come from one typeface (see AppTypography).
      textTheme: AppTypography.applyToTheme(_buildTextTheme(p)),
      primaryTextTheme: AppTypography.applyToTheme(base.primaryTextTheme),
      // App Bar
      appBarTheme: AppBarTheme(
        backgroundColor: p.bgBase,
        foregroundColor: p.textPrimary,
        elevation: 0,
        centerTitle: false,
        // Dark status bar icons over the light theme's paper, light ones
        // over the dark theme.
        systemOverlayStyle: isLight
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
        titleTextStyle: AppTypography.apply(
          TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: p.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
      ),
      // Cards
      cardTheme: CardThemeData(
        color: p.bgElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        ),
        margin: EdgeInsets.zero,
      ),
      // Buttons
      // Primary call to action: the accent, lighter on hover, darker while
      // pressed, black on all three (7:1 or more). A disabled button drops to
      // grey on grey instead of a dimmed lavender.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: accentFillFor(p),
          foregroundColor: accentForegroundFor(p),
          // The fill itself changes on hover and press; a white wash on top
          // would only grey it.
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll<double>(0),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(
              horizontal: AppSpacing.buttonPaddingHorizontal,
              vertical: AppSpacing.buttonPaddingVertical,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
            ),
          ),
          textStyle: WidgetStatePropertyAll(
            AppTypography.apply(
              const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
      // Filled and tonal buttons share this theme, so it sets no enabled
      // colours: filled takes the accent and black from primary/onPrimary,
      // tonal the deep lavender and light lavender from the containers. It
      // makes the press visible on both and gives both the readable disabled
      // grey of the elevated button.
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: disabledFillFor(p),
          foregroundColor: disabledForegroundFor(p),
          iconColor: disabledForegroundFor(p),
          overlayColor: fillOverlay,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? p.textDisabled
                : p.textPrimary,
          ),
          side: outlinedSideFor(p),
          overlayColor: fillOverlay,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? p.accentContainer
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return p.textDisabled;
            }
            return states.contains(WidgetState.selected)
                ? p.onAccentContainer
                : p.textSecondary;
          }),
          side: WidgetStatePropertyAll(BorderSide(color: p.borderStrong)),
          overlayColor: fillOverlay,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        hoverColor: p.accentHover,
        splashColor: p.accentPressed,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return p.textDisabled;
          }
          return states.contains(WidgetState.selected)
              ? p.onAccent
              : p.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return p.bgSurface;
          }
          return states.contains(WidgetState.selected)
              ? p.accent
              : p.bgHighlight;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? p.accent : p.borderStrong,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (!states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return states.contains(WidgetState.disabled)
              ? p.textDisabled
              : p.accent;
        }),
        checkColor: WidgetStatePropertyAll(p.onAccent),
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(
            width: 2,
            color: states.contains(WidgetState.disabled)
                ? p.textDisabled
                : states.contains(WidgetState.selected)
                ? p.accent
                : p.textSecondary,
          ),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return p.textDisabled;
          }
          return states.contains(WidgetState.selected)
              ? p.accent
              : p.textSecondary;
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.textPrimary,
        unselectedLabelColor: p.textSecondary,
        indicatorColor: p.accent,
        dividerColor: p.borderSubtle,
      ),
      // The persistent navigation: the deep lavender pill behind the chosen
      // destination, light lavender on it, bold white label under it.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.bgElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: p.accentContainer,
        overlayColor: fillOverlay,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? p.onAccentContainer
                : p.textSecondary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? navigationLabelSelected
              : navigationLabel,
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: p.bgElevated,
        useIndicator: true,
        indicatorColor: p.accentContainer,
        selectedIconTheme: IconThemeData(size: 24, color: p.onAccentContainer),
        unselectedIconTheme: IconThemeData(size: 24, color: p.textSecondary),
        selectedLabelTextStyle: navigationLabelSelected,
        unselectedLabelTextStyle: navigationLabel,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.textPrimary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
          ),
        ),
      ),
      // No foreground here: the theme applies to every icon button variant,
      // and a grey set here also painted the icons of filled (lavender) and
      // tonal buttons, 1.1:1 on the accent. Plain icon buttons get the grey
      // from onSurfaceVariant, filled ones black, tonal ones light lavender.
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          hoverColor: p.hoverOverlay,
          highlightColor: p.pressedOverlay,
        ),
      ),
      // Inputs
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.bgSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
          borderSide: BorderSide(color: p.accent, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: AppTypography.apply(
          TextStyle(color: p.textTertiary, fontSize: 14),
        ),
        // Field errors are text too; the error border keeps the fill red.
        errorStyle: AppTypography.apply(TextStyle(color: p.errorText)),
      ),
      // List Tiles
      listTileTheme: ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
        minLeadingWidth: AppSpacing.lg,
        iconColor: p.textSecondary,
        textColor: p.textPrimary,
        selectedTileColor: p.bgHighlight,
      ),
      // Chips: a selected chip used to differ from the others only by the
      // default grey fill, so a row of filter or section chips gave little
      // sign of which one was on (audit L-03). The selected fill is the
      // opaque accent container; its label and icon come from
      // onSecondaryContainer, light lavender instead of black.
      chipTheme: ChipThemeData(
        selectedColor: p.accentContainer,
        checkmarkColor: p.onAccentContainer,
        side: chipSideFor(p),
      ),
      // Bottom Navigation
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: p.bgElevated,
        selectedItemColor: p.accent,
        unselectedItemColor: p.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        showSelectedLabels: true,
        showUnselectedLabels: true,
      ),
      // Slider
      sliderTheme: SliderThemeData(
        activeTrackColor: p.accent,
        inactiveTrackColor: p.bgHighlight,
        thumbColor: p.textPrimary,
        overlayColor: p.accent.withAlpha(26),
        trackHeight: AppSpacing.unit,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      // Progress Indicator
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.bgHighlight,
        circularTrackColor: p.bgHighlight,
      ),
      // Divider
      dividerTheme: DividerThemeData(
        color: p.borderSubtle,
        thickness: 1,
        space: 1,
      ),
      // Tooltip
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.bgSurface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        ),
        textStyle: AppTypography.apply(
          TextStyle(color: p.textPrimary, fontSize: 12),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
      ),
      // Snackbar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.bgHighlight,
        contentTextStyle: AppTypography.apply(
          TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600),
        ),
        actionTextColor: p.accentHover,
        closeIconColor: p.textSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      // Dialog
      dialogTheme: DialogThemeData(
        backgroundColor: p.bgElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        ),
      ),
      // Scrollbar
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(p.textTertiary),
        trackColor: WidgetStateProperty.all(p.bgSurface),
        radius: const Radius.circular(AppSpacing.radiusCircular),
        thickness: WidgetStateProperty.all(4),
      ),
    );
  }

  static TextTheme _buildTextTheme(AppPalette p) {
    final baseTextStyle = TextStyle(color: p.textPrimary);

    return TextTheme(
      displayLarge: baseTextStyle.copyWith(
        fontSize: 48,
        fontWeight: FontWeight.w900,
        letterSpacing: -2,
        height: 1.1,
      ),
      displayMedium: baseTextStyle.copyWith(
        fontSize: 36,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.5,
        height: 1.2,
      ),
      displaySmall: baseTextStyle.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -1,
        height: 1.2,
      ),
      headlineLarge: baseTextStyle.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.3,
      ),
      headlineMedium: baseTextStyle.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.3,
      ),
      headlineSmall: baseTextStyle.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.25,
        height: 1.4,
      ),
      titleLarge: baseTextStyle.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        height: 1.4,
      ),
      titleMedium: baseTextStyle.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
        height: 1.5,
      ),
      titleSmall: baseTextStyle.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        height: 1.5,
        color: p.textSecondary,
      ),
      bodyLarge: baseTextStyle.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.5,
      ),
      bodyMedium: baseTextStyle.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.5,
        color: p.textSecondary,
      ),
      bodySmall: baseTextStyle.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
        height: 1.5,
        color: p.textTertiary,
      ),
      labelLarge: baseTextStyle.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        height: 1.4,
      ),
      labelMedium: baseTextStyle.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        height: 1.4,
      ),
      // The smallest style, used for captions and badges; 11 is the floor for
      // text people are expected to read (UI audit E-06).
      labelSmall: baseTextStyle.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        height: 1.4,
        color: p.textTertiary,
      ),
    );
  }
}
