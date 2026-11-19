import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/lyric_review_queue.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/controllers/review_inbox_bulk_review.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';

final _created = DateTime(2026, 11, 1);
final _now = DateTime(2026, 11, 28, 9);

ProjectManifest _project(String id, {int lines = 2, int revision = 1}) {
  return ProjectManifest(
    id: id,
    name: '歌曲 $id',
    createdAt: _created,
    updatedAt: _created,
    revision: revision,
    lyricDocument: lines == 0
        ? null
        : LyricDocument(
            language: 'zh',
            lines: [
              for (var index = 0; index < lines; index++)
                LyricLine(
                  id: '$id-$index',
                  text: '第 ${index + 1} 行',
                  startTime: Duration(seconds: index * 3),
                  endTime: Duration(seconds: index * 3 + 3),
                  confidence: 30,
                ),
            ],
          ),
  );
}

/// Several projects behind the same revision check as the file store.
class _Repository implements ProjectRepository {
  _Repository(List<ProjectManifest> projects)
    : stored = {for (final project in projects) project.id: project};

  final Map<String, ProjectManifest> stored;
  final Set<String> failing = <String>{};
  final List<String> writes = <String>[];

  @override
  Future<ProjectManifest> updateProjectIfUnchanged(
    ProjectManifest project, {
    required int expectedRevision,
  }) async {
    if (failing.contains(project.id)) {
      throw const FileSystemException('disk full');
    }
    final current = stored[project.id]!;
    if (current.revision != expectedRevision) {
      throw ProjectUpdateConflictException(currentProject: current);
    }
    writes.add(project.id);
    return stored[project.id] = project.copyWith(
      revision: expectedRevision + 1,
    );
  }

  int pending(String id) {
    final queue = LyricReviewQueue.build(stored[id]!.lyricDocument!);
    return queue.needsReviewCount;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('marks every project and reports progress per project', () async {
    final projects = [_project('a'), _project('b', lines: 3)];
    final repository = _Repository(projects);
    final bulk = ReviewInboxBulkReview(repository, clock: () => _now);
    final progress = <String>[];

    final batch = await bulk.markAllProjectsReviewed(
      projects,
      onProgress: (done, total) => progress.add('$done/$total'),
    );

    expect(progress, ['1/2', '2/2']);
    expect(repository.writes, ['a', 'b']);
    expect(batch.saved, hasLength(2));
    expect(batch.markedLines, 5);
    expect(batch.conflicts, isEmpty);
    expect(batch.failed, isEmpty);
    expect(batch.canUndo, isTrue);
    expect(batch.changedAnything, isTrue);
    expect(repository.pending('a'), 0);
    expect(repository.pending('b'), 0);
  });

  test('a project saved elsewhere is skipped, the rest still saved', () async {
    final projects = [_project('a'), _project('b'), _project('c')];
    final repository = _Repository(projects);
    // The editor saved b after the inbox read it.
    repository.stored['b'] = repository.stored['b']!.copyWith(revision: 9);
    final bulk = ReviewInboxBulkReview(repository, clock: () => _now);

    final batch = await bulk.markAllProjectsReviewed(projects);

    expect(repository.writes, ['a', 'c']);
    expect(batch.saved.map((result) => result.saved!.id), ['a', 'c']);
    expect(batch.conflicts.map((project) => project.id), ['b']);
    expect(repository.stored['b']!.revision, 9);
    expect(repository.pending('b'), 2);
  });

  test('one failing save does not stop the others and never throws', () async {
    final projects = [_project('a'), _project('b')];
    final repository = _Repository(projects)..failing.add('a');
    final bulk = ReviewInboxBulkReview(repository, clock: () => _now);

    final batch = await bulk.markAllProjectsReviewed(projects);

    expect(batch.failed.map((project) => project.id), ['a']);
    expect(batch.saved.single.saved!.id, 'b');
    expect(repository.pending('a'), 2);
    expect(repository.pending('b'), 0);
  });

  test('confirmed projects and ones without lyrics are not written', () async {
    final done = _project('done', lines: 1);
    final repository = _Repository([done, _project('empty', lines: 0)]);
    final bulk = ReviewInboxBulkReview(repository, clock: () => _now);
    final first = await bulk.markAllProjectsReviewed([done]);
    repository.writes.clear();

    final batch = await bulk.markAllProjectsReviewed([
      first.saved.single.saved!,
      repository.stored['empty']!,
    ]);

    expect(repository.writes, isEmpty);
    expect(batch.unchanged, 2);
    expect(batch.saved, isEmpty);
    expect(batch.canUndo, isFalse);
    expect(batch.changedAnything, isFalse);
  });

  test('an empty request reports nothing and calls no progress', () async {
    final bulk = ReviewInboxBulkReview(_Repository(const []));
    var calls = 0;

    final batch = await bulk.markAllProjectsReviewed(
      const [],
      onProgress: (_, _) => calls++,
    );

    expect(calls, 0);
    expect(batch.saved, isEmpty);
    expect(batch.markedLines, 0);
  });

  group('undo', () {
    test('restores every project the batch saved', () async {
      final projects = [_project('a'), _project('b')];
      final repository = _Repository(projects);
      final bulk = ReviewInboxBulkReview(repository, clock: () => _now);
      final batch = await bulk.markAllProjectsReviewed(projects);

      final undone = await bulk.undoBatch(batch);

      expect(undone.restored, 2);
      expect(undone.isComplete, isTrue);
      expect(repository.pending('a'), 2);
      expect(repository.pending('b'), 2);
    });

    test('leaves a project saved again since the batch alone', () async {
      final projects = [_project('a'), _project('b')];
      final repository = _Repository(projects);
      final bulk = ReviewInboxBulkReview(repository, clock: () => _now);
      final batch = await bulk.markAllProjectsReviewed(projects);
      repository.stored['a'] = repository.stored['a']!.copyWith(revision: 30);

      final undone = await bulk.undoBatch(batch);

      expect(undone.restored, 1);
      expect(undone.conflicts, 1);
      expect(undone.isComplete, isFalse);
      expect(repository.stored['a']!.revision, 30);
      expect(repository.pending('a'), 0);
      expect(repository.pending('b'), 2);
    });

    test('counts a failing restore without stopping', () async {
      final projects = [_project('a'), _project('b')];
      final repository = _Repository(projects);
      final bulk = ReviewInboxBulkReview(repository, clock: () => _now);
      final batch = await bulk.markAllProjectsReviewed(projects);
      repository.failing.add('a');

      final undone = await bulk.undoBatch(batch);

      expect(undone.failed, 1);
      expect(undone.restored, 1);
      expect(repository.pending('b'), 2);
    });

    test('skips conflicts and failures of the original batch', () async {
      final projects = [_project('a'), _project('b')];
      final repository = _Repository(projects)..failing.add('b');
      final bulk = ReviewInboxBulkReview(repository, clock: () => _now);
      final batch = await bulk.markAllProjectsReviewed(projects);
      repository.writes.clear();

      final undone = await bulk.undoBatch(batch);

      expect(repository.writes, ['a']);
      expect(undone.restored, 1);
      expect(undone.failed, 0);
    });
  });
}
