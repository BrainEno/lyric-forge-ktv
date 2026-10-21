import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/lyric_review_strings.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/smart_review_audition_button.dart';

void main() {
  testWidgets(
    'button does not also invoke the lyric row tap on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var auditions = 0;
      var rowTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: InkWell(
                onTap: () => rowTaps++,
                child: SmartReviewAuditionButton(
                  isSmartReview: true,
                  hasAudio: true,
                  isPlaying: false,
                  onPressed: () => auditions++,
                ),
              ),
            ),
          ),
        ),
      );

      final action = find.byTooltip(LyricReviewStrings.auditionPlayTooltip);
      expect(action, findsOneWidget);
      expect(tester.getSize(action).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(action).height, greaterThanOrEqualTo(48));

      await tester.tap(action);
      await tester.pump();

      expect(auditions, 1);
      expect(rowTaps, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('toggling a row changes play to pause and back', (tester) async {
    var isPlaying = false;
    var toggles = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Center(
              child: SmartReviewAuditionButton(
                isSmartReview: true,
                hasAudio: true,
                isPlaying: isPlaying,
                onPressed: () {
                  setState(() => isPlaying = !isPlaying);
                  toggles++;
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byTooltip(LyricReviewStrings.auditionPlayTooltip),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip(LyricReviewStrings.auditionPlayTooltip));
    await tester.pump();
    expect(
      find.byTooltip(LyricReviewStrings.auditionPauseTooltip),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    await tester.tap(find.byTooltip(LyricReviewStrings.auditionPauseTooltip));
    await tester.pump();
    expect(
      find.byTooltip(LyricReviewStrings.auditionPlayTooltip),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(toggles, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hides audition outside smart review or without audio', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SmartReviewAuditionButton(
                isSmartReview: false,
                hasAudio: true,
                isPlaying: false,
                onPressed: null,
              ),
              SmartReviewAuditionButton(
                isSmartReview: true,
                hasAudio: false,
                isPlaying: false,
                onPressed: null,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(IconButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not invoke audition when disabled', (tester) async {
    var auditions = 0;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SmartReviewAuditionButton(
              isSmartReview: true,
              hasAudio: true,
              isPlaying: false,
              onPressed: null,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip(LyricReviewStrings.auditionPlayTooltip));
    expect(auditions, 0);
    expect(tester.takeException(), isNull);
  });
}
