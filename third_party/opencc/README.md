# OpenCC dictionary data

`lib/features/lyrics/domain/text/chinese_script_data.g.dart` is derived from
the dictionaries of [OpenCC](https://github.com/BYVoid/OpenCC) (Open Chinese
Convert), revision `fae2a0a911c30764e669a7d8b0591cd8e852934a`, licensed under
the Apache License 2.0 (copy in `LICENSE`).

Files used: `STCharacters`, `TSCharacters`, `STPhrases`, `TSPhrases`,
`TWVariants`, `TWVariantsPhrases`, `TWVariantsRevPhrases`, `HKVariants`,
`HKVariantsPhrases`, `HKVariantsRevPhrases`.

Modifications, all made by `tool/generate_chinese_script_tables.dart`:

- every entry keeps only its default (first) candidate;
- phrase entries whose value equals the character-level conversion of the
  key are stored as the bare key and rebuilt when parsed (they are kept,
  because they still steer forward-maximum-matching segmentation);
- script-specific character sets are computed from all candidates.

No OpenCC code is included; LyricForge implements its own converter in Dart.
