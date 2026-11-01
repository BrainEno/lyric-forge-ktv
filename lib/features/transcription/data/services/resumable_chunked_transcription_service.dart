import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../../project/domain/models/lyric_document.dart';
import '../../domain/models/transcription_models.dart';
import '../../domain/services/transcription_service.dart';
import 'asr_audio_normalization.dart';
import 'asr_process_supervisor.dart';

/// Splits genuinely long audio into resumable chunks, keeping the wrapped
/// service's quality policy intact for every chunk.
///
/// Songs must not be chunked here. Every ASR engine already handles a full song
/// on its own (the Qwen runtime splits at 180 s internally with its forced
/// aligner, Whisper uses a sliding window), and a second, coarser split above
/// them is what creates half-sentences at the seams, resets the decoder context
/// twice per song, and replaces whole-song engine disagreement with per-seam
/// bookkeeping. The wrapper therefore only takes over when the audio is far
/// longer than any song, where resuming inference is worth more than seam
/// fidelity.
class ResumableChunkedTranscriptionService implements TranscriptionService {
  /// Audio at or below this length is sent to the delegate in one pass.
  static const Duration defaultChunkDuration = Duration(minutes: 20);

  /// Default seam overlap. Only meaningful for the >[defaultChunkDuration] path.
  static const Duration defaultOverlap = Duration(seconds: 8);

  /// Version of the on-disk checkpoint manifest, bumped whenever the
  /// compatibility rules change so stale checkpoints cannot be reused.
  static const int checkpointManifestVersion = 2;

  final TranscriptionService delegate;
  final Duration chunkDuration;
  final Duration overlap;
  final int maxAttempts;
  final AsrProcessSupervisor _processSupervisor;
  final Duration durationProbeTimeout;

  final StreamController<TranscriptionProgress> _progressController =
      StreamController<TranscriptionProgress>.broadcast();

  bool _running = false;
  bool _cancelRequested = false;
  Process? _activeFfmpeg;

  ResumableChunkedTranscriptionService({
    required this.delegate,
    this.chunkDuration = defaultChunkDuration,
    this.overlap = defaultOverlap,
    this.maxAttempts = 3,
    AsrProcessSupervisor? processSupervisor,
    this.durationProbeTimeout = const Duration(seconds: 45),
  }) : _processSupervisor = processSupervisor ?? AsrProcessSupervisor(),
       assert(chunkDuration > overlap),
       assert(maxAttempts > 0),
       assert(durationProbeTimeout > Duration.zero);

  /// Fingerprint of every recognition setting that can change the output.
  ///
  /// Checkpoints are only reusable when this matches. Without it, switching
  /// between "Whisper only" and "highest quality", changing the engine order,
  /// picking a different model, or fixing a broken runtime would all silently
  /// replay the previous run's lyrics — which reads to the user as "the app
  /// cannot recognise anything, no matter what I pick". Executables are
  /// included because a replaced binary is a different recogniser, and the
  /// value is hashed so absolute paths stay out of the project directory.
  static String checkpointConfigFingerprint(TranscriptionConfig config) {
    final material = [
      'mode=${config.mode.name}',
      'engineOrder=${config.engineOrder.name}',
      'qwenExecutable=${config.qwenExecutable}',
      'qwenModelPath=${config.qwenModelPath}',
      'qwenAlignerModelPath=${config.qwenAlignerModelPath}',
      'qwenDevice=${config.qwenDevice}',
      'qwenDtype=${config.qwenDtype}',
      'whisperExecutable=${config.whisperExecutable}',
      'modelPath=${config.modelPath}',
      'language=${config.language}',
      'fallbackConfidenceThreshold=${config.fallbackConfidenceThreshold}',
      'maxFallbackSegments=${config.maxFallbackSegments}',
    ].join('\u0000');
    return sha256.convert(utf8.encode(material)).toString();
  }

  @override
  Stream<TranscriptionProgress> get progressStream =>
      _progressController.stream;

  @override
  bool get isRunning => _running;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    if (_running) {
      throw const TranscriptionException.busy('已有分片识别任务正在运行');
    }
    _running = true;
    _cancelRequested = false;

