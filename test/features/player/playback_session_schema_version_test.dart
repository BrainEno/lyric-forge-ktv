import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_playback_session_store.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_session_snapshot.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

void main() {
  test('file store loads a legacy session without a version stamp', () async {
    final root = await Directory.systemTemp.createTemp(
      'elysium_session_store_',
    );
    addTearDown(() => root.delete(recursive: true));
    final store = FilePlaybackSessionStore(rootDirectory: root);
    await store.save(
      PlaybackSessionSnapshot(
        state: PlaybackSessionState(
          queue: [_localItem('local:1', '/music/one.mp3')],
          currentIndex: 0,
        ),
        position: Duration.zero,
        savedAt: DateTime.utc(2026, 10, 8, 1),
      ),
    );

    // Simulate a document written before schema versioning existed.
    final file = File(
      '${root.path}${Platform.pathSeparator}playback_session.json',
    );
    final decoded = jsonDecode(await file.readAsString()) as Map;
    final legacy = Map<String, dynamic>.from(decoded)..remove('version');
    await file.writeAsString(jsonEncode(legacy), flush: true);

    final loaded = await store.load();
    expect(loaded, isNotNull);
    expect(loaded!.state.currentItem?.id, 'local:1');
  });

  test('file store rejects a session from a newer schema version', () async {
    final root = await Directory.systemTemp.createTemp(
      'elysium_session_store_',
    );
    addTearDown(() => root.delete(recursive: true));
    final store = FilePlaybackSessionStore(rootDirectory: root);
    final file = File(
      '${root.path}${Platform.pathSeparator}playback_session.json',
    );
    await file.writeAsString(
      jsonEncode({'version': 99, 'queue': <Object?>[]}),
      flush: true,
    );

    await expectLater(store.load(), throwsA(isA<FormatException>()));
    // The newer document is left untouched for the newer build.
    expect(jsonDecode(await file.readAsString()), {
      'version': 99,
      'queue': <Object?>[],
    });
  });
}

PlaybackItem _localItem(String id, String path) {
  return PlaybackItem(
    id: id,
    title: id,
    audioAsset: AudioAsset(
      originalPath: path,
      format: 'mp3',
      duration: const Duration(minutes: 3),
    ),
  );
}
