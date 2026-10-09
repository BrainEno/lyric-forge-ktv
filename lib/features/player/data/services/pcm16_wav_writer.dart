import 'dart:io';
import 'dart:typed_data';

class Pcm16WavWriter {
  final int sampleRate;
  final int channels;
  RandomAccessFile? _file;
  int _dataBytes = 0;

  Pcm16WavWriter({
    this.sampleRate = 48000,
    this.channels = 1,
  });

  int get dataBytes => _dataBytes;

  Duration get duration {
    final bytesPerSecond = sampleRate * channels * 2;
    if (bytesPerSecond <= 0) return Duration.zero;
    return Duration(
      microseconds: (_dataBytes * Duration.microsecondsPerSecond ~/ bytesPerSecond),
    );
  }

  /// Repairs a WAV interrupted before its RIFF/data sizes were finalized.
  /// Returns the recovered audio duration, or null for an invalid file.
  static Future<Duration?> recoverInterruptedFile(
    String path, {
    int sampleRate = 48000,
    int channels = 1,
  }) async {
    final file = File(path);
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) return null;
    final handle = await file.open(mode: FileMode.writeOnly);
    try {
      final size = await handle.length();
      if (size < 44 || size > 0xffffffff) return null;
      await handle.setPosition(0);
      final header = await handle.read(44);
      if (header.length != 44 ||
          String.fromCharCodes(header.sublist(0, 4)) != 'RIFF' ||
          String.fromCharCodes(header.sublist(8, 12)) != 'WAVE' ||
          String.fromCharCodes(header.sublist(36, 40)) != 'data') {
        return null;
      }
      final bytes = ByteData.sublistView(Uint8List.fromList(header));
      if (bytes.getUint16(20, Endian.little) != 1 ||
          bytes.getUint16(22, Endian.little) != channels ||
          bytes.getUint32(24, Endian.little) != sampleRate ||
          bytes.getUint16(34, Endian.little) != 16) return null;
      final audioBytes = (size - 44) - ((size - 44) % (channels * 2));
      if (audioBytes <= 0) return null;
      if (bytes.getUint32(40, Endian.little) != audioBytes ||
          bytes.getUint32(4, Endian.little) != 36 + audioBytes) {
        bytes.setUint32(4, 36 + audioBytes, Endian.little);
        bytes.setUint32(40, audioBytes, Endian.little);
        await handle.setPosition(0);
        await handle.writeFrom(bytes.buffer.asUint8List());
        await handle.flush();
      }
      return Duration(
        microseconds: audioBytes * Duration.microsecondsPerSecond ~/
            (sampleRate * channels * 2),
      );
    } finally {
      await handle.close();
    }
  }

  Future<void> open(String path) async {
    if (_file != null) throw StateError('WAV writer is already open');
    final target = File(path);
    await target.parent.create(recursive: true);
    _file = await target.open(mode: FileMode.write);
    _file!.writeFromSync(_wavHeader(dataBytes: 0));
  }

  void addPcm16(Uint8List bytes) {
    final file = _file;
    if (file == null) throw StateError('WAV writer is not open');
    if (bytes.isEmpty) return;
    final evenLength = bytes.lengthInBytes - (bytes.lengthInBytes % 2);
    if (evenLength <= 0) return;
    file.writeFromSync(bytes, 0, evenLength);
    _dataBytes += evenLength;
  }

  Future<Duration> close() async {
    final file = _file;
    if (file == null) return duration;
    _file = null;
    await file.setPosition(0);
    await file.writeFrom(_wavHeader(dataBytes: _dataBytes));
    await file.flush();
    await file.close();
    return duration;
  }

  Uint8List _wavHeader({required int dataBytes}) {
    final byteRate = sampleRate * channels * 2;
    final blockAlign = channels * 2;
    final header = ByteData(44);

    void ascii(int offset, String value) {
      for (var index = 0; index < value.length; index++) {
        header.setUint8(offset + index, value.codeUnitAt(index));
      }
    }

    ascii(0, 'RIFF');
    header.setUint32(4, 36 + dataBytes, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    header.setUint32(40, dataBytes, Endian.little);
    return header.buffer.asUint8List();
  }
}
