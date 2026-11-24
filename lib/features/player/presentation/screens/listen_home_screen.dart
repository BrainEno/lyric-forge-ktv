import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/diagnostics/best_effort.dart';
import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/app_chrome_scope.dart';
import '../../../../core/navigation/playback_destination.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/navigation/transfer_entry.dart';
import '../../../../core/onboarding/getting_started.dart';
import '../../../../core/onboarding/getting_started_card.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_vinyl_disc.dart';
import '../../../../core/widgets/undo_snack_bar.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/local_media_library_entry.dart';
import '../../domain/models/mobile_getting_started.dart';
import '../../domain/models/play_history.dart';
import '../../domain/services/media_file_names.dart';
import '../../domain/services/playback_session_service.dart';
import '../listen_home_guide.dart';
import '../local_library_dependencies.dart';
import '../widgets/listen_home_getting_started_card.dart';
import '../widgets/listen_home_hero.dart';
import '../widgets/listen_home_sections.dart';
import '../widgets/listen_home_text.dart';
import '../widgets/local_song_lyrics_import_action.dart';
import '../widgets/local_store_integrity_banner.dart';
import '../widgets/media_import_action.dart';
import '../widgets/now_playing_listener.dart';
import '../widgets/playback_action_feedback.dart';
import '../widgets/playback_artwork.dart';

/// The phone's home: 听歌 (decision D-041).
///
/// The phone is an offline player first, so it opens on the music, not on
/// the desktop's project dashboard. The page is, from the top:
///
///  * the record that is on — a turning vinyl with the cover as its label,
///    the title, a seek bar and the transport — over a wash of the cover's
///    own colours; or, with nothing playing, a still record and a way to
///    start;
///  * 播放全部 and 随机播放 over the whole local library;
///  * for someone new, the 开始使用 checklist (D-071);
///  * a nudge to import lyrics when the song playing has none — lyric import
///    is the phone's second job, offered where it is needed;
///  * 最近播放, as song rows that mark the one playing;
///  * shortcuts into the five library sections.
///
/// The mini player bar steps aside on this page (see `AppChrome`): the hero
/// already is the player.
///
/// This file holds the page's state and its order; the parts live in
/// `listen_home_hero.dart` and `listen_home_sections.dart`, the words and
/// keys in `listen_home_text.dart`, and the checklist's memory in
/// `listen_home_guide.dart`.
class ListenHomeScreen extends StatefulWidget {
  const ListenHomeScreen({super.key, required this.dependencies, this.random});

  final LocalLibraryDependencies dependencies;

  /// Order of 随机播放; null for a fresh random order. Tests pass a seeded
  /// one.
  final math.Random? random;

  // The words and keys live in [ListenHomeText] and [ListenHomeKeys]; these
  // names stay so callers and tests keep reading them off the page.
  static const String title = ListenHomeText.title;
  static const String recentTitle = ListenHomeText.recentTitle;
  static const String libraryTitle = ListenHomeText.libraryTitle;
  static const String playAllLabel = ListenHomeText.playAllLabel;
  static const String shuffleLabel = ListenHomeText.shuffleLabel;
  static const String openLibraryLabel = ListenHomeText.openLibraryLabel;
  static const String idleTitle = ListenHomeText.idleTitle;
  static const String noSongsMessage = ListenHomeText.noSongsMessage;
  static const String importLyricsLabel = ListenHomeText.importLyricsLabel;
  static const String openPlayerHint = ListenHomeText.openPlayerHint;

  static const Key heroKey = ListenHomeKeys.hero;
  static const Key playAllKey = ListenHomeKeys.playAll;
  static const Key shuffleKey = ListenHomeKeys.shuffle;
  static const Key lyricsNudgeKey = ListenHomeKeys.lyricsNudge;
  static const Key importKey = ListenHomeKeys.import;
  static const Key idleImportKey = ListenHomeKeys.idleImport;

  /// Recent plays shown.
  static const int recentLimit = 6;

  /// The queue 播放全部 starts: every song whose file is there, by title.
  static List<PlaybackItem> queueFrom(
    Iterable<LocalMediaLibraryEntry> entries, {
    bool Function(String path)? exists,
  }) {
    final fileExists = exists ?? (path) => File(path).existsSync();
    final songs = [
      for (final entry in entries)
        if (!entry.isMissing && fileExists(entry.sourcePath)) entry,
    ];
    songs.sort(
      (a, b) => titleOf(a).toLowerCase().compareTo(titleOf(b).toLowerCase()),
    );
    return [for (final entry in songs) itemFor(entry)];
  }

  /// Whether [item] has a cover of its own to blur behind the hero.
  static bool hasCover(PlaybackItem item) {
    final path = PlaybackArtwork.localPathOf(item);
    return (path != null && path.trim().isNotEmpty) ||
        PlaybackArtwork.remoteUriOf(item) != null;
  }

  /// The title of [entry]: its tag, else its file name without extension,
  /// and 未命名歌曲 for a name a picker made up (D-058).
  static String titleOf(LocalMediaLibraryEntry entry) {
    final tagged = entry.embeddedTitle?.trim();
    if (tagged != null && tagged.isNotEmpty) return tagged;
    return songTitleFromPath(entry.sourcePath);
  }

