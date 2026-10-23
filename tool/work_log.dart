// Tooling for the work-log harness.
//
// Usage:
//   dart run tool/work_log.dart write   Regenerate docs/work_log.md from the
//                                        entry files in docs/log/entries/.
//   dart run tool/work_log.dart check   Lint the harness and exit non-zero on
//                                        any violation.
//   dart run tool/work_log.dart print   Print the generated summary.
//
// The harness keeps one immutable file per completed task under
// docs/log/entries/. This tool only reads those files and the navigation
// documents; it never rewrites an entry.

import 'dart:io';

const int kDefaultActiveCount = 8;

const List<String> kEntryFields = <String>[
  'Scope',
  'Files',
  'Validation',
  'Notes',
  'Commit',
];

const List<String> kDecisionFields = <String>[
  '日期：',
  '背景：',
  '决定：',
  '影响：',
  '状态：',
];

const List<String> kHandoffSections = <String>[
  '## 目标',
  '## Git 现场',
  '## 已改文件',
  '## 检查结果',
  '## 下一步',
  '## 已知风险',
  '最后更新',
];

final RegExp _entryNamePattern = RegExp(
  r'^(\d{4}-\d{2}-\d{2})-(\d{4})-([a-z0-9]+(?:-[a-z0-9]+)*)\.md$',
);

final RegExp _entryHeaderPattern = RegExp(
  r'^# \[(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2})\] (.+)$',
);

