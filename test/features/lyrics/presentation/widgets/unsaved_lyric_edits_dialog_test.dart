import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/unsaved_lyric_edits_dialog.dart';

/// Hosts the dialog behind a button and records the decision it returned.
class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  UnsavedLyricEditsDecision? decision;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          // The dialog needs a context below the MaterialApp's Navigator.
          builder: (innerContext) => Column(
            children: [
              TextButton(
                onPressed: () async {
                  final result = await confirmUnsavedLyricEdits(innerContext);
                  if (!mounted) return;
                  setState(() => decision = result);
                },
                child: const Text('leave'),
              ),
              Text(
                decision == null ? 'none' : 'decision:${decision!.name}',
                key: const Key('decision'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(const _Harness());
  await tester.tap(find.text('leave'));
  await tester.pumpAndSettle();
}

String _decision(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('decision'))).data!;

void main() {
  testWidgets('保存并返回 reports save so the caller can save then leave', (
    tester,
  ) async {
    await _open(tester);

    expect(find.text('有未保存的修改'), findsOneWidget);
    await tester.tap(find.text('保存并返回'));
    await tester.pumpAndSettle();

    // The decision is reported separately from leaving; the caller saves first.
    expect(_decision(tester), 'decision:save');
  });

  testWidgets('放弃修改 reports discard', (tester) async {
    await _open(tester);

    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();

    expect(_decision(tester), 'decision:discard');
  });

  testWidgets('继续编辑 keeps the editor open', (tester) async {
    await _open(tester);

    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();

    expect(_decision(tester), 'decision:stay');
  });

  testWidgets('dismissing the dialog never throws the edits away', (
    tester,
  ) async {
    await _open(tester);

    // Tap the barrier outside the dialog.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(_decision(tester), 'decision:stay');
  });
}
