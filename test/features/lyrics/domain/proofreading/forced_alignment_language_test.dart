import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/forced_alignment_language.dart';

void main() {
  group('ForcedAlignmentLanguage.resolve', () {
    test('accepts the names users type in Chinese', () {
      expect(ForcedAlignmentLanguage.resolve('中文'), 'Chinese');
      expect(ForcedAlignmentLanguage.resolve('汉语'), 'Chinese');
      expect(ForcedAlignmentLanguage.resolve('日文'), 'Japanese');
      expect(ForcedAlignmentLanguage.resolve('英文'), 'English');
    });

    test('accepts English names and BCP-47 tags', () {
      expect(ForcedAlignmentLanguage.resolve('Chinese'), 'Chinese');
      expect(ForcedAlignmentLanguage.resolve('japanese'), 'Japanese');
      expect(ForcedAlignmentLanguage.resolve('English'), 'English');
      expect(ForcedAlignmentLanguage.resolve('zh'), 'Chinese');
      expect(ForcedAlignmentLanguage.resolve('zh-Hant'), 'Chinese');
      expect(ForcedAlignmentLanguage.resolve('ja-JP'), 'Japanese');
      expect(ForcedAlignmentLanguage.resolve('en-US'), 'English');
    });

    test('ignores surrounding whitespace and casing', () {
      expect(ForcedAlignmentLanguage.resolve('  ZH-hans '), 'Chinese');
      expect(ForcedAlignmentLanguage.resolve(' Japanese '), 'Japanese');
    });

    test('rejects a language the aligner does not support', () {
      expect(
        () => ForcedAlignmentLanguage.resolve('klingon'),
        throwsA(
          isA<ForcedAlignmentLanguageResolutionException>().having(
            (error) => error.language,
            'language',
            'klingon',
          ),
        ),
      );
      expect(
        () => ForcedAlignmentLanguage.resolve(''),
        throwsA(
          isA<ForcedAlignmentLanguageResolutionException>().having(
            (error) => error.language,
            'language',
            '',
          ),
        ),
      );
    });
  });
}
