import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/lyric_tokenizer.dart';

void main() {
  const tokenizer = LyricTokenizer();

  test('tokenize splits Latin words, apostrophes, CJK and full-width text', () {
    const cases = <String, List<String>>{
      'Keep your eyes on the road.': ['keep', 'your', 'eyes', 'on', 'the', 'road'],
      "Yeah, we're going to the roadhouse": ['yeah', "we're", 'going', 'to', 'the', 'roadhouse'],
      'Gonna have a real, a good-time': ['gonna', 'have', 'a', 'real', 'a', 'good', 'time'],
      '♪ Well, I woke up in a moment ♪': ['well', 'i', 'woke', 'up', 'in', 'a', 'moment'],
      '我在这里等你': ['我', '在', '这', '里', '等', '你'],
      'Ｈｅｌｌｏ　ＷＯＲＬＤ': ['hello', 'world'],
      'I love 你 so much': ['i', 'love', '你', 'so', 'much'],
      "'cause rockin' all night": ['cause', 'rockin', 'all', 'night'],
      '君の名は': ['君', 'の', '名', 'は'],
      '': <String>[],
      '♪ ♪': <String>[],
    };
    for (final sample in cases.entries) {
      expect(tokenizer.tokenize(sample.key), sample.value, reason: sample.key);
    }
  });

  test('normalize and CJK token detection follow the contract', () {
    expect(tokenizer.normalize('Good-Time!'), 'good time');
    expect(tokenizer.isCjkToken('我'), isTrue);
    expect(tokenizer.isCjkToken('we'), isFalse);
  });
}
