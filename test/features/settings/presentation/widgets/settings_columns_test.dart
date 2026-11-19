import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/settings/presentation/widgets/settings_columns.dart';

const _primaryKey = ValueKey('primary-group');
const _secondaryKey = ValueKey('secondary-group');

Future<void> _pump(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SettingsColumns(
            primary: _Counter(key: _primaryKey, height: 420),
            secondary: _Counter(key: _secondaryKey, height: 260),
          ),
        ),
      ),
    ),
  );
}

Rect _rect(WidgetTester tester, Key key) => tester.getRect(find.byKey(key));

void main() {
  test('uses two columns from the breakpoint', () {
    expect(SettingsColumns.useTwoColumns(1079), isFalse);
    expect(SettingsColumns.useTwoColumns(1080), isTrue);
    expect(SettingsColumns.useTwoColumns(1416), isTrue);
  });

  testWidgets('stacks the groups below the breakpoint', (tester) async {
    await _pump(tester, 900);

    final primary = _rect(tester, _primaryKey);
    final secondary = _rect(tester, _secondaryKey);
    expect(primary.width, 900);
    expect(secondary.width, 900);
    expect(secondary.top, primary.bottom + SettingsColumns.gap);
    expect(tester.takeException(), isNull);
  });

  testWidgets('puts the groups side by side on a wide window', (tester) async {
    await _pump(tester, 1400);

    final primary = _rect(tester, _primaryKey);
    final secondary = _rect(tester, _secondaryKey);
    expect(primary.top, secondary.top);
    expect(secondary.left, primary.right + SettingsColumns.gap);
    expect(primary.width, closeTo((1400 - SettingsColumns.gap) * 3 / 5, 1));
    expect(secondary.width, closeTo((1400 - SettingsColumns.gap) * 2 / 5, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps group state when a resize crosses the breakpoint', (
    tester,
  ) async {
    await _pump(tester, 1400);
    await tester.tap(find.byKey(_primaryKey));
    await tester.tap(find.byKey(_secondaryKey));
    await tester.tap(find.byKey(_secondaryKey));
    await tester.pump();
    expect(find.text('taps 1'), findsOneWidget);
    expect(find.text('taps 2'), findsOneWidget);

    tester.view.physicalSize = const Size(900, 900);
    await tester.pump();

    final primary = _rect(tester, _primaryKey);
    final secondary = _rect(tester, _secondaryKey);
    expect(secondary.top, greaterThan(primary.bottom));
    expect(find.text('taps 1'), findsOneWidget);
    expect(find.text('taps 2'), findsOneWidget);

    tester.view.physicalSize = const Size(1400, 900);
    await tester.pump();

    expect(_rect(tester, _primaryKey).top, _rect(tester, _secondaryKey).top);
    expect(find.text('taps 1'), findsOneWidget);
    expect(find.text('taps 2'), findsOneWidget);
  });
}

/// A group stand-in that counts taps, to show its state survives a resize.
class _Counter extends StatefulWidget {
  const _Counter({super.key, required this.height});

  final double height;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var _taps = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _taps++),
      child: SizedBox(
        height: widget.height,
        child: Center(child: Text('taps $_taps')),
      ),
    );
  }
}
