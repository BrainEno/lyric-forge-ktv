import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/vocal_check_record.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/local_transcription_vocal_check.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/pcm_wav_energy_reader.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/vocal_activity.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/vocal_activity_lyric_gate.dart';

import 'wav_fixture.dart';

// Every lyric below is synthetic text written for these tests.

LyricLine _line(String text, double start, double end) => LyricLine(
  text: text,
  startTime: Duration(milliseconds: (start * 1000).round()),
  endTime: Duration(milliseconds: (end * 1000).round()),
);

/// A 40 s "song": intro 0–8 s, verse 8–18 s, interlude 18–24 s, chorus
/// 24–34 s, outro 34–40 s.
const _singing = <SungStretch>[
  (start: 8, end: 12.6, amplitude: 0.25),
  (start: 12.8, end: 18, amplitude: 0.2),
  (start: 24, end: 34, amplitude: 0.3),
];

LyricDocument _draft() => LyricDocument(
  language: 'zh',
  lines: [
    _line('请不吝点赞订阅', 2, 6),
    _line('第一句歌词', 8, 12.6),
    _line('第二句歌词', 12.8, 18),
    _line('间奏里编出来的', 19, 23),
    _line('副歌第一句', 24, 29),
    _line('副歌第二句', 29, 37),
    _line('谢谢观看', 36.5, 39.5),
  ],
);

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('vocal-check-');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('removes lyrics invented over silence in a real stem file', () async {
    final stem = await writeVocalStem(
      '${root.path}/vocals.wav',
      seconds: 40,
      singing: _singing,
    );
    final result = await const LocalTranscriptionVocalCheck(
      readEnvelope: _readHere,
    ).check(_draft(), audioPaths: [stem.path]);

    expect(result.report.applied, isTrue);
    expect(result.report.audioPath, stem.path);
    expect(result.document.lines.map((line) => line.text), [
      '第一句歌词',
      '第二句歌词',
      '副歌第一句',
      '副歌第二句',
    ]);
    expect(result.report.record.removedLines.map((line) => line.text), [
      '请不吝点赞订阅',
      '间奏里编出来的',
      '谢谢观看',
    ]);
    // The chorus' last row ran 3 s into the outro; it now stops with the
    // singing (plus the release).
    final last = result.document.lines.last;
    expect(last.endTime.inMilliseconds, closeTo(34200, 60));
    expect(result.report.record.retimedLines, 1);
    expect(result.report.record.uncoveredSpans, isEmpty);
    expect(
      LyricVocalCheckRecord.fromMetadata(result.document.metadata),
      isNotNull,
    );
  });

  test('reports singing that no row covers', () async {
    final stem = await writeVocalStem(
      '${root.path}/vocals.wav',
      seconds: 40,
      singing: _singing,
    );
    final draft = LyricDocument(
      language: 'zh',
      lines: [_line('第一句歌词', 8, 12.6), _line('第二句歌词', 12.8, 18)],
    );
    final result = await const LocalTranscriptionVocalCheck(
      readEnvelope: _readHere,
    ).check(draft, audioPaths: [stem.path]);
    final spans = result.report.record.uncoveredSpans;
    expect(spans, hasLength(1));
    expect(spans.single.start.inMilliseconds, closeTo(24000, 60));
    expect(spans.single.end.inMilliseconds, closeTo(34000, 60));
  });

  test('a stereo 44.1 kHz separator stem works as well', () async {
    final stem = await writeVocalStem(
      '${root.path}/vocals-44k.wav',
      seconds: 40,
      singing: _singing,
      sampleRate: 44100,
      channels: 2,
    );
    final result = await const LocalTranscriptionVocalCheck(
      readEnvelope: _readHere,
    ).check(_draft(), audioPaths: [stem.path]);
    expect(result.report.record.removedLines, hasLength(3));
  });

  test('the first readable path wins', () async {
    final notWav = File('${root.path}/normalized.wav');
    await notWav.writeAsString('not a wave file');
    final stem = await writeVocalStem(
      '${root.path}/vocals.wav',
      seconds: 40,
      singing: _singing,
    );
    final result =
        await const LocalTranscriptionVocalCheck(readEnvelope: _readHere).check(
          _draft(),
          audioPaths: ['', '${root.path}/gone.wav', notWav.path, stem.path],
        );
    expect(result.report.applied, isTrue);
    expect(result.report.audioPath, stem.path);
  });

  test('no readable path leaves the draft unchanged and says why', () async {
    final notWav = File('${root.path}/song.mp3');
    await notWav.writeAsString('ID3');
    final draft = _draft();
    final result = await const LocalTranscriptionVocalCheck(
      readEnvelope: _readHere,
    ).check(draft, audioPaths: ['${root.path}/gone.wav', notWav.path]);
    expect(identical(result.document, draft), isTrue);
    expect(result.report.skipReason, VocalCheckSkipReason.unreadableAudio);
    expect(result.report.error, contains('gone.wav: missing'));
    expect(result.report.error, contains('RIFF'));
  });

  test('no path at all is unreadable', () async {
    final result = await const LocalTranscriptionVocalCheck(
      readEnvelope: _readHere,
    ).check(_draft(), audioPaths: const []);
    expect(result.report.skipReason, VocalCheckSkipReason.unreadableAudio);
    expect(result.report.error, 'no audio path');
  });

  test('a reader failure of any kind moves on to the next path', () async {
    final first = await writeVocalStem(
      '${root.path}/a.wav',
      seconds: 40,
      singing: _singing,
    );
    final second = await writeVocalStem(
      '${root.path}/b.wav',
      seconds: 40,
      singing: _singing,
    );
    final result = await LocalTranscriptionVocalCheck(
      readEnvelope: (path) => path == first.path
          ? throw StateError('isolate died')
          : _readHere(path),
    ).check(_draft(), audioPaths: [first.path, second.path]);
    expect(result.report.audioPath, second.path);
  });

  test('a full mix used as the vocal is left alone', () async {
    // Accompaniment everywhere: loud in the "silent" parts too.
    final mix = await writeVocalStem(
      '${root.path}/mix.wav',
      seconds: 40,
      singing: _singing,
      noiseAmplitude: 0.15,
    );
    final draft = _draft();
    final result = await const LocalTranscriptionVocalCheck(
      readEnvelope: _readHere,
    ).check(draft, audioPaths: [mix.path]);
    expect(identical(result.document, draft), isTrue);
    expect(result.report.skipReason, VocalCheckSkipReason.unreliableProfile);
    expect(
      result.report.profile?.unreliability,
      VocalActivityUnreliability.lowContrast,
    );
  });

  test('a failure inside the gate keeps the draft', () async {
    final stem = await writeVocalStem(
      '${root.path}/vocals.wav',
      seconds: 40,
      singing: _singing,
    );
    final draft = _draft();
    final result = await const LocalTranscriptionVocalCheck(
      readEnvelope: _readHere,
      gate: _ThrowingGate(),
    ).check(draft, audioPaths: [stem.path]);
    expect(identical(result.document, draft), isTrue);
    expect(result.report.skipReason, VocalCheckSkipReason.failed);
    expect(result.report.error, contains('boom'));
  });
}

/// The reader on the test's own isolate: temp files and fake file systems
/// stay simple.
Future<VocalEnergyEnvelope> _readHere(String path) =>
    const PcmWavEnergyReader().read(path);

class _ThrowingGate extends VocalActivityLyricGate {
  const _ThrowingGate();

  @override
  VocalCheckResult apply(
    LyricDocument draft,
    VocalActivityProfile profile, {
    required String audioPath,
  }) => throw StateError('boom');
}
