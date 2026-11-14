import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/models/transcription_models.dart';
import 'whisper_json_transcript_parser.dart';

/// Result codes for a read-only whisper.cpp response-file lookup.
///
/// Paths originate in project metadata and can be stale or malformed. Keep
/// failure states separate so callers can fall back to the immutable embedded
/// transcript without exposing an arbitrary file or blocking proofreading.
enum WhisperJsonArtifactStatus {
  noPath,
  invalidPath,
  missing,
  notRegularFile,
  empty,
  tooLarge,
  changedDuringRead,
  invalidEncoding,
  invalidJson,
  noUsableSegments,
  loaded,
}

/// A bounded parse outcome; `parsed` is non-null only for [loaded].
class WhisperJsonArtifactReadResult {
  final WhisperJsonArtifactStatus status;
  final WhisperJsonTranscriptParseResult? parsed;

  const WhisperJsonArtifactReadResult(this.status, {this.parsed})
    : assert((status == WhisperJsonArtifactStatus.loaded) == (parsed != null));

  bool get isLoaded => status == WhisperJsonArtifactStatus.loaded;
}

/// Reads an optional whisper.cpp artifact without trusting project metadata.
///
/// The reader never writes files, rejects symbolic-link path entries, reads at
/// most a configured byte limit, or treats the raw file alone as proof that it
/// belongs to the current audio.
/// The project evidence loader cross-checks successful parses against its
/// audio-verified inline transcript before choosing this representation.
class WhisperJsonArtifactReader {
  static const int defaultMaxArtifactBytes = 48 * 1024 * 1024;
  static const int maxPathCharacters = 4096;

  final WhisperJsonTranscriptParser parser;
  final int maxArtifactBytes;

  const WhisperJsonArtifactReader({
    this.parser = const WhisperJsonTranscriptParser(),
    this.maxArtifactBytes = defaultMaxArtifactBytes,
  });

  Future<WhisperJsonArtifactReadResult> read(Object? rawPath) async {
    if (rawPath == null) {
      return const WhisperJsonArtifactReadResult(
        WhisperJsonArtifactStatus.noPath,
      );
    }
    if (rawPath is! String ||
        rawPath.trim().isEmpty ||
        rawPath.length > maxPathCharacters ||
        rawPath.contains('\u0000')) {
      return const WhisperJsonArtifactReadResult(
        WhisperJsonArtifactStatus.invalidPath,
      );
    }

    final path = rawPath.trim();
    final file = File(path);
    try {
      final entryType = await FileSystemEntity.type(path, followLinks: false);
      if (entryType == FileSystemEntityType.notFound) {
        return const WhisperJsonArtifactReadResult(
          WhisperJsonArtifactStatus.missing,
        );
      }
      if (entryType != FileSystemEntityType.file) {
        return const WhisperJsonArtifactReadResult(
          WhisperJsonArtifactStatus.notRegularFile,
        );
      }

      final before = await file.stat();
      if (before.type != FileSystemEntityType.file) {
        return const WhisperJsonArtifactReadResult(
          WhisperJsonArtifactStatus.notRegularFile,
        );
      }
      if (before.size == 0) {
        return const WhisperJsonArtifactReadResult(
          WhisperJsonArtifactStatus.empty,
        );
      }
      if (before.size > maxArtifactBytes) {
        return const WhisperJsonArtifactReadResult(
          WhisperJsonArtifactStatus.tooLarge,
        );
      }

      final bytes = await _readBounded(file);
      final after = await file.stat();
      if (_changed(before, after) || bytes.length != after.size) {
        return const WhisperJsonArtifactReadResult(
          WhisperJsonArtifactStatus.changedDuringRead,
        );
      }
      if (bytes.length > maxArtifactBytes) {
        return const WhisperJsonArtifactReadResult(
          WhisperJsonArtifactStatus.tooLarge,
        );
      }
      if (bytes.isEmpty) {
        return const WhisperJsonArtifactReadResult(
          WhisperJsonArtifactStatus.empty,
        );
      }

      late final String source;
      try {
        source = utf8.decode(bytes, allowMalformed: false);
      } on FormatException {
        return const WhisperJsonArtifactReadResult(
          WhisperJsonArtifactStatus.invalidEncoding,
        );
      }

      try {
        final parsed = parser.parse(source, rawJsonPath: path);
        return WhisperJsonArtifactReadResult(
          WhisperJsonArtifactStatus.loaded,
          parsed: parsed,
        );
      } on TranscriptionException catch (error) {
        return WhisperJsonArtifactReadResult(
          error.kind == TranscriptionFailureKind.input
              ? WhisperJsonArtifactStatus.noUsableSegments
              : WhisperJsonArtifactStatus.invalidJson,
        );
      }
    } on FileSystemException {
      return const WhisperJsonArtifactReadResult(
        WhisperJsonArtifactStatus.missing,
      );
    }
  }

  Future<Uint8List> _readBounded(File file) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(0, maxArtifactBytes + 1)) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  bool _changed(FileStat before, FileStat after) =>
      before.type != after.type ||
      before.size != after.size ||
      before.modified != after.modified ||
      before.changed != after.changed;
}
