import '../../../lyrics/domain/services/lyric_span_rerecognition.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../models/transcription_models.dart';
import '../models/vocal_gap_fill_models.dart';
import 'asr_runtime_manager.dart';

/// What the gap-fill step needs from the recognition run around it.
class VocalGapFillRequest {
  /// The vocal audio the draft was recognised from; clips are cut from it,
  /// so recognised rows land on the draft's timeline.
  final String audioPath;

  /// The run's repaired configuration.
  final TranscriptionConfig config;

  /// Engines in the order to try them for each stretch.
  final List<LyricSpanEngine> engines;

  /// Title, artist and terms, as for the whole song.
  final RecognitionHints hints;

  /// Length of the song, when known; windows never reach past it.
  final Duration? audioDuration;

  final void Function(TranscriptionProgress progress)? onProgress;

  const VocalGapFillRequest({
    required this.audioPath,
    required this.config,
    required this.engines,
    this.hints = const RecognitionHints(),
    this.audioDuration,
    this.onProgress,
  });
}

/// The optional last step of whole-song recognition (D-047): recognise every
/// stretch the vocal check heard singing but no row in, and insert what is
/// heard.
///
/// Runs inside the recognition run and its resource lease, so it must not
/// take a lease of its own.
abstract interface class TranscriptionVocalGapFill {
  /// Never throws: whatever goes wrong leaves [draft] unchanged, with a
  /// report saying why. After [cancel] it returns promptly with the rows
  /// found so far and [VocalGapFillStopReason.cancelled].
  Future<VocalGapFillResult> fill(
    LyricDocument draft,
    VocalGapFillRequest request,
  );

  /// Stops the clip being cut or recognised. Safe to call at any time.
  Future<void> cancel();
}

/// The engines for the step, in the order to try them.
///
/// Whisper is the baseline every run has. Qwen3-ASR joins only when this run
/// asked for two engines, its runtime and model are ready, and the run was
/// not degraded to Whisper (a Qwen that just failed on the song will not do
/// better on a clip of it). The run's engine order decides which goes first.
List<LyricSpanEngine> vocalGapFillEngines({
  required TranscriptionConfig config,
  required AsrRuntimeStatus status,
  required bool degraded,
}) {
  // The run itself already required the Whisper baseline.
  final whisperReady = config.isWhisperConfigured && status.isBaselineReady;
  final qwenReady =
      config.mode == TranscriptionMode.highestQuality &&
      !degraded &&
      config.isQwenConfigured &&
      status.hasReadyComponents(const {
        AsrRuntimeComponent.ffmpeg,
        AsrRuntimeComponent.qwenRuntime,
        AsrRuntimeComponent.qwenModel,
        AsrRuntimeComponent.qwenAligner,
      });
  final qwenFirst = config.engineOrder == TranscriptionEngineOrder.qwenPrimary;
  return List.unmodifiable([
    if (qwenReady && qwenFirst) LyricSpanEngine.qwen,
    if (whisperReady) LyricSpanEngine.whisper,
    if (qwenReady && !qwenFirst) LyricSpanEngine.qwen,
  ]);
}
