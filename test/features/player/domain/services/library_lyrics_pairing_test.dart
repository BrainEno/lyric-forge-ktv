import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/local_media_metadata.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/library_lyric_file_matcher.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/library_lyrics_pairing.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';

void main() {
  final pairing = LibraryLyricsPairing(
    lyricPath: '/曲库/夜曲.lrc',
    projectId: 'p-1',
    reason: LibraryLyricMatchReason.title,
    createdProject: true,
    projectRevision: 1,
    previousStatus: ProjectStatus.draft,
    previousStage: ProcessingStage.none,
    fingerprint: '1:abcdef01',
    pairedAt: DateTime.utc(2026, 11, 29, 9),
  );

  LocalMediaMetadata metadata(Map<String, dynamic> values) {
    return LocalMediaMetadata(
      sourcePath: '/music/夜曲.mp3',
      updatedAt: DateTime(2026),
      metadata: values,
    );
  }

  group('record', () {
    test('survives a round trip through JSON', () {
      final read = LibraryLyricsPairing.fromJson(pairing.toJson())!;

      expect(read.lyricPath, '/曲库/夜曲.lrc');
      expect(read.projectId, 'p-1');
      expect(read.reason, LibraryLyricMatchReason.title);
      expect(read.createdProject, isTrue);
      expect(read.projectRevision, 1);
      expect(read.previousStatus, ProjectStatus.draft);
      expect(read.previousStage, ProcessingStage.none);
      expect(read.fingerprint, '1:abcdef01');
      expect(read.pairedAt, DateTime.utc(2026, 11, 29, 9));
    });

    test('a damaged record reads as no record', () {
      final json = pairing.toJson();

      expect(LibraryLyricsPairing.fromJson(null), isNull);
      expect(LibraryLyricsPairing.fromJson('lyricAutoLink'), isNull);
      expect(LibraryLyricsPairing.fromJson({...json, 'path': ''}), isNull);
      expect(LibraryLyricsPairing.fromJson({...json, 'reason': 'x'}), isNull);
      expect(
        LibraryLyricsPairing.fromJson({...json, 'projectRevision': '1'}),
        isNull,
      );
      expect(
        LibraryLyricsPairing.fromJson({...json, 'previousStage': 'later'}),
        isNull,
      );
      expect(
        LibraryLyricsPairing.fromJson({...json, 'pairedAt': 'yesterday'}),
        isNull,
      );
    });

    test('counts only while the song is linked to the paired project', () {
      final record = pairing.toJson();

      expect(LibraryLyricsPairing.of(null), isNull);
      expect(
        LibraryLyricsPairing.of(
          metadata({
            'linkedProjectId': 'p-1',
            LibraryLyricsPairing.metadataKey: record,
          }),
        )?.lyricPath,
        '/曲库/夜曲.lrc',
      );
      // Linked by hand to another project later: the old record is stale.
      expect(
        LibraryLyricsPairing.of(
          metadata({
            'linkedProjectId': 'p-2',
            LibraryLyricsPairing.metadataKey: record,
          }),
        ),
        isNull,
      );
      expect(
        LibraryLyricsPairing.of(
          metadata({LibraryLyricsPairing.metadataKey: record}),
        ),
        isNull,
      );
    });

    test('lists the files the user took back, ignoring junk', () {
      expect(LibraryLyricsPairing.dismissedFiles(null), isEmpty);
      expect(
        LibraryLyricsPairing.dismissedFiles(
          metadata({
            LibraryLyricsPairing.dismissedKey: ['/曲库/a.lrc', 3, '  ', '/b.srt'],
          }),
        ),
        {'/曲库/a.lrc', '/b.srt'},
      );
      expect(
        LibraryLyricsPairing.dismissedFiles(
          metadata({LibraryLyricsPairing.dismissedKey: '/曲库/a.lrc'}),
        ),
        isEmpty,
      );
    });
  });

  group('fingerprint', () {
    LyricDocument document(List<(String, int, int)> lines) {
      return LyricDocument(
        language: 'zh',
        lines: [
          for (final (text, start, end) in lines)
            LyricLine(
              text: text,
              startTime: Duration(milliseconds: start),
              endTime: Duration(milliseconds: end),
            ),
        ],
      );
    }

    test('is empty without lyrics', () {
      expect(lyricLinesFingerprint(null), '');
      expect(lyricLinesFingerprint(document(const [])), '');
    });

    test('is stable and changes with any text or timing edit', () {
      const first = ('一群嗜血的蚂蚁', 0, 3000);
      const second = ('被腐肉所吸引', 3000, 6000);
      final original = document(const [first, second]);
      final same = document(const [first, second]);
      final retimed = document(const [first, ('被腐肉所吸引', 3100, 6000)]);
      final retyped = document(const [first, ('被腐肉所吸引了', 3000, 6000)]);
      final dropped = document(const [first]);

      final digest = lyricLinesFingerprint(original);
      expect(digest, startsWith('2:'));
      expect(lyricLinesFingerprint(same), digest);
      expect(lyricLinesFingerprint(retimed), isNot(digest));
      expect(lyricLinesFingerprint(retyped), isNot(digest));
      expect(lyricLinesFingerprint(dropped), isNot(digest));
    });

    test('ignores details other than the lines', () {
      final plain = document(const [('晴天', 0, 2000)]);
      final noted = LyricDocument(
        language: 'zh-Hant',
        lines: plain.lines,
        metadata: const {'reviewed': true},
      );

      expect(lyricLinesFingerprint(noted), lyricLinesFingerprint(plain));
    });
  });

  group('projectWithoutPairedLyrics', () {
    test('drops the lyrics and the import, keeps everything else', () {
      final project = ProjectManifest(
        id: 'p-1',
        name: '夜曲',
        artist: '周杰伦',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026, 11, 29),
        revision: 4,
        status: ProjectStatus.ready,
        currentStage: ProcessingStage.lyricsEdited,
        audioAsset: const AudioAsset(
          originalPath: '/music/夜曲.mp3',
          format: 'mp3',
        ),
        lyricDocument: LyricDocument(
          language: 'zh',
          lines: [
            LyricLine(
              text: '一群嗜血的蚂蚁',
              startTime: Duration.zero,
              endTime: const Duration(seconds: 3),
            ),
          ],
        ),
        metadata: const {
          'lyricSource': 'library-folder',
          'lyricImport': {'path': '/曲库/夜曲.lrc', 'automatic': true},
          'lyricBackups': ['older'],
          'stems': 'kept',
        },
      );

      final emptied = projectWithoutPairedLyrics(project, pairing);

      expect(emptied.hasLyrics, isFalse);
      expect(emptied.lyricDocument, isNull);
      expect(emptied.status, ProjectStatus.draft);
      expect(emptied.currentStage, ProcessingStage.none);
      expect(emptied.id, 'p-1');
      expect(emptied.revision, 4);
      expect(emptied.artist, '周杰伦');
      expect(emptied.audioAsset?.originalPath, '/music/夜曲.mp3');
      expect(emptied.metadata.keys, unorderedEquals(['lyricBackups', 'stems']));
      expect(emptied.metadata['lyricBackups'], ['older']);
    });

    test('keeps a later import from another file', () {
      final project = ProjectManifest(
        id: 'p-1',
        name: '夜曲',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        metadata: const {
          'lyricSource': 'imported-file',
          'lyricImport': {'path': '/下载/夜曲.lrc'},
        },
      );

      final emptied = projectWithoutPairedLyrics(project, pairing);

      expect(emptied.metadata['lyricSource'], 'imported-file');
      expect(emptied.metadata['lyricImport'], {'path': '/下载/夜曲.lrc'});
    });
  });
}
