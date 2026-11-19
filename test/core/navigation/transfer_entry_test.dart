import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/navigation/routes.dart';
import 'package:lyric_forge_ktv/core/navigation/transfer_entry.dart';

Future<List<String?>> _openFrom(WidgetTester tester, {bool? desktop}) async {
  final opened = <String?>[];
  await tester.pumpWidget(
    MaterialApp(
      // A fresh navigator per call, so a second call starts from home.
      key: UniqueKey(),
      onGenerateRoute: (settings) {
        opened.add(settings.name);
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const Scaffold(body: Text(TransferEntry.label)),
        );
      },
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => TransferEntry.open(context, desktop: desktop),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return opened;
}

void main() {
  test('the desktop shares its library, a phone connects to one', () {
    expect(TransferEntry.routeFor(desktop: true), Routes.mediaSharing);
    expect(TransferEntry.routeFor(desktop: false), Routes.remoteLibrary);
  });

  test('one name and icon for every entry', () {
    expect(TransferEntry.label, '跨设备传输');
    expect(TransferEntry.icon, Icons.devices_rounded);
  });

  testWidgets('opens the screen for the requested device', (tester) async {
    expect(await _openFrom(tester, desktop: true), [Routes.mediaSharing]);
  });

  testWidgets('opens the phone screen when asked for it', (tester) async {
    expect(await _openFrom(tester, desktop: false), [Routes.remoteLibrary]);
  });

  testWidgets('follows the platform when no device is given', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final desktop = await _openFrom(tester);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final phone = await _openFrom(tester);
    debugDefaultTargetPlatformOverride = null;

    expect(desktop, [Routes.mediaSharing]);
    expect(phone, [Routes.remoteLibrary]);
  });
}
