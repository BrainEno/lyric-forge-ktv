// Generates lib/features/lyrics/domain/text/chinese_script_data.g.dart from an
// OpenCC checkout.
//
//   git clone https://github.com/BYVoid/OpenCC.git /tmp/opencc
//   git -C /tmp/opencc checkout <revision>
//   dart run tool/generate_chinese_script_tables.dart \
//     --opencc /tmp/opencc --revision <revision>
//   dart format lib/features/lyrics/domain/text/chinese_script_data.g.dart
//
// What is kept, and why:
//
// * Character tables keep only the first (default) candidate, exactly what
//   OpenCC's own converter emits when no phrase matches.
// * Phrase dictionaries are kept whole (first candidate per entry). Most of
//   STPhrases' ~49k entries convert exactly like the character table, but
//   they still matter: in running text a phrase such as 会了 consumes the 了
//   that would otherwise start 了如 → 瞭如, so 学会了如何 would come out as
//   學會瞭如何. Keeping only "useful" entries plus the ones that block them
//   still retains ~97% of the dictionary and is not exact, so it is not done.
// * Variant and reverse-variant dictionaries are small and kept whole.
// * Script-specific character sets are computed from all candidates, so a
//   character that is also valid in the other script (后, 台, 只, 了 …) is
//   never treated as evidence of either script.

import 'dart:io';

