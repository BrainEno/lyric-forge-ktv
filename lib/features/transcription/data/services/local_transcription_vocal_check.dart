import 'dart:io';

import '../../../project/domain/models/lyric_document.dart';
import '../../domain/models/vocal_activity.dart';
import '../../domain/services/transcription_vocal_check.dart';
import '../../domain/services/vocal_activity_analyzer.dart';
import '../../domain/services/vocal_activity_lyric_gate.dart';
import 'pcm_wav_energy_reader.dart';

/// [TranscriptionVocalCheck] on the local file system (D-044): reads the
/// stem's loudness with [PcmWavEnergyReader], finds the singing with
/// [VocalActivityAnalyzer] and applies [VocalActivityLyricGate].
class LocalTranscriptionVocalCheck implements TranscriptionVocalCheck {
  const LocalTranscriptionVocalCheck({
    this.analyzer = const VocalActivityAnalyzer(),
    this.gate = const VocalActivityLyricGate(),
    this.readEnvelope = PcmWavEnergyReader.readInIsolate,
  });

  final VocalActivityAnalyzer analyzer;
  final VocalActivityLyricGate gate;
  final Future<VocalEnergyEnvelope> Function(String path) readEnvelope;

  @override
  Future<VocalCheckResult> check(
    LyricDocument draft, {
    required List<String> audioPaths,
  }) async {
    final errors = <String>[];
    for (final path in audioPaths) {
      if (path.trim().isEmpty) continue;
      final VocalEnergyEnvelope envelope;
      try {
        if (!await File(path).exists()) {
          errors.add('$path: missing');
          continue;
        }
        envelope = await readEnvelope(path);
      } on FormatException catch (error) {
        errors.add('$path: ${error.message}');
        continue;
      } catch (error) {
        // Unreadable for any other reason (permissions, a vanished file, a
        // failed isolate): try the next path.
        errors.add('$path: $error');
        continue;
      }
      try {
        return gate.apply(draft, analyzer.analyze(envelope), audioPath: path);
      } catch (error) {
        return VocalCheckResult.unchanged(
          draft,
          VocalCheckReport.skipped(
            VocalCheckSkipReason.failed,
            audioPath: path,
            error: error.toString(),
          ),
        );
      }
    }
    return VocalCheckResult.unchanged(
      draft,
      VocalCheckReport.skipped(
        VocalCheckSkipReason.unreadableAudio,
        error: errors.isEmpty ? 'no audio path' : errors.join('; '),
      ),
    );
  }
}
