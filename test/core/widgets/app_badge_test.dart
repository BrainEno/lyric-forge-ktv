import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/app_theme.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/core/widgets/app_badge.dart';

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

BoxDecoration _decoration(WidgetTester tester) {
  final finder = find.descendant(
    of: find.byType(AppBadge),
    matching: find.byType(Container),
  );
  final container = tester.widget<Container>(finder);
  return container.decoration! as BoxDecoration;
}

void main() {
  testWidgets('neutral badges use the translucent wash', (tester) async {
    await tester.pumpWidget(_host(const AppBadge(label: 'FLAC')));

    expect(_decoration(tester).color, AppColors.hoverOverlay);
    final text = tester.widget<Text>(find.text('FLAC'));
    expect(text.style?.color, AppColors.textSecondary);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('tones tint the background and colour the text', (tester) async {
    await tester.pumpWidget(
      _host(
        const AppBadge(
          label: '需确认',
          icon: Icons.warning_amber_rounded,
          tone: AppBadgeTone.warning,
        ),
      ),
    );

    expect(
      _decoration(tester).color,
      AppColors.warning.withAlpha(AppBadge.tintAlpha),
    );
    final text = tester.widget<Text>(find.textContaining('需确认'));
    expect(text.style?.color, AppColors.warning);
    final icon = tester.widget<Icon>(find.byIcon(Icons.warning_amber_rounded));
    expect(icon.color, AppColors.warning);
    expect(icon.size, 14);
  });

  testWidgets('an explicit colour overrides the tone', (tester) async {
    await tester.pumpWidget(
      _host(
        const AppBadge(
          label: '已复核',
          tone: AppBadgeTone.accent,
          color: AppColors.textTertiary,
        ),
      ),
    );

    expect(
      _decoration(tester).color,
      AppColors.textTertiary.withAlpha(AppBadge.tintAlpha),
    );
    expect(
      tester.widget<Text>(find.text('已复核')).style?.color,
      AppColors.textTertiary,
    );
  });

  testWidgets('small badges keep a readable label and use a smaller icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(
          body: Center(
            child: AppBadge(
              label: '副歌',
              icon: Icons.star_rounded,
              size: AppBadgeSize.small,
              emphasized: true,
            ),
          ),
        ),
      ),
    );

    final style = tester.widget<Text>(find.textContaining('副歌')).style;
    // 10 was too small to read (UI audit E-06); the theme's smallest label
    // is the floor.
    expect(style?.fontSize, 11);
    expect(style?.fontWeight, FontWeight.w700);
    expect(tester.widget<Icon>(find.byIcon(Icons.star_rounded)).size, 12);
  });

  test('every tone except neutral has a colour', () {
    for (final tone in AppBadgeTone.values) {
      final color = AppBadge.toneColor(tone);
      if (tone == AppBadgeTone.neutral) {
        expect(color, isNull);
      } else {
        expect(color, isNotNull, reason: tone.name);
      }
    }
  });

  testWidgets('long labels stay on one line inside a narrow parent', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 120,
          child: Row(
            children: [
              Flexible(
                child: AppBadge(
                  label: '很长的标签文字' * 6,
                  icon: Icons.folder_rounded,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(find.textContaining('很长的标签文字'));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.getSize(find.byType(AppBadge)).width, lessThanOrEqualTo(120));
  });

  testWidgets('icon badges lay out directly inside a row', (tester) async {
    await tester.pumpWidget(
      _host(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('第一首'),
            AppBadge(label: '当前', icon: Icons.graphic_eq_rounded),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    expect(find.textContaining('当前'), findsOneWidget);
  });
}
