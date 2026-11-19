import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/library_lyric_file_matcher.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/library_lyrics_auto_linker.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/library_lyrics_pairing.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/library_lyrics_link_text.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';

void main() {
  LibraryLyricMatch match(String title, String lyricPath) {
    return LibraryLyricMatch(
      song: LibraryLyricSong(audioPath: '/music/$title.mp3', title: title),
      lyricPath: lyricPath,
      reason: LibraryLyricMatchReason.title,
    );
  }

  test('one song names the song and the file', () {
    final pass = LibraryLyricsLinkResult(
      linked: [match('夜曲', r'D:\曲库\周杰伦 - 夜曲.lrc')],
    );

    expect(LibraryLyricsLinkText.summary(pass), '「夜曲」已配上歌词文件「周杰伦 - 夜曲.lrc」');
    expect(LibraryLyricsLinkText.libraryNotice(pass), isNotNull);
  });

  test('several songs are counted, failures added', () {
    final pass = LibraryLyricsLinkResult(
      linked: [match('夜曲', '/a/夜曲.lrc'), match('晴天', '/a/晴天.lrc')],
      failed: const ['/a/坏.lrc'],
    );

    expect(LibraryLyricsLinkText.summary(pass), '已为 2 首歌配上歌词文件；1 个歌词文件没能读取');
  });

  test('nothing new is said plainly, and the library stays quiet', () {
    const nothing = LibraryLyricsLinkResult();
    const onlyFailures = LibraryLyricsLinkResult(failed: ['/a/坏.lrc']);

    expect(LibraryLyricsLinkText.summary(nothing), '没有找到能配对的新歌词文件');
    expect(LibraryLyricsLinkText.libraryNotice(nothing), isNull);
    expect(LibraryLyricsLinkText.summary(onlyFailures), '1 个歌词文件没能读取');
    expect(LibraryLyricsLinkText.libraryNotice(onlyFailures), isNull);
  });

  group('taking a pairing back (D-034)', () {
    final pairing = LibraryLyricsPairing(
      lyricPath: r'D:\曲库\夜曲.lrc',
      projectId: 'p-1',
      reason: LibraryLyricMatchReason.title,
      createdProject: true,
      projectRevision: 1,
      previousStatus: ProjectStatus.draft,
      previousStage: ProcessingStage.none,
      fingerprint: '1:00000000',
      pairedAt: DateTime(2026, 11, 29),
    );

    test('every reason is explained, the weakest with its caveat', () {
      final labels = {
        for (final reason in LibraryLyricMatchReason.values)
          LibraryLyricsLinkText.reasonLabel(reason),
      };

      expect(labels, hasLength(LibraryLyricMatchReason.values.length));
      expect(
        LibraryLyricsLinkText.reasonLabel(LibraryLyricMatchReason.title),
        contains('没有核对歌手'),
      );
    });

    test('the question names the song and the file only', () {
      expect(
        LibraryLyricsLinkText.unpairQuestion('夜曲', pairing),
        '「夜曲」的歌词是按文件名从「夜曲.lrc」自动配上的。解除后这首歌不再显示这份歌词。',
      );
    });

    test('each outcome says what happened', () {
      String say(LibraryLyricsUnpairOutcome outcome) {
        return LibraryLyricsLinkText.unpairOutcome(
          '夜曲',
          LibraryLyricsUnpairResult(outcome, pairing: pairing),
        );
      }

      expect(say(LibraryLyricsUnpairOutcome.unpaired), '已解除「夜曲」和「夜曲.lrc」的配对');
      expect(
        say(LibraryLyricsUnpairOutcome.notAutoPaired),
        '「夜曲」的歌词不是自动配对的，没有改动',
      );
      expect(
        say(LibraryLyricsUnpairOutcome.editedSincePairing),
        contains('为免丢失修改'),
      );
    });

    test('undo says whether the lyrics came back', () {
      final restored = LibraryLyricsLinkResult(
        linked: [match('夜曲', r'D:\曲库\夜曲.lrc')],
      );
      const unreadable = LibraryLyricsLinkResult(failed: ['/曲库/夜曲.lrc']);
      const skipped = LibraryLyricsLinkResult();

      expect(
        LibraryLyricsLinkText.pairAgainOutcome('夜曲', restored),
        '已恢复「夜曲」的歌词配对',
      );
      expect(
        LibraryLyricsLinkText.pairAgainOutcome('夜曲', unreadable),
        '没能恢复：歌词文件「夜曲.lrc」读取失败',
      );
      expect(
        LibraryLyricsLinkText.pairAgainOutcome('夜曲', skipped),
        '没有恢复：「夜曲」现在已经有歌词了',
      );
    });
  });
}
