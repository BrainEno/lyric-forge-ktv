import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_timing.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/project_manifest.dart';

LyricLine _plain(String text) =>
    LyricLine(text: text, startTime: Duration.zero, endTime: Duration.zero);

LyricLine _timed(String text, int startMs, int endMs) => LyricLine(
  text: text,
  startTime: Duration(milliseconds: startMs),
  endTime: Duration(milliseconds: endMs),
);

ProjectManifest _project(LyricDocument? document) => ProjectManifest(
  id: 'p',
  name: 'Song',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  lyricDocument: document,
);

void main() {
  group('isUntimed', () {
    test('plain lines are untimed', () {
      final document = LyricDocument(
        language: 'zh',
        lines: [_plain('第一句'), _plain('第二句')],
      );
      expect(document.isUntimed, isTrue);
      expect(document.isTimed, isFalse);
      expect(document.timedLineCount, 0);
    });

    test('an empty document is neither timed nor untimed', () {
      const document = LyricDocument(language: 'zh', lines: []);
      expect(document.isUntimed, isFalse);
      expect(document.isTimed, isFalse);
    });

    test('a first line at 0:00 with an end is timed', () {
      final document = LyricDocument(
        language: 'zh',
        lines: [_timed('第一句', 0, 2000), _plain('第二句')],
      );
      expect(document.isUntimed, isFalse);
      expect(document.isTimed, isTrue);
      expect(document.timedLineCount, 1);
    });

    test('word timing alone makes a line timed', () {
      final document = LyricDocument(
        language: 'zh',
        lines: [
          LyricLine(
            text: '你好',
            startTime: Duration.zero,
            endTime: Duration.zero,
            words: const [
              LyricWordTiming(
                text: '你',
                start: Duration(milliseconds: 100),
                end: Duration(milliseconds: 300),
              ),
            ],
          ),
        ],
      );
      expect(document.isUntimed, isFalse);
    });

    test('a stale timed:false flag does not hide lyrics timed later', () {
      final document = LyricDocument(
        language: 'zh',
        lines: [_timed('第一句', 1000, 2000)],
        metadata: const {'timed': false},
      );
      expect(document.isTimed, isTrue);
    });
  });

  test('withoutTimestamps keeps words and drops every time', () {
    final document = LyricDocument(
      language: 'zh',
      globalOffset: const Duration(milliseconds: 300),
      metadata: const {'timed': true, 'source': 'online-lyrics'},
      lines: [
        LyricLine(
          text: '第一句',
          startTime: const Duration(seconds: 1),
          endTime: const Duration(seconds: 2),
          isChorus: true,
          id: 'a',
          words: const [
            LyricWordTiming(
              text: '第',
              start: Duration(seconds: 1),
              end: Duration(milliseconds: 1200),
            ),
          ],
        ),
        _timed('第二句', 3000, 4000),
      ],
    );
    final plain = document.withoutTimestamps();
    expect(plain.isUntimed, isTrue);
    expect(plain.lines.map((line) => line.text), ['第一句', '第二句']);
    expect(plain.lines.first.isChorus, isTrue);
    expect(plain.lines.first.id, 'a');
    expect(plain.lines.first.words, isEmpty);
    expect(plain.globalOffset, isNull);
    expect(plain.metadata['timed'], isFalse);
    expect(plain.metadata['timestampsRemoved'], isTrue);
    expect(plain.metadata['source'], 'online-lyrics');
    expect(plain.language, 'zh');
  });

  group('activeLineIndex', () {
    final document = LyricDocument(
      language: 'zh',
      lines: [
        _timed('一', 1000, 2000),
        _timed('二', 3000, 4000),
        _timed('三', 5000, 6000),
      ],
    );

    test('follows the position', () {
      expect(document.activeLineIndex(Duration.zero), 0);
      expect(document.activeLineIndex(const Duration(milliseconds: 3500)), 1);
      expect(document.activeLineIndex(const Duration(seconds: 9)), 2);
    });

    test('honours the global offset and a previewed nudge', () {
      final shifted = document.copyWith(
        globalOffset: const Duration(seconds: 1),
      );
      expect(shifted.activeLineIndex(const Duration(milliseconds: 3500)), 0);
      expect(
        document.activeLineIndex(
          const Duration(milliseconds: 3500),
          extraOffset: const Duration(seconds: 1),
        ),
        0,
      );
      expect(
        document.activeLineIndex(
          const Duration(milliseconds: 2500),
          extraOffset: const Duration(seconds: -1),
        ),
        1,
      );
    });

    test('is null for untimed lyrics', () {
      final plain = document.withoutTimestamps();
      expect(plain.activeLineIndex(const Duration(seconds: 4)), isNull);
    });
  });

  test('effectiveStart never goes below zero', () {
    final document = LyricDocument(
      language: 'zh',
      globalOffset: const Duration(seconds: -5),
      lines: [_timed('一', 1000, 2000)],
    );
    expect(document.effectiveStart(document.lines.first), Duration.zero);
    expect(
      document.effectiveStart(
        document.lines.first,
        extraOffset: const Duration(seconds: 6),
      ),
      const Duration(seconds: 2),
    );
  });

  test('lastTimedStart ignores untimed rows', () {
    final document = LyricDocument(
      language: 'zh',
      lines: [_timed('一', 1000, 2000), _timed('二', 8000, 9000), _plain('新')],
    );
    expect(document.lastTimedStart, const Duration(seconds: 8));
    expect(document.withoutTimestamps().lastTimedStart, isNull);
  });

  test('project timing helpers', () {
    expect(_project(null).hasTimedLyrics, isFalse);
    expect(_project(null).hasUntimedLyrics, isFalse);
    final plain = _project(LyricDocument(language: 'zh', lines: [_plain('一')]));
    expect(plain.hasUntimedLyrics, isTrue);
    expect(plain.hasTimedLyrics, isFalse);
    final timed = _project(
      LyricDocument(language: 'zh', lines: [_timed('一', 0, 1000)]),
    );
    expect(timed.hasTimedLyrics, isTrue);
    expect(timed.hasUntimedLyrics, isFalse);
  });
}
