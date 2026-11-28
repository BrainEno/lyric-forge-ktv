import '../features/import/presentation/transcription_import_dependencies.dart';
import '../features/lyrics/domain/models/lyric_review_queue.dart';
import '../features/player/domain/services/playback_session_service.dart';
import '../features/project/data/services/file_project_accompaniment_importer.dart';
import '../features/project/domain/models/lyric_review_overview.dart';
import '../features/project/domain/models/project_manifest.dart';
import '../features/project/domain/services/project_deletion_service.dart';
import '../features/project/presentation/project_detail_dependencies.dart';
import '../features/project/presentation/project_list_dependencies.dart';
import 'app_services.dart';
import 'transcription_assembly.dart';

/// Builds dependencies for screens outside the playback and library surfaces.
ProjectDetailDependencies assembleProjectDetailDependencies(
  AppServices services,
) {
  return ProjectDetailDependencies(
    projectRepository: services.projectRepository,
    accompanimentImporter: FileProjectAccompanimentImporter(
      projectRepository: services.projectRepository,
    ),
    vocalImporter: FileProjectAccompanimentImporter(
      projectRepository: services.projectRepository,
    ),
    playbackSourceUpdater:
        services.playbackSessionService is ActiveProjectPlaybackSourceUpdater
        ? services.playbackSessionService as ActiveProjectPlaybackSourceUpdater
        : null,
    transcriptionWorkflow: services.createProjectTranscriptionWorkflow(),
    asrRuntimeSetupDependencies: assembleAsrRuntimeSetupDependencies(services),
    deletionService: assembleProjectDeletionService(services),
    reviewCounter: countProjectLyricReview,
  );
}

/// The lyric editor's 建议复核 counts for the project page (D-069), with the
/// audio length the editor uses so both pages report the same number.
ProjectLyricReviewOverview countProjectLyricReview(ProjectManifest project) {
  final document = project.lyricDocument;
  if (document == null) {
    return const ProjectLyricReviewOverview(
      suggested: 0,
      mustCheck: 0,
      reviewed: 0,
    );
  }
  final queue = LyricReviewQueue.build(
    document,
    audioDuration: project.audioAsset?.duration,
  );
  return ProjectLyricReviewOverview(
    suggested: queue.needsReviewCount,
    mustCheck: queue.mustCheckCount,
    reviewed: queue.reviewedLines,
  );
}

/// Deletes projects into 最近删除 (D-063, D-064).
ProjectDeletionService assembleProjectDeletionService(AppServices services) =>
    services.projectDeletionService;

ProjectListDependencies assembleProjectListDependencies(AppServices services) {
  return ProjectListDependencies(
    projectRepository: services.projectRepository,
    deletionService: assembleProjectDeletionService(services),
    canonicalizeAudioPath: services.audioPathCanonicalizer.canonicalize,
  );
}

TranscriptionImportDependencies assembleTranscriptionImportDependencies(
  AppServices services,
) {
  return TranscriptionImportDependencies(
    audioLibraryImportService: services.audioLibraryImportService,
    transcriptionQueue: services.transcriptionQueue,
    asrRuntimeSetupDependencies: assembleAsrRuntimeSetupDependencies(services),
  );
}
