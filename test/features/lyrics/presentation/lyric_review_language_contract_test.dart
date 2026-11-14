import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #442: proofreading UI text uses Simplified Chinese as its single default
/// language. Product and model identifiers (ForcedAligner, ASR, Whisper, Qwen,
/// LRC, V2) may appear inside Chinese sentences, but a sentence written only in
/// English is a regression. This is a source scan until the app adopts
/// localization resources with locale fallback.
const _presentationRoot = 'lib/features/lyrics/presentation';

/// Literals that are developer diagnostics, never shown to users. Each entry
/// must stay justified; remove it when the literal disappears.
const _developerOnlyLiterals = <String>{
  // Thrown only when save is called without a loaded document; the save path
  // returns earlier, so the message cannot reach the UI.
  'Nothing to save: no document is loaded.',
};

void main() {
  test('lyric presentation has no English-only user-facing sentences', () {
    final offenders = <String>[];
    final files = Directory(_presentationRoot)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        for (final literal in englishOnlySentences(lines[index])) {
          if (_developerOnlyLiterals.contains(literal)) continue;
          offenders.add('${file.path}:${index + 1}: $literal');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('every allowlisted developer literal still exists', () {
    final source = Directory(_presentationRoot)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');
    for (final literal in _developerOnlyLiterals) {
      expect(source, contains(literal), reason: 'Remove stale "$literal"');
    }
  });

  group('englishOnlySentences heuristic', () {
    test('flags plain English sentences', () {
      expect(
        englishOnlySentences("  'Forced alignment is unavailable.',"),
        ['Forced alignment is unavailable.'],
      );
    });

    test('accepts Chinese sentences that mention model identifiers', () {
      expect(
        englishOnlySentences("  'ForcedAligner 强制对齐不可用；请手动复核时间。',"),
        isEmpty,
      );
    });

    test('ignores keys, identifiers, interpolation and comments', () {
      expect(
        englishOnlySentences("ValueKey('forced_alignment_review_toggle'),"),
        isEmpty,
      );
      expect(englishOnlySentences(r"'${value.inMilliseconds} ms'"), isEmpty);
      expect(
        englishOnlySentences("// 'This comment is not shown anywhere'"),
        isEmpty,
      );
      expect(englishOnlySentences("'（Ctrl/Cmd+Shift+Z）'"), isEmpty);
      expect(englishOnlySentences("import 'package:a/b c d.dart';"), isEmpty);
    });
  });
}

final _singleQuoted = RegExp(r"'((?:[^'\\]|\\.)*)'");
final _cjk = RegExp(r'[\u3040-\u30ff\u3400-\u9fff\uf900-\ufaff]');
final _englishWord = RegExp(r'(?<![\w])[A-Za-z]{2,}(?![\w])');

/// Single-quoted literals on [line] that read as English sentences: at least
/// three English words separated by whitespace and no CJK characters, after
/// removing string interpolation.
List<String> englishOnlySentences(String line) {
  final trimmed = line.trimLeft();
  if (trimmed.startsWith('//') ||
      trimmed.startsWith('import ') ||
      trimmed.startsWith('export ') ||
      trimmed.startsWith('part ')) {
    return const [];
  }
  final found = <String>[];
  for (final match in _singleQuoted.allMatches(line)) {
    final literal = match.group(1)!;
    final text = literal
        .replaceAll(RegExp(r'\$\{[^}]*\}'), ' ')
        .replaceAll(RegExp(r'\$\{.*$'), ' ')
        .replaceAll(RegExp(r'\$[A-Za-z_]\w*'), ' ');
    if (_cjk.hasMatch(text)) continue;
    final words = _englishWord.allMatches(text).length;
    final tokens = text.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    if (words >= 3 && tokens.length >= 3) found.add(literal);
  }
  return found;
}
