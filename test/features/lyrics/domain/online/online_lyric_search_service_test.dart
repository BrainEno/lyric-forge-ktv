import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/online/online_lyric_candidate.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/online/online_lyric_query.dart';

import 'online_lyric_test_support.dart';

void main() {
  const query = OnlineLyricQuery(title: '夜航', artist: '林小雨');

  test('合并所有来源的候选，按来源和编号去重并丢弃空歌词', () async {
    final service = OnlineLyricSearchService(
      sources: [
        FakeLyricSource(
          OnlineLyricSourceKind.netease,
          results: [candidate(id: '1'), candidate(id: '1')],
        ),
        FakeLyricSource(
          OnlineLyricSourceKind.kugou,
          results: [
            candidate(source: OnlineLyricSourceKind.kugou, id: '1'),
            candidate(
              source: OnlineLyricSourceKind.kugou,
              id: '2',
              lyricText: '  ',
            ),
          ],
        ),
      ],
    );
    final result = await service.search(query);
    expect(result.candidates, hasLength(2));
    expect(result.failures, isEmpty);
    expect(result.allSourcesFailed, isFalse);
  });

  test('一个来源失败不影响其他来源，失败原因被记录', () async {
    final service = OnlineLyricSearchService(
      sources: [
        FakeLyricSource(
          OnlineLyricSourceKind.netease,
          error: const SocketException('Failed host lookup'),
        ),
        FakeLyricSource(OnlineLyricSourceKind.lrclib, results: [candidate()]),
      ],
    );
    final result = await service.search(query);
    expect(result.candidates, hasLength(1));
    expect(result.failures.keys, [OnlineLyricSourceKind.netease]);
    expect(result.allSourcesFailed, isFalse);
  });

  test('超时的来源记为连接超时', () async {
    final service = OnlineLyricSearchService(
      timeout: const Duration(milliseconds: 20),
      sources: [
        FakeLyricSource(
          OnlineLyricSourceKind.kugou,
          delay: const Duration(milliseconds: 200),
          results: [candidate()],
        ),
      ],
    );
    final result = await service.search(query);
    expect(result.candidates, isEmpty);
    expect(result.failures[OnlineLyricSourceKind.kugou], '连接超时');
    expect(result.allSourcesFailed, isTrue);
  });

  test('没有歌名时不发请求', () async {
    final source = FakeLyricSource(OnlineLyricSourceKind.netease);
    final service = OnlineLyricSearchService(sources: [source]);
    final result = await service.search(const OnlineLyricQuery(title: ' '));
    expect(result.candidates, isEmpty);
    expect(source.calls, 0);
  });
}
