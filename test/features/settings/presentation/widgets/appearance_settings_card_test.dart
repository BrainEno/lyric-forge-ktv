import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/app_appearance.dart';
import 'package:lyric_forge_ktv/core/theme/app_appearance_host.dart';
import 'package:lyric_forge_ktv/core/theme/app_palette.dart';
import 'package:lyric_forge_ktv/core/theme/app_theme.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/features/settings/presentation/widgets/appearance_settings_card.dart';

class _FailingStore implements AppearanceStore {
  bool fail = true;

  @override
  Future<AppThemeVariant?> load() async => null;

  @override
  Future<void> save(AppThemeVariant variant) async {
    if (fail) throw const FileSystemException('read-only');
  }
}

/// The colours painted inside the preview of [variant].
Set<Color> _previewColors(WidgetTester tester, AppThemeVariant variant) {
  final preview = find.descendant(
    of: find.byKey(AppearanceSettingsCard.tileKey(variant)),
    matching: find.byType(AppThemePreview),
  );
  final colors = <Color>{};
  for (final element in find
      .descendant(of: preview, matching: find.byType(Container))
      .evaluate()) {
    final container = element.widget as Container;
    final decoration = container.decoration;
    if (decoration is BoxDecoration && decoration.color != null) {
      colors.add(decoration.color!);
    }
    if (container.color != null) colors.add(container.color!);
  }
  final box = tester.widget<DecoratedBox>(
    find.descendant(of: preview, matching: find.byType(DecoratedBox)).first,
  );
  colors.add((box.decoration as BoxDecoration).color!);
  return colors;
}

