/// Pinned managed FFmpeg assets.
///
/// URLs point to immutable, versioned release assets rather than a floating
/// "latest" alias. Review the URL and SHA-256 together when updating a pin.
class FfmpegRuntimeRelease {
  const FfmpegRuntimeRelease({
    required this.platform,
    required this.architecture,
    required this.version,
    required this.downloadUrl,
    required this.sha256,
  });

  final String platform;
  final String architecture;
  final String version;
  final String downloadUrl;
  final String sha256;

  Uri get downloadUri => Uri.parse(downloadUrl);

  static const windowsX64 = FfmpegRuntimeRelease(
    platform: 'windows',
    architecture: 'x64',
    version: '9.0.2-36-g6882969ce9 (LGPL)',
    downloadUrl:
        'https://github.com/BtbN/FFmpeg-Builds/releases/download/'
        'autobuild-2026-10-27-18-38/'
        'ffmpeg-n9.0.2-36-g6882969ce9-win64-lgpl-9.0.zip',
    sha256:
        '79e8ff30c01ac58a2bc4e820c86be81d426ea0bee10df8030fc6ac3c72fe785c',
  );

  static const macosX64 = FfmpegRuntimeRelease(
    platform: 'macos',
    architecture: 'x64',
    version: '9.0.2',
    downloadUrl:
        'https://github.com/boul2gom/ffmpeg-builds/releases/download/'
        'v9.0.2/ffmpeg-osx-x64.zip',
    sha256:
        'bc6a726fcd237ecae0a3303acb747fe782075dcc069a0f889586821403f9e788',
  );

  static const macosArm64 = FfmpegRuntimeRelease(
    platform: 'macos',
    architecture: 'arm64',
    version: '9.0.2',
    downloadUrl:
        'https://github.com/boul2gom/ffmpeg-builds/releases/download/'
        'v9.0.2/ffmpeg-osx-arm64.zip',
    sha256:
        '1e935c8d5231c75907347ba7b860ff35018466ce1f9f5d44509f5e82bc504e77',
  );

  static const linuxX64 = FfmpegRuntimeRelease(
    platform: 'linux',
    architecture: 'x64',
    version: '9.0.2',
    downloadUrl:
        'https://github.com/boul2gom/ffmpeg-builds/releases/download/'
        'v9.0.2/ffmpeg-linux-x64.zip',
    sha256:
        'b792b04f4f159f886a368a3e7f40178d5af8367742caedda68c0dbc9204384fa',
  );

  static const linuxArm64 = FfmpegRuntimeRelease(
    platform: 'linux',
    architecture: 'arm64',
    version: '9.0.2',
    downloadUrl:
        'https://github.com/boul2gom/ffmpeg-builds/releases/download/'
        'v9.0.2/ffmpeg-linux-arm64.zip',
    sha256:
        'f27274e3859cc53a072d1564be98ff83fbed11da72fabdacc54740fb50f904cc',
  );

  static const supported = <FfmpegRuntimeRelease>[
    windowsX64,
    macosX64,
    macosArm64,
    linuxX64,
    linuxArm64,
  ];

  static FfmpegRuntimeRelease forTarget({
    required String platform,
    required String architecture,
  }) {
    for (final release in supported) {
      if (release.platform == platform &&
          release.architecture == architecture) {
        return release;
      }
    }
    throw UnsupportedError(
      'No pinned FFmpeg asset for $platform/$architecture',
    );
  }
}
