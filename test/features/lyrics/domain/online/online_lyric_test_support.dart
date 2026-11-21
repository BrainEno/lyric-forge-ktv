import 'package:lyric_forge_ktv/features/lyrics/domain/online/online_lyric_candidate.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/online/online_lyric_query.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

/// An invented song, so the tests carry no published lyrics.
const List<String> kNightFlightLyric = [
  '窗外的雨停了又下',
  '我还在等你的回答',
  '城市的灯一盏盏亮起',
  '照亮我回家的那条路',
  '我们说好不再分离',
  '你却消失在人海里',
  '如果还能再见到你',
  '我会把思念都交给你',
];

/// What a recogniser might make of [kNightFlightLyric]: three wrong
/// characters, the fifth row missed, a caption invented on the outro.
LyricDocument nightFlightDraft({int confidence = 70}) {
  LyricLine line(String text, int startMs, int endMs) => LyricLine(
    text: text,
    startTime: Duration(milliseconds: startMs),
    endTime: Duration(milliseconds: endMs),
    confidence: confidence,
  );
  return LyricDocument(
    language: 'zh',
    lines: [
      line('窗外的雨停了又夏', 10000, 14000),
      line('我还在等你的回答', 15000, 19000),
      line('城市的灯一盏盏亮起', 20000, 24000),
      line('照亮我回家的那条鹿', 25000, 29000),
      line('你却消失在人海里', 36000, 40000),
      line('如果还能在见到你', 41000, 45000),
      line('我会把思念都交给你', 46000, 50000),
      line('谢谢观看', 52000, 54000),
    ],
  );
}

/// [kNightFlightLyric] as a NetEase-style LRC with credits and a header.
String nightFlightLrc({int shiftMs = 0}) {
  String stamp(int ms) {
    final total = ms + shiftMs;
    final minutes = total ~/ 60000;
    final seconds = (total % 60000) / 1000;
    return '[${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toStringAsFixed(2).padLeft(5, '0')}]';
  }

  const starts = [10000, 15000, 20000, 25000, 30500, 36000, 41000, 46000];
  return [
    '[00:00.00]夜航 - 林小雨',
    '[00:01.00]作词 : 林小雨',
    '[00:02.00]作曲 : 陈大海',
    for (var i = 0; i < kNightFlightLyric.length; i++)
      '${stamp(starts[i])}${kNightFlightLyric[i]}',
  ].join('\n');
}

OnlineLyricCandidate candidate({
  OnlineLyricSourceKind source = OnlineLyricSourceKind.netease,
  String id = '1',
  String title = '夜航',
  String artist = '林小雨',
  Duration? duration = const Duration(seconds: 56),
  String? lyricText,
}) => OnlineLyricCandidate(
  source: source,
  sourceId: id,
  title: title,
  artist: artist,
  duration: duration,
  lyricText: lyricText ?? nightFlightLrc(),
);

/// A lyric source answering from memory.
class FakeLyricSource implements OnlineLyricSource {
  FakeLyricSource(
    this.kind, {
    this.results = const [],
    this.error,
    this.delay = Duration.zero,
  });

  @override
  final OnlineLyricSourceKind kind;
  final List<OnlineLyricCandidate> results;
  final Object? error;
  final Duration delay;
  int calls = 0;

  @override
  Future<List<OnlineLyricCandidate>> search(OnlineLyricQuery query) async {
    calls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final failure = error;
    if (failure != null) throw failure;
    return results;
  }
}
