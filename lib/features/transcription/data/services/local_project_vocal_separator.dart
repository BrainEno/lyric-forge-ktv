import 'dart:convert';
import 'dart:io';

import '../../../project/domain/models/audio_asset.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../domain/models/transcription_models.dart';
import '../../domain/models/vocal_separation_models.dart';
import '../../domain/services/project_vocal_separator.dart';
import '../../domain/services/vocal_separation_planner.dart';
import 'asr_process_supervisor.dart' show AsrProcessStarter;
import 'separator_output_parser.dart';
import 'vocal_separator_runtime.dart';

/// Separates the lead vocal with `lyricforge-separator` (D-043).
///
/// One run: install or locate the separator, decode the song to the 44.1 kHz
/// stereo WAV the separator reads, separate into a fresh directory, check
/// the stem is not silent, and hand back the audio asset with the stem and
/// its provenance marker. Only cancellation escapes as an exception.
class LocalProjectVocalSeparator implements ProjectVocalSeparator {
  /// A vocal stem quieter than this fraction of the mix (about -30 dB) is
  /// treated as "no singing": recognising it would drop every lyric, while
  /// the mix still has a chance.
  static const double silentStemRatio = 0.03;
  static const Duration conversionTimeout = Duration(minutes: 5);
  static const Duration separationTimeout = Duration(minutes: 45);
  static const String _cancelledMessage = '歌词识别已取消';

  final VocalSeparatorRuntime _runtime;
  final AsrProcessStarter _startProcess;
  final VocalSeparationPlanner _planner;
  final DateTime Function() _now;
  final Stopwatch Function() _stopwatch;

  bool _cancelled = false;
  Process? _active;

  LocalProjectVocalSeparator({
    required VocalSeparatorRuntime runtime,
    AsrProcessStarter? startProcess,
    VocalSeparationPlanner planner = const VocalSeparationPlanner(),
    DateTime Function()? now,
    Stopwatch Function()? stopwatch,
  }) : _runtime = runtime,
       _startProcess = startProcess ?? _startPlatformProcess,
       _planner = planner,
       _now = now ?? DateTime.now,
       _stopwatch = stopwatch ?? Stopwatch.new;

  static Future<Process> _startPlatformProcess(
    String executable,
    List<String> arguments,
  ) => Process.start(executable, arguments, runInShell: false);

  @override
  Future<ProjectVocalSeparation> separate(
    ProjectManifest project, {
    required TranscriptionConfig config,
    required String workDirectory,
    required void Function(TranscriptionProgress progress) onProgress,
  }) async {
    _cancelled = false;
    final audio = project.audioAsset;
    if (audio == null) {
      return const ProjectVocalSeparation(
        VocalSeparationOutcome.skipped(VocalSeparationSkipReason.sourceMissing),
      );
    }
    final facts = await _facts(audio);
    _checkCancelled();
    final plan = _planner.plan(
      audio: audio,
      preference: config.vocalSeparation,
      platformSupported: _runtime.supportsCurrentPlatform,
      separatorRevision: _runtime.separatorRevision,
      facts: facts,
    );
    switch (plan.action) {
      case VocalSeparationAction.skip:
        return ProjectVocalSeparation(
          VocalSeparationOutcome.skipped(plan.skipReason!),
        );
      case VocalSeparationAction.reuse:
        final marker = plan.reusable!;
        return ProjectVocalSeparation(
          VocalSeparationOutcome.reused(
            vocalPath: marker.vocalPath,
            accompanimentPath: facts.accompanimentFileExists
                ? marker.accompanimentPath
                : null,
            provider: marker.provider,
            separatorRevision: marker.separatorRevision,
          ),
        );
      case VocalSeparationAction.run:
        return _run(audio, facts, config, workDirectory, onProgress);
    }
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    _runtime.cancel();
    _active?.kill();
  }

