import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/navigation/app_chrome_controller.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
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
import '../widgets/ktv_microphone_sheet.dart';
import '../widgets/ktv_recording_toolbar.dart';
import '../widgets/ktv_take_history_sheet.dart';
import '../widgets/ktv_take_result_sheet.dart';
import '../widgets/seekable_progress_bar.dart';

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
    AppChromeController.enterImmersive();
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
    AppChromeController.exitImmersive();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FullscreenKtvInteractionSurface(
    onExit: () => Navigator.maybePop(context),
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
                          )
                        : Center(
                            child: Text(
                              '歌词加载失败：$_error',
                              style: const TextStyle(color: AppColors.error),
                            ),
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
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: '退出全屏 KTV',
                    onPressed: onExit,
                    icon: const Icon(Icons.fullscreen_exit_rounded),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                children: [
                  SeekableProgressBar(state: playback, onSeek: onSeek),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: canPrevious ? onPrevious : null,
                        icon: const Icon(Icons.skip_previous_rounded),
                      ),
                      IconButton.filled(
                        onPressed: playback.isLoading || playback.isBuffering
                            ? null
                            : onPlayPause,
                        icon: Icon(
                          playback.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                      IconButton(
                        onPressed: canNext ? onNext : null,
                        icon: const Icon(Icons.skip_next_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  toolbar,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
