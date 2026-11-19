import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/navigation/app_chrome_controller.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_error_state.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/ktv_recording_session.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/repositories/local_media_metadata_repository.dart';
import '../../domain/services/audio_path_canonicalizer.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/audio_preview_service.dart';
import '../../domain/services/ktv_microphone_service.dart';
import '../../domain/services/ktv_recording_service.dart';
import '../../domain/services/ktv_take_history_store.dart';
import '../../domain/services/playback_lyrics_project_resolver.dart';
import '../../domain/services/playback_session_service.dart';
import '../playback_screen_dependencies.dart';
import '../widgets/fullscreen_ktv_interaction_surface.dart';
import '../widgets/fullscreen_ktv_lyric_stage.dart';
import '../widgets/global_playback_shortcuts.dart';
import '../widgets/ktv_microphone_sheet.dart';
import '../widgets/ktv_recording_toolbar.dart';
import '../widgets/ktv_take_history_sheet.dart';
import '../widgets/ktv_take_result_sheet.dart';
import '../widgets/seekable_progress_bar.dart';
import '../widgets/transport_bar.dart';

/// Immersive lyrics view backed by the app-scoped playback session, and the
/// only place a KTV take can be recorded, auditioned, exported or managed.
///
/// All nine collaborators arrive in one [ImmersiveKtvDependencies] bundle from
/// `lib/app/playback_assembly.dart`. That is deliberate: this screen used to
/// fall back to the app-wide locator per field, and the microphone/recording
/// half of it sat in a second, unreachable fullscreen view — which is how the
/// app ended up with recording code and no way to reach it.
class ImmersiveKtvScreen extends StatefulWidget {
  final String initialProjectId;

  /// Supplied by the routing table / the screen that opens fullscreen KTV.
  final ImmersiveKtvDependencies dependencies;

  const ImmersiveKtvScreen({
    super.key,
    required this.initialProjectId,
    required this.dependencies,
  });

  /// Shown in place of the lyrics when they could not be loaded.
  static const String errorTitle = '歌词加载失败';

  static const Key errorKey = ValueKey('immersive-ktv-error');
  static const Key titleKey = ValueKey('immersive-ktv-title');
  static const Key topScrimKey = ValueKey('immersive-ktv-top-scrim');
  static const Key bottomScrimKey = ValueKey('immersive-ktv-bottom-scrim');
  static const Key keyHintKey = ValueKey('immersive-ktv-key-hint');

  static const String exitTooltip = '退出全屏 KTV（Esc）';

  /// Opacity of the scrims at the screen edge; they fade to nothing towards
  /// the lyrics, so the controls stay readable over a bright karaoke line.
  static const double scrimAlpha = 0.72;

  @override
  State<ImmersiveKtvScreen> createState() => _ImmersiveKtvScreenState();
}

