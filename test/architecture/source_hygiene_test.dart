import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source rules that keep three kinds of debt from coming back: silently
/// swallowed errors (#460), colour literals outside the theme (#458) and
/// download addresses outside the ASR endpoint table (#461).
void main() {
  group('errors are never swallowed silently', () {
    // `catch (...) {}` with nothing inside, not even a comment.
    final emptyCatch = RegExp(r'catch\s*\([^)]*\)\s*\{\s*\}');
    // `.catchError((Object _) {})` and friends.
    final emptyCatchError = RegExp(
      r'\.catchError\(\s*\([^)]*\)\s*(\{\s*\}|=>\s*null)\s*\)',
    );

    // The logger cannot report a failure of its own sinks to itself; these
    // chains keep logging alive after a disk error. Every other file uses
    // `bestEffort` or explains its catch.
    const catchErrorAllowed = <String>{
      'lib/core/diagnostics/crash_capture.dart',
      'lib/core/diagnostics/file_log_sink.dart',
    };

    test('no empty catch blocks', () {
      final offenders = _matches(_dartFiles('lib'), emptyCatch);
      expect(
        offenders,
        isEmpty,
        reason:
            'Use bestEffort(...) from core/diagnostics/best_effort.dart, '
            'SerialWriteQueue for write chains, or say in a comment why the '
            'error does not matter.',
      );
    });

    test('no empty catchError handlers outside the logger', () {
      final files = _dartFiles(
        'lib',
      ).where((file) => !catchErrorAllowed.contains(_path(file)));
      expect(_matches(files, emptyCatchError), isEmpty);
    });

    test('file stores share SerialWriteQueue instead of hand-rolled chains', () {
      final offenders = _matches(
        _dartFiles('lib/features'),
        RegExp(r'_writeChain\b'),
      );
      expect(offenders, isEmpty);
    });
  });

  test('colours come from AppColors outside the theme', () {
    final literal = RegExp(
      r'\bColor\(0x|\bColor\.from(ARGB|RGBO)\(|\bColors\.(?!transparent\b)\w+',
    );
    final files = _dartFiles(
      'lib',
    ).where((file) => !_path(file).startsWith('lib/core/theme/'));
    expect(
      _matches(files, literal),
      isEmpty,
      reason: 'Add a token to AppColors (lib/core/theme/color_tokens.dart).',
    );
  });

  test('transcription spells out remote addresses only in AsrEndpoints', () {
    const endpoints =
        'lib/features/transcription/data/services/asr_endpoints.dart';
    final address = RegExp(r'https://|Uri\.https\(');
    final files = _dartFiles(
      'lib/features/transcription',
    ).where((file) => _path(file) != endpoints);
    expect(
      _matches(files, address),
      isEmpty,
      reason: 'Add the address to $endpoints and ask it for a Uri.',
    );
    expect(File(endpoints).readAsStringSync(), contains('releaseRepository'));
  });
}

Iterable<File> _dartFiles(String root) => Directory(root)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

String _path(File file) => file.path.replaceAll(r'\', '/');

/// `path:line` of every match that is not inside a line comment.
List<String> _matches(Iterable<File> files, RegExp pattern) {
  final found = <String>[];
  for (final file in files) {
    final source = file.readAsStringSync();
    for (final match in pattern.allMatches(source)) {
      final lineStart = source.lastIndexOf('\n', match.start) + 1;
      final prefix = source.substring(lineStart, match.start).trimLeft();
      if (prefix.startsWith('//')) continue;
      final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
      found.add('${_path(file)}:$line');
    }
  }
  return found;
}
