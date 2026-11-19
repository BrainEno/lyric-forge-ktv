import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/app_theme.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';

void main() {
  test('selected chips get the accent outline and tint', () {
    final chips = AppTheme.darkTheme.chipTheme;

    expect(chips.selectedColor, AppColors.accentMuted);
    expect(chips.checkmarkColor, AppColors.accent);
    expect(
      AppTheme.chipSide.resolve({WidgetState.selected}).color,
      AppColors.accent,
    );
    expect(AppTheme.chipSide.resolve({}).color, AppColors.borderSubtle);
    expect(chips.side, same(AppTheme.chipSide));
  });

  test('the selected tint keeps white labels readable', () {
    final tint = Color.alphaBlend(AppColors.accentMuted, AppColors.bgElevated);
    final white = AppColors.textPrimary.computeLuminance() + 0.05;
    final background = tint.computeLuminance() + 0.05;
    expect(white / background, greaterThan(7));
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
