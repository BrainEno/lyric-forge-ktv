import 'dart:async';

import '../../../player/domain/models/playback_state.dart';
import '../../../player/domain/services/audio_player_service.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/media_hub_connection.dart';
import '../../domain/services/media_hub_client_service.dart';
import '../../domain/services/media_hub_connection_store.dart';

/// Guarantees that every Media Hub audio load uses the latest usable connection
/// known to the app, including loads triggered internally by automatic queue
/// advance.
///
/// Non-Media-Hub HTTP audio and local/project audio pass through unchanged.
class MediaHubRebindingAudioPlayerService implements AudioPlayerService {
  final AudioPlayerService delegate;
  final MediaHubClientService client;
  final MediaHubConnectionStore connectionStore;

  MediaHubRebindingAudioPlayerService({
    required this.delegate,
    required this.client,
    required this.connectionStore,
  });

  @override
  PlaybackState get currentState => delegate.currentState;

  @override
  Stream<PlaybackState> get stateStream => delegate.stateStream;

  @override
  Stream<Duration> get positionStream => delegate.positionStream;

  @override
  Stream<Duration?> get durationStream => delegate.durationStream;

  @override
  Future<void> loadProjectAudio({
    required AudioAsset audioAsset,
    AudioSourceType preferredSource = AudioSourceType.instrumental,
  }) =>
      delegate.loadProjectAudio(
        audioAsset: audioAsset,
        preferredSource: preferredSource,
      );

  @override
  Future<void> loadAudioUri({
    required Uri uri,
    AudioSourceType source = AudioSourceType.original,
  }) async {
    final resolved = await _latestMediaHubUri(uri);
    await delegate.loadAudioUri(uri: resolved, source: source);
  }

  Future<Uri> _latestMediaHubUri(Uri original) async {
    if (!_looksLikeMediaHubAudio(original)) return original;

    final active = client.currentConnection;
    final saved = await connectionStore.loadLastConnection();
    final candidates = <MediaHubConnection>[];
    if (active != null) candidates.add(active);
    if (saved != null &&
        (active == null || !_sameConnection(active, saved))) {
      candidates.add(saved);
    }

    if (candidates.isEmpty) return original;

    Object? lastError;
    for (final connection in candidates) {
      try {
        // connectTo may transparently replace a stale endpoint through the UDP
        // device discovery flow. Always rebase with the connection it actually
        // resolved, not the stale candidate passed into this call.
        await client.connectTo(connection);
        final resolvedConnection = client.currentConnection ?? connection;
        return _rebase(original, resolvedConnection);
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError != null) throw lastError;
    return original;
  }

  bool _sameConnection(MediaHubConnection a, MediaHubConnection b) =>
      a.host == b.host && a.port == b.port && a.token == b.token;

  bool _looksLikeMediaHubAudio(Uri uri) {
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    final segments = uri.pathSegments;
    return segments.length >= 4 &&
        segments[0] == 'v1' &&
        segments[1] == 'tracks' &&
        segments.last == 'audio';
  }

  Uri _rebase(Uri original, MediaHubConnection connection) {
    final rebased = connection.resolve(original.path);
    return rebased.replace(
      queryParameters: {
        ...original.queryParameters,
        'token': connection.token,
      },
    );
  }

  @override
  Future<void> play() => delegate.play();

  @override
  Future<void> pause() => delegate.pause();

  @override
  Future<void> stop() => delegate.stop();

  @override
  Future<void> seek(Duration position) => delegate.seek(position);

  @override
  Future<void> switchSource(AudioSourceType source) =>
      delegate.switchSource(source);

  @override
  Future<void> setSpeed(double speed) => delegate.setSpeed(speed);

  @override
  Future<void> setVolume(double volume) => delegate.setVolume(volume);

  @override
  Future<void> dispose() => delegate.dispose();
}
