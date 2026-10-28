import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/local_ktv_recording_service.dart';
import 'package:lyric_forge_ktv/features/player/data/services/pcm16_wav_writer.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/ktv_recording_session.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/audio_asset.dart';

void main() {
  test('PCM16 WAV writer patches a valid mono 48 kHz header', () async {
    final directory = await Directory.systemTemp.createTemp('ktv_wav_test_');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}voice.wav';
    final writer = Pcm16WavWriter();

    await writer.open(path);
    writer.addPcm16(Uint8List.fromList(<int>[1, 0, 2, 0, 3, 0, 4, 0]));
    final duration = await writer.close();

    final bytes = await File(path).readAsBytes();
    expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF');
    expect(ascii.decode(bytes.sublist(8, 12)), 'WAVE');
    expect(ascii.decode(bytes.sublist(36, 40)), 'data');
    final header = ByteData.sublistView(bytes);
    expect(header.getUint16(22, Endian.little), 1);
    expect(header.getUint32(24, Endian.little), 48000);
    expect(header.getUint16(34, Endian.little), 16);
    expect(header.getUint32(40, Endian.little), 8);
    expect(bytes.length, 52);
    expect(duration.inMicroseconds, 83);
  });

  test('recording session JSON preserves playback alignment facts', () {
    final session = _session();
    final restored = KtvRecordingSession.fromJson(session.toJson());

    expect(restored.id, session.id);
    expect(restored.backingSource, AudioSourceType.instrumental);
    expect(restored.startPosition, const Duration(milliseconds: 12345));
    expect(restored.duration, const Duration(milliseconds: 5432));
    expect(restored.backingVolume, 0.7);
    expect(restored.monitorMicGain, 1.25);
    expect(restored.alignmentReliable, isTrue);
  });

  test('FFmpeg mix plan trims backing from take start and mixes raw voice stem', () {
    final args = buildKtvMixFfmpegArguments(
      _session(),
      outputPath: '/tmp/mix.wav',
      voiceVolume: 1.2,
      backingVolume: 0.65,
    );

    expect(args, containsAllInOrder(<String>[
      '-i',
      '/music/instrumental.wav',
      '-i',
      '/takes/voice.wav',
      '-filter_complex',
    ]));
    final filter = args[args.indexOf('-filter_complex') + 1];
    expect(filter, contains('atrim=start=12.345000:duration=5.432000'));
    expect(filter, contains('volume=0.6500[b]'));
    expect(filter, contains('volume=1.2000[v]'));
    expect(filter, contains('amix=inputs=2:duration=shortest'));
    expect(args.last, '/tmp/mix.wav');
  });
}

KtvRecordingSession _session() => KtvRecordingSession(
      id: 'take-1',
      projectId: 'project-1',
      startedAt: DateTime.utc(2026, 10, 9, 4, 0),
      completedAt: DateTime.utc(2026, 10, 9, 4, 1),
      backingSource: AudioSourceType.instrumental,
      backingPath: '/music/instrumental.wav',
      startPosition: const Duration(milliseconds: 12345),
      duration: const Duration(milliseconds: 5432),
      micStemPath: '/takes/voice.wav',
      manifestPath: '/takes/session.json',
      backingVolume: 0.7,
      monitorMicGain: 1.25,
    );
