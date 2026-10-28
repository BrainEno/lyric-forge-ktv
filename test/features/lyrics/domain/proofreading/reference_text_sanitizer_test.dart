import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/proofreading/reference_text_sanitizer.dart';

void main() {
  const sanitizer = ReferenceTextSanitizer();

  test('removes title, section headers and page noise but keeps adlibs', () {
    final result = sanitizer.sanitize(
      "Roadhouse Blues Lyrics\n[Verse 1]\nKeep your eyes on the road\n\n"
      "(Oh yeah)\n[Chorus]\nYeah, we're going to the roadhouse\n123Embed",
      title: 'Roadhouse Blues',
    );
    expect(result.lines, [
      'Keep your eyes on the road',
      '(Oh yeah)',
      "Yeah, we're going to the roadhouse",
    ]);
    expect(result.removed.map((line) => line.reason).toList(), [
      RemovedReason.titleLine,
      RemovedReason.sectionHeader,
      RemovedReason.sectionHeader,
      RemovedReason.pageNoise,
    ]);
  });
  test('removes a generic Lyrics title when no song title is supplied', () {
    final result = sanitizer.sanitize('Lyrics\nHello');
    expect(result.lines, ['Hello']);
    expect(result.removed, hasLength(1));
    expect(result.removed.single.reason, RemovedReason.titleLine);
  });
  test('removes Chinese credits', () {
    final result = sanitizer.sanitize('作词：张三\n我在这里');
    expect(result.lines, ['我在这里']);
    expect(result.removed, hasLength(1));
    expect(result.removed.single.reason, RemovedReason.creditLine);
  });
  test('preserves repeated lyric lines', () {
    final result = sanitizer.sanitize('Oh oh oh\nOh oh oh');
    expect(result.lines, ['Oh oh oh', 'Oh oh oh']);
    expect(result.removed, isEmpty);
  });
}
