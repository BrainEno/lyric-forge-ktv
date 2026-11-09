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

class AsrAudioChangedDuringHashException implements Exception {
  const AsrAudioChangedDuringHashException();
}

/// Hashes bytes as a stream without loading an entire recording into memory.
/// File-stat checks catch common concurrent changes, but are not a file lock.
Future<String> hashAsrAudioFile(String path, {void Function()? onChunk}) async {
  final file = File(path);
  final before = await file.stat();
  if (before.type != FileSystemEntityType.file) {
    throw FileSystemException('Audio is not a readable file', path);
  }
  final bytes = file.openRead().map((chunk) {
    onChunk?.call();
    return chunk;
  });
  final digest = (await sha256.bind(bytes).first).toString();
  final after = await file.stat();
  if (after.type != before.type ||
      after.size != before.size ||
      after.modified != before.modified ||
      after.changed != before.changed) {
    throw const AsrAudioChangedDuringHashException();
  }
  return digest;
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
    } on AsrAudioChangedDuringHashException {
      return AsrEvidenceAudioStatus.audioChanged;
    } on FileSystemException {
      return AsrEvidenceAudioStatus.audioUnavailable;
    }
  }
}
