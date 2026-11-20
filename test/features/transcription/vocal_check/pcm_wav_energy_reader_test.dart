import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/pcm_wav_energy_reader.dart';

import 'wav_fixture.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('wav-energy-');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<String> write(String name, List<int> bytes) async {
    final file = File('${root.path}/$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Int16List constant(int frames, int value, {int channels = 1}) =>
      Int16List(frames * channels)..fillRange(0, frames * channels, value);

  test('one RMS value per 20 ms frame of a 16 kHz mono file', () async {
    // 1 s: half silence, half a constant at half scale.
    final samples = Int16List(16000)..fillRange(8000, 16000, 16384);
    final path = await write('mono.wav', wavBytes(samples));
    final envelope = await const PcmWavEnergyReader().read(path);
    expect(envelope.frameLength, const Duration(milliseconds: 20));
    expect(envelope.frameRms, hasLength(50));
    expect(envelope.frameRms.first, 0);
    expect(envelope.frameRms.last, closeTo(0.5, 1e-6));
    expect(envelope.duration, const Duration(seconds: 1));
  });

  test('a sine at amplitude a has an RMS of a over root two', () async {
    final samples = vocalStemSamples(
      seconds: 1,
      singing: const [(start: 0, end: 1, amplitude: 0.5)],
      noiseAmplitude: 0,
    );
    final path = await write('sine.wav', wavBytes(samples));
    final envelope = await const PcmWavEnergyReader().read(path);
    for (final rms in envelope.frameRms) {
      expect(rms, closeTo(0.5 / math.sqrt2, 0.01));
    }
  });

  test('stereo channels are averaged before squaring', () async {
    // Left +half, right -half: out-of-phase channels cancel in the mono sum
    // the recogniser hears.
    final samples = Int16List(44100 * 2);
    for (var frame = 0; frame < 44100; frame++) {
      samples[frame * 2] = 16384;
      samples[frame * 2 + 1] = frame < 22050 ? -16384 : 16384;
    }
    final path = await write(
      'stereo.wav',
      wavBytes(samples, sampleRate: 44100, channels: 2),
    );
    final envelope = await const PcmWavEnergyReader().read(path);
    // 882 samples per frame at 44.1 kHz.
    expect(envelope.frameLength, const Duration(milliseconds: 20));
    expect(envelope.frameRms, hasLength(50));
    expect(envelope.frameRms.first, closeTo(0, 1e-9));
    expect(envelope.frameRms.last, closeTo(0.5, 1e-6));
  });

  test('chunked reads give the same envelope as one read', () async {
    final samples = vocalStemSamples(
      seconds: 3,
      singing: const [(start: 0.5, end: 2.2, amplitude: 0.3)],
    );
    final path = await write('chunks.wav', wavBytes(samples));
    final whole = await const PcmWavEnergyReader().read(path);
    // A chunk size that splits frames and is rounded down to whole blocks.
    final pieces = await const PcmWavEnergyReader(chunkBytes: 1001).read(path);
    expect(pieces.frameRms, hasLength(whole.frameRms.length));
    for (var index = 0; index < whole.frameRms.length; index++) {
      expect(pieces.frameRms[index], closeTo(whole.frameRms[index], 1e-12));
    }
  });

  test('a custom frame length is honoured', () async {
    final path = await write('frames.wav', wavBytes(constant(16000, 100)));
    final envelope = await const PcmWavEnergyReader(
      frameLength: Duration(milliseconds: 50),
    ).read(path);
    expect(envelope.frameLength, const Duration(milliseconds: 50));
    expect(envelope.frameRms, hasLength(20));
  });

  test('a trailing part frame counts from half a frame', () async {
    // 20 ms frames are 320 samples: 3 frames and 170 samples over.
    final path = await write('tail.wav', wavBytes(constant(320 * 3 + 170, 50)));
    final envelope = await const PcmWavEnergyReader().read(path);
    expect(envelope.frameRms, hasLength(4));

    final short = await write(
      'short-tail.wav',
      wavBytes(constant(320 * 3 + 100, 50)),
    );
    expect(
      (await const PcmWavEnergyReader().read(short)).frameRms,
      hasLength(3),
    );
  });

  test('skips chunks before the data and their pad bytes', () async {
    final path = await write(
      'list.wav',
      wavBytes(
        constant(3200, 8192),
        extraChunks: const [
          (id: 'LIST', body: [1, 2, 3, 4, 5]),
          (id: 'junk', body: [0, 0, 0, 0]),
        ],
      ),
    );
    final envelope = await const PcmWavEnergyReader().read(path);
    expect(envelope.frameRms, hasLength(10));
    expect(envelope.frameRms.first, closeTo(0.25, 1e-6));
  });

  test('WAVE_FORMAT_EXTENSIBLE with a PCM sub-format is read', () async {
    final path = await write(
      'extensible.wav',
      wavBytes(
        constant(4410, 16384, channels: 2),
        sampleRate: 44100,
        channels: 2,
        extensible: true,
      ),
    );
    final envelope = await const PcmWavEnergyReader().read(path);
    expect(envelope.frameRms, hasLength(5));
    expect(envelope.frameRms.first, closeTo(0.5, 1e-6));
  });

  test('a streaming writer\'s unknown data size reads to the end', () async {
    for (final size in [0, 0xFFFFFFFF, 1 << 30]) {
      final path = await write(
        'stream-$size.wav',
        wavBytes(constant(1600, 100), dataSizeField: size),
      );
      expect(
        (await const PcmWavEnergyReader().read(path)).frameRms,
        hasLength(5),
        reason: 'data size field $size',
      );
    }
  });

  test('a declared data size shorter than the file is honoured', () async {
    final path = await write(
      'declared.wav',
      wavBytes(constant(3200, 100), dataSizeField: 1600 * 2),
    );
    expect(
      (await const PcmWavEnergyReader().read(path)).frameRms,
      hasLength(5),
    );
  });

  test('an odd trailing byte is ignored', () async {
    final bytes = wavBytes(constant(1600, 100), dataSizeField: 0);
    final path = await write('odd.wav', [...bytes, 7]);
    expect(
      (await const PcmWavEnergyReader().read(path)).frameRms,
      hasLength(5),
    );
  });

  group('rejects', () {
    Future<void> rejects(String name, List<int> bytes, Pattern message) async {
      final path = await write(name, bytes);
      await expectLater(
        const PcmWavEnergyReader().read(path),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains(message),
          ),
        ),
      );
    }

    test('files that are not RIFF/WAVE', () async {
      await rejects('mp3.wav', 'ID3\u0004 not a wave'.codeUnits, 'RIFF');
      await rejects('tiny.wav', const [1, 2, 3], 'RIFF');
    });

    test('float and 24-bit encodings', () async {
      await rejects(
        'float.wav',
        wavBytes(constant(100, 0), formatCode: 3, bits: 32),
        'Unsupported',
      );
      await rejects(
        'float-ext.wav',
        wavBytes(constant(100, 0), formatCode: 3, extensible: true),
        'Unsupported',
      );
      await rejects(
        '24bit.wav',
        wavBytes(constant(100, 0), bits: 24),
        'Unsupported',
      );
    });

    test('a file without a data chunk', () async {
      final bytes = wavBytes(constant(10, 0));
      // Cut right after the fmt chunk.
      await rejects('nodata.wav', bytes.sublist(0, 12 + 8 + 16), 'no data');
    });

    test('a data chunk before its format', () async {
      final bytes = BytesBuilder()
        ..add('RIFF'.codeUnits)
        ..add(const [12, 0, 0, 0])
        ..add('WAVE'.codeUnits)
        ..add('data'.codeUnits)
        ..add(const [4, 0, 0, 0, 1, 0, 1, 0]);
      await rejects('order.wav', bytes.toBytes(), 'before its format');
    });

    test('an inconsistent block size', () async {
      final bytes = wavBytes(constant(100, 0));
      // Block align lives at offset 12 + 8 + 12.
      bytes[32] = 3;
      await rejects('align.wav', bytes, 'Inconsistent');
    });

    test('a truncated fmt chunk', () async {
      final bytes = BytesBuilder()
        ..add('RIFF'.codeUnits)
        ..add(const [20, 0, 0, 0])
        ..add('WAVE'.codeUnits)
        ..add('fmt '.codeUnits)
        ..add(const [8, 0, 0, 0, 1, 0, 1, 0, 0x80, 0x3E, 0, 0]);
      await rejects('fmt.wav', bytes.toBytes(), 'Truncated');
    });
  });

  test('missing files fail with a file system error', () async {
    await expectLater(
      const PcmWavEnergyReader().read('${root.path}/missing.wav'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('readInIsolate reads with the default settings', () async {
    final path = await write('isolate.wav', wavBytes(constant(16000, 16384)));
    final envelope = await PcmWavEnergyReader.readInIsolate(path);
    expect(envelope.frameRms, hasLength(50));
    expect(envelope.frameRms.first, closeTo(0.5, 1e-6));
  });
}
