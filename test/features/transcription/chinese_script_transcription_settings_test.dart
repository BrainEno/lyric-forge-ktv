import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/chinese_script_preference.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/text/chinese_script_converter.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/whisper_decoding_policy.dart';

void main() {
  const base = TranscriptionConfig(whisperExecutable: 'w', modelPath: 'm');

  group('TranscriptionConfig.chineseScriptPreference', () {
    test('defaults to automatic and survives a JSON round trip', () {
      expect(base.chineseScriptPreference, ChineseScriptPreference.auto);
      for (final value in ChineseScriptPreference.values) {
        final config = base.copyWith(chineseScriptPreference: value);
        final restored = TranscriptionConfig.fromJson(config.toJson());
        expect(restored.chineseScriptPreference, value);
      }
    });

    test('settings saved before the option existed read as automatic', () {
      final json = base.toJson()..remove('chineseScriptPreference');
      expect(
        TranscriptionConfig.fromJson(json).chineseScriptPreference,
        ChineseScriptPreference.auto,
      );
      expect(
        TranscriptionConfig.fromJson({
          ...json,
          'chineseScriptPreference': 'unknown',
        }).chineseScriptPreference,
        ChineseScriptPreference.auto,
      );
    });

    test('output target follows the explicit choice, then the language', () {
      expect(base.chineseScriptOutputTarget, isNull);
      expect(
        base
            .copyWith(
              chineseScriptPreference:
                  ChineseScriptPreference.traditionalHongKong,
            )
            .chineseScriptOutputTarget,
        ChineseScriptTarget.traditionalHongKong,
      );
      expect(
        base.copyWith(language: 'zh-TW').chineseScriptOutputTarget,
        ChineseScriptTarget.traditionalTaiwan,
      );
      expect(
        base
            .copyWith(
              language: 'zh-TW',
              chineseScriptPreference: ChineseScriptPreference.keep,
            )
            .chineseScriptOutputTarget,
        isNull,
      );
    });
  });

  group('Whisper prompt script', () {
    const policy = WhisperDecodingPolicy();
    const hints = RecognitionHints(songTitle: '夜航', artist: '林', album: '海');

    test('a traditional target writes the template words in traditional', () {
      final simplified = policy.buildPrompt(hints: hints, language: 'zh');
      final traditional = policy.buildPrompt(
        hints: hints,
        language: 'zh',
        chineseScript: ChineseScriptTarget.traditionalTaiwan,
      );
      expect(simplified?.text, '歌曲《夜航》，演唱：林，专辑：海。');
      expect(traditional?.text, '歌曲《夜航》，演唱：林，專輯：海。');
    });

    test('hint values keep the spelling the user typed', () {
      final prompt = policy.buildPrompt(
        hints: const RecognitionHints(songTitle: '后来', terms: ['发哥']),
        language: 'zh',
        chineseScript: ChineseScriptTarget.traditionalHongKong,
      );
      expect(prompt?.text, '歌曲《后来》，人名與專有名詞：发哥。');
    });

    test('other languages and simplified targets keep their templates', () {
      expect(
        policy
            .buildPrompt(
              hints: hints,
              language: 'ja',
              chineseScript: ChineseScriptTarget.traditionalTaiwan,
            )
            ?.text,
        policy.buildPrompt(hints: hints, language: 'ja')?.text,
      );
      expect(
        policy
            .buildPrompt(
              hints: hints,
              language: 'zh',
              chineseScript: ChineseScriptTarget.simplified,
            )
            ?.text,
        policy.buildPrompt(hints: hints, language: 'zh')?.text,
      );
    });

    test('the prompt script is part of the checkpoint fingerprint', () {
      String material(ChineseScriptTarget? script) =>
          policy.fingerprintMaterial(
            profile: WhisperDecodingProfile.lyrics,
            hints: hints,
            language: 'zh',
            chineseScript: script,
          );
      expect(material(null), material(ChineseScriptTarget.simplified));
      expect(
        material(null),
        isNot(material(ChineseScriptTarget.traditionalTaiwan)),
      );
    });
  });
}
