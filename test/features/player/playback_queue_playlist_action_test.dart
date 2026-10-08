import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/playback_queue_playlist_action.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

PlaybackItem item(
  String id,
  String path, {
  String? projectId,
  Uri? streamUri,
}) {
  return PlaybackItem(
    id: id,
    title: id,
    projectId: projectId,
    streamUri: streamUri,
    audioAsset: AudioAsset(
      originalPath: path,
      format: 'mp3',
    ),
  );
}

void main() {
  test('queue playlist paths keep local songs in queue order', () {
    final state = PlaybackSessionState(
      queue: [
        item('a', r'D:\Music\a.mp3'),
        item('b', r'D:\Music\b.mp3'),
        item('c', r'D:\Music\c.mp3'),
      ],
      currentIndex: 1,
    );

    expect(
      localQueuePlaylistPaths(state),
      [r'D:\Music\a.mp3', r'D:\Music\b.mp3', r'D:\Music\c.mp3'],
    );
  });

  test('remote streams, projects, blank paths and duplicates are skipped', () {
    final state = PlaybackSessionState(
      queue: [
        item('local', r'D:\Music\keep.mp3'),
        item(
          'remote',
          r'D:\Cache\remote.mp3',
          streamUri: Uri.parse('http://192.168.1.10/music/remote.mp3'),
        ),
        item('project', r'D:\Projects\song\original.mp3', projectId: 'p1'),
        item('blank', '   '),
        item('duplicate', r'D:\Music\keep.mp3'),
      ],
    );

    expect(localQueuePlaylistPaths(state), [r'D:\Music\keep.mp3']);
  });
}
