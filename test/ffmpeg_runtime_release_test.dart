import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/ffmpeg_runtime_release.dart';

void main() {
  group('FfmpegRuntimeRelease', () {
    test('each supported target uses a fixed HTTPS archive and SHA-256', () {
      expect(FfmpegRuntimeRelease.supported, hasLength(5));

      for (final release in FfmpegRuntimeRelease.supported) {
        expect(release.downloadUri.scheme, 'https');
        expect(release.downloadUri.path, endsWith('.zip'));
        expect(release.downloadUrl, isNot(contains('/latest/')));
        expect(
          release.sha256,
          matches(RegExp(r'^[0-9a-f]{64}$')),
          reason: '${release.platform}/${release.architecture}',
        );
      }

      expect(
        FfmpegRuntimeRelease.windowsX64.downloadUrl,
        contains('autobuild-2026-10-27-18-38'),
      );
      expect(
        FfmpegRuntimeRelease.windowsX64.downloadUrl,
        contains('-win64-lgpl-9.0.zip'),
      );
      expect(
        FfmpegRuntimeRelease.windowsX64.sha256,
        '79e8ff30c01ac58a2bc4e820c86be81d426ea0bee10df8030fc6ac3c72fe785c',
      );
      expect(FfmpegRuntimeRelease.macosX64.downloadUrl, contains('/v9.0.2/'));
      expect(
        FfmpegRuntimeRelease.macosArm64.downloadUrl,
        contains('arm64.zip'),
      );
      expect(
        FfmpegRuntimeRelease.linuxX64.downloadUrl,
        contains('linux-x64.zip'),
      );
      expect(
        FfmpegRuntimeRelease.linuxArm64.downloadUrl,
        contains('linux-arm64.zip'),
      );
    });

    test('rejects unsupported platform and architecture pairs', () {
      expect(
        () => FfmpegRuntimeRelease.forTarget(
          platform: 'windows',
          architecture: 'arm64',
        ),
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        () => FfmpegRuntimeRelease.forTarget(
          platform: 'web',
          architecture: 'x64',
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
