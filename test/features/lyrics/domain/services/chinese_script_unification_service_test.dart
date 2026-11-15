import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/chinese_script_preference.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/chinese_script_unification_service.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/text/chinese_script_converter.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';

void main() {
  const service = ChineseScriptUnificationService();

  LyricDocument document(List<String> texts, {String language = 'zh'}) {
    return LyricDocument(
      language: language,
      lines: [
        for (var index = 0; index < texts.length; index++)
          LyricLine(
            id: 'line-$index',
            text: texts[index],
            startTime: Duration(seconds: index * 4),
            endTime: Duration(seconds: index * 4 + 3),
            confidence: 70 + index,
            confidenceSource: LyricConfidenceSource.heuristic,
          ),
      ],
      metadata: const {'editableDraft': true},
    );
  }

  group('automatic', () {
    test('converts the minority traditional line to simplified', () {
      final draft = document(['我爱你', '让我们一起唱', '頭髮飄在風裡', '你在哪里']);
      final plan = service.plan(
        draft,
        preference: ChineseScriptPreference.auto,
      );

      expect(plan.target, ChineseScriptTarget.simplified);
      expect(plan.changes.map((change) => change.index), [2]);
      expect(plan.changes.single.after, '头发飘在风里');
      expect(plan.changes.single.beforeKind, ChineseScriptKind.traditional);
      expect(plan.profile.simplifiedLines, 2);
      expect(plan.profile.traditionalLines, 1);
      expect(plan.profile.neutralLines, 1);
      expect(plan.profile.inconsistentLines, 1);
      expect(plan.noopReason, isNull);
    });

    test('converts the minority simplified line to Taiwan forms', () {
      final draft = document(['我愛你', '讓我們一起唱', '头发飘在风里', '你在哪裡']);
      final plan = service.plan(
        draft,
        preference: ChineseScriptPreference.auto,
      );

      expect(plan.target, ChineseScriptTarget.traditionalTaiwan);
      expect(plan.changes.single.index, 2);
      expect(plan.changes.single.after, '頭髮飄在風裡');
    });

    test('Cantonese lyrics default to Hong Kong forms', () {
      final draft = document([
        '我愛你',
        '讓我們一起唱',
        '头发飘在风里',
      ], language: 'yue');
      final plan = service.plan(
        draft,
        preference: ChineseScriptPreference.auto,
      );

      expect(plan.target, ChineseScriptTarget.traditionalHongKong);
      expect(plan.changes.single.after, '頭髮飄在風裏');
    });

    test('neutral lines stay as recognised', () {
      final plan = service.plan(
        document(['我爱你', '让我们一起唱', '你在哪里', '頭髮飄在風裡']),
        preference: ChineseScriptPreference.auto,
      );
      expect(plan.changes.map((change) => change.index), [3]);
    });

    test('mixed lines are converted to the majority script', () {
      final plan = service.plan(
        document(['我爱你', '让我们一起唱', '我愛你也爱我']),
        preference: ChineseScriptPreference.auto,
      );
      expect(plan.changes.single.index, 2);
      expect(plan.changes.single.after, '我爱你也爱我');
      expect(plan.changes.single.beforeKind, ChineseScriptKind.mixed);
    });

    test('a consistent document is left untouched', () {
      final draft = document(['我爱你', '你在哪里']);
      final plan = service.plan(
        draft,
        preference: ChineseScriptPreference.auto,
      );
      expect(plan.hasChanges, isFalse);
      expect(plan.target, isNull);
      expect(plan.noopReason, ChineseScriptNoopReason.alreadyConsistent);
      expect(identical(plan.applyTo(draft), draft), isTrue);
    });

    test('a tie needs a language tag or an explicit choice', () {
      final tie = service.plan(
        document(['我爱你', '我愛你']),
        preference: ChineseScriptPreference.auto,
      );
      expect(tie.hasChanges, isFalse);
      expect(tie.noopReason, ChineseScriptNoopReason.ambiguousMajority);

      final tagged = service.plan(
        document(['我爱你', '我愛你'], language: 'zh-TW'),
        preference: ChineseScriptPreference.auto,
      );
      expect(tagged.target, ChineseScriptTarget.traditionalTaiwan);
      expect(tagged.changes.single.index, 0);
      expect(tagged.changes.single.after, '我愛你');
    });
  });

  group('explicit target', () {
    test('converts neutral lines and adjusts traditional ones regionally', () {
      final plan = service.plan(
        document(['你在哪里', '裏面的着急', '台北的夜']),
        preference: ChineseScriptPreference.traditionalTaiwan,
      );
      expect(plan.target, ChineseScriptTarget.traditionalTaiwan);
      final byIndex = {
        for (final change in plan.changes) change.index: change.after,
      };
      expect(byIndex[0], '你在哪裡');
      expect(byIndex[1], '裡面的著急');
      // OpenCC writes 臺 for a neutral 台 when converting from simplified.
      expect(byIndex[2], '臺北的夜');
    });

    test('simplified target converts every traditional line', () {
      final plan = service.plan(
        document(['我愛你', '讓我們一起唱', '我爱你']),
        preference: ChineseScriptPreference.simplified,
      );
      expect(plan.changes.map((change) => change.after), ['我爱你', '让我们一起唱']);
    });

    test('keep never converts', () {
      final plan = service.plan(
        document(['我爱你', '我愛你']),
        preference: ChineseScriptPreference.keep,
      );
      expect(plan.hasChanges, isFalse);
      expect(plan.noopReason, ChineseScriptNoopReason.disabled);
    });
  });

  group('Japanese, Korean and protected lines', () {
    test('a Japanese document is never converted, even kanji-only lines', () {
      final plan = service.plan(
        document(['愛してる', '東京の夜', '遠い約束'], language: 'ja'),
        preference: ChineseScriptPreference.simplified,
      );
      expect(plan.hasChanges, isFalse);
      expect(plan.noopReason, ChineseScriptNoopReason.notChinese);
    });

    test('automatic language with mostly kana lines counts as Japanese', () {
      final plan = service.plan(
        document(['愛してる', '君の夢を見た', '遠い約束'], language: 'auto'),
        preference: ChineseScriptPreference.simplified,
      );
      expect(plan.noopReason, ChineseScriptNoopReason.notChinese);
    });

    test('kana lines inside a Chinese document are skipped', () {
      final plan = service.plan(
        document(['我愛你', '讓我們一起唱', '愛してる']),
        preference: ChineseScriptPreference.simplified,
      );
      expect(plan.changes.map((change) => change.index), [0, 1]);
      expect(plan.profile.japaneseOrKoreanLines, 1);
    });

    test('manually edited lines are skipped and reported', () {
      final draft = document(['我爱你', '让我们一起唱', '頭髮飄在風裡']);
      final plan = service.plan(
        draft,
        preference: ChineseScriptPreference.auto,
        protectedIndices: {2},
      );
      expect(plan.hasChanges, isFalse);
      expect(plan.skippedProtectedIndices, [2]);
      expect(plan.noopReason, ChineseScriptNoopReason.onlyProtectedLines);
    });

    test('a document without Han characters has nothing to do', () {
      final plan = service.plan(
        document(['hello', 'world'], language: 'zh'),
        preference: ChineseScriptPreference.simplified,
      );
      expect(plan.noopReason, ChineseScriptNoopReason.noChineseText);
    });
  });

  group('applyTo', () {
    test('changes only text and records the conversion', () {
      final draft = document(['我爱你', '让我们一起唱', '頭髮飄在風裡']);
      final plan = service.plan(
        draft,
        preference: ChineseScriptPreference.auto,
      );
      final applied = plan.applyTo(draft);

      expect(applied.lines.map((line) => line.text), [
        '我爱你',
        '让我们一起唱',
        '头发飘在风里',
      ]);
      for (var index = 0; index < draft.lines.length; index++) {
        final before = draft.lines[index];
        final after = applied.lines[index];
        expect(after.id, before.id);
        expect(after.startTime, before.startTime);
        expect(after.endTime, before.endTime);
        expect(after.confidence, before.confidence);
        expect(after.confidenceSource, before.confidenceSource);
      }
      expect(applied.metadata['editableDraft'], isTrue);
      final record = ChineseScriptUnificationRecord.tryParse(
        applied.metadata[ChineseScriptUnificationService.metadataKey],
      )!;
      expect(record.target, ChineseScriptTarget.simplified);
      expect(record.preference, ChineseScriptPreference.auto);
      expect(record.revision, const ChineseScriptConverter().revision);
      expect(record.convertedLineCount, 1);
      expect(record.convertedLineIds, ['line-2']);
    });

    test('refuses to apply over a line edited after planning', () {
      final draft = document(['我爱你', '让我们一起唱', '頭髮飄在風裡']);
      final plan = service.plan(
        draft,
        preference: ChineseScriptPreference.auto,
      );
      final edited = draft.copyWith(
        lines: [
          ...draft.lines.take(2),
          draft.lines[2].copyWith(text: '頭髮飄在風中'),
        ],
      );
      expect(() => plan.applyTo(edited), throwsStateError);
    });
  });

  group('record replay', () {
    const record = ChineseScriptUnificationRecord(
      target: ChineseScriptTarget.simplified,
      preference: ChineseScriptPreference.auto,
      revision: 'placeholder',
      convertedLineCount: 1,
      convertedLineIds: [],
    );

    test('explains exactly the converted text with matching tables', () {
      final current = ChineseScriptUnificationRecord(
        target: ChineseScriptTarget.simplified,
        preference: ChineseScriptPreference.auto,
        revision: const ChineseScriptConverter().revision,
        convertedLineCount: 1,
        convertedLineIds: const [],
      );
      expect(current.explains(original: '頭髮飄在風裡', current: '头发飘在风里'), isTrue);
      expect(current.explains(original: '頭髮飄在風裡', current: '頭髮飄在風裡'), isTrue);
      expect(current.explains(original: '頭髮飄在風裡', current: '头发飘在风中'), isFalse);
    });

    test('a different table revision cannot validate converted text', () {
      expect(record.explains(original: '頭髮飄在風裡', current: '头发飘在风里'), isFalse);
      expect(record.explains(original: '一样', current: '一样'), isTrue);
    });

    test('parsing rejects incomplete records', () {
      expect(ChineseScriptUnificationRecord.tryParse(null), isNull);
      expect(
        ChineseScriptUnificationRecord.tryParse({'target': 'simplified'}),
        isNull,
      );
      expect(
        ChineseScriptUnificationRecord.tryParse({
          'target': 'unknown',
          'revision': 'x',
        }),
        isNull,
      );
      final parsed = ChineseScriptUnificationRecord.tryParse(record.toJson());
      expect(parsed?.target, ChineseScriptTarget.simplified);
    });
  });

  group('language tags', () {
    test('imply scripts and recognise Chinese languages', () {
      expect(ChineseLanguageTag.isChinese('zh'), isTrue);
      expect(ChineseLanguageTag.isChinese('yue'), isTrue);
      expect(ChineseLanguageTag.isChinese('ja'), isFalse);
      expect(ChineseLanguageTag.isChinese('auto'), isNull);
      expect(
        ChineseLanguageTag.impliedTarget('zh-TW'),
        ChineseScriptTarget.traditionalTaiwan,
      );
      expect(
        ChineseLanguageTag.impliedTarget('zh_Hant_HK'),
        ChineseScriptTarget.traditionalHongKong,
      );
      expect(
        ChineseLanguageTag.impliedTarget('zh-Hans'),
        ChineseScriptTarget.simplified,
      );
      expect(ChineseLanguageTag.impliedTarget('zh'), isNull);
      expect(ChineseLanguageTag.impliedTarget('ja-JP'), isNull);
    });

    test('preference names round-trip and default to auto', () {
      for (final value in ChineseScriptPreference.values) {
        expect(ChineseScriptPreference.fromName(value.name), value);
      }
      expect(
        ChineseScriptPreference.fromName('nonsense'),
        ChineseScriptPreference.auto,
      );
      expect(ChineseScriptPreference.fromName(null), ChineseScriptPreference.auto);
    });
  });
}
