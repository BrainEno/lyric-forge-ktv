import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/lyric_tokenizer.dart';

void main() {
  const tokenizer = LyricTokenizer();

  void expectTokens(String input, List<String> expected) {
    expect(tokenizer.tokenize(input), expected, reason: input);
  }

  test('tokenize splits Latin words, apostrophes, CJK and full-width text', () {
    expectTokens(
      'Keep your eyes on the road.',
      ['keep', 'your', 'eyes', 'on', 'the', 'road'],
    );
    expectTokens(
      "Yeah, we're going to the roadhouse",
      ['yeah', "we're", 'going', 'to', 'the', 'roadhouse'],
    );
    expectTokens(
      'Gonna have a real, a good-time',
      ['gonna', 'have', 'a', 'real', 'a', 'good', 'time'],
    );
    expectTokens(
      '♪ Well, I woke up in a moment ♪',
      ['well', 'i', 'woke', 'up', 'in', 'a', 'moment'],
    );
    expectTokens('我在这里等你', ['我', '在', '这', '里', '等', '你']);
    expectTokens('Ｈｅｌｌｏ　ＷＯＲＬＤ', ['hello', 'world']);
    expectTokens('I love 你 so much', ['i', 'love', '你', 'so', 'much']);
    expectTokens(
      "'cause rockin' all night",
      ['cause', 'rockin', 'all', 'night'],
    );
    expectTokens('君の名は', ['君', 'の', '名', 'は']);
    expectTokens('', <String>[]);
    expectTokens('♪ ♪', <String>[]);
  });

  test('normalize and CJK token detection follow the contract', () {
    expect(tokenizer.normalize('Good-Time!'), 'good time');
    expect(tokenizer.isCjkToken('我'), isTrue);
    expect(tokenizer.isCjkToken('we'), isFalse);
  });
}
