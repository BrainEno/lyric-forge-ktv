import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/app_theme.dart';

/// UI audit E-06: captions and badges were drawn at 10 logical pixels. Pages
/// take their small text from the theme (the source hygiene test rejects
/// literal font sizes), so the floor only has to hold here.
void main() {
  final text = AppTheme.darkTheme.textTheme;
  final styles = <String, TextStyle?>{
    'displayLarge': text.displayLarge,
    'displayMedium': text.displayMedium,
    'displaySmall': text.displaySmall,
    'headlineLarge': text.headlineLarge,
    'headlineMedium': text.headlineMedium,
    'headlineSmall': text.headlineSmall,
    'titleLarge': text.titleLarge,
    'titleMedium': text.titleMedium,
    'titleSmall': text.titleSmall,
    'bodyLarge': text.bodyLarge,
    'bodyMedium': text.bodyMedium,
    'bodySmall': text.bodySmall,
    'labelLarge': text.labelLarge,
    'labelMedium': text.labelMedium,
    'labelSmall': text.labelSmall,
  };

  test('every theme text style is at least 11 logical pixels', () {
    for (final entry in styles.entries) {
      final size = entry.value?.fontSize;
      expect(size, isNotNull, reason: entry.key);
      expect(size!, greaterThanOrEqualTo(11), reason: entry.key);
    }
  });

  test('the smallest label is 11 and stays the smallest style', () {
    final smallest = styles.values
        .map((style) => style!.fontSize!)
        .reduce((a, b) => a < b ? a : b);
    expect(text.labelSmall!.fontSize, 11);
    expect(smallest, text.labelSmall!.fontSize);
  });
}
