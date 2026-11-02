import 'package:flutter_test/flutter_test.dart';

import 'package:lyric_forge_ktv/features/lyrics/domain/models/lyric_edit_history.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

LyricDocument _document(List<String> texts) {
  return LyricDocument(
    language: 'zh',
    lines: [
      for (var index = 0; index < texts.length; index++)
        LyricLine(
          text: texts[index],
          startTime: Duration(seconds: index * 4),
          endTime: Duration(seconds: index * 4 + 4),
        ),
    ],
  );
}

List<String> _texts(LyricDocument document) =>
    document.lines.map((line) => line.text).toList();

void main() {
  test('撤销回到编辑前的文档，重做再回到编辑后', () {
    final history = LyricEditHistory();
    final before = _document(['月亮代表我的心']);
    final after = _document(['月亮代表我的星']);

    history.record(before, label: '修改第 1 行');
    expect(history.canUndo, isTrue);
    expect(history.canRedo, isFalse);
    expect(history.undoLabel, '修改第 1 行');

    final undone = history.undo(after);
    expect(_texts(undone!.document), ['月亮代表我的心']);
    expect(history.canUndo, isFalse);
    expect(history.canRedo, isTrue);

    final redone = history.redo(before);
    expect(_texts(redone!.document), ['月亮代表我的星']);
    expect(history.canUndo, isTrue);
    expect(history.canRedo, isFalse);
  });

  test('误改五行可以一路撤回原始歌词', () {
    final history = LyricEditHistory();
    var current = _document(['一', '二', '三', '四', '五']);
    final original = current;

    // Five separate mistakes, each on a different line.
    for (var index = 0; index < 5; index++) {
      final previous = _texts(current);
      history.record(
        current,
        label: '修改第 ${index + 1} 行',
        mergeKey: 'line:$index',
      );
      current = _document(
        List<String>.generate(
          5,
          (i) => i == index ? '错$i' : previous[i],
        ),
      );
    }
    expect(history.undoDepth, 5);

    for (var step = 0; step < 5; step++) {
      final snapshot = history.undo(current);
      expect(snapshot, isNotNull);
      current = snapshot!.document;
    }

    expect(_texts(current), _texts(original));
    expect(history.canUndo, isFalse);
  });

  test('同一次输入里的连续修改合并成一步', () {
    final history = LyricEditHistory();
    final start = _document(['月亮代表我的心']);
    final at = DateTime(2026, 11, 2, 10, 0, 0);

    history.record(start, label: '修改第 1 行', mergeKey: 'line:0', now: at);
    history.record(
      _document(['月亮代表我的']),
      label: '修改第 1 行',
      mergeKey: 'line:0',
      now: at.add(const Duration(milliseconds: 400)),
    );
    history.record(
      _document(['月亮代表我的星']),
      label: '修改第 1 行',
      mergeKey: 'line:0',
      now: at.add(const Duration(milliseconds: 900)),
    );

    // One step, and it still points at the state before the burst started.
    expect(history.undoDepth, 1);
    final undone = history.undo(_document(['月亮代表我的星']));
    expect(_texts(undone!.document), ['月亮代表我的心']);
  });

  test('超出合并窗口或换了行号就是新的一步', () {
    final history = LyricEditHistory();
    final start = _document(['一', '二']);
    final at = DateTime(2026, 11, 2, 10, 0, 0);

    history.record(start, label: '修改第 1 行', mergeKey: 'line:0', now: at);
    history.record(
      _document(['改过的一', '二']),
      label: '修改第 1 行',
      mergeKey: 'line:0',
      now: at.add(LyricEditHistory.mergeWindow + const Duration(seconds: 1)),
    );
    expect(history.undoDepth, 2);

    history.record(
      _document(['改过的一', '二']),
      label: '修改第 2 行',
      mergeKey: 'line:1',
      now: at.add(const Duration(seconds: 5)),
    );
    expect(history.undoDepth, 3);
  });

  test('新的编辑作废重做分支', () {
    final history = LyricEditHistory();
    final first = _document(['一']);
    final second = _document(['二']);

    history.record(first, label: '修改第 1 行');
    history.undo(second);
    expect(history.canRedo, isTrue);

    history.record(second, label: '修改第 1 行', mergeKey: 'line:0');
    expect(history.canRedo, isFalse);
  });

  test('最多保留 50 步，更早的自动丢弃', () {
    final history = LyricEditHistory();
    for (var index = 0; index < LyricEditHistory.maxEntries + 10; index++) {
      history.record(
        _document(['第 $index 版']),
        label: '修改第 1 行',
        // Distinct keys so nothing merges; we are testing the depth cap.
        mergeKey: 'line:$index',
      );
    }

    expect(history.undoDepth, LyricEditHistory.maxEntries);
    // The oldest steps are gone, not silently merged into the newest.
    expect(history.undoLabel, '修改第 1 行');
  });

  test('清空后两个方向都不可用', () {
    final history = LyricEditHistory();
    history.record(_document(['一']), label: '修改第 1 行');
    history.undo(_document(['二']));

    history.clear();

    expect(history.canUndo, isFalse);
    expect(history.canRedo, isFalse);
    expect(history.undoLabel, isNull);
    expect(history.redoLabel, isNull);
    expect(history.undo(_document(['三'])), isNull);
    expect(history.redo(_document(['三'])), isNull);
  });

  test('撤销会带回当时选中的行', () {
    final history = LyricEditHistory();
    history.record(
      _document(['一', '二', '三']),
      label: '删除第 2 行',
      selectedLineIndex: 1,
    );

    final undone = history.undo(_document(['一', '三']));
    expect(undone!.selectedLineIndex, 1);
  });
}
