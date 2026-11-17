import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/aligner_word_timing_repair.dart';

Duration _ms(int value) => Duration(milliseconds: value);

AlignedWord _w(String text, int startMs, int endMs) =>
    AlignedWord(text: text, start: _ms(startMs), end: _ms(endMs));

List<String> _texts(List<AlignedWord> words) => [
  for (final word in words) word.text,
];

void main() {
  const repair = AlignerWordTimingRepair();

  test('words with a length outside a cluster are left untouched', () {
    final input = [_w('hold', 1000, 1300), _w('on', 1300, 1700)];
    final result = repair.repair(input);
    expect(result.words, input);
    expect(result.zeroLengthWords, 0);
    expect(result.spreadClusters, 0);
  });

  test('a pile before a stretched word is spread over its span', () {
    // The shape the Qwen3 aligner returns for an unplaced chant.
    final result = repair.repair([
      _w('find', 10000, 10000),
      _w('the', 10000, 10000),
      _w('fire', 10000, 10000),
      _w('find', 10000, 10000),
      _w('the', 10000, 10000),
      _w('fire', 10000, 14000),
      _w('whoa', 14000, 14400),
    ]);
    final words = result.words;
    expect(_texts(words), [
      'find',
      'the',
      'fire',
      'find',
      'the',
      'fire',
      'whoa',
    ]);
    expect(result.zeroLengthWords, 5);
    expect(result.spreadClusters, 1);
    expect(words.first.start, _ms(10000));
    expect(words[5].end, _ms(14000));
    for (var index = 1; index < 6; index++) {
      expect(words[index].start, words[index - 1].end);
      expect(words[index].end, greaterThan(words[index].start));
    }
    // Longer words take longer: 'find' (4 letters) beats 'the' (3).
    expect(words[0].length, greaterThan(words[1].length));
    expect(words.last, _w('whoa', 14000, 14400));
  });

  test('a cluster over a very long span is placed at its end', () {
    // 2 words cannot fill 23 s; the singing comes at the end of the
    // stretch, as in the measured songs.
    final result = repair.repair([
      _w('and', 156400, 156400),
      _w('I', 156400, 179700),
    ]);
    final words = result.words;
    expect(words.first.start, _ms(179700 - 2400));
    expect(words.last.end, _ms(179700));
  });

  test('a zero-length pile with no span borrows room up to the next word', () {
    final result = repair.repair([
      _w('oh', 1000, 1000),
      _w('oh', 1000, 1000),
      _w('I', 1600, 1900),
    ]);
    final words = result.words;
    expect(words[0].start, _ms(1000));
    expect(words[0].end, _ms(1300));
    expect(words[1].end, _ms(1600));
    expect(words[2], _w('I', 1600, 1900));
  });

  test('borrowed room is capped per word', () {
    final result = repair.repair([
      _w('hey', 1000, 1000),
      _w('next', 9000, 9400),
    ]);
    expect(result.words.first.end, _ms(1350));
  });

  test('the last word of the song gets the fallback length', () {
    final result = repair.repair([
      _w('la', 5000, 5400),
      _w('la', 6000, 6000),
      _w('la', 6000, 6000),
    ]);
    expect(result.words[1].start, _ms(6000));
    expect(result.words[2].end, _ms(6700));
  });

  test('a pile shares the span of the word that ends it', () {
    final result = repair.repair([
      _w('a', 1000, 1000),
      _w('b', 1000, 1000),
      _w('c', 1010, 1010),
      _w('d', 1010, 1300),
      _w('e', 1300, 1500),
    ]);
    // 'a', 'b', 'c' and 'd' start within the window: one cluster, extended
    // only up to the next word.
    expect(_texts(result.words), ['a', 'b', 'c', 'd', 'e']);
    expect(result.words.first.start, _ms(1000));
    expect(result.words[3].end, _ms(1300));
    expect(result.words.last, _w('e', 1300, 1500));
  });

  test('a pile at the very end gets the fallback length per word', () {
    final result = repair.repair([
      _w('x', 2000, 2000),
      _w('y', 2000, 2000),
      _w('z', 2000, 2000),
      _w('w', 2000, 2000),
    ]);
    expect(_texts(result.words), ['x', 'y', 'z', 'w']);
    expect(result.words.last.end, _ms(2000 + 350 * 4));
  });

  test('with no room at all a word keeps zero length but stays', () {
    // The next word starts before this one: there is nowhere to grow.
    final result = repair.repair([_w('x', 2000, 2000), _w('y', 1500, 1800)]);
    expect(result.words, [_w('x', 2000, 2000), _w('y', 1500, 1800)]);
    expect(result.spreadClusters, 0);
  });

  test('a word is not pulled into a cluster that started much earlier', () {
    final result = repair.repair([
      _w('one', 1000, 1000),
      _w('two', 1200, 1500),
    ]);
    expect(result.words[0].end, _ms(1200));
    expect(result.words[1], _w('two', 1200, 1500));
  });

  test('a backwards word is treated as zero length and blank ones dropped', () {
    final result = repair.repair([
      _w('back', 3000, 2500),
      _w('  ', 3000, 3200),
      _w('next', 3400, 3800),
    ]);
    expect(_texts(result.words), ['back', 'next']);
    expect(result.words.first.start, _ms(3000));
    expect(result.words.first.end, _ms(3350));
    expect(result.zeroLengthWords, 1);
  });

  test('spaceless-script characters weigh more than letters', () {
    final result = repair.repair([
      _w('啦', 0, 0),
      _w('la', 0, 0),
      _w('x', 0, 3000),
    ]);
    // Weights 2, 2, 1 over 3 s.
    expect(result.words[0].end, _ms(1200));
    expect(result.words[1].end, _ms(2400));
  });
}
