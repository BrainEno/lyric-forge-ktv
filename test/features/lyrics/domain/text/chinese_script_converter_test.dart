import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/text/chinese_script_converter.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/text/chinese_script_data.g.dart'
    as data;
import 'package:lyric_forge_ktv/features/lyrics/domain/text/chinese_script_tables.dart';

void main() {
  const converter = ChineseScriptConverter();

  group('tables', () {
    test('parse every bundled table without unpaired entries', () {
      final tables = ChineseScriptTables.instance;
      expect(tables.revision, data.chineseScriptDataRevision);
      expect(tables.simplifiedToTraditional.length, greaterThan(3000));
      expect(tables.traditionalToSimplified.length, greaterThan(3000));
      // The whole OpenCC phrase dictionaries are kept, including entries that
      // only steer segmentation.
      expect(tables.simplifiedToTraditionalPhrases.entries.length, 49277);
      expect(tables.traditionalToSimplifiedPhrases.entries.length, 498);
      expect(tables.taiwanVariants, isNotEmpty);
      expect(tables.hongKongVariants, isNotEmpty);
      expect(tables.simplifiedOnly, contains('爱'.runes.single));
      expect(tables.traditionalOnly, contains('愛'.runes.single));
    });

    test('bare phrase keys are rebuilt from the character table', () {
      final phrases = ChineseScriptTables.instance
          .simplifiedToTraditionalPhrases
          .entries;
      // Stored as `会了|`: converts like the characters, but still has to win
      // the match so 了如 → 瞭如 does not fire inside 学会了如何.
      expect(phrases['会了'], '會了');
      expect(phrases['了如'], '瞭如');
    });

    test('phrase entries reject malformed input', () {
      expect(
        () => ChinesePhraseTable.parse('=值|'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ChinesePhraseTable.parse('键=|'),
        throwsA(isA<FormatException>()),
      );
      final table = ChinesePhraseTable.parse(
        '后来=後來|头发|',
        characters: {'头'.runes.single: '頭'.runes.single},
      );
      expect(table.entries, {'后来': '後來', '头发': '頭发'});
      expect(table.maxKeyRunes, 2);
    });

    test('the comparison fold is idempotent for every mapped character', () {
      final fold = ChineseScriptTables.instance.comparisonFold;
      for (final entry in fold.entries) {
        expect(
          converter.foldRune(entry.value),
          entry.value,
          reason:
              '${String.fromCharCode(entry.key)} → '
              '${String.fromCharCode(entry.value)}',
        );
      }
    });
  });

  group('traditional to simplified', () {
    test('converts lyric lines including phrase overrides', () {
      expect(converter.toSimplified('頭髮飄在風裡'), '头发飘在风里');
      expect(converter.toSimplified('後來我總算學會了'), '后来我总算学会了');
      expect(converter.toSimplified('乾淨的天空'), '干净的天空');
      expect(converter.toSimplified('為什麼'), '为什么');
      expect(converter.toSimplified('你在哪裡'), '你在哪里');
    });

    test('maps Taiwan and Hong Kong forms back first', () {
      expect(converter.toSimplified('裏面的着急'), '里面的着急');
      expect(converter.toSimplified('麪條'), '面条');
    });

    test('leaves text without Han characters untouched', () {
      const text = 'Hello, world! 😀';
      expect(identical(converter.toSimplified(text), text), isTrue);
      expect(converter.toSimplified(''), '');
    });
  });

  group('simplified to traditional', () {
    test('uses the regional standard', () {
      expect(
        converter.toTraditional('一只猫在面包店', ChineseScriptTarget.traditionalTaiwan),
        '一隻貓在麵包店',
      );
      expect(
        converter.toTraditional(
          '一只猫在面包店',
          ChineseScriptTarget.traditionalHongKong,
        ),
        '一隻貓在麪包店',
      );
      expect(
        converter.toTraditional('这里', ChineseScriptTarget.traditionalTaiwan),
        '這裡',
      );
      expect(
        converter.toTraditional('这里', ChineseScriptTarget.traditionalHongKong),
        '這裏',
      );
      expect(
        converter.toTraditional('看着', ChineseScriptTarget.traditionalTaiwan),
        '看著',
      );
      expect(
        converter.toTraditional('看着', ChineseScriptTarget.traditionalHongKong),
        '看着',
      );
    });

    test('segmentation phrases keep running text correct', () {
      expect(
        converter.toTraditional(
          '后来我总算学会了如何去爱',
          ChineseScriptTarget.traditionalTaiwan,
        ),
        '後來我總算學會了如何去愛',
      );
      expect(
        converter.toTraditional('头发', ChineseScriptTarget.traditionalTaiwan),
        '頭髮',
      );
    });

    test('keeps non-BMP characters and emoji intact', () {
      // U+2003E is a simplified extension-B character with a traditional
      // form; surrounding emoji must survive the code point walk.
      expect(
        converter.toTraditional(
          '😀\u{2003E}爱😀',
          ChineseScriptTarget.traditionalTaiwan,
        ),
        '😀\u{2005E}愛😀',
      );
      expect(converter.toSimplified('😀\u{2005E}😀'), '😀\u{2003E}😀');
    });
  });

  group('convertLine', () {
    test('traditional lines only get regional adjustments', () {
      // 台 is valid traditional; the simplified chain would turn it into 臺.
      expect(
        converter.convertLine('台北裏面', ChineseScriptTarget.traditionalTaiwan),
        '台北裡面',
      );
      expect(
        converter.convertLine('裏面的着急', ChineseScriptTarget.traditionalTaiwan),
        '裡面的著急',
      );
    });

    test('simplified and neutral lines take the full chain', () {
      expect(
        converter.convertLine('你在哪里', ChineseScriptTarget.traditionalTaiwan),
        '你在哪裡',
      );
      expect(
        converter.convertLine('我愛你', ChineseScriptTarget.simplified),
        '我爱你',
      );
    });
  });

  group('comparison fold', () {
    test('folds traditional, regional and simplified forms together', () {
      String fold(String value) => converter.foldForComparison(value);
      expect(fold('為什麼'), fold('为什么'));
      expect(fold('看著'), fold('看着'));
      expect(fold('裡面'), fold('里面'));
      expect(fold('裏面'), fold('里面'));
      expect(fold('麪條'), fold('面条'));
      expect(fold('麵條'), fold('面条'));
      expect(fold('我愛你'), '我爱你');
    });

    test('never folds a simplified character through a regional table', () {
      // Hong Kong writes 幺 as 么; the simplified 么 of 什么 must stay.
      expect(converter.foldForComparison('什么'), '什么');
      expect(converter.foldForComparison('什麼'), '什么');
    });

    test('keeps Latin text and punctuation', () {
      expect(converter.foldForComparison('Love, 愛!'), 'Love, 爱!');
    });
  });

  group('profile', () {
    test('classifies lines by script-exclusive characters', () {
      expect(converter.profile('我爱你').kind, ChineseScriptKind.simplified);
      expect(converter.profile('我愛你').kind, ChineseScriptKind.traditional);
      expect(converter.profile('我在等你').kind, ChineseScriptKind.neutral);
      expect(converter.profile('我愛你也爱我').kind, ChineseScriptKind.mixed);
      expect(converter.profile('hello').kind, ChineseScriptKind.none);
    });

    test('flags kana and hangul so Japanese and Korean are left alone', () {
      final japanese = converter.profile('愛してる');
      expect(japanese.hasKanaOrHangul, isTrue);
      expect(japanese.hanCount, 1);
      expect(converter.profile('사랑해 愛').hasKanaOrHangul, isTrue);
      expect(converter.profile('我爱你').hasKanaOrHangul, isFalse);
    });
  });
}
