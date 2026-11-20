import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/vocal_check_record.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/vocal_activity.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/vocal_activity_analyzer.dart';

const _frame = Duration(milliseconds: 20);

Duration _ms(int value) => Duration(milliseconds: value);

/// An envelope of [seconds] at [quiet] RMS with [loud] stretches (start and
/// end in milliseconds, RMS).
VocalEnergyEnvelope _envelope(
  double seconds, {
  double quiet = 0.0003,
  List<(int, int, double)> loud = const [],
}) {
  final frames = (seconds * 1000 / _frame.inMilliseconds).round();
  return VocalEnergyEnvelope(
    frameLength: _frame,
    frameRms: [
      for (var index = 0; index < frames; index++)
        () {
          final ms = index * _frame.inMilliseconds;
          for (final (start, end, rms) in loud) {
            if (ms >= start && ms < end) return rms;
          }
          return quiet;
        }(),
    ],
  );
}

void main() {
  const analyzer = VocalActivityAnalyzer();

  test('dB conversion clamps silence', () {
    expect(VocalActivityAnalyzer.toDb(1), closeTo(0, 1e-9));
    expect(VocalActivityAnalyzer.toDb(0.1), closeTo(-20, 1e-9));
    expect(VocalActivityAnalyzer.toDb(0.001), closeTo(-60, 1e-9));
    expect(VocalActivityAnalyzer.toDb(0), -120);
    expect(VocalActivityAnalyzer.toDb(-1), -120);
    expect(VocalActivityAnalyzer.toDb(1e-12), -120);
  });

  test('finds sung stretches between quiet ones', () {
    final profile = analyzer.analyze(
      _envelope(30, loud: [(5000, 12000, 0.2), (15000, 22000, 0.15)]),
    );
    expect(profile.isReliable, isTrue);
    expect(profile.regions, [
      LyricVocalCheckSpan(_ms(5000), _ms(12000)),
      LyricVocalCheckSpan(_ms(15000), _ms(22000)),
    ]);
    expect(profile.voiced, _ms(14000));
    expect(profile.duration, _ms(30000));
    expect(profile.contrastDb, greaterThan(40));
    expect(profile.thresholdDb, greaterThan(profile.floorDb));
    expect(profile.thresholdDb, lessThan(profile.referenceDb));
  });

  test('bridges breaths shorter than the bridge gap', () {
    final profile = analyzer.analyze(
      _envelope(
        20,
        loud: [(2000, 4000, 0.2), (4200, 6000, 0.2), (7000, 9000, 0.2)],
      ),
    );
    expect(profile.regions, [
      LyricVocalCheckSpan(_ms(2000), _ms(6000)),
      LyricVocalCheckSpan(_ms(7000), _ms(9000)),
    ]);
  });

  test('drops blips shorter than the minimum region', () {
    final profile = analyzer.analyze(
      _envelope(20, loud: [(1000, 1060, 0.3), (5000, 9000, 0.2)]),
    );
    expect(profile.regions, [LyricVocalCheckSpan(_ms(5000), _ms(9000))]);
  });

  test('quiet singing well inside the range still counts', () {
    // A soft verse 20 dB under the chorus.
    final profile = analyzer.analyze(
      _envelope(30, loud: [(2000, 8000, 0.02), (12000, 25000, 0.2)]),
    );
    expect(profile.regions, hasLength(2));
    expect(profile.regions.first.start, _ms(2000));
  });

  test('leftover bleed far under the singing is not singing', () {
    // Faint accompaniment leftovers in the intro, 40 dB under the vocal.
    final profile = analyzer.analyze(
      _envelope(30, loud: [(0, 6000, 0.002), (8000, 25000, 0.2)]),
    );
    expect(profile.regions, [LyricVocalCheckSpan(_ms(8000), _ms(25000))]);
  });

  test('a region reaching the end of the audio is closed there', () {
    final profile = analyzer.analyze(_envelope(10, loud: [(7000, 10000, 0.2)]));
    expect(profile.regions, [LyricVocalCheckSpan(_ms(7000), _ms(10000))]);
  });

  test('audio starting with singing opens a region at zero', () {
    final profile = analyzer.analyze(_envelope(10, loud: [(0, 3000, 0.2)]));
    expect(profile.regions.first.start, Duration.zero);
  });

  group('unreliable profiles', () {
    test('too short to judge', () {
      final profile = analyzer.analyze(_envelope(2, loud: [(0, 1000, 0.2)]));
      expect(profile.unreliability, VocalActivityUnreliability.tooShort);
      expect(profile.isReliable, isFalse);
      expect(profile.regions, isEmpty);
    });

    test('an empty envelope or a zero frame is too short', () {
      expect(
        analyzer
            .analyze(
              const VocalEnergyEnvelope(frameLength: _frame, frameRms: []),
            )
            .unreliability,
        VocalActivityUnreliability.tooShort,
      );
      expect(
        analyzer
            .analyze(
              VocalEnergyEnvelope(
                frameLength: Duration.zero,
                frameRms: List.filled(1000, 0.1),
              ),
            )
            .unreliability,
        VocalActivityUnreliability.tooShort,
      );
    });

    test('digital silence', () {
      final profile = analyzer.analyze(_envelope(20, quiet: 0));
      expect(profile.unreliability, VocalActivityUnreliability.silent);
    });

    test('a few audible frames in silence are still silence', () {
      final profile = analyzer.analyze(
        _envelope(20, quiet: 0, loud: [(1000, 1200, 0.2)]),
      );
      expect(profile.unreliability, VocalActivityUnreliability.silent);
    });

    test('a full mix imported as the vocal is low contrast', () {
      final profile = analyzer.analyze(
        _envelope(30, quiet: 0.08, loud: [(5000, 25000, 0.2)]),
      );
      expect(profile.unreliability, VocalActivityUnreliability.lowContrast);
      expect(profile.regions, isEmpty);
      expect(profile.contrastDb, lessThan(18));
    });

    test('constant noise is low contrast', () {
      final profile = analyzer.analyze(_envelope(30, quiet: 0.01));
      expect(profile.unreliability, VocalActivityUnreliability.lowContrast);
    });
  });

  test('a stem with digital silence between phrases is judged on the '
      'audible frames', () {
    final profile = analyzer.analyze(
      _envelope(30, quiet: 0, loud: [(3000, 9000, 0.1), (14000, 20000, 0.1)]),
    );
    expect(profile.isReliable, isTrue);
    expect(profile.regions, hasLength(2));
  });

  test('the threshold never drops under the absolute floor', () {
    // A very quiet but clean stem: reference -50 dB, silence beneath.
    final profile = analyzer.analyze(
      _envelope(20, quiet: 0.00001, loud: [(2000, 8000, 0.003)]),
    );
    expect(profile.thresholdDb, greaterThanOrEqualTo(-55));
  });

  group('profile queries', () {
    final profile = VocalActivityProfile(
      duration: _ms(60000),
      referenceDb: -12,
      floorDb: -70,
      thresholdDb: -42,
      regions: [
        LyricVocalCheckSpan(_ms(10000), _ms(20000)),
        LyricVocalCheckSpan(_ms(30000), _ms(35000)),
      ],
    );

    test('voicedWithin sums the overlap', () {
      expect(profile.voicedWithin(_ms(0), _ms(10000)), Duration.zero);
      expect(profile.voicedWithin(_ms(15000), _ms(32000)), _ms(7000));
      expect(profile.voicedWithin(_ms(0), _ms(60000)), _ms(15000));
      expect(profile.voicedWithin(_ms(19000), _ms(19000)), Duration.zero);
      expect(profile.voicedWithin(_ms(25000), _ms(21000)), Duration.zero);
    });

    test('firstVoiceIn and lastVoiceIn find the edges', () {
      expect(profile.firstVoiceIn(_ms(5000), _ms(15000)), _ms(10000));
      expect(profile.firstVoiceIn(_ms(12000), _ms(15000)), _ms(12000));
      expect(profile.firstVoiceIn(_ms(21000), _ms(29000)), isNull);
      expect(profile.firstVoiceIn(_ms(36000), _ms(50000)), isNull);
      expect(profile.lastVoiceIn(_ms(15000), _ms(28000)), _ms(20000));
      expect(profile.lastVoiceIn(_ms(15000), _ms(18000)), _ms(18000));
      expect(profile.lastVoiceIn(_ms(21000), _ms(29000)), isNull);
      expect(profile.lastVoiceIn(_ms(0), _ms(9000)), isNull);
      expect(profile.lastVoiceIn(_ms(0), _ms(60000)), _ms(35000));
    });

    test('summaryJson rounds levels', () {
      final json = profile.summaryJson();
      expect(json['durationMs'], 60000);
      expect(json['voicedMs'], 15000);
      expect(json['regions'], 2);
      expect(json['referenceDb'], -12.0);
      expect(json['unreliability'], isNull);
    });
  });
}
