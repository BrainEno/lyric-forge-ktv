import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/models/spoken_language.dart';

/// Writes the [windows] of a 16-bit PCM WAV, joined in order, as a new WAV
/// with the same format (D-061). Windows past the end of the source are cut
/// short or skipped. Returns the length of the written clip.
///
/// Anything but 16-bit integer PCM in a RIFF/WAVE container is rejected with
/// a [FormatException].
Future<Duration> writePcmWavClip({
  required String sourcePath,
  required String targetPath,
  required List<SpokenLanguageWindow> windows,
}) async {
  final source = await File(sourcePath).open();
  final data = BytesBuilder(copy: false);
  late final _PcmFormat format;
  try {
    format = await _readFormat(source);
    for (final window in windows) {
      final from = _byteOffset(format, window.start);
      final to = math.min(_byteOffset(format, window.end), format.dataBytes);
      if (to <= from) continue;
      await source.setPosition(format.dataOffset + from);
      var remaining = to - from;
      while (remaining > 0) {
        final bytes = await source.read(math.min(remaining, 1 << 20));
        if (bytes.isEmpty) break;
        data.add(bytes);
        remaining -= bytes.length;
      }
    }
  } finally {
    await source.close();
  }
  final written = data.length;
  final clip = BytesBuilder(copy: false)
    ..add(_header(format, written))
    ..add(data.takeBytes());
  await File(targetPath).writeAsBytes(clip.takeBytes(), flush: true);
  return Duration(
    microseconds: (written / format.blockAlign * 1000000 / format.sampleRate)
        .round(),
  );
}

int _byteOffset(_PcmFormat format, Duration at) {
  final frames = (at.inMicroseconds * format.sampleRate / 1000000).floor();
  return math.max(0, frames) * format.blockAlign;
}

Uint8List _header(_PcmFormat format, int dataBytes) {
  final header = ByteData(44);
  void tag(int offset, String value) {
    for (var index = 0; index < 4; index++) {
      header.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  tag(0, 'RIFF');
  header.setUint32(4, 36 + dataBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, format.channels, Endian.little);
  header.setUint32(24, format.sampleRate, Endian.little);
  header.setUint32(28, format.sampleRate * format.blockAlign, Endian.little);
  header.setUint16(32, format.blockAlign, Endian.little);
  header.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  header.setUint32(40, dataBytes, Endian.little);
  return header.buffer.asUint8List();
}

Future<_PcmFormat> _readFormat(RandomAccessFile file) async {
  final length = await file.length();
  final riff = await file.read(12);
  if (riff.length < 12 ||
      String.fromCharCodes(riff, 0, 4) != 'RIFF' ||
      String.fromCharCodes(riff, 8, 12) != 'WAVE') {
    throw const FormatException('Not a RIFF/WAVE file');
  }
  var position = 12;
  int? channels;
  int? sampleRate;
  while (position + 8 <= length) {
    await file.setPosition(position);
    final chunk = await file.read(8);
    if (chunk.length < 8) break;
    final id = String.fromCharCodes(chunk, 0, 4);
    final size = ByteData.sublistView(chunk).getUint32(4, Endian.little);
    final body = position + 8;
    if (id == 'fmt ') {
      if (size < 16) throw const FormatException('Truncated fmt chunk');
      final fmt = ByteData.sublistView(await file.read(math.min(size, 40)));
      var code = fmt.getUint16(0, Endian.little);
      if (code == 0xFFFE && fmt.lengthInBytes >= 26) {
        code = fmt.getUint16(24, Endian.little);
      }
      final bits = fmt.getUint16(14, Endian.little);
      if (code != 1 || bits != 16) {
        throw FormatException('Unsupported WAV encoding $code/$bits bit');
      }
      channels = fmt.getUint16(2, Endian.little);
      sampleRate = fmt.getUint32(4, Endian.little);
      if (channels == 0 || sampleRate == 0) {
        throw const FormatException('Inconsistent WAV format');
      }
    } else if (id == 'data') {
      if (channels == null || sampleRate == null) {
        throw const FormatException('WAV data before its format');
      }
      final available = length - body;
      final bytes = size == 0 || size == 0xFFFFFFFF || size > available
          ? available
          : size;
      final blockAlign = channels * 2;
      return _PcmFormat(
        channels: channels,
        sampleRate: sampleRate,
        dataOffset: body,
        dataBytes: bytes - bytes % blockAlign,
      );
    }
    position = body + size + size % 2;
  }
  throw const FormatException('WAV file has no data chunk');
}

class _PcmFormat {
  final int channels;
  final int sampleRate;
  final int dataOffset;
  final int dataBytes;

  const _PcmFormat({
    required this.channels,
    required this.sampleRate,
    required this.dataOffset,
    required this.dataBytes,
  });

  int get blockAlign => channels * 2;
}
