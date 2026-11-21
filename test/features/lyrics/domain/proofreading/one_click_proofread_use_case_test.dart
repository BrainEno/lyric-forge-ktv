import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/local_lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/online/online_lyric_matcher.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/online/online_lyric_query.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/one_click_proofread_use_case.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/reference_lyric_text_parser.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

import '../online/online_lyric_test_support.dart';

void main() {
  const useCase = OneClickProofreadUseCase();
  final appliedAt = DateTime.utc(2026, 12, 17, 9, 30);
  final matcher = OnlineLyricMatcher(
    parser: ReferenceLyricTextParser(LocalLyricFileImportService()),
  );
  const query = OnlineLyricQuery(
    title: '夜航',
    artist: '林小雨',
    duration: Duration(seconds: 56),
  );

  OnlineLyricMatch matchFor(LyricDocument draft) =>
      matcher.rank(draft: draft, candidates: [candidate()], query: query).first;

  test('在线歌词改正错字，识别行的时间保持不变', () {
    final draft = nightFlightDraft();
    final result = useCase.build(
      draft: draft,
      reference: matchFor(draft),
      audioDuration: const Duration(seconds: 56),
      appliedAt: appliedAt,
    );
    final texts = result.document.lines.map((line) => line.text).toList();
    expect(texts, contains('窗外的雨停了又下'));
    expect(texts, contains('照亮我回家的那条路'));
    expect(texts, contains('如果还能再见到你'));
    expect(texts, isNot(contains('窗外的雨停了又夏')));
    expect(result.correctedLines, 3);
    expect(result.usedReference, isTrue);

    final corrected = result.document.lines.firstWhere(
      (line) => line.text == '窗外的雨停了又下',
    );
    expect(corrected.startTime, const Duration(seconds: 10));
    expect(corrected.endTime, const Duration(seconds: 14));
    expect(corrected.confidence, 100);
  });

  test('字幕残留在对齐前删除，不算作对不上的行', () {
    final draft = nightFlightDraft();
    final result = useCase.build(
      draft: draft,
      reference: matchFor(draft),
      audioDuration: const Duration(seconds: 56),
      appliedAt: appliedAt,
    );
    expect(
      result.document.lines.map((line) => line.text),
      isNot(contains('谢谢观看')),
    );
    expect(result.removedLines, 1);
    expect(result.unmatchedDraftLines, 0);
  });

  test('与歌词逐字一致的行标记为可信', () {
    final draft = nightFlightDraft();
    final result = useCase.build(
      draft: draft,
      reference: matchFor(draft),
      audioDuration: const Duration(seconds: 56),
      appliedAt: appliedAt,
    );
    expect(result.verifiedLines, greaterThanOrEqualTo(3));
    final confirmed = result.document.lines.firstWhere(
      (line) => line.text == '我还在等你的回答',
    );
    expect(confirmed.confidence, 100);
  });

  test('漏唱的一行要么补入，要么计为待确认', () {
    final draft = nightFlightDraft();
    final result = useCase.build(
      draft: draft,
      reference: matchFor(draft),
      audioDuration: const Duration(seconds: 56),
      appliedAt: appliedAt,
    );
    final inserted = result.document.lines.any(
      (line) => line.text == '我们说好不再分离',
    );
    expect(inserted ? result.insertedLines : result.uncertainLines, 1);
  });

  test('手动编辑过的行不被修改', () {
    final draft = nightFlightDraft();
    final result = useCase.build(
      draft: draft,
      reference: matchFor(draft),
      protectedIndices: const {0},
      audioDuration: const Duration(seconds: 56),
      appliedAt: appliedAt,
    );
    expect(result.document.lines.first.text, '窗外的雨停了又夏');
    expect(result.correctedLines, 2);
  });

  test('记录使用了哪份在线歌词', () {
    final draft = nightFlightDraft();
    final result = useCase.build(
      draft: draft,
      reference: matchFor(draft),
      audioDuration: const Duration(seconds: 56),
      appliedAt: appliedAt,
    );
    final record =
        result.document.metadata[kOneClickProofreadMetadataKey]
            as Map<String, dynamic>;
    expect(record['source'], 'netease');
    expect(record['title'], '夜航');
    expect(record['appliedAt'], appliedAt.toIso8601String());
  });

  test('没有在线歌词时只做本地整理', () {
    final result = useCase.build(
      draft: nightFlightDraft(),
      appliedAt: appliedAt,
    );
    expect(result.usedReference, isFalse);
    expect(result.correctedLines, 0);
    expect(result.removedLines, 1);
    expect(result.hasChanges, isTrue);
    expect(
      result.document.metadata.containsKey(kOneClickProofreadMetadataKey),
      isFalse,
    );
  });

  test('未被接受的匹配不会被使用', () {
    final draft = nightFlightDraft();
    final rejected = matcher
        .rank(
          draft: draft,
          candidates: [candidate(lyricText: '海风吹过旧码头\n船笛声里有离愁\n我们约好明年再见')],
          query: query,
        )
        .first;
    expect(rejected.accepted, isFalse);
    final result = useCase.build(
      draft: draft,
      reference: rejected,
      appliedAt: appliedAt,
    );
    expect(result.reference, isNull);
    expect(result.correctedLines, 0);
  });

  test('没有任何可改之处时原样返回草稿', () {
    final draft = LyricDocument(
      language: 'zh',
      lines: [
        for (var i = 0; i < 3; i++)
          LyricLine(
            text: kNightFlightLyric[i],
            startTime: Duration(seconds: i * 5),
            endTime: Duration(seconds: i * 5 + 4),
          ),
      ],
    );
    final result = useCase.build(draft: draft, appliedAt: appliedAt);
    expect(result.hasChanges, isFalse);
    expect(identical(result.document, draft), isTrue);
    expect(result.firstChangedIndex, isNull);
  });

  test('重叠的时间轴按规则修复', () {
    final draft = LyricDocument(
      language: 'zh',
      lines: [
        LyricLine(
          text: kNightFlightLyric[0],
          startTime: const Duration(seconds: 10),
          endTime: const Duration(seconds: 16),
        ),
        LyricLine(
          text: kNightFlightLyric[1],
          startTime: const Duration(seconds: 15),
          endTime: const Duration(seconds: 19),
        ),
      ],
    );
    final result = useCase.build(draft: draft, appliedAt: appliedAt);
    expect(result.timelineFixes, greaterThanOrEqualTo(1));
    expect(
      result.document.lines.first.endTime,
      lessThanOrEqualTo(result.document.lines[1].startTime),
    );
    expect(result.firstChangedIndex, 0);
  });
}
