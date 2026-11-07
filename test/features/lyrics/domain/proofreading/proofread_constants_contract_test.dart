import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _constantsPath =
    'lib/features/lyrics/domain/proofreading/proofread_constants.dart';

/// A conservative lexical scan: comments and string literals cannot count as
/// uses. Interpolation is deliberately ignored, so a string-only use must be
/// expressed as ordinary code rather than silently satisfying this contract.
String _codeOnly(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      i = end < 0 ? source.length : end;
      out.write(' ');
    } else if (source.startsWith('/*', i)) {
      var depth = 1;
      i += 2;
      while (i < source.length && depth > 0) {
        if (source.startsWith('/*', i)) {
          depth++;
          i += 2;
        } else if (source.startsWith('*/', i)) {
          depth--;
          i += 2;
        } else {
          i++;
        }
      }
      out.write(' ');
    } else if (source[i] == "'" || source[i] == '"') {
      final quote = source[i];
      final raw = i > 0 && source[i - 1] == 'r' &&
          (i < 2 || !RegExp(r'[A-Za-z0-9_]').hasMatch(source[i - 2]));
      final delimiter = source.startsWith(quote * 3, i) ? quote * 3 : quote;
      i += delimiter.length;
      while (i < source.length) {
        if (source.startsWith(delimiter, i)) {
          i += delimiter.length;
          break;
        }
        if (!raw && source[i] == r'\' && i + 1 < source.length) {
          i += 2;
        } else {
          i++;
        }
      }
      out.write(' ');
    } else {
      out.write(source[i++]);
    }
  }
  return out.toString();
}

Set<String> _declarations(String source) {
  final code = _codeOnly(source);
  final starts = RegExp(r'\bstatic\s+const\b').allMatches(code).length;
  // Enforce one simple declaration per statement so new declarations cannot
  // accidentally escape the liveness check. Complex declarations fail closed.
  final matches = RegExp(
    r'\bstatic\s+const\s+(?:(?:int|double|bool|String)\s+)?'
    r'([A-Za-z_]\w*)\s*=\s*[^;,]+;',
  ).allMatches(code).toList();
  if (matches.length != starts) {
    throw const FormatException('Unsupported ProofreadConstants declaration');
  }
  return matches.map((match) => match.group(1)!).toSet();
}

Set<String> _references(String source) => RegExp(
  r'\bProofreadConstants\s*\.\s*([A-Za-z_]\w*)\b',
).allMatches(_codeOnly(source)).map((match) => match.group(1)!).toSet();

void main() {
  test('every proofreading constant has a production consumer', () {
    final declarations = _declarations(File(_constantsPath).readAsStringSync());
    expect(declarations, isNotEmpty);
    final references = <String>{};
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final path = file.path.replaceAll('\\', '/');
      if (!path.endsWith('.dart') || path == _constantsPath) continue;
      references.addAll(_references(file.readAsStringSync()));
    }
    expect(
      declarations.difference(references),
      isEmpty,
      reason: 'Remove unused constants or connect them to production behavior.',
    );
  });

  test('scanner rejects dead constants and ignores comments and strings', () {
    const declarations = '''
      class ProofreadConstants {
        static const active = 1;
        static const unused = 2;
      }
    ''';
    const consumer = '''
      final value = ProofreadConstants.active;
      // ProofreadConstants.unused
      /* outer /* nested */ ProofreadConstants.unused */
      final text = 'ProofreadConstants.unused';
      final raw = r"ProofreadConstants.unused";
    ''';
    expect(_declarations(declarations).difference(_references(consumer)), {'unused'});
    expect(
      () => _declarations('static const first = 1, second = 2;'),
      throwsFormatException,
    );
  });
}
