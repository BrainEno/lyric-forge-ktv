import 'dart:async';
import 'dart:io';

import '../../../lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import '../../../lyrics/domain/services/lyric_span_rerecognition.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/transcription_model_identity.dart';
import '../../domain/models/transcription_models.dart';
import '../../domain/services/asr_resource_coordinator.dart';
import '../../domain/services/asr_runtime_manager.dart';
import '../../domain/services/transcription_profile_resolver.dart';
import '../../domain/services/transcription_service.dart';
import '../../domain/services/transcription_settings_store.dart';
import 'asr_audio_normalization.dart';
import 'asr_process_supervisor.dart';
import 'project_recognition_hints.dart';
import 'project_transcription_input.dart';
import 'qwen3_asr_native_transcription_service.dart';
import 'whisper_cpp_transcription_service.dart';

/// Cuts `[start, start + length)` of [inputPath] into a 16 kHz mono WAV at
/// [outputPath]. [onProcess] receives the running FFmpeg process (and null
/// when it ends) so a cancel can stop it.
typedef SpanClipCutter =
    Future<void> Function({
      required String ffmpegExecutable,
      required String inputPath,
      required String outputPath,
      required Duration start,
      required Duration length,
      required void Function(Process? process) onProcess,
    });

/// Runs one stretch of a project's selected audio through Qwen3-ASR,
/// Whisper or the forced aligner, for the editor's "re-run this stretch".
///
/// The stretch is cut into its own clip, so the recogniser sees only that
/// part of the song, and the result is moved back onto the song's timeline.
/// Nothing is written to the project: the editor shows the result and
/// applies it as one undoable change.
///
/// Holds the shared [AsrResourceCoordinator] lease for the whole run, so a
/// transcription, alignment or runtime installation cannot start in between.
/// Qwen3-ASR runs on the app's shared adapter when one is given, so a model
/// server that is still loaded from a full recognition is reused instead of
/// a second one being started on the same GPU; that adapter is never
/// disposed here. Otherwise each recognition uses a new, exclusively owned
/// adapter that is disposed afterwards.
class ProjectSpanRecognitionService implements LyricSpanRecognizer {
  final ProjectRepository _projects;
  final TranscriptionSettingsStore _settings;
  final TranscriptionProfileResolver _profiles;
  final AsrRuntimeManager _runtime;
  final AsrResourceCoordinator _resources;
  final ForcedAlignmentRunner _alignClip;
  final TranscriptionService Function() _createQwen;
  final TranscriptionService Function() _createWhisper;
  final TranscriptionService? _sharedQwen;
  final SpanClipCutter _cutClip;

  /// Slack given to the aligner past the clip's nominal length, because
  /// FFmpeg rounds the cut to whole samples and the aligner rounds its
  /// times.
  static const Duration alignmentSlack = Duration(milliseconds: 250);

  bool _running = false;
  bool _cancelled = false;
  Process? _ffmpeg;
  TranscriptionService? _active;

  ProjectSpanRecognitionService({
    required ProjectRepository projects,
    required TranscriptionSettingsStore settings,
    required TranscriptionProfileResolver profiles,
    required AsrRuntimeManager runtime,
    required AsrResourceCoordinator resources,
    required ForcedAlignmentRunner alignClip,
    TranscriptionService Function()? createQwen,
    TranscriptionService Function()? createWhisper,
    TranscriptionService? sharedQwen,
    SpanClipCutter? cutClip,
  }) : _projects = projects,
       _settings = settings,
       _profiles = profiles,
       _runtime = runtime,
       _resources = resources,
       _alignClip = alignClip,
       _createQwen = createQwen ?? Qwen3AsrNativeTranscriptionService.new,
       _createWhisper = createWhisper ?? WhisperCppTranscriptionService.new,
       _sharedQwen = sharedQwen,
       _cutClip = cutClip ?? cutSpanClipWithFfmpeg;

  bool get isRunning => _running;

  @override
  Future<LyricRecognizedSpan> recognize({
    required String projectId,
    required Duration start,
    required Duration end,
    required LyricSpanEngine engine,
  }) async {
    return _run(projectId, start, end, (input, clip, length) async {
      final config = await _readyConfig(engine);
      _checkCancelled();
      final shared = engine == LyricSpanEngine.qwen ? _sharedQwen : null;
      final adapter =
          shared ??
          switch (engine) {
            LyricSpanEngine.qwen => _createQwen(),
            LyricSpanEngine.whisper => _createWhisper(),
          };
      if (adapter.isRunning) {
        throw const LyricSpanRecognitionException('识别服务正在使用，请稍后重试', busy: true);
      }
      _active = adapter;
      try {
        await _cutClip(
          ffmpegExecutable: config.ffmpegExecutable,
          inputPath: input.audioPath,
          outputPath: clip.wavPath,
          start: start,
          length: length,
          onProcess: (process) => _ffmpeg = process,
        );
        _checkCancelled();
        final result = await adapter.transcribe(
          TranscriptionRequest(
            inputAudioPath: clip.wavPath,
            normalizedInputAudioPath: clip.wavPath,
            outputDirectory: clip.directory.path,
            config: config,
            recognitionHints: input.hints,
          ),
        );
        _checkCancelled();
        return LyricRecognizedSpan(
          lines: List.unmodifiable([
            for (final line in result.lyrics.lines) _shift(line, start),
          ]),
          engineLabel: switch (engine) {
            LyricSpanEngine.qwen => TranscriptionModelIdentity.qwenAsrLabel(
              config.qwenModelPath,
            ),
            LyricSpanEngine.whisper => TranscriptionModelIdentity.whisperLabel(
              config.modelPath,
            ),
          },
          language: result.detectedLanguage,
        );
      } finally {
        _active = null;
        if (shared == null) await adapter.dispose();
      }
    });
  }

