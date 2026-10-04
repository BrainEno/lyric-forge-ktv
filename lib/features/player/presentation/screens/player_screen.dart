import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/navigation/app_chrome_controller.dart';
import '../../../../core/navigation/app_router.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/audio_player_service.dart';
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
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            const Text('加载播放器失败'),
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
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
          IconButton(
            tooltip: '工程详情',
            onPressed: () => Navigator.pushNamed(
              context,
              Routes.projectDetailPath(widget.project.id),
            ),
            icon: const Icon(Icons.info_outline_rounded),
          ),
          IconButton(
            tooltip: '校对歌词',
            onPressed: () => Navigator.pushNamed(
              context,
              Routes.lyricEditorPath(widget.project.id),
            ),
            icon: const Icon(Icons.edit_rounded),
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
        final wide = constraints.maxWidth >= 980;
        if (wide) {
          return Row(
            children: [
              SizedBox(
                width: constraints.maxWidth.clamp(360.0, 460.0).toDouble(),
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
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 310),
            child: _ProjectArtwork(
              path: project.audioAsset?.thumbnailPath,
              loading: playback.isLoading,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SongIdentity(project: project),
        if (playback.error != null) ...[
          const SizedBox(height: AppSpacing.md),
          _PlaybackError(message: playback.error!),
        ],
        const SizedBox(height: AppSpacing.lg),
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
        const SizedBox(height: AppSpacing.lg),
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
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                height: 64,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  ktvMode ? 'KTV 歌词' : '同步歌词',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (ktvMode && onOpenFullScreenKtv != null)
                TextButton.icon(
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

class _ScrollableLyrics extends StatelessWidget {
  final List<LyricLine> lyrics;
  final int? currentIndex;
  final ValueChanged<LyricLine> onLyricTap;

  const _ScrollableLyrics({
    required this.lyrics,
    required this.currentIndex,
    required this.onLyricTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      itemCount: lyrics.length,
      itemBuilder: (context, index) {
        final line = lyrics[index];
        final current = currentIndex == index;
        return Material(
          color: current ? AppColors.accent.withAlpha(18) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
          child: InkWell(
            onTap: () => onLyricTap(line),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 58,
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
                            height: 1.45,
                          ),
                    ),
                  ),
                  if (line.isChorus)
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
    final index = (currentIndex ?? 0).clamp(0, lyrics.length - 1).toInt();
    final previous = index > 0 ? lyrics[index - 1] : null;
    final current = lyrics[index];
    final next = index + 1 < lyrics.length ? lyrics[index + 1] : null;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xxl,
        ),
        child: Column(
          children: [
            _FocusLyricLine(
              line: previous,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textTertiary,
                  ),
              onTap: previous == null ? null : () => onLyricTap(previous),
            ),
            const SizedBox(height: AppSpacing.xl),
            _FocusLyricLine(
              line: current,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w900,
                    height: 1.35,
                  ),
              onTap: () => onLyricTap(current),
            ),
            const SizedBox(height: AppSpacing.xl),
            _FocusLyricLine(
              line: next,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
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
    if (line == null) return const SizedBox(height: 32);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Text(
          line!.text,
          textAlign: TextAlign.center,
          style: style,
        ),
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
  StreamSubscription<PlaybackSessionState>? _sessionSubscription;
  int _projectLoadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _project = widget.initialProject;
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

  @override
  void dispose() {
    _sessionSubscription?.cancel();
    AppChromeController.exitImmersive();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final document = _project.lyricDocument;
    final lyrics = document?.lines ?? const <LyricLine>[];
    final availableSources =
        _project.audioAsset?.availableSources ?? const <AudioSourceType>[];

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
                final playback =
                    playbackSnapshot.data ?? const PlaybackState.idle();
                final currentIndex =
                    _currentLyricIndex(document, playback.position) ?? 0;
                final safeIndex = lyrics.isEmpty
                    ? 0
                    : currentIndex.clamp(0, lyrics.length - 1).toInt();
                final previous =
                    lyrics.isNotEmpty && safeIndex > 0 ? lyrics[safeIndex - 1] : null;
                final current = lyrics.isEmpty ? null : lyrics[safeIndex];
                final next = lyrics.isNotEmpty && safeIndex + 1 < lyrics.length
                    ? lyrics[safeIndex + 1]
                    : null;

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
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.md,
                          AppSpacing.md,
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  if (_project.artist?.trim().isNotEmpty == true)
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
                            if (availableSources.length > 1)
                              Flexible(
                                child: _AudioSourceSelector(
                                  availableSources: availableSources,
                                  currentSource: playback.currentSource,
                                  onSourceChanged: widget.onSwitchSource,
                                  compact: true,
                                ),
                              ),
                            const SizedBox(width: AppSpacing.sm),
                            IconButton.filledTonal(
                              tooltip: '退出全屏 KTV',
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.fullscreen_exit_rounded),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: lyrics.isEmpty
                            ? const _FullscreenNoLyrics()
                            : Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.xxxl,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _FullscreenLyric(
                                        line: previous,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              color: AppColors.textTertiary,
                                              height: 1.4,
                                            ),
                                      ),
                                      const SizedBox(height: AppSpacing.xxl),
                                      _FullscreenLyric(
                                        line: current,
                                        style: Theme.of(context)
                                            .textTheme
                                            .displaySmall
                                            ?.copyWith(
                                              color: AppColors.pureWhite,
                                              fontWeight: FontWeight.w900,
                                              height: 1.25,
                                            ),
                                      ),
                                      const SizedBox(height: AppSpacing.xxl),
                                      _FullscreenLyric(
                                        line: next,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineMedium
                                            ?.copyWith(
                                              color: AppColors.textSecondary,
                                              height: 1.35,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.xl,
                          0,
                          AppSpacing.xl,
                          AppSpacing.lg,
                        ),
                        child: Column(
                          children: [
                            if (playback.error != null) ...[
                              _PlaybackError(message: playback.error!),
                              const SizedBox(height: AppSpacing.sm),
                            ],
                            _ProgressBar(
                              state: playback,
                              onSeek: widget.onSeek,
                              compact: true,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            _PlaybackControls(
                              isPlaying: playback.isPlaying,
                              isBuffering: playback.isBuffering,
                              canPrevious: session.currentItem != null,
                              canNext: session.canSkipNext,
                              onPrevious: widget.onSkipPrevious,
                              onPlayPause: widget.onPlayPause,
                              onNext: widget.onSkipNext,
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

class _FullscreenLyric extends StatelessWidget {
  final LyricLine? line;
  final TextStyle? style;

  const _FullscreenLyric({required this.line, required this.style});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Text(
        line?.text ?? '',
        key: ValueKey<String?>(line?.text),
        textAlign: TextAlign.center,
        maxLines: 3,
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
    return Center(
      child: Text(
        '当前歌曲没有可用歌词',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppColors.textTertiary,
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
    final value = state.position.inMilliseconds.toDouble().clamp(0.0, max);

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
                : (next) =>
                    onSeek(Duration(milliseconds: next.round())),
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
    final playSize = compact ? 38.0 : 52.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: '上一首 / 回到开头',
          onPressed: canPrevious ? onPrevious : null,
          icon: const Icon(Icons.skip_previous_rounded),
          iconSize: compact ? 24 : 30,
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
        IconButton(
          tooltip: '下一首',
          onPressed: canNext ? onNext : null,
          icon: const Icon(Icons.skip_next_rounded),
          iconSize: compact ? 24 : 30,
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

  const _AudioSourceSelector({
    required this.availableSources,
    required this.currentSource,
    required this.onSourceChanged,
    this.compact = false,
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
          label: Text(_sourceLabel(source)),
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
            label: const Text('全屏 KTV'),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
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

String _sourceLabel(AudioSourceType source) {
  return switch (source) {
    AudioSourceType.original => '原声',
    AudioSourceType.instrumental => '伴奏',
    AudioSourceType.vocals => '人声',
  };
}

String _formatTime(Duration value) {
  final minutes = value.inMinutes.toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