  /// The queue entry for [entry], keyed the way the library keys its songs
  /// so the session recognises the same song from either page. The session
  /// applies the user's own title, artist and cover on top.
  static PlaybackItem itemFor(LocalMediaLibraryEntry entry) => PlaybackItem(
    id: 'local:${entry.sourcePath}',
    title: titleOf(entry),
    artist: entry.embeddedArtist,
    artworkPath: entry.embeddedArtworkPath,
    audioAsset: AudioAsset(
      originalPath: entry.sourcePath,
      format: entry.format,
      thumbnailPath: entry.embeddedArtworkPath,
    ),
    preferredSource: AudioSourceType.original,
  );

  /// The newest play of each file, newest first, at most [limit].
  static List<PlayHistory> distinctRecent(
    Iterable<PlayHistory> histories, {
    int limit = recentLimit,
  }) {
    final sorted = histories.toList()
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    final seen = <String>{};
    return [
      for (final history in sorted)
        if (seen.add(NowPlaying.pathKey(history.filePath))) history,
    ].take(limit).toList(growable: false);
  }

  @override
  State<ListenHomeScreen> createState() => _ListenHomeScreenState();
}

class _ListenHomeScreenState extends State<ListenHomeScreen> {
  late final PlaybackSessionService _session;
  StreamSubscription<PlaybackSessionState>? _sessionChanges;
  String? _currentId;

  List<LocalMediaLibraryEntry> _entries = const [];
  List<PlayHistory> _recent = const [];
  bool _loading = true;
  String? _error;

  /// The 开始使用 checklist (D-071); null while it is hidden.
  MobileGettingStartedProgress? _guide;
  late final ListenHomeGuide _guideMemory = ListenHomeGuide(
    store: widget.dependencies.gettingStartedStore,
    readOverrides: widget.dependencies.metadataRepository.getAll,
  );

