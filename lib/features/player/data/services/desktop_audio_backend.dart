import 'package:flutter/foundation.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

/// Returns true when desktop playback should use the libmpv/FFmpeg-backed
/// just_audio implementation instead of a platform codec implementation.
bool shouldUseDesktopMediaKit({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (isWeb) return false;
  return platform == TargetPlatform.windows || platform == TargetPlatform.linux;
}

bool _initialized = false;

/// Must run before the first just_audio [AudioPlayer] is constructed.
///
/// On Windows/Linux this registers just_audio_media_kit, which uses libmpv and
/// FFmpeg and therefore handles a substantially wider range of MP3 variants,
/// VBR files and unusual container/tag layouts than host-codec-only backends.
/// Android/iOS/macOS keep just_audio's native implementations.
void initializeDesktopAudioBackend() {
  if (_initialized) return;
  if (!shouldUseDesktopMediaKit(
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
  )) {
    return;
  }

  JustAudioMediaKit.title = 'Elysium Player';
  JustAudioMediaKit.ensureInitialized();
  _initialized = true;
}
