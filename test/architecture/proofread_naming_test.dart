import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// UI audit T-02: the smart proofreading flow (智能校对) kept a version
/// suffix in its file and type names long after the first version was gone,
/// so readers looked for a version one that does not exist. Types drop the
/// suffix (`LyricProofreadReviewItem`, `RunProofreadUseCase`); the editor's
/// entry point is named after its menu item (`onSmartProofread`).
void main() {
  // Written with a character class so this file does not match itself.
  final versionedName = RegExp(r'[Pp]roofread[V]2');
  final versionedPath = RegExp(r'proofread_[v]2');

  Iterable<File> dartFiles() => [
    for (final root in ['lib', 'test'])
      ...Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
  ];

  String path(File file) => file.path.replaceAll(r'\', '/');

  test('no proofreading file name carries a version suffix', () {
    final offenders = [
      for (final file in dartFiles())
        if (versionedPath.hasMatch(path(file))) path(file),
    ];
    expect(offenders, isEmpty);
  });

  test('no identifier or comment names a proofreading version', () {
    final offenders = <String>[];
    for (final file in dartFiles()) {
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (versionedName.hasMatch(line) || versionedPath.hasMatch(line)) {
          offenders.add('${path(file)}:${index + 1}');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('the renamed flow keeps its files where imports expect them', () {
    for (final file in [
      'lib/features/lyrics/domain/proofreading/run_proofread_use_case.dart',
      'lib/features/lyrics/domain/proofreading/'
          'proofread_review_assembler.dart',
      'lib/features/lyrics/domain/proofreading/'
          'proofread_document_composer.dart',
      'lib/features/lyrics/presentation/widgets/lyric_proofread_dialog.dart',
    ]) {
      expect(File(file).existsSync(), isTrue, reason: file);
    }
  });

  test('the editor entry point is named after its menu item', () {
    final menu = File(
      'lib/features/lyrics/presentation/widgets/'
      'lyric_proofread_menu_button.dart',
    ).readAsStringSync();
    expect(menu, contains('smartProofread(LyricProofreadGroup.correction)'));
    expect(menu, contains("smartProofreadTitle = '智能校对'"));
    expect(menu, contains('final VoidCallback? onSmartProofread;'));
  });
}