final RegExp _entryCommitPattern = RegExp(r'^- Commit: `(.+)`\s*
final RegExp _markdownLinkPattern = RegExp(r'\]\(([^)#]+?)\)');

final RegExp _indexSnapshotPattern = RegExp(
  r'Navigation snapshot through (\d{4}-\d{2}-\d{2})',
);

const String _autoArchiveStartMarker =
    '<!-- BEGIN AUTO-GENERATED WORK LOG REFERENCES -->';
const String _autoArchiveEndMarker =
    '<!-- END AUTO-GENERATED WORK LOG REFERENCES -->';
final RegExp _autoArchiveBlockPattern = RegExp(
  r'\n?<!-- BEGIN AUTO-GENERATED WORK LOG REFERENCES -->[\s\S]*?'
  r'<!-- END AUTO-GENERATED WORK LOG REFERENCES -->\s*',
);

/// A single task entry parsed from `docs/log/entries/`.
class LogEntry {
  LogEntry({
    required this.fileName,
    required this.path,
    this.timestamp,
    this.title,
    this.commit,
    this.commitIsExplicit = false,
    this.missingFields = const <String>[],
  });

  final String fileName;
  final String path;
  final String? timestamp;
  final String? title;
  final String? commit;

  /// True when the entry explicitly marks the value as a literal Git subject.
  /// Legacy plain-text values are still rendered in summaries but aren't
  /// checked against history because older entries often used task titles.
  final bool commitIsExplicit;
  final List<String> missingFields;

  bool get hasValidHeader => timestamp != null && title != null;

  /// `2026-10-19-2130` style prefix used by the entry file name.
  String? get fileStamp {
    final value = timestamp;
    if (value == null) {
      return null;
    }
    final parts = value.split(' ');
    if (parts.length != 2) {
      return null;
    }
    return '${parts[0]}-${parts[1].replaceAll(':', '')}';
  }
}

/// A single lint finding.
class LogProblem {
  LogProblem(this.rule, this.message, {this.isWarning = false});

  final String rule;
  final String message;
  final bool isWarning;

  @override
  String toString() => '[$rule] $message';
}

/// Reads and validates the work-log documents of a repository.
class WorkLogHarness {
  WorkLogHarness(this.root);

  final Directory root;

  static final String _sep = Platform.pathSeparator;

  Directory get docsDir => Directory('${root.path}$_sep'
      'docs');

  Directory get entriesDir => Directory('${root.path}$_sep'
      'docs$_sep'
      'log$_sep'
      'entries');

  File get summaryFile => File('${root.path}$_sep'
      'docs$_sep'
      'work_log.md');

  File get archiveFile => File('${root.path}$_sep'
      'docs$_sep'
      'work_log_archive.md');

  File get indexFile => File('${root.path}$_sep'
      'docs$_sep'
      'work_log_index.md');

  File get decisionsFile => File('${root.path}$_sep'
      'docs$_sep'
      'decisions.md');

  File get handoffFile => File('${root.path}$_sep'
      'docs$_sep'
      'handoff.md');

  /// Reads every entry file, ordered by file name.
  List<LogEntry> readEntries() {
    final entries = <LogEntry>[];
    if (!entriesDir.existsSync()) {
      return entries;
    }
    final files = entriesDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.md'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      entries.add(_parseEntry(file));
    }
    return entries;
  }

  LogEntry _parseEntry(File file) {
    final text = readText(file);
    final header = _entryHeaderPattern.firstMatch(text.split('\n').first);
    final explicitCommit = _entryCommitPattern.firstMatch(text);
    final legacyCommit = _legacyEntryCommitPattern.firstMatch(text);
    final commit = explicitCommit?.group(1) ?? legacyCommit?.group(1)?.trim();
    final missing = <String>[
      for (final field in kEntryFields)
        if (!RegExp('^- $field:', multiLine: true).hasMatch(text)) field,
    ];
    return LogEntry(
      fileName: file.uri.pathSegments.last,
      path: file.path,
      timestamp: header?.group(1) == null
          ? null
          : '${header!.group(1)} ${header.group(2)}',
      title: header?.group(3),
      commit: commit,
      commitIsExplicit: explicitCommit != null,
      missingFields: missing,
    );
  }

  /// Entries sorted newest first.
  List<LogEntry> sortedEntries(List<LogEntry> entries) {
    final valid = entries.where((entry) => entry.hasValidHeader).toList()
      ..sort((a, b) => b.timestamp!.compareTo(a.timestamp!));
    return valid;
  }

  /// The text of the generated active summary.
  String buildSummary(List<LogEntry> entries, {int activeCount = kDefaultActiveCount}) {
    final ordered = sortedEntries(entries);
    final active = ordered.take(activeCount).toList();
    final archived = ordered.skip(activeCount).toList();
    final buffer = StringBuffer()
      ..writeln('# Work Log (Active)')
      ..writeln()
      ..writeln('<!-- Generated by `dart run tool/work_log.dart write`. Do not edit by hand. -->')
      ..writeln();
    for (final entry in active) {
      final commit = entry.commit == null ? '' : ' `${entry.commit}`';
      buffer.writeln(
        '- [${entry.timestamp}] ${entry.title}$commit '
        '([entry](log/entries/${entry.fileName}))',
      );
    }
    buffer
      ..writeln()
      ..writeln(
        '<!-- ${ordered.length} entries total: ${active.length} active, '
        '${archived.length} archived. -->',
      )
      ..writeln()
      ..writeln('- Full entries: `docs/log/entries/`')
      ..writeln(
        '- Older entries: [archive](work_log_archive.md) | '
        'stable decisions: [decisions](decisions.md)',
      );
    return buffer.toString();
  }

  /// Regenerates navigation data derived from immutable entry files.
  ///
  /// The index body remains manually maintained; only its snapshot date is
  /// synchronized. Missing archive links are appended to a managed section so
  /// aging an entry out of the active window never leaves it unreferenced.
  void writeGeneratedFiles({int activeCount = kDefaultActiveCount}) {
    final entries = readEntries();
    final ordered = sortedEntries(entries);
    summaryFile.writeAsStringSync(
      buildSummary(entries, activeCount: activeCount),
    );
    _syncIndexSnapshot(ordered, activeCount: activeCount);
    _syncArchiveReferences(ordered, activeCount: activeCount);
  }

  void _syncIndexSnapshot(
    List<LogEntry> ordered, {
    required int activeCount,
  }) {
    if (!indexFile.existsSync() || ordered.isEmpty || activeCount <= 0) {
      return;
    }
    final text = readText(indexFile);
    final newestDate = ordered.first.timestamp!.split(' ').first;
    final updated = text.replaceFirstMapped(
      _indexSnapshotPattern,
      (_) => 'Navigation snapshot through $newestDate',
    );
    if (updated != text) {
      indexFile.writeAsStringSync(updated);
    }
  }

  void _syncArchiveReferences(
    List<LogEntry> ordered, {
    required int activeCount,
  }) {
    final original = archiveFile.existsSync()
        ? readText(archiveFile)
        : '# Work Log Archive\n\n'
              '> Navigation only. Full entries live under '
              '`docs/log/entries/`.\n';
    final stableContent = original
        .replaceAll(_autoArchiveBlockPattern, '')
        .trimRight();
    final missing = ordered
        .skip(activeCount)
        .where((entry) => !stableContent.contains(entry.fileName))
        .toList();

    final buffer = StringBuffer(stableContent);
    if (missing.isNotEmpty) {
      if (buffer.length > 0) {
        buffer.writeln();
        buffer.writeln();
      }
      buffer
        ..writeln(_autoArchiveStartMarker)
        ..writeln('## Additional archived entries (auto-generated)');
      for (final entry in missing) {
        buffer.writeln(
          '- [${entry.timestamp}] ${entry.title} '
          '([entry](log/entries/${entry.fileName}))',
        );
      }
      buffer.writeln(_autoArchiveEndMarker);
    }
    final updated = '${buffer.toString().trimRight()}\n';
    if (updated != original) {
      archiveFile.writeAsStringSync(updated);
    }
  }

  /// Runs every harness rule and returns the findings.
  List<LogProblem> lint({
    int activeCount = kDefaultActiveCount,
    bool lookupCommits = true,
  }) {
    final problems = <LogProblem>[];
    if (!entriesDir.existsSync()) {
      problems.add(LogProblem('entry-name', 'Entry directory not found: ${entriesDir.path}'));
      return problems;
    }

    final entries = readEntries();
    final ordered = sortedEntries(entries);
    final active = ordered.take(activeCount).toList();
    final seen = <String, String>{};

    for (final entry in entries) {
      if (!_entryNamePattern.hasMatch(entry.fileName)) {
        problems.add(LogProblem('entry-name', 'Invalid entry file name: ${entry.fileName}'));
      }
      if (!entry.hasValidHeader) {
        problems.add(
          LogProblem(
            'entry-timestamp',
            "Entry has no valid '# [yyyy-mm-dd hh:mm] Title' header: ${entry.fileName}",
          ),
        );
        continue;
      }
      final stamp = entry.fileStamp!;
      if (!entry.fileName.startsWith('$stamp-')) {
        problems.add(
          LogProblem(
            'entry-timestamp',
            'File name and header disagree on the timestamp: ${entry.fileName}',
          ),
        );
      }
      final timestamp = entry.timestamp!;
      final previous = seen[timestamp];
      if (previous != null) {
        problems.add(
          LogProblem(
            'entry-duplicate',
            'Duplicate entry timestamp $timestamp: '
            '${entry.fileName} and $previous',
          ),
        );
      } else {
        seen[timestamp] = entry.fileName;
      }
      if (entry.missingFields.isNotEmpty) {
        problems.add(
          LogProblem(
            'entry-fields',
            'Entry is missing ${entry.missingFields.join(', ')}: ${entry.fileName}',
          ),
        );
      }
    }

    final generated = buildSummary(entries, activeCount: activeCount);
    final summaryText = readText(summaryFile);
    if (summaryText != generated) {
      problems.add(
        LogProblem(
          'summary-stale',
          'docs/work_log.md is stale; run `dart run tool/work_log.dart write`.',
        ),
      );
    }

    final archiveText = readText(archiveFile);
    for (final entry in entries) {
      if (!summaryText.contains(entry.fileName) && !archiveText.contains(entry.fileName)) {
        problems.add(
          LogProblem(
            'entry-unreferenced',
            'Entry file is not referenced from work_log.md or '
            'work_log_archive.md: ${entry.fileName}',
          ),
        );
      }
    }

    for (final doc in <File>[summaryFile, archiveFile, indexFile, decisionsFile]) {
      if (!doc.existsSync()) {
        continue;
      }
      final text = readText(doc);
      for (final match in _markdownLinkPattern.allMatches(text)) {
        final target = match.group(1)!;
        if (target.startsWith('http://') ||
            target.startsWith('https://') ||
            target.startsWith('mailto:')) {
          continue;
        }
        final resolved = File('${doc.parent.path}$_sep$target');
        if (!resolved.existsSync()) {
          problems.add(
            LogProblem(
              'broken-link',
              'Broken link in ${_relative(doc.path)}: $target',
            ),
          );
        }
      }
    }

    final indexText = readText(indexFile);
    final snapshot = _indexSnapshotPattern.firstMatch(indexText)?.group(1);
    if (snapshot == null) {
      problems.add(
        LogProblem(
          'index-snapshot',
          'Index is missing the "Navigation snapshot through <date>" line',
        ),
      );
    } else if (active.isNotEmpty) {
      final newest = active.first.timestamp!.split(' ').first;
      if (snapshot != newest) {
        problems.add(
          LogProblem(
            'index-snapshot',
            'Index snapshot says $snapshot but the newest active entry is $newest',
          ),
        );
      }
    }

    final decisionsText = readText(decisionsFile);
    for (final block in decisionsText.split(RegExp('^## ', multiLine: true))) {
      if (!block.startsWith(RegExp(r'D-\d+'))) {
        continue;
      }
      final title = block.split('\n').first.trim();
      for (final field in kDecisionFields) {
        if (!block.contains('- $field')) {
          problems.add(
            LogProblem('decisions-fields', "Decision $title is missing '- $field'"),
          );
        }
      }
    }

    final handoffText = readText(handoffFile);
    for (final section in kHandoffSections) {
      if (!handoffText.contains(section)) {
        problems.add(
          LogProblem('handoff-sections', "Handoff is missing section '$section'"),
        );
      }
    }

    if (lookupCommits) {
      final subjects = _gitSubjects();
      if (subjects.isNotEmpty) {
        final activeNames = active.map((entry) => entry.fileName).toSet();
        for (final entry in entries) {
          final commit = entry.commit;
          if (commit == null ||
              !entry.commitIsExplicit ||
              !activeNames.contains(entry.fileName)) {
            continue;
          }
          if (!subjects.contains(commit)) {
            problems.add(
              LogProblem(
                'commit-subject',
                'Entry commit subject not found in git history: $commit '
                '(${entry.fileName})',
                isWarning: true,
              ),
            );
          }
        }
      }
    }

    return problems;
  }

  List<String> _gitSubjects() {
    try {
      final result = Process.runSync(
        'git',
        <String>['-C', root.path, 'log', '--pretty=format:%s', '-n', '500'],
      );
      if (result.exitCode != 0) {
        return const <String>[];
      }
      return (result.stdout as String)
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
    } on ProcessException {
      return const <String>[];
    }
  }

  String _relative(String path) {
    final prefix = '${root.path}$_sep';
    final normalized = path.replaceAll('/', _sep);
    if (normalized.startsWith(prefix)) {
      return normalized.substring(prefix.length).replaceAll(_sep, '/');
    }
    return normalized;
  }

  /// Reads a file as UTF-8 and normalizes line endings to `\n`.
  static String readText(File file) {
    if (!file.existsSync()) {
      return '';
    }
    return file.readAsStringSync().replaceAll('\r\n', '\n');
  }
}

