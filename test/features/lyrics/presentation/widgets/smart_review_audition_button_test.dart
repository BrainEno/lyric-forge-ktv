import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/smart_review_audition_button.dart';

void main() {
  testWidgets('invokes the existing preview callback with an accessible touch target', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var previews = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SmartReviewAuditionButton(
              onPressed: () => previews++,
            ),
          ),
        ),
      ),
    );

    final action = find.byTooltip('从这一行开始试听');
    expect(action, findsOneWidget);
    expect(tester.getSize(action).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(action).height, greaterThanOrEqualTo(48));

    await tester.tap(action);
    expect(previews, 1);
  });

  testWidgets('does not invoke preview when disabled', (tester) async {
    var previews = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SmartReviewAuditionButton(
              onPressed: null,
            ),
          ),
        ),
      ),
    );

    final action = find.byTooltip('从这一行开始试听');
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);

    await tester.tap(action);
    expect(previews, 0);
  });
}
