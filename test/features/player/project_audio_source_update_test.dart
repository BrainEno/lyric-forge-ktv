import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/audio_player_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/project_audio_source_update.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/transfer/data/services/media_hub_rebinding_audio_player_service.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/services/media_hub_client_service.dart';
import 'package:lyric_forge_ktv/features/transfer/domain/services/media_hub_connection_store.dart';

void main() {
  const original = AudioAsset(originalPath: '/song.wav', format: 'wav');
  const newBacking = AudioAsset(
    originalPath: '/song.wav',
    instrumentalPath: '/backing.wav',
    format: 'wav',
  );
  const oldBacking = AudioAsset(
    originalPath: '/song.wav',
    instrumentalPath: '/old.wav',
    format: 'wav',
  );

  AudioAsset? update({
    AudioAsset? current = original,
    AudioAsset expected = original,
    AudioAsset replacement = newBacking,
    AudioSourceType? source = AudioSourceType.original,
  }) => safeProjectAudioSourceUpdate(
    current: current,
    expected: expected,
    replacement: replacement,
    activeSource: source,
  );

  test(
    'adds an inactive accompaniment without changing the active original',
    () {
      expect(update(), same(newBacking));
      expect(
        update(current: oldBacking, expected: oldBacking),
        same(newBacking),
      );
    },
  );

  test('refuses stale, remote, unknown or different source bindings', () {
    expect(update(current: null), isNull);
    expect(update(source: null), isNull);
    expect(update(current: oldBacking), isNull);
    expect(
      update(
        replacement: const AudioAsset(
          originalPath: '/other.wav',
          format: 'wav',
        ),
      ),
      isNull,
    );
    expect(update(source: AudioSourceType.vocals), isNull);
  });

  test('does not silently replace the source currently being played', () {
    expect(
      update(
        current: oldBacking,
        expected: oldBacking,
        source: AudioSourceType.instrumental,
      ),
      isNull,
    );
    expect(
      update(
        current: newBacking,
        expected: newBacking,
        replacement: newBacking,
        source: AudioSourceType.instrumental,
      ),
      same(newBacking),
    );
  });

  test('wrapper delegates only when it supports the capability', () {
    final player = _SourcePlayer();
    final wrapper = _wrapper(player);
    expect(
      wrapper.updateActiveProjectAudioSources(
        expected: original,
        replacement: newBacking,
      ),
      isTrue,
    );
    expect(player.expected, same(original));
    expect(player.replacement, same(newBacking));
    final unsupported = _wrapper(_UnsupportedPlayer());
    expect(
      unsupported.updateActiveProjectAudioSources(
        expected: original,
        replacement: newBacking,
      ),
      isFalse,
    );
  });

  test(
    'wrapper rejects updates throughout overlapping audio loads, including errors',
    () async {
      final player = _SourcePlayer();
      final wrapper = _wrapper(player);
      final first = Completer<void>();
      final second = Completer<void>();
      player.projectLoad = first.future;
      final a = wrapper.loadProjectAudio(audioAsset: original);
      player.uriLoad = second.future;
      final b = wrapper.loadAudioUri(uri: Uri.parse('file:///song.wav'));
      expect(
        wrapper.updateActiveProjectAudioSources(
          expected: original,
          replacement: newBacking,
        ),
        isFalse,
      );
      first.complete();
      await a;
      expect(
        wrapper.updateActiveProjectAudioSources(
          expected: original,
          replacement: newBacking,
        ),
        isFalse,
      );
      final failure = expectLater(b, throwsStateError);
      second.completeError(StateError('load failed'));
      await failure;
      expect(
        wrapper.updateActiveProjectAudioSources(
          expected: original,
          replacement: newBacking,
        ),
        isTrue,
      );
    },
  );
}

MediaHubRebindingAudioPlayerService _wrapper(AudioPlayerService player) =>
    MediaHubRebindingAudioPlayerService(
      delegate: player,
      client: _Client(),
      connectionStore: _Connections(),
    );

class _UnsupportedPlayer extends Fake implements AudioPlayerService {}

class _SourcePlayer extends Fake
    implements AudioPlayerService, ActiveProjectAudioSourceUpdater {
  AudioAsset? expected;
  AudioAsset? replacement;
  Future<void> projectLoad = Future.value();
  Future<void> uriLoad = Future.value();

  @override
  bool updateActiveProjectAudioSources({
    required AudioAsset expected,
    required AudioAsset replacement,
  }) {
    this.expected = expected;
    this.replacement = replacement;
    return true;
  }

  @override
  Future<void> loadProjectAudio({
    required AudioAsset audioAsset,
    AudioSourceType preferredSource = AudioSourceType.instrumental,
  }) => projectLoad;

  @override
  Future<void> loadAudioUri({
    required Uri uri,
    AudioSourceType source = AudioSourceType.original,
  }) => uriLoad;
}

class _Client extends Fake implements MediaHubClientService {}

class _Connections extends Fake implements MediaHubConnectionStore {}
