import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/library_lyric_file_matcher.dart';

void main() {
  const matcher = LibraryLyricFileMatcher();

  LibraryLyricSong song(String path, String title, {String? artist}) {
    return LibraryLyricSong(audioPath: path, title: title, artist: artist);
  }

  Map<String, (String, LibraryLyricMatchReason)> pairs(
    List<LibraryLyricMatch> matches,
  ) {
    return {
      for (final match in matches)
        match.song.audioPath: (match.lyricPath, match.reason),
    };
  }

  test('a file beside the song with the same name is paired', () {
    final matches = matcher.match(
      songs: [song('/music/jay/夜曲.mp3', '夜曲')],
      lyricFiles: ['/music/jay/夜曲.lrc'],
    );

    expect(pairs(matches), {
      '/music/jay/夜曲.mp3': (
        '/music/jay/夜曲.lrc',
        LibraryLyricMatchReason.besideSong,
      ),
    });
  });

  test('a file anywhere in the library folder pairs by file name', () {
    final matches = matcher.match(
      songs: [song('/music/jay/track01.flac', '夜曲')],
      lyricFiles: ['/library/lyrics/Track01.LRC'],
    );

    expect(matches.single.lyricPath, '/library/lyrics/Track01.LRC');
    expect(matches.single.reason, LibraryLyricMatchReason.sameFileName);
  });

  test('an exported file named after the title pairs with that song', () {
    final matches = matcher.match(
      songs: [
        song('/music/01.mp3', '夜曲', artist: '周杰伦'),
        song('/music/02.mp3', '晴天', artist: '周杰伦'),
      ],
      lyricFiles: ['/library/晴天.lrc'],
    );

    expect(pairs(matches), {
      '/music/02.mp3': ('/library/晴天.lrc', LibraryLyricMatchReason.title),
    });
  });

  test('artist and title pair in either order and any dash spacing', () {
    final matches = matcher.match(
      songs: [
        song('/music/01.mp3', '夜曲', artist: '周杰伦'),
        song('/music/02.mp3', 'Yellow', artist: 'Coldplay'),
      ],
      lyricFiles: ['/library/周杰伦-夜曲.lrc', '/library/yellow  –  coldplay.lrc'],
    );

    expect(pairs(matches), {
      '/music/01.mp3': (
        '/library/周杰伦-夜曲.lrc',
        LibraryLyricMatchReason.artistAndTitle,
      ),
      '/music/02.mp3': (
        '/library/yellow  –  coldplay.lrc',
        LibraryLyricMatchReason.artistAndTitle,
      ),
    });
  });

  test('characters an export replaces with _ still match the title', () {
    final matches = matcher.match(
      songs: [song('/music/01.mp3', 'AC/DC: Live?')],
      lyricFiles: ['/library/AC_DC_ Live_.lrc'],
    );

    expect(matches.single.reason, LibraryLyricMatchReason.title);
  });

  test('two songs with the same title leave the file alone', () {
    final matches = matcher.match(
      songs: [
        song('/music/a/01.mp3', '海阔天空', artist: 'Beyond'),
        song('/music/b/07.mp3', '海阔天空', artist: '信乐团'),
      ],
      lyricFiles: ['/library/海阔天空.lrc'],
    );

    expect(matches, isEmpty);
  });

  test('a stronger match is not overruled by a weaker tie', () {
    final matches = matcher.match(
      songs: [
        song('/music/a/海阔天空.mp3', '海阔天空'),
        song('/music/b/07.mp3', '海阔天空'),
      ],
      lyricFiles: ['/music/a/海阔天空.lrc'],
    );

    expect(pairs(matches), {
      '/music/a/海阔天空.mp3': (
        '/music/a/海阔天空.lrc',
        LibraryLyricMatchReason.besideSong,
      ),
    });
  });

  test('two songs with the same file name in different folders tie', () {
    final matches = matcher.match(
      songs: [song('/music/a/01.mp3', 'A'), song('/music/b/01.mp3', 'B')],
      lyricFiles: ['/library/01.lrc', '/music/b/01.lrc'],
    );

    // Beside song b, its own file wins; the loose 01.lrc is ambiguous.
    expect(pairs(matches), {
      '/music/b/01.mp3': (
        '/music/b/01.lrc',
        LibraryLyricMatchReason.besideSong,
      ),
    });
  });

  test('a song with several files keeps the strongest, then LRC', () {
    final matches = matcher.match(
      songs: [song('/music/夜曲.mp3', '夜曲')],
      lyricFiles: [
        '/library/夜曲.srt',
        '/library/夜曲.lrc',
        '/music/夜曲.ass',
        '/music/夜曲.srt',
      ],
    );

    expect(matches.single.lyricPath, '/music/夜曲.ass');
    expect(matches.single.reason, LibraryLyricMatchReason.besideSong);

    final loose = matcher.match(
      songs: [song('/music/夜曲.mp3', '夜曲')],
      lyricFiles: ['/library/夜曲.srt', '/library/夜曲.lrc'],
    );
    expect(loose.single.lyricPath, '/library/夜曲.lrc');
  });

  test('Windows paths are compared by folder without case', () {
    final matches = matcher.match(
      songs: [song(r'D:\Music\Jay\夜曲.mp3', '夜曲')],
      lyricFiles: [r'd:\music\jay\夜曲.lrc'],
    );

    expect(matches.single.reason, LibraryLyricMatchReason.besideSong);
  });

  test('no songs or no files means no matches', () {
    expect(matcher.match(songs: const [], lyricFiles: ['/a.lrc']), isEmpty);
    expect(
      matcher.match(songs: [song('/a.mp3', 'A')], lyricFiles: const []),
      isEmpty,
    );
  });

  group('path helpers', () {
    test('stem, extension and folder for both separators', () {
      expect(LibraryLyricFileMatcher.fileStem('/a/b/夜曲.live.lrc'), '夜曲.live');
      expect(LibraryLyricFileMatcher.fileStem(r'C:\a\.hidden'), '.hidden');
      expect(LibraryLyricFileMatcher.fileExtension('/a/B.LRC'), 'lrc');
      expect(LibraryLyricFileMatcher.fileExtension('/a/noext'), '');
      expect(LibraryLyricFileMatcher.folderKey(r'C:\Music\x.mp3'), 'c:/music');
      expect(LibraryLyricFileMatcher.folderKey('x.mp3'), '');
    });

    test('name keys ignore case, spacing and unsafe characters', () {
      const key = LibraryLyricFileMatcher.nameKey;
      expect(key('  Hello   World '), 'hello world');
      expect(key('周杰伦 — 夜曲'), '周杰伦-夜曲');
      expect(key('a:b*c'), 'a b c');
    });
  });
}
