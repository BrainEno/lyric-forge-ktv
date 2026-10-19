import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/work_log.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lyricforge-work-log-');
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  void writeFile(String relativePath, String content) {
    final file = File('${root.path}${Platform.pathSeparator}$relativePath');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  String entryBody({
    required String timestamp,
    required String title,
    bool withNotes = true,
    String commit = 'Fixture commit',
  }) {
    return '# [$timestamp] $title\n'
        '\n'
        '- Scope: fixture scope\n'
        '- Files: fixture file\n'
        '- Validation:\n'
        '  - `fixture` => ok\n'
        '${withNotes ? '- Notes: fixture note\n' : ''}'
        '- Commit: `$commit`\n';
  }

  /// Creates a complete, valid harness with [entryCount] entries.
  void createValidHarness({int entryCount = 10}) {
    final stamps = <String>[];
    for (var i = 0; i < entryCount; i++) {
      final hour = 9 + (i ~/ 6);
      final minute = i % 6;
      final stamp =
          '2026-01-01 ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      stamps.add(stamp);
      final compact =
          '${stamp.split(' ').first}-${stamp.split(' ').last.replaceAll(':', '')}';
      writeFile(
        'docs/log/entries/$compact-fixture-entry-$i.md',
        entryBody(timestamp: stamp, title: 'Fixture entry $i'),
      );
    }

    final harness = WorkLogHarness(root);
    final entries = harness.readEntries();
    writeFile('docs/work_log.md', harness.buildSummary(entries));

    final archive = StringBuffer('# Work Log Archive\n\n');
    for (final entry in harness.sortedEntries(entries).skip(8)) {
      archive.writeln(
        '- [${entry.timestamp}] ${entry.title} '
        '([entry](log/entries/${entry.fileName}))',
      );
    }
    writeFile('docs/work_log_archive.md', archive.toString());
    writeFile(
      'docs/work_log_index.md',
      '> Navigation snapshot through 2026-01-01\n',
    );
    writeFile(
      'docs/decisions.md',
      '# Decisions\n\n'
      '## D-001 Fixture\n'
      '- 日期：2026-01-01\n'
      '- 背景：background\n'
      '- 决定：decision\n'
      '- 影响：impact\n'
      '- 状态：生效\n',
    );
    writeFile(
      'docs/handoff.md',
      '# Handoff\n\n'
      '## 目标\n'
      '## Git 现场\n'
      '## 已改文件\n'
      '## 检查结果\n'
      '## 下一步\n'
      '## 已知风险\n'
      '最后更新：2026-01-01 09:00\n',
    );
  }

  List<String> rulesOf(List<LogProblem> problems) =>
      problems.map((problem) => problem.rule).toSet().toList();

  test('accepts a complete harness', () {
    createValidHarness();
    final problems = WorkLogHarness(root).lint(lookupCommits: false);
    expect(problems, isEmpty);
  });

  test('summary lists newest entries first and counts the archive', () {
    createValidHarness();
    final harness = WorkLogHarness(root);
    final summary = harness.buildSummary(harness.readEntries());
    expect(summary, contains('<!-- 10 entries total: 8 active, 2 archived. -->'));
    expect(
      summary.indexOf('[2026-01-01 10:03]'),
      lessThan(summary.indexOf('[2026-01-01 09:02]')),
    );
    expect(summary, isNot(contains('[2026-01-01 09:00]')));
  });

  test('detects a stale summary', () {
    createValidHarness();
    writeFile('docs/work_log.md', '# Work Log (Active)\n\nstale\n');
    final problems = WorkLogHarness(root).lint(lookupCommits: false);
    expect(rulesOf(problems), contains('summary-stale'));
  });

  test('detects an entry without the required fields', () {
    createValidHarness();
    writeFile(
      'docs/log/entries/2026-01-01-1010-fixture-entry-10.md',
      entryBody(
        timestamp: '2026-01-01 10:10',
        title: 'Fixture entry 10',
        withNotes: false,
      ),
    );
    final problems = WorkLogHarness(root).lint(lookupCommits: false);
    expect(rulesOf(problems), contains('entry-fields'));
  });

  test('detects an invalid entry file name', () {
    createValidHarness();
    writeFile(
      'docs/log/entries/2026-01-01-1011-Bad Name!.md',
      entryBody(timestamp: '2026-01-01 10:11', title: 'Bad name'),
    );
    final problems = WorkLogHarness(root).lint(lookupCommits: false);
    expect(rulesOf(problems), contains('entry-name'));
  });

  test('detects duplicate entry timestamps', () {
    createValidHarness();
    writeFile(
      'docs/log/entries/2026-01-01-0900-duplicate-entry.md',
      entryBody(timestamp: '2026-01-01 09:00', title: 'Duplicate'),
    );
    final problems = WorkLogHarness(root).lint(lookupCommits: false);
    expect(rulesOf(problems), contains('entry-duplicate'));
  });

  test('detects an entry that no document references', () {
    createValidHarness();
    writeFile(
      'docs/log/entries/2026-01-02-0800-orphan-entry.md',
      entryBody(timestamp: '2026-01-02 08:00', title: 'Orphan'),
    );
    final problems = WorkLogHarness(root).lint(lookupCommits: false);
    expect(rulesOf(problems), contains('entry-unreferenced'));
  });

  test('detects a broken markdown link', () {
    createValidHarness();
    writeFile(
      'docs/work_log_index.md',
      '> Navigation snapshot through 2026-01-01\n'
      '\n'
      '- [missing](log/entries/does-not-exist.md)\n',
    );
    final problems = WorkLogHarness(root).lint(lookupCommits: false);
    expect(rulesOf(problems), contains('broken-link'));
  });

  test('detects an index snapshot that does not match the newest entry', () {
    createValidHarness();
    writeFile(
      'docs/work_log_index.md',
      '> Navigation snapshot through 2025-05-05\n',
    );
    final problems = WorkLogHarness(root).lint(lookupCommits: false);
    expect(rulesOf(problems), contains('index-snapshot'));
  });

  test('detects a decision without all fields', () {
    createValidHarness();
    writeFile(
      'docs/decisions.md',
      '# Decisions\n\n'
      '## D-001 Fixture\n'
      '- 日期：2026-01-01\n'
      '- 背景：background\n',
    );
    final problems = WorkLogHarness(root).lint(lookupCommits: false);
    expect(rulesOf(problems), contains('decisions-fields'));
  });

  test('detects a handoff that lost a section', () {
    createValidHarness();
    writeFile('docs/handoff.md', '# Handoff\n\n## 目标\n');
    final problems = WorkLogHarness(root).lint(lookupCommits: false);
    expect(rulesOf(problems), contains('handoff-sections'));
  });
}