  @override
  Future<List<ForcedAlignedSpan>> align({
    required String projectId,
    required Duration start,
    required Duration end,
    required String text,
    required String language,
  }) async {
    if (text.trim().isEmpty) {
      throw const LyricSpanRecognitionException('这一段没有可对齐的歌词文字');
    }
    return _run(projectId, start, end, (input, clip, length) async {
      final saved = await _settings.load();
      _checkCancelled();
      if (saved == null) {
        throw const LyricSpanRecognitionException('请先完成本地歌词识别运行时配置');
      }
      final resolved = await _profiles.resolve(saved);
      _checkCancelled();
      await _cutClip(
        ffmpegExecutable: resolved.config.ffmpegExecutable,
        inputPath: input.audioPath,
        outputPath: clip.wavPath,
        start: start,
        length: length,
        onProcess: (process) => _ffmpeg = process,
      );
      _checkCancelled();
      final spans = await _alignClip(
        audioPath: clip.wavPath,
        text: text,
        language: language,
        audioDuration: length + alignmentSlack,
      );
      _checkCancelled();
      return List.unmodifiable([
        for (final span in spans)
          ForcedAlignedSpan(
            text: span.text,
            start: span.start + start,
            end: span.end + start,
          ),
      ]);
    });
  }

  @override
  Future<void> cancel() async {
    if (!_running) return;
    _cancelled = true;
    _ffmpeg?.kill();
    final active = _active;
    if (active != null) await active.cancel();
  }

  Future<T> _run<T>(
    String projectId,
    Duration start,
    Duration end,
    Future<T> Function(_SpanInput input, _SpanClip clip, Duration length) body,
  ) async {
    if (start.isNegative || end <= start) {
      throw const LyricSpanRecognitionException('识别范围无效');
    }
    if (end - start > LyricSpanRerecognitionPlanner.maxWindow) {
      throw const LyricSpanRecognitionException('识别范围过长，请缩短到 90 秒以内');
    }
    if (_running) {
      throw const LyricSpanRecognitionException('已有片段识别正在运行', busy: true);
    }
    if (_runtime.isInstalling) {
      throw const LyricSpanRecognitionException(
        '识别运行时正在安装或修复，请稍后重试',
        busy: true,
      );
    }
    final lease = _resources.tryAcquire(AsrResourceUse.spanRecognition);
    if (lease == null) {
      throw const LyricSpanRecognitionException(
        '识别资源正在被其他任务使用，请稍后重试',
        busy: true,
      );
    }
    _running = true;
    _cancelled = false;
    Directory? work;
    try {
      final project = await _projects.getProjectById(projectId);
      _checkCancelled();
      if (project == null) {
        throw const LyricSpanRecognitionException('工程不存在');
      }
      final duration = project.audioAsset?.duration;
      var clipEnd = end;
      if (duration != null && duration > Duration.zero && clipEnd > duration) {
        clipEnd = duration;
      }
      if (clipEnd <= start) {
        throw const LyricSpanRecognitionException('识别范围超出了音频长度');
      }
      final String audioPath;
      try {
        audioPath = await resolveProjectTranscriptionInput(project);
      } on TranscriptionException catch (error) {
        throw LyricSpanRecognitionException(error.message);
      }
      _checkCancelled();
      work = await Directory.systemTemp.createTemp('lyricforge-span-');
      _checkCancelled();
      final clip = _SpanClip(
        work,
        '${work.path}${Platform.pathSeparator}span.wav',
      );
      return await body(
        _SpanInput(audioPath, recognitionHintsForProject(project)),
        clip,
        clipEnd - start,
      );
    } on LyricSpanRecognitionException {
      rethrow;
    } on TranscriptionException catch (error) {
      if (_cancelled || error.kind == TranscriptionFailureKind.cancelled) {
        throw const LyricSpanRecognitionException('已取消', cancelled: true);
      }
      throw LyricSpanRecognitionException(
        error.message,
        busy: error.kind == TranscriptionFailureKind.busy,
      );
    } on ForcedAlignmentResourceBusyException {
      throw const LyricSpanRecognitionException(
        '对齐资源正在被其他任务使用，请稍后重试',
        busy: true,
      );
    } on Exception catch (error) {
      if (_cancelled) {
        throw const LyricSpanRecognitionException('已取消', cancelled: true);
      }
      throw LyricSpanRecognitionException('$error');
    } finally {
      _ffmpeg = null;
      try {
        if (work != null) await work.delete(recursive: true);
      } on FileSystemException {
        // A leftover temporary clip must not hide the real outcome.
      } finally {
        _running = false;
        _cancelled = false;
        lease.release();
      }
    }
  }

