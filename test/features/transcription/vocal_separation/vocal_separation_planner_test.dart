import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/vocal_separation_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/vocal_separation_planner.dart';

const _revision = 'htdemucs-ft-vocals-onnx-v1';
final _modified = DateTime.utc(2026, 11, 18, 8);

VocalSeparationFacts _facts({
  bool sourceExists = true,
  int bytes = 4000000,
  DateTime? modified,
  bool vocalFileExists = false,
}) => VocalSeparationFacts(
  sourceExists: sourceExists,
  sourceBytes: bytes,
  sourceModified: modified ?? _modified,
  vocalFileExists: vocalFileExists,
);

AudioAsset _audio({String? vocalPath, Duration? duration, VocalStemMarker? marker}) =>
    AudioAsset(
      originalPath: '/music/song.flac',
      format: 'flac',
      vocalPath: vocalPath,
      duration: duration,
      metadata: {
        'title': 'Song',
        if (marker != null) VocalStemMarker.metadataKey: marker.toJson(),
      },
    );

VocalStemMarker _marker({
  String revision = _revision,
  String? fingerprint,
  String vocalPath = '/p/stems/run-1/vocals.wav',
}) => VocalStemMarker(
  separatorRevision: revision,
  sourceFingerprint:
      fingerprint ??
      VocalSeparationPlanner.fingerprintOf('/music/song.flac', _facts()),
  vocalPath: vocalPath,
  accompanimentPath: '/p/stems/run-1/accompaniment.wav',
  provider: 'dml',
  generatedAt: DateTime.utc(2026, 11, 18, 9),
);

VocalSeparationPlan _plan(
  AudioAsset audio, {
  VocalSeparationPreference preference = VocalSeparationPreference.automatic,
  bool platformSupported = true,
  VocalSeparationFacts? facts,
}) => const VocalSeparationPlanner().plan(
  audio: audio,
  preference: preference,
  platformSupported: platformSupported,
  separatorRevision: _revision,
  facts: facts ?? _facts(),
);

void main() {
  test('a plain song on Windows is separated', () {
    final plan = _plan(_audio());
    expect(plan.action, VocalSeparationAction.run);
    expect(plan.skipReason, isNull);
  });

  test('switching separation off wins over everything else', () {
    final plan = _plan(
      _audio(vocalPath: '/p/stems/run-1/vocals.wav', marker: _marker()),
      preference: VocalSeparationPreference.off,
      facts: _facts(vocalFileExists: true),
    );
    expect(plan.action, VocalSeparationAction.skip);
    expect(plan.skipReason, VocalSeparationSkipReason.disabled);
  });

  test('a vocal stem the user imported is never replaced', () {
    final plan = _plan(
      _audio(vocalPath: '/stems/my-vocal.wav'),
      facts: _facts(vocalFileExists: true),
    );
    expect(plan.skipReason, VocalSeparationSkipReason.userProvidedVocal);
  });

  test('a user stem that replaced an automatic one is respected', () {
    // The importer overwrites vocalPath but leaves the old marker behind.
    final plan = _plan(
      _audio(vocalPath: '/stems/my-vocal.wav', marker: _marker()),
      facts: _facts(vocalFileExists: true),
    );
    expect(plan.skipReason, VocalSeparationSkipReason.userProvidedVocal);
  });

  test('a missing imported stem does not block separation', () {
    final plan = _plan(_audio(vocalPath: '/stems/deleted.wav'));
    expect(plan.action, VocalSeparationAction.run);
  });

  test('other platforms skip with a reason', () {
    final plan = _plan(_audio(), platformSupported: false);
    expect(plan.skipReason, VocalSeparationSkipReason.unsupportedPlatform);
  });

  test('a missing song file is skipped, not failed', () {
    final plan = _plan(_audio(), facts: _facts(sourceExists: false));
    expect(plan.skipReason, VocalSeparationSkipReason.sourceMissing);
  });

  test('very long recordings are recognised from the mix', () {
    expect(
      _plan(_audio(duration: const Duration(minutes: 16))).skipReason,
      VocalSeparationSkipReason.tooLong,
    );
    expect(
      _plan(_audio(duration: VocalSeparationPlanner.maxDuration)).action,
      VocalSeparationAction.run,
    );
  });

  test('an unchanged automatic stem is reused', () {
    final marker = _marker();
    final plan = _plan(
      _audio(vocalPath: marker.vocalPath, marker: marker),
      facts: _facts(vocalFileExists: true),
    );
    expect(plan.action, VocalSeparationAction.reuse);
    expect(plan.reusable?.vocalPath, marker.vocalPath);
    expect(plan.reusable?.provider, 'dml');
  });

  test('a replaced song file is separated again', () {
    final marker = _marker();
    for (final facts in [
      _facts(vocalFileExists: true, bytes: 4000001),
      _facts(vocalFileExists: true, modified: DateTime.utc(2026, 11, 19)),
    ]) {
      final plan = _plan(
        _audio(vocalPath: marker.vocalPath, marker: marker),
        facts: facts,
      );
      expect(plan.action, VocalSeparationAction.run);
    }
  });

  test('a new separator revision separates again', () {
    final marker = _marker(revision: 'htdemucs-ft-vocals-onnx-v0');
    final plan = _plan(
      _audio(vocalPath: marker.vocalPath, marker: marker),
      facts: _facts(vocalFileExists: true),
    );
    expect(plan.action, VocalSeparationAction.run);
  });

  test('a deleted automatic stem is separated again', () {
    final marker = _marker();
    final plan = _plan(_audio(vocalPath: marker.vocalPath, marker: marker));
    expect(plan.action, VocalSeparationAction.run);
  });

  test('the fingerprint covers size, time and path', () {
    final base = VocalSeparationPlanner.fingerprintOf('/a.flac', _facts());
    expect(
      VocalSeparationPlanner.fingerprintOf('/b.flac', _facts()),
      isNot(base),
    );
    expect(
      VocalSeparationPlanner.fingerprintOf('/a.flac', _facts(bytes: 1)),
      isNot(base),
    );
    expect(
      VocalSeparationPlanner.fingerprintOf(
        '/a.flac',
        _facts(modified: _modified.add(const Duration(milliseconds: 1))),
      ),
      isNot(base),
    );
    // Local and UTC spellings of the same instant agree.
    expect(
      VocalSeparationPlanner.fingerprintOf(
        '/a.flac',
        _facts(modified: _modified.toLocal()),
      ),
      base,
    );
  });
}
