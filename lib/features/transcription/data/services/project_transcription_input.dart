import 'dart:io';

import '../../../project/domain/models/project_manifest.dart';
import '../../domain/models/transcription_models.dart';

/// The order must be shared by project transcription and candidate reruns.
///
/// [includeVocal] false skips the vocal stem; the workflow uses it for an
/// automatically separated stem that this run must not trust (separation
/// switched off, or a fresh separation of a changed song failed).
Future<String> resolveProjectTranscriptionInput(
  ProjectManifest project, {
  bool includeVocal = true,
}) async {
  final audio = project.audioAsset;
  if (audio == null) {
    throw const TranscriptionException.input('工程还没有可识别的音频');
  }
  for (final path in [
    if (includeVocal) audio.vocalPath,
    audio.normalizedPath,
    audio.originalPath,
  ]) {
    if (path == null || path.trim().isEmpty) continue;
    if (await File(path).exists()) return path;
  }
  throw const TranscriptionException.input('工程音频文件不可用：人声、标准化音频和原声都不存在');
}
