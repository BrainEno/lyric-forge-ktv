import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/app_chrome_controller.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/ktv_backing_mode.dart';
import '../../domain/models/ktv_microphone_state.dart';
import '../../domain/models/ktv_recording_session.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/ktv_microphone_service.dart';
import '../../domain/services/ktv_recording_service.dart';
import '../../domain/services/playback_session_service.dart';

class PlayerScreen extends StatefulWidget {
  final String projectId;

  const PlayerScreen({
    super.key,
    required this.projectId,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final ProjectRepository _repository;
  late final AudioPlayerService _audioService;
  late final PlaybackSessionService _playbackSession;
  late Future<ProjectManifest?> _projectFuture;
  late String _activeProjectId;
  StreamSubscription<PlaybackSessionState>? _sessionSubscription;

  @override
  void initState() {
    super.initState();
    _repository = ServiceLocatorGlobal.I.projectRepository;
    _audioService = ServiceLocatorGlobal.I.audioPlayerService;
    _playbackSession = ServiceLocatorGlobal.I.playbackSessionService;
    _activeProjectId = widget.projectId;
    _loadProject(_activeProjectId);
    _sessionSubscription =
        _playbackSession.stateStream.listen(_handleSessionChange);
  }

  void _loadProject(String projectId) {
    _projectFuture = _repository.getProjectById(projectId);
  }

  void _handleSessionChange(PlaybackSessionState state) {
    final projectId = state.currentItem?.projectId;
    if (!mounted || projectId == null || projectId == _activeProjectId) return;

    setState(() {
      _activeProjectId = projectId;
      _loadProject(projectId);
    });
  }

  Future<void> _openLyricEditor(ProjectManifest project) async {
    await Navigator.pushNamed(
      context,
      Routes.lyricEditorPath(project.id),
    );
    if (!mounted || _activeProjectId != project.id) return;
    setState(() => _loadProject(project.id));
  }

  Future<void> _initializeAudio(ProjectManifest project) async {
    final audioAsset = project.audioAsset;
    if (audioAsset == null) return;

    if (_playbackSession.currentState.currentItem?.projectId == project.id) {
      return;
    }

    try {
      await _playbackSession.playItem(
        PlaybackItem(
          id: 'project:${project.id}',
          title: project.name,
          artist: project.artist,
          projectId: project.id,
          artworkPath: audioAsset.thumbnailPath,
          hasLyrics: project.hasLyrics,
          audioAsset: audioAsset,
          preferredSource: audioAsset.defaultSource,
        ),
      );
    } catch (_) {
      // Shared playback state surfaces loading/playback errors in the UI.
    }
  }

  Future<void> _playPause() => _playbackSession.togglePlayPause();

  Future<void> _seek(Duration position) => _playbackSession.seek(position);

  Future<void> _switchSource(AudioSourceType source) async {
    try {
      await _audioService.switchSource(source);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法切换到该音源：$error')),
      );
    }
  }

  Future<void> _skipPrevious() => _playbackSession.skipPrevious();

  Future<void> _skipNext() => _playbackSession.skipNext();

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProjectManifest?>(
      future: _projectFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingState();
        }

        if (snapshot.hasError || snapshot.data == null) {
          return _ErrorState(
            onRetry: () => setState(() => _loadProject(_activeProjectId)),
          );
        }

        final project = snapshot.data!;
        return _PlayerContent(
          key: ValueKey('player_${project.id}'),
          project: project,
          repository: _repository,
          audioService: _audioService,
          playbackSession: _playbackSession,
          onInitialize: () => _initializeAudio(project),
          onOpenLyricEditor: () => _openLyricEditor(project),
          onPlayPause: _playPause,
          onSeek: _seek,
          onSwitchSource: _switchSource,
          onSkipPrevious: _skipPrevious,
          onSkipNext: _skipNext,
        );
      },
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(spec.pageGutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: AppColors.error),
              const SizedBox(height: AppSpacing.md),
              const Text('加载播放器失败'),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  minimumSize: Size.fromHeight(spec.minimumInteractiveExtent),
                ),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerContent extends StatefulWidget {
  final ProjectManifest project;
  final ProjectRepository repository;
  final AudioPlayerService audioService;
  final PlaybackSessionService playbackSession;
  final VoidCallback onInitialize;
  final Future<void> Function() onOpenLyricEditor;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<AudioSourceType> onSwitchSource;
  final VoidCallback onSkipPrevious;
  final VoidCallback onSkipNext;

  const _PlayerContent({
    super.key,
    required this.project,
    required this.repository,
    required this.audioService,
    required this.playbackSession,
    required this.onInitialize,
    required this.onOpenLyricEditor,
    required this.onPlayPause,
    required this.onSeek,
    required this.onSwitchSource,
    required this.onSkipPrevious,
    required this.onSkipNext,
  });

  @override
  State<_PlayerContent> createState() => _PlayerContentState();
}

class _PlayerContentState extends State<_PlayerContent> {
  bool _ktvMode = false;

  @override
  void initState() {
    super.initState();
    widget.onInitialize();
  }

  void _seekToLine(LyricLine line) {
    widget.onSeek(_effectiveLyricStart(widget.project.lyricDocument, line));
  }

  Future<void> _enterKtv() async {
    final document = widget.project.lyricDocument;
    final audioAsset = widget.project.audioAsset;
    if (document == null || document.lines.isEmpty || audioAsset == null) return;

    final selectedMode = await showModalBottomSheet<KtvBackingMode>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: AppColors.bgElevated,
      builder: (context) => _KtvEntrySheet(
        audioAsset: audioAsset,
        currentSource: widget.audioService.currentState.currentSource,
      ),
    );
    if (!mounted || selectedMode == null) return;

