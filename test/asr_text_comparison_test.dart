import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_text_comparison.dart';

void main() {
  const comparison = AsrTextComparison();

  group('AsrTextComparison', () {
    test('preserves Korean, Japanese, Greek, and Cyrillic text', () {
      for (final text in ['안녕하세요', 'こんにちは', 'γειά σου', 'привет']) {
        expect(comparison.normalize(text), isNotEmpty, reason: text);
        expect(comparison.similarity(text, text), 1, reason: text);
      }

      expect(comparison.similarity('안녕하세요', '안녕히 가세요'), lessThan(1));
      expect(comparison.similarity('γειά σου', 'γειά σας'), lessThan(1));
      expect(comparison.similarity('привет', 'пока'), lessThan(1));
    });

    test('folds precomposed and decomposed Latin diacritics', () {
      expect(comparison.normalize('Café olé'), 'cafeole');
      expect(comparison.normalize('Cafe\u0301 ole\u0301'), 'cafeole');
      expect(comparison.similarity('Café olé', 'Cafe ole'), 1);
      expect(comparison.similarity('Cafe\u0301 ole\u0301', 'Cafe ole'), 1);
      expect(comparison.similarity('Tiếng Việt', 'Tieng Viet'), 1);
    });

    test('empty normalized text is not evidence of agreement', () {
      expect(comparison.normalize('!? 🎵'), isEmpty);
      expect(comparison.similarity('', ''), 0);
      expect(comparison.similarity('!?', '...'), 0);
      expect(comparison.similarity('안녕', ''), 0);
    });
  });
}
