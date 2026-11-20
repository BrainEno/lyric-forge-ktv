import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/player_lyric_semantics.dart';

// The player's lyric lines as a screen reader reads them (audit A-04): the
// time and the text in one sentence, the chorus and the playing line said
// out loud, and the focus view's lines named by where they sit.

void main() {
  group('listRow', () {
    test('time and text', () {
      expect(
        PlayerLyricSemantics.listRow(time: '00:12', text: '月亮代表我的心'),
        '00:12，月亮代表我的心',
      );
    });

    test('a chorus line that is playing', () {
      expect(
        PlayerLyricSemantics.listRow(
          time: '01:05',
          text: '你问我爱你有多深',
          chorus: true,
          current: true,
        ),
        '01:05，你问我爱你有多深，副歌，正在播放',
      );
    });

    test('the text is trimmed and a blank line is named', () {
      expect(
        PlayerLyricSemantics.listRow(time: '00:00', text: '  前奏  '),
        '00:00，前奏',
      );
      expect(
        PlayerLyricSemantics.listRow(time: '00:30', text: '   '),
        '00:30，${PlayerLyricSemantics.emptyLineLabel}',
      );
    });
  });

  group('focusLine', () {
    test('each line says where it sits', () {
      expect(
        PlayerLyricSemantics.focusLine(PlayerFocusLyricRole.previous, '甲'),
        '上一句：甲',
      );
      expect(
        PlayerLyricSemantics.focusLine(PlayerFocusLyricRole.current, '乙'),
        '当前句：乙',
      );
      expect(
        PlayerLyricSemantics.focusLine(PlayerFocusLyricRole.next, '丙'),
        '下一句：丙',
      );
    });

    test('every role has its own word', () {
      final words = PlayerFocusLyricRole.values
          .map(PlayerLyricSemantics.roleLabel)
          .toSet();
      expect(words, hasLength(PlayerFocusLyricRole.values.length));
    });

    test('a blank line is named', () {
      expect(
        PlayerLyricSemantics.focusLine(PlayerFocusLyricRole.next, ''),
        '下一句：${PlayerLyricSemantics.emptyLineLabel}',
      );
    });
  });
}
