import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/pcm16_wav_writer.dart';

void main() {
  test('repairs interrupted WAV header without changing voice samples', () async {
    final root = await Directory.systemTemp.createTemp('ktv-recover-');
    try {
      final path = '${root.path}${Platform.pathSeparator}voice.wav';
      final writer = Pcm16WavWriter();
      await writer.open(path);
      writer.addPcm16(Uint8List(9600));
      await writer.close();
      final file = File(path);
      final bytes = await file.readAsBytes();
      for (final offset in [4, 5, 6, 7, 40, 41, 42, 43]) {
        bytes[offset] = 0;
      }
      await file.writeAsBytes(bytes);
      final recovered = await Pcm16WavWriter.recoverInterruptedFile(path);
      expect(recovered, const Duration(milliseconds: 100));
      final repaired = await file.readAsBytes();
      expect(repaired.sublist(44), bytes.sublist(44));
      final header = ByteData.sublistView(Uint8List.fromList(repaired));
      expect(header.getUint32(40, Endian.little), 9600);
      expect(header.getUint32(4, Endian.little), 9636);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
