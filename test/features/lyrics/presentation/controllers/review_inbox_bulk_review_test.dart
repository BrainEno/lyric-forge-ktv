import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/lyric_review_queue.dart';
import 'package:lyric_forge_ktv/features/lyrics/presentation/controllers/review_inbox_bulk_review.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';
import 'package:lyric_forge_ktv/features/project/domain/repositories/project_repository.dart';

final _created = DateTime(2026, 11, 1);
final _now = DateTime(2026, 11, 25, 12);

ProjectManifest _project({List<LyricLine>? lines, int revision = 3}) {
  return ProjectManifest(
    id: 'p1',
    name: '夜曲',
    createdAt: _created,
    updatedAt: _created,
    revision: revision,
    lyricDocument: lines == null
        ? null
        : LyricDocument(language: 'zh', lines: lines),
  );
}

LyricLine _line(String text, {String? id, int start = 0}) => LyricLine(
  id: id,
  text: text,
  startTime: Duration(seconds: start),
  endTime: Duration(seconds: start + 3),
  confidence: 30,
);

/// Stores one project and enforces the revision check like the file
/// repository does.
class _Repository implements ProjectRepository {
  _Repository(this.stored);

  ProjectManifest stored;
  int writes = 0;
  Object? failure;

  @override
  Future<ProjectManifest> updateProjectIfUnchanged(
    ProjectManifest project, {
    required int expectedRevision,
  }) async {
    final error = failure;
    if (error != null) throw error;
    if (stored.revision != expectedRevision) {
      throw ProjectUpdateConflictException(currentProject: stored);
    }
    writes++;
    return stored = project.copyWith(revision: expectedRevision + 1);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('marks every line reviewed and saves with the revision check', () async {
    final project = _project(
      lines: [
        _line('第一行', id: 'a'),
        _line('第二行', id: 'b', start: 3),
      ],
    );
    final repository = _Repository(project);
    final bulk = ReviewInboxBulkReview(repository, clock: () => _now);

    final result = await bulk.markAllReviewed(project);

    expect(result.status, BulkReviewStatus.saved);
    expect(result.markedLines, 2);
    expect(result.canUndo, isTrue);
    expect(repository.writes, 1);
    expect(repository.stored.revision, 4);
    expect(repository.stored.updatedAt, _now);
    final queue = LyricReviewQueue.build(repository.stored.lyricDocument!);
    expect(queue.needsReviewCount, 0);
    expect(queue.reviewedLines, 2);
  });

  test('gives lines from older documents an ID first', () async {
    final project = _project(lines: [_line('旧数据'), _line('旧数据二', start: 3)]);
    final repository = _Repository(project);

    final bulk = ReviewInboxBulkReview(repository, clock: () => _now);
    final result = await bulk.markAllReviewed(project);

    expect(result.markedLines, 2);
    final document = repository.stored.lyricDocument!;
    expect(document.lines.every((line) => line.id?.isNotEmpty == true), isTrue);
    expect(LyricReviewQueue.build(document).items, isEmpty);
  });

  test('a newer save wins: nothing is written on a conflict', () async {
    final loaded = _project(lines: [_line('第一行', id: 'a')]);
    final repository = _Repository(loaded.copyWith(revision: 9));

    final bulk = ReviewInboxBulkReview(repository);
    final result = await bulk.markAllReviewed(loaded);

    expect(result.status, BulkReviewStatus.conflict);
    expect(result.canUndo, isFalse);
    expect(repository.writes, 0);
  });

  test('nothing to do without lyrics or when all is confirmed', () async {
    final repository = _Repository(_project());
    final bulk = ReviewInboxBulkReview(repository, clock: () => _now);

    expect(
      (await bulk.markAllReviewed(_project())).status,
      BulkReviewStatus.unchanged,
    );
    expect(
      (await bulk.markAllReviewed(_project(lines: const []))).status,
      BulkReviewStatus.unchanged,
    );

    final project = _project(lines: [_line('第一行', id: 'a')]);
    repository.stored = project;
    final first = await bulk.markAllReviewed(project);
    final again = await bulk.markAllReviewed(first.saved!);

    expect(again.status, BulkReviewStatus.unchanged);
    expect(repository.writes, 1);
  });

  test('other repository errors reach the caller', () async {
    final project = _project(lines: [_line('第一行', id: 'a')]);
    final repository = _Repository(project)
      ..failure = const ProjectRepositoryException('disk full');

    expect(
      ReviewInboxBulkReview(repository).markAllReviewed(project),
      throwsA(isA<ProjectRepositoryException>()),
    );
  });

  test('undo puts the old lyrics back', () async {
    final project = _project(lines: [_line('第一行', id: 'a')]);
    final repository = _Repository(project);
    final bulk = ReviewInboxBulkReview(repository, clock: () => _now);

    final result = await bulk.markAllReviewed(project);
    final undone = await bulk.undo(result);

    expect(undone.status, BulkReviewStatus.saved);
    expect(undone.canUndo, isTrue);
    expect(repository.stored.revision, 5);
    final queue = LyricReviewQueue.build(repository.stored.lyricDocument!);
    expect(queue.reviewedLines, 0);
    expect(queue.needsReviewCount, 1);
  });

  test('undo refuses to overwrite a later save', () async {
    final project = _project(lines: [_line('第一行', id: 'a')]);
    final repository = _Repository(project);
    final bulk = ReviewInboxBulkReview(repository, clock: () => _now);

    final result = await bulk.markAllReviewed(project);
    repository.stored = repository.stored.copyWith(revision: 20);
    final undone = await bulk.undo(result);

    expect(undone.status, BulkReviewStatus.conflict);
    expect(repository.stored.revision, 20);
  });

  test('undo of a result without a save does nothing', () async {
    final repository = _Repository(_project());
    final bulk = ReviewInboxBulkReview(repository);

    final unchanged = await bulk.markAllReviewed(_project());
    final undone = await bulk.undo(unchanged);

    expect(undone.status, BulkReviewStatus.unchanged);
    expect(repository.writes, 0);
  });
}
