import 'package:media_kit/media_kit.dart';

import '../just_audio_media_kit.dart';

/// Builds the same audio-only configuration used by the adapter.
PlayerConfiguration audioPlayerConfiguration(void Function() onReady) {
  return PlayerConfiguration(
    // media_kit 1.2.6 writes osc=no when false, which audio-only libmpv
    // builds may reject. No video surface or on-screen controls are created.
    osc: true,
    pitch: JustAudioMediaKit.pitch,
    protocolWhitelist: JustAudioMediaKit.protocolWhitelist,
    title: JustAudioMediaKit.title,
    bufferSize: JustAudioMediaKit.bufferSize,
    logLevel: JustAudioMediaKit.mpvLogLevel,
    ready: onReady,
  );
}

/// Waits for the native player before applying the two local MPV options.
Future<void> prepareAudioPlayer(
  Future<void> ready,
  Future<void> Function(String name, String value) setProperty,
) async {
  await ready;
  // Keep normal memory/network buffering while avoiding temporary cache files.
  await setProperty('cache-on-disk', 'no');
  await setProperty('sub-auto', 'no');
}
