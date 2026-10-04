import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/layout/app_responsive.dart';

void main() {
  group('AppResponsive width classes', () {
    test('classifies breakpoint boundaries deterministically', () {
      expect(AppResponsive.widthClassFor(599), AppWidthClass.compact);
      expect(AppResponsive.widthClassFor(600), AppWidthClass.medium);
      expect(AppResponsive.widthClassFor(839), AppWidthClass.medium);
      expect(AppResponsive.widthClassFor(840), AppWidthClass.expanded);
      expect(AppResponsive.widthClassFor(1199), AppWidthClass.expanded);
      expect(AppResponsive.widthClassFor(1200), AppWidthClass.large);
      expect(AppResponsive.widthClassFor(1599), AppWidthClass.large);
      expect(AppResponsive.widthClassFor(1600), AppWidthClass.extraLarge);
    });
  });

  group('AppResponsive height classes', () {
    test('short height is independent from width', () {
      final shortWide = AppResponsive.fromSize(
        const Size(1440, 580),
        desktopPlatform: true,
      );
      expect(shortWide.widthClass, AppWidthClass.large);
      expect(shortWide.heightClass, AppHeightClass.short);
      expect(shortWide.supportsTwoPane, isFalse);
      expect(shortWide.useNavigationRail, isFalse);
    });
  });

  test('rail navigation is viewport based and avoids short landscape screens', () {
    final narrowDesktop = AppResponsive.fromSize(
      const Size(800, 800),
      desktopPlatform: true,
    );
    final expandedTablet = AppResponsive.fromSize(
      const Size(1024, 768),
      desktopPlatform: false,
    );
    final shortLandscape = AppResponsive.fromSize(
      const Size(844, 390),
      desktopPlatform: false,
    );

    expect(narrowDesktop.useNavigationRail, isFalse);
    expect(expandedTablet.useNavigationRail, isTrue);
    expect(shortLandscape.useNavigationRail, isFalse);
  });

  test('touch platforms preserve 48dp minimum interactive extent', () {
    expect(
      AppResponsive.fromSize(
        const Size(390, 844),
        desktopPlatform: false,
      ).minimumInteractiveExtent,
      48,
    );
    expect(
      AppResponsive.fromSize(
        const Size(1024, 768),
        desktopPlatform: false,
      ).minimumInteractiveExtent,
      48,
    );
  });

  test('desktop control density does not scale indefinitely', () {
    final large = AppResponsive.fromSize(
      const Size(1440, 900),
      desktopPlatform: true,
    );
    final extraLarge = AppResponsive.fromSize(
      const Size(2560, 1440),
      desktopPlatform: true,
    );

    expect(large.minimumInteractiveExtent, 40);
    expect(extraLarge.minimumInteractiveExtent, 40);
    expect(extraLarge.contentMaxWidth, lessThan(extraLarge.width));
    expect(extraLarge.playerContentMaxWidth, lessThan(extraLarge.width));
  });

  test('narrow desktop windows keep larger controls after actions collapse', () {
    final narrow = AppResponsive.fromSize(
      const Size(580, 720),
      desktopPlatform: true,
    );
    expect(narrow.minimumInteractiveExtent, 48);
  });

  test('grid columns respond to width while remaining bounded', () {
    final phone = AppResponsive.fromSize(
      const Size(390, 844),
      desktopPlatform: false,
    );
    final desktop = AppResponsive.fromSize(
      const Size(1920, 1080),
      desktopPlatform: true,
    );

    expect(phone.gridColumns(), 2);
    expect(desktop.gridColumns(), inInclusiveRange(5, 7));
  });
}