  @override
  void initState() {
    super.initState();
    _session = widget.dependencies.playbackSession;
    _currentId = _session.currentState.currentItem?.id;
    // A new song lands in the history when the previous one is saved, so
    // 最近播放 is read again whenever the song changes.
    _sessionChanges = _session.stateStream.listen((state) {
      final id = state.currentItem?.id;
      if (id == _currentId) return;
      _currentId = id;
      unawaited(_loadRecent());
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_sessionChanges?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final entries = await widget.dependencies.libraryRepository.getAll();
      final histories = await widget.dependencies.playHistoryRepository
          .getRecentPlayHistory(limit: 30);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _recent = ListenHomeScreen.distinctRecent(histories);
        _loading = false;
        _error = null;
      });
      await _loadGuide(histories);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = describeLocalLibraryError(error);
      });
    }
  }

  /// Reads the checklist and how far the user has got (D-071).
  Future<void> _loadGuide(List<PlayHistory> histories) async {
    final guide = await _guideMemory.load(
      entries: _entries,
      histories: histories,
    );
    if (mounted) setState(() => _guide = guide);
  }

  /// The close button: hides the card, with an undo and a pointer to 设置.
  Future<void> _dismissGuide() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _guide = null);
    await _guideMemory.remember(GettingStartedVisibility.dismissed);
    showUndoSnackBar(
      messenger,
      message: GettingStartedCardText.dismissedNotice,
      onUndo: () async {
        await _guideMemory.remember(GettingStartedVisibility.active);
        if (mounted) await _load();
        return null;
      },
    );
  }

  /// 收起 after all three steps.
  Future<void> _finishGuide() async {
    setState(() => _guide = null);
    await _guideMemory.remember(GettingStartedVisibility.completed);
  }

  /// 跟着歌词播放一首: plays the song and opens the page with its lyrics.
  Future<void> _playWithLyrics(PlaybackItem item) async {
    await runPlaybackActionWithFeedback(context, () => _session.playItem(item));
    if (mounted) _openNowPlaying();
  }

  /// Reads 最近播放 again. On failure the shelf keeps what it showed; a
  /// pull to refresh reports the error.
  Future<void> _loadRecent() =>
      bestEffort('ListenHome', 'refresh recent plays', () async {
        final histories = await widget.dependencies.playHistoryRepository
            .getRecentPlayHistory(limit: 30);
        if (!mounted) return;
        setState(() => _recent = ListenHomeScreen.distinctRecent(histories));
      });

  int get _availableCount => _entries.where((entry) => !entry.isMissing).length;

  Future<void> _playLibrary({required bool shuffle}) async {
    final queue = ListenHomeScreen.queueFrom(_entries);
    if (queue.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text(ListenHomeScreen.noSongsMessage)),
        );
      return;
    }
    if (shuffle) queue.shuffle(widget.random ?? math.Random());
    await runPlaybackActionWithFeedback(
      context,
      () => _session.setQueue(queue),
    );
  }

  Future<void> _resume(PlayHistory history) async {
    await Navigator.pushNamed(
      context,
      PlaybackDestination.localPlayer.routeName(),
      arguments: history,
    );
    await _loadRecent();
  }

  Future<void> _open(String route) async {
    await Navigator.pushNamed(context, route);
    if (mounted) await _load();
  }

  /// 导入音频或视频 (D-056), straight from the home page on a phone.
  Future<void> _importMedia() async {
    final mediaImport = widget.dependencies.mediaImport;
    if (mediaImport == null) return;
    final result = await runMediaImport(context, mediaImport);
    if (mounted && result != null && result.importedPaths.isNotEmpty) {
      await _load();
    }
  }

  void _openNowPlaying() {
    unawaited(Navigator.pushNamed(context, Routes.nowPlaying));
  }

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    final gutter = layout.pageGutter;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: NowPlayingListener(
        playbackSession: _session,
        audioPlayer: widget.dependencies.audioPlayer,
        builder: (context, nowPlaying) {
          final current = nowPlaying.item;
          final hasSongs = _availableCount > 0;
          final needsLyrics =
              current != null &&
              !current.isRemoteStream &&
              current.projectId == null &&
              !current.hasLyrics;

          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                AppCoverGlow(
                  // Only a real cover is blurred: the grey placeholder of a
                  // song without one turned the wash into a grey band
                  // (D-058).
                  cover: current == null || !ListenHomeScreen.hasCover(current)
                      ? null
                      : PlaybackArtwork(item: current, borderRadius: 0),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        gutter,
                        AppSpacing.md,
                        gutter,
                        AppSpacing.lg,
                      ),
                      child: Column(
                        children: [
                          ListenHomeHeader(
                            songCount: _availableCount,
                            loading: _loading,
                            // The global search when the app offers it
                            // (D-065): songs, playlists and lyrics at once.
                            onSearch:
                                AppChromeScope.searchOf(context) ??
                                () => _open(Routes.library),
                            searchesEverything:
                                AppChromeScope.searchOf(context) != null,
                            onImport: widget.dependencies.mediaImport == null
                                ? null
                                : _importMedia,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          KeyedSubtree(
                            key: ListenHomeScreen.heroKey,
                            child: current == null
                                ? ListenHomeIdleHero(
                                    hasSongs: hasSongs,
                                    songCount: _availableCount,
                                    onShuffle: () =>
                                        _playLibrary(shuffle: true),
                                    onOpenLibrary: () => _open(Routes.library),
                                    onImport:
                                        widget.dependencies.mediaImport == null
                                        ? null
                                        : _importMedia,
                                  )
                                : ListenHomePlayingHero(
                                    item: current,
                                    isPlaying: nowPlaying.isPlaying,
                                    dependencies: widget.dependencies,
                                    onOpen: _openNowPlaying,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(gutter, 0, gutter, gutter),
                    child: Text(
                      _error!,
                      style: TextStyle(color: AppColors.errorText),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: gutter),
                  child: ListenHomeQuickPlayRow(
                    enabled: hasSongs,
                    onPlayAll: () => _playLibrary(shuffle: false),
                    onShuffle: () => _playLibrary(shuffle: true),
                  ),
                ),
                if (_guide case final guide?)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      gutter,
                      AppSpacing.md,
                      gutter,
                      0,
                    ),
                    child: ListenHomeGettingStartedCard(
                      progress: guide.whilePlaying(current),
                      onImport: widget.dependencies.mediaImport == null
                          ? null
                          : _importMedia,
                      onOpenLibrary: () => _open(Routes.library),
                      onTransfer: () =>
                          TransferEntry.open(context, desktop: false),
                      onAddLyrics: () => _open(Routes.review),
                      onPlay: () {
                        final song = guide.lyricSong;
                        if (song != null) unawaited(_playWithLyrics(song));
                      },
                      onDismiss: _dismissGuide,
                      onFinish: _finishGuide,
                    ),
                  ),
                if (needsLyrics)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      gutter,
                      AppSpacing.md,
                      gutter,
                      0,
                    ),
                    child: ListenHomeLyricsNudge(
                      key: ListenHomeScreen.lyricsNudgeKey,
                      title: current.title,
                      onImport: () => importLyricsForLocalPlaybackItem(
                        context,
                        current,
                        widget.dependencies.lyricsImport,
                      ),
                    ),
                  ),
                ListenHomeSectionTitle(
                  ListenHomeText.recentTitle,
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    layout.sectionGap,
                    gutter,
                    AppSpacing.sm,
                  ),
                ),
                ListenHomeRecentShelf(
                  recent: _recent,
                  loading: _loading,
                  gutter: gutter,
                  nowPlaying: nowPlaying,
                  onResume: _resume,
                ),
                ListenHomeSectionTitle(
                  ListenHomeText.libraryTitle,
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    layout.sectionGap,
                    gutter,
                    AppSpacing.sm,
                  ),
                ),
                ListenHomeLibraryShortcuts(
                  gutter: gutter,
                  songCount: _availableCount,
                  onOpen: _open,
                ),
                SizedBox(height: layout.sectionGap),
              ],
            ),
          );
        },
      ),
    );
  }
}
