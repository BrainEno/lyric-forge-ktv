import '../features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import '../features/lyrics/presentation/lyric_editor_dependencies.dart';
import '../features/transcription/domain/services/asr_runtime_manager.dart';
import 'app_services.dart';

/// Builds what the lyric editor needs, including the forced-alignment runner.
///
/// The runner used to be constructed inside `_openProofreadV2`: it loaded the
/// saved transcription settings, resolved the hardware profile, inspected the
/// runtime components and only then called the native aligner — four service
/// lookups and three error messages buried in a dialog handler, where the only
/// way to test them was to open the editor on a machine with a real runtime.
///
/// It lives here because it is assembly: the editor asks for word-level timing
/// and gets either spans or an error it can show. The `qwenRuntime` +
/// `qwenAligner` readiness question stays exactly where it can be answered.
LyricEditorDependencies assembleLyricEditorDependencies(AppServices services) {
  return LyricEditorDependencies(
    projectRepository: services.projectRepository,
    playbackSession: services.playbackSessionService,
    audioPlayer: services.audioPlayerService,
    lyricFileExport: services.lyricFileExportService,
    lyricFileImport: services.lyricFileImportService,
    forcedAlignmentRunner: buildForcedAlignmentRunner(services),
  );
}

/// Adapts the native path to [ForcedAlignmentRunner].
///
/// Every failure is an exception with a message meant for the user: the
/// proofread flow surfaces it as the reason the run could not start, which is
/// more useful than a silent fall back to "no evidence".
ForcedAlignmentRunner buildForcedAlignmentRunner(AppServices services) {
  return ({
    required String audioPath,
    required String text,
    required String language,
    required Duration audioDuration,
  }) async {
    final savedConfig = await services.transcriptionSettingsStore.load();
    if (savedConfig == null) {
      throw Exception('尚未配置本地转写运行时。');
    }
    final resolved = await services.transcriptionProfileResolver.resolve(
      savedConfig,
    );
    final runtimeStatus = await services.asrRuntimeManager.inspect(
      resolved.config,
    );
    final runtimeReady = runtimeStatus.hasReadyComponents(const {
      AsrRuntimeComponent.qwenRuntime,
      AsrRuntimeComponent.qwenAligner,
    });
    if (!runtimeReady) {
      throw Exception('Qwen ForcedAligner 运行时未就绪；请先在转写设置中准备高质量运行环境。');
    }
    return services.qwenNativeTranscriptionService.alignReference(
      audioPath: audioPath,
      text: text,
      language: language,
      audioDuration: audioDuration,
      config: resolved.config,
    );
  };
}
