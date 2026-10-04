import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/repositories/file_playback_session_snapshot_repository.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/playback_session_snapshot.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lyricforge-playback-session-');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('persists Unicode queue, position and playback modes across recreation', () async {
    final first = await _audio(temp, '中文の歌.mp3');
    final second = await _audio(temp, '宇多田ヒカル.flac');
    final savedAt = DateTime.utc(2026, 10, 3, 12, 30);
    final snapshot = PlaybackSessionSnapshot(
      items: [
        _item(first.path, '中文歌曲', artist: '测试艺人'),
        _item(second.path, 'First Love', artist: '宇多田ヒカル'),
      ],
      currentIndex: 1,
      position: const Duration(minutes: 2, seconds: 17),
      shuffleEnabled: true,
      repeatMode: PlaybackRepeatMode.all,
      savedAt: savedAt,
    );

    var repository = FilePlaybackSessionSnapshotRepository(rootDirectory: temp);
    await repository.save(snapshot);

    repository = FilePlaybackSessionSnapshotRepository(rootDirectory: temp);
    final restored = await repository.load();

    expect(restored, isNotNull);
    expect(restored!.items, hasLength(2));
    expect(restored.items.first.title, '中文歌曲');
    expect(restored.items.first.artist, '测试艺人');
    expect(restored.items.last.title, 'First Love');
    expect(restored.items.last.audioAsset.originalPath, second.path);
    expect(restored.currentIndex, 1);
    expect(restored.position, const Duration(minutes: 2, seconds: 17));
    expect(restored.shuffleEnabled, isTrue);
    expect(restored.repeatMode, PlaybackRepeatMode.all);
    expect(restored.savedAt, savedAt);
  });

  test('prunes missing rows and keeps the same current song when it survives', () async {
    final first = await _audio(temp, 'one.mp3');
    final current = await _audio(temp, 'current.mp3');
    final last = await _audio(temp, 'last.mp3');
    final missing = File('${temp.path}${Platform.pathSeparator}missing.mp3');
    final repository = FilePlaybackSessionSnapshotRepository(rootDirectory: temp);
    await repository.save(
      PlaybackSessionSnapshot(
        items: [
          _item(first.path, 'One'),
          _item(missing.path, 'Missing'),
          _item(current.path, 'Current'),
          _item(last.path, 'Last'),
        ],
        currentIndex: 2,
        position: const Duration(seconds: 44),
        shuffleEnabled: false,
        repeatMode: PlaybackRepeatMode.one,
        savedAt: DateTime.utc(2026, 10, 4),
      ),
    );

    final restored = await repository.load();

    expect(restored, isNotNull);
    expect(restored!.items.map((item) => item.title), ['One', 'Current', 'Last']);
    expect(restored.currentIndex, 1);
    expect(restored.items[restored.currentIndex].title, 'Current');

    // The pruned result is written back, so a new repository sees the clean
    // snapshot rather than repeatedly processing the same dead path.
    final recreated = FilePlaybackSessionSnapshotRepository(rootDirectory: temp);
    final secondLoad = await recreated.load();
    expect(secondLoad!.items, hasLength(3));
    expect(secondLoad.items.any((item) => item.title == 'Missing'), isFalse);
  });

  test('falls forward when current file is missing, otherwise to last survivor', () async {
    final before = await _audio(temp, 'before.mp3');
    final after = await _audio(temp, 'after.mp3');
    final missingCurrent = File(
      '${temp.path}${Platform.pathSeparator}missing-current.mp3',
    );
    final repository = FilePlaybackSessionSnapshotRepository(rootDirectory: temp);
    await repository.save(
      PlaybackSessionSnapshot(
        items: [
          _item(before.path, 'Before'),
          _item(missingCurrent.path, 'Missing current'),
          _item(after.path, 'After'),
        ],
        currentIndex: 1,
        position: Duration.zero,
        shuffleEnabled: false,
        repeatMode: PlaybackRepeatMode.off,
        savedAt: DateTime.utc(2026, 10, 4),
      ),
    );

    final restored = await repository.load();
    expect(restored!.items[restored.currentIndex].title, 'After');

    await after.delete();
    await repository.save(
      PlaybackSessionSnapshot(
        items: [
          _item(before.path, 'Before'),
          _item(missingCurrent.path, 'Missing current'),
          _item(after.path, 'After missing too'),
        ],
        currentIndex: 1,
        position: Duration.zero,
        shuffleEnabled: false,
        repeatMode: PlaybackRepeatMode.off,
        savedAt: DateTime.utc(2026, 10, 4),
      ),
    );
    final fallback = await repository.load();
    expect(fallback!.items[fallback.currentIndex].title, 'Before');
  });

  test('clears the persisted document when every source file is missing', () async {
    final missing = File('${temp.path}${Platform.pathSeparator}gone.mp3');
    final repository = FilePlaybackSessionSnapshotRepository(rootDirectory: temp);
    await repository.save(
      PlaybackSessionSnapshot(
        items: [_item(missing.path, 'Gone')],
        currentIndex: 0,
        position: const Duration(seconds: 12),
        shuffleEnabled: false,
        repeatMode: PlaybackRepeatMode.off,
        savedAt: DateTime.utc(2026, 10, 4),
      ),
    );

    expect(await repository.load(), isNull);
    final store = File(
      '${temp.path}${Platform.pathSeparator}playback_session.json',
    );
    expect(await store.exists(), isFalse);
  });
}

Future<File> _audio(Directory directory, String name) async {
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(const [1, 2, 3, 4]);
  return file;
}

PlaybackSessionItemSnapshot _item(
  String path,
  String title, {
  String? artist,
}) {
  return PlaybackSessionItemSnapshot(
    id: 'local:$path',
    title: title,
    artist: artist,
    audioAsset: AudioAsset(
      originalPath: path,
      format: path.split('.').last,
      duration: const Duration(minutes: 4),
      metadata: const {'source': 'test'},
    ),
    preferredSource: AudioSourceType.original,
  );
}