  /// The configuration for [engine], with the runtime repaired and every
  /// component it needs ready. Mirrors the independent re-run's preflight.
  Future<TranscriptionConfig> _readyConfig(LyricSpanEngine engine) async {
    final saved = await _settings.load();
    _checkCancelled();
    if (saved == null) {
      throw const LyricSpanRecognitionException('请先完成本地歌词识别运行时配置');
    }
    // Runtime inspection reports Qwen components only in highest-quality
    // mode; the mode selects what is inspected, not which engine runs.
    final requested = saved.copyWith(
      mode: engine == LyricSpanEngine.qwen
          ? TranscriptionMode.highestQuality
          : TranscriptionMode.whisperOnly,
    );
    final resolved = await _profiles.resolve(requested);
    _checkCancelled();
    _checkNotInstalling();
    final config = await _runtime.repair(resolved.config);
    _checkCancelled();
    _checkNotInstalling();
    final status = await _runtime.inspect(config);
    _checkCancelled();
    _checkNotInstalling();
    final required = switch (engine) {
      LyricSpanEngine.qwen => const {
        AsrRuntimeComponent.ffmpeg,
        AsrRuntimeComponent.qwenRuntime,
        AsrRuntimeComponent.qwenModel,
        AsrRuntimeComponent.qwenAligner,
      },
      LyricSpanEngine.whisper => const {
        AsrRuntimeComponent.ffmpeg,
        AsrRuntimeComponent.whisperRuntime,
        AsrRuntimeComponent.whisperModel,
      },
    };
    final configured = switch (engine) {
      LyricSpanEngine.qwen => config.isQwenConfigured,
      LyricSpanEngine.whisper => config.isWhisperConfigured,
    };
    if (!status.hasReadyComponents(required) || !configured) {
      throw LyricSpanRecognitionException(
        engine == LyricSpanEngine.qwen
            ? 'Qwen3-ASR 运行环境或模型尚未就绪，请先在转写设置中准备高质量运行环境'
            : 'Whisper 运行环境或模型尚未就绪，请先检查本地运行环境',
      );
    }
    return config;
  }

  void _checkNotInstalling() {
    if (_runtime.isInstalling) {
      throw const LyricSpanRecognitionException(
        '识别运行时正在安装或修复，请稍后重试',
        busy: true,
      );
    }
  }

  void _checkCancelled() {
    if (_cancelled) {
      throw const LyricSpanRecognitionException('已取消', cancelled: true);
    }
  }

  static LyricLine _shift(LyricLine line, Duration by) => line.copyWith(
    startTime: line.startTime + by,
    endTime: line.endTime + by,
    words: [
      for (final word in line.words)
        LyricWordTiming(
          text: word.text,
          start: word.start + by,
          end: word.end + by,
        ),
    ],
  );
}

class _SpanInput {
  final String audioPath;
  final RecognitionHints hints;

  const _SpanInput(this.audioPath, this.hints);
}

class _SpanClip {
  final Directory directory;
  final String wavPath;

  const _SpanClip(this.directory, this.wavPath);
}

/// The default [SpanClipCutter]: FFmpeg through the bounded process
/// supervisor, with the same output format as whole-song preprocessing.
Future<void> cutSpanClipWithFfmpeg({
  required String ffmpegExecutable,
  required String inputPath,
  required String outputPath,
  required Duration start,
  required Duration length,
  required void Function(Process? process) onProcess,
}) async {
  final result = await AsrProcessSupervisor().run(
    ffmpegExecutable,
    AsrAudioNormalization.chunkArguments(
      inputPath: inputPath,
      outputPath: outputPath,
      start: start,
      duration: length,
    ),
    timeout: const Duration(minutes: 2),
    operation: '片段音频裁剪',
    onProcessChanged: onProcess,
  );
  final file = File(outputPath);
  // A WAV header alone is 44 bytes: anything that small holds no audio.
  if (result.exitCode != 0 ||
      !await file.exists() ||
      await file.length() <= 44) {
    throw TranscriptionException.input(
      'FFmpeg 未能裁剪出这一段音频',
      details: result.stderrTail.join('\n'),
    );
  }
}
