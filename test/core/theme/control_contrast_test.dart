import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/app_theme.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// What a translucent [color] looks like over the page.
Color _onPage(Color color) => Color.alphaBlend(color, AppColors.bgBase);

const _states = <String, Set<WidgetState>>{
  'idle': {},
  'hovered': {WidgetState.hovered},
  'focused': {WidgetState.focused},
  'pressed': {WidgetState.pressed},
};

/// Pumps [button] on the app theme.
Future<void> _pump(WidgetTester tester, Widget button) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(body: Center(child: button)),
    ),
  );
}

/// Colour the icon [icon] is drawn in.
Color _iconColor(WidgetTester tester, IconData icon) {
  final text = tester.widget<RichText>(
    find.descendant(of: find.byIcon(icon), matching: find.byType(RichText)),
  );
  return text.text.style!.color!;
}

/// Fill of the closest Material around [finder], over the page.
Color _fillAround(WidgetTester tester, Finder finder) {
  final material = tester.widget<Material>(
    find.ancestor(of: finder, matching: find.byType(Material)).first,
  );
  return _onPage(material.color ?? Colors.transparent);
}

void main() {
  final theme = AppTheme.darkTheme;
  final scheme = theme.colorScheme;

  group('colour roles', () {
    test('containers carry light lavender at AAA', () {
      expect(scheme.primaryContainer, AppColors.accentContainer);
      expect(scheme.secondaryContainer, AppColors.accentContainer);
      expect(scheme.onPrimaryContainer, AppColors.onAccentContainer);
      expect(scheme.onSecondaryContainer, AppColors.onAccentContainer);
      expect(
        _contrast(AppColors.onAccentContainer, AppColors.accentContainer),
        greaterThanOrEqualTo(7),
      );
    });

    test('the container is not a second accent fill', () {
      // Tonal buttons used to be the accent with a black label, which made
      // them look exactly like the primary button beside them.
      expect(AppColors.accentContainer, isNot(AppColors.accent));
      expect(
        _contrast(AppColors.accent, AppColors.accentContainer),
        greaterThanOrEqualTo(3),
      );
    });

    test('secondary text and icons are grey, readable on every surface', () {
      expect(scheme.onSurfaceVariant, AppColors.textSecondary);
      for (final surface in [
        AppColors.bgBase,
        AppColors.bgElevated,
        AppColors.bgSurface,
      ]) {
        expect(
          _contrast(scheme.onSurfaceVariant, surface),
          greaterThanOrEqualTo(4.5),
        );
      }
    });

    test('control outlines reach 3:1 without shouting', () {
      expect(scheme.outline, AppColors.borderStrong);
      for (final surface in [AppColors.bgBase, AppColors.bgElevated]) {
        expect(
          _contrast(AppColors.borderStrong, surface),
          greaterThanOrEqualTo(3),
        );
      }
      expect(scheme.outline, isNot(AppColors.textPrimary));
    });

    test('raised surfaces are not washed with lavender', () {
      expect(scheme.surfaceTint.a, 0);
    });
  });

  group('elevated buttons', () {
    test('every enabled state keeps black at AAA on its fill', () {
      for (final entry in _states.entries) {
        final fill = AppTheme.accentFill.resolve(entry.value);
        final label = AppTheme.accentForeground.resolve(entry.value);
        expect(
          _contrast(label, fill),
          greaterThanOrEqualTo(7),
          reason: entry.key,
        );
      }
    });

    test('hover lightens and press darkens the fill', () {
      expect(
        AppTheme.accentFill.resolve({WidgetState.hovered}),
        AppColors.accentHover,
      );
      expect(
        AppTheme.accentFill.resolve({WidgetState.pressed}),
        AppColors.accentPressed,
      );
    });

    test('a disabled button is grey on grey, not a dimmed accent', () {
      const disabled = {WidgetState.disabled};
      final fill = AppTheme.accentFill.resolve(disabled);
      final label = AppTheme.accentForeground.resolve(disabled);
      expect(fill, isNot(AppColors.accent));
      expect(_contrast(label, fill), greaterThanOrEqualTo(3));
    });

    test('the theme uses those states', () {
      final style = theme.elevatedButtonTheme.style!;
      // The getters build a fresh property for the palette in use each
      // time (D-042), so compare what they resolve to, state by state.
      for (final states in const <Set<WidgetState>>[
        {},
        {WidgetState.hovered},
        {WidgetState.focused},
        {WidgetState.pressed},
        {WidgetState.disabled},
      ]) {
        expect(
          style.backgroundColor!.resolve(states),
          AppTheme.accentFill.resolve(states),
        );
        expect(
          style.foregroundColor!.resolve(states),
          AppTheme.accentForeground.resolve(states),
        );
      }
    });
  });

  group('segmented buttons', () {
    final style = theme.segmentedButtonTheme.style!;

    test('the chosen segment is deep lavender with a light label', () {
      const selected = {WidgetState.selected};
      final fill = style.backgroundColor!.resolve(selected)!;
      final label = style.foregroundColor!.resolve(selected)!;
      expect(fill, AppColors.accentContainer);
      expect(_contrast(label, fill), greaterThanOrEqualTo(7));
    });

    test('the other segments stay readable on the page', () {
      final label = style.foregroundColor!.resolve({})!;
      expect(_contrast(label, AppColors.bgElevated), greaterThanOrEqualTo(4.5));
    });
  });

  group('selection controls', () {
    test('the switch thumb stands out from its track either way', () {
      final switches = theme.switchTheme;
      for (final states in [
        <WidgetState>{},
        {WidgetState.selected},
      ]) {
        final thumb = switches.thumbColor!.resolve(states)!;
        final track = switches.trackColor!.resolve(states)!;
        expect(_contrast(thumb, track), greaterThanOrEqualTo(3));
      }
    });

    test('a ticked checkbox draws black on the accent', () {
      final boxes = theme.checkboxTheme;
      const selected = {WidgetState.selected};
      final fill = boxes.fillColor!.resolve(selected)!;
      final check = boxes.checkColor!.resolve(selected)!;
      expect(fill, AppColors.accent);
      expect(_contrast(check, fill), greaterThanOrEqualTo(7));
    });

    test('an empty checkbox and radio are visible on the page', () {
      final side = theme.checkboxTheme.side! as WidgetStateBorderSide;
      final outline = WidgetStateProperty.resolveAs<BorderSide?>(side, {});
      expect(
        _contrast(outline!.color, AppColors.bgElevated),
        greaterThanOrEqualTo(3),
      );
      final radio = theme.radioTheme.fillColor!.resolve({})!;
      expect(_contrast(radio, AppColors.bgElevated), greaterThanOrEqualTo(3));
    });
  });

  group('icon buttons on lavender', () {
    testWidgets('a filled icon button draws a black icon', (tester) async {
      await _pump(
        tester,
        IconButton.filled(
          onPressed: () {},
          icon: const Icon(Icons.play_arrow_rounded),
        ),
      );

      final icon = _iconColor(tester, Icons.play_arrow_rounded);
      final fill = _fillAround(tester, find.byIcon(Icons.play_arrow_rounded));
      expect(fill, AppColors.accent);
      expect(icon, AppColors.onAccent);
      expect(_contrast(icon, fill), greaterThanOrEqualTo(7));
    });

    testWidgets('a tonal icon button draws light lavender on deep lavender', (
      tester,
    ) async {
      await _pump(
        tester,
        IconButton.filledTonal(
          onPressed: () {},
          icon: const Icon(Icons.history_rounded),
        ),
      );

      final icon = _iconColor(tester, Icons.history_rounded);
      final fill = _fillAround(tester, find.byIcon(Icons.history_rounded));
      expect(fill, AppColors.accentContainer);
      expect(_contrast(icon, fill), greaterThanOrEqualTo(7));
    });

    testWidgets('a plain icon button keeps the grey', (tester) async {
      await _pump(
        tester,
        IconButton(onPressed: () {}, icon: const Icon(Icons.edit_outlined)),
      );

      expect(_iconColor(tester, Icons.edit_outlined), AppColors.textSecondary);
    });

    testWidgets('a selected icon button turns the accent', (tester) async {
      await _pump(
        tester,
        IconButton(
          isSelected: true,
          onPressed: () {},
          icon: const Icon(Icons.favorite_border_rounded),
          selectedIcon: const Icon(Icons.favorite_rounded),
        ),
      );

      expect(_iconColor(tester, Icons.favorite_rounded), AppColors.accent);
    });
  });

  group('text buttons on lavender', () {
    testWidgets('a filled button has a black label and icon', (tester) async {
      await _pump(
        tester,
        FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('播放'),
        ),
      );

      final label = tester.widget<RichText>(
        find.descendant(of: find.text('播放'), matching: find.byType(RichText)),
      );
      final fill = _fillAround(tester, find.text('播放'));
      expect(fill, AppColors.accent);
      expect(label.text.style!.color, AppColors.onAccent);
      expect(_iconColor(tester, Icons.play_arrow_rounded), AppColors.onAccent);
    });

    testWidgets('a tonal button is light lavender on deep lavender', (
      tester,
    ) async {
      await _pump(
        tester,
        FilledButton.tonalIcon(
          onPressed: () {},
          icon: const Icon(Icons.lyrics_rounded),
          label: const Text('歌词'),
        ),
      );

      final label = tester.widget<RichText>(
        find.descendant(of: find.text('歌词'), matching: find.byType(RichText)),
      );
      final fill = _fillAround(tester, find.text('歌词'));
      expect(fill, AppColors.accentContainer);
      expect(
        _contrast(label.text.style!.color!, fill),
        greaterThanOrEqualTo(7),
      );
      expect(
        _iconColor(tester, Icons.lyrics_rounded),
        AppColors.onAccentContainer,
      );
    });

    testWidgets('a selected segment uses the container colours', (
      tester,
    ) async {
      await _pump(
        tester,
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('逐行')),
            ButtonSegment(value: 1, label: Text('逐字')),
          ],
          selected: const {0},
          onSelectionChanged: (_) {},
        ),
      );

      final chosen = tester.widget<RichText>(
        find.descendant(of: find.text('逐行'), matching: find.byType(RichText)),
      );
      final other = tester.widget<RichText>(
        find.descendant(of: find.text('逐字'), matching: find.byType(RichText)),
      );
      expect(chosen.text.style!.color, AppColors.onAccentContainer);
      expect(other.text.style!.color, AppColors.textSecondary);
    });
  });
}