const String _outputPath =
    'lib/features/lyrics/domain/text/chinese_script_data.g.dart';

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  final root = options['--opencc'];
  final revision = options['--revision'];
  if (root == null || revision == null || revision.length < 12) {
    stderr.writeln(
      'Usage: dart run tool/generate_chinese_script_tables.dart '
      '--opencc <OpenCC checkout> --revision <full commit hash> '
      '[--output <path>]',
    );
    exitCode = 2;
    return;
  }
  final dictionary = '$root/data/dictionary';

  final st = _load('$dictionary/STCharacters.txt');
  final ts = _load('$dictionary/TSCharacters.txt');
  final stPhrases = _load('$dictionary/STPhrases.txt');
  final tsPhrases = _load('$dictionary/TSPhrases.txt');
  final tw = _load('$dictionary/TWVariants.txt');
  final twPhrases = _load('$dictionary/TWVariantsPhrases.txt');
  final twRevPhrases = _load('$dictionary/TWVariantsRevPhrases.txt');
  final hk = _load('$dictionary/HKVariants.txt');
  final hkPhrases = _load('$dictionary/HKVariantsPhrases.txt');
  final hkRevPhrases = _load('$dictionary/HKVariantsRevPhrases.txt');

  final stChars = _firstCandidates(st);
  final tsChars = _firstCandidates(ts);

  final output = StringBuffer()
    ..writeln('// GENERATED FILE. Do not edit by hand.')
    ..writeln('//')
    ..writeln('// Regenerate with tool/generate_chinese_script_tables.dart, then')
    ..writeln('// run dart format on this file.')
    ..writeln('//')
    ..writeln('// Derived from OpenCC (https://github.com/BYVoid/OpenCC)')
    ..writeln('// revision $revision.')
    ..writeln('// Copyright (c) the OpenCC contributors.')
    ..writeln('// Licensed under the Apache License, Version 2.0;')
    ..writeln('// see third_party/opencc/LICENSE. Modifications: every entry')
    ..writeln('// reduced to its default (first) candidate; character sets')
    ..writeln('// derived from the character dictionaries (see the generator).')
    ..writeln()
    ..writeln('/// Identifies the table build recorded in lyric metadata.')
    ..writeln(
      "const String chineseScriptDataRevision = "
      "'opencc-${revision.substring(0, 12)}-lyricforge-1';",
    )
    ..writeln();

  _writeCharTable(
    output,
    'simplifiedToTraditionalCharacters',
    'Code point pairs: simplified, then its default traditional form.',
    stChars,
  );
  _writeCharTable(
    output,
    'traditionalToSimplifiedCharacters',
    'Code point pairs: traditional, then its default simplified form.',
    tsChars,
  );
  _writePhraseTable(
    output,
    'simplifiedToTraditionalPhrases',
    'Simplified to traditional phrases: `key=value|`, or `key|` when the '
        'value is the character-level conversion of the key.',
    _firstPhrases(stPhrases),
    characters: stChars,
  );
  _writePhraseTable(
    output,
    'traditionalToSimplifiedPhrases',
    'Traditional to simplified phrases: `key=value|`, or `key|` when the '
        'value is the character-level conversion of the key.',
    _firstPhrases(tsPhrases),
    characters: tsChars,
  );
  _writeCharTable(
    output,
    'taiwanVariantCharacters',
    'OpenCC standard traditional to Taiwan forms.',
    _firstCandidates(tw),
  );
  _writePhraseTable(
    output,
    'taiwanVariantPhrases',
    'Phrase exceptions for Taiwan forms.',
    _firstPhrases(twPhrases),
  );
  _writeCharTable(
    output,
    'taiwanVariantReverseCharacters',
    'Taiwan forms back to OpenCC standard traditional.',
    _reverseFirstCandidates(tw),
  );
  _writePhraseTable(
    output,
    'taiwanVariantReversePhrases',
    'Phrase exceptions for reversing Taiwan forms.',
    _firstPhrases(twRevPhrases),
  );
  _writeCharTable(
    output,
    'hongKongVariantCharacters',
    'OpenCC standard traditional to Hong Kong forms.',
    _firstCandidates(hk),
  );
  _writePhraseTable(
    output,
    'hongKongVariantPhrases',
    'Phrase exceptions for Hong Kong forms.',
    _firstPhrases(hkPhrases),
  );
  _writeCharTable(
    output,
    'hongKongVariantReverseCharacters',
    'Hong Kong forms back to OpenCC standard traditional.',
    _reverseFirstCandidates(hk),
  );
  _writePhraseTable(
    output,
    'hongKongVariantReversePhrases',
    'Phrase exceptions for reversing Hong Kong forms.',
    _firstPhrases(hkRevPhrases),
  );
  _writeCodePointSet(
    output,
    'simplifiedOnlyCharacters',
    'Characters that have no identity mapping to traditional.',
    _withoutIdentity(st),
  );
  _writeCodePointSet(
    output,
    'traditionalOnlyCharacters',
    'Characters that have no identity mapping to simplified.',
    _withoutIdentity(ts),
  );

  final target = File(options['--output'] ?? _outputPath);
  await target.parent.create(recursive: true);
  await target.writeAsString(output.toString());
  stdout.writeln('Wrote ${target.path}');
}

Map<String, String> _parseArgs(List<String> args) {
  final options = <String, String>{};
  for (var index = 0; index + 1 < args.length; index += 2) {
    options[args[index]] = args[index + 1];
  }
  return options;
}

/// Reads an OpenCC text dictionary: `key<TAB>value value …`, `#` comments.
/// Keys keep file order, which is what OpenCC's reverse tables rely on.
Map<String, List<String>> _load(String path) {
  final entries = <String, List<String>>{};
  for (final raw in File(path).readAsLinesSync()) {
    final line = raw.trimRight();
    if (line.isEmpty || line.startsWith('#')) continue;
    final tab = line.indexOf('\t');
    if (tab <= 0) {
      throw FormatException('Malformed OpenCC entry in $path: $line');
    }
    final values = line
        .substring(tab + 1)
        .split(' ')
        .where((value) => value.isNotEmpty)
        .toList();
    if (values.isEmpty) {
      throw FormatException('OpenCC entry without values in $path: $line');
    }
    entries[line.substring(0, tab)] = values;
  }
  return entries;
}

