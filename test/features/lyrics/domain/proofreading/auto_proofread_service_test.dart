import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/data/services/local_lyric_file_import_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/online/online_lyric_candidate.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/online/online_lyric_matcher.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/online/online_lyric_query.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/auto_proofread_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/reference_lyric_text_parser.dart';

import '../online/online_lyric_test_support.dart';

void main() {
  final matcher = OnlineLyricMatcher(
    parser: ReferenceLyricTextParser(LocalLyricFileImportService()),
  );
  final appliedAt = DateTime.utc(2026, 12, 17);
  final query = AutoProofreadService.queryFor(
    projectName: '林小雨 - 夜航.mp3',
    audioDuration: const Duration(seconds: 56),
  );

  AutoProofreadService serviceWith(List<OnlineLyricSource> sources) =>
      AutoProofreadService(
        search: OnlineLyricSearchService(sources: sources),
        matcher: matcher,
      );

  test('项目名解析成查询', () {
    expect(query.title, '夜航');
    expect(query.artist, '林小雨');
    expect(query.duration, const Duration(seconds: 56));
  });

  test('找到匹配的歌词后一次完成校对', () async {
    final service = serviceWith([
      FakeLyricSource(OnlineLyricSourceKind.netease, results: [candidate()]),
    ]);
    final outcome = await service.run(
      draft: nightFlightDraft(),
      query: query,
      appliedAt: appliedAt,
    );
    expect(outcome.lyricStatus, AutoProofreadLyricStatus.applied);
    expect(outcome.usedOnlineLyric, isTrue);
    expect(outcome.result.correctedLines, 3);
  });

  test('所有来源都失败时视为离线，仍做本地整理', () async {
    final service = serviceWith([
      FakeLyricSource(
        OnlineLyricSourceKind.netease,
        error: const SocketException('offline'),
      ),
      FakeLyricSource(
        OnlineLyricSourceKind.kugou,
        error: const SocketException('offline'),
      ),
    ]);
    final outcome = await service.run(
      draft: nightFlightDraft(),
      query: query,
      appliedAt: appliedAt,
    );
    expect(outcome.lyricStatus, AutoProofreadLyricStatus.offline);
    expect(outcome.failures, hasLength(2));
    expect(outcome.result.removedLines, 1);
    expect(outcome.result.correctedLines, 0);
  });

  test('来源都回答了但没有歌词时为未找到', () async {
    final service = serviceWith([
      FakeLyricSource(OnlineLyricSourceKind.netease),
    ]);
    final outcome = await service.run(
      draft: nightFlightDraft(),
      query: query,
      appliedAt: appliedAt,
    );
    expect(outcome.lyricStatus, AutoProofreadLyricStatus.notFound);
  });

  test('歌词对不上时不使用，并给出最接近的候选', () async {
    final service = serviceWith([
      FakeLyricSource(
        OnlineLyricSourceKind.netease,
        results: [candidate(lyricText: '海风吹过旧码头\n船笛声里有离愁\n我们约好明年再见')],
      ),
    ]);
    final outcome = await service.run(
      draft: nightFlightDraft(),
      query: query,
      appliedAt: appliedAt,
    );
    expect(outcome.lyricStatus, AutoProofreadLyricStatus.noMatch);
    expect(outcome.bestCandidate, isNotNull);
    expect(outcome.result.correctedLines, 0);
  });

  test('没有配置联网搜索时只做本地整理', () async {
    final service = AutoProofreadService(search: null, matcher: matcher);
    expect(service.canSearch, isFalse);
    final outcome = await service.run(
      draft: nightFlightDraft(),
      query: query,
      appliedAt: appliedAt,
    );
    expect(outcome.lyricStatus, AutoProofreadLyricStatus.searchUnavailable);
    expect(outcome.result.hasChanges, isTrue);
  });

  test('没有歌名时不搜索', () async {
    final source = FakeLyricSource(OnlineLyricSourceKind.netease);
    final outcome = await serviceWith([source]).run(
      draft: nightFlightDraft(),
      query: const OnlineLyricQuery(title: ''),
      appliedAt: appliedAt,
    );
    expect(outcome.lyricStatus, AutoProofreadLyricStatus.noTitle);
    expect(source.calls, 0);
  });
}
