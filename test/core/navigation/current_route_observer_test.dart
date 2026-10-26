import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/navigation/current_route_observer.dart';

void main() {
  testWidgets(
    'publishes restored route after build and tracks push/pop safely',
    (tester) async {
      final observer = CurrentRouteObserver();

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          onGenerateRoute: (settings) {
            if (settings.name == '/next') {
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Pop'),
                  ),
                ),
              );
            }
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).pushNamed('/next'),
                  child: const Text('Push next'),
                ),
              ),
            );
          },
          builder: (context, child) => Column(
            children: [
              ValueListenableBuilder<String?>(
                valueListenable: observer.routeName,
                builder: (context, routeName, _) => Text(
                  'Current route: ${routeName ?? '<pending>'}',
                ),
              ),
              Expanded(child: child ?? const SizedBox.shrink()),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.text('Current route: /'), findsOneWidget);

      await tester.tap(find.text('Push next'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Current route: /next'), findsOneWidget);

      await tester.tap(find.text('Pop'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Current route: /'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      observer.dispose();
    },
  );
}