int _run(List<String> args) {
  final root = Directory.current;
  final harness = WorkLogHarness(root);

  if (args.isEmpty) {
    stdout.writeln('Usage: dart run tool/work_log.dart <write|check|print>');
    return 2;
  }

  switch (args.first) {
    case 'write':
      final entries = harness.sortedEntries(harness.readEntries());
      harness.writeGeneratedFiles();
      stdout.writeln(
        'Wrote work-log navigation (summary, index snapshot, and archive refs; '
        '${entries.take(kDefaultActiveCount).length} active of ${entries.length} entries).',
      );
      return 0;
    case 'print':
      stdout.write(harness.buildSummary(harness.readEntries()));
      return 0;
    case 'check':
      final problems = harness.lint();
      final errors = problems.where((problem) => !problem.isWarning).toList();
      final warnings = problems.where((problem) => problem.isWarning).toList();
      if (errors.isNotEmpty) {
        stdout.writeln(
          'Work log lint failed (${errors.length} error(s), ${warnings.length} warning(s)):',
        );
        for (final problem in errors) {
          stdout.writeln('  $problem');
        }
      }
      if (warnings.isNotEmpty) {
        stdout.writeln('Warnings (${warnings.length}):');
        for (final problem in warnings) {
          stdout.writeln('  $problem');
        }
      }
      if (errors.isNotEmpty) {
        return 1;
      }
      stdout.writeln(
        'Work log lint passed (0 errors, ${warnings.length} warning(s)).',
      );
      return 0;
    default:
      stdout.writeln('Unknown command: ${args.first}');
      stdout.writeln('Usage: dart run tool/work_log.dart <write|check|print>');
      return 2;
  }
}

