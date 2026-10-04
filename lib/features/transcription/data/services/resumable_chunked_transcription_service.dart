import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../project/domain/models/lyric_document.dart';
import '../../domain/models/transcription_models.dart';
import '../../domain/services/transcription_service.dart';

/// Runs long audio as resumable chunks while keeping the wrapped service's
/// quality policy intact for every chunk.
class ResumableChunkedTranscriptionService implements TranscriptionService {
  final TranscriptionService delegate;
  final Duration chunkDuration;
  final Duration overlap;
  final int maxAttempts;

  final StreamController<TranscriptionProgress> _progressController =
      StreamController<TranscriptionProgress>.broadcast();

  bool _running = false;
  bool _cancelRequested = false;
  Process? _activeFfmpeg;

  ResumableChunkedTranscriptionService({
    required this.delegate,
    this.chunkDuration = const Duration(minutes: 3),
    this.overlap = const Duration(seconds: 8),
    this.maxAttempts = 3,
  }) : assert(chunkDuration > overlap),
       assert(maxAttempts > 0);

  @override
  Stream<TranscriptionProgress> get progressStream => _progressController.stream;

  @override
  bool get isRunning => _running;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    if (_running) throw const TranscriptionException('已有分片识别任务正在运行');
    _running = true;
    _cancelRequested = false;

    try {
      final root = Directory(
        request.outputDirectory + Platform.pathSeparator + 'chunk_session',
      );
      await root.create(recursive: true);
      final chunksDir = Directory(root.path + Platform.pathSeparator + 'chunks');
      await chunksDir.create(recursive: true);

      _emit(TranscriptionStage.preprocessing, 0.01, '正在分析音频并准备可恢复分片');
      final duration = await _probeDuration(
        request.config.ffmpegExecutable,
        request.inputAudioPath,
      );
      _throwIfCancelled();

      // Short songs keep the existing path and avoid needless chunk overhead.
      if (duration <= chunkDuration) {
        return await _runDelegate(request, prefix: '');
      }

      final plan = _buildPlan(duration);
      final fingerprint = await _fingerprint(request.inputAudioPath);
      final manifestFile = File(root.path + Platform.pathSeparator + 'session.json');
      var manifest = await _loadManifest(manifestFile);
      final compatible = manifest != null &&
          manifest['version'] == 1 &&
          manifest['sourceFingerprint'] == fingerprint &&
          manifest['chunkMs'] == chunkDuration.inMilliseconds &&
          manifest['overlapMs'] == overlap.inMilliseconds;

      if (!compatible) {
        if (await chunksDir.exists()) {
          await chunksDir.delete(recursive: true);
          await chunksDir.create(recursive: true);
        }
        manifest = <String, dynamic>{
          'version': 1,
          'sourceFingerprint': fingerprint,
          'chunkMs': chunkDuration.inMilliseconds,
          'overlapMs': overlap.inMilliseconds,
          'durationMs': duration.inMilliseconds,
          'completed': <String>[],
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        };
        await _writeManifest(manifestFile, manifest);
      }

      final completed = ((manifest!['completed'] as List?) ?? const [])
          .map((e) => e.toString())
          .toSet();
      final restored = completed.where(
        (id) => File(chunksDir.path + Platform.pathSeparator + id + '.json').existsSync(),
      ).length;
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
          chunksDir.path + Platform.pathSeparator + id + '.json',
        );
        if (completed.contains(id) && await resultFile.exists()) continue;

