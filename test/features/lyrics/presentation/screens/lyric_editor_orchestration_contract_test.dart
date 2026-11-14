import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _screenPath =
    'lib/features/lyrics/presentation/screens/lyric_editor_screen.dart';
const _useCaseTestPath =
    'test/features/lyrics/domain/proofreading/run_proofread_v2_use_case_test.dart';

void main() {
  test('editor screen stays below the orchestration size budget', () {
    final screen = File(_screenPath).readAsStringSync();
    expect(screen.split('\n'), hasLength(lessThan(1200)));
    expect(screen, contains('implements LyricEditorProofreadFlowHost'));
    expect(screen, contains("import '../widgets/lyric_editor_content.dart';"));
  });

  for (final signature in [
    'Future<void> _openReferenceAlignment(ProjectManifest project)',
    'Future<void> _openReferenceProofread(ProjectManifest project)',
    'Future<void> _openProofreadV2(ProjectManifest project)',
  ]) {
    test('$signature remains a thin interaction entry point', () {
      final screen = File(_screenPath).readAsStringSync();
      final lines = _methodLines(screen, signature);
      expect(lines, lessThan(40));
      expect(screen, contains('_proofreading.'));
    });
  }

  test('V2 proposal decisions remain covered outside widget orchestration', () {
    final useCaseTests = File(_useCaseTestPath).readAsStringSync();
    final cases = RegExp(
      r'\btest(?:Widgets)?\s*\(',
    ).allMatches(useCaseTests).length;
    expect(cases, greaterThanOrEqualTo(10));
  });
}

int _methodLines(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: 'Missing $signature');
  final opening = source.indexOf('{', start);
  expect(
    opening,
    greaterThanOrEqualTo(0),
    reason: 'Missing method body for $signature',
  );

  var depth = 0;
  for (var index = opening; index < source.length; index++) {
    final character = source[index];
    if (character == '{') depth++;
    if (character == '}') depth--;
    if (depth == 0) {
      return source.substring(start, index + 1).split('\n').length;
    }
  }
  fail('Unclosed method body for $signature');
}
