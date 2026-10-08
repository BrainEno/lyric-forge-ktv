import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/desktop_audio_backend.dart';

void main() {
  test('Windows and Linux use media-kit outside the web build', () {
    expect(
      shouldUseDesktopMediaKit(
        isWeb: false,
        platform: TargetPlatform.windows,
      ),
      isTrue,
    );
    expect(
      shouldUseDesktopMediaKit(
        isWeb: false,
        platform: TargetPlatform.linux,
      ),
      isTrue,
    );
  });

  test('mobile, macOS and web keep their existing playback backend', () {
    for (final platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.fuchsia,
    ]) {
      expect(
        shouldUseDesktopMediaKit(isWeb: false, platform: platform),
        isFalse,
      );
    }

    expect(
      shouldUseDesktopMediaKit(
        isWeb: true,
        platform: TargetPlatform.windows,
      ),
      isFalse,
    );
  });
}
