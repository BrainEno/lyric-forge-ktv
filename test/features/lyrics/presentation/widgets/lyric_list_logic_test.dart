import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/widgets/lyric_list_logic.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

LyricDocument _document(
  List<String> texts, {
  Map<String, dynamic> metadata = const {},
}) {
  return LyricDocument(
    language: 'zh',
    metadata: metadata,
    lines: [
      for (var index = 0; index < texts.length; index++)
        LyricLine(
          id: 'line-$index',
          text: texts[index],
          startTime: Duration(seconds: index * 4),
          endTime: Duration(seconds: index * 4 + 3),
        ),
    ],
  );
}

Map<String, dynamic> _candidate(Object? lineIndex) => {
  'lineIndex': lineIndex,
  'alternativeText': 'alt',
};

void main() {
  group('sameLyricIndices', () {
    test('the same list is the same', () {
      final list = [1, 2, 3];
      expect(sameLyricIndices(list, list), isTrue);
    });

    test('equal contents are the same', () {
      expect(sameLyricIndices([1, 2, 3], [1, 2, 3]), isTrue);
      expect(sameLyricIndices(const [], const []), isTrue);
    });

    test('order and length matter', () {
      expect(sameLyricIndices([1, 2, 3], [1, 3, 2]), isFalse);
      expect(sameLyricIndices([1, 2], [1, 2, 3]), isFalse);
    });
  });

  group('search', () {
    final document = _document(['月亮代表我的心', 'Hello World', '你问我爱你有多深']);

    test('normalizes case and spaces', () {
      expect(LyricListSearch.normalize('  HeLLo '), 'hello');
    });

    test('an empty or blank query returns the shown rows themselves', () {
      final visible = [0, 1, 2];
      expect(LyricListSearch.filter(document, visible, ''), same(visible));
      expect(LyricListSearch.filter(document, visible, '   '), same(visible));
    });

    test('matches text regardless of case', () {
      expect(LyricListSearch.filter(document, [0, 1, 2], 'WORLD'), [1]);
      expect(LyricListSearch.filter(document, [0, 1, 2], '我'), [0, 2]);
    });

    test('matches the start time as shown', () {
      expect(LyricListSearch.filter(document, [0, 1, 2], '00:08'), [2]);
    });

    test('matches the row number', () {
      expect(LyricListSearch.filter(document, [0, 1, 2], '2'), [1]);
    });

    test('only searches the shown rows, in their order', () {
      expect(LyricListSearch.filter(document, [2, 0], '我'), [2, 0]);
      expect(LyricListSearch.filter(document, [1], '我'), isEmpty);
    });

    test('rows that no longer exist are skipped', () {
      expect(LyricListSearch.filter(document, [0, 7, -1], '月'), [0]);
    });

    test('matches is true for an empty query', () {
      expect(LyricListSearch.matches(document.lines.first, 0, ''), isTrue);
    });
  });

  group('candidate highlights', () {
    test('none without a saved candidate list', () {
      expect(
        LyricCandidateHighlights.from(_document(['a']), reviewed: const {}),
        isNull,
      );
      expect(
        LyricCandidateHighlights.from(
          _document(['a'], metadata: {'fallbackCandidates': 'broken'}),
          reviewed: const {},
        ),
        isNull,
      );
    });

    test('without a limit every unreviewed candidate is marked', () {
      final highlights = LyricCandidateHighlights.from(
        _document(
          ['a', 'b', 'c'],
          metadata: {
            'fallbackCandidates': [_candidate(0), _candidate(2)],
          },
        ),
        reviewed: const {},
      )!;
      expect(highlights.total, 2);
      expect(highlights.eligible, 2);
      expect(highlights.highlighted, {0, 2});
      expect(highlights.shows(0), isTrue);
      expect(highlights.shows(1), isFalse);
      expect(highlights.remaining, 0);
      expect(highlights.hasSummary, isTrue);
    });

    test('reviewed rows are never marked', () {
      final highlights = LyricCandidateHighlights.from(
        _document(
          ['a', 'b', 'c'],
          metadata: {
            'fallbackCandidates': [_candidate(0), _candidate(1), _candidate(2)],
          },
        ),
        reviewed: const {1},
      )!;
      expect(highlights.total, 3);
      expect(highlights.eligible, 2);
      expect(highlights.highlighted, {0, 2});
    });

    test('the limit keeps the first rows in saved order', () {
      final highlights = LyricCandidateHighlights.from(
        _document(
          ['a', 'b', 'c', 'd'],
          metadata: {
            'fallbackHighlightLimit': 2,
            'fallbackCandidates': [
              _candidate(3),
              _candidate(1),
              _candidate(0),
            ],
          },
        ),
        reviewed: const {},
      )!;
      expect(highlights.highlighted, {3, 1});
      expect(highlights.remaining, 1);
    });

    test('the limit is clamped and may be fractional', () {
      final document = _document(
        ['a', 'b'],
        metadata: {
          'fallbackHighlightLimit': 99.7,
          'fallbackCandidates': [_candidate(0), _candidate(1)],
        },
      );
      expect(
        LyricCandidateHighlights.from(document, reviewed: const {})!
            .highlighted,
        {0, 1},
      );
      final negative = document.copyWith(
        metadata: {...document.metadata, 'fallbackHighlightLimit': -3},
      );
      expect(
        LyricCandidateHighlights.from(negative, reviewed: const {})!
            .highlighted,
        isEmpty,
      );
    });

    test('a limit that is not a number is ignored', () {
      final highlights = LyricCandidateHighlights.from(
        _document(
          ['a'],
          metadata: {
            'fallbackHighlightLimit': 'three',
            'fallbackCandidates': [_candidate(0)],
          },
        ),
        reviewed: const {},
      )!;
      expect(highlights.highlighted, {0});
    });

    test('broken entries and duplicates are skipped', () {
      final highlights = LyricCandidateHighlights.from(
        _document(
          ['a', 'b'],
          metadata: {
            'fallbackCandidates': [
              'text',
              _candidate('1'),
              _candidate(-1),
              _candidate(9),
              _candidate(1),
              _candidate(1),
            ],
          },
        ),
        reviewed: const {},
      )!;
      expect(highlights.total, 1);
      expect(highlights.highlighted, {1});
    });

    test('an empty list has no summary', () {
      final highlights = LyricCandidateHighlights.from(
        _document(['a'], metadata: {'fallbackCandidates': <Object>[]}),
        reviewed: const {},
      )!;
      expect(highlights.hasSummary, isFalse);
      expect(highlights.shows(0), isFalse);
    });

    test('the summary counts the marked rows on screen', () {
      const highlights = LyricCandidateHighlights(
        total: 30,
        eligible: 29,
        highlighted: {1, 2, 3},
      );
      expect(
        highlights.summary([0, 1, 2, 4]),
        '已保存候选 30 行 · 未复核 29 行 · 重点标记 3 行（当前筛选 2 行） · '
        '其余未复核 26 行仍可查看',
      );
      expect(highlights.summary(const []), contains('当前筛选 0 行'));
    });
  });

  group('keys', () {
    LyricListCommand? commandFor(LogicalKeyboardKey key, {bool cmd = false}) =>
        LyricListNavigation.commandFor(key, command: cmd);

    test('arrows move the selection', () {
      expect(commandFor(LogicalKeyboardKey.arrowDown), LyricListCommand.next);
      expect(commandFor(LogicalKeyboardKey.arrowUp), LyricListCommand.previous);
    });

    test('Enter, numpad Enter and F2 edit', () {
      for (final key in [
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.numpadEnter,
        LogicalKeyboardKey.f2,
      ]) {
        expect(commandFor(key), LyricListCommand.edit, reason: '$key');
      }
    });

    test('Delete and Backspace only delete with Ctrl or Cmd', () {
      expect(commandFor(LogicalKeyboardKey.delete), isNull);
      expect(commandFor(LogicalKeyboardKey.backspace), isNull);
      expect(
        commandFor(LogicalKeyboardKey.delete, cmd: true),
        LyricListCommand.delete,
      );
      expect(
        commandFor(LogicalKeyboardKey.backspace, cmd: true),
        LyricListCommand.delete,
      );
    });

    test('Ctrl or Cmd + F searches; F alone does nothing', () {
      expect(
        commandFor(LogicalKeyboardKey.keyF, cmd: true),
        LyricListCommand.search,
      );
      expect(commandFor(LogicalKeyboardKey.keyF), isNull);
    });

    test('other keys are left to the app', () {
      for (final key in [
        LogicalKeyboardKey.tab,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.keyZ,
        LogicalKeyboardKey.keyS,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.escape,
      ]) {
        expect(commandFor(key), isNull, reason: '$key');
        expect(commandFor(key, cmd: true), isNull, reason: 'cmd $key');
      }
    });
  });

  group('selection steps', () {
    const shown = [2, 5, 9];

    test('next and previous follow the shown order', () {
      expect(LyricListNavigation.next(shown, 2), 5);
      expect(LyricListNavigation.next(shown, 5), 9);
      expect(LyricListNavigation.previous(shown, 9), 5);
      expect(LyricListNavigation.previous(shown, 5), 2);
    });

    test('stop at the ends', () {
      expect(LyricListNavigation.next(shown, 9), isNull);
      expect(LyricListNavigation.previous(shown, 2), isNull);
    });

    test('a hidden selection does not move', () {
      expect(LyricListNavigation.next(shown, 3), isNull);
      expect(LyricListNavigation.previous(shown, 3), isNull);
    });
  });

  group('follow target', () {
    double? target({
      int position = 10,
      double viewport = 500,
      double max = 5000,
      double offset = 0,
    }) => LyricListNavigation.followTarget(
      position: position,
      viewport: viewport,
      minExtent: 0,
      maxExtent: max,
      offset: offset,
    );

    test('puts the row a little above the middle', () {
      expect(target(), 10 * 68 - 500 * 0.42);
    });

    test('is clamped to the scroll range', () {
      expect(target(position: 1, offset: 100), 0);
      expect(target(position: 100, max: 1000), 1000);
    });

    test('does not scroll for small differences', () {
      expect(target(offset: 10 * 68 - 210 + 19), isNull);
      expect(target(offset: 10 * 68 - 210 + 21), isNotNull);
    });

    test('a hidden row does not scroll', () {
      expect(target(position: -1), isNull);
    });
  });
}