void main(List<String> args) {
  exitCode = _run(args);
}
, multiLine: true);
final RegExp _legacyEntryCommitPattern = RegExp(
  r'^- Commit: (?!`)(.+?)\s*
final RegExp _markdownLinkPattern = RegExp(r'\]\(([^)#]+?)\)');

final RegExp _indexSnapshotPattern = RegExp(
  r'Navigation snapshot through (\d{4}-\d{2}-\d{2})',
);

const String _autoArchiveStartMarker =
    '<!-- BEGIN AUTO-GENERATED WORK LOG REFERENCES -->';
const String _autoArchiveEndMarker =
    '<!-- END AUTO-GENERATED WORK LOG REFERENCES -->';
final RegExp _autoArchiveBlockPattern = RegExp(
  r'\n?<!-- BEGIN AUTO-GENERATED WORK LOG REFERENCES -->[\s\S]*?'
  r'<!-- END AUTO-GENERATED WORK LOG REFERENCES -->\s*',
);

/// A single task entry parsed from `docs/log/entries/`.
class LogEntry {
  LogEntry({
    required this.fileName,
    required this.path,
    this.timestamp,
    this.title,
    this.commit,
    this.missingFields = const <String>[],
  });

  final String fileName;
  final String path;
  final String? timestamp;
  final String? title;
  final String? commit;
  final List<String> missingFields;

  bool get hasValidHeader => timestamp != null && title != null;

  /// `2026-10-19-2130` style prefix used by the entry file name.
  String? get fileStamp {
    final value = timestamp;
    if (value == null) {
      return null;
    }
    final parts = value.split(' ');
    if (parts.length != 2) {
      return null;
    }
    return '${parts[0]}-${parts[1].replaceAll(':', '')}';
  }
}

/// A single lint finding.
class LogProblem {
  LogProblem(this.rule, this.message, {this.isWarning = false});

  final String rule;
  final String message;
  final bool isWarning;

  @override
  String toString() => '[$rule] $message';
}

/// Reads and validates the work-log documents of a repository.
class WorkLogHarness {
  WorkLogHarness(this.root);

  final Directory root;

  static final String _sep = Platform.pathSeparator;

  Directory get docsDir => Directory('${root.path}$_sep'
      'docs');

  Directory get entriesDir => Directory('${root.path}$_sep'
      'docs$_sep'
      'log$_sep'
      'entries');

  File get summaryFile => File('${root.path}$_sep'
      'docs$_sep'
      'work_log.md');

  File get archiveFile => File('${root.path}$_sep'
      'docs$_sep'
      'work_log_archive.md');

  File get indexFile => File('${root.path}$_sep'
      'docs$_sep'
      'work_log_index.md');

  File get decisionsFile => File('${root.path}$_sep'
      'docs$_sep'
      'decisions.md');

  File get handoffFile => File('${root.path}$_sep'
      'docs$_sep'
      'handoff.md');

  /// Reads every entry file, ordered by file name.
  List<LogEntry> readEntries() {
    final entries = <LogEntry>[];
    if (!entriesDir.existsSync()) {
      return entries;
    }
    final files = entriesDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.md'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      entries.add(_parseEntry(file));
    }
    return entries;
  }

  LogEntry _parseEntry(File file) {
    final text = readText(file);
    final header = _entryHeaderPattern.firstMatch(text.split('\n').first);
    final commit = _entryCommitPattern.firstMatch(text)?.group(1);
    final missing = <String>[
      for (final field in kEntryFields)
        if (!RegExp('^- $field:', multiLine: true).hasMatch(text)) field,
    ];
    return LogEntry(
      fileName: file.uri.pathSegments.last,
      path: file.path,
      timestamp: header?.group(1) == null
          ? null
          : '${header!.group(1)} ${header.group(2)}',
      title: header?.group(3),
      commit: commit,
      missingFields: missing,
    );
  }

  /// Entries sorted newest first.
  List<LogEntry> sortedEntries(List<LogEntry> entries) {
    final valid = entries.where((entry) => entry.hasValidHeader).toList()
      ..sort((a, b) => b.timestamp!.compareTo(a.timestamp!));
    return valid;
  }

  /// The text of the generated active summary.
  String buildSummary(List<LogEntry> entries, {int activeCount = kDefaultActiveCount}) {
    final ordered = sortedEntries(entries);
    final active = ordered.take(activeCount).toList();
    final archived = ordered.skip(activeCount).toList();
    final buffer = StringBuffer()
      ..writeln('# Work Log (Active)')
      ..writeln()
      ..writeln('<!-- Generated by `dart run tool/work_log.dart write`. Do not edit by hand. -->')
      ..writeln();
    for (final entry in active) {
      final commit = entry.commit == null ? '' : ' `${entry.commit}`';
      buffer.writeln(
        '- [${entry.timestamp}] ${entry.title}$commit '
        '([entry](log/entries/${entry.fileName}))',
      );
    }
    buffer
      ..writeln()
      ..writeln(
        '<!-- ${ordered.length} entries total: ${active.length} active, '
        '${archived.length} archived. -->',
      )
      ..writeln()
      ..writeln('- Full entries: `docs/log/entries/`')
      ..writeln(
        '- Older entries: [archive](work_log_archive.md) | '
        'stable decisions: [decisions](decisions.md)',
      );
    return buffer.toString();
  }

  /// Regenerates navigation data derived from immutable entry files.
  ///
  /// The index body remains manually maintained; only its snapshot date is
  /// synchronized. Missing archive links are appended to a managed section so
  /// aging an entry out of the active window never leaves it unreferenced.
  void writeGeneratedFiles({int activeCount = kDefaultActiveCount}) {
    final entries = readEntries();
    final ordered = sortedEntries(entries);
    summaryFile.writeAsStringSync(
      buildSummary(entries, activeCount: activeCount),
    );
    _syncIndexSnapshot(ordered, activeCount: activeCount);
    _syncArchiveReferences(ordered, activeCount: activeCount);
  }

  void _syncIndexSnapshot(
    List<LogEntry> ordered, {
    required int activeCount,
  }) {
    if (!indexFile.existsSync() || ordered.isEmpty || activeCount <= 0) {
      return;
    }
    final text = readText(indexFile);
    final newestDate = ordered.first.timestamp!.split(' ').first;
    final updated = text.replaceFirstMapped(
      _indexSnapshotPattern,
      (_) => 'Navigation snapshot through $newestDate',
    );
    if (updated != text) {
      indexFile.writeAsStringSync(updated);
    }
  }

  void _syncArchiveReferences(
    List<LogEntry> ordered, {
    required int activeCount,
  }) {
    final original = archiveFile.existsSync()
        ? readText(archiveFile)
        : '# Work Log Archive\n\n'
              '> Navigation only. Full entries live under '
              '`docs/log/entries/`.\n';
    final stableContent = original
        .replaceAll(_autoArchiveBlockPattern, '')
        .trimRight();
    final missing = ordered
        .skip(activeCount)
        .where((entry) => !stableContent.contains(entry.fileName))
        .toList();

    final buffer = StringBuffer(stableContent);
    if (missing.isNotEmpty) {
      if (buffer.length > 0) {
        buffer.writeln();
        buffer.writeln();
      }
      buffer
        ..writeln(_autoArchiveStartMarker)
        ..writeln('## Additional archived entries (auto-generated)');
      for (final entry in missing) {
        buffer.writeln(
          '- [${entry.timestamp}] ${entry.title} '
          '([entry](log/entries/${entry.fileName}))',
        );
      }
      buffer.writeln(_autoArchiveEndMarker);
    }
    final updated = '${buffer.toString().trimRight()}\n';
    if (updated != original) {
      archiveFile.writeAsStringSync(updated);
    }
  }

  /// Runs every harness rule and returns the findings.
  List<LogProblem> lint({
    int activeCount = kDefaultActiveCount,
    bool lookupCommits = true,
  }) {
    final problems = <LogProblem>[];
    if (!entriesDir.existsSync()) {
      problems.add(LogProblem('entry-name', 'Entry directory not found: ${entriesDir.path}'));
      return problems;
    }

    final entries = readEntries();
    final ordered = sortedEntries(entries);
    final active = ordered.take(activeCount).toList();
    final seen = <String, String>{};

    for (final entry in entries) {
      if (!_entryNamePattern.hasMatch(entry.fileName)) {
        problems.add(LogProblem('entry-name', 'Invalid entry file name: ${entry.fileName}'));
      }
      if (!entry.hasValidHeader) {
        problems.add(
          LogProblem(
            'entry-timestamp',
            "Entry has no valid '# [yyyy-mm-dd hh:mm] Title' header: ${entry.fileName}",
          ),
        );
        continue;
      }
      final stamp = entry.fileStamp!;
      if (!entry.fileName.startsWith('$stamp-')) {
        problems.add(
          LogProblem(
            'entry-timestamp',
            'File name and header disagree on the timestamp: ${entry.fileName}',
          ),
        );
      }
      final timestamp = entry.timestamp!;
      final previous = seen[timestamp];
      if (previous != null) {
        problems.add(
          LogProblem(
            'entry-duplicate',
            'Duplicate entry timestamp $timestamp: '
            '${entry.fileName} and $previous',
          ),
        );
      } else {
        seen[timestamp] = entry.fileName;
      }
      if (entry.missingFields.isNotEmpty) {
        problems.add(
          LogProblem(
            'entry-fields',
            'Entry is missing ${entry.missingFields.join(', ')}: ${entry.fileName}',
          ),
        );
      }
    }

    final generated = buildSummary(entries, activeCount: activeCount);
    final summaryText = readText(summaryFile);
    if (summaryText != generated) {
      problems.add(
        LogProblem(
          'summary-stale',
          'docs/work_log.md is stale; run `dart run tool/work_log.dart write`.',
        ),
      );
    }

    final archiveText = readText(archiveFile);
    for (final entry in entries) {
      if (!summaryText.contains(entry.fileName) && !archiveText.contains(entry.fileName)) {
        problems.add(
          LogProblem(
            'entry-unreferenced',
            'Entry file is not referenced from work_log.md or '
            'work_log_archive.md: ${entry.fileName}',
          ),
        );
      }
    }

    for (final doc in <File>[summaryFile, archiveFile, indexFile, decisionsFile]) {
      if (!doc.existsSync()) {
        continue;
      }
      final text = readText(doc);
      for (final match in _markdownLinkPattern.allMatches(text)) {
        final target = match.group(1)!;
        if (target.startsWith('http://') ||
            target.startsWith('https://') ||
            target.startsWith('mailto:')) {
          continue;
        }
        final resolved = File('${doc.parent.path}$_sep$target');
        if (!resolved.existsSync()) {
          problems.add(
            LogProblem(
              'broken-link',
              'Broken link in ${_relative(doc.path)}: $target',
            ),
          );
        }
      }
    }

    final indexText = readText(indexFile);
    final snapshot = _indexSnapshotPattern.firstMatch(indexText)?.group(1);
    if (snapshot == null) {
      problems.add(
        LogProblem(
          'index-snapshot',
          'Index is missing the "Navigation snapshot through <date>" line',
        ),
      );
    } else if (active.isNotEmpty) {
      final newest = active.first.timestamp!.split(' ').first;
      if (snapshot != newest) {
        problems.add(
          LogProblem(
            'index-snapshot',
            'Index snapshot says $snapshot but the newest active entry is $newest',
          ),
        );
      }
    }

    final decisionsText = readText(decisionsFile);
    for (final block in decisionsText.split(RegExp('^## ', multiLine: true))) {
      if (!block.startsWith(RegExp(r'D-\d+'))) {
        continue;
      }
      final title = block.split('\n').first.trim();
      for (final field in kDecisionFields) {
        if (!block.contains('- $field')) {
          problems.add(
            LogProblem('decisions-fields', "Decision $title is missing '- $field'"),
          );
        }
      }
    }

    final handoffText = readText(handoffFile);
    for (final section in kHandoffSections) {
      if (!handoffText.contains(section)) {
        problems.add(
          LogProblem('handoff-sections', "Handoff is missing section '$section'"),
        );
      }
    }

    if (lookupCommits) {
      final subjects = _gitSubjects();
      if (subjects.isNotEmpty) {
        final activeNames = active.map((entry) => entry.fileName).toSet();
        for (final entry in entries) {
          final commit = entry.commit;
          if (commit == null || !activeNames.contains(entry.fileName)) {
            continue;
          }
          if (!subjects.contains(commit)) {
            problems.add(
              LogProblem(
                'commit-subject',
                'Entry commit subject not found in git history: $commit '
                '(${entry.fileName})',
                isWarning: true,
              ),
            );
          }
        }
      }
    }

    return problems;
  }

  List<String> _gitSubjects() {
    try {
      final result = Process.runSync(
        'git',
        <String>['-C', root.path, 'log', '--pretty=format:%s', '-n', '500'],
      );
      if (result.exitCode != 0) {
        return const <String>[];
      }
      return (result.stdout as String)
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
    } on ProcessException {
      return const <String>[];
    }
  }

  String _relative(String path) {
    final prefix = '${root.path}$_sep';
    final normalized = path.replaceAll('/', _sep);
    if (normalized.startsWith(prefix)) {
      return normalized.substring(prefix.length).replaceAll(_sep, '/');
    }
    return normalized;
  }

  /// Reads a file as UTF-8 and normalizes line endings to `\n`.
  static String readText(File file) {
    if (!file.existsSync()) {
      return '';
    }
    return file.readAsStringSync().replaceAll('\r\n', '\n');
  }
}

