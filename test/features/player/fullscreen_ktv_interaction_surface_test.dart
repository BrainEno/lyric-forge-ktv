import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/presentation/widgets/fullscreen_ktv_interaction_surface.dart';

void main() {
  testWidgets('controls hide after idle and reveal on tap', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        hideDelay: const Duration(milliseconds: 100),
        onExit: () {},
      ),
    );

    expect(find.text('controls-visible'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('controls-hidden'), findsOneWidget);

    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    expect(find.text('controls-visible'), findsOneWidget);
  });

  testWidgets('escape exits fullscreen KTV', (tester) async {
    var exits = 0;
    await tester.pumpWidget(
      _TestApp(
        hideDelay: const Duration(seconds: 30),
        onExit: () => exits += 1,
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(exits, 1);
  });

  testWidgets('double tap exits fullscreen KTV', (tester) async {
    var exits = 0;
    await tester.pumpWidget(
      _TestApp(
        hideDelay: const Duration(seconds: 30),
        onExit: () => exits += 1,
      ),
    );

    await tester.doubleTap(find.text('lyrics'));
    await tester.pump();

    expect(exits, 1);
  });
}

class _TestApp extends StatelessWidget {
  final Duration hideDelay;
  final VoidCallback onExit;

  const _TestApp({
    required this.hideDelay,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: FullscreenKtvInteractionSurface(
          controlsHideDelay: hideDelay,
          onExit: onExit,
          builder: (context, controlsVisible) {
            return SizedBox.expand(
              child: Column(
                children: [
                  Text(controlsVisible ? 'controls-visible' : 'controls-hidden'),
                  const Expanded(child: Center(child: Text('lyrics'))),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
