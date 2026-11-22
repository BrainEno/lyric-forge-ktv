import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/vocal_check_record.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/spoken_language.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/vocal_activity.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/whisper_decoding_policy.dart';

const _frame = Duration(milliseconds: 20);
const _policy = SpokenLanguagePolicy();

/// An envelope of [seconds] with [loud] stretches at 0.5 RMS, the rest at
/// [quiet].
VocalEnergyEnvelope _envelope(
  int seconds, {
  List<(int, int)> loud = const [],
  double quiet = 0.01,
}) {
  final frames = seconds * 50;
  return VocalEnergyEnvelope(
    frameLength: _frame,
    frameRms: [
      for (var index = 0; index < frames; index++)
        loud.any((span) => index >= span.$1 * 50 && index < span.$2 * 50)
            ? 0.5
            : quiet,
    ],
  );
}

VocalActivityProfile _profile(
  int seconds, {
  List<(int, int)> sung = const [],
  bool reliable = true,
}) => VocalActivityProfile(
  duration: Duration(seconds: seconds),
  referenceDb: -12,
  floorDb: -60,
  thresholdDb: -40,
  regions: [
    for (final span in sung)
      LyricVocalCheckSpan(Duration(seconds: span.$1), Duration(seconds: span.$2)),
  ],
  unreliability: reliable ? null : VocalActivityUnreliability.silent,
);

List<List<int>> _starts(List<List<SpokenLanguageWindow>> probes) => [
  for (final probe in probes)
    [for (final window in probe) window.start.inSeconds],
];

