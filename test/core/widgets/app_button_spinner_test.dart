import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/app_theme.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/core/widgets/app_button_spinner.dart';

Widget _button({required bool enabled}) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(
      body: Center(
        child: FilledButton.icon(
          onPressed: enabled ? () {} : null,
          icon: const AppButtonSpinner(),
          label: const Text('正在处理'),
        ),
      ),
    ),
  );
}

void main() {
  CircularProgressIndicator spinnerIn(WidgetTester tester) =>
      tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );

  testWidgets('takes the label colour of an enabled accent button', (
    tester,
  ) async {
    await tester.pumpWidget(_button(enabled: true));

    expect(spinnerIn(tester).color, AppColors.onAccent);
    expect(tester.getSize(find.byType(AppButtonSpinner)), const Size(18, 18));
  });

  testWidgets('dims with the label while the button is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(_button(enabled: false));

    // The theme's disabled grey, the same as the label, not white or the
    // accent.
    expect(spinnerIn(tester).color, AppColors.textTertiary);
  });

  testWidgets('falls back to the ambient icon colour outside buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: IconTheme(
          data: IconThemeData(color: AppColors.warning),
          child: Center(child: AppButtonSpinner(size: 24)),
        ),
      ),
    );

    expect(spinnerIn(tester).color, AppColors.warning);
    expect(tester.getSize(find.byType(AppButtonSpinner)), const Size(24, 24));
  });
}
