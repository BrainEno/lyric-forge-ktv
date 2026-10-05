import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

import '../../domain/services/audio_player_service.dart';
import '../../domain/services/playback_session_service.dart';
import 'system_media_audio_handler.dart';

LyricForgeSystemMediaHandler? _systemMediaHandler;
StreamSubscription<void>? _becomingNoisySubscription;

/// Installs the platform media session on Android/iOS only.
///
/// Desktop playback keeps using the exact same LyricForge audio/session stack
/// without initialising a mobile AudioService implementation.
Future<void> initializeMobileSystemMediaSession({
  required PlaybackSessionService playbackSession,
  required AudioPlayerService audioPlayer,
}) async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS)) {
    return;
  }
  if (_systemMediaHandler != null) return;

  final audioSession = await AudioSession.instance;
  await audioSession.configure(AudioSessionConfiguration.music());

  final handler = await AudioService.init<LyricForgeSystemMediaHandler>(
    builder: () => LyricForgeSystemMediaHandler(
      session: playbackSession,
      audio: audioPlayer,
    ),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.braineno.lyricforge.playback',
      androidNotificationChannelName: 'LyricForge 播放',
      androidNotificationChannelDescription: '本地音乐播放、锁屏和耳机控制',
      androidNotificationIcon: 'drawable/ic_stat_lyricforge_music',
      androidShowNotificationBadge: false,
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      androidResumeOnClick: true,
      androidNotificationClickStartsActivity: true,
      preloadArtwork: true,
      artDownscaleWidth: 1024,
      artDownscaleHeight: 1024,
      fastForwardInterval: Duration(seconds: 10),
      rewindInterval: Duration(seconds: 10),
    ),
  );
  _systemMediaHandler = handler;

  // just_audio already handles normal audio focus/phone-call interruptions.
  // Explicitly handling "becoming noisy" guarantees that unplugging wired
  // headphones or disconnecting a route does not suddenly play through the
  // phone speaker.
  _becomingNoisySubscription?.cancel();
  _becomingNoisySubscription = audioSession.becomingNoisyEventStream.listen((_) {
    if (audioPlayer.currentState.isPlaying) {
      unawaited(handler.pause());
    }
  });
}