int _run(List<String> args) {
  final root = Directory.current;
  final harness = WorkLogHarness(root);

  if (args.isEmpty) {
    stdout.writeln('Usage: dart run tool/work_log.dart <write|check|print>');
    return 2;
  }

  switch (args.first) {
    case 'write':
      final entries = harness.sortedEntries(harness.readEntries());
      harness.writeGeneratedFiles();
      stdout.writeln(
        'Wrote work-log navigation (summary, index snapshot, and archive refs; '
        '${entries.take(kDefaultActiveCount).length} active of ${entries.length} entries).',
      );
      return 0;
    case 'print':
      stdout.write(harness.buildSummary(harness.readEntries()));
      return 0;
    case 'check':
      final problems = harness.lint();
      final errors = problems.where((problem) => !problem.isWarning).toList();
      final warnings = problems.where((problem) => problem.isWarning).toList();
      if (errors.isNotEmpty) {
        stdout.writeln(
          'Work log lint failed (${errors.length} error(s), ${warnings.length} warning(s)):',
        );
        for (final problem in errors) {
          stdout.writeln('  $problem');
        }
      }
      if (warnings.isNotEmpty) {
        stdout.writeln('Warnings (${warnings.length}):');
        for (final problem in warnings) {
          stdout.writeln('  $problem');
        }
      }
      if (errors.isNotEmpty) {
        return 1;
      }
      stdout.writeln(
        'Work log lint passed (0 errors, ${warnings.length} warning(s)).',
      );
      return 0;
    default:
      stdout.writeln('Unknown command: ${args.first}');
      stdout.writeln('Usage: dart run tool/work_log.dart <write|check|print>');
      return 2;
  }
}