    try {
      _emit(TranscriptionStage.preprocessing, 0.01, '正在分析音频时长');
      final duration = await _probeDuration(
        request.config.ffmpegExecutable,
        request.inputAudioPath,
      );
      _throwIfCancelled();

      // A song is one recognisable unit: hand it to the delegate whole and let
      // the engine's own internal windowing do its job. Chunking here is only
      // for audio long enough that resuming beats seam fidelity. Probing first
      // also means the whole-song path leaves no chunk session behind at all.
      if (duration <= chunkDuration) {
        return await _runDelegate(request, prefix: '');
      }

      final root = Directory(
        '${request.outputDirectory}${Platform.pathSeparator}chunk_session',
      );
      await root.create(recursive: true);
      final chunksDir = Directory(
        '${root.path}${Platform.pathSeparator}chunks',
      );
      await chunksDir.create(recursive: true);
      _emit(TranscriptionStage.preprocessing, 0.02, '正在准备可恢复分片');
      _throwIfCancelled();

      final plan = _buildPlan(duration);
      final fingerprint = await _fingerprint(request.inputAudioPath);
      final configFingerprint = checkpointConfigFingerprint(request.config);
      final manifestFile = File(
        '${root.path}${Platform.pathSeparator}session.json',
      );
      var manifest = await _loadManifest(manifestFile);
      final compatible =
          manifest != null &&
          manifest['version'] == checkpointManifestVersion &&
          manifest['sourceFingerprint'] == fingerprint &&
          manifest['configFingerprint'] == configFingerprint &&
          manifest['chunkMs'] == chunkDuration.inMilliseconds &&
          manifest['overlapMs'] == overlap.inMilliseconds;

      if (!compatible) {
        if (await chunksDir.exists()) {
          await chunksDir.delete(recursive: true);
          await chunksDir.create(recursive: true);
        }
        manifest = <String, dynamic>{
          'version': checkpointManifestVersion,
          'sourceFingerprint': fingerprint,
          'configFingerprint': configFingerprint,
          'chunkMs': chunkDuration.inMilliseconds,
          'overlapMs': overlap.inMilliseconds,
          'durationMs': duration.inMilliseconds,
          'completed': <String>[],
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        };
        await _writeManifest(manifestFile, manifest);
      }

      final completed = ((manifest['completed'] as List?) ?? const [])
          .map((e) => e.toString())
          .toSet();
      final restored = completed
          .where(
            (id) => File(
              '${chunksDir.path}${Platform.pathSeparator}$id.json',
            ).existsSync(),
          )
          .length;
      if (restored > 0) {
        _emit(
          TranscriptionStage.transcribing,
          restored / plan.length,
          '已恢复上次 $restored / ${plan.length} 个分片结果',
        );
      }

      for (var index = 0; index < plan.length; index++) {
        _throwIfCancelled();
        final chunk = plan[index];
        final id = _chunkId(index);
        final resultFile = File(
          '${chunksDir.path}${Platform.pathSeparator}$id.json',
        );
        if (completed.contains(id) && await resultFile.exists()) continue;

        final wav = File('${chunksDir.path}${Platform.pathSeparator}$id.wav');
        await _extractChunk(
          executable: request.config.ffmpegExecutable,
          inputPath: request.inputAudioPath,
          outputPath: wav.path,
          start: chunk.start,
          duration: chunk.end - chunk.start,
        );
        _throwIfCancelled();

        TranscriptionResult? result;
        Object? lastError;
        final chunkOutput = Directory(
          '${chunksDir.path}${Platform.pathSeparator}${id}_work',
        );
        for (var attempt = 1; attempt <= maxAttempts; attempt++) {
          _throwIfCancelled();
          final base = index / plan.length;
          _emit(
            TranscriptionStage.transcribing,
            base,
            attempt == 1
                ? '正在识别分片 ${index + 1} / ${plan.length}'
                : '分片 ${index + 1} / ${plan.length} 失败，正在重试 $attempt / $maxAttempts',
          );
          try {
            await chunkOutput.create(recursive: true);
            result = await _runDelegate(
              TranscriptionRequest(
                inputAudioPath: wav.path,
                outputDirectory: chunkOutput.path,
                config: request.config,
                context: request.context,
              ),
              prefix: '分片 ${index + 1}/${plan.length} · ',
              base: base,
              span: 1 / plan.length,
            );
            break;
          } on TranscriptionException catch (error) {
            if (error.kind == TranscriptionFailureKind.cancelled ||
                error.message == '歌词识别已取消') {
              rethrow;
            }
            if (error.blocksQueue) {
              // Retrying the same chunk cannot repair a missing executable,
              // crashed runtime, driver problem or model environment. Preserve
              // the structured kind so the outer queue can pause immediately.
              rethrow;
            }
            lastError = error;
            if (attempt == maxAttempts) break;
            await Future<void>.delayed(Duration(seconds: attempt));
          }
        }

        if (result == null) {
          final failureKind = lastError is TranscriptionException
              ? lastError.kind
              : TranscriptionFailureKind.unknown;
          throw TranscriptionException(
            '分片 ${index + 1} / ${plan.length} 连续失败',
            details: lastError.toString(),
            kind: failureKind,
          );
        }

        final shifted = _shiftDocument(result.lyrics, chunk.start);
        await resultFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'id': id,
            'index': index,
            'startMs': chunk.start.inMilliseconds,
            'endMs': chunk.end.inMilliseconds,
            'language': result.detectedLanguage,
            'lyrics': shifted.toJson(),
          }),
          flush: true,
        );
        completed.add(id);
        manifest['completed'] = completed.toList()..sort();
        manifest['updatedAt'] = DateTime.now().toUtc().toIso8601String();
        await _writeManifest(manifestFile, manifest);

        // The chunk WAV and the delegate's per-chunk working directory are
        // reproducible; the checkpoint JSON is the valuable state. Leaving the
        // working directories behind used to fill the project with one
        // normalized copy of the audio per chunk.
        if (await wav.exists()) await wav.delete();
        if (await chunkOutput.exists()) {
          await chunkOutput.delete(recursive: true);
        }
      }

      _throwIfCancelled();
      _emit(TranscriptionStage.parsing, 0.98, '正在合并分片并清理重叠歌词');
      final documents = <LyricDocument>[];
      final languages = <String>[];
      for (var index = 0; index < plan.length; index++) {
        final json =
            jsonDecode(
                  await File(
                    '${chunksDir.path}${Platform.pathSeparator}${_chunkId(index)}.json',
                  ).readAsString(),
                )
                as Map<String, dynamic>;
        documents.add(
          LyricDocument.fromJson(
            Map<String, dynamic>.from(json['lyrics'] as Map),
          ),
        );
        final language = json['language']?.toString();
        if (language != null && language.isNotEmpty) languages.add(language);
      }

      final merged = _mergeDocuments(documents);
      final finalFile = File(
        '${root.path}${Platform.pathSeparator}merged_result.json',
      );
      await finalFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(merged.toJson()),
        flush: true,
      );
      _emit(TranscriptionStage.completed, 1.0, '全部 ${plan.length} 个分片识别并合并完成');

      return TranscriptionResult(
        lyrics: merged.copyWith(
          metadata: {
            ...merged.metadata,
            'chunked': true,
            'chunkCount': plan.length,
            'chunkDurationMs': chunkDuration.inMilliseconds,
            'chunkOverlapMs': overlap.inMilliseconds,
            'checkpointDirectory': root.path,
          },
        ),
        normalizedAudioPath: request.inputAudioPath,
        rawJsonPath: finalFile.path,
        detectedLanguage: _mostCommon(languages),
      );
    } on _ChunkCancelled {
      _emit(TranscriptionStage.cancelled, 0.0, '分片识别已取消，已完成进度已保存');
      throw const TranscriptionException.cancelled('歌词识别已取消');
    } finally {
      _running = false;
      _cancelRequested = false;
      _activeFfmpeg = null;
    }
  }

  List<_Chunk> _buildPlan(Duration total) {
    final result = <_Chunk>[];
    final step = chunkDuration - overlap;
    var start = Duration.zero;
    while (start < total) {
      final candidateEnd = start + chunkDuration;
      final end = candidateEnd < total ? candidateEnd : total;
      result.add(_Chunk(start, end));
      if (end >= total) break;
      start += step;
    }
    return result;
  }

  Future<AsrProcessResult> _runFfmpeg({
    required String executable,
    required List<String> arguments,
    required Duration timeout,
    required String operation,
  }) async {
    _throwIfCancelled();
    try {
      final result = await _processSupervisor.run(
        executable,
        arguments,
        timeout: timeout,
        operation: 'FFmpeg $operation',
        maxOutputLines: 80,
        maxLineLength: 2048,
        onProcessChanged: (process) {
          _activeFfmpeg = process;
          if (process != null && _cancelRequested) {
            unawaited(_processSupervisor.terminate(process));
          }
        },
      );
      _throwIfCancelled();
      return result;
    } on AsrProcessTimeoutException catch (error) {
      _throwIfCancelled();
      throw TranscriptionException.environment(
        'FFmpeg $operation 超时',
        details: error.toString(),
      );
    } on ProcessException catch (error) {
      _throwIfCancelled();
      throw TranscriptionException.environment(
        '无法启动 FFmpeg 执行$operation',
        details: error.message,
      );
    } finally {
      _activeFfmpeg = null;
    }
  }

  Future<Duration> _probeDuration(String executable, String input) async {
    // Asking FFmpeg to write zero seconds of output reads container metadata
    // without decoding the entire source just to discover its duration.
    final result = await _runFfmpeg(
      executable: executable,
      arguments: [
        '-hide_banner',
        '-i',
        input,
        '-t',
        '0',
        '-f',
        'null',
        Platform.isWindows ? 'NUL' : '-',
      ],
      timeout: durationProbeTimeout,
      operation: '读取音频时长',
    );
    final diagnostic = result.stderrTail.join('\n');
    if (result.exitCode != 0) {
      throw TranscriptionException.input('无法读取音频时长', details: diagnostic);
    }
    final match = RegExp(
      r'Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)',
    ).firstMatch(diagnostic);
    if (match == null) {
      throw TranscriptionException.input(
        '无法读取音频时长',
        details: diagnostic.isEmpty ? null : diagnostic,
      );
    }
    final hours = int.parse(match.group(1)!);
    final minutes = int.parse(match.group(2)!);
    final seconds = double.parse(match.group(3)!);
    final duration = Duration(
      milliseconds: (((hours * 3600 + minutes * 60) + seconds) * 1000).round(),
    );
    if (duration <= Duration.zero) {
      throw const TranscriptionException.input('音频时长必须大于零');
    }
    return duration;
  }

  Future<void> _extractChunk({
    required String executable,
    required String inputPath,
    required String outputPath,
    required Duration start,
    required Duration duration,
  }) async {
    final file = File(outputPath);
    var outputComplete = false;
    try {
      if (await file.exists()) await file.delete();
      final timeout = await AsrProcessTimeoutPolicy.ffmpegPreprocessingForFile(
        inputPath,
      );
      final result = await _runFfmpeg(
        executable: executable,
        arguments: AsrAudioNormalization.chunkArguments(
          inputPath: inputPath,
          outputPath: outputPath,
          start: start,
          duration: duration,
        ),
        timeout: timeout,
        operation: '音频分片',
      );
      final diagnostic = result.stderrTail.join('\n');
      if (result.exitCode != 0) {
        throw TranscriptionException.input('音频分片失败', details: diagnostic);
      }
      if (!await file.exists() || await file.length() <= 44) {
        throw TranscriptionException.input(
          'FFmpeg 未生成有效的音频分片',
          details: diagnostic.isEmpty ? null : diagnostic,
        );
      }
      outputComplete = true;
    } finally {
      // WAV chunks can be regenerated. Do not touch successful JSON checkpoints.
      if (!outputComplete) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {
          // Preserve the original timeout, cancellation, or extraction error.
        }
      }
    }
  }

  Future<TranscriptionResult> _runDelegate(
    TranscriptionRequest request, {
    required String prefix,
    double base = 0,
    double span = 1,
  }) async {
    final subscription = delegate.progressStream.listen((p) {
      if (_cancelRequested) return;
      _emit(
        p.stage,
        (base + p.progress * span).clamp(0.0, 1.0).toDouble(),
        prefix + p.message,
      );
    });
    try {
      return await delegate.transcribe(request);
    } finally {
      await subscription.cancel();
    }
  }

  LyricDocument _shiftDocument(LyricDocument document, Duration offset) {
    final metadata = document.metadata;
    final candidates = metadata['fallbackCandidates'];
    return document.copyWith(
      lines: document.lines
          .map(
            (line) => line.copyWith(
              startTime: line.startTime + offset,
              endTime: line.endTime + offset,
            ),
          )
          .toList(growable: false),
      // Review candidates carry their own timestamps; leaving them in chunk
      // local time would describe the wrong part of the song.
      metadata: candidates is List
          ? {
              ...metadata,
              'fallbackCandidates': <Map<String, dynamic>>[
                for (final entry in candidates)
                  if (entry is Map)
                    _shiftCandidateTimes(
                      Map<String, dynamic>.from(entry),
                      offset,
                    ),
              ],
            }
          : metadata,
    );
  }

  Map<String, dynamic> _shiftCandidateTimes(
    Map<String, dynamic> candidate,
    Duration offset,
  ) {
    for (final key in const ['startMs', 'endMs']) {
      final value = candidate[key];
      if (value is num) {
        candidate[key] = value.toInt() + offset.inMilliseconds;
      }
    }
    return candidate;
  }

  LyricDocument _mergeDocuments(List<LyricDocument> documents) {
    if (documents.isEmpty) {
      return const LyricDocument(language: 'unknown', lines: []);
    }
    final lines = <LyricLine>[];
    // For each chunk: its own line index -> index in `lines` before sorting.
    final indexMaps = <List<int>>[];
    for (final document in documents) {
      final indexMap = List<int>.filled(document.lines.length, -1);
      for (var index = 0; index < document.lines.length; index++) {
        final line = document.lines[index];
        final duplicateIndex = lines.lastIndexWhere(
          (existing) =>
              _normalize(existing.text) == _normalize(line.text) &&
              _absoluteDuration(existing.startTime - line.startTime) <= overlap,
        );
        if (duplicateIndex >= 0) {
          indexMap[index] = duplicateIndex;
          if (line.confidence > lines[duplicateIndex].confidence) {
            lines[duplicateIndex] = line;
          }
        } else {
          indexMap[index] = lines.length;
          lines.add(line);
        }
      }
      indexMaps.add(indexMap);
    }

    final order = List<int>.generate(lines.length, (index) => index)
      ..sort((a, b) => lines[a].startTime.compareTo(lines[b].startTime));
    final sortedIndex = List<int>.filled(lines.length, -1);
    final sortedLines = <LyricLine>[];
    for (var position = 0; position < order.length; position++) {
      sortedIndex[order[position]] = position;
      sortedLines.add(lines[order[position]]);
    }
    final finalMaps = <List<int>>[
      for (final indexMap in indexMaps)
        <int>[
          for (final index in indexMap)
            index >= 0 && index < sortedIndex.length ? sortedIndex[index] : -1,
        ],
    ];

    return documents.first.copyWith(
      lines: sortedLines,
      metadata: _mergeMetadata(documents, finalMaps),
    );
  }

  /// Rebuilds document metadata across chunks instead of dropping it.
  ///
  /// Per-chunk engine identity, quality mode, fusion policy and the review
  /// evidence (`fallbackCandidates`, `secondaryOnlyLineIndices`,
  /// `suspiciousLineIndexes`) are the reason the editor can offer "use the
  /// other engine's line" at all. Those fields are line-indexed, so they are
  /// remapped onto the merged line list; counts are recomputed from the merged
  /// data rather than copied from one chunk.
  Map<String, dynamic> _mergeMetadata(
    List<LyricDocument> documents,
    List<List<int>> indexMaps,
  ) {
    final merged = <String, dynamic>{
      ...documents.first.metadata,
      'mergeStrategy': 'overlapTextAndTimeDedup',
    };
    // These point at a single chunk's working directory, which is not the
    // document the user ends up with. The merged result's own `rawJsonPath` is
    // reported by [transcribe] instead.
    merged
      ..remove('qwenRawJsonPath')
      ..remove('whisperRawJsonPath');

    int remap(int chunk, Object? rawIndex) {
      if (rawIndex is! num) return -1;
      final index = rawIndex.toInt();
      if (chunk >= indexMaps.length) return -1;
      final map = indexMaps[chunk];
      if (index < 0 || index >= map.length) return -1;
      return map[index];
    }

    List<int> remapIndexList(String key) {
      final result = <int>{};
      for (var chunk = 0; chunk < documents.length; chunk++) {
        final raw = documents[chunk].metadata[key];
        if (raw is! List) continue;
        for (final entry in raw) {
          final index = remap(chunk, entry);
          if (index >= 0) result.add(index);
        }
      }
      final sorted = result.toList()..sort();
      return sorted;
    }

    final secondaryOnly = remapIndexList('secondaryOnlyLineIndices');
    final suspicious = remapIndexList('suspiciousLineIndexes');
    final hasSecondaryOnlyKey = documents.any(
      (document) => document.metadata.containsKey('secondaryOnlyLineIndices'),
    );
    final hasSuspiciousKey = documents.any(
      (document) => document.metadata.containsKey('suspiciousLineIndexes'),
    );

    final candidates = <Map<String, dynamic>>[];
    final candidateLines = <int>{};
    var appliedCount = 0;
    var hasCandidateKey = false;
    for (var chunk = 0; chunk < documents.length; chunk++) {
      final metadata = documents[chunk].metadata;
      final applied = metadata['fallbackAppliedCount'];
      if (applied is num) appliedCount += applied.toInt();
      final raw = metadata['fallbackCandidates'];
      if (raw is! List) continue;
      hasCandidateKey = true;
      for (final entry in raw) {
        if (entry is! Map) continue;
        final candidate = Map<String, dynamic>.from(entry);
        final lineIndex = remap(chunk, candidate['lineIndex']);
        if (lineIndex < 0) continue;
        // A line that both chunks saw twice needs one candidate, not two; the
        // editor looks candidates up per line.
        if (!candidateLines.add(lineIndex)) continue;
        candidate['lineIndex'] = lineIndex;
        candidates.add(candidate);
      }
    }

    if (hasCandidateKey) {
      merged['fallbackCandidates'] = candidates;
      merged['fallbackCandidateCount'] = candidates.length;
      merged['fallbackAppliedCount'] = appliedCount;
    }
    if (hasSecondaryOnlyKey) {
      merged['secondaryOnlyLineIndices'] = secondaryOnly;
      merged['secondaryOnlyLineCount'] = secondaryOnly.length;
    }
    if (hasSuspiciousKey) {
      merged['suspiciousLineIndexes'] = suspicious;
    }
    return merged;
  }

  Duration _absoluteDuration(Duration value) =>
      value.isNegative ? -value : value;

  String _normalize(String value) => value.toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9\u3400-\u9fff\u3040-\u30ff]+'),
    '',
  );

  Future<String> _fingerprint(String path) async {
    final file = File(path);
    final stat = await file.stat();
    return '${stat.size}:${stat.modified.toUtc().millisecondsSinceEpoch}:${file.absolute.path}';
  }

  Future<Map<String, dynamic>?> _loadManifest(File file) async {
    if (!await file.exists()) return null;
    try {
      return Map<String, dynamic>.from(
        jsonDecode(await file.readAsString()) as Map,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeManifest(File file, Map<String, dynamic> manifest) async {
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  String _chunkId(int index) => 'chunk_${index.toString().padLeft(4, '0')}';

  String _mostCommon(List<String> values) {
    if (values.isEmpty) return 'unknown';
    final counts = <String, int>{};
    for (final value in values) {
      counts[value] = (counts[value] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  void _emit(TranscriptionStage stage, double progress, String message) {
    if (!_progressController.isClosed) {
      _progressController.add(
        TranscriptionProgress(
          stage: stage,
          progress: progress.clamp(0.0, 1.0).toDouble(),
          message: message,
        ),
      );
    }
  }

  void _throwIfCancelled() {
    if (_cancelRequested) throw const _ChunkCancelled();
  }

  @override
  Future<void> cancel() async {
    if (!_running) return;
    _cancelRequested = true;
    final process = _activeFfmpeg;
    if (process != null) await _processSupervisor.terminate(process);
    await delegate.cancel();
  }

  @override
  Future<void> dispose() async {
    _cancelRequested = true;
    final process = _activeFfmpeg;
    if (process != null) await _processSupervisor.terminate(process);
    await delegate.dispose();
    await _progressController.close();
  }
}

class _Chunk {
  final Duration start;
  final Duration end;
  const _Chunk(this.start, this.end);
}

class _ChunkCancelled implements Exception {
  const _ChunkCancelled();
}
