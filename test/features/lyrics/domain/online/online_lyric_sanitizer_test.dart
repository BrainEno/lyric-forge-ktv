import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/online/online_lyric_sanitizer.dart';

void main() {
  const sanitizer = OnlineLyricSanitizer();

  test('去掉作词作曲等署名行和「歌名 - 歌手」标题行', () {
    final cleaned = sanitizer.sanitize(
      [
        '[00:00.00]夜航 - 林小雨',
        '[00:01.00]作词 : 林小雨',
        '[00:02.00]作曲：陈大海',
        '[00:03.00]Producer: Someone',
        '[00:10.00]窗外的雨停了又下',
      ].join('\n'),
      title: '夜航',
      artist: '林小雨',
    );
    expect(cleaned, '[00:10.00]窗外的雨停了又下');
  });

  test('酷狗的 CRLF 换行与 LRC 元数据不影响结果', () {
    final cleaned = sanitizer.sanitize(
      '[ti:夜航]\r\n[ar:林小雨]\r\n[00:01.00]词：林小雨\r\n[00:10.00]我还在等你的回答\r\n',
      title: '夜航',
      artist: '林小雨',
    );
    expect(cleaned.contains('词：'), isFalse);
    expect(cleaned.contains('我还在等你的回答'), isTrue);
    expect(cleaned.contains('[ti:夜航]'), isTrue);
  });

  test('只等于歌名的首行可能是唱出来的，保留', () {
    final cleaned = sanitizer.sanitize('夜航\n窗外的雨停了又下', title: '夜航');
    expect(cleaned.split('\n'), ['夜航', '窗外的雨停了又下']);
  });

  test('纯音乐提示返回空字符串', () {
    expect(sanitizer.sanitize('[00:00.00]纯音乐，请欣赏'), isEmpty);
    expect(sanitizer.sanitize('[00:00.00]此歌曲为没有填词的纯音乐，请您欣赏'), isEmpty);
  });

  test('含「纯音乐」字样的长歌词行不当作提示', () {
    const sung = '我把心事写进一首没有名字的纯音乐里慢慢地唱给你听直到天亮';
    expect(sanitizer.sanitize(sung), sung);
  });

  test('标题行只在开头几行内识别', () {
    final cleaned = sanitizer.sanitize(
      '窗外的雨停了又下\n夜航 - 林小雨',
      title: '夜航',
      artist: '林小雨',
    );
    expect(cleaned.split('\n'), hasLength(2));
  });

  test('isTimed 区分 LRC 与纯文本', () {
    expect(sanitizer.isTimed('[00:12.34]窗外'), isTrue);
    expect(sanitizer.isTimed('窗外的雨停了又下'), isFalse);
  });
}