void main(List<String> args) {
  exitCode = _run(args);
}
,
  multiLine: true,
);

final RegExp _markdownLinkPattern = RegExp(r'\]\(([^)#]+?)\)');

final RegExp _indexSnapshotPattern = RegExp(
  r'Navigation snapshot through (\d{4}-\d{2}-\d{2})',
);

const String _autoArchiveStartMarker =
    '<!-- BEGIN AUTO-GENERATED WORK LOG REFERENCES -->';
const String _autoArchiveEndMarker =
    '<!-- END AUTO-GENERATED WORK LOG REFERENCES -->';
final RegExp _autoArchiveBlockPattern = RegExp(
  r'\n?<!-- BEGIN AUTO-GENERATED WORK LOG REFERENCES -->[\s\S]*?'
  r'<!-- END AUTO-GENERATED WORK LOG REFERENCES -->\s*',
);

/// A single task entry parsed from `docs/log/entries/`.
class LogEntry {
  LogEntry({
    required this.fileName,
    required this.path,
    this.timestamp,
    this.title,
    this.commit,
    this.missingFields = const <String>[],
  });

  final String fileName;
  final String path;
  final String? timestamp;
  final String? title;
  final String? commit;
  final List<String> missingFields;

  bool get hasValidHeader => timestamp != null && title != null;

  /// `2026-10-19-2130` style prefix used by the entry file name.
  String? get fileStamp {
    final value = timestamp;
    if (value == null) {
      return null;
    }
    final parts = value.split(' ');
    if (parts.length != 2) {
      return null;
    }
    return '${parts[0]}-${parts[1].replaceAll(':', '')}';
  }
}

/// A single lint finding.
class LogProblem {
  LogProblem(this.rule, this.message, {this.isWarning = false});

  final String rule;
  final String message;
  final bool isWarning;

  @override
  String toString() => '[$rule] $message';
}

/// Reads and validates the work-log documents of a repository.
class WorkLogHarness {
  WorkLogHarness(this.root);

  final Directory root;

  static final String _sep = Platform.pathSeparator;

  Directory get docsDir => Directory('${root.path}$_sep'
      'docs');

  Directory get entriesDir => Directory('${root.path}$_sep'
      'docs$_sep'
      'log$_sep'
      'entries');

  File get summaryFile => File('${root.path}$_sep'
      'docs$_sep'
      'work_log.md');

  File get archiveFile => File('${root.path}$_sep'
      'docs$_sep'
      'work_log_archive.md');

  File get indexFile => File('${root.path}$_sep'
      'docs$_sep'
      'work_log_index.md');

  File get decisionsFile => File('${root.path}$_sep'
      'docs$_sep'
      'decisions.md');

  File get handoffFile => File('${root.path}$_sep'
      'docs$_sep'
      'handoff.md');

