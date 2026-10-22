import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/alternative_candidate_diff.dart';

void main() {
  testWidgets('highlights the difference between current and alternative lyrics', (tester) async {
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

    expect(find.text('当前识别'), findsOneWidget);
    expect(find.text('备选识别'), findsOneWidget);
    expect(find.text('Ashin lady', findRichText: true), findsOneWidget);
    expect(find.text('passion lady', findRichText: true), findsOneWidget);
  });
}
