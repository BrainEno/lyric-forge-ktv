import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../core/layout/app_capabilities.dart';
import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_error_state.dart';
import '../../../../core/widgets/app_loading_state.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../../project/domain/models/automatic_accompaniment.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/lyric_timing.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/playback_session_service.dart';
import '../../domain/models/ktv_backing_mode.dart';
import '../playback_screen_dependencies.dart';
import '../widgets/ktv_entry_sheet.dart';
import '../widgets/lyrics_source_sheet.dart';
import '../widgets/project_player_transport.dart';
import '../widgets/player_lyrics_pane.dart';
import '../widgets/reference_lyrics_view.dart';
import '../widgets/song_lyrics_acquisition.dart';
import '../widgets/song_lyrics_preview_dialog.dart';
import 'immersive_ktv_screen.dart';

class PlayerScreen extends StatefulWidget {
  final String projectId;

  /// Supplied by the routing table (`lib/app/playback_assembly.dart`).
  final PlayerScreenDependencies dependencies;

  const PlayerScreen({
    super.key,
    required this.projectId,
    required this.dependencies,
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

  /// What the queue said about this project's song when it was last read:
  /// title, artist and lyric flag.
  String? _itemLabel;

  @override
  void initState() {
    super.initState();
    final dependencies = widget.dependencies;
    _repository = dependencies.projectRepository;
    _audioService = dependencies.audioPlayer;
    _playbackSession = dependencies.playbackSession;
    _activeProjectId = widget.projectId;
    final current = _playbackSession.currentState.currentItem;
    _itemLabel = current?.projectId == _activeProjectId
        ? _labelFor(current)
        : null;
    _loadProject(_activeProjectId);
    _sessionSubscription = _playbackSession.stateStream.listen(
      _handleSessionChange,
    );
  }

  void _loadProject(String projectId) {
    _projectFuture = _repository.getProjectById(projectId);
  }

  /// Reloads when the queue moves to another project, and when the song of
  /// this one was renamed or got or lost lyrics elsewhere — 歌曲信息 edited
  /// in the library renames the project too (D-059), and this page used to
  /// keep showing what it read when it opened.
  void _handleSessionChange(PlaybackSessionState state) {
    final item = state.currentItem;
    final projectId = item?.projectId;
    if (!mounted || projectId == null) return;
    final label = _labelFor(item);
    if (projectId == _activeProjectId) {
      final previous = _itemLabel;
      _itemLabel = label;
      // The first sight of the song (this page just started it) is what
      // was loaded already.
      if (previous == null || label == previous) return;
      setState(() => _loadProject(projectId));
      return;
    }

    setState(() {
      _activeProjectId = projectId;
      _itemLabel = label;
      _loadProject(projectId);
    });
  }

  static String? _labelFor(PlaybackItem? item) => item == null
      ? null
      : [
          item.title,
          item.artist ?? '',
          item.hasLyrics ? '1' : '0',
        ].join('\u0000');

  Future<void> _openLyricEditor(ProjectManifest project) async {
    await Navigator.pushNamed(context, Routes.lyricEditorPath(project.id));
    if (!mounted || _activeProjectId != project.id) return;
    setState(() => _loadProject(project.id));
  }

  /// 添加歌词 for a project without timed lyrics (D-054): fetch, paste or
  /// import, then reload so the pane shows what was saved.
  Future<void> _addLyrics(
    ProjectManifest project,
    LyricsSourceChoice? choice,
  ) async {
    final importer = widget.dependencies.lyricsImporter;
    if (importer == null) return;
    final saved = await addLyricsToProject(
      context,
      project: project,
      repository: _repository,
      importer: importer,
      lookup: widget.dependencies.songLyricsLookup,
      playback: _previewPlayback(project),
      choice: choice,
      tagReader: widget.dependencies.songTagReader,
    );
    if (!mounted || saved == null || _activeProjectId != project.id) return;
    setState(() => _loadProject(project.id));
  }

  /// The timing preview follows and seeks this player; the song is already
  /// the one playing, so there is nothing to start.
  SongLyricsPreviewPlayback _previewPlayback(ProjectManifest project) {
    return SongLyricsPreviewPlayback(
      positionStream: _audioService.positionStream,
      currentPosition: () => _audioService.currentState.position,
      isCurrentSong: () =>
          _playbackSession.currentState.currentItem?.projectId == project.id,
      seek: _playbackSession.seek,
      togglePlayPause: _playbackSession.togglePlayPause,
    );
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
          preferredSource: audioAsset.preferredProjectPlaybackSource,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法切换到该音源：$error')));
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
        // A reload of the same project keeps the page up instead of
        // flashing the loading screen.
        final reloading =
            snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data?.id == _activeProjectId;
        if (snapshot.connectionState == ConnectionState.waiting && !reloading) {
          return const _LoadingState();
        }

        if (snapshot.hasError || snapshot.data == null) {
          return _ErrorState(
            onRetry: () => setState(() => _loadProject(_activeProjectId)),
          );
        }

        final project = snapshot.data!;
        final canAddLyrics =
            widget.dependencies.lyricsImporter != null &&
            project.audioAsset != null &&
            !project.hasTimedLyrics;
        return _PlayerContent(
          key: ValueKey('player_${project.id}'),
          project: project,
          repository: _repository,
          audioService: _audioService,
          playbackSession: _playbackSession,
          immersiveKtv: widget.dependencies.immersiveKtv,
          onInitialize: () => _initializeAudio(project),
          // A phone has no lyric editor (D-058).
          onOpenLyricEditor: AppCapabilities.lyricWorkbench
              ? () => _openLyricEditor(project)
              : null,
          onAddLyrics: canAddLyrics
              ? (choice) => _addLyrics(project, choice)
              : null,
          onlineLyricsAvailable: widget.dependencies.songLyricsLookup != null,
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
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: AppLoadingState(message: '正在准备播放器'),
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
      body: AppErrorState(
        title: '加载播放器失败',
        message: '工程或音频暂时无法读取，可以重新加载一次。',
        onRetry: onRetry,
      ),
    );
  }
}

class _PlayerContent extends StatefulWidget {
  final ProjectManifest project;
  final ProjectRepository repository;
  final AudioPlayerService audioService;
  final PlaybackSessionService playbackSession;
  final ImmersiveKtvDependencies immersiveKtv;
  final VoidCallback onInitialize;
  final Future<void> Function()? onOpenLyricEditor;

  /// Opens 添加歌词; null when the project already has timed lyrics or the
  /// app has no importer. A null choice asks the user where from.
  final ValueChanged<LyricsSourceChoice?>? onAddLyrics;
  final bool onlineLyricsAvailable;
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
    required this.immersiveKtv,
    required this.onInitialize,
    required this.onOpenLyricEditor,
    required this.onAddLyrics,
    required this.onlineLyricsAvailable,
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
    final document = widget.project.lyricDocument;
    if (document == null || document.isUntimed) return;
    widget.onSeek(document.effectiveStart(line));
  }

  Future<void> _enterKtv() async {
    final document = widget.project.lyricDocument;
    final audioAsset = _audioAssetForSession(
      widget.project,
      widget.playbackSession.currentState,
    );
    // Reference lyrics have no timing to sing to (D-054).
    if (document == null || !document.isTimed || audioAsset == null) {
      return;
    }

    final openedItem = widget.playbackSession.currentState.currentItem;
    bool isSameItem(PlaybackItem? item) =>
        openedItem != null &&
        openedItem.projectId == widget.project.id &&
        !openedItem.isRemoteStream &&
        item != null &&
        item.id == openedItem.id &&
        item.projectId == openedItem.projectId &&
        !item.isRemoteStream;

    final selection = await showModalBottomSheet<KtvEntrySelection>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: AppColors.bgElevated,
      builder: (context) => StreamBuilder<PlaybackSessionState>(
        stream: widget.playbackSession.stateStream,
        initialData: widget.playbackSession.currentState,
        builder: (context, sessionSnapshot) {
          final item = widget.playbackSession.currentState.currentItem;
          final matches = isSameItem(item);
          final displayedAsset = matches ? item!.audioAsset : audioAsset;
          return StreamBuilder<PlaybackState>(
            stream: widget.audioService.stateStream,
            initialData: widget.audioService.currentState,
            builder: (context, playbackSnapshot) => KtvEntrySheet(
              audioAsset: displayedAsset,
              currentSource: playbackSnapshot.data?.currentSource,
              sessionMatches: matches,
            ),
          );
        },
      ),
    );
    if (!mounted || selection == null) return;

    bool selectionIsCurrent() {
      final item = widget.playbackSession.currentState.currentItem;
      if (!isSameItem(item)) return false;
      return item!.audioAsset.getPathForSource(selection.mode.source) ==
          selection.sourcePath;
    }

    if (!selectionIsCurrent()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('播放项或音轨已变化，请重新打开 KTV。')));
      return;
    }

    try {
      if (widget.audioService.currentState.currentSource !=
          selection.mode.source) {
        await widget.audioService.switchSource(selection.mode.source);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法进入 KTV：$error')));
      return;
    }

    if (!mounted) return;
    if (!selectionIsCurrent()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('播放项或音轨已变化，请重新打开 KTV。')));
      return;
    }
    setState(() => _ktvMode = true);
    await _openFullScreenKtv();
  }

  Future<void> _openFullScreenKtv() async {
    final document = widget.project.lyricDocument;
    if (document == null || !document.isTimed) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ImmersiveKtvScreen(
          initialProjectId: widget.project.id,
          dependencies: widget.immersiveKtv,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final document = widget.project.lyricDocument;
    final timedLyrics = document?.isTimed ?? false;

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
                    : AppCapabilities.lyricWorkbench
                    ? '本地工程'
                    : '本地歌曲',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: AppColors.textTertiary),
              ),
          ],
        ),
        actions: [
          // The project page is part of the desktop workbench (D-058).
          if (AppCapabilities.lyricWorkbench)
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
          if (timedLyrics)
            SizedBox(
              width: spec.minimumInteractiveExtent,
              height: spec.minimumInteractiveExtent,
              child: IconButton.filledTonal(
                tooltip: '进入 KTV',
                onPressed: _enterKtv,
                icon: const Icon(Icons.mic_rounded),
              ),
            ),
          if (widget.onOpenLyricEditor != null)
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
                final currentLyricIndex = document?.activeLineIndex(
                  playback.position,
                );

                return _PlayerWorkspace(
                  project: widget.project,
                  document: document,
                  playback: playback,
                  session: session,
                  ktvMode: _ktvMode && timedLyrics,
                  currentLyricIndex: currentLyricIndex,
                  onPlayPause: widget.onPlayPause,
                  onSeek: widget.onSeek,
                  onLyricTap: _seekToLine,
                  onSwitchSource: widget.onSwitchSource,
                  onSkipPrevious: widget.onSkipPrevious,
                  onSkipNext: widget.onSkipNext,
                  onModeChanged: (ktvMode) =>
                      setState(() => _ktvMode = ktvMode && timedLyrics),
                  onOpenFullScreenKtv: timedLyrics ? _openFullScreenKtv : null,
                  onOpenLyricEditor: widget.onOpenLyricEditor,
                  onAddLyrics: widget.onAddLyrics,
                  onlineLyricsAvailable: widget.onlineLyricsAvailable,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

AudioAsset? _audioAssetForSession(
  ProjectManifest project,
  PlaybackSessionState session,
) {
  final item = session.currentItem;
  return item != null && item.projectId == project.id
      ? item.audioAsset
      : project.audioAsset;
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
  final Future<void> Function()? onOpenLyricEditor;
  final ValueChanged<LyricsSourceChoice?>? onAddLyrics;
  final bool onlineLyricsAvailable;

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
    required this.onOpenLyricEditor,
    required this.onAddLyrics,
    required this.onlineLyricsAvailable,
  });

  @override
  Widget build(BuildContext context) {
    final lyrics = document?.lines ?? const <LyricLine>[];
    final pane = PlayerLyricsPane(
      lyrics: lyrics,
      untimed: document?.isUntimed ?? false,
      sourceLabel: document == null
          ? null
          : lyricSourceLabel(document!.metadata),
      ktvMode: ktvMode,
      currentIndex: currentLyricIndex,
      onLyricTap: onLyricTap,
      onOpenFullScreenKtv: onOpenFullScreenKtv,
      onOpenLyricEditor: onOpenLyricEditor,
      onAddLyrics: onAddLyrics,
      onlineLyricsAvailable: onlineLyricsAvailable,
    );
    final availableSources =
        _audioAssetForSession(project, session)?.availableSources ??
        const <AudioSourceType>[];

    final transport = ProjectPlayerTransportState(
      project: project,
      playback: playback,
      session: session,
      availableSources: availableSources,
      ktvMode: ktvMode,
    );
    final actions = ProjectPlayerTransportActions(
      onPlayPause: onPlayPause,
      onSeek: onSeek,
      onSwitchSource: onSwitchSource,
      onSkipPrevious: onSkipPrevious,
      onSkipNext: onSkipNext,
      onModeChanged: onModeChanged,
      onOpenFullScreenKtv: onOpenFullScreenKtv,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final spec = AppResponsive.fromConstraints(constraints);
        if (spec.supportsTwoPane) {
          return Row(
            children: [
              SizedBox(
                width: spec.sidePanelWidth,
                child: ProjectPlayerTransport(
                  state: transport,
                  actions: actions,
                  layout: ProjectPlayerTransportLayout.sidePane,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: pane),
            ],
          );
        }

        return Column(
          children: [
            ProjectPlayerTransport(
              state: transport,
              actions: actions,
              // Short-ness follows the window, as it always has; the side
              // pane is already ruled out by this box's width.
              layout: AppResponsive.of(context).isShort
                  ? ProjectPlayerTransportLayout.shortHeader
                  : ProjectPlayerTransportLayout.header,
            ),
            const Divider(height: 1),
            Expanded(child: pane),
          ],
        );
      },
    );
  }
}
