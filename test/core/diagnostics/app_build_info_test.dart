import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/diagnostics/app_build_info.dart';

void main() {
  test('appVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final line = pubspec.firstWhere((line) => line.startsWith('version:'));
    expect(
      appVersion,
      line.substring('version:'.length).trim(),
      reason:
          'Update appVersion in lib/core/diagnostics/app_build_info.dart '
          'whenever the pubspec version changes.',
    );
  });

  test('current() describes the platform without identifying the user', () {
    final info = AppBuildInfo.current();
    expect(info.version, appVersion);
    expect(info.buildMode, anyOf('debug', 'profile', 'release'));
    expect(info.operatingSystem, Platform.operatingSystem);
    expect(info.processorCount, greaterThan(0));

    final json = info.toJson();
    expect(json.keys, [
      'app',
      'version',
      'buildMode',
      'os',
      'osVersion',
      'dart',
      'processors',
      'locale',
    ]);
    final text = json.values.join(' ');
    expect(text, isNot(contains(Platform.localHostname)));
  });
}
