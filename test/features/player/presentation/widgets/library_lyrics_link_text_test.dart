import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/library_lyric_file_matcher.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/library_lyrics_auto_linker.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/library_lyrics_link_text.dart';

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
}