void main() {
  group('probeWindows', () {
    test('a vocal stem silent until the verse is heard at the verse', () {
      // 45 s of intro, then singing: the case whisper gets wrong on its own.
      final probes = _policy.probeWindows(
        _envelope(180, loud: [(45, 75), (100, 130)]),
        _profile(180, sung: [(45, 75), (100, 130)]),
      );
      // Full windows first; the half-sung edges of the verse come last.
      expect(_starts(probes), [
        [50, 60, 100],
        [40, 110, 120],
      ]);
      expect(probes.first.every((w) => w.duration.inSeconds == 10), isTrue);
    });

    test('in a mix the loudest stretches count', () {
      final probes = _policy.probeWindows(
        _envelope(120, loud: [(60, 90)]),
        _profile(120, reliable: false),
      );
      expect(_starts(probes).first, [60, 70, 80]);
      // The rest is under a fifth of the loudest: no second probe.
      expect(probes, hasLength(1));
    });

    test('an even mix gets two probes, the earliest windows first', () {
      final probes = _policy.probeWindows(
        _envelope(100, quiet: 0.3),
        _profile(100, reliable: false),
      );
      expect(_starts(probes), [
        [0, 10, 20],
        [30, 40, 50],
      ]);
    });

    test('a short song is heard whole', () {
      final probes = _policy.probeWindows(
        _envelope(25, loud: [(5, 20)]),
        _profile(25, sung: [(5, 20)]),
      );
      expect(probes, hasLength(1));
      expect(probes.single.single.start, Duration.zero);
      expect(probes.single.single.end, const Duration(seconds: 25));
    });

    test('a stem without singing gives nothing to probe', () {
      expect(
        _policy.probeWindows(_envelope(120), _profile(120, sung: [(10, 11)])),
        isEmpty,
      );
      expect(
        _policy.probeWindows(_envelope(20), _profile(20, sung: [(1, 2)])),
        isEmpty,
      );
      expect(
        _policy.probeWindows(
          const VocalEnergyEnvelope(frameLength: _frame, frameRms: []),
          _profile(0),
        ),
        isEmpty,
      );
    });
  });

  group('decide', () {
    test('a confident probe wins', () {
      final resolution = _policy.decide(
        probes: const [SpokenLanguageProbe('en', 0.93)],
        songInfoLanguage: 'zh',
      );
      expect(resolution.language, 'en');
      expect(resolution.source, SpokenLanguageSource.detected);
      expect(resolution.isResolved, isTrue);
      expect(resolution.summary, '演唱语言：英文');
    });

    test('Norwegian from a weak probe never pins the song', () {
      final resolution = _policy.decide(
        probes: const [SpokenLanguageProbe('nn', 0.62)],
        songInfoLanguage: 'en',
      );
      expect(resolution.language, 'en');
      expect(resolution.source, SpokenLanguageSource.songInfo);
      expect(resolution.summary, '演唱语言：英文（按歌名判断）');

      final alone = _policy.decide(
        probes: const [SpokenLanguageProbe('nn', 0.62)],
      );
      expect(alone.isResolved, isFalse);
      expect(alone.language, 'auto');
      expect(alone.summary, contains('自动检测'));
    });

    test('a very confident Norwegian probe is believed', () {
      final resolution = _policy.decide(
        probes: const [SpokenLanguageProbe('nn', 0.95)],
      );
      expect(resolution.language, 'nn');
      expect(resolution.source, SpokenLanguageSource.detected);
    });

    test('the most confident of two probes counts', () {
      final resolution = _policy.decide(
        probes: const [
          SpokenLanguageProbe('de', 0.55),
          SpokenLanguageProbe('en', 0.81),
        ],
      );
      expect(resolution.language, 'en');
    });

    test('without song info a weak ordinary probe is still used', () {
      final weak = _policy.decide(
        probes: const [SpokenLanguageProbe('en', 0.31)],
      );
      expect(weak.language, 'en');
      final tooWeak = _policy.decide(
        probes: const [SpokenLanguageProbe('en', 0.12)],
      );
      expect(tooWeak.isResolved, isFalse);
    });

    test('an error is kept with whatever was decided', () {
      final resolution = _policy.decide(
        probes: const [],
        songInfoLanguage: 'ja',
        windows: const [SpokenLanguageWindow(Duration.zero, Duration(seconds: 10))],
        error: 'whisper missing',
      );
      expect(resolution.language, 'ja');
      final json = resolution.toJson();
      expect(json['source'], 'songInfo');
      expect(json['songInfoLanguage'], 'ja');
      expect(json['error'], 'whisper missing');
      expect(json['windows'], [
        {'startMs': 0, 'endMs': 10000},
      ]);
      expect(
        _policy.decide(probes: const []).toJson(),
        isNot(contains('error')),
      );
    });
  });

  group('song info', () {
    String? of(String title, [String artist = '']) =>
        SpokenLanguagePolicy.languageFromSongInfo(
          RecognitionHints(songTitle: title, artist: artist),
        );

    test('English titles and artists', () {
      expect(of('Riders on the Storm', 'The Doors'), 'en');
      expect(of('Light My Fire'), 'en');
      expect(of('Hotel California', 'Eagles'), 'en');
    });

    test('CJK scripts', () {
      expect(of('晴天', '周杰伦'), 'zh');
      expect(of('夜に駆ける', 'YOASOBI'), 'ja');
      expect(of('봄날', 'BTS'), 'ko');
    });

    test('says nothing when unsure', () {
      expect(of(''), isNull);
      expect(of('Despacito', 'Luis Fonsi'), isNull);
      expect(of('Ne me quitte pas', 'Jacques Brel'), isNull);
      expect(of('Für Elise'), isNull);
      // One English-looking word among many is not enough.
      expect(of('Te quiero mi love para siempre'), isNull);
    });
  });

  group('pinning', () {
    const config = TranscriptionConfig(
      mode: TranscriptionMode.whisperOnly,
      whisperExecutable: 'whisper',
      modelPath: 'model',
    );

    test('only an automatic config is pinned', () {
      expect(
        SpokenLanguagePolicy.withKnownLanguage(config, 'en').language,
        'en',
      );
      expect(
        SpokenLanguagePolicy.withKnownLanguage(
          config.copyWith(language: 'zh'),
          'en',
        ).language,
        'zh',
      );
      expect(
        SpokenLanguagePolicy.withKnownLanguage(config, 'auto').language,
        'auto',
      );
      expect(
        SpokenLanguagePolicy.withKnownLanguage(config, null).language,
        'auto',
      );
      expect(
        SpokenLanguagePolicy.withKnownLanguage(config, 'unknown').language,
        'auto',
      );
    });

    test('a project remembers the language of its recognition', () {
      Map<String, dynamic> withTranscription(Map<String, Object?> value) => {
        'transcription': value,
      };
      expect(
        SpokenLanguageResolution.languageOfProject(
          withTranscription({
            'detectedLanguage': 'nn',
            'spokenLanguage': const SpokenLanguageResolution(
              language: 'en',
              source: SpokenLanguageSource.detected,
            ).toJson(),
          }),
        ),
        'en',
      );
      // Before D-061: the engines' own answer, unless it is a typical
      // misdetection.
      expect(
        SpokenLanguageResolution.languageOfProject(
          withTranscription({'detectedLanguage': 'en'}),
        ),
        'en',
      );
      expect(
        SpokenLanguageResolution.languageOfProject(
          withTranscription({'detectedLanguage': 'nn'}),
        ),
        isNull,
      );
      expect(
        SpokenLanguageResolution.languageOfProject(
          withTranscription({
            'detectedLanguage': 'nn',
            'spokenLanguage': const SpokenLanguageResolution.unresolved()
                .toJson(),
          }),
        ),
        isNull,
      );
      expect(SpokenLanguageResolution.languageOfProject(const {}), isNull);
    });
  });
}
