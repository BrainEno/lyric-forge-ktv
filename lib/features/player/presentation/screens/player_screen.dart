import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../core/layout/app_capabilities.dart';
import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_error_state.dart';
import '../../../../core/widgets/app_loading_state.dart';
import '../../../../core/widgets/app_tap_target.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../../project/domain/models/lyric_document.dart';
import '../../../project/domain/models/lyric_timing.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/ktv_backing_mode.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/audio_player_service.dart';
import '../../domain/services/playback_session_service.dart';
import '../playback_screen_dependencies.dart';
import '../widgets/ktv_entry_sheet.dart';
import '../widgets/lyrics_source_sheet.dart';
import '../widgets/player_lyric_semantics.dart';
import '../widgets/project_player_transport.dart';
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
    final pane = _LyricsPane(
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

class _LyricsPane extends StatelessWidget {
  final List<LyricLine> lyrics;

  /// Reference lyrics: shown statically, never followed or tapped to seek.
  final bool untimed;
  final String? sourceLabel;
  final bool ktvMode;
  final int? currentIndex;
  final ValueChanged<LyricLine> onLyricTap;
  final VoidCallback? onOpenFullScreenKtv;
  final Future<void> Function()? onOpenLyricEditor;
  final ValueChanged<LyricsSourceChoice?>? onAddLyrics;
  final bool onlineLyricsAvailable;

  const _LyricsPane({
    required this.lyrics,
    required this.untimed,
    required this.sourceLabel,
    required this.ktvMode,
    required this.currentIndex,
    required this.onLyricTap,
    required this.onOpenFullScreenKtv,
    required this.onOpenLyricEditor,
    required this.onAddLyrics,
    required this.onlineLyricsAvailable,
  });

  @override
  Widget build(BuildContext context) {
    final addLyrics = onAddLyrics;
    if (lyrics.isEmpty) {
      return _NoLyricsState(
        onAddLyrics: addLyrics,
        onlineLyricsAvailable: onlineLyricsAvailable,
      );
    }
    if (untimed) {
      return ReferenceLyricsView(
        lines: lyrics,
        sourceLabel: sourceLabel,
        onOpenEditor: onOpenLyricEditor,
        onFindTimedLyrics: addLyrics != null && onlineLyricsAvailable
            ? () => addLyrics(LyricsSourceChoice.online)
            : null,
      );
    }
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
                  style:
                      (spec.isCompact || spec.isShort
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
          child: AppTapTarget(
            label: PlayerLyricSemantics.listRow(
              time: _formatTime(line.startTime),
              text: line.text,
              chorus: line.isChorus,
              current: current,
            ),
            hint: PlayerLyricSemantics.seekHint,
            selected: current,
            onTap: () => widget.onLyricTap(line),
            child: InkWell(
              onTap: () => widget.onLyricTap(line),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
              child: Container(
                constraints: BoxConstraints(
                  minHeight: spec.minimumInteractiveExtent,
                ),
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
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: current
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                              fontWeight: current
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              height: spec.isShort ? 1.3 : 1.45,
                            ),
                      ),
                    ),
                    if (line.isChorus && !spec.isCompact)
                      Padding(
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

    final previousStyle =
        (spec.isShort || spec.isCompact
                ? Theme.of(context).textTheme.bodyLarge
                : Theme.of(context).textTheme.titleMedium)
            ?.copyWith(color: AppColors.textTertiary);
    final currentStyle =
        (spec.isShort || spec.isCompact
                ? Theme.of(context).textTheme.headlineSmall
                : Theme.of(context).textTheme.headlineMedium)
            ?.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w900,
              height: 1.3,
            );
    final nextStyle =
        (spec.isShort || spec.isCompact
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
              role: PlayerFocusLyricRole.previous,
              style: previousStyle,
              onTap: previous == null ? null : () => onLyricTap(previous),
            ),
            SizedBox(height: gap),
            _FocusLyricLine(
              line: current,
              role: PlayerFocusLyricRole.current,
              style: currentStyle,
              onTap: () => onLyricTap(current),
            ),
            SizedBox(height: gap),
            _FocusLyricLine(
              line: next,
              role: PlayerFocusLyricRole.next,
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
  final PlayerFocusLyricRole role;
  final TextStyle? style;
  final VoidCallback? onTap;

  const _FocusLyricLine({
    required this.line,
    required this.role,
    required this.style,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    if (line == null) {
      return SizedBox(height: spec.isShort ? 18 : 32);
    }
    return AppTapTarget(
      label: PlayerLyricSemantics.focusLine(role, line!.text),
      hint: onTap == null ? null : PlayerLyricSemantics.seekHint,
      selected: role == PlayerFocusLyricRole.current,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        child: Container(
          constraints: BoxConstraints(minHeight: spec.minimumInteractiveExtent),
          padding: EdgeInsets.all(spec.isShort ? 6 : AppSpacing.sm),
          child: Text(line!.text, textAlign: TextAlign.center, style: style),
        ),
      ),
    );
  }
}

class _NoLyricsState extends StatelessWidget {
  final ValueChanged<LyricsSourceChoice?>? onAddLyrics;
  final bool onlineLyricsAvailable;

  const _NoLyricsState({
    required this.onAddLyrics,
    required this.onlineLyricsAvailable,
  });

  @override
  Widget build(BuildContext context) {
    final spec = AppResponsive.of(context);
    final addLyrics = onAddLyrics;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(spec.pageGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lyrics_outlined,
              size: 52,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              AppCapabilities.lyricWorkbench ? '这个工程还没有歌词' : '这首歌还没有歌词',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              addLyrics == null
                  ? '可以继续普通播放，有时间轴的歌词才能进入 KTV 模式。'
                  : '可以联网获取歌词，或粘贴纯文本歌词作为参考（静态显示、手动滚动）；'
                        '有时间轴的歌词才能进入 KTV 模式。',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
            ),
            if (addLyrics != null) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (onlineLyricsAvailable)
                    FilledButton.icon(
                      key: const ValueKey('player-fetch-lyrics'),
                      onPressed: () => addLyrics(LyricsSourceChoice.online),
                      icon: const Icon(Icons.travel_explore_rounded),
                      label: const Text('联网获取歌词'),
                    ),
                  OutlinedButton.icon(
                    key: const ValueKey('player-paste-lyrics'),
                    onPressed: () => addLyrics(LyricsSourceChoice.paste),
                    icon: const Icon(Icons.content_paste_rounded),
                    label: const Text('粘贴歌词'),
                  ),
                  TextButton.icon(
                    key: const ValueKey('player-import-lyrics-file'),
                    onPressed: () => addLyrics(LyricsSourceChoice.file),
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text('导入歌词文件'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatTime(Duration value) {
  final minutes = value.inMinutes.toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
