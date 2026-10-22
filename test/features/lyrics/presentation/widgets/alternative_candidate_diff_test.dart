import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/alternative_candidate_diff.dart';

void main() {
  testWidgets(
    'highlights the difference between current and alternative lyrics',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: AlternativeCandidateDiff(
                currentText: 'Ashin lady',
                alternativeText: 'passion lady',
              ),
            ),
          ),
        ),
      );

      expect(find.text('主引擎结果'), findsOneWidget);
      expect(find.text('备选引擎结果'), findsOneWidget);
      expect(find.text('Ashin lady', findRichText: true), findsOneWidget);
      expect(find.text('passion lady', findRichText: true), findsOneWidget);

      final primary = tester.widget<RichText>(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText && widget.text.toPlainText() == 'Ashin lady',
        ),
      );
      final primarySpans = primary.text.children!.whereType<TextSpan>();
      expect(
        primarySpans.any(
          (span) => span.style?.decoration == TextDecoration.lineThrough,
        ),
        isTrue,
      );

      final alternative = tester.widget<RichText>(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText() == 'passion lady',
        ),
      );
      final alternativeSpans = alternative.text.children!
          .whereType<TextSpan>();
      expect(
        alternativeSpans.any(
          (span) => span.style?.fontWeight == FontWeight.w700,
        ),
        isTrue,
      );
    },
  );
}
