import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// A sung stretch of a synthetic vocal stem, in seconds, at [amplitude]
/// (0–1 of full scale).
typedef SungStretch = ({double start, double end, double amplitude});

/// 16-bit PCM samples of a synthetic vocal stem: a 220 Hz tone wherever
/// someone "sings", faint deterministic noise elsewhere (separation
/// leftovers), interleaved for [channels].
Int16List vocalStemSamples({
  required double seconds,
  required List<SungStretch> singing,
  int sampleRate = 16000,
  int channels = 1,
  double noiseAmplitude = 0.0005,
}) {
  final frames = (seconds * sampleRate).round();
  final samples = Int16List(frames * channels);
  var seed = 12345;
  for (var frame = 0; frame < frames; frame++) {
    final time = frame / sampleRate;
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    var value = (seed / 0x7fffffff * 2 - 1) * noiseAmplitude;
    for (final stretch in singing) {
      if (time >= stretch.start && time < stretch.end) {
        value += stretch.amplitude * math.sin(2 * math.pi * 220 * time);
      }
    }
    final sample = (value.clamp(-1.0, 1.0) * 32767).round();
    for (var channel = 0; channel < channels; channel++) {
      samples[frame * channels + channel] = sample;
    }
  }
  return samples;
}

/// The bytes of a WAV file. [formatCode], [bits] and [extraChunks] let tests
/// build the variants real writers produce; [dataSizeField] overrides the
/// declared data size (0 and 0xFFFFFFFF are what streaming writers leave).
Uint8List wavBytes(
  Int16List samples, {
  int sampleRate = 16000,
  int channels = 1,
  int formatCode = 1,
  int bits = 16,
  bool extensible = false,
  List<({String id, List<int> body})> extraChunks = const [],
  int? dataSizeField,
}) {
  final out = BytesBuilder();
  void tag(String value) => out.add(value.codeUnits);
  void u16(int value) => out.add(
    (ByteData(2)..setUint16(0, value, Endian.little)).buffer.asUint8List(),
  );
  void u32(int value) => out.add(
    (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List(),
  );

  final data = samples.buffer.asUint8List(
    samples.offsetInBytes,
    samples.lengthInBytes,
  );
  final blockAlign = channels * bits ~/ 8;
  final fmtSize = extensible ? 40 : 16;
  var riffSize = 4 + 8 + fmtSize + 8 + data.length;
  for (final chunk in extraChunks) {
    riffSize += 8 + chunk.body.length + chunk.body.length % 2;
  }

  tag('RIFF');
  u32(riffSize);
  tag('WAVE');
  tag('fmt ');
  u32(fmtSize);
  u16(extensible ? 0xFFFE : formatCode);
  u16(channels);
  u32(sampleRate);
  u32(sampleRate * blockAlign);
  u16(blockAlign);
  u16(bits);
  if (extensible) {
    u16(22); // extension size
    u16(bits); // valid bits
    u32(channels == 1 ? 4 : 3); // channel mask
    // Sub-format GUID: the format code, then the fixed KSDATAFORMAT tail.
    u16(formatCode);
    out.add(const [
      0x00, 0x00, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, //
      0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71,
    ]);
  }
  for (final chunk in extraChunks) {
    tag(chunk.id);
    u32(chunk.body.length);
    out.add(chunk.body);
    if (chunk.body.length.isOdd) out.addByte(0);
  }
  tag('data');
  u32(dataSizeField ?? data.length);
  out.add(data);
  return out.toBytes();
}

Future<File> writeVocalStem(
  String path, {
  required double seconds,
  required List<SungStretch> singing,
  int sampleRate = 16000,
  int channels = 1,
  double noiseAmplitude = 0.0005,
}) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(
    wavBytes(
      vocalStemSamples(
        seconds: seconds,
        singing: singing,
        sampleRate: sampleRate,
        channels: channels,
        noiseAmplitude: noiseAmplitude,
      ),
      sampleRate: sampleRate,
      channels: channels,
    ),
  );
  return file;
}