void main() {
  late AppAppearanceController controller;
  late MemoryAppearanceStore store;

  setUp(() {
    store = MemoryAppearanceStore();
    controller = AppAppearanceController(store: store);
  });

  tearDown(() => AppColors.usePalette(AppPalette.dark));

  Future<void> pumpCard(
    WidgetTester tester, {
    double width = 600,
    AppAppearanceController? using,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final appearance = using ?? controller;
    await tester.pumpWidget(
      AppAppearanceHost(
        controller: appearance,
        builder: (context, variant) => MaterialApp(
          theme: AppTheme.themeFor(variant.palette),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: AppearanceSettingsCard(controller: appearance),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers one tile per theme', (tester) async {
    await pumpCard(tester);

    for (final variant in AppThemeVariant.values) {
      final tile = find.byKey(AppearanceSettingsCard.tileKey(variant));
      expect(tile, findsOneWidget);
      expect(
        find.descendant(of: tile, matching: find.text(variant.label)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile, matching: find.text(variant.description)),
        findsOneWidget,
      );
    }
  });

  testWidgets('checks the theme in use only', (tester) async {
    await pumpCard(tester);

    final check = find.byKey(const ValueKey('appearance-theme-check'));
    expect(check, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(AppearanceSettingsCard.tileKey(AppThemeVariant.dark)),
        matching: check,
      ),
      findsOneWidget,
    );
  });

  testWidgets('each preview paints its own palette, whatever is in use', (
    tester,
  ) async {
    await pumpCard(tester);

    final dark = _previewColors(tester, AppThemeVariant.dark);
    final light = _previewColors(tester, AppThemeVariant.light);
    for (final colors in [
      (dark, AppPalette.dark),
      (light, AppPalette.light),
    ]) {
      final palette = colors.$2;
      expect(
        colors.$1,
        containsAll([
          palette.bgBase,
          palette.bgElevated,
          palette.accent,
          palette.accentContainer,
          palette.textPrimary,
          palette.vinylBrass,
        ]),
      );
    }
    expect(light, isNot(contains(AppPalette.dark.bgBase)));
  });

  testWidgets('tapping a tile switches the theme and saves it', (
    tester,
  ) async {
    await pumpCard(tester);

    await tester.tap(
      find.byKey(AppearanceSettingsCard.tileKey(AppThemeVariant.light)),
    );
    await tester.pumpAndSettle();

    expect(controller.variant, AppThemeVariant.light);
    expect(store.saved, AppThemeVariant.light);
    expect(AppColors.palette, same(AppPalette.light));
    expect(
      find.descendant(
        of: find.byKey(AppearanceSettingsCard.tileKey(AppThemeVariant.light)),
        matching: find.byKey(const ValueKey('appearance-theme-check')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the selected tile is outlined in the accent', (tester) async {
    await pumpCard(tester);

    Material tileMaterial(AppThemeVariant variant) => tester.widget<Material>(
      find
          .descendant(
            of: find.byKey(AppearanceSettingsCard.tileKey(variant)),
            matching: find.byType(Material),
          )
          .first,
    );
    final selected = tileMaterial(AppThemeVariant.dark).shape!
        as RoundedRectangleBorder;
    final other = tileMaterial(AppThemeVariant.light).shape!
        as RoundedRectangleBorder;
    expect(selected.side.color, AppColors.accent);
    expect(selected.side.width, greaterThan(other.side.width));
    expect(other.side.color, AppColors.borderSubtle);
  });

  testWidgets('screen readers hear each tile as a selectable button', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpCard(tester);

    expect(find.bySemanticsLabel('深色主题'), findsOneWidget);
    final dark = tester.getSemantics(
      find.byKey(AppearanceSettingsCard.tileKey(AppThemeVariant.dark)),
    );
    expect(
      dark,
      isSemantics(
        label: '深色主题',
        hint: AppThemeVariant.dark.description,
        isButton: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    final light = tester.getSemantics(
      find.byKey(AppearanceSettingsCard.tileKey(AppThemeVariant.light)),
    );
    expect(
      light,
      isSemantics(
        label: '浅色主题',
        isButton: true,
        isSelected: false,
      ),
    );

    light.owner!.performAction(light.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(controller.variant, AppThemeVariant.light);
    handle.dispose();
  });

  testWidgets('tiles sit side by side on a wide card', (tester) async {
    await pumpCard(tester, width: 700);

    final dark = tester.getRect(
      find.byKey(AppearanceSettingsCard.tileKey(AppThemeVariant.dark)),
    );
    final light = tester.getRect(
      find.byKey(AppearanceSettingsCard.tileKey(AppThemeVariant.light)),
    );
    expect(dark.top, light.top);
    expect(light.left, greaterThan(dark.right));
  });

  testWidgets('tiles stack on a very narrow card', (tester) async {
    await pumpCard(tester, width: 320);

    final dark = tester.getRect(
      find.byKey(AppearanceSettingsCard.tileKey(AppThemeVariant.dark)),
    );
    final light = tester.getRect(
      find.byKey(AppearanceSettingsCard.tileKey(AppThemeVariant.light)),
    );
    expect(light.top, greaterThan(dark.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits a 390-wide phone without overflow', (tester) async {
    await pumpCard(tester, width: 390);
    expect(tester.takeException(), isNull);
    for (final variant in AppThemeVariant.values) {
      final rect = tester.getRect(
        find.byKey(AppearanceSettingsCard.tileKey(variant)),
      );
      expect(rect.right, lessThanOrEqualTo(390));
    }
  });

  testWidgets('says so when the choice could not be saved', (tester) async {
    final failing = _FailingStore();
    final unsaved = AppAppearanceController(store: failing);
    await pumpCard(tester, using: unsaved);
    expect(find.byKey(const ValueKey('appearance-save-failed')), findsNothing);

    await tester.tap(
      find.byKey(AppearanceSettingsCard.tileKey(AppThemeVariant.light)),
    );
    await tester.pumpAndSettle();

    expect(unsaved.variant, AppThemeVariant.light);
    expect(find.text(AppearanceSettingsText.saveFailed), findsOneWidget);
    final message = tester.widget<Text>(
      find.byKey(const ValueKey('appearance-save-failed')),
    );
    expect(message.style?.color, AppPalette.light.errorText);

    failing.fail = false;
    await tester.tap(
      find.byKey(AppearanceSettingsCard.tileKey(AppThemeVariant.light)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('appearance-save-failed')), findsNothing);
  });

  testWidgets('the card itself follows the theme it switches to', (
    tester,
  ) async {
    await pumpCard(tester);
    Color labelColor() => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(
              AppearanceSettingsCard.tileKey(AppThemeVariant.dark),
            ),
            matching: find.text('深色'),
          ),
        )
        .style!
        .color!;

    expect(labelColor(), AppPalette.dark.textPrimary);

    await controller.select(AppThemeVariant.light);
    await tester.pumpAndSettle();

    expect(labelColor(), AppPalette.light.textPrimary);
  });

  group('the settings screen', () {
    final screen = File(
      'lib/features/settings/presentation/screens/settings_screen.dart',
    ).readAsStringSync();

    test('opens with 外观, before the library and recognition', () {
      final appearance = screen.indexOf("key: ValueKey('settings-group:appearance')");
      final library = screen.indexOf("key: ValueKey('settings-group:library')");
      final recognition = screen.indexOf(
        "key: ValueKey('settings-group:recognition')",
      );
      expect(appearance, greaterThan(0));
      expect(library, greaterThan(appearance));
      expect(recognition, greaterThan(library));
      expect(screen, contains('AppearanceSettingsCard('));
    });

    test('shows the card only when the dependencies carry a controller', () {
      expect(screen, contains('if (appearance != null)'));
    });

    test('the assembly hands it the app controller', () {
      final assembly = File(
        'lib/app/transcription_assembly.dart',
      ).readAsStringSync();
      expect(assembly, contains('appearance: services.appearance'));
    });

    test('the intro names the appearance settings', () {
      expect(screen, contains("settingsIntro = '外观、"));
    });
  });
}
