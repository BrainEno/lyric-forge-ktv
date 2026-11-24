import '../../../core/diagnostics/app_diagnostics.dart';
import '../../../core/theme/app_appearance.dart';
import '../../player/domain/services/library_folder_settings.dart';
import '../../transcription/domain/services/asr_end_to_end_smoke_test_service.dart';
import '../../transcription/presentation/transcription_screen_dependencies.dart';

/// App-scoped collaborators used by the settings screen and its ASR sections.
class SettingsScreenDependencies {
  final AsrRuntimeSetupDependencies asrRuntimeSetupDependencies;
  final AsrEndToEndSmokeTestService smokeTestService;

  /// Logs, crash records, timings and the exportable diagnostics report.
  final AppDiagnostics diagnostics;

  /// The 曲库目录 setting (decision D-033); null hides its card.
  final LibraryFolderSettings? libraryFolder;

  /// Pairs lyric files in the library folder now and describes the result.
  final Future<String> Function()? findLibraryLyrics;

  /// Counts the songs whose lyrics the library paired on its own (D-034).
  final Future<int> Function()? countAutoPairedLyrics;

  /// The theme choice of 外观 (decision D-042); null hides the card.
  final AppAppearanceController? appearance;

  /// Puts the dashboard's 开始使用 checklist back (D-070); null hides the
  /// card that offers it.
  final Future<void> Function()? showGettingStarted;

  const SettingsScreenDependencies({
    required this.asrRuntimeSetupDependencies,
    required this.smokeTestService,
    required this.diagnostics,
    this.libraryFolder,
    this.findLibraryLyrics,
    this.countAutoPairedLyrics,
    this.appearance,
    this.showGettingStarted,
  });
}
