import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../domain/models/independent_asr_evidence.dart';
import '../../domain/models/chunked_independent_asr_evidence.dart';

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

/// Caller must resolve the actual current transcription input (project vocal,
/// normalized, then original, selecting the first existing file). A match only
/// concerns audio bytes at verification time, not models or safe application.
class AsrEvidenceAudioVerifier {
  const AsrEvidenceAudioVerifier();

  Future<AsrEvidenceAudioStatus> verify({
    required Object? rawEvidence,
    required String? currentAudioPath,
  }) async {
    if (rawEvidence == null) return AsrEvidenceAudioStatus.missingEvidence;
    final single = IndependentAsrEvidence.tryParse(rawEvidence);
    final chunked = single == null
        ? ChunkedIndependentAsrEvidence.tryParse(rawEvidence)
        : null;
    if (single == null && chunked == null) return AsrEvidenceAudioStatus.invalidEvidence;
    final expected = single?.sourceAudioSha256 ?? chunked?.sourceAudioSha256;
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