class _ImmersiveKtvScreenState extends State<ImmersiveKtvScreen> {
  late final ProjectRepository _projects;
  late final LocalMediaMetadataRepository _metadata;
  late final AudioPlayerService _audio;
  late final PlaybackSessionService _session;
  late final AudioPathCanonicalizer _pathCanonicalizer;
  late final KtvMicrophoneService _microphone;
  late final KtvRecordingService _recording;
  late final KtvTakeHistoryStore _takeHistory;
  late final AudioPreviewService _preview;
  StreamSubscription<PlaybackSessionState>? _sessionSub;
  ProjectManifest? _project;
  Object? _error;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    final dependencies = widget.dependencies;
    _projects = dependencies.projectRepository;
    _metadata = dependencies.metadataRepository;
    _audio = dependencies.audioPlayer;
    _session = dependencies.playbackSession;
    _pathCanonicalizer = dependencies.pathCanonicalizer;
    _microphone = dependencies.microphoneService;
    _recording = dependencies.recordingService;
    _takeHistory = dependencies.takeHistoryStore;
    _preview = dependencies.previewService;
    // App chrome is observed above the Navigator, so notifying it while this
    // route is mounting would ask an ancestor to rebuild during its build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppChromeController.enterImmersive();
    });
    unawaited(_loadProject(widget.initialProjectId));
    _sessionSub = _session.stateStream.listen(_syncProjectToPlayback);
  }

  Future<void> _loadProject(String projectId) async {
    final generation = ++_loadGeneration;
    try {
      final project = await _projects.getProjectById(projectId);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _project = project;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = error);
    }
  }

  Future<void> _syncProjectToPlayback(PlaybackSessionState state) async {
    final item = state.currentItem;
    if (item == null) return;
    final generation = ++_loadGeneration;
    try {
      final projectId = await resolvePlaybackLyricsProjectId(
        item: item,
        projectRepository: _projects,
        metadataRepository: _metadata,
        pathCanonicalizer: _pathCanonicalizer,
      );
      if (!mounted || generation != _loadGeneration) return;
      if (projectId == null) {
        setState(() {
          _project = null;
          _error = null;
        });
        return;
      }
      final project = await _projects.getProjectById(projectId);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _project = project;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = error);
    }
  }

  bool get _takeMutationLocked {
    final state = _recording.currentState;
    return state.isRecording || state.isExporting;
  }

  void _showTakeMutationLockedMessage() {
    if (!mounted) return;
    final state = _recording.currentState;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          state.isExporting
              ? KtvTakeHistorySheet.lockedExportMessage
              : KtvTakeHistorySheet.lockedRecordingMessage,
        ),
      ),
    );
  }

  Future<void> _toggleRecording() async {
    final project = _project;
    if (project == null) return;
    try {
      if (_recording.currentState.isRecording) {
        final completed = await _recording.stopRecording();
        if (!mounted || completed == null) return;
        await _showTakeResult(completed);
        return;
      }
      await _recording.startRecording(project);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('KTV 录音失败：$error')));
    }
  }

  Future<void> _showTakeResult(KtvRecordingSession session) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.bgElevated,
      builder: (context) => KtvTakeResultSheet(
        initialSession: session,
        recordingService: _recording,
        previewService: _preview,
      ),
    );
  }

  Future<void> _openTakeHistory() async {
    final project = _project;
    if (project == null) return;
    if (_takeMutationLocked) {
      _showTakeMutationLockedMessage();
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.bgElevated,
      builder: (context) => KtvTakeHistorySheet(
        project: project,
        takeHistoryStore: _takeHistory,
        recordingService: _recording,
        previewService: _preview,
      ),
    );
  }

  Future<void> _openMicrophoneControls() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.bgElevated,
      builder: (context) => KtvMicrophoneSheet(
        microphoneService: _microphone,
        audioService: _audio,
        recordingLocked: _recording.currentState.isRecording,
      ),
    );
  }

  Future<void> _shutdownKtvAudio() async {
    if (_recording.currentState.isRecording) {
      await _recording.stopRecording();
    }
    await _microphone.stopMonitoring();
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    unawaited(_shutdownKtvAudio());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppChromeController.exitImmersive();
    });
    super.dispose();
  }

  /// Reloads the lyrics of the song that is playing, or of the project the
  /// screen was opened with when nothing plays.
  void _retryLoad() {
    setState(() => _error = null);
    final state = _session.currentState;
    if (state.currentItem != null) {
      unawaited(_syncProjectToPlayback(state));
    } else {
      unawaited(_loadProject(widget.initialProjectId));
    }
  }

  @override
  Widget build(BuildContext context) => FullscreenKtvInteractionSurface(
    onExit: () => Navigator.maybePop(context),
    onCommand: (command) => GlobalPlaybackShortcuts.run(command, _session),
    builder: (context, controlsVisible) => Material(
      color: AppColors.pureBlack,
      child: SafeArea(
        child: StreamBuilder<PlaybackSessionState>(
          stream: _session.stateStream,
          initialData: _session.currentState,
          builder: (context, sessionSnapshot) => StreamBuilder<PlaybackState>(
            stream: _audio.stateStream,
            initialData: _audio.currentState,
            builder: (context, playbackSnapshot) {
              final session = sessionSnapshot.data ?? _session.currentState;
              final playback = playbackSnapshot.data ?? _audio.currentState;
              return Stack(
                children: [
                  Positioned.fill(
                    child: _error == null
                        ? FullscreenKtvLyricStage(
                            document: _project?.lyricDocument,
                            position: playback.position,
                            isPlaying: playback.isPlaying,
                          )
                        : AppErrorState(
                            key: ImmersiveKtvScreen.errorKey,
                            title: ImmersiveKtvScreen.errorTitle,
                            message: '$_error',
                            onRetry: _retryLoad,
                          ),
                  ),
                  // Above the lyrics and outside the fading chrome: a running
                  // take must stay visible while the controls are hidden.
                  Positioned(
                    top: AppSpacing.md,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: KtvRecordingIndicator(
                        recordingService: _recording,
                      ),
                    ),
                  ),
                  _ControlLayer(
                    visible: controlsVisible,
                    title:
                        _project?.name ?? session.currentItem?.title ?? 'KTV',
                    subtitle: session.currentItem?.artist,
                    playback: playback,
                    canPrevious: session.canSkipPrevious,
                    canNext: session.canSkipNext,
                    onExit: () => Navigator.maybePop(context),
                    onSeek: _session.seek,
                    onPlayPause: _session.togglePlayPause,
                    onPrevious: _session.skipPrevious,
                    onNext: _session.skipNext,
                    toolbar: KtvRecordingToolbar(
                      enabled: _project != null,
                      recordingService: _recording,
                      microphoneService: _microphone,
                      onOpenHistory: () => unawaited(_openTakeHistory()),
                      onToggleRecording: () => unawaited(_toggleRecording()),
                      onOpenMicrophone: () =>
                          unawaited(_openMicrophoneControls()),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _ControlLayer extends StatelessWidget {
  final bool visible;
  final String title;
  final String? subtitle;
  final PlaybackState playback;
  final bool canPrevious;
  final bool canNext;
  final VoidCallback onExit;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  /// Recording/history/microphone entry points, supplied by the screen.
  final Widget toolbar;

  const _ControlLayer({
    required this.visible,
    required this.title,
    required this.playback,
    required this.canPrevious,
    required this.canNext,
    required this.onExit,
    required this.onSeek,
    required this.onPlayPause,
    required this.onPrevious,
    required this.onNext,
    required this.toolbar,
    this.subtitle,
  });

  /// Desktop platforms, where a keyboard is a safe assumption.
  static const Set<TargetPlatform> _keyboardPlatforms = {
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  };

  static bool get _hasKeyboard =>
      _keyboardPlatforms.contains(defaultTargetPlatform);

  static BoxDecoration _scrim({required bool top}) => BoxDecoration(
    gradient: LinearGradient(
      begin: top ? Alignment.topCenter : Alignment.bottomCenter,
      end: top ? Alignment.bottomCenter : Alignment.topCenter,
      colors: [
        AppColors.pureBlack.withValues(alpha: ImmersiveKtvScreen.scrimAlpha),
        AppColors.pureBlack.withValues(alpha: 0),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final artist = subtitle?.trim() ?? '';
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Column(
          children: [
            _Scrimmed(
              scrimKey: ImmersiveKtvScreen.topScrimKey,
              decoration: _scrim(top: true),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.xl,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            key: ImmersiveKtvScreen.titleKey,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleLarge?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (artist.isNotEmpty)
                            Text(
                              artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    IconButton(
                      tooltip: ImmersiveKtvScreen.exitTooltip,
                      onPressed: onExit,
                      icon: const Icon(Icons.fullscreen_exit_rounded),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            _Scrimmed(
              scrimKey: ImmersiveKtvScreen.bottomScrimKey,
              decoration: _scrim(top: false),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xxl,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Column(
                  children: [
                    SeekableProgressBar(state: playback, onSeek: onSeek),
                    TransportBar(
                      compact: true,
                      isPlaying: playback.isPlaying,
                      isBusy: playback.isLoading || playback.isBuffering,
                      onPlayPause: onPlayPause,
                      onPrevious: canPrevious ? onPrevious : null,
                      onNext: canNext ? onNext : null,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    toolbar,
                    if (_hasKeyboard) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        FullscreenKtvInteractionSurface.keyHint(),
                        key: ImmersiveKtvScreen.keyHintKey,
                        textAlign: TextAlign.center,
                        style: text.labelSmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [child] over a gradient that fills the same area but never takes a tap,
/// so a control group's scrim does not hide what lies below it (the retry
/// button of the error state, the lyrics) from the pointer.
class _Scrimmed extends StatelessWidget {
  final Key scrimKey;
  final Decoration decoration;
  final Widget child;

  const _Scrimmed({
    required this.scrimKey,
    required this.decoration,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(key: scrimKey, decoration: decoration),
          ),
        ),
        child,
      ],
    );
  }
}
