import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/layout/app_capabilities.dart';

void main() {
  tearDown(() {
    AppCapabilities.debugLyricWorkbenchOverride = null;
    debugDefaultTargetPlatformOverride = null;
  });

  test('desktops have the lyric workbench, phones do not (D-058)', () {
    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(AppCapabilities.lyricWorkbench, isTrue, reason: '$platform');
    }
    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(AppCapabilities.lyricWorkbench, isFalse, reason: '$platform');
    }
  });

  test('a test can pretend either way', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    AppCapabilities.debugLyricWorkbenchOverride = true;
    expect(AppCapabilities.lyricWorkbench, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    AppCapabilities.debugLyricWorkbenchOverride = false;
    expect(AppCapabilities.lyricWorkbench, isFalse);
  });
}
