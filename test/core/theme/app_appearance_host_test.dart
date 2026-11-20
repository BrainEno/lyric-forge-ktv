import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/app_appearance.dart';
import 'package:lyric_forge_ktv/core/theme/app_appearance_host.dart';
import 'package:lyric_forge_ktv/core/theme/app_palette.dart';
import 'package:lyric_forge_ktv/core/theme/app_theme.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';

/// A constant widget that paints with AppColors and never looks the theme
/// up: the kind of widget a theme change used to leave untouched.
class _Swatch extends StatelessWidget {
  const _Swatch();

  static const Key boxKey = ValueKey('swatch');

  @override
  Widget build(BuildContext context) {
    return Container(
      key: boxKey,
      width: 10,
      height: 10,
      color: AppColors.bgBase,
    );
  }
}

/// Counts taps in its state, to prove a theme change keeps state.
class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => setState(() => taps++),
      child: Text('taps $taps', style: TextStyle(color: AppColors.textPrimary)),
    );
  }
}

Color _swatchColor(WidgetTester tester) {
  final box = tester.widget<Container>(find.byKey(_Swatch.boxKey));
  return box.color!;
}

Color? _textColor(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  late AppAppearanceController controller;

  setUp(() {
    controller = AppAppearanceController(store: MemoryAppearanceStore());
  });

  tearDown(() => AppColors.usePalette(AppPalette.dark));

  Widget app({AppAppearanceController? using, Widget? home}) {
    return AppAppearanceHost(
      controller: using ?? controller,
      builder: (context, variant) => MaterialApp(
        theme: AppTheme.themeFor(variant.palette),
        themeAnimationDuration: Duration.zero,
        home: Scaffold(
          body: home ?? const Column(children: [_Swatch(), _Counter()]),
        ),
      ),
    );
  }

  testWidgets('applies the controller theme when it is built', (tester) async {
    final light = AppAppearanceController(
      store: MemoryAppearanceStore(),
      initial: AppThemeVariant.light,
    );
    await tester.pumpWidget(app(using: light));

    expect(AppColors.palette, same(AppPalette.light));
    expect(_swatchColor(tester), AppPalette.light.bgBase);
    final context = tester.element(find.byType(_Swatch));
    expect(Theme.of(context).brightness, Brightness.light);
  });

  testWidgets('repaints constant widgets when the theme changes', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    expect(_swatchColor(tester), AppPalette.dark.bgBase);

    await controller.select(AppThemeVariant.light);
    await tester.pump();

    expect(_swatchColor(tester), AppPalette.light.bgBase);
    expect(_textColor(tester, 'taps 0'), AppPalette.light.textPrimary);
    final context = tester.element(find.byType(_Swatch));
    expect(Theme.of(context).colorScheme.primary, AppPalette.light.accent);
  });

  testWidgets('keeps widget state across a theme change', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('taps 0'));
    await tester.pump();
    await tester.tap(find.text('taps 1'));
    await tester.pump();

    await controller.select(AppThemeVariant.light);
    await tester.pump();

    expect(find.text('taps 2'), findsOneWidget);
    expect(_textColor(tester, 'taps 2'), AppPalette.light.textPrimary);
  });

  testWidgets('keeps the route stack across a theme change', (tester) async {
    await tester.pumpWidget(
      app(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: _Swatch()),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(_swatchColor(tester), AppPalette.dark.bgBase);

    await controller.select(AppThemeVariant.light);
    await tester.pump();

    // Still on the pushed page, now in the light colours.
    expect(find.byType(_Swatch), findsOneWidget);
    expect(_swatchColor(tester), AppPalette.light.bgBase);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(navigator.canPop(), isTrue);
  });

  testWidgets('switches back to dark', (tester) async {
    await tester.pumpWidget(app());
    await controller.select(AppThemeVariant.light);
    await tester.pump();
    await controller.select(AppThemeVariant.dark);
    await tester.pump();

    expect(AppColors.palette, same(AppPalette.dark));
    expect(_swatchColor(tester), AppPalette.dark.bgBase);
  });

  testWidgets('a restored theme takes effect once read', (tester) async {
    final restoring = AppAppearanceController(
      store: MemoryAppearanceStore(AppThemeVariant.light),
    );
    await tester.pumpWidget(app(using: restoring));
    expect(_swatchColor(tester), AppPalette.dark.bgBase);

    await restoring.restore();
    await tester.pump();

    expect(_swatchColor(tester), AppPalette.light.bgBase);
  });

  testWidgets('hands the controller down through the scope', (tester) async {
    await tester.pumpWidget(app());
    final context = tester.element(find.byType(_Swatch));
    expect(AppAppearanceScope.maybeOf(context), same(controller));
  });

  testWidgets('the scope is absent without a host', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Swatch()));
    final context = tester.element(find.byType(_Swatch));
    expect(AppAppearanceScope.maybeOf(context), isNull);
  });

  testWidgets('follows a new controller handed to it', (tester) async {
    await tester.pumpWidget(app());
    final light = AppAppearanceController(
      store: MemoryAppearanceStore(),
      initial: AppThemeVariant.light,
    );

    await tester.pumpWidget(app(using: light));
    expect(AppColors.palette, same(AppPalette.light));
    expect(_swatchColor(tester), AppPalette.light.bgBase);

    // The old controller no longer drives the app.
    await controller.select(AppThemeVariant.dark);
    await tester.pump();
    expect(AppColors.palette, same(AppPalette.light));

    await light.select(AppThemeVariant.dark);
    await tester.pump();
    expect(_swatchColor(tester), AppPalette.dark.bgBase);
  });

  testWidgets('stops listening once removed', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpWidget(const SizedBox.shrink());

    await controller.select(AppThemeVariant.light);
    await tester.pump();

    expect(AppColors.palette, same(AppPalette.dark));
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting the theme in use rebuilds nothing', (tester) async {
    var builds = 0;
    await tester.pumpWidget(
      AppAppearanceHost(
        controller: controller,
        builder: (context, variant) {
          builds++;
          return const SizedBox.shrink();
        },
      ),
    );
    expect(builds, 1);

    await controller.select(AppThemeVariant.dark);
    await tester.pump();

    expect(builds, 1);
  });
}