  /// Reads every entry file, ordered by file name.
  List<LogEntry> readEntries() {
    final entries = <LogEntry>[];
    if (!entriesDir.existsSync()) {
      return entries;
    }
    final files = entriesDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.md'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      entries.add(_parseEntry(file));
    }
    return entries;
  }

  LogEntry _parseEntry(File file) {
    final text = readText(file);
    final header = _entryHeaderPattern.firstMatch(text.split('\n').first);
    final commit = _entryCommitPattern.firstMatch(text)?.group(1);
    final missing = <String>[
      for (final field in kEntryFields)
        if (!RegExp('^- $field:', multiLine: true).hasMatch(text)) field,
    ];
    return LogEntry(
      fileName: file.uri.pathSegments.last,
      path: file.path,
      timestamp: header?.group(1) == null
          ? null
          : '${header!.group(1)} ${header.group(2)}',
      title: header?.group(3),
      commit: commit,
      missingFields: missing,
    );
  }

  /// Entries sorted newest first.
  List<LogEntry> sortedEntries(List<LogEntry> entries) {
    final valid = entries.where((entry) => entry.hasValidHeader).toList()
      ..sort((a, b) => b.timestamp!.compareTo(a.timestamp!));
    return valid;
  }

  /// The text of the generated active summary.
  String buildSummary(List<LogEntry> entries, {int activeCount = kDefaultActiveCount}) {
    final ordered = sortedEntries(entries);
    final active = ordered.take(activeCount).toList();
    final archived = ordered.skip(activeCount).toList();
    final buffer = StringBuffer()
      ..writeln('# Work Log (Active)')
      ..writeln()
      ..writeln('<!-- Generated by `dart run tool/work_log.dart write`. Do not edit by hand. -->')
      ..writeln();
    for (final entry in active) {
      final commit = entry.commit == null ? '' : ' `${entry.commit}`';
      buffer.writeln(
        '- [${entry.timestamp}] ${entry.title}$commit '
        '([entry](log/entries/${entry.fileName}))',
      );
    }
    buffer
      ..writeln()
      ..writeln(
        '<!-- ${ordered.length} entries total: ${active.length} active, '
        '${archived.length} archived. -->',
      )
      ..writeln()
      ..writeln('- Full entries: `docs/log/entries/`')
      ..writeln(
        '- Older entries: [archive](work_log_archive.md) | '
        'stable decisions: [decisions](decisions.md)',
      );
    return buffer.toString();
  }

  /// Regenerates navigation data derived from immutable entry files.
  ///
  /// The index body remains manually maintained; only its snapshot date is
  /// synchronized. Missing archive links are appended to a managed section so
  /// aging an entry out of the active window never leaves it unreferenced.
  void writeGeneratedFiles({int activeCount = kDefaultActiveCount}) {
    final entries = readEntries();
    final ordered = sortedEntries(entries);
    summaryFile.writeAsStringSync(
      buildSummary(entries, activeCount: activeCount),
    );
    _syncIndexSnapshot(ordered, activeCount: activeCount);
    _syncArchiveReferences(ordered, activeCount: activeCount);
  }

  void _syncIndexSnapshot(
    List<LogEntry> ordered, {
    required int activeCount,
  }) {
    if (!indexFile.existsSync() || ordered.isEmpty || activeCount <= 0) {
      return;
    }
    final text = readText(indexFile);
    final newestDate = ordered.first.timestamp!.split(' ').first;
    final updated = text.replaceFirstMapped(
      _indexSnapshotPattern,
      (_) => 'Navigation snapshot through $newestDate',
    );
    if (updated != text) {
      indexFile.writeAsStringSync(updated);
    }
  }

  void _syncArchiveReferences(
    List<LogEntry> ordered, {
    required int activeCount,
  }) {
    final original = archiveFile.existsSync()
        ? readText(archiveFile)
        : '# Work Log Archive\n\n'
              '> Navigation only. Full entries live under '
              '`docs/log/entries/`.\n';
    final stableContent = original
        .replaceAll(_autoArchiveBlockPattern, '')
        .trimRight();
    final missing = ordered
        .skip(activeCount)
        .where((entry) => !stableContent.contains(entry.fileName))
        .toList();

    final buffer = StringBuffer(stableContent);
    if (missing.isNotEmpty) {
      if (buffer.length > 0) {
        buffer.writeln();
        buffer.writeln();
      }
      buffer
        ..writeln(_autoArchiveStartMarker)
        ..writeln('## Additional archived entries (auto-generated)');
      for (final entry in missing) {
        buffer.writeln(
          '- [${entry.timestamp}] ${entry.title} '
          '([entry](log/entries/${entry.fileName}))',
        );
      }
      buffer.writeln(_autoArchiveEndMarker);
    }
    final updated = '${buffer.toString().trimRight()}\n';
    if (updated != original) {
      archiveFile.writeAsStringSync(updated);
    }
  }

  /// Runs every harness rule and returns the findings.
  List<LogProblem> lint({
    int activeCount = kDefaultActiveCount,
    bool lookupCommits = true,
  }) {
    final problems = <LogProblem>[];
    if (!entriesDir.existsSync()) {
      problems.add(LogProblem('entry-name', 'Entry directory not found: ${entriesDir.path}'));
      return problems;
    }

    final entries = readEntries();
    final ordered = sortedEntries(entries);
    final active = ordered.take(activeCount).toList();
    final seen = <String, String>{};

    for (final entry in entries) {
      if (!_entryNamePattern.hasMatch(entry.fileName)) {
        problems.add(LogProblem('entry-name', 'Invalid entry file name: ${entry.fileName}'));
      }
      if (!entry.hasValidHeader) {
        problems.add(
          LogProblem(
            'entry-timestamp',
            "Entry has no valid '# [yyyy-mm-dd hh:mm] Title' header: ${entry.fileName}",
          ),
        );
        continue;
      }
      final stamp = entry.fileStamp!;
      if (!entry.fileName.startsWith('$stamp-')) {
        problems.add(
          LogProblem(
            'entry-timestamp',
            'File name and header disagree on the timestamp: ${entry.fileName}',
          ),
        );
      }
      final timestamp = entry.timestamp!;
      final previous = seen[timestamp];
      if (previous != null) {
        problems.add(
          LogProblem(
            'entry-duplicate',
            'Duplicate entry timestamp $timestamp: '
            '${entry.fileName} and $previous',
          ),
        );
      } else {
        seen[timestamp] = entry.fileName;
      }
      if (entry.missingFields.isNotEmpty) {
        problems.add(
          LogProblem(
            'entry-fields',
            'Entry is missing ${entry.missingFields.join(', ')}: ${entry.fileName}',
          ),
        );
      }
    }

    final generated = buildSummary(entries, activeCount: activeCount);
    final summaryText = readText(summaryFile);
    if (summaryText != generated) {
      problems.add(
        LogProblem(
          'summary-stale',
          'docs/work_log.md is stale; run `dart run tool/work_log.dart write`.',
        ),
      );
    }

    final archiveText = readText(archiveFile);
    for (final entry in entries) {
      if (!summaryText.contains(entry.fileName) && !archiveText.contains(entry.fileName)) {
        problems.add(
          LogProblem(
            'entry-unreferenced',
            'Entry file is not referenced from work_log.md or '
            'work_log_archive.md: ${entry.fileName}',
          ),
        );
      }
    }

    for (final doc in <File>[summaryFile, archiveFile, indexFile, decisionsFile]) {
      if (!doc.existsSync()) {
        continue;
      }
      final text = readText(doc);
      for (final match in _markdownLinkPattern.allMatches(text)) {
        final target = match.group(1)!;
        if (target.startsWith('http://') ||
            target.startsWith('https://') ||
            target.startsWith('mailto:')) {
          continue;
        }
        final resolved = File('${doc.parent.path}$_sep$target');
        if (!resolved.existsSync()) {
          problems.add(
            LogProblem(
              'broken-link',
              'Broken link in ${_relative(doc.path)}: $target',
            ),
          );
        }
      }
    }

    final indexText = readText(indexFile);
    final snapshot = _indexSnapshotPattern.firstMatch(indexText)?.group(1);
    if (snapshot == null) {
      problems.add(
        LogProblem(
          'index-snapshot',
          'Index is missing the "Navigation snapshot through <date>" line',
        ),
      );
    } else if (active.isNotEmpty) {
      final newest = active.first.timestamp!.split(' ').first;
      if (snapshot != newest) {
        problems.add(
          LogProblem(
            'index-snapshot',
            'Index snapshot says $snapshot but the newest active entry is $newest',
          ),
        );
      }
    }

    final decisionsText = readText(decisionsFile);
    for (final block in decisionsText.split(RegExp('^## ', multiLine: true))) {
      if (!block.startsWith(RegExp(r'D-\d+'))) {
        continue;
      }
      final title = block.split('\n').first.trim();
      for (final field in kDecisionFields) {
        if (!block.contains('- $field')) {
          problems.add(
            LogProblem('decisions-fields', "Decision $title is missing '- $field'"),
          );
        }
      }
    }

    final handoffText = readText(handoffFile);
    for (final section in kHandoffSections) {
      if (!handoffText.contains(section)) {
        problems.add(
          LogProblem('handoff-sections', "Handoff is missing section '$section'"),
        );
      }
    }

    if (lookupCommits) {
      final subjects = _gitSubjects();
      if (subjects.isNotEmpty) {
        final activeNames = active.map((entry) => entry.fileName).toSet();
        for (final entry in entries) {
          final commit = entry.commit;
          if (commit == null || !activeNames.contains(entry.fileName)) {
            continue;
          }
          if (!subjects.contains(commit)) {
            problems.add(
              LogProblem(
                'commit-subject',
                'Entry commit subject not found in git history: $commit '
                '(${entry.fileName})',
                isWarning: true,
              ),
            );
          }
        }
      }
    }

    return problems;
  }

  List<String> _gitSubjects() {
    try {
      final result = Process.runSync(
        'git',
        <String>['-C', root.path, 'log', '--pretty=format:%s', '-n', '500'],
      );
      if (result.exitCode != 0) {
        return const <String>[];
      }
      return (result.stdout as String)
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
    } on ProcessException {
      return const <String>[];
    }
  }

  String _relative(String path) {
    final prefix = '${root.path}$_sep';
    final normalized = path.replaceAll('/', _sep);
    if (normalized.startsWith(prefix)) {
      return normalized.substring(prefix.length).replaceAll(_sep, '/');
    }
    return normalized;
  }

  /// Reads a file as UTF-8 and normalizes line endings to `\n`.
  static String readText(File file) {
    if (!file.existsSync()) {
      return '';
    }
    return file.readAsStringSync().replaceAll('\r\n', '\n');
  }
}

