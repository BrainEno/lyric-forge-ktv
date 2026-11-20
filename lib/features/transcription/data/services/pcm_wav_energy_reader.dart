import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/models/vocal_activity.dart';

/// Reads the loudness envelope of a 16-bit PCM WAV file (D-044).
///
/// Recognition already decodes its input to a 16 kHz mono WAV
/// (`AsrAudioNormalization`), and the separator writes 44.1 kHz stereo
/// WAVs, so this reader covers both without another FFmpeg run. Channels
/// are averaged before squaring. The file is read in chunks, never whole.
///
/// Anything but 16-bit integer PCM in a RIFF/WAVE container is rejected
/// with a [FormatException].
class PcmWavEnergyReader {
  const PcmWavEnergyReader({
    this.frameLength = const Duration(milliseconds: 20),
    this.chunkBytes = 1 << 20,
  });

  final Duration frameLength;
  final int chunkBytes;

  static const int _pcm = 1;
  static const int _extensible = 0xFFFE;

  /// [PcmWavEnergyReader.read] with the default settings, off the calling
  /// isolate: a four-minute stem is several million samples.
  static Future<VocalEnergyEnvelope> readInIsolate(String path) =>
      Isolate.run(() => const PcmWavEnergyReader().read(path));

  Future<VocalEnergyEnvelope> read(String path) async {
    final file = await File(path).open();
    try {
      final length = await file.length();
      final format = await _readFormat(file, length);
      final frameSamples = math.max(
        1,
        (format.sampleRate * frameLength.inMicroseconds / 1000000).round(),
      );
      final block = format.blockAlign;
      final readSize = math.max(block, chunkBytes - chunkBytes % block);
      final rms = <double>[];
      var sumSquares = 0.0;
      var count = 0;
      var remaining = format.dataBytes - format.dataBytes % block;
      await file.setPosition(format.dataOffset);
      while (remaining > 0) {
        final bytes = await file.read(math.min(readSize, remaining));
        if (bytes.isEmpty) break;
        final usable = bytes.length - bytes.length % block;
        remaining -= bytes.length;
        final data = ByteData.sublistView(bytes);
        for (var offset = 0; offset < usable; offset += block) {
          var mixed = 0;
          for (var channel = 0; channel < format.channels; channel++) {
            mixed += data.getInt16(offset + channel * 2, Endian.little);
          }
          final sample = mixed / (format.channels * 32768.0);
          sumSquares += sample * sample;
          if (++count == frameSamples) {
            rms.add(math.sqrt(sumSquares / count));
            sumSquares = 0;
            count = 0;
          }
        }
        if (usable != bytes.length) break;
      }
      // A trailing part frame counts when it is at least half a frame.
      if (count * 2 >= frameSamples) rms.add(math.sqrt(sumSquares / count));
      return VocalEnergyEnvelope(
        frameLength: Duration(
          microseconds: (frameSamples * 1000000 / format.sampleRate).round(),
        ),
        frameRms: rms,
      );
    } finally {
      await file.close();
    }
  }

  Future<_WavFormat> _readFormat(RandomAccessFile file, int length) async {
    final header = await file.read(12);
    if (header.length < 12 ||
        _tag(header, 0) != 'RIFF' ||
        _tag(header, 8) != 'WAVE') {
      throw const FormatException('Not a RIFF/WAVE file');
    }
    var position = 12;
    _WavFormat? format;
    while (position + 8 <= length) {
      await file.setPosition(position);
      final chunk = await file.read(8);
      if (chunk.length < 8) break;
      final id = _tag(chunk, 0);
      final size = ByteData.sublistView(chunk).getUint32(4, Endian.little);
      final body = position + 8;
      if (id == 'fmt ') {
        if (size < 16) throw const FormatException('Truncated fmt chunk');
        final fmt = ByteData.sublistView(await file.read(math.min(size, 40)));
        var code = fmt.getUint16(0, Endian.little);
        if (code == _extensible && fmt.lengthInBytes >= 26) {
          code = fmt.getUint16(24, Endian.little);
        }
        final channels = fmt.getUint16(2, Endian.little);
        final sampleRate = fmt.getUint32(4, Endian.little);
        final blockAlign = fmt.getUint16(12, Endian.little);
        final bits = fmt.getUint16(14, Endian.little);
        if (code != _pcm || bits != 16) {
          throw FormatException('Unsupported WAV encoding $code/$bits bit');
        }
        if (channels == 0 || sampleRate == 0 || blockAlign != channels * 2) {
          throw const FormatException('Inconsistent WAV format');
        }
        format = _WavFormat(
          channels: channels,
          sampleRate: sampleRate,
          blockAlign: blockAlign,
        );
      } else if (id == 'data') {
        if (format == null) {
          throw const FormatException('WAV data before its format');
        }
        // Streamed writers leave the size 0 or 0xFFFFFFFF; trust the file.
        final available = length - body;
        final bytes = size == 0 || size == 0xFFFFFFFF || size > available
            ? available
            : size;
        return format.withData(body, bytes);
      }
      position = body + size + size % 2;
    }
    throw const FormatException('WAV file has no data chunk');
  }

  static String _tag(Uint8List bytes, int offset) =>
      String.fromCharCodes(bytes, offset, offset + 4);
}

class _WavFormat {
  final int channels;
  final int sampleRate;
  final int blockAlign;
  final int dataOffset;
  final int dataBytes;

  const _WavFormat({
    required this.channels,
    required this.sampleRate,
    required this.blockAlign,
    this.dataOffset = 0,
    this.dataBytes = 0,
  });

  _WavFormat withData(int offset, int bytes) => _WavFormat(
    channels: channels,
    sampleRate: sampleRate,
    blockAlign: blockAlign,
    dataOffset: offset,
    dataBytes: bytes,
  );
}
