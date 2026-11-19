import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/app_theme.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/core/widgets/app_button_spinner.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/transport_bar.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

const _disabled = {WidgetState.disabled};

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// Colour the only spinner on screen is drawn in.
Color _spinnerColor(WidgetTester tester) {
  final spinner = tester.widget<CircularProgressIndicator>(
    find.byType(CircularProgressIndicator),
  );
  return spinner.color!;
}

/// Fill of the button around the spinner, over the page.
Color _fillAroundSpinner(WidgetTester tester) {
  final materials = find.ancestor(
    of: find.byType(AppButtonSpinner),
    matching: find.byType(Material),
  );
  final fill = tester.widget<Material>(materials.first).color;
  return Color.alphaBlend(fill ?? Colors.transparent, AppColors.bgBase);
}

void main() {
  group('play disc', () {
    final style = AppTheme.playDisc;

    test('white with a black icon while it can be pressed', () {
      expect(style.backgroundColor!.resolve({}), AppColors.pureWhite);
      expect(style.foregroundColor!.resolve({}), AppColors.pureBlack);
    });

    test('stays light under a black spinner while playback loads', () {
      final fill = style.backgroundColor!.resolve(_disabled)!;
      final icon = style.foregroundColor!.resolve(_disabled)!;
      expect(fill.a, 1, reason: 'a translucent disc shows the dark bar');
      expect(icon, AppColors.pureBlack);
      expect(_contrast(icon, fill), greaterThanOrEqualTo(7));
    });

    test('the loading disc still stands out from the player bar', () {
      final fill = style.backgroundColor!.resolve(_disabled)!;
      for (final bar in [AppColors.bgElevated, AppColors.bgSurface]) {
        expect(_contrast(fill, bar), greaterThanOrEqualTo(3));
      }
    });

    testWidgets('a busy transport draws a black spinner on a light disc', (
      tester,
    ) async {
      await _pump(
        tester,
        TransportBar(isPlaying: false, isBusy: true, onPlayPause: () {}),
      );

      final spinner = _spinnerColor(tester);
      final fill = _fillAroundSpinner(tester);
      expect(spinner, AppColors.pureBlack);
      expect(fill, AppColors.textSecondary);
      expect(_contrast(spinner, fill), greaterThanOrEqualTo(7));
    });

    testWidgets('an idle transport keeps the white disc', (tester) async {
      await _pump(tester, TransportBar(isPlaying: false, onPlayPause: () {}));

      final materials = find.ancestor(
        of: find.byIcon(Icons.play_arrow_rounded),
        matching: find.byType(Material),
      );
      final fill = tester.widget<Material>(materials.first).color;
      expect(fill, AppColors.pureWhite);
    });
  });

  group('busy accent disc', () {
    test('keeps the accent and black while disabled', () {
      final style = AppTheme.busyAccentDisc;
      final fill = style.backgroundColor!.resolve(_disabled)!;
      final icon = style.foregroundColor!.resolve(_disabled)!;
      expect(fill, AppColors.accent);
      expect(icon, AppColors.onAccent);
      expect(_contrast(icon, fill), greaterThanOrEqualTo(7));
    });

    testWidgets('a buffering filled icon button shows a black spinner', (
      tester,
    ) async {
      await _pump(
        tester,
        IconButton.filled(
          onPressed: null,
          style: AppTheme.busyAccentDisc,
          icon: const AppButtonSpinner(),
        ),
      );

      expect(_spinnerColor(tester), AppColors.onAccent);
      expect(_fillAroundSpinner(tester), AppColors.accent);
    });

    testWidgets('the enabled state is untouched', (tester) async {
      await _pump(
        tester,
        IconButton.filled(
          onPressed: () {},
          style: AppTheme.busyAccentDisc,
          icon: const Icon(Icons.play_arrow_rounded),
        ),
      );

      final materials = find.ancestor(
        of: find.byIcon(Icons.play_arrow_rounded),
        matching: find.byType(Material),
      );
      expect(tester.widget<Material>(materials.first).color, AppColors.accent);
    });
  });

  group('disabled filled and tonal buttons', () {
    test('resolve to grey on grey at 3:1 or more', () {
      final fill = AppTheme.disabledFill.resolve(_disabled)!;
      final label = AppTheme.disabledForeground.resolve(_disabled)!;
      expect(fill, AppColors.bgHighlight);
      expect(_contrast(label, fill), greaterThanOrEqualTo(3));
    });

    test('leave the enabled states to the colour scheme', () {
      for (final states in [
        <WidgetState>{},
        {WidgetState.hovered},
        {WidgetState.pressed},
      ]) {
        expect(AppTheme.disabledFill.resolve(states), isNull);
        expect(AppTheme.disabledForeground.resolve(states), isNull);
      }
    });

    test('the filled button theme uses them', () {
      final style = AppTheme.darkTheme.filledButtonTheme.style!;
      expect(style.backgroundColor, same(AppTheme.disabledFill));
      expect(style.foregroundColor, same(AppTheme.disabledForeground));
      expect(style.iconColor, same(AppTheme.disabledForeground));
    });

    testWidgets('a busy filled button shows its spinner at 3:1', (
      tester,
    ) async {
      await _pump(
        tester,
        FilledButton.icon(
          onPressed: null,
          icon: const AppButtonSpinner(),
          label: const Text('解析中…'),
        ),
      );

      final spinner = _spinnerColor(tester);
      final fill = _fillAroundSpinner(tester);
      expect(fill, AppColors.bgHighlight);
      expect(spinner, AppColors.textTertiary);
      expect(_contrast(spinner, fill), greaterThanOrEqualTo(3));
    });

    testWidgets('a busy tonal button matches', (tester) async {
      await _pump(
        tester,
        FilledButton.tonalIcon(
          onPressed: null,
          icon: const AppButtonSpinner(),
          label: const Text('连接中…'),
        ),
      );

      expect(_fillAroundSpinner(tester), AppColors.bgHighlight);
      expect(_spinnerColor(tester), AppColors.textTertiary);
    });

    testWidgets('an enabled filled button keeps the accent', (tester) async {
      await _pump(
        tester,
        FilledButton(onPressed: () {}, child: const Text('开始对齐')),
      );

      final materials = find.ancestor(
        of: find.text('开始对齐'),
        matching: find.byType(Material),
      );
      expect(tester.widget<Material>(materials.first).color, AppColors.accent);
    });
  });
}
