import 'dart:io';

import 'package:flutter/foundation.dart';

/// Version of this build. Kept in sync with `pubspec.yaml` by
/// `test/core/diagnostics/app_build_info_test.dart`; the app has no runtime
/// package-info dependency.
const String appVersion = '1.0.0+1';

/// Display name used in reports.
const String appDisplayName = 'Elysium Player';

/// Facts about the running build and platform. Contains nothing that
/// identifies the user: no host name, user name or device serial.
class AppBuildInfo {
  final String version;
  final String buildMode;
  final String operatingSystem;
  final String operatingSystemVersion;
  final String dartVersion;
  final int processorCount;
  final String locale;

  const AppBuildInfo({
    required this.version,
    required this.buildMode,
    required this.operatingSystem,
    required this.operatingSystemVersion,
    required this.dartVersion,
    required this.processorCount,
    required this.locale,
  });

  factory AppBuildInfo.current() {
    String read(String Function() getter) {
      try {
        return getter();
      } catch (_) {
        return 'unknown';
      }
    }

    return AppBuildInfo(
      version: appVersion,
      buildMode: kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'debug',
      operatingSystem: read(() => Platform.operatingSystem),
      operatingSystemVersion: read(() => Platform.operatingSystemVersion),
      // `3.11.4 (stable) (…) on "macos_arm64"`: keep version and target.
      dartVersion: read(() => Platform.version),
      processorCount: () {
        try {
          return Platform.numberOfProcessors;
        } catch (_) {
          return 0;
        }
      }(),
      locale: read(() => Platform.localeName),
    );
  }

  Map<String, Object?> toJson() => {
    'app': appDisplayName,
    'version': version,
    'buildMode': buildMode,
    'os': operatingSystem,
    'osVersion': operatingSystemVersion,
    'dart': dartVersion,
    'processors': processorCount,
    'locale': locale,
  };
}
