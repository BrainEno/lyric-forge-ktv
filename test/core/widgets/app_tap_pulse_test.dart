import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/widgets/app_tap_pulse.dart';

double _scaleOf(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.descendant(
      of: find.byType(AppTapPulse),
      matching: find.byType(Transform),
    ),
  );
  return transform.transform.getMaxScaleOnAxis();
}

Widget _host(int trigger, {bool reduceMotion = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: AppTapPulse(
          trigger: trigger,
          child: const SizedBox.square(dimension: 24),
        ),
      ),
    ),
  );
}

void main() {
  group('scaleAt', () {
    test('starts and ends at rest', () {
      expect(AppTapPulse.scaleAt(0), 1);
      expect(AppTapPulse.scaleAt(1), closeTo(1, 1e-9));
    });

    test('peaks at 40 per cent', () {
      expect(
        AppTapPulse.scaleAt(0.4),
        closeTo(AppTapPulse.defaultPeakScale, 1e-9),
      );
      expect(AppTapPulse.scaleAt(0.4, peakScale: 1.3), closeTo(1.3, 1e-9));
    });

    test('rises, then falls, and never shrinks the child', () {
      var previous = AppTapPulse.scaleAt(0);
      for (var step = 1; step <= 40; step++) {
        final scale = AppTapPulse.scaleAt(step / 100);
        expect(scale, greaterThanOrEqualTo(previous));
        previous = scale;
      }
      for (var step = 41; step <= 100; step++) {
        final scale = AppTapPulse.scaleAt(step / 100);
        expect(scale, lessThanOrEqualTo(previous));
        expect(scale, greaterThanOrEqualTo(1));
        previous = scale;
      }
    });

    test('clamps progress outside 0 to 1', () {
      expect(AppTapPulse.scaleAt(-1), 1);
      expect(AppTapPulse.scaleAt(2), closeTo(1, 1e-9));
    });
  });

  group('widget', () {
    testWidgets('rests at full size until the trigger changes', (tester) async {
      await tester.pumpWidget(_host(0));
      expect(_scaleOf(tester), 1);

      await tester.pumpWidget(_host(0));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_scaleOf(tester), 1);
    });

    testWidgets('swells on a new trigger and settles back', (tester) async {
      await tester.pumpWidget(_host(0));
      await tester.pumpWidget(_host(1));
      await tester.pump(const Duration(milliseconds: 100));

      expect(_scaleOf(tester), greaterThan(1.05));

      await tester.pumpAndSettle();
      expect(_scaleOf(tester), closeTo(1, 1e-9));
    });

    testWidgets('every press pulses again', (tester) async {
      await tester.pumpWidget(_host(0));
      await tester.pumpWidget(_host(1));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_host(2));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_scaleOf(tester), greaterThan(1.05));
      await tester.pumpAndSettle();
    });

    testWidgets('stays still when the platform asks for less motion', (
      tester,
    ) async {
      await tester.pumpWidget(_host(0, reduceMotion: true));
      await tester.pumpWidget(_host(1, reduceMotion: true));
      await tester.pump(const Duration(milliseconds: 100));

      expect(_scaleOf(tester), 1);
    });
  });
}
