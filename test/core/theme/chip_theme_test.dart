import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/app_theme.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';

void main() {
  test('selected chips get the accent outline and tint', () {
    final chips = AppTheme.darkTheme.chipTheme;

    expect(chips.selectedColor, AppColors.accentContainer);
    expect(chips.checkmarkColor, AppColors.onAccentContainer);
    expect(
      AppTheme.chipSide.resolve({WidgetState.selected})?.color,
      AppColors.accent,
    );
    expect(AppTheme.chipSide.resolve({})?.color, AppColors.borderSubtle);
    final side = chips.side! as WidgetStateBorderSide;
    for (final states in const <Set<WidgetState>>[
      {},
      {WidgetState.selected},
    ]) {
      expect(side.resolve(states), AppTheme.chipSide.resolve(states));
    }
  });

  test('the selected fill keeps its label readable', () {
    final label = AppColors.onAccentContainer.computeLuminance() + 0.05;
    final fill = AppColors.accentContainer.computeLuminance() + 0.05;
    expect(label / fill, greaterThan(7));
  });

  testWidgets('a selected chip draws its label and icon in light lavender', (
    tester,
  ) async {
    // Both used to come out black: Material derives them from the secondary
    // container roles, which were unset and fell back to the black label of
    // the accent, 1.6:1 on the translucent selected tint.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Row(
            children: [
              ChoiceChip(
                selected: true,
                onSelected: (_) {},
                avatar: const Icon(Icons.favorite_rounded),
                label: const Text('收藏'),
              ),
              ChoiceChip(
                selected: false,
                onSelected: (_) {},
                avatar: const Icon(Icons.queue_music_outlined),
                label: const Text('歌单'),
              ),
            ],
          ),
        ),
      ),
    );

    Color? colourOf(Finder finder) => tester
        .widget<RichText>(
          find.descendant(of: finder, matching: find.byType(RichText)),
        )
        .text
        .style
        ?.color;

    expect(colourOf(find.text('收藏')), AppColors.onAccentContainer);
    expect(
      colourOf(find.byIcon(Icons.favorite_rounded)),
      AppColors.onAccentContainer,
    );
    expect(colourOf(find.text('歌单')), AppColors.textSecondary);
  });

  testWidgets('a selected ChoiceChip draws the accent outline', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Row(
            children: [
              ChoiceChip(
                selected: true,
                onSelected: (_) {},
                label: const Text('歌曲'),
              ),
              ChoiceChip(
                selected: false,
                onSelected: (_) {},
                label: const Text('艺人'),
              ),
            ],
          ),
        ),
      ),
    );

    BorderSide? outlineOf(String label) {
      final chip = find.ancestor(
        of: find.text(label),
        matching: find.byType(Material),
      );
      final material = tester.widget<Material>(chip.first);
      final shape = material.shape;
      return shape is OutlinedBorder ? shape.side : null;
    }

    expect(outlineOf('歌曲')?.color, AppColors.accent);
    expect(outlineOf('艺人')?.color, AppColors.borderSubtle);
  });
}
