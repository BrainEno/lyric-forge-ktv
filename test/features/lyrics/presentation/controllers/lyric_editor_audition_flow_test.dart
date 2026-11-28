import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/controllers/lyric_editor_audition_flow.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';

final _at = DateTime(2027, 1, 6);

const _asset = AudioAsset(
  originalPath: '/songs/qingtian.mp3',
  format: 'mp3',
  thumbnailPath: '/covers/qingtian.jpg',
  duration: Duration(minutes: 4),
);

ProjectManifest _project({String id = 'p1', LyricDocument? lyrics}) =>
    ProjectManifest(
      id: id,
      name: '晴天',
      artist: '周杰伦',
      createdAt: _at,
      updatedAt: _at,
      audioAsset: _asset,
      lyricDocument: lyrics,
    );

PlaybackItem _playing(String projectId) => PlaybackItem(
  id: 'project:$projectId',
  title: projectId,
  projectId: projectId,
  audioAsset: _asset,
);

void main() {
  group('playbackItemFor', () {
    test('plays the project as itself, from the original audio', () {
      final item = LyricEditorAuditionFlow.playbackItemFor(_project(), _asset);

      expect(item.id, 'project:p1');
      expect(item.title, '晴天');
      expect(item.artist, '周杰伦');
      expect(item.projectId, 'p1');
      expect(item.artworkPath, '/covers/qingtian.jpg');
      expect(item.hasLyrics, isFalse);
      expect(item.preferredSource, AudioSourceType.original);
    });

    test('prefers the vocal stem and carries the lyrics flag', () {
      const separated = AudioAsset(
        originalPath: '/songs/qingtian.mp3',
        vocalPath: '/stems/qingtian_vocals.wav',
        format: 'mp3',
      );
      final project = _project(
        lyrics: const LyricDocument(
          language: 'zh',
          lines: [
            LyricLine(
              id: 'l1',
              text: '故事的小黄花',
              startTime: Duration(seconds: 1),
              endTime: Duration(seconds: 3),
            ),
          ],
        ),
      );

      final item = LyricEditorAuditionFlow.playbackItemFor(project, separated);

      expect(item.preferredSource, AudioSourceType.vocals);
      expect(item.hasLyrics, isTrue);
    });
  });

  group('audioDurationFor', () {
    const measured = Duration(minutes: 4, seconds: 9);

    test('uses what the player measured while it plays this project', () {
      expect(
        LyricEditorAuditionFlow.audioDurationFor(
          _project(),
          _asset,
          current: _playing('p1'),
          playerDuration: measured,
        ),
        measured,
      );
    });

    test('falls back to the stored length before the player knows', () {
      expect(
        LyricEditorAuditionFlow.audioDurationFor(
          _project(),
          _asset,
          current: _playing('p1'),
          playerDuration: null,
        ),
        _asset.duration,
      );
    });

    test('ignores the player while it plays something else', () {
      for (final current in [_playing('other'), null]) {
        expect(
          LyricEditorAuditionFlow.audioDurationFor(
            _project(),
            _asset,
            current: current,
            playerDuration: measured,
          ),
          _asset.duration,
        );
      }
    });
  });
}
