import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/imported_lyrics_project.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';

void main() {
  final now = DateTime.utc(2026, 11, 28, 9);
  const audio = AudioAsset(originalPath: '/music/夜曲.mp3', format: 'mp3');

  LyricDocument document(String text, {bool timed = true}) {
    return LyricDocument(
      language: 'zh',
      lines: [
        LyricLine(
          text: text,
          startTime: Duration.zero,
          endTime: const Duration(seconds: 2),
        ),
      ],
      metadata: {'timed': timed},
    );
  }

  LyricImportResult imported(String text, {bool timed = true}) {
    return LyricImportResult(
      document: document(text, timed: timed),
      format: LyricImportFormat.lrc,
      sourcePath: '/曲库/夜曲.lrc',
      detectedEncoding: 'gbk',
      artist: '文件里的歌手',
      album: '十一月的萧邦',
    );
  }

  ProjectManifest project({LyricDocument? lyrics, Map<String, dynamic>? meta}) {
    return ProjectManifest(
      id: 'p',
      name: '旧名字',
      createdAt: now,
      updatedAt: now,
      lyricDocument: lyrics,
      metadata: meta ?? const {'keep': 'me'},
    );
  }

  test('a timed file makes a ready project for the song', () {
    final result = projectWithImportedLyrics(
      project(),
      title: '夜曲',
      artist: null,
      audioAsset: audio,
      artworkPath: '/art/夜曲.jpg',
      result: imported('一群嗜血的蚂蚁'),
      now: now,
    );

    expect(result.name, '夜曲');
    expect(result.artist, '文件里的歌手');
    expect(result.album, '十一月的萧邦');
    expect(result.audioAsset?.thumbnailPath, '/art/夜曲.jpg');
    expect(result.status, ProjectStatus.ready);
    expect(result.currentStage, ProcessingStage.lyricsEdited);
    expect(result.lyricDocument?.metadata['detectedEncoding'], 'gbk');
    expect(result.lyricDocument?.metadata['importedAt'], now.toIso8601String());
    expect(result.metadata['keep'], 'me');
    expect(result.metadata['lyricSource'], 'imported-file');
    expect(result.metadata['lyricImport'], {
      'path': '/曲库/夜曲.lrc',
      'format': 'lrc',
      'encoding': 'gbk',
      'timed': true,
      'importedAt': now.toIso8601String(),
    });
    expect(result.metadata.containsKey('lyricBackups'), isFalse);
  });

  test('plain text still needs timing; an automatic pairing says so', () {
    final result = projectWithImportedLyrics(
      project(),
      title: '夜曲',
      artist: '周杰伦',
      audioAsset: audio,
      artworkPath: null,
      result: imported('一群嗜血的蚂蚁', timed: false),
      now: now,
      source: 'library-folder',
      automatic: true,
    );

    expect(result.artist, '周杰伦');
    expect(result.status, ProjectStatus.editing);
    expect(result.currentStage, ProcessingStage.transcriptionComplete);
    expect(result.metadata['lyricSource'], 'library-folder');
    final import = result.metadata['lyricImport'] as Map<String, dynamic>;
    expect(import['automatic'], isTrue);
    expect(import['timed'], isFalse);
  });

  test('replaced lyrics are backed up, newest first, at most three', () {
    final older = [
      for (var index = 0; index < 3; index++)
        {'reason': 'replaced-by-import', 'index': index},
    ];
    final result = projectWithImportedLyrics(
      project(lyrics: document('手工校对过'), meta: {'lyricBackups': older}),
      title: '夜曲',
      artist: null,
      audioAsset: audio,
      artworkPath: null,
      result: imported('新歌词'),
      now: now,
    );

    final backups = result.metadata['lyricBackups'] as List;
    expect(backups, hasLength(3));
    final newest = backups.first as Map<String, dynamic>;
    expect(newest['createdAt'], now.toIso8601String());
    final saved = LyricDocument.fromJson(
      newest['document'] as Map<String, dynamic>,
    );
    expect(saved.lines.single.text, '手工校对过');
    expect((backups[1] as Map)['index'], 0);
    expect((backups[2] as Map)['index'], 1);
  });

  test('a project without lyrics has nothing to back up', () {
    expect(nextLyricBackups(project(), now: now), isEmpty);
  });
}
