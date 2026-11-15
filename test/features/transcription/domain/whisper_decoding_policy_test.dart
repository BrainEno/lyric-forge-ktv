import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/whisper_decoding_policy.dart';

const _fullHelp = '''
usage: whisper-cli [options] file0 file1 ...
supported audio formats: flac, mp3, ogg, wav

options:
  -h,        --help              [default] show this help message and exit
  -t N,      --threads N         [4      ] number of threads to use during computation
  -bs N,     --beam-size N       [5      ] beam size for beam search
  -nf,       --no-fallback       [false  ] do not use temperature fallback while decoding
  -pp,       --print-progress    [false  ] print progress
  -ojf,      --output-json-full  [false  ] include more information in the JSON file
  -of FNAME, --output-file FNAME [       ] output file path (without file extension)
  -sns,      --suppress-nst      [false  ] suppress non-speech tokens
  --prompt PROMPT                [       ] initial prompt (max n_text_ctx/2 tokens)
  --carry-initial-prompt         [false  ] always prepend initial prompt
  -m FNAME,  --model FNAME       [models/ggml-base.en.bin] model path
  -f FNAME,  --file FNAME        [       ] input audio file path
''';

/// An older build: same core flags, no `--suppress-nst`, no `--prompt`.
const _oldHelp = '''
usage: main [options] file0.wav file1.wav ...
  -h,       --help           [default] show this help message and exit
  -pp,      --print-progress [false  ] print progress
  -m FNAME, --model FNAME    [models/ggml-base.en.bin] model path
  -f FNAME, --file FNAME     [       ] input WAV file path
''';

