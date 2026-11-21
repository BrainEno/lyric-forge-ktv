import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The fonts of the interface: the platform's UI font for Latin text and
/// one Simplified Chinese UI font for every Chinese character.
///
/// The app named no font at all, so each Chinese character went to the
/// system's own fallback on its own. On Windows set to Traditional Chinese
/// (zh-TW) or Japanese that fallback takes a character such as 音, 校 or 工
/// from Microsoft JhengHei or Yu Gothic, which have it, but 乐, 库 and 对,
/// which only Simplified Chinese fonts have, from Microsoft YaHei. One label
/// then mixed two typefaces of different weight and shape (“音乐库” read
/// as a bold 音 beside a thin 乐库). Listing a Simplified Chinese font first
/// gives every character of a label the same typeface.
abstract final class AppTypography {
  /// Simplified Chinese UI fonts of [platform], in order of preference.
  /// Fonts that are not installed are skipped by the engine.
  static List<String> chineseFontsFor(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.windows => const [
        'Microsoft YaHei UI',
        'Microsoft YaHei',
        'DengXian',
        'SimHei',
      ],
      TargetPlatform.macOS || TargetPlatform.iOS => const [
        'PingFang SC',
        'Hiragino Sans GB',
        'Heiti SC',
      ],
      TargetPlatform.android ||
      TargetPlatform.linux ||
      TargetPlatform.fuchsia => const [
        'Noto Sans CJK SC',
        'Noto Sans SC',
        'Source Han Sans SC',
        'WenQuanYi Micro Hei',
      ],
    };
  }

  /// The platform's UI font as Flutter's typography names it (Segoe UI on
  /// Windows), so Latin text looks as it did before.
  static String? familyFor(TargetPlatform platform) =>
      _platformBody(platform).fontFamily;

  /// The Chinese fonts first, then whatever the platform typography already
  /// falls back to (Linux lists Ubuntu, Cantarell and others).
  static List<String> fallbackFor(TargetPlatform platform) {
    final chinese = chineseFontsFor(platform);
    return [
      ...chinese,
      for (final family
          in _platformBody(platform).fontFamilyFallback ?? const <String>[])
        if (!chinese.contains(family)) family,
    ];
  }

  /// [familyFor] of the platform the app runs on.
  static String? get family => familyFor(defaultTargetPlatform);

  /// [fallbackFor] of the platform the app runs on.
  static List<String> get fallback => fallbackFor(defaultTargetPlatform);

  /// [style] with the interface fonts.
  static TextStyle apply(TextStyle style) =>
      style.copyWith(fontFamily: family, fontFamilyFallback: fallback);

  /// [theme] with the interface fonts.
  static TextTheme applyToTheme(TextTheme theme) =>
      theme.apply(fontFamily: family, fontFamilyFallback: fallback);

  static TextStyle _platformBody(TargetPlatform platform) =>
      Typography.material2021(platform: platform).black.bodyMedium ??
      const TextStyle();
}
