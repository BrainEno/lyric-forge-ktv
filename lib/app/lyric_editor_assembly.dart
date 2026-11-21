import 'dart:io';

import '../features/lyrics/data/services/online_lyrics/online_lyric_http.dart';
import '../features/lyrics/data/services/online_lyrics/online_lyric_sources.dart';
import '../features/lyrics/domain/online/online_lyric_candidate.dart';
import '../features/lyrics/domain/online/song_lyrics_lookup.dart';
import '../features/lyrics/domain/proofreading/forced_alignment_proofread_service.dart';
import '../features/lyrics/presentation/lyric_editor_dependencies.dart';
import '../features/transcription/data/services/asr_download_http_client_factory.dart';
import '../features/transcription/data/services/project_proofread_evidence_loader.dart';
import '../features/transcription/data/services/project_span_recognition_service.dart';
import '../features/transcription/data/services/reference_alignment_audio_guard.dart';
import '../features/transcription/domain/services/asr_resource_coordinator.dart';
import '../features/transcription/domain/services/asr_runtime_manager.dart';
import 'app_services.dart';

/// Builds what the lyric editor needs, including the forced-alignment runner.
///
/// The runner used to be constructed inside `_openSmartProofread`: it loaded
/// the saved transcription settings, resolved the hardware profile, inspected
/// the runtime components and only then called the native aligner — four
/// service lookups and three error messages buried in a dialog handler, where
/// the only way to test them was to open the editor on a machine with a real
/// runtime.
///
/// It lives here because it is assembly: the editor asks for word-level timing
/// and gets either spans or an error it can show. The `qwenRuntime` +
/// `qwenAligner` readiness question stays exactly where it can be answered.
LyricEditorDependencies assembleLyricEditorDependencies(AppServices services) {
  final evidenceLoader = VerifiedProjectProofreadEvidenceLoader(
    projects: services.projectRepository,
  );
  return LyricEditorDependencies(
    projectRepository: services.projectRepository,
    playbackSession: services.playbackSessionService,
    audioPlayer: services.audioPlayerService,
    lyricFileExport: services.lyricFileExportService,
    lyricFileImport: services.lyricFileImportService,
    forcedAlignmentRunner: buildForcedAlignmentRunner(services),
    referenceAlignmentAudioGuard: ProjectReferenceAlignmentAudioGuard(
      projects: services.projectRepository,
    ),
    projectProofreadEvidenceLoader: evidenceLoader.load,
    projectProofreadEvidencePreviewer: evidenceLoader.preview,
    spanRecognizer: ProjectSpanRecognitionService(
      projects: services.projectRepository,
      settings: services.transcriptionSettingsStore,
      profiles: services.transcriptionProfileResolver,
      runtime: services.asrRuntimeManager,
      resources: services.asrResourceCoordinator,
      // Reuses a Qwen model server still loaded from a full recognition.
      sharedQwen: services.qwenNativeTranscriptionService,
      // The span service already holds the shared lease for its whole run.
      alignClip: _alignWithReadyRuntime(services),
    ),
    onlineLyricSearch: buildOnlineLyricSearch(),
  );
}

/// The lyric sites 一键校对 searches. Requests honour the same system or
/// environment proxy as the model downloads, so a machine that can download
/// models can also reach the lyric sites.
OnlineLyricSearchService buildOnlineLyricSearch() {
  final proxies = AsrDownloadHttpClientFactory();
  final http = IoOnlineLyricHttp(
    createClient: () async {
      HttpClient client;
      try {
        client = await proxies.create();
      } on Object {
        // An unreadable proxy setting must not block the search; a direct
        // connection still works on most networks.
        client = HttpClient();
      }
      return client..connectionTimeout = const Duration(seconds: 8);
    },
  );
  return OnlineLyricSearchService(
    sources: [
      NeteaseLyricSource(get: http.get),
      KugouLyricSource(get: http.get),
      LrclibLyricSource(get: http.get),
    ],
  );
}

/// 联网获取歌词 for a song that has none yet (D-054): the same sites and
/// proxy handling as 一键校对, read with the app's own lyric parser.
SongLyricsLookup buildSongLyricsLookup(AppServices services) {
  return SongLyricsLookup(
    search: buildOnlineLyricSearch(),
    importer: services.lyricFileImportService,
  );
}

/// Adapts the native path to [ForcedAlignmentRunner].
///
/// A busy resource is reported separately so the user can retry. Other
/// failures retain the proofreading service's unavailable-evidence fallback.
ForcedAlignmentRunner buildForcedAlignmentRunner(AppServices services) {
  return coordinateForcedAlignmentRunner(
    resources: services.asrResourceCoordinator,
    delegate: _alignWithReadyRuntime(services),
  );
}

/// The native alignment call with its readiness checks, without taking the
/// shared resource lease; callers own the lease.
ForcedAlignmentRunner _alignWithReadyRuntime(AppServices services) {
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

/// Holds the shared resource through preflight, native alignment and cleanup.
/// The delegate is not called when busy and is not cancelled by this wrapper.
ForcedAlignmentRunner coordinateForcedAlignmentRunner({
  required AsrResourceCoordinator resources,
  required ForcedAlignmentRunner delegate,
}) {
  return ({
    required String audioPath,
    required String text,
    required String language,
    required Duration audioDuration,
  }) async {
    final lease = resources.tryAcquire(AsrResourceUse.alignment);
    if (lease == null) throw const ForcedAlignmentResourceBusyException();
    try {
      return await delegate(
        audioPath: audioPath,
        text: text,
        language: language,
        audioDuration: audioDuration,
      );
    } finally {
      lease.release();
    }
  };
}
