import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../domain/models/independent_asr_evidence.dart';

/// A point-in-time check, not permission to overwrite lyrics or a file lock.
enum AsrEvidenceAudioStatus {
  missingEvidence,
  invalidEvidence,
  unverified,
  audioUnavailable,
  audioChanged,
  audioMatches,
}

/// Hashes bytes as a stream without loading an entire recording into memory.
Future<String> hashAsrAudioFile(
  String path, {
  void Function()? onChunk,
}) async {
  final bytes = File(path).openRead().map((chunk) {
    onChunk?.call();
    return chunk;
  });
  return (await sha256.bind(bytes).first).toString();
}

class AsrEvidenceAudioVerifier {
  const AsrEvidenceAudioVerifier();

  Future<AsrEvidenceAudioStatus> verify({
    required Object? rawEvidence,
    required String? currentAudioPath,
  }) async {
    if (rawEvidence == null) return AsrEvidenceAudioStatus.missingEvidence;
    final evidence = IndependentAsrEvidence.tryParse(rawEvidence);
    if (evidence == null) return AsrEvidenceAudioStatus.invalidEvidence;
    final expected = evidence.sourceAudioSha256;
    if (expected == null) return AsrEvidenceAudioStatus.unverified;
    if (currentAudioPath == null || currentAudioPath.trim().isEmpty) {
      return AsrEvidenceAudioStatus.audioUnavailable;
    }
    try {
      final actual = await hashAsrAudioFile(currentAudioPath);
      return actual == expected
          ? AsrEvidenceAudioStatus.audioMatches
          : AsrEvidenceAudioStatus.audioChanged;
    } on FileSystemException {
      return AsrEvidenceAudioStatus.audioUnavailable;
    }
  }
}