        final wav = File(chunksDir.path + Platform.pathSeparator + id + '.wav');
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
            final chunkOutput = Directory(
              chunksDir.path + Platform.pathSeparator + id + '_work',
            );
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
            if (error.message == '歌词识别已取消') rethrow;
            lastError = error;
            if (attempt == maxAttempts) break;
            await Future<void>.delayed(Duration(seconds: attempt));
          }
        }

        if (result == null) {
          throw TranscriptionException(
            '分片 ${index + 1} / ${plan.length} 连续失败',
            details: lastError.toString(),
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

        // Chunk WAV is reproducible; checkpoint JSON is the valuable state.
        if (await wav.exists()) await wav.delete();
      }

      _throwIfCancelled();
      _emit(TranscriptionStage.parsing, 0.98, '正在合并分片并清理重叠歌词');
      final documents = <LyricDocument>[];
      final languages = <String>[];
      for (var index = 0; index < plan.length; index++) {
        final json = jsonDecode(
          await File(
            chunksDir.path + Platform.pathSeparator + _chunkId(index) + '.json',
          ).readAsString(),
        ) as Map<String, dynamic>;
        documents.add(
          LyricDocument.fromJson(
            Map<String, dynamic>.from(json['lyrics'] as Map),
          ),
        );
        final language = json['language']?.toString();
        if (language != null && language.isNotEmpty) languages.add(language);
      }

      final merged = _mergeDocuments(documents);
      final finalFile = File(root.path + Platform.pathSeparator + 'merged_result.json');
      await finalFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(merged.toJson()),
        flush: true,
      );
      _emit(TranscriptionStage.completed, 1.0, '全部 ${plan.length} 个分片识别并合并完成');

      return TranscriptionResult(
        lyrics: merged.copyWith(metadata: {
          ...merged.metadata,
          'chunked': true,
          'chunkCount': plan.length,
          'chunkDurationMs': chunkDuration.inMilliseconds,
          'chunkOverlapMs': overlap.inMilliseconds,
          'checkpointDirectory': root.path,
        }),
        normalizedAudioPath: request.inputAudioPath,
        rawJsonPath: finalFile.path,
        detectedLanguage: _mostCommon(languages),
      );
    } on _ChunkCancelled {
      _emit(TranscriptionStage.cancelled, 0.0, '分片识别已取消，已完成进度已保存');
      throw const TranscriptionException('歌词识别已取消');
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

  Future<Duration> _probeDuration(String executable, String input) async {
    final result = await Process.run(executable, [
      '-i', input, '-f', 'null', Platform.isWindows ? 'NUL' : '/dev/null',
    ]);
    final text = result.stderr.toString();
    final match = RegExp(r'Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)').firstMatch(text);
    if (match == null) throw const TranscriptionException('无法读取音频时长');
    final hours = int.parse(match.group(1)!);
    final minutes = int.parse(match.group(2)!);
    final seconds = double.parse(match.group(3)!);
    return Duration(milliseconds: (((hours * 3600 + minutes * 60) + seconds) * 1000).round());
  }

  Future<void> _extractChunk({
    required String executable,
    required String inputPath,
    required String outputPath,
    required Duration start,
    required Duration duration,
  }) async {
    final file = File(outputPath);
    if (await file.exists()) await file.delete();
    final process = await Process.start(executable, [
      '-y',
      '-ss', (start.inMilliseconds / 1000).toStringAsFixed(3),
      '-i', inputPath,
      '-t', (duration.inMilliseconds / 1000).toStringAsFixed(3),
      '-vn', '-ar', '16000', '-ac', '1', '-c:a', 'pcm_s16le',
      outputPath,
    ]);
    _activeFfmpeg = process;
    if (_cancelRequested) process.kill();
    final stderr = utf8.decoder.bind(process.stderr).join();
    final stdoutDrain = process.stdout.drain<void>();
    final code = await process.exitCode;
    await stdoutDrain;
    final error = await stderr;
    if (identical(_activeFfmpeg, process)) _activeFfmpeg = null;
    _throwIfCancelled();
    if (code != 0 || !await file.exists()) {
      throw TranscriptionException('音频分片失败', details: error);
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
    return document.copyWith(
      lines: document.lines.map((line) => line.copyWith(
        startTime: line.startTime + offset,
        endTime: line.endTime + offset,
      )).toList(growable: false),
    );
  }

  LyricDocument _mergeDocuments(List<LyricDocument> documents) {
    if (documents.isEmpty) {
      return const LyricDocument(language: 'unknown', lines: []);
    }
    final lines = <LyricLine>[];
    for (final document in documents) {
      for (final line in document.lines) {
        final duplicateIndex = lines.lastIndexWhere((existing) =>
          _normalize(existing.text) == _normalize(line.text) &&
          (existing.startTime - line.startTime).abs() <= overlap);
        if (duplicateIndex >= 0) {
          if (line.confidence > lines[duplicateIndex].confidence) {
            lines[duplicateIndex] = line;
          }
        } else {
          lines.add(line);
        }
      }
    }
    lines.sort((a, b) => a.startTime.compareTo(b.startTime));
    return LyricDocument(
      language: documents.first.language,
      lines: lines,
      metadata: {'mergeStrategy': 'overlapTextAndTimeDedup'},
    );
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u3400-\u9fff\u3040-\u30ff]+'), '');

  Future<String> _fingerprint(String path) async {
    final file = File(path);
    final stat = await file.stat();
    return '${stat.size}:${stat.modified.toUtc().millisecondsSinceEpoch}:${file.absolute.path}';
  }

  Future<Map<String, dynamic>?> _loadManifest(File file) async {
    if (!await file.exists()) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeManifest(File file, Map<String, dynamic> manifest) async {
    final temp = File(file.path + '.tmp');
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
    for (final value in values) counts[value] = (counts[value] ?? 0) + 1;
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  void _emit(TranscriptionStage stage, double progress, String message) {
    if (!_progressController.isClosed) {
      _progressController.add(TranscriptionProgress(
        stage: stage,
        progress: progress.clamp(0.0, 1.0).toDouble(),
        message: message,
      ));
    }
  }

  void _throwIfCancelled() {
    if (_cancelRequested) throw const _ChunkCancelled();
  }

  @override
  Future<void> cancel() async {
    if (!_running) return;
    _cancelRequested = true;
    _activeFfmpeg?.kill();
    await delegate.cancel();
  }

  @override
  Future<void> dispose() async {
    _cancelRequested = true;
    _activeFfmpeg?.kill();
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
