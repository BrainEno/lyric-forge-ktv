import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A screen file holds a page's state and the order of its parts; the parts
/// live in widgets and controllers. Past this many lines a screen is doing
/// both (D-074).
const _budget = 1200;

/// Screens already over the budget, at their size when the check came in.
/// They may only shrink; drop an entry once its screen is back under.
const _frozen = <String, int>{
  'lib/features/player/presentation/screens/local_collections_screen.dart':
      1249,
};

int _linesOf(File file) => file.readAsStringSync().split('\n').length;

String _pathOf(File file) => file.uri.pathSegments.join('/');

bool _isScreen(File file) =>
    file.path.endsWith('.dart') && file.uri.pathSegments.contains('screens');

List<File> _screens() {
  final files = Directory('lib').listSync(recursive: true).whereType<File>();
  return [
    for (final file in files)
      if (_isScreen(file)) file,
  ]..sort((a, b) => a.path.compareTo(b.path));
}

void main() {
  final screens = _screens();

  test('finds the screens', () {
    expect(screens.length, greaterThan(10));
  });

  test('screens stay under $_budget lines', () {
    final over = <String>[
      for (final file in screens)
        if (!_frozen.containsKey(_pathOf(file)) && _linesOf(file) >= _budget)
          '${_pathOf(file)}: ${_linesOf(file)}',
    ];
    expect(
      over,
      isEmpty,
      reason:
          'Move parts into widgets/ or flows into controllers/ (see '
          'D-072 to D-074).',
    );
  });

  test('frozen screens only shrink, and leave the list once under', () {
    for (final entry in _frozen.entries) {
      final lines = _linesOf(File(entry.key));
      expect(lines, lessThanOrEqualTo(entry.value), reason: entry.key);
      expect(
        lines,
        greaterThanOrEqualTo(_budget),
        reason: '${entry.key} is under budget now; remove it from _frozen.',
      );
    }
  });
}