/// Single-character entries mapped to their first candidate, identity
/// mappings dropped.
Map<int, int> _firstCandidates(Map<String, List<String>> table) {
  final result = <int, int>{};
  for (final entry in table.entries) {
    final key = entry.key.runes.toList();
    final value = entry.value.first.runes.toList();
    if (key.length != 1 || value.length != 1) {
      throw FormatException('Expected a character entry: ${entry.key}');
    }
    if (key.single != value.single) result[key.single] = value.single;
  }
  return result;
}

/// OpenCC builds `*Rev` character tables by listing, for every value, the
/// keys that produce it in file order; the converter then takes the first.
Map<int, int> _reverseFirstCandidates(Map<String, List<String>> table) {
  final reversed = <int, List<int>>{};
  for (final entry in table.entries) {
    final key = entry.key.runes.single;
    for (final value in entry.value) {
      reversed.putIfAbsent(value.runes.single, () => <int>[]).add(key);
    }
  }
  return {
    for (final entry in reversed.entries)
      if (entry.value.first != entry.key) entry.key: entry.value.first,
  };
}

Map<String, String> _firstPhrases(Map<String, List<String>> table) => {
  for (final entry in table.entries) entry.key: entry.value.first,
};

Set<int> _withoutIdentity(Map<String, List<String>> table) => {
  for (final entry in table.entries)
    if (!entry.value.contains(entry.key)) entry.key.runes.single,
};

void _writeCharTable(
  StringBuffer output,
  String name,
  String doc,
  Map<int, int> table,
) {
  final keys = table.keys.toList()..sort();
  final pairs = [
    for (final key in keys)
      String.fromCharCode(key) + String.fromCharCode(table[key]!),
  ];
  _writeChunks(output, name, doc, pairs, 16);
}

/// With [characters], entries whose value is just the character-level
/// conversion of the key are written as `key|` and rebuilt when parsed; they
/// are kept (not dropped) because they still steer the segmentation.
void _writePhraseTable(
  StringBuffer output,
  String name,
  String doc,
  Map<String, String> table, {
  Map<int, int>? characters,
}) {
  final keys = table.keys.toList()..sort(_compareCodePoints);
  final entries = [
    for (final key in keys)
      characters != null && _convertCharacters(key, characters) == table[key]
          ? '$key|'
          : '$key=${table[key]}|',
  ];
  _writeChunks(output, name, doc, entries, 10);
}

String _convertCharacters(String text, Map<int, int> characters) {
  final output = StringBuffer();
  for (final rune in text.runes) {
    output.writeCharCode(characters[rune] ?? rune);
  }
  return output.toString();
}

void _writeCodePointSet(
  StringBuffer output,
  String name,
  String doc,
  Set<int> values,
) {
  final sorted = values.toList()..sort();
  _writeChunks(output, name, doc, [
    for (final value in sorted) String.fromCharCode(value),
  ], 32);
}

void _writeChunks(
  StringBuffer output,
  String name,
  String doc,
  List<String> items,
  int perLine,
) {
  for (final item in items) {
    if (item.contains("'") || item.contains(r'$') || item.contains(r'\')) {
      throw FormatException('Unsafe character in generated literal: $item');
    }
  }
  output
    ..writeln('/// $doc')
    ..writeln('const String $name =');
  if (items.isEmpty) {
    output
      ..writeln("    '';")
      ..writeln();
    return;
  }
  for (var start = 0; start < items.length; start += perLine) {
    final end = start + perLine < items.length
        ? start + perLine
        : items.length;
    final last = end == items.length;
    output.writeln("    '${items.sublist(start, end).join()}'${last ? ';' : ''}");
  }
  output.writeln();
}

int _compareCodePoints(String a, String b) {
  final left = a.runes.toList();
  final right = b.runes.toList();
  final shared = left.length < right.length ? left.length : right.length;
  for (var index = 0; index < shared; index++) {
    final order = left[index].compareTo(right[index]);
    if (order != 0) return order;
  }
  return left.length.compareTo(right.length);
}
