import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/proofread_strategy_selector.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_proofread_v2_dialog.dart';

void main() {
  Future<void> open(WidgetTester tester, {required bool enabled, required ValueChanged<ProofreadV2RunOptions?> onResult, double scale = 1}) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: MediaQuery(data: MediaQueryData(size: const Size(320, 568), textScaler: TextScaler.linear(scale)), child: Builder(builder: (context) => Scaffold(body: ElevatedButton(onPressed: () async => onResult(await showProofreadV2RunOptionsDialog(context, allowProjectEvidence: enabled)), child: const Text('open')))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('unsupported hosts do not show project option', (tester) async {
    await open(tester, enabled: false, onResult: (_) {});
    expect(find.byKey(const ValueKey('project_asr_evidence_toggle')), findsNothing);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('project evidence is explicit and excludes retained pasted text at scale $scale', (tester) async {
      ProofreadV2RunOptions? result;
      await open(tester, enabled: true, scale: scale, onResult: (value) => result = value);
      final field = find.byKey(const ValueKey('secondary_asr_transcript_input'));
      await tester.ensureVisible(field);
      await tester.enterText(field, '[00:01.00] manual');
      final toggle = find.byKey(const ValueKey('project_asr_evidence_toggle'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).enabled, isFalse);
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      expect(result!.useProjectEvidence, isTrue);
      expect(result!.secondaryTranscriptText, isNull);
      expect(result!.strategy, LyricSourceStrategy.auto);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('switching back restores manual text; reference suppresses project option', (tester) async {
    ProofreadV2RunOptions? result;
    await open(tester, enabled: true, onResult: (value) => result = value);
    final field = find.byKey(const ValueKey('secondary_asr_transcript_input'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '[00:01.00] manual');
    final toggle = find.byKey(const ValueKey('project_asr_evidence_toggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).enabled, isTrue);
    expect(tester.widget<TextField>(field).controller!.text, '[00:01.00] manual');
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('参考歌词优先'));
    await tester.tap(find.text('参考歌词优先'));
    await tester.pumpAndSettle();
    expect(find.textContaining('之前配置的 ASR 第二意见'), findsOneWidget);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(result!.useProjectEvidence, isFalse);
    expect(result!.secondaryTranscriptText, isNull);
  });
}
