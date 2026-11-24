import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/onboarding/getting_started.dart';
import 'package:lyric_forge_ktv/features/home/domain/models/getting_started.dart';
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
      final progress = GettingStartedProgress.from([
        _project('new'),
        _project('old', lyrics: true),
      ], countReview: _reviewed(const {}));

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
      final progress = GettingStartedProgress.from([
        _project('a', lyrics: true),
        _project('b', lyrics: true),
      ], countReview: _reviewed(const {'b'}));

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
}