    try {
      if (widget.audioService.currentState.currentSource != selectedMode.source) {
        await widget.audioService.switchSource(selectedMode.source);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法进入 KTV：$error')),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _ktvMode = true);
    await _openFullScreenKtv();
  }

  Future<void> _openFullScreenKtv() async {
    final document = widget.project.lyricDocument;
    if (document == null || document.lines.isEmpty) return;

    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: _FullScreenKtvView(
              initialProject: widget.project,
              repository: widget.repository,
              audioService: widget.audioService,
              playbackSession: widget.playbackSession,
              onPlayPause: widget.onPlayPause,
              onSeek: widget.onSeek,
              onSwitchSource: widget.onSwitchSource,
              onSkipPrevious: widget.onSkipPrevious,
              onSkipNext: widget.onSkipNext,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final document = widget.project.lyricDocument;
    final lyrics = document?.lines ?? const <LyricLine>[];

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        titleSpacing: AppSpacing.sm,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.project.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (!spec.isShort)
              Text(
                widget.project.artist?.trim().isNotEmpty == true
                    ? widget.project.artist!
                    : '本地工程',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
              ),
          ],
        ),
        actions: [
          SizedBox(
            width: spec.minimumInteractiveExtent,
            height: spec.minimumInteractiveExtent,
            child: IconButton(
              tooltip: '工程详情',
              onPressed: () => Navigator.pushNamed(
                context,
                Routes.projectDetailPath(widget.project.id),
              ),
              icon: const Icon(Icons.info_outline_rounded),
            ),
          ),
          if (lyrics.isNotEmpty)
            SizedBox(
              width: spec.minimumInteractiveExtent,
              height: spec.minimumInteractiveExtent,
              child: IconButton.filledTonal(
                tooltip: '进入 KTV',
                onPressed: _enterKtv,
                icon: const Icon(Icons.mic_rounded),
              ),
            ),
          SizedBox(
            width: spec.minimumInteractiveExtent,
            height: spec.minimumInteractiveExtent,
            child: IconButton(
              tooltip: '校对歌词',
              onPressed: widget.onOpenLyricEditor,
              icon: const Icon(Icons.edit_rounded),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<PlaybackSessionState>(
          stream: widget.playbackSession.stateStream,
          initialData: widget.playbackSession.currentState,
          builder: (context, sessionSnapshot) {
            final session =
                sessionSnapshot.data ?? widget.playbackSession.currentState;
            return StreamBuilder<PlaybackState>(
              stream: widget.audioService.stateStream,
              initialData: widget.audioService.currentState,
              builder: (context, playbackSnapshot) {
                final playback =
                    playbackSnapshot.data ?? const PlaybackState.idle();
                final currentLyricIndex = _currentLyricIndex(
                  document,
                  playback.position,
                );

                return _PlayerWorkspace(
                  project: widget.project,
                  document: document,
                  playback: playback,
                  session: session,
                  ktvMode: _ktvMode,
                  currentLyricIndex: currentLyricIndex,
                  onPlayPause: widget.onPlayPause,
                  onSeek: widget.onSeek,
                  onLyricTap: _seekToLine,
                  onSwitchSource: widget.onSwitchSource,
                  onSkipPrevious: widget.onSkipPrevious,
                  onSkipNext: widget.onSkipNext,
                  onModeChanged: (ktvMode) =>
                      setState(() => _ktvMode = ktvMode),
                  onOpenFullScreenKtv:
                      lyrics.isEmpty ? null : _openFullScreenKtv,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _PlayerWorkspace extends StatelessWidget {
  final ProjectManifest project;
  final LyricDocument? document;
  final PlaybackState playback;
  final PlaybackSessionState session;
  final bool ktvMode;
  final int? currentLyricIndex;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<LyricLine> onLyricTap;
  final ValueChanged<AudioSourceType> onSwitchSource;
  final VoidCallback onSkipPrevious;
  final VoidCallback onSkipNext;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback? onOpenFullScreenKtv;

  const _PlayerWorkspace({
    required this.project,
    required this.document,
    required this.playback,
    required this.session,
    required this.ktvMode,
    required this.currentLyricIndex,
    required this.onPlayPause,
    required this.onSeek,
    required this.onLyricTap,
    required this.onSwitchSource,
    required this.onSkipPrevious,
    required this.onSkipNext,
    required this.onModeChanged,
    required this.onOpenFullScreenKtv,
  });

  @override
  Widget build(BuildContext context) {
    final lyrics = document?.lines ?? const <LyricLine>[];
    final availableSources = project.audioAsset?.availableSources ??
        const <AudioSourceType>[];

    return LayoutBuilder(
      builder: (context, constraints) {
        final spec = AppResponsive.fromConstraints(constraints);
        if (spec.supportsTwoPane) {
          return Row(
            children: [
              SizedBox(
                width: spec.sidePanelWidth,
                child: _TransportPane(
                  project: project,
                  playback: playback,
                  session: session,
                  availableSources: availableSources,
                  ktvMode: ktvMode,
                  onPlayPause: onPlayPause,
                  onSeek: onSeek,
                  onSwitchSource: onSwitchSource,
                  onSkipPrevious: onSkipPrevious,
                  onSkipNext: onSkipNext,
                  onModeChanged: onModeChanged,
                  onOpenFullScreenKtv: onOpenFullScreenKtv,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _LyricsPane(
                  lyrics: lyrics,
                  ktvMode: ktvMode,
                  currentIndex: currentLyricIndex,
                  onLyricTap: onLyricTap,
                  onOpenFullScreenKtv: onOpenFullScreenKtv,
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            _CompactTransportHeader(
              project: project,
              playback: playback,
              session: session,
              availableSources: availableSources,
              ktvMode: ktvMode,
              onPlayPause: onPlayPause,
              onSeek: onSeek,
              onSwitchSource: onSwitchSource,
              onSkipPrevious: onSkipPrevious,
              onSkipNext: onSkipNext,
              onModeChanged: onModeChanged,
              onOpenFullScreenKtv: onOpenFullScreenKtv,
            ),
            const Divider(height: 1),
            Expanded(
              child: _LyricsPane(
                lyrics: lyrics,
                ktvMode: ktvMode,
                currentIndex: currentLyricIndex,
                onLyricTap: onLyricTap,
                onOpenFullScreenKtv: onOpenFullScreenKtv,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TransportPane extends StatelessWidget {
  final ProjectManifest project;
  final PlaybackState playback;
  final PlaybackSessionState session;
  final List<AudioSourceType> availableSources;
  final bool ktvMode;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<AudioSourceType> onSwitchSource;
  final VoidCallback onSkipPrevious;
  final VoidCallback onSkipNext;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback? onOpenFullScreenKtv;

  const _TransportPane({
    required this.project,
    required this.playback,
    required this.session,
    required this.availableSources,
    required this.ktvMode,
    required this.onPlayPause,
    required this.onSeek,
    required this.onSwitchSource,
    required this.onSkipPrevious,
    required this.onSkipNext,
    required this.onModeChanged,
    required this.onOpenFullScreenKtv,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final padding = spec.pageGutter.clamp(16, 28).toDouble();
    return ListView(
      padding: EdgeInsets.all(padding),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: spec.playerArtworkMaxExtent.clamp(220, 320).toDouble(),
            ),
            child: _ProjectArtwork(
              path: project.audioAsset?.thumbnailPath,
              loading: playback.isLoading,
            ),
          ),
        ),
        SizedBox(height: spec.sectionGap),
        _SongIdentity(project: project),
        if (playback.error != null) ...[
          const SizedBox(height: AppSpacing.md),
          _PlaybackError(message: playback.error!),
        ],
        SizedBox(height: spec.sectionGap),
        _ProgressBar(state: playback, onSeek: onSeek),
        const SizedBox(height: AppSpacing.md),
        _PlaybackControls(
          isPlaying: playback.isPlaying,
          isBuffering: playback.isBuffering,
          canPrevious: session.currentItem != null,
          canNext: session.canSkipNext,
          onPrevious: onSkipPrevious,
          onPlayPause: onPlayPause,
          onNext: onSkipNext,
        ),
        if (availableSources.length > 1) ...[
          const SizedBox(height: AppSpacing.md),
          _AudioSourceSelector(
            availableSources: availableSources,
            currentSource: playback.currentSource,
            onSourceChanged: onSwitchSource,
          ),
        ],
        SizedBox(height: spec.sectionGap),
        _PlayerModeControls(
          ktvMode: ktvMode,
          hasLyrics: project.hasLyrics,
          onModeChanged: onModeChanged,
          onOpenFullScreenKtv: onOpenFullScreenKtv,
        ),
      ],
    );
  }
}

class _CompactTransportHeader extends StatelessWidget {
  final ProjectManifest project;
  final PlaybackState playback;
  final PlaybackSessionState session;
  final List<AudioSourceType> availableSources;
  final bool ktvMode;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<AudioSourceType> onSwitchSource;
  final VoidCallback onSkipPrevious;
  final VoidCallback onSkipNext;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback? onOpenFullScreenKtv;

  const _CompactTransportHeader({
    required this.project,
    required this.playback,
    required this.session,
    required this.availableSources,
    required this.ktvMode,
    required this.onPlayPause,
    required this.onSeek,
    required this.onSwitchSource,
    required this.onSkipPrevious,
    required this.onSkipNext,
    required this.onModeChanged,
    required this.onOpenFullScreenKtv,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final padding = spec.isCompact ? 12.0 : 16.0;

    if (spec.isShort) {
      return Padding(
        padding: EdgeInsets.fromLTRB(padding, 6, padding, 8),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: _ProjectArtwork(
                    path: project.audioAsset?.thumbnailPath,
                    loading: playback.isLoading,
                    compact: true,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: _SongIdentity(project: project, compact: true)),
                const SizedBox(width: AppSpacing.xs),
                _PlaybackControls(
                  isPlaying: playback.isPlaying,
                  isBuffering: playback.isBuffering,
                  canPrevious: session.currentItem != null,
                  canNext: session.canSkipNext,
                  onPrevious: onSkipPrevious,
                  onPlayPause: onPlayPause,
                  onNext: onSkipNext,
                  compact: true,
                ),
              ],
            ),
            if (playback.error != null) ...[
              const SizedBox(height: 6),
              _PlaybackError(message: playback.error!),
            ],
            _ProgressBar(state: playback, onSeek: onSeek, compact: true),
            const SizedBox(height: 2),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (availableSources.length > 1) ...[
                    _AudioSourceSelector(
                      availableSources: availableSources,
                      currentSource: playback.currentSource,
                      onSourceChanged: onSwitchSource,
                      compact: true,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  _PlayerModeControls(
                    ktvMode: ktvMode,
                    hasLyrics: project.hasLyrics,
                    onModeChanged: onModeChanged,
                    onOpenFullScreenKtv: onOpenFullScreenKtv,
                    compact: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.all(padding),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: spec.isCompact ? 56 : 64,
                height: spec.isCompact ? 56 : 64,
                child: _ProjectArtwork(
                  path: project.audioAsset?.thumbnailPath,
                  loading: playback.isLoading,
                  compact: true,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _SongIdentity(project: project, compact: true)),
            ],
          ),
          if (playback.error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _PlaybackError(message: playback.error!),
          ],
          const SizedBox(height: AppSpacing.sm),
          _ProgressBar(state: playback, onSeek: onSeek, compact: true),
          const SizedBox(height: AppSpacing.xs),
          _PlaybackControls(
            isPlaying: playback.isPlaying,
            isBuffering: playback.isBuffering,
            canPrevious: session.currentItem != null,
            canNext: session.canSkipNext,
            onPrevious: onSkipPrevious,
            onPlayPause: onPlayPause,
            onNext: onSkipNext,
            compact: true,
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (availableSources.length > 1)
                _AudioSourceSelector(
                  availableSources: availableSources,
                  currentSource: playback.currentSource,
                  onSourceChanged: onSwitchSource,
                  compact: true,
                ),
              _PlayerModeControls(
                ktvMode: ktvMode,
                hasLyrics: project.hasLyrics,
                onModeChanged: onModeChanged,
                onOpenFullScreenKtv: onOpenFullScreenKtv,
                compact: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LyricsPane extends StatelessWidget {
  final List<LyricLine> lyrics;
  final bool ktvMode;
  final int? currentIndex;
  final ValueChanged<LyricLine> onLyricTap;
  final VoidCallback? onOpenFullScreenKtv;

  const _LyricsPane({
    required this.lyrics,
    required this.ktvMode,
    required this.currentIndex,
    required this.onLyricTap,
    required this.onOpenFullScreenKtv,
  });

  @override
  Widget build(BuildContext context) {
    if (lyrics.isEmpty) return const _NoLyricsState();
    final spec = AppResponsive.of(context);
    final gutter = spec.pageGutter.clamp(12, 28).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            gutter,
            spec.isShort ? 6 : AppSpacing.md,
            gutter,
            spec.isShort ? 4 : AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  ktvMode ? 'KTV 歌词' : '同步歌词',
                  style: (spec.isCompact || spec.isShort
                          ? Theme.of(context).textTheme.titleMedium
                          : Theme.of(context).textTheme.titleLarge)
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (ktvMode && onOpenFullScreenKtv != null)
                spec.isCompact
                    ? IconButton(
                        tooltip: '全屏 KTV',
                        onPressed: onOpenFullScreenKtv,
                        icon: const Icon(Icons.fullscreen_rounded),
                      )
                    : TextButton.icon(
                        onPressed: onOpenFullScreenKtv,
                        icon: const Icon(Icons.fullscreen_rounded),
                        label: const Text('全屏'),
                      ),
            ],
          ),
        ),
        Expanded(
          child: ktvMode
              ? _KtvFocusLyrics(
                  lyrics: lyrics,
                  currentIndex: currentIndex,
                  onLyricTap: onLyricTap,
                )
              : _ScrollableLyrics(
                  lyrics: lyrics,
                  currentIndex: currentIndex,
                  onLyricTap: onLyricTap,
                ),
        ),
      ],
    );
  }
}

class _ScrollableLyrics extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int? currentIndex;
  final ValueChanged<LyricLine> onLyricTap;

  const _ScrollableLyrics({
    required this.lyrics,
    required this.currentIndex,
    required this.onLyricTap,
  });

  @override
  State<_ScrollableLyrics> createState() => _ScrollableLyricsState();
}

class _ScrollableLyricsState extends State<_ScrollableLyrics> {
  static const double _estimatedRowExtent = 68;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scheduleFollow();
  }

  @override
  void didUpdateWidget(covariant _ScrollableLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex ||
        oldWidget.lyrics.length != widget.lyrics.length) {
      _scheduleFollow();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleFollow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final index = widget.currentIndex;
      if (index == null || index < 0 || index >= widget.lyrics.length) return;

      final position = _scrollController.position;
      final rawTarget =
          index * _estimatedRowExtent - position.viewportDimension * 0.4;
      final target = rawTarget
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((_scrollController.offset - target).abs() < 18) return;

      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final gutter = spec.pageGutter.clamp(10, 28).toDouble();
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        gutter,
        spec.isShort ? 4 : AppSpacing.sm,
        gutter,
        spec.isShort ? AppSpacing.md : AppSpacing.xxl,
      ),
      itemCount: widget.lyrics.length,
      itemBuilder: (context, index) {
        final line = widget.lyrics[index];
        final current = widget.currentIndex == index;
        return Material(
          color: current ? AppColors.accent.withAlpha(18) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
          child: InkWell(
            onTap: () => widget.onLyricTap(line),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
            child: Container(
              constraints: BoxConstraints(minHeight: spec.minimumInteractiveExtent),
              padding: EdgeInsets.symmetric(
                horizontal: spec.isCompact ? AppSpacing.sm : AppSpacing.md,
                vertical: spec.isShort ? 6 : AppSpacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: spec.isCompact ? 48 : 58,
                    child: Text(
                      _formatTime(line.startTime),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: current
                                ? AppColors.accent
                                : AppColors.textTertiary,
                          ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      line.text,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: current
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            fontWeight:
                                current ? FontWeight.w800 : FontWeight.w500,
                            height: spec.isShort ? 1.3 : 1.45,
                          ),
                    ),
                  ),
                  if (line.isChorus && !spec.isCompact)
                    const Padding(
                      padding: EdgeInsets.only(left: AppSpacing.sm),
                      child: Icon(
                        Icons.queue_music_rounded,
                        size: 18,
                        color: AppColors.accent,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _KtvFocusLyrics extends StatelessWidget {
  final List<LyricLine> lyrics;
  final int? currentIndex;
  final ValueChanged<LyricLine> onLyricTap;

  const _KtvFocusLyrics({
    required this.lyrics,
    required this.currentIndex,
    required this.onLyricTap,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final index = (currentIndex ?? 0).clamp(0, lyrics.length - 1).toInt();
    final previous = index > 0 ? lyrics[index - 1] : null;
    final current = lyrics[index];
    final next = index + 1 < lyrics.length ? lyrics[index + 1] : null;
    final gap = spec.isShort ? AppSpacing.sm : AppSpacing.xl;
    final horizontal = spec.pageGutter.clamp(16, 48).toDouble();

    final previousStyle = (spec.isShort || spec.isCompact
            ? Theme.of(context).textTheme.bodyLarge
            : Theme.of(context).textTheme.titleMedium)
        ?.copyWith(color: AppColors.textTertiary);
    final currentStyle = (spec.isShort || spec.isCompact
            ? Theme.of(context).textTheme.headlineSmall
            : Theme.of(context).textTheme.headlineMedium)
        ?.copyWith(
      color: AppColors.accent,
      fontWeight: FontWeight.w900,
      height: 1.3,
    );
    final nextStyle = (spec.isShort || spec.isCompact
            ? Theme.of(context).textTheme.titleMedium
            : Theme.of(context).textTheme.titleLarge)
        ?.copyWith(color: AppColors.textSecondary);

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: horizontal,
          vertical: spec.isShort ? AppSpacing.sm : AppSpacing.xxl,
        ),
        child: Column(
          children: [
            _FocusLyricLine(
              line: previous,
              style: previousStyle,
              onTap: previous == null ? null : () => onLyricTap(previous),
            ),
            SizedBox(height: gap),
            _FocusLyricLine(
              line: current,
              style: currentStyle,
              onTap: () => onLyricTap(current),
            ),
            SizedBox(height: gap),
            _FocusLyricLine(
              line: next,
              style: nextStyle,
              onTap: next == null ? null : () => onLyricTap(next),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusLyricLine extends StatelessWidget {
  final LyricLine? line;
  final TextStyle? style;
  final VoidCallback? onTap;

  const _FocusLyricLine({
    required this.line,
    required this.style,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    if (line == null) {
      return SizedBox(height: spec.isShort ? 18 : 32);
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      child: Container(
        constraints: BoxConstraints(minHeight: spec.minimumInteractiveExtent),
        padding: EdgeInsets.all(spec.isShort ? 6 : AppSpacing.sm),
        child: Text(
          line!.text,
          textAlign: TextAlign.center,
          style: style,
        ),
      ),
    );
  }
}

class _KtvEntrySheet extends StatelessWidget {
  final AudioAsset audioAsset;
  final AudioSourceType? currentSource;

  const _KtvEntrySheet({
    required this.audioAsset,
    required this.currentSource,
  });

  @override
  Widget build(BuildContext context) {
    final instrumentalAvailable =
        audioAsset.hasSource(AudioSourceType.instrumental);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mic_rounded, color: AppColors.accent),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '进入 KTV',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '选择演唱时保留原唱伴唱，或只播放纯伴奏。切换音轨会保留当前播放位置。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          _KtvModeTile(
            mode: KtvBackingMode.guideVocal,
            selected: currentSource == KtvBackingMode.guideVocal.source,
            enabled: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          _KtvModeTile(
            mode: KtvBackingMode.instrumental,
            selected: currentSource == KtvBackingMode.instrumental.source,
            enabled: instrumentalAvailable,
          ),
          if (!instrumentalAvailable) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '纯伴奏暂不可用：需要先为该歌曲生成伴奏轨。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _KtvModeTile extends StatelessWidget {
  final KtvBackingMode mode;
  final bool selected;
  final bool enabled;

  const _KtvModeTile({
    required this.mode,
    required this.selected,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accent.withAlpha(18) : AppColors.bgSurface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      child: ListTile(
        enabled: enabled,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        ),
        leading: Icon(
          mode == KtvBackingMode.guideVocal
              ? Icons.record_voice_over_rounded
              : Icons.music_note_rounded,
          color: enabled ? AppColors.accent : AppColors.textTertiary,
        ),
        title: Text(
          mode.label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(mode.description),
        trailing: selected ? const Icon(Icons.check_circle_rounded) : null,
        onTap: enabled ? () => Navigator.pop(context, mode) : null,
      ),
    );
  }
}

class _FullScreenKtvView extends StatefulWidget {
  final ProjectManifest initialProject;
  final ProjectRepository repository;
  final AudioPlayerService audioService;
  final PlaybackSessionService playbackSession;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<AudioSourceType> onSwitchSource;
  final VoidCallback onSkipPrevious;
  final VoidCallback onSkipNext;

  const _FullScreenKtvView({
    required this.initialProject,
    required this.repository,
    required this.audioService,
    required this.playbackSession,
    required this.onPlayPause,
    required this.onSeek,
    required this.onSwitchSource,
    required this.onSkipPrevious,
    required this.onSkipNext,
  });

  @override
  State<_FullScreenKtvView> createState() => _FullScreenKtvViewState();
}

class _FullScreenKtvViewState extends State<_FullScreenKtvView> {
  late ProjectManifest _project;
  late final KtvMicrophoneService _microphoneService;
  late final KtvRecordingService _recordingService;
  StreamSubscription<PlaybackSessionState>? _sessionSubscription;
  int _projectLoadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _project = widget.initialProject;
    _microphoneService = ServiceLocatorGlobal.I.ktvMicrophoneService;
    _recordingService = ServiceLocatorGlobal.I.ktvRecordingService;
    AppChromeController.enterImmersive();
    _sessionSubscription =
        widget.playbackSession.stateStream.listen(_handleSessionChange);
  }

  Future<void> _handleSessionChange(PlaybackSessionState state) async {
    final projectId = state.currentItem?.projectId;
    if (projectId == null || projectId == _project.id) return;

    final generation = ++_projectLoadGeneration;
    final nextProject = await widget.repository.getProjectById(projectId);
    if (!mounted || generation != _projectLoadGeneration || nextProject == null) {
      return;
    }
    setState(() => _project = nextProject);
  }

  Future<void> _openMicrophoneControls() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.bgElevated,
      builder: (context) => _KtvAudioControlsSheet(
        microphoneService: _microphoneService,
        audioService: widget.audioService,
        recordingLocked: _recordingService.currentState.isRecording,
      ),
    );
  }

  Future<void> _toggleRecording() async {
    try {
      if (_recordingService.currentState.isRecording) {
        final completed = await _recordingService.stopRecording();
        if (!mounted) return;
        setState(() {});
        if (completed != null) await _showTakeResult(completed);
        return;
      }
      await _recordingService.startRecording(_project);
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('KTV 录音失败：$error')),
      );
    }
  }

  Future<void> _showTakeResult(KtvRecordingSession session) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.bgElevated,
      builder: (context) => _KtvTakeResultSheet(
        initialSession: session,
        recordingService: _recordingService,
      ),
    );
  }

  Future<void> _shutdownKtvAudio() async {
    if (_recordingService.currentState.isRecording) {
      await _recordingService.stopRecording();
    }
    await _microphoneService.stopMonitoring();
  }

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    unawaited(_shutdownKtvAudio());
    AppChromeController.exitImmersive();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final document = _project.lyricDocument;
    final lyrics = document?.lines ?? const <LyricLine>[];
    final ktvSources = availableKtvBackingModes(_project.audioAsset)
        .map((mode) => mode.source)
        .toList(growable: false);
    final recordingLocked = _recordingService.currentState.isRecording;

    return Material(
      color: AppColors.pureBlack,
      child: SafeArea(
        child: StreamBuilder<PlaybackSessionState>(
          stream: widget.playbackSession.stateStream,
          initialData: widget.playbackSession.currentState,
          builder: (context, sessionSnapshot) {
            final session =
                sessionSnapshot.data ?? widget.playbackSession.currentState;
            return StreamBuilder<PlaybackState>(
              stream: widget.audioService.stateStream,
              initialData: widget.audioService.currentState,
              builder: (context, playbackSnapshot) {
                final spec = AppResponsive.of(context);
                final playback =
                    playbackSnapshot.data ?? const PlaybackState.idle();
                final currentIndex =
                    _currentLyricIndex(document, playback.position) ?? 0;
                final safeIndex = lyrics.isEmpty
                    ? 0
                    : currentIndex.clamp(0, lyrics.length - 1).toInt();
                final previous = lyrics.isNotEmpty && safeIndex > 0
                    ? lyrics[safeIndex - 1]
                    : null;
                final current = lyrics.isEmpty ? null : lyrics[safeIndex];
                final next = lyrics.isNotEmpty && safeIndex + 1 < lyrics.length
                    ? lyrics[safeIndex + 1]
                    : null;
                final topGutter = spec.pageGutter.clamp(12, 32).toDouble();
                final lyricGutter = spec.isExtraLarge
                    ? 120.0
                    : spec.isLarge
                        ? 88.0
                        : spec.pageGutter.clamp(16, 48).toDouble();
                final lyricGap = spec.isShort
                    ? AppSpacing.sm
                    : spec.isCompact
                        ? AppSpacing.lg
                        : AppSpacing.xxl;

                final previousStyle = (spec.isShort || spec.isCompact
                        ? Theme.of(context).textTheme.titleMedium
                        : Theme.of(context).textTheme.headlineSmall)
                    ?.copyWith(
                  color: AppColors.textTertiary,
                  height: 1.35,
                );
                final currentStyle = (spec.isShort
                        ? Theme.of(context).textTheme.headlineMedium
                        : spec.isCompact
                            ? Theme.of(context).textTheme.headlineLarge
                            : Theme.of(context).textTheme.displaySmall)
                    ?.copyWith(
                  color: AppColors.pureWhite,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                );
                final nextStyle = (spec.isShort || spec.isCompact
                        ? Theme.of(context).textTheme.titleLarge
                        : Theme.of(context).textTheme.headlineMedium)
                    ?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.3,
                );

                return Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF151515), Color(0xFF050505)],
                    ),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          topGutter,
                          spec.isShort ? 6 : AppSpacing.md,
                          topGutter,
                          0,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _project.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: (spec.isShort
                                            ? Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                            : Theme.of(context)
                                                .textTheme
                                                .titleLarge)
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  if (!spec.isShort &&
                                      _project.artist?.trim().isNotEmpty == true)
                                    Text(
                                      _project.artist!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: AppColors.textSecondary,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                            if (ktvSources.length > 1) ...[
                              if (spec.isCompact || spec.isShort)
                                IgnorePointer(
                                  ignoring: recordingLocked,
                                  child: Opacity(
                                    opacity: recordingLocked ? 0.45 : 1,
                                    child: _CompactSourceMenu(
                                      availableSources: ktvSources,
                                      currentSource: playback.currentSource,
                                      onSourceChanged: widget.onSwitchSource,
                                      ktvLabels: true,
                                    ),
                                  ),
                                )
                              else
                                Flexible(
                                  child: IgnorePointer(
                                    ignoring: recordingLocked,
                                    child: Opacity(
                                      opacity: recordingLocked ? 0.45 : 1,
                                      child: _AudioSourceSelector(
                                        availableSources: ktvSources,
                                        currentSource: playback.currentSource,
                                        onSourceChanged: widget.onSwitchSource,
                                        compact: true,
                                        ktvLabels: true,
                                      ),
                                    ),
                                  ),
                                ),
                              const SizedBox(width: AppSpacing.sm),
                            ],
                            StreamBuilder<KtvRecordingState>(
                              stream: _recordingService.stateStream,
                              initialData: _recordingService.currentState,
                              builder: (context, recordingSnapshot) {
                                final recording = recordingSnapshot.data ??
                                    _recordingService.currentState;
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (recording.isRecording && !spec.isShort)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: AppSpacing.xs,
                                        ),
                                        child: Text(
                                          _formatRecordingTime(
                                            recording.recordedDuration,
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                color: AppColors.error,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                    SizedBox(
                                      width: spec.minimumInteractiveExtent,
                                      height: spec.minimumInteractiveExtent,
                                      child: IconButton.filled(
                                        tooltip: recording.isRecording
                                            ? '停止录音'
                                            : '开始 KTV 录音',
                                        onPressed: recording.isExporting
                                            ? null
                                            : _toggleRecording,
                                        style: IconButton.styleFrom(
                                          backgroundColor: recording.isRecording
                                              ? AppColors.error
                                              : AppColors.bgSurface,
                                          foregroundColor: AppColors.pureWhite,
                                        ),
                                        icon: Icon(
                                          recording.isRecording
                                              ? Icons.stop_rounded
                                              : Icons.fiber_manual_record_rounded,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            StreamBuilder<KtvMicrophoneState>(
                              stream: _microphoneService.stateStream,
                              initialData: _microphoneService.currentState,
                              builder: (context, microphoneSnapshot) {
                                final microphone = microphoneSnapshot.data ??
                                    _microphoneService.currentState;
                                return SizedBox(
                                  width: spec.minimumInteractiveExtent,
                                  height: spec.minimumInteractiveExtent,
                                  child: IconButton.filledTonal(
                                    tooltip: microphone.isMonitoring
                                        ? '麦克风监听已开启'
                                        : '麦克风与音量',
                                    onPressed: _openMicrophoneControls,
                                    icon: Icon(
                                      microphone.isMonitoring
                                          ? Icons.mic_rounded
                                          : Icons.mic_none_rounded,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            SizedBox(
                              width: spec.minimumInteractiveExtent,
                              height: spec.minimumInteractiveExtent,
                              child: IconButton.filledTonal(
                                tooltip: '退出全屏 KTV',
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.fullscreen_exit_rounded),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: lyrics.isEmpty
                            ? const _FullscreenNoLyrics()
                            : Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: lyricGutter,
                                    vertical:
                                        spec.isShort ? 4 : AppSpacing.sm,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _FullscreenLyric(
                                        line: previous,
                                        style: previousStyle,
                                        maxLines: spec.isShort ? 1 : 2,
                                      ),
                                      SizedBox(height: lyricGap),
                                      _FullscreenLyric(
                                        line: current,
                                        style: currentStyle,
                                        maxLines: spec.isShort ? 2 : 3,
                                      ),
                                      SizedBox(height: lyricGap),
                                      _FullscreenLyric(
                                        line: next,
                                        style: nextStyle,
                                        maxLines: spec.isShort ? 1 : 2,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          topGutter,
                          0,
                          topGutter,
                          spec.isShort ? 6 : AppSpacing.lg,
                        ),
                        child: Column(
                          children: [
                            if (playback.error != null) ...[
                              _PlaybackError(message: playback.error!),
                              SizedBox(
                                height: spec.isShort ? 4 : AppSpacing.sm,
                              ),
                            ],
                            IgnorePointer(
                              ignoring: recordingLocked,
                              child: Opacity(
                                opacity: recordingLocked ? 0.55 : 1,
                                child: _ProgressBar(
                                  state: playback,
                                  onSeek: widget.onSeek,
                                  compact: true,
                                ),
                              ),
                            ),
                            SizedBox(
                              height: spec.isShort ? 2 : AppSpacing.sm,
                            ),
                            IgnorePointer(
                              ignoring: recordingLocked,
                              child: Opacity(
                                opacity: recordingLocked ? 0.55 : 1,
                                child: _PlaybackControls(
                                  isPlaying: playback.isPlaying,
                                  isBuffering: playback.isBuffering,
                                  canPrevious: session.currentItem != null,
                                  canNext: session.canSkipNext,
                                  onPrevious: widget.onSkipPrevious,
                                  onPlayPause: widget.onPlayPause,
                                  onNext: widget.onSkipNext,
                                  compact: spec.isShort || spec.isCompact,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _KtvTakeResultSheet extends StatefulWidget {
  final KtvRecordingSession initialSession;
  final KtvRecordingService recordingService;

  const _KtvTakeResultSheet({
    required this.initialSession,
    required this.recordingService,
  });

  @override
  State<_KtvTakeResultSheet> createState() => _KtvTakeResultSheetState();
}

class _KtvTakeResultSheetState extends State<_KtvTakeResultSheet> {
  late KtvRecordingSession _session;
  late double _voiceVolume;
  late double _backingVolume;
  bool _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
    _voiceVolume = 1.0;
    _backingVolume = _session.backingVolume;
  }

  Future<void> _exportMix() async {
    if (_exporting || !_session.alignmentReliable) return;
    setState(() {
      _exporting = true;
      _error = null;
    });
    try {
      final exported = await widget.recordingService.exportMix(
        _session,
        voiceVolume: _voiceVolume,
        backingVolume: _backingVolume,
      );
      if (!mounted) return;
      setState(() {
        _session = exported;
        _exporting = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        spec.pageGutter,
        AppSpacing.sm,
        spec.pageGutter,
        AppSpacing.xxl,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    _session.alignmentReliable
                        ? Icons.check_circle_rounded
                        : Icons.warning_amber_rounded,
                    color: _session.alignmentReliable
                        ? AppColors.accent
                        : AppColors.warning,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'KTV 录音已保存',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '人声 stem（${_formatRecordingTime(_session.duration)}）',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              SelectableText(
                _session.micStemPath,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              if (!_session.alignmentReliable) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _session.alignmentIssue ??
                      '播放时间轴在录音中发生变化，已保留人声 stem，但自动混音已禁用。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.warning,
                      ),
                ),
              ],
              if (_session.mixedOutputPath != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  '混音成品',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                SelectableText(
                  _session.mixedOutputPath!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              _KtvControlLabel(
                title: '导出人声音量',
                value: '${(_voiceVolume * 100).round()}%',
              ),
              Slider(
                value: _voiceVolume,
                min: 0,
                max: 2,
                divisions: 20,
                onChanged: _exporting
                    ? null
                    : (value) => setState(() => _voiceVolume = value),
              ),
              _KtvControlLabel(
                title: '导出伴奏音量',
                value: '${(_backingVolume * 100).round()}%',
              ),
              Slider(
                value: _backingVolume,
                min: 0,
                max: 1,
                divisions: 20,
                onChanged: _exporting
                    ? null
                    : (value) => setState(() => _backingVolume = value),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                _PlaybackError(message: _error!),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: !_session.alignmentReliable || _exporting
                    ? null
                    : _exportMix,
                icon: _exporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.graphic_eq_rounded),
                label: Text(
                  _session.mixedOutputPath == null ? '导出 WAV 混音' : '重新导出混音',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KtvAudioControlsSheet extends StatelessWidget {
  final KtvMicrophoneService microphoneService;
  final AudioPlayerService audioService;
  final bool recordingLocked;

  const _KtvAudioControlsSheet({
    required this.microphoneService,
    required this.audioService,
    required this.recordingLocked,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    return StreamBuilder<KtvMicrophoneState>(
      stream: microphoneService.stateStream,
      initialData: microphoneService.currentState,
      builder: (context, microphoneSnapshot) {
        final microphone =
            microphoneSnapshot.data ?? microphoneService.currentState;
        return StreamBuilder<PlaybackState>(
          stream: audioService.stateStream,
          initialData: audioService.currentState,
          builder: (context, playbackSnapshot) {
            final playback = playbackSnapshot.data ?? audioService.currentState;
            final engineMs = microphone.engineLatency?.inMilliseconds;
            final extraMs = microphone.monitorDelay.inMilliseconds;
            final totalMs = engineMs == null ? null : engineMs + extraMs;
            const systemDefaultDeviceId = '__system_default__';
            final selectedDeviceId = microphone.selectedInputDeviceId;
            final selectedDeviceValue = selectedDeviceId != null &&
                    microphone.inputDevices
                        .any((device) => device.id == selectedDeviceId)
                ? selectedDeviceId
                : systemDefaultDeviceId;
            final selectedDevice = microphone.selectedInputDevice;
            final deviceControlsLocked = recordingLocked ||
                microphone.isStarting ||
                microphone.isRefreshingInputDevices;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                spec.pageGutter,
                AppSpacing.sm,
                spec.pageGutter,
                AppSpacing.xxl,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.mic_rounded, color: AppColors.accent),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              '麦克风与演唱音量',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '麦克风监听与歌曲播放使用独立音量。建议佩戴耳机或使用独立监听设备，扬声器直出可能产生啸叫。',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '麦克风输入设备',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                          SizedBox(
                            width: spec.minimumInteractiveExtent,
                            height: spec.minimumInteractiveExtent,
                            child: IconButton(
                              tooltip: recordingLocked
                                  ? '录音期间不能刷新麦克风设备'
                                  : '刷新麦克风设备',
                              onPressed: deviceControlsLocked
                                  ? null
                                  : () => unawaited(
                                        microphoneService.refreshInputDevices(),
                                      ),
                              icon: microphone.isRefreshingInputDevices
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.refresh_rounded),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      InputDecorator(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.mic_external_on_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusMedium,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedDeviceValue,
                            isExpanded: true,
                            items: [
                              const DropdownMenuItem<String>(
                                value: systemDefaultDeviceId,
                                child: Text('系统默认'),
                              ),
                              ...microphone.inputDevices.map(
                                (device) => DropdownMenuItem<String>(
                                  value: device.id,
                                  child: Text(
                                    device.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: deviceControlsLocked
                                ? null
                                : (value) => unawaited(
                                      microphoneService.selectInputDevice(
                                        value == systemDefaultDeviceId
                                            ? null
                                            : value,
                                      ),
                                    ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        recordingLocked
                            ? '正在录制 take，输入设备已锁定；停止录音后可切换。'
                            : selectedDevice == null
                                ? microphone.inputDevices.isEmpty
                                    ? '未发现可选麦克风，将继续使用系统默认输入；可点击刷新重新扫描。'
                                    : '当前跟随系统默认输入设备；也可以固定选择某个麦克风。'
                                : '当前：${selectedDevice.label}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: recordingLocked
                                  ? AppColors.warning
                                  : AppColors.textTertiary,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: microphone.isMonitoring,
                        onChanged: microphone.isStarting || recordingLocked
                            ? null
                            : (enabled) {
                                unawaited(
                                  enabled
                                      ? microphoneService.startMonitoring()
                                      : microphoneService.stopMonitoring(),
                                );
                              },
                        secondary: microphone.isStarting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                microphone.isMonitoring
                                    ? Icons.hearing_rounded
                                    : Icons.hearing_disabled_rounded,
                              ),
                        title: const Text('实时麦克风监听'),
                        subtitle: Text(
                          microphone.isMonitoring
                              ? '正在把麦克风输入低延迟送到当前输出设备'
                              : '开启后系统会请求麦克风权限',
                        ),
                      ),
                      if (microphone.error != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _PlaybackError(message: microphone.error!),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        '麦克风电平',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      LinearProgressIndicator(
                        value: microphone.inputLevel.clamp(0.0, 1.0).toDouble(),
                        minHeight: 7,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _KtvControlLabel(
                        title: '麦克风音量',
                        value: '${(microphone.micGain * 100).round()}%',
                      ),
                      Slider(
                        value: microphone.micGain.clamp(0.0, 2.0).toDouble(),
                        min: 0,
                        max: 2,
                        divisions: 20,
                        onChanged: (value) =>
                            unawaited(microphoneService.setMicGain(value)),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _KtvControlLabel(
                        title: '歌曲音量',
                        value: '${(playback.volume * 100).round()}%',
                      ),
                      Slider(
                        value: playback.volume.clamp(0.0, 1.0).toDouble(),
                        min: 0,
                        max: 1,
                        divisions: 20,
                        onChanged: recordingLocked
                            ? null
                            : (value) =>
                                unawaited(audioService.setVolume(value)),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _KtvControlLabel(
                        title: '监听附加延迟',
                        value: '${extraMs}ms',
                      ),
                      Slider(
                        value: extraMs.clamp(0, 250).toDouble(),
                        min: 0,
                        max: 250,
                        divisions: 25,
                        onChanged: (value) => unawaited(
                          microphoneService.setMonitorDelay(
                            Duration(milliseconds: value.round()),
                          ),
                        ),
                      ),
                      Text(
                        totalMs == null
                            ? '设备未报告稳定的硬件延迟；这里的数值只增加软件监听延迟。'
                            : '音频引擎约 ${engineMs}ms + 附加 ${extraMs}ms = 约 ${totalMs}ms。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textTertiary,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _KtvControlLabel extends StatelessWidget {
  final String title;
  final String value;

  const _KtvControlLabel({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.labelLarge),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ],
    );
  }
}

class _CompactSourceMenu extends StatelessWidget {
  final List<AudioSourceType> availableSources;
  final AudioSourceType? currentSource;
  final ValueChanged<AudioSourceType> onSourceChanged;
  final bool ktvLabels;

  const _CompactSourceMenu({
    required this.availableSources,
    required this.currentSource,
    required this.onSourceChanged,
    this.ktvLabels = false,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    return SizedBox(
      width: spec.minimumInteractiveExtent,
      height: spec.minimumInteractiveExtent,
      child: PopupMenuButton<AudioSourceType>(
        tooltip: ktvLabels ? '切换 KTV 音轨' : '切换音源',
        icon: const Icon(Icons.tune_rounded),
        onSelected: onSourceChanged,
        itemBuilder: (context) => availableSources
            .map(
              (source) => CheckedPopupMenuItem<AudioSourceType>(
                value: source,
                checked: source == currentSource,
                child: Text(
                  ktvLabels ? _ktvSourceLabel(source) : _sourceLabel(source),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _FullscreenLyric extends StatelessWidget {
  final LyricLine? line;
  final TextStyle? style;
  final int maxLines;

  const _FullscreenLyric({
    required this.line,
    required this.style,
    this.maxLines = 3,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Text(
        line?.text ?? '',
        key: ValueKey<String?>(line?.text),
        textAlign: TextAlign.center,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

class _FullscreenNoLyrics extends StatelessWidget {
  const _FullscreenNoLyrics();

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(spec.pageGutter),
        child: Text(
          '当前歌曲没有可用歌词',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.textTertiary,
              ),
        ),
      ),
    );
  }
}

class _ProjectArtwork extends StatelessWidget {
  final String? path;
  final bool loading;
  final bool compact;

  const _ProjectArtwork({
    this.path,
    required this.loading,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final file = path == null ? null : File(path!);
    final hasArtwork = file != null && file.existsSync();
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          compact ? AppSpacing.radiusMedium : AppSpacing.radiusXLarge,
        ),
        child: Container(
          decoration: const BoxDecoration(gradient: AppColors.playerGradient),
          child: hasArtwork
              ? Image.file(file!, fit: BoxFit.cover)
              : Center(
                  child: Icon(
                    Icons.album_rounded,
                    size: compact ? 34 : 88,
                    color: loading
                        ? AppColors.accent
                        : AppColors.textTertiary,
                  ),
                ),
        ),
      ),
    );
  }
}

class _SongIdentity extends StatelessWidget {
  final ProjectManifest project;
  final bool compact;

  const _SongIdentity({required this.project, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    return Column(
      crossAxisAlignment:
          compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(
          project.name,
          textAlign: compact ? TextAlign.left : TextAlign.center,
          maxLines: compact ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: (compact
                  ? Theme.of(context).textTheme.titleMedium
                  : Theme.of(context).textTheme.headlineSmall)
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (!spec.isShort) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            project.artist?.trim().isNotEmpty == true
                ? project.artist!
                : '未知艺术家',
            textAlign: compact ? TextAlign.left : TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
        if (!compact && project.album?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 2),
          Text(
            project.album!,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
          ),
        ],
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final PlaybackState state;
  final ValueChanged<Duration> onSeek;
  final bool compact;

  const _ProgressBar({
    required this.state,
    required this.onSeek,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final duration = state.duration;
    final durationMs = duration?.inMilliseconds ?? 0;
    final max = durationMs > 0 ? durationMs.toDouble() : 1.0;
    final value = state.position.inMilliseconds
        .toDouble()
        .clamp(0.0, max)
        .toDouble();

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: compact ? 3 : 4,
            overlayShape: SliderComponentShape.noOverlay,
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius: compact ? 5 : 7,
            ),
          ),
          child: Slider(
            value: value,
            min: 0,
            max: max,
            onChanged: durationMs <= 0
                ? null
                : (next) => onSeek(Duration(milliseconds: next.round())),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: [
              Text(
                state.formattedPosition,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
              ),
              const Spacer(),
              Text(
                state.formattedDuration,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  final bool isPlaying;
  final bool isBuffering;
  final bool canPrevious;
  final bool canNext;
  final VoidCallback onPrevious;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final bool compact;

  const _PlaybackControls({
    required this.isPlaying,
    required this.isBuffering,
    required this.canPrevious,
    required this.canNext,
    required this.onPrevious,
    required this.onPlayPause,
    required this.onNext,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final secondaryExtent = spec.minimumInteractiveExtent;
    final playSize = compact
        ? spec.minimumInteractiveExtent
        : spec.primaryPlayerControlExtent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: secondaryExtent,
          height: secondaryExtent,
          child: IconButton(
            tooltip: '上一首 / 回到开头',
            onPressed: canPrevious ? onPrevious : null,
            icon: const Icon(Icons.skip_previous_rounded),
            iconSize: compact ? 24 : 30,
          ),
        ),
        SizedBox(width: compact ? AppSpacing.xs : AppSpacing.sm),
        SizedBox(
          width: playSize,
          height: playSize,
          child: IconButton(
            tooltip: isPlaying ? '暂停' : '播放',
            onPressed: isBuffering ? null : onPlayPause,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.pureWhite,
              foregroundColor: AppColors.pureBlack,
            ),
            icon: isBuffering
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.pureBlack,
                    ),
                  )
                : Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
          ),
        ),
        SizedBox(width: compact ? AppSpacing.xs : AppSpacing.sm),
        SizedBox(
          width: secondaryExtent,
          height: secondaryExtent,
          child: IconButton(
            tooltip: '下一首',
            onPressed: canNext ? onNext : null,
            icon: const Icon(Icons.skip_next_rounded),
            iconSize: compact ? 24 : 30,
          ),
        ),
      ],
    );
  }
}

class _AudioSourceSelector extends StatelessWidget {
  final List<AudioSourceType> availableSources;
  final AudioSourceType? currentSource;
  final ValueChanged<AudioSourceType> onSourceChanged;
  final bool compact;
  final bool ktvLabels;

  const _AudioSourceSelector({
    required this.availableSources,
    required this.currentSource,
    required this.onSourceChanged,
    this.compact = false,
    this.ktvLabels = false,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: availableSources.map((source) {
        return ChoiceChip(
          selected: source == currentSource,
          onSelected: (_) => onSourceChanged(source),
          visualDensity: compact ? VisualDensity.compact : null,
          label: Text(
            ktvLabels ? _ktvSourceLabel(source) : _sourceLabel(source),
          ),
        );
      }).toList(growable: false),
    );
  }
}

class _PlayerModeControls extends StatelessWidget {
  final bool ktvMode;
  final bool hasLyrics;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback? onOpenFullScreenKtv;
  final bool compact;

  const _PlayerModeControls({
    required this.ktvMode,
    required this.hasLyrics,
    required this.onModeChanged,
    required this.onOpenFullScreenKtv,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        ChoiceChip(
          selected: !ktvMode,
          visualDensity: compact ? VisualDensity.compact : null,
          onSelected: (_) => onModeChanged(false),
          avatar: const Icon(Icons.library_music_outlined, size: 17),
          label: const Text('普通'),
        ),
        ChoiceChip(
          selected: ktvMode,
          visualDensity: compact ? VisualDensity.compact : null,
          onSelected: hasLyrics ? (_) => onModeChanged(true) : null,
          avatar: const Icon(Icons.mic_rounded, size: 17),
          label: const Text('KTV'),
        ),
        if (hasLyrics)
          OutlinedButton.icon(
            onPressed: onOpenFullScreenKtv,
            icon: const Icon(Icons.fullscreen_rounded, size: 18),
            label: Text(spec.isCompact || spec.isShort ? '全屏' : '全屏 KTV'),
            style: OutlinedButton.styleFrom(
              minimumSize: Size(0, spec.minimumInteractiveExtent),
            ),
          ),
      ],
    );
  }
}

class _PlaybackError extends StatelessWidget {
  final String message;

  const _PlaybackError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.error.withAlpha(20),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        border: Border.all(color: AppColors.error.withAlpha(70)),
      ),
      child: Text(
        message,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.error,
            ),
      ),
    );
  }
}

class _NoLyricsState extends StatelessWidget {
  const _NoLyricsState();

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(spec.pageGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lyrics_outlined,
              size: 52,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '这个工程还没有歌词',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '可以继续普通播放，生成或编辑歌词后再进入 KTV 模式。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

Duration _effectiveLyricStart(LyricDocument? document, LyricLine line) {
  final shifted = line.startTime + (document?.globalOffset ?? Duration.zero);
  return shifted.isNegative ? Duration.zero : shifted;
}

int? _currentLyricIndex(LyricDocument? document, Duration position) {
  final lines = document?.lines;
  if (lines == null || lines.isEmpty) return null;

  for (var index = lines.length - 1; index >= 0; index--) {
    if (position >= _effectiveLyricStart(document, lines[index])) {
      return index;
    }
  }
  return 0;
}

String _formatRecordingTime(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '$minutes:$seconds';
}

String _sourceLabel(AudioSourceType source) {
  return switch (source) {
    AudioSourceType.original => '原声',
    AudioSourceType.instrumental => '伴奏',
    AudioSourceType.vocals => '人声',
  };
}

String _ktvSourceLabel(AudioSourceType source) {
  return switch (source) {
    AudioSourceType.original => KtvBackingMode.guideVocal.label,
    AudioSourceType.instrumental => KtvBackingMode.instrumental.label,
    AudioSourceType.vocals => '人声试听',
  };
}

String _formatTime(Duration value) {
  final minutes = value.inMinutes.toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