int _run(List<String> args) {
  final root = Directory.current;
  final harness = WorkLogHarness(root);

  if (args.isEmpty) {
    stdout.writeln('Usage: dart run tool/work_log.dart <write|check|print>');
    return 2;
  }

  switch (args.first) {
    case 'write':
      final entries = harness.sortedEntries(harness.readEntries());
      harness.writeGeneratedFiles();
      stdout.writeln(
        'Wrote work-log navigation (summary, index snapshot, and archive refs; '
        '${entries.take(kDefaultActiveCount).length} active of ${entries.length} entries).',
      );
      return 0;
    case 'print':
      stdout.write(harness.buildSummary(harness.readEntries()));
      return 0;
    case 'check':
      final problems = harness.lint();
      final errors = problems.where((problem) => !problem.isWarning).toList();
      final warnings = problems.where((problem) => problem.isWarning).toList();
      if (errors.isNotEmpty) {
        stdout.writeln(
          'Work log lint failed (${errors.length} error(s), ${warnings.length} warning(s)):',
        );
        for (final problem in errors) {
          stdout.writeln('  $problem');
        }
      }
      if (warnings.isNotEmpty) {
        stdout.writeln('Warnings (${warnings.length}):');
        for (final problem in warnings) {
          stdout.writeln('  $problem');
        }
      }
      if (errors.isNotEmpty) {
        return 1;
      }
      stdout.writeln(
        'Work log lint passed (0 errors, ${warnings.length} warning(s)).',
      );
      return 0;
    default:
      stdout.writeln('Unknown command: ${args.first}');
      stdout.writeln('Usage: dart run tool/work_log.dart <write|check|print>');
      return 2;
  }
}

void main(List<String> args) {
  exitCode = _run(args);
}
