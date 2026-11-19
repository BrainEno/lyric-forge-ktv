import 'package:flutter/material.dart';
import 'color_tokens.dart';
import 'spacing_tokens.dart';

class AppTheme {
  const AppTheme._();

  /// Chip outline: accent while selected, the subtle border otherwise.
  static final WidgetStateBorderSide chipSide =
      WidgetStateBorderSide.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.borderSubtle,
        ),
      );

  /// Background of accent-filled buttons in each state.
  static final WidgetStateProperty<Color> accentFill =
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return AppColors.bgHighlight;
        }
        if (states.contains(WidgetState.pressed)) {
          return AppColors.accentPressed;
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return AppColors.accentHover;
        }
        return AppColors.accent;
      });

  /// Label and icon on [accentFill].
  static final WidgetStateProperty<Color> accentForeground =
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? AppColors.textTertiary
            : AppColors.onAccent,
      );

  /// Press and hover wash for buttons whose fill stays put: white at 10 %
  /// on hover and 20 % while pressed, so a press always shows.
  static final WidgetStateProperty<Color?> fillOverlay =
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return AppColors.pressedOverlay;
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return AppColors.hoverOverlay;
        }
        return null;
      });

  /// Outline of outlined buttons: grey, dimmer when disabled.
  static final WidgetStateBorderSide outlinedSide =
      WidgetStateBorderSide.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.disabled)
              ? AppColors.borderSubtle
              : AppColors.borderStrong,
        ),
      );

  /// Filled and tonal buttons while disabled: the same grey on grey as
  /// [accentFill], and nothing for the enabled states, which fall through to
  /// the colour scheme.
  ///
  /// Material's default disabled colours are white at 12 % and 38 %, which
  /// leaves the label, and the spinner of a busy button, at 2.2:1.
  static final WidgetStateProperty<Color?> disabledFill =
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? AppColors.bgHighlight
            : null,
      );
  static final WidgetStateProperty<Color?> disabledForeground =
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? AppColors.textTertiary
            : null,
      );

  /// The white play/pause disc of the player bars and the transport.
  ///
  /// The disc is disabled only while playback loads, and then shows a black
  /// spinner. The disabled disc used to be transparent (desktop bar) or
  /// #535353 (mobile bar, transport), leaving that spinner at 1.1:1 or 2.7:1;
  /// it now stays light grey, 10:1 under black.
  static final ButtonStyle playDisc = IconButton.styleFrom(
    backgroundColor: AppColors.pureWhite,
    foregroundColor: AppColors.pureBlack,
    disabledBackgroundColor: AppColors.textSecondary,
    disabledForegroundColor: AppColors.pureBlack,
  );

  /// A filled (accent) icon button that is disabled only while it works,
  /// like the dashboard play button during buffering. It keeps the accent
  /// disc under a black spinner (9.2:1) rather than turning into the grey of
  /// an unavailable control, which read as "cannot play" instead of "loading".
  static final ButtonStyle busyAccentDisc = IconButton.styleFrom(
    disabledBackgroundColor: AppColors.accent,
    disabledForegroundColor: AppColors.onAccent,
  );

  /// Navigation labels: grey, and bold white for the chosen destination.
  static const TextStyle navigationLabel = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );
  static const TextStyle navigationLabelSelected = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: AppColors.bgBase,
      canvasColor: AppColors.bgElevated,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accent,
        secondary: AppColors.accent,
        surface: AppColors.bgSurface,
        surfaceContainerHighest: AppColors.bgBase,
        error: AppColors.error,
        onPrimary: AppColors.onAccent,
        onSecondary: AppColors.onAccent,
        // Selected chips, tonal buttons, segmented buttons and the
        // navigation indicator read these; left unset they copy the accent
        // and its black label.
        primaryContainer: AppColors.accentContainer,
        onPrimaryContainer: AppColors.onAccentContainer,
        secondaryContainer: AppColors.accentContainer,
        onSecondaryContainer: AppColors.onAccentContainer,
        inversePrimary: AppColors.accentHover,
        onSurface: AppColors.textPrimary,
        // Secondary text and icons: standard icon buttons, unselected chips,
        // tabs and navigation entries. Plain icon buttons take their grey
        // from here instead of from the icon button theme, which also
        // painted the icons of filled buttons.
        onSurfaceVariant: AppColors.textSecondary,
        onError: AppColors.onError,
        outline: AppColors.borderStrong,
        outlineVariant: AppColors.bgHighlight,
        // No lavender wash over raised surfaces (menus, sheets, the bottom
        // navigation): the greys stay the greys of the palette.
        surfaceTint: Colors.transparent,
      ),
      // Typography
      textTheme: _buildTextTheme(),
      // App Bar
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bgBase,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.5,
        ),
      ),
      // Cards
      cardTheme: CardThemeData(
        color: AppColors.bgElevated,
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
          backgroundColor: accentFill,
          foregroundColor: accentForeground,
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
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
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
          backgroundColor: disabledFill,
          foregroundColor: disabledForeground,
          iconColor: disabledForeground,
          overlayColor: fillOverlay,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? AppColors.textDisabled
                : AppColors.textPrimary,
          ),
          side: outlinedSide,
          overlayColor: fillOverlay,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.accentContainer
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.textDisabled;
            }
            return states.contains(WidgetState.selected)
                ? AppColors.onAccentContainer
                : AppColors.textSecondary;
          }),
          side: const WidgetStatePropertyAll(
            BorderSide(color: AppColors.borderStrong),
          ),
          overlayColor: fillOverlay,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        hoverColor: AppColors.accentHover,
        splashColor: AppColors.accentPressed,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return AppColors.textDisabled;
          }
          return states.contains(WidgetState.selected)
              ? AppColors.onAccent
              : AppColors.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return AppColors.bgSurface;
          }
          return states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.bgHighlight;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.borderStrong,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (!states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return states.contains(WidgetState.disabled)
              ? AppColors.textDisabled
              : AppColors.accent;
        }),
        checkColor: const WidgetStatePropertyAll(AppColors.onAccent),
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(
            width: 2,
            color: states.contains(WidgetState.disabled)
                ? AppColors.textDisabled
                : states.contains(WidgetState.selected)
                ? AppColors.accent
                : AppColors.textSecondary,
          ),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return AppColors.textDisabled;
          }
          return states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.textSecondary;
        }),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.accent,
        dividerColor: AppColors.borderSubtle,
      ),
      // The persistent navigation: the deep lavender pill behind the chosen
      // destination, light lavender on it, bold white label under it.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.bgElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: AppColors.accentContainer,
        overlayColor: fillOverlay,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? AppColors.onAccentContainer
                : AppColors.textSecondary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? navigationLabelSelected
              : navigationLabel,
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: AppColors.bgElevated,
        useIndicator: true,
        indicatorColor: AppColors.accentContainer,
        selectedIconTheme: IconThemeData(
          size: 24,
          color: AppColors.onAccentContainer,
        ),
        unselectedIconTheme: IconThemeData(
          size: 24,
          color: AppColors.textSecondary,
        ),
        selectedLabelTextStyle: navigationLabelSelected,
        unselectedLabelTextStyle: navigationLabel,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
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
          hoverColor: AppColors.hoverOverlay,
          highlightColor: AppColors.pressedOverlay,
        ),
      ),
      // Inputs
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgSurface,
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
          borderSide: const BorderSide(color: AppColors.accent, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
        // Field errors are text too; the error border keeps the fill red.
        errorStyle: const TextStyle(color: AppColors.errorText),
      ),
      // List Tiles
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
        minLeadingWidth: AppSpacing.lg,
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        selectedTileColor: AppColors.bgHighlight,
      ),
      // Chips: a selected chip used to differ from the others only by the
      // default grey fill, so a row of filter or section chips gave little
      // sign of which one was on (audit L-03). The selected fill is the
      // opaque accent container; its label and icon come from
      // onSecondaryContainer, light lavender instead of black.
      chipTheme: ChipThemeData(
        selectedColor: AppColors.accentContainer,
        checkmarkColor: AppColors.onAccentContainer,
        side: chipSide,
      ),
      // Bottom Navigation
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.bgElevated,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        showSelectedLabels: true,
        showUnselectedLabels: true,
      ),
      // Slider
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: AppColors.bgHighlight,
        thumbColor: AppColors.pureWhite,
        overlayColor: AppColors.accent.withAlpha(26),
        trackHeight: AppSpacing.unit,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      // Progress Indicator
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.bgHighlight,
        circularTrackColor: AppColors.bgHighlight,
      ),
      // Divider
      dividerTheme: const DividerThemeData(
        color: AppColors.borderSubtle,
        thickness: 1,
        space: 1,
      ),
      // Tooltip
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        ),
        textStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
      ),
      // Snackbar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.bgHighlight,
        contentTextStyle: const TextStyle(
          color: AppColors.pureWhite,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: AppColors.accentHover,
        closeIconColor: AppColors.textSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      // Dialog
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.bgElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        ),
      ),
      // Scrollbar
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(AppColors.textTertiary),
        trackColor: WidgetStateProperty.all(AppColors.bgSurface),
        radius: const Radius.circular(AppSpacing.radiusCircular),
        thickness: WidgetStateProperty.all(4),
      ),
    );
  }

  static TextTheme _buildTextTheme() {
    const baseTextStyle = TextStyle(color: AppColors.textPrimary);

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
        color: AppColors.textSecondary,
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
        color: AppColors.textSecondary,
      ),
      bodySmall: baseTextStyle.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
        height: 1.5,
        color: AppColors.textTertiary,
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
      labelSmall: baseTextStyle.copyWith(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        height: 1.4,
        color: AppColors.textTertiary,
      ),
    );
  }
}