void main() {
  const policy = WhisperDecodingPolicy();
  final full = WhisperRuntimeCapabilities.fromHelpText(_fullHelp);
  final old = WhisperRuntimeCapabilities.fromHelpText(_oldHelp);

  group('WhisperRuntimeCapabilities', () {
    test('reads long flags from real-shaped help text', () {
      expect(full.probed, isTrue);
      expect(full.supports('--prompt'), isTrue);
      expect(full.supports('--suppress-nst'), isTrue);
      expect(full.supports('--vad'), isFalse);
      expect(old.probed, isTrue);
      expect(old.supports('--prompt'), isFalse);
    });

    test('text that is not whisper help is unknown, not empty-supported', () {
      final caps = WhisperRuntimeCapabilities.fromHelpText(
        'bash: whisper-cli: --prompt not found',
      );
      expect(caps.probed, isFalse);
      expect(caps.supports('--prompt'), isFalse);
      expect(WhisperRuntimeCapabilities.unknown.supports('--model'), isFalse);
    });

    test('recognises the unknown-argument stderr line', () {
      expect(
        WhisperRuntimeCapabilities.isUnknownArgumentLine(
          'error: unknown argument: --suppress-nst',
        ),
        isTrue,
      );
      expect(
        WhisperRuntimeCapabilities.isUnknownArgumentLine(
          'whisper_init_from_file: loading model',
        ),
        isFalse,
      );
    });
  });

  group('plan', () {
    const hints = RecognitionHints(songTitle: 'Neon Harbor', artist: 'Mira');

    test('standard profile never probes or adds flags', () {
      final plan = policy.plan(
        profile: WhisperDecodingProfile.standard,
        hints: hints,
        language: 'en',
        capabilities: full,
      );
      expect(plan.isStandard, isTrue);
      expect(plan.prompt, isNull);
      expect(plan.effectiveProfile.id, 'whisper-standard-v1');
      expect(plan.requestedProfile.id, 'whisper-standard-v1');
    });

    test('lyrics profile on a capable runtime adds prompt and nst', () {
      final plan = policy.plan(
        profile: WhisperDecodingProfile.lyrics,
        hints: hints,
        language: 'en',
        capabilities: full,
      );
      expect(plan.extraArguments, [
        '--prompt',
        'Song: Neon Harbor. Artist: Mira.',
        '--suppress-nst',
      ]);
      expect(plan.effectiveProfile, WhisperDecodingProfile.lyrics);
      expect(plan.promptSources, ['title', 'artist']);
      expect(plan.omittedFlags, isEmpty);
    });

    test('never uses carry-initial-prompt even when advertised', () {
      final plan = policy.plan(
        profile: WhisperDecodingProfile.lyrics,
        hints: hints,
        language: 'en',
        capabilities: full,
      );
      expect(plan.extraArguments, isNot(contains('--carry-initial-prompt')));
    });

    test('an old runtime falls back to the exact standard line', () {
      final plan = policy.plan(
        profile: WhisperDecodingProfile.lyrics,
        hints: hints,
        language: 'en',
        capabilities: old,
      );
      expect(plan.isStandard, isTrue);
      expect(plan.requestedProfile, WhisperDecodingProfile.lyrics);
      expect(plan.effectiveProfile, WhisperDecodingProfile.standard);
      expect(plan.omittedFlags, ['--prompt', '--suppress-nst']);
    });

    test('an unknown runtime falls back to standard', () {
      final plan = policy.plan(
        profile: WhisperDecodingProfile.lyrics,
        hints: hints,
        language: 'en',
        capabilities: WhisperRuntimeCapabilities.unknown,
      );
      expect(plan.isStandard, isTrue);
      expect(plan.toMetadata()['effectiveProfile'], 'whisper-standard-v1');
    });

    test('no hints still applies non-speech suppression only', () {
      final plan = policy.plan(
        profile: WhisperDecodingProfile.lyrics,
        hints: RecognitionHints.none,
        language: 'auto',
        capabilities: full,
      );
      expect(plan.extraArguments, ['--suppress-nst']);
      expect(plan.prompt, isNull);
    });

    test('metadata redacts the prompt text and reports its size', () {
      final plan = policy.plan(
        profile: WhisperDecodingProfile.lyrics,
        hints: const RecognitionHints(songTitle: '夜航'),
        language: 'zh',
        capabilities: full,
      );
      final metadata = plan.toMetadata(fallbackReason: 'x');
      expect(metadata['arguments'], ['--prompt', '<prompt>', '--suppress-nst']);
      expect(jsonEncode(metadata), isNot(contains('夜航')));
      expect(metadata['promptRunes'], plan.prompt!.runes.length);
      expect(metadata['promptUtf8Bytes'], utf8.encode(plan.prompt!).length);
      expect(metadata['fallbackReason'], 'x');
    });
  });

  group('buildPrompt', () {
    test('uses a template per language', () {
      String? prompt(String language) => policy
          .buildPrompt(
            hints: const RecognitionHints(songTitle: '夜航', artist: '林'),
            language: language,
          )
          ?.text;
      expect(prompt('zh'), '歌曲《夜航》，演唱：林。');
      expect(prompt('yue'), '歌曲《夜航》，演唱：林。');
      expect(prompt('ja'), '曲名「夜航」、歌手：林。');
      expect(prompt('en'), 'Song: 夜航. Artist: 林.');
      // Auto detection gets bare names only, so no language is implied.
      expect(prompt('auto'), '夜航, 林');
      expect(prompt('zh-TW'), '歌曲《夜航》，演唱：林。');
    });

    test('returns null when nothing usable is provided', () {
      expect(
        policy.buildPrompt(
          hints: const RecognitionHints(songTitle: '  ', terms: ['', ' ']),
          language: 'en',
        ),
        isNull,
      );
    });

    test('cleans file-name noise from titles', () {
      expect(
        WhisperDecodingPolicy.sanitizeTitle(
          '03 - Neon_Harbor (Official Lyric Video).mp3',
        ),
        'Neon Harbor',
      );
      expect(WhisperDecodingPolicy.sanitizeTitle('夜航【官方歌词版】.flac'), '夜航');
      // A title that merely contains a bracket stays intact.
      expect(
        WhisperDecodingPolicy.sanitizeTitle('Song (For You)'),
        'Song (For You)',
      );
    });

    test('strips control characters, quotes and newlines', () {
      expect(
        WhisperDecodingPolicy.sanitizeField('A\n"B"\t<C>\u0000 [D]'),
        'A B C D',
      );
    });

    test('a newline in metadata cannot inject an extra argument line', () {
      final prompt = policy.buildPrompt(
        hints: const RecognitionHints(songTitle: 'Title\n-m\nother.bin'),
        language: 'en',
      );
      expect(prompt!.text, isNot(contains('\n')));
      expect(prompt.text, 'Song: Title -m other.bin.');
    });

    test('caps every prompt at the UTF-8 byte budget', () {
      final hints = RecognitionHints(
        songTitle: '很' * 200,
        artist: '长' * 200,
        album: '专' * 200,
        terms: [for (var i = 0; i < 40; i++) '名词$i'],
      );
      for (final language in ['zh', 'ja', 'en', 'auto']) {
        final prompt = policy.buildPrompt(hints: hints, language: language)!;
        expect(
          utf8.encode(prompt.text).length,
          lessThanOrEqualTo(WhisperDecodingPolicy.maxPromptUtf8Bytes),
          reason: language,
        );
      }
    });

    test('field truncation never splits a surrogate pair', () {
      final value = WhisperDecodingPolicy.sanitizeField('🎵' * 100);
      expect(value.runes.length, WhisperDecodingPolicy.maxFieldRunes);
      expect(value.runes.every((rune) => rune == 0x1F3B5), isTrue);
      // Re-encoding round-trips, which fails on a lone surrogate.
      expect(utf8.decode(utf8.encode(value)), value);
    });

    test('byte truncation keeps whole code points', () {
      final prompt = policy.buildPrompt(
        hints: RecognitionHints(songTitle: '🎵' * 60, artist: '😀' * 60),
        language: 'auto',
      )!;
      expect(utf8.decode(utf8.encode(prompt.text)), prompt.text);
      expect(
        utf8.encode(prompt.text).length,
        lessThanOrEqualTo(WhisperDecodingPolicy.maxPromptUtf8Bytes),
      );
    });

    test('terms are deduplicated, capped and dropped whole', () {
      final prompt = policy.buildPrompt(
        hints: RecognitionHints(
          terms: [
            'Kaohsiung',
            'kaohsiung',
            for (var i = 0; i < 30; i++) 'Term$i',
          ],
        ),
        language: 'en',
      )!;
      final names = prompt.text
          .replaceFirst('Names: ', '')
          .replaceFirst(RegExp(r'\.$'), '')
          .split(', ');
      expect(names.first, 'Kaohsiung');
      expect(names.where((name) => name.toLowerCase() == 'kaohsiung'), [
        'Kaohsiung',
      ]);
      expect(names.length, lessThanOrEqualTo(WhisperDecodingPolicy.maxTerms));
      expect(prompt.sources, ['terms']);
    });

    test('the album is skipped when it equals the title', () {
      final prompt = policy.buildPrompt(
        hints: const RecognitionHints(
          songTitle: 'Blue',
          artist: 'Mira',
          album: 'Blue',
        ),
        language: 'en',
      )!;
      expect(prompt.text, 'Song: Blue. Artist: Mira.');
      expect(prompt.sources, ['title', 'artist']);
    });
  });

  group('fingerprintMaterial', () {
    const hints = RecognitionHints(songTitle: 'A', artist: 'B');

    test('is stable and changes with anything that changes decoding', () {
      String material({
        WhisperDecodingProfile profile = WhisperDecodingProfile.lyrics,
        RecognitionHints value = hints,
        String language = 'en',
      }) => policy.fingerprintMaterial(
        profile: profile,
        hints: value,
        language: language,
      );

      expect(material(), material());
      expect(material(), isNot(material(language: 'zh')));
      expect(
        material(),
        isNot(material(value: const RecognitionHints(songTitle: 'C'))),
      );
      expect(
        material(),
        isNot(material(profile: WhisperDecodingProfile.standard)),
      );
    });

    test('standard ignores hints, so old checkpoints stay comparable', () {
      expect(
        policy.fingerprintMaterial(
          profile: WhisperDecodingProfile.standard,
          hints: hints,
          language: 'en',
        ),
        policy.fingerprintMaterial(
          profile: WhisperDecodingProfile.standard,
          hints: RecognitionHints.none,
          language: 'zh',
        ),
      );
    });
  });

  test('RecognitionHints has no lyric field', () {
    // Guard rail: the hint type must stay metadata-only. If a lyric field is
    // ever added, this list changes and the reviewer has to look.
    const hints = RecognitionHints(
      songTitle: 't',
      artist: 'a',
      album: 'b',
      terms: ['x'],
    );
    expect(hints.isEmpty, isFalse);
    expect(RecognitionHints.none.isEmpty, isTrue);
  });
}
