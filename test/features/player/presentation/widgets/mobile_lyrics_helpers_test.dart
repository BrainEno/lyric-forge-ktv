import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/playback_session_service.dart';
import 'package:lyric_forge_ktv/features/player/presentation/screens/listen_home_screen.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/local_song_lyrics_import_action.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/lyric_file_picker.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/reference_lyrics_view.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  group('importedLyricFileMessage (D-058)', () {
    test('a phone is not told to time or proofread in an editor', () {
      final untimed = importedLyricFileMessage(
        timed: false,
        wordTimedRows: 0,
        workbench: false,
      );
      expect(untimed, contains('静态显示'));
      expect(untimed, isNot(contains('打轴')));
      expect(
        importedLyricFileMessage(
          timed: true,
          wordTimedRows: 3,
          workbench: false,
        ),
        '歌词已导入（3 行带逐字时间），可直接播放',
      );
      expect(
        importedLyricFileMessage(timed: true, wordTimedRows: 0, workbench: false),
        isNot(contains('校对')),
      );
    });

    test('the desktop keeps its words', () {
      expect(
        importedLyricFileMessage(timed: false, wordTimedRows: 0, workbench: true),
        '文本歌词已作为参考歌词导入：播放时静态显示，需要同步时再去打轴',
      );
      expect(
        importedLyricFileMessage(timed: true, wordTimedRows: 0, workbench: true),
        '歌词已导入，可直接校对或播放',
      );
    });
  });

  group('isSupportedLyricFile', () {
    const extensions = {'lrc', 'txt', 'srt'};

    test('checks the extension, ignoring case', () {
      expect(isSupportedLyricFile('/a/晴天.LRC', extensions), isTrue);
      expect(isSupportedLyricFile(r'C:\a\晴天.txt', extensions), isTrue);
      expect(isSupportedLyricFile('/a/晴天.mp3', extensions), isFalse);
      expect(isSupportedLyricFile('/a/lrc', extensions), isFalse);
      expect(isSupportedLyricFile('/a/.lrc', extensions), isFalse);
      expect(isSupportedLyricFile('/a/晴天.', extensions), isFalse);
    });
  });

  group('ListenHomeScreen.hasCover', () {
    PlaybackItem item({String? artwork, String? thumbnail}) => PlaybackItem(
      id: 'local:/m/a.mp3',
      title: '晴天',
      artworkPath: artwork,
      audioAsset: AudioAsset(
        originalPath: '/m/a.mp3',
        format: 'mp3',
        thumbnailPath: thumbnail,
      ),
    );

    test('only a real cover is blurred behind the hero', () {
      expect(ListenHomeScreen.hasCover(item()), isFalse);
      expect(ListenHomeScreen.hasCover(item(artwork: '  ')), isFalse);
      expect(ListenHomeScreen.hasCover(item(artwork: '/c.jpg')), isTrue);
      expect(ListenHomeScreen.hasCover(item(thumbnail: '/t.jpg')), isTrue);
    });
  });

  group('ReferenceLyricsView without an editor', () {
    testWidgets('does not promise timing a phone cannot do', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReferenceLyricsView(
              lines: [
                LyricLine(
                  text: '故事的小黄花',
                  startTime: Duration.zero,
                  endTime: Duration.zero,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.textContaining('打轴'), findsNothing);
      expect(find.textContaining('请手动滚动查看'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('reference-lyrics-open-editor')),
        findsNothing,
      );
    });
  });
}
