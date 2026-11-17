import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

LyricLine loopLine(
  String text,
  int startMs,
  int endMs, {
  int confidence = 88,
  LyricConfidenceSource source = LyricConfidenceSource.model,
}) => LyricLine(
  text: text,
  startTime: Duration(milliseconds: startMs),
  endTime: Duration(milliseconds: endMs),
  confidence: confidence,
  confidenceSource: source,
);

const String loopChant = 'Oh-oh-oh-oh-oh-oh';
const String loopVerse = 'And the lanterns that you hold, we never need to fold';

/// The shape whisper.cpp produced on a real song once its rolling history
/// fed the last couplet back into every window: normal rows, then rows
/// squeezed onto a one-second grid (the lead-in), then a two-row block
/// repeated eleven times on that grid, then the decoder resynchronising.
/// Lyrics are synthetic; timings and repetition counts are the real ones.
List<LyricLine> whisperLoopedSong() {
  final lines = <LyricLine>[
    loopLine('Wake me up when the city is quiet', 30000, 36920),
    loopLine('Carry me home on a paper balloon', 36920, 44800),
    loopLine('Now the river is wide and the morning is near', 74680, 82120),
    loopLine('Tell me again why the road never ends', 82120, 89280),
    // Lead-in: real lyrics, but squeezed onto the collapsed grid.
    loopLine('How far is the harbour?', 89280, 90320),
    loopLine('Is it under the water?', 90320, 91360),
    loopLine('I hope we arrive in time', 91360, 92360),
    loopLine('Now you never look back on the way', 92360, 93360),
    loopLine(loopChant, 93360, 94360),
    loopLine('And the lantern that you hold, we never need to fold', 94360, 95360),
  ];
  var start = 95360;
  for (var repeat = 0; repeat < 11; repeat++) {
    lines.add(loopLine(loopChant, start, start + 1000));
    lines.add(loopLine(loopVerse, start + 1000, start + 2000));
    start += 2000;
  }
  lines.addAll([
    loopLine('What they say, oh, the truth is we never care', start, start + 10000),
    loopLine('And that is quite enough of that', 151360, 158920),
  ]);
  return lines;
}

/// What an independent engine decoding 30 s chunks heard over the same
/// audio: the real lines, once each, with real timings.
List<LyricLine> qwenOverLoopedSong() => [
  loopLine('Wake me up when the city is quiet', 30200, 36500, confidence: 84),
  loopLine('Carry me home on a paper balloon', 37000, 44500, confidence: 82),
  loopLine(
    'Now the river is wide and the morning is near',
    74800,
    81900,
    confidence: 85,
  ),
  loopLine('Tell me again why the road never ends', 82300, 89000, confidence: 83),
  loopLine(
    'How far is the harbour, is it under the water?',
    89500,
    95000,
    confidence: 80,
  ),
  loopLine('I hope we arrive in time', 95500, 99000, confidence: 81),
  loopLine('Now you never look back on the way', 101500, 107000, confidence: 79),
  loopLine(
    'Oh, and the lanterns that you hold, we never mean to fold',
    107500,
    113500,
    confidence: 78,
  ),
  loopLine(
    'Oh, but the people you know, they say what they want to',
    114000,
    117000,
    confidence: 77,
  ),
  loopLine('And that is quite enough of that', 151500, 158800, confidence: 86),
];
