import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/app_motion.dart';
import 'package:lyric_forge_ktv/core/theme/app_palette.dart';
import 'package:lyric_forge_ktv/core/theme/color_tokens.dart';
import 'package:lyric_forge_ktv/core/widgets/app_vinyl_disc.dart';

Widget _host(Widget child, {bool disableAnimations = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Scaffold(body: Center(child: child)),
  ),
);

/// Turns looping motion on for one test, as production has it.
void _allowAmbientMotion() {
  final previous = AppMotion.ambientEnabled;
  AppMotion.ambientEnabled = true;
  addTearDown(() => AppMotion.ambientEnabled = previous);
}

double _turns(WidgetTester tester) => tester
    .widget<RotationTransition>(
      find.descendant(
        of: find.byType(AppVinylDisc),
        matching: find.byType(RotationTransition),
      ),
    )
    .turns
    .value;

void main() {
  group('AppMotion', () {
    test('looping motion is off under flutter test', () {
      expect(AppMotion.ambientEnabled, isFalse);
    });

    test('a record turns at 33⅓ rpm', () {
      // 60 s / 33.33 turns = 1.8 s per turn.
      expect(AppMotion.recordTurn, const Duration(milliseconds: 1800));
      expect(AppMotion.rhythmCycle, lessThan(AppMotion.recordTurn));
    });

    testWidgets('the system setting turns it off even when allowed', (
      tester,
    ) async {
      _allowAmbientMotion();
      late bool allowed;
      late bool reduced;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              allowed = AppMotion.ambientOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              reduced = AppMotion.ambientOf(context);
              return const SizedBox();
            },
          ),
          disableAnimations: true,
        ),
      );

      expect(allowed, isTrue);
      expect(reduced, isFalse);
    });

    testWidgets('it works without a MediaQuery above', (tester) async {
      _allowAmbientMotion();
      late bool allowed;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            allowed = AppMotion.ambientOf(context);
            return const SizedBox();
          },
        ),
      );
      expect(allowed, isTrue);
    });
  });

  group('AppVinylDisc', () {
    test('grooves follow the band between label and rim', () {
      expect(AppVinylDisc.grooveCountFor(48), 3);
      expect(
        AppVinylDisc.grooveCountFor(280),
        greaterThan(AppVinylDisc.grooveCountFor(120)),
      );
      // A larger label leaves less vinyl, so fewer grooves.
      expect(
        AppVinylDisc.grooveCountFor(280, labelFraction: 0.7),
        lessThan(AppVinylDisc.grooveCountFor(280)),
      );
    });

    testWidgets('is sized to its diameter and hidden from screen readers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(const AppVinylDisc(size: 120, label: Text('封面'))),
      );

      expect(tester.getSize(find.byType(AppVinylDisc)), const Size.square(120));
      expect(find.text('封面'), findsOneWidget);
      expect(find.bySemanticsLabel('封面'), findsNothing);
      handle.dispose();
    });

    testWidgets('draws a brass note on a blank label without a cover', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const AppVinylDisc(size: 100)));

      final note = tester.widget<Icon>(find.byIcon(Icons.music_note_rounded));
      expect(note.color, AppColors.vinylBrass);
      expect(note.size, closeTo(100 * 0.46 * 0.42, 0.01));
    });

    testWidgets('turns while spinning and keeps its angle when it stops', (
      tester,
    ) async {
      _allowAmbientMotion();
      await tester.pumpWidget(
        _host(const AppVinylDisc(size: 100, spinning: true)),
      );
      // The turn starts on the first frame after the one that built it.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      final turned = _turns(tester);
      expect(turned, closeTo(0.25, 0.02));

      await tester.pumpWidget(_host(const AppVinylDisc(size: 100)));
      await tester.pump(const Duration(milliseconds: 450));

      // Paused where it was, like a turntable, not snapped back to 0.
      expect(_turns(tester), closeTo(turned, 0.001));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('stays still under flutter test, so screens can settle', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const AppVinylDisc(size: 100, spinning: true)),
      );
      await tester.pumpAndSettle();

      expect(_turns(tester), 0);
    });

    testWidgets('stays still when the system asks for less motion', (
      tester,
    ) async {
      _allowAmbientMotion();
      await tester.pumpWidget(
        _host(
          const AppVinylDisc(size: 100, spinning: true),
          disableAnimations: true,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(_turns(tester), 0);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('only the hero record glows', (tester) async {
      await tester.pumpWidget(
        _host(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppVinylDisc(key: ValueKey('plain'), size: 60),
              AppVinylDisc(key: ValueKey('hero'), size: 60, glow: true),
            ],
          ),
        ),
      );

      List<BoxShadow> shadowsOf(String key) => tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .expand((decoration) => decoration.boxShadow ?? const <BoxShadow>[])
          .toList();

      expect(shadowsOf('plain'), isEmpty);
      expect(shadowsOf('hero').single.color, AppColors.vinylBrassMuted);
    });
  });

  group('AppRhythmBars', () {
    test('every bar stays between a quarter and the full height', () {
      for (var bar = 0; bar < AppRhythmBars.barCount; bar++) {
        for (var step = 0; step <= 20; step++) {
          final height = AppRhythmBars.heightAt(bar, step / 20);
          expect(height, inInclusiveRange(0.25, 1.0));
        }
      }
    });

    test('the bars never move in step', () {
      final first = AppRhythmBars.heightAt(0, 0.1);
      final second = AppRhythmBars.heightAt(1, 0.1);
      final third = AppRhythmBars.heightAt(2, 0.1);
      expect({first, second, third}, hasLength(3));
    });

    List<double> heights(WidgetTester tester) => tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(AppRhythmBars),
            matching: find.byType(Container),
          ),
        )
        .map((bar) => bar.constraints!.maxHeight)
        .toList();

    testWidgets('rest at staggered heights while paused', (tester) async {
      await tester.pumpWidget(
        _host(const AppRhythmBars(playing: false, size: 20)),
      );

      expect(heights(tester), [
        for (final fraction in AppRhythmBars.restingHeights) 20 * fraction,
      ]);
    });

    testWidgets('bounce while playing and rest again on pause', (tester) async {
      _allowAmbientMotion();
      await tester.pumpWidget(
        _host(const AppRhythmBars(playing: true, size: 20)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final moving = heights(tester);
      expect(
        moving,
        isNot([
          for (final fraction in AppRhythmBars.restingHeights) 20 * fraction,
        ]),
      );

      await tester.pumpWidget(
        _host(const AppRhythmBars(playing: false, size: 20)),
      );
      await tester.pump();
      expect(heights(tester), [
        for (final fraction in AppRhythmBars.restingHeights) 20 * fraction,
      ]);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('take the colour they are given', (tester) async {
      await tester.pumpWidget(
        _host(AppRhythmBars(playing: false, color: AppColors.textPrimary)),
      );

      final colours = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(AppRhythmBars),
              matching: find.byType(Container),
            ),
          )
          .map((bar) => (bar.decoration! as BoxDecoration).color)
          .toSet();
      expect(colours, {AppColors.textPrimary});
    });
  });

  group('AppCoverGlow', () {
    testWidgets('blurs the cover behind the content', (tester) async {
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 300,
            height: 200,
            child: AppCoverGlow(
              cover: ColoredBox(color: AppColors.vinylBrass),
              child: Text('内容'),
            ),
          ),
        ),
      );

      expect(find.text('内容'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppCoverGlow),
          matching: find.byType(ImageFiltered),
        ),
        findsOneWidget,
      );
    });

    testWidgets('falls back to the warm gradient without a cover', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 300,
            height: 200,
            child: AppCoverGlow(cover: null, child: Text('内容')),
          ),
        ),
      );

      expect(find.byType(ImageFiltered), findsNothing);
      final gradients = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(AppCoverGlow),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((box) => (box.decoration as BoxDecoration).gradient)
          .toList();
      expect(gradients, contains(AppColors.vinylHeroGradient));
    });
  });

  group('AppVinylDisc in the light theme (D-042)', () {
    setUp(() => AppColors.usePalette(AppPalette.light));
    tearDown(() => AppColors.usePalette(AppPalette.dark));

    testWidgets('the blank label takes the warm paper and bronze note', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const AppVinylDisc(size: 100)));

      final note = tester.widget<Icon>(find.byIcon(Icons.music_note_rounded));
      expect(note.color, AppPalette.light.vinylBrass);
      final label = tester.widget<ColoredBox>(
        find
            .ancestor(
              of: find.byIcon(Icons.music_note_rounded),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(label.color, AppPalette.light.vinylSurfaceHigh);
    });

    testWidgets('the label ring keeps the light brass on the black record', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const AppVinylDisc(size: 100)));

      final rings = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(AppVinylDisc),
              matching: find.byType(Container),
            ),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color);
      expect(rings, contains(AppColors.vinylBrassOnDark));
      expect(rings, isNot(contains(AppPalette.light.vinylBrass)));
    });

    testWidgets('the spindle hole shows the light page through it', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const AppVinylDisc(size: 100)));

      final colors = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(AppVinylDisc),
              matching: find.byType(Container),
            ),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color);
      expect(colors, contains(AppPalette.light.bgBase));
    });

    test('the light brass of the ring reads on the record (7:1)', () {
      final ring = AppColors.vinylBrassOnDark.computeLuminance();
      final record = AppColors.vinylDisc.computeLuminance();
      final center = AppPalette.light.vinylDiscCenter.computeLuminance();
      expect((ring + 0.05) / (record + 0.05), greaterThan(7));
      expect((ring + 0.05) / (center + 0.05), greaterThan(7));
    });
  });
}
