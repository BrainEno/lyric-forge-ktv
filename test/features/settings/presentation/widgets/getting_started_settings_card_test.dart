import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/settings/presentation/widgets/getting_started_settings_card.dart';

void main() {
  Widget host(Future<void> Function() onShow) => MaterialApp(
    home: Scaffold(body: GettingStartedSettingsCard(onShow: onShow)),
  );

  testWidgets('在首页重新显示 brings the checklist back (D-070)', (tester) async {
    var calls = 0;
    await tester.pumpWidget(host(() async => calls++));

    await tester.tap(find.byKey(GettingStartedSettingsCard.showKey));
    await tester.pump();

    expect(calls, 1);
    expect(find.text(GettingStartedSettingsText.shown), findsOneWidget);
  });

  testWidgets('a failure is reported instead of lost', (tester) async {
    await tester.pumpWidget(host(() async => throw StateError('disk full')));

    await tester.tap(find.text(GettingStartedSettingsText.show));
    await tester.pump();

    expect(find.textContaining('没能打开开始使用指南'), findsOneWidget);
  });
}
