import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Width classes used throughout LyricForge.
///
/// The first three ranges follow common adaptive-layout practice, while large
/// and extraLarge split desktop widths so controls do not scale indefinitely.
enum AppWidthClass {
  compact,
  medium,
  expanded,
  large,
  extraLarge,
}

enum AppHeightClass {
  short,
  regular,
  tall,
}

abstract class AppBreakpoints {
  static const double compactMax = 599;
  static const double mediumMax = 839;
  static const double expandedMax = 1199;
  static const double largeMax = 1599;

  static const double shortHeightMax = 599;
  static const double regularHeightMax = 899;

  static const double navigationRailMinWidth = 840;
  static const double playerTwoPaneMinWidth = 1080;
  static const double desktopWideMinWidth = 1200;
  static const double desktopExtraWideMinWidth = 1600;
}

/// Immutable layout decisions for one viewport.
///
/// Feature pages should consume this object instead of inventing their own
/// numeric breakpoints. Window resizing therefore follows the same rules as
/// mobile/tablet/desktop form factors.
@immutable
class AppLayoutSpec {
  final double width;
  final double height;
  final AppWidthClass widthClass;
  final AppHeightClass heightClass;
  final bool desktopPlatform;

  const AppLayoutSpec({
    required this.width,
    required this.height,
    required this.widthClass,
    required this.heightClass,
    required this.desktopPlatform,
  });

  bool get isCompact => widthClass == AppWidthClass.compact;
  bool get isMedium => widthClass == AppWidthClass.medium;
  bool get isExpanded => widthClass == AppWidthClass.expanded;
  bool get isLarge => widthClass == AppWidthClass.large;
  bool get isExtraLarge => widthClass == AppWidthClass.extraLarge;
  bool get isShort => heightClass == AppHeightClass.short;

  bool get isCompactOrMedium => isCompact || isMedium;

  /// Rail navigation is a viewport decision, not a device-name decision.
  /// Short-height landscape phones stay on bottom navigation even when their
  /// width barely crosses the expanded breakpoint.
  bool get useNavigationRail =>
      width >= AppBreakpoints.navigationRailMinWidth && !isShort;

  bool get supportsTwoPane =>
      width >= AppBreakpoints.playerTwoPaneMinWidth && !isShort;
  bool get isWideDesktop =>
      desktopPlatform && width >= AppBreakpoints.desktopWideMinWidth;
  bool get isExtraWideDesktop =>
      desktopPlatform && width >= AppBreakpoints.desktopExtraWideMinWidth;

  /// Standard page gutter. Large monitors gain breathing room, but controls do
  /// not grow proportionally with the window.
  double get pageGutter {
    switch (widthClass) {
      case AppWidthClass.compact:
        return 12;
      case AppWidthClass.medium:
        return 16;
      case AppWidthClass.expanded:
        return 24;
      case AppWidthClass.large:
        return 32;
      case AppWidthClass.extraLarge:
        return 40;
    }
  }

  double get sectionGap => isCompact ? 16 : isMedium ? 20 : 24;

  /// Prevents text/cards becoming excessively wide on large desktop monitors.
  double get contentMaxWidth => isExtraLarge ? 1480 : isLarge ? 1360 : 1200;

  double get playerContentMaxWidth => isExtraLarge ? 1440 : 1280;

  double get sidePanelWidth {
    if (isExtraLarge) return 420;
    if (isLarge) return 390;
    return 340;
  }

  /// Touch platforms always retain 48dp targets. Narrow desktop windows also
  /// keep the larger hit area because secondary actions are already collapsed.
  double get minimumInteractiveExtent =>
      !desktopPlatform || isCompactOrMedium ? 48 : 40;

  double get primaryPlayerControlExtent => isCompact ? 56 : 64;

  double get playerArtworkMaxExtent {
    if (isShort) return 220;
    if (isCompact) return 320;
    if (isMedium) return 360;
    if (isExpanded) return 300;
    return 340;
  }

  int gridColumns({
    double minTileWidth = 190,
    int min = 2,
    int max = 7,
  }) {
    final usable = (width - pageGutter * 2).clamp(0, double.infinity);
    final calculated = (usable / minTileWidth).floor();
    return calculated.clamp(min, max).toInt();
  }
}

abstract class AppResponsive {
  static AppWidthClass widthClassFor(double width) {
    if (width <= AppBreakpoints.compactMax) return AppWidthClass.compact;
    if (width <= AppBreakpoints.mediumMax) return AppWidthClass.medium;
    if (width <= AppBreakpoints.expandedMax) return AppWidthClass.expanded;
    if (width <= AppBreakpoints.largeMax) return AppWidthClass.large;
    return AppWidthClass.extraLarge;
  }

  static AppHeightClass heightClassFor(double height) {
    if (height <= AppBreakpoints.shortHeightMax) return AppHeightClass.short;
    if (height <= AppBreakpoints.regularHeightMax) return AppHeightClass.regular;
    return AppHeightClass.tall;
  }

  static bool isDesktopTarget() {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  static AppLayoutSpec fromSize(
    Size size, {
    bool? desktopPlatform,
  }) {
    return AppLayoutSpec(
      width: size.width,
      height: size.height,
      widthClass: widthClassFor(size.width),
      heightClass: heightClassFor(size.height),
      desktopPlatform: desktopPlatform ?? isDesktopTarget(),
    );
  }

  static AppLayoutSpec fromConstraints(
    BoxConstraints constraints, {
    bool? desktopPlatform,
  }) {
    return fromSize(
      Size(constraints.maxWidth, constraints.maxHeight),
      desktopPlatform: desktopPlatform,
    );
  }

  static AppLayoutSpec of(BuildContext context) =>
      fromSize(MediaQuery.sizeOf(context));
}

/// Standard content frame used by top-level media surfaces.
class ResponsiveContentFrame extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final bool includeVerticalPadding;

  const ResponsiveContentFrame({
    super.key,
    required this.child,
    this.maxWidth,
    this.includeVerticalPadding = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spec = AppResponsive.fromConstraints(constraints);
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth ?? spec.contentMaxWidth,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: spec.pageGutter,
                vertical: includeVerticalPadding ? spec.pageGutter : 0,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