  Future<ProjectVocalSeparation> _run(
    AudioAsset audio,
    VocalSeparationFacts facts,
    TranscriptionConfig config,
    String workDirectory,
    void Function(TranscriptionProgress progress) onProgress,
  ) async {
    void report(double fraction, String message) => onProgress(
      TranscriptionProgress(
        stage: TranscriptionStage.preprocessing,
        progress: fraction.clamp(0.0, 1.0).toDouble(),
        message: message,
      ),
    );

    final stopwatch = _stopwatch()..start();
    final VocalSeparatorInstallation installation;
    try {
      installation = await _runtime.ensureInstalled(
        proxy: config.downloadProxy,
        onProgress: (fraction, message) => report(0.3 * fraction, message),
      );
    } on TranscriptionException catch (error) {
      if (error.kind == TranscriptionFailureKind.cancelled || _cancelled) {
        throw const TranscriptionException.cancelled(_cancelledMessage);
      }
      return _failed(VocalSeparationFailure.installFailed, error.toString());
    } on VocalSeparatorInstallException catch (error) {
      _checkCancelled();
      return _failed(VocalSeparationFailure.installFailed, error.toString());
    } catch (error) {
      _checkCancelled();
      return _failed(VocalSeparationFailure.installFailed, error.toString());
    }
    _checkCancelled();

    final runDirectory = Directory(
      _join(workDirectory, ['run-${_now().toUtc().millisecondsSinceEpoch}']),
    );
    final input = File(_join(runDirectory.path, ['input.wav']));
    try {
      await runDirectory.create(recursive: true);
      report(0.32, '正在准备人声分离音频');
      final conversion = await _runProcess(
        config.ffmpegExecutable,
        [
          '-nostdin',
          '-hide_banner',
          '-loglevel',
          'error',
          '-y',
          '-i',
          audio.originalPath,
          '-vn',
          '-ac',
          '2',
          '-ar',
          '44100',
          '-c:a',
          'pcm_s16le',
          input.path,
        ],
        timeout: conversionTimeout,
        startFailure: VocalSeparationFailure.conversionFailed,
      );
      _checkCancelled();
      if (conversion.exitCode != 0 || !await _nonEmpty(input)) {
        await _deleteQuietly(runDirectory);
        return _failed(
          VocalSeparationFailure.conversionFailed,
          'ffmpeg exit ${conversion.exitCode}: ${conversion.stderrTail}',
        );
      }

      final separatorReport = SeparatorRunReport();
      report(0.35, '正在分离人声');
      final separation = await _runProcess(
        installation.executablePath,
        [
          '--model',
          installation.modelPath,
          '--input',
          input.path,
          '--output-dir',
          runDirectory.path,
          '--provider',
          'auto',
          '--vocals-index',
          '${installation.manifest.vocalsIndex}',
        ],
        timeout: separationTimeout,
        startFailure: VocalSeparationFailure.separatorFailed,
        onStdoutLine: (line) {
          final event = parseSeparatorLine(line);
          if (event == null) return;
          separatorReport.add(event);
          if (event is SeparatorProgressEvent ||
              event is SeparatorStageEvent ||
              event is SeparatorDoneEvent) {
            final overall = separatorReport.overallProgress;
            report(
              0.35 + 0.65 * overall,
              '正在分离人声 ${(overall * 100).toStringAsFixed(0)}%',
            );
          }
        },
      );
      _checkCancelled();
      await _deleteQuietly(input);

      final failure = await _validate(separation, separatorReport, runDirectory);
      if (failure != null) {
        await _deleteQuietly(runDirectory);
        return ProjectVocalSeparation(
          VocalSeparationOutcome.failed(
            failure.$1,
            detail: failure.$2,
            provider: separatorReport.provider,
            fallbacks: List.unmodifiable(separatorReport.fallbacks),
            stats: separatorReport.stats,
            elapsed: stopwatch.elapsed,
          ),
        );
      }

      final vocalPath = _join(runDirectory.path, ['vocals.wav']);
      final accompaniment = File(
        _join(runDirectory.path, ['accompaniment.wav']),
      );
      final accompanimentPath = await _nonEmpty(accompaniment)
          ? accompaniment.path
          : null;
      final provider = separatorReport.provider ?? 'cpu';
      final marker = VocalStemMarker(
        separatorRevision: installation.manifest.separatorRevision,
        sourceFingerprint: VocalSeparationPlanner.fingerprintOf(
          audio.originalPath,
          facts,
        ),
        vocalPath: vocalPath,
        accompanimentPath: accompanimentPath,
        provider: provider,
        generatedAt: _now(),
      );
      await _pruneOldRuns(workDirectory, keep: {
        runDirectory.path,
        if (audio.vocalPath != null) File(audio.vocalPath!).parent.path,
      });
      return ProjectVocalSeparation(
        VocalSeparationOutcome.separated(
          vocalPath: vocalPath,
          accompanimentPath: accompanimentPath,
          provider: provider,
          fallbacks: List.unmodifiable(separatorReport.fallbacks),
          stats: separatorReport.stats,
          elapsed: stopwatch.elapsed,
          separatorRevision: installation.manifest.separatorRevision,
        ),
        updatedAudio: audio.copyWith(
          vocalPath: vocalPath,
          metadata: {
            ...audio.metadata,
            VocalStemMarker.metadataKey: marker.toJson(),
          },
        ),
      );
    } on TranscriptionException {
      await _deleteQuietly(runDirectory);
      rethrow;
    } on _ProcessStartFailure catch (error) {
      await _deleteQuietly(runDirectory);
      _checkCancelled();
      return _failed(error.failure, error.detail);
    } on FileSystemException catch (error) {
      await _deleteQuietly(runDirectory);
      _checkCancelled();
      return _failed(VocalSeparationFailure.invalidOutput, error.toString());
    }
  }

