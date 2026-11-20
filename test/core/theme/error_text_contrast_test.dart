import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/app_theme.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/playback_error_banner.dart';
import 'package:lyric_forge_ktv/features/transcription/presentation/widgets/asr_install_error_card.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

double _hueDistance(Color a, Color b) {
  final difference = (HSLColor.fromColor(a).hue - HSLColor.fromColor(b).hue)
      .abs();
  return difference > 180 ? 360 - difference : difference;
}

Map<String, Color> get _surfaces => {
  'bgBase': AppColors.bgBase,
  'bgElevated': AppColors.bgElevated,
  'bgSurface': AppColors.bgSurface,
  'bgHighlight': AppColors.bgHighlight,
};

/// The red tints the error banners and cards lay over their page.
const _bannerTints = [14, 16, 18, 20];

void main() {
  group('error text contrast', () {
    for (final entry in _surfaces.entries) {
      test('errorText reaches AA on ${entry.key}', () {
        expect(
          _contrast(AppColors.errorText, entry.value),
          greaterThanOrEqualTo(4.5),
        );
      });
    }

    test('the fill red is below AA as text', () {
      expect(_contrast(AppColors.error, AppColors.bgBase), lessThan(4.5));
      expect(_contrast(AppColors.error, AppColors.bgSurface), lessThan(4.5));
    });

    test('errorText stays readable inside every red-tinted banner', () {
      for (final page in [AppColors.bgBase, AppColors.bgElevated]) {
        for (final alpha in _bannerTints) {
          final banner = Color.alphaBlend(
            AppColors.error.withAlpha(alpha),
            page,
          );
          expect(
            _contrast(AppColors.errorText, banner),
            greaterThanOrEqualTo(4.5),
            reason: 'alpha $alpha over $page',
          );
        }
      }
    });

    test('errorText reaches AAA on the pages most errors sit on', () {
      expect(
        _contrast(AppColors.errorText, AppColors.bgBase),
        greaterThanOrEqualTo(7),
      );
      expect(
        _contrast(AppColors.errorText, AppColors.bgElevated),
        greaterThanOrEqualTo(7),
      );
    });

    test('labels on the error fill keep their contrast', () {
      expect(
        _contrast(AppColors.onError, AppColors.error),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('errorText still reads as an error', () {
    test('same hue family as the error fill', () {
      expect(
        _hueDistance(AppColors.errorText, AppColors.error),
        lessThanOrEqualTo(15),
      );
    });

    test('far from the lavender accent and the success green', () {
      expect(
        _hueDistance(AppColors.errorText, AppColors.accent),
        greaterThanOrEqualTo(40),
      );
      expect(
        _hueDistance(AppColors.errorText, AppColors.success),
        greaterThanOrEqualTo(90),
      );
    });

    test('saturated enough not to pass for a grey', () {
      expect(
        HSLColor.fromColor(AppColors.errorText).saturation,
        greaterThanOrEqualTo(0.8),
      );
    });

    test('distinct from the brand red, which is reserved for the mark', () {
      expect(AppColors.errorText, isNot(AppColors.brand));
      expect(AppColors.errorText, isNot(AppColors.error));
    });
  });

  group('theme', () {
    test('field error text uses errorText', () {
      final theme = AppTheme.darkTheme;
      expect(theme.inputDecorationTheme.errorStyle?.color, AppColors.errorText);
    });

    test('the colour scheme keeps the fill red for borders and badges', () {
      expect(AppTheme.darkTheme.colorScheme.error, AppColors.error);
    });

    testWidgets('a TextField error is drawn in errorText', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: TextField(decoration: InputDecoration(errorText: '路径无效')),
          ),
        ),
      );

      final error = tester.widget<Text>(find.text('路径无效'));
      expect(error.style?.color, AppColors.errorText);
    });
  });

  group('error surfaces', () {
    Widget host(Widget child) => MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(body: child),
    );

    testWidgets('PlaybackErrorBanner writes its message in errorText', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const PlaybackErrorBanner(message: '无法播放：文件不存在')),
      );

      final text = tester.widget<Text>(find.text('无法播放：文件不存在'));
      expect(text.style?.color, AppColors.errorText);
    });

    testWidgets('AsrInstallErrorCard title and icon use errorText', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const AsrInstallErrorCard(message: 'download failed')),
      );

      final title = tester.widget<Text>(find.text('暂时无法完成准备'));
      expect(title.style?.color, AppColors.errorText);
      final icon = tester.widget<Icon>(
        find.byIcon(Icons.error_outline_rounded),
      );
      expect(icon.color, AppColors.errorText);
    });
  });

  group('sources', () {
    final foreground = RegExp(r'(?<![A-Za-z])color: AppColors\.error(?=[,)])');

    /// Places where `color: AppColors.error` styles something other than
    /// text: a tinted container whose label stays white.
    const allowed = {'asr_end_to_end_smoke_test_card.dart'};

    test('feature code no longer writes text in the fill red', () {
      final offenders = <String>[];
      final files = Directory('lib/features')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      for (final file in files) {
        final path = file.path.replaceAll(r'\', '/');
        if (allowed.any(path.endsWith)) continue;
        final lines = file.readAsLinesSync();
        for (var index = 0; index < lines.length; index++) {
          if (foreground.hasMatch(lines[index])) {
            offenders.add('$path:${index + 1}');
          }
        }
      }
      expect(offenders, isEmpty);
    });

    test('destructive text buttons use errorText', () {
      final files = Directory('lib/features')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      for (final file in files) {
        expect(
          file.readAsStringSync(),
          isNot(contains('foregroundColor: AppColors.error,')),
          reason: file.path,
        );
      }
    });
  });
}
