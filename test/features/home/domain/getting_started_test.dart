import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/home/domain/models/getting_started.dart';
import 'package:lyric_forge_ktv/features/home/domain/services/getting_started_store.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_review_overview.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';

ProjectManifest _project(String id, {bool lyrics = false}) => ProjectManifest(
  id: id,
  name: '歌 $id',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  lyricDocument: lyrics
      ? const LyricDocument(
          language: 'zh',
          lines: [
            LyricLine(
              text: '窗外的麻雀',
              startTime: Duration.zero,
              endTime: Duration(seconds: 3),
            ),
          ],
        )
      : null,
);

ProjectLyricReviewCounter _reviewed(Set<String> ids) =>
    (project) => ProjectLyricReviewOverview(
      suggested: 0,
      mustCheck: 0,
      reviewed: ids.contains(project.id) ? 1 : 0,
    );

void main() {
  group('first decision (D-070)', () {
    test('someone with no projects gets the checklist', () {
      final decided = const GettingStartedPreferences().decidedFor(
        hasProjects: false,
      );
      expect(decided.visibility, GettingStartedVisibility.active);
      expect(decided.showsCard, isTrue);
    });

    test('someone who already has projects does not', () {
      final decided = const GettingStartedPreferences().decidedFor(
        hasProjects: true,
      );
      expect(decided.visibility, GettingStartedVisibility.dismissed);
      expect(decided.showsCard, isFalse);
    });

    test('a saved choice is never decided again', () {
      const closed = GettingStartedPreferences(
        visibility: GettingStartedVisibility.dismissed,
      );
      expect(
        closed.decidedFor(hasProjects: false).visibility,
        GettingStartedVisibility.dismissed,
      );
    });

    test('unknown saved values read as undecided', () {
      expect(
        GettingStartedVisibility.fromId('later'),
        GettingStartedVisibility.undecided,
      );
      expect(
        GettingStartedVisibility.fromId('completed'),
        GettingStartedVisibility.completed,
      );
    });
  });

  group('progress from the projects', () {
    test('no projects: only importing can start', () {
      final progress = GettingStartedProgress.from(const []);

      expect(
        progress.stateOf(GettingStartedStep.importSong),
        GettingStartedStepState.ready,
      );
      expect(
        progress.stateOf(GettingStartedStep.reviewLyrics),
        GettingStartedStepState.locked,
      );
      expect(
        progress.stateOf(GettingStartedStep.singKtv),
        GettingStartedStepState.locked,
      );
      expect(progress.doneCount, 0);
      expect(progress.next, GettingStartedStep.importSong);
    });

    test('a project still being recognised is in progress', () {
      final progress = GettingStartedProgress.from([_project('a')]);

      expect(
        progress.stateOf(GettingStartedStep.importSong),
        GettingStartedStepState.inProgress,
      );
      expect(progress.recognizing?.id, 'a');
      expect(progress.doneCount, 0);
    });

    test('lyrics finish the first step and unlock the other two', () {
      final progress = GettingStartedProgress.from(
        [_project('new'), _project('old', lyrics: true)],
        countReview: _reviewed(const {}),
      );

      expect(progress.lyricsProject?.id, 'old');
      expect(progress.recognizing, isNull);
      expect(
        progress.stateOf(GettingStartedStep.importSong),
        GettingStartedStepState.done,
      );
      expect(
        progress.stateOf(GettingStartedStep.reviewLyrics),
        GettingStartedStepState.ready,
      );
      expect(
        progress.stateOf(GettingStartedStep.singKtv),
        GettingStartedStepState.ready,
      );
      expect(progress.next, GettingStartedStep.reviewLyrics);
    });

    test('a confirmed line in any project finishes review', () {
      final progress = GettingStartedProgress.from(
        [_project('a', lyrics: true), _project('b', lyrics: true)],
        countReview: _reviewed(const {'b'}),
      );

      expect(progress.reviewed, isTrue);
      expect(progress.next, GettingStartedStep.singKtv);
    });

    test('without a counter review never ticks itself', () {
      final progress = GettingStartedProgress.from([
        _project('a', lyrics: true),
      ]);
      expect(progress.reviewed, isFalse);
    });

    test('all three done', () {
      final progress = GettingStartedProgress.from(
        [_project('a', lyrics: true)],
        countReview: _reviewed(const {'a'}),
        openedKtv: true,
      );

      expect(progress.doneCount, 3);
      expect(progress.allDone, isTrue);
      expect(progress.next, isNull);
    });
  });

  test('设置 brings the card back and keeps what was done', () async {
    final store = MemoryGettingStartedStore(
      const GettingStartedPreferences(
        visibility: GettingStartedVisibility.completed,
        openedKtv: true,
      ),
    );

    await showGettingStartedAgain(store);

    expect(store.saved?.visibility, GettingStartedVisibility.active);
    expect(store.saved?.openedKtv, isTrue);
  });
}