  Future<(VocalSeparationFailure, String)?> _validate(
    _ProcessOutcome separation,
    SeparatorRunReport report,
    Directory runDirectory,
  ) async {
    if (separation.timedOut) {
      return (
        VocalSeparationFailure.separatorFailed,
        'timed out after ${separationTimeout.inMinutes} minutes',
      );
    }
    if (separation.exitCode != 0 || !report.done) {
      final error = report.error;
      return (
        VocalSeparationFailure.separatorFailed,
        error == null
            ? 'exit ${separation.exitCode}: ${separation.stderrTail}'
            : 'exit ${separation.exitCode} (LF_ERROR ${error.code}): '
                  '${error.message}',
      );
    }
    final vocals = File(_join(runDirectory.path, ['vocals.wav']));
    if (!await _nonEmpty(vocals)) {
      return (VocalSeparationFailure.invalidOutput, 'vocals.wav is missing');
    }
    final ratio = report.stats?.vocalsToMixRatio;
    if (ratio != null && ratio < silentStemRatio) {
      return (
        VocalSeparationFailure.silentStem,
        'vocals/mix RMS ratio ${ratio.toStringAsFixed(4)}',
      );
    }
    return null;
  }

  Future<_ProcessOutcome> _runProcess(
    String executable,
    List<String> arguments, {
    required Duration timeout,
    required VocalSeparationFailure startFailure,
    void Function(String line)? onStdoutLine,
  }) async {
    final Process process;
    try {
      process = await _startProcess(executable, arguments);
    } on ProcessException catch (error) {
      throw _ProcessStartFailure(startFailure, error.toString());
    }
    _active = process;
    if (_cancelled) process.kill();

    final stderrTail = <String>[];
    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          try {
            onStdoutLine?.call(line);
          } catch (_) {
            // Progress reporting must not stop the pipe from draining.
          }
        })
        .asFuture<void>()
        .catchError(_pipeClosed);
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (stderrTail.length >= 8) stderrTail.removeAt(0);
          stderrTail.add(line.length > 300 ? line.substring(0, 300) : line);
        })
        .asFuture<void>()
        .catchError(_pipeClosed);

    var timedOut = false;
    final int exitCode;
    try {
      exitCode = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          timedOut = true;
          process.kill();
          return -1;
        },
      );
      await Future.wait([
        stdoutDone,
        stderrDone,
      ]).timeout(const Duration(seconds: 2), onTimeout: () => const []);
    } finally {
      if (identical(_active, process)) _active = null;
    }
    return _ProcessOutcome(exitCode, stderrTail.join(' | '), timedOut);
  }

  /// A pipe error only means the child went away; its exit code reports
  /// what happened.
  static void _pipeClosed(Object error) {
    // Nothing to do: the exit code and stderr tail carry the failure.
  }

  Future<VocalSeparationFacts> _facts(AudioAsset audio) async {
    final source = File(audio.originalPath);
    final exists = await source.exists();
    final stat = exists ? await source.stat() : null;
    final vocal = audio.vocalPath;
    final marker = VocalStemMarker.fromAudioMetadata(audio.metadata);
    final accompaniment = marker?.accompanimentPath;
    return VocalSeparationFacts(
      sourceExists: exists,
      sourceBytes: stat?.size ?? 0,
      sourceModified: stat?.modified,
      vocalFileExists:
          vocal != null &&
          vocal.trim().isNotEmpty &&
          await File(vocal).exists(),
      accompanimentFileExists:
          accompaniment != null && await File(accompaniment).exists(),
    );
  }

  /// Removes stems of earlier runs, keeping [keep] (this run and the stem
  /// the project still points at until the workflow saves the new one).
  Future<void> _pruneOldRuns(String workDirectory, {required Set<String> keep}) async {
    try {
      final normalizedKeep = keep.map(_normalize).toSet();
      await for (final entity in Directory(workDirectory).list()) {
        if (entity is! Directory) continue;
        final name = entity.path.split(RegExp(r'[\\/]')).last;
        if (!name.startsWith('run-')) continue;
        if (normalizedKeep.contains(_normalize(entity.path))) continue;
        await _deleteQuietly(entity);
      }
    } on FileSystemException {
      // Old stems are only disk space; never fail a run over them.
    }
  }

  ProjectVocalSeparation _failed(VocalSeparationFailure failure, String detail) =>
      ProjectVocalSeparation(
        VocalSeparationOutcome.failed(failure, detail: detail),
      );

  void _checkCancelled() {
    if (_cancelled) {
      throw const TranscriptionException.cancelled(_cancelledMessage);
    }
  }

  static Future<bool> _nonEmpty(File file) async =>
      await file.exists() && await file.length() > 44;

  static Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      if (await entity.exists()) await entity.delete(recursive: true);
    } on FileSystemException {
      // A locked leftover is removed by a later run.
    }
  }

  static String _normalize(String path) {
    final unified = path.replaceAll('\\', '/');
    final trimmed = unified.endsWith('/')
        ? unified.substring(0, unified.length - 1)
        : unified;
    return Platform.isWindows ? trimmed.toLowerCase() : trimmed;
  }

  static String _join(String root, List<String> parts) =>
      [root, ...parts].join(Platform.pathSeparator);
}

class _ProcessOutcome {
  final int exitCode;
  final String stderrTail;
  final bool timedOut;

  const _ProcessOutcome(this.exitCode, this.stderrTail, this.timedOut);
}

class _ProcessStartFailure implements Exception {
  final VocalSeparationFailure failure;
  final String detail;

  const _ProcessStartFailure(this.failure, this.detail);
}
