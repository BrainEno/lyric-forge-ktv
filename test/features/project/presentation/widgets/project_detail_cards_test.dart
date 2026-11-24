import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_review_overview.dart';
import 'package:lyric_forge_ktv/features/project/presentation/widgets/project_detail_cards.dart';

ProjectLyricReviewOverview _review({
  int suggested = 0,
  int mustCheck = 0,
  int reviewed = 0,
}) => ProjectLyricReviewOverview(
  suggested: suggested,
  mustCheck: mustCheck,
  reviewed: reviewed,
);

void main() {
  group('reviewSentence', () {
    String sentence(ProjectLyricReviewOverview? review) =>
        ProjectDetailLyricStatusCard.reviewSentence(review);

    test('without counts it still points to the editor', () {
      expect(sentence(null), '自动识别结果仍建议进入歌词编辑器逐行校对。');
    });

    test('names how many rows are left and how many must be checked', () {
      expect(
        sentence(_review(suggested: 5, mustCheck: 2)),
        '还有 5 行建议复核，其中 2 行必看，在歌词编辑器里逐行确认。',
      );
      expect(sentence(_review(suggested: 5)), '还有 5 行建议复核，在歌词编辑器里逐行确认。');
    });

    test('nothing left after confirming says so', () {
      expect(sentence(_review(reviewed: 4)), '建议复核的行都已确认，仍可在歌词编辑器里逐行检查。');
    });

    test('nothing found and nothing confirmed says nothing was found', () {
      expect(sentence(_review()), '没有发现需要复核的行，仍可在歌词编辑器里逐行检查。');
    });
  });
}
