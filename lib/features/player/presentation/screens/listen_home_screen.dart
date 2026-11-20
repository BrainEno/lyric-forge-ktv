import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/diagnostics/best_effort.dart';
import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/playback_destination.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/navigation/transfer_entry.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_artwork.dart';
import '../../../../core/widgets/app_brand_mark.dart';
import '../../../../core/widgets/app_button_spinner.dart';
import '../../../../core/widgets/app_song_row.dart';
import '../../../../core/widgets/app_tap_target.dart';
import '../../../../core/widgets/app_vinyl_disc.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/local_media_library_entry.dart';
import '../../domain/models/play_history.dart';
import '../../domain/models/playback_state.dart';
import '../../domain/services/playback_session_service.dart';
import '../local_library_dependencies.dart';
import '../widgets/local_song_lyrics_import_action.dart';
import '../widgets/local_store_integrity_banner.dart';
import '../widgets/now_playing_listener.dart';
import '../widgets/playback_action_feedback.dart';
import '../widgets/playback_artwork.dart';
import '../widgets/player_bar_semantics.dart';
import '../widgets/seekable_progress_bar.dart';

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
///  * a nudge to import lyrics when the song playing has none — lyric import
///    is the phone's second job, offered where it is needed;
///  * 最近播放, as song rows that mark the one playing;
///  * shortcuts into the five library sections.
///
/// The mini player bar steps aside on this page (see `AppChrome`): the hero
/// already is the player.
class ListenHomeScreen extends StatefulWidget {
  const ListenHomeScreen({super.key, required this.dependencies, this.random});

  final LocalLibraryDependencies dependencies;

  /// Order of 随机播放; null for a fresh random order. Tests pass a seeded
  /// one.
  final math.Random? random;

  static const String title = '听歌';
  static const String recentTitle = '最近播放';
  static const String libraryTitle = '音乐库';
  static const String playAllLabel = '播放全部';
  static const String shuffleLabel = '随机播放';
  static const String openLibraryLabel = '打开音乐库';
  static const String idleTitle = '放一张唱片吧';
  static const String noSongsMessage = '音乐库里还没有可以播放的歌曲。';
  static const String importLyricsLabel = '导入歌词';
  static const String openPlayerHint = PlayerBarSemantics.openHint;

  static const Key heroKey = ValueKey('listen-home:hero');
  static const Key playAllKey = ValueKey('listen-home:play-all');
  static const Key shuffleKey = ValueKey('listen-home:shuffle');
  static const Key lyricsNudgeKey = ValueKey('listen-home:lyrics-nudge');

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

  /// The title of [entry]: its tag, else its file name without extension.
  static String titleOf(LocalMediaLibraryEntry entry) {
    final tagged = entry.embeddedTitle?.trim();
    if (tagged != null && tagged.isNotEmpty) return tagged;
    final name = entry.sourcePath.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
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
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = describeLocalLibraryError(error);
      });
    }
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
                  cover: current == null
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
                          _HomeHeader(
                            songCount: _availableCount,
                            loading: _loading,
                            onSearch: () => _open(Routes.library),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          KeyedSubtree(
                            key: ListenHomeScreen.heroKey,
                            child: current == null
                                ? _IdleHero(
                                    hasSongs: hasSongs,
                                    songCount: _availableCount,
                                    onShuffle: () =>
                                        _playLibrary(shuffle: true),
                                    onOpenLibrary: () => _open(Routes.library),
                                  )
                                : _PlayingHero(
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
                  child: _QuickPlayRow(
                    enabled: hasSongs,
                    onPlayAll: () => _playLibrary(shuffle: false),
                    onShuffle: () => _playLibrary(shuffle: true),
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
                    child: _LyricsNudge(
                      key: ListenHomeScreen.lyricsNudgeKey,
                      title: current.title,
                      onImport: () => importLyricsForLocalPlaybackItem(
                        context,
                        current,
                        widget.dependencies.lyricsImport,
                      ),
                    ),
                  ),
                _SectionTitle(
                  ListenHomeScreen.recentTitle,
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    layout.sectionGap,
                    gutter,
                    AppSpacing.sm,
                  ),
                ),
                if (_recent.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: gutter),
                    child: Text(
                      _loading ? '正在读取…' : '播放过的歌曲会出现在这里。',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  )
                else
                  for (final history in _recent)
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: math.max(0, gutter - AppSpacing.sm),
                      ),
                      child: AppSongRow(
                        key: ValueKey('listen-home:recent:${history.id}'),
                        title: history.name,
                        subtitle: _recentSubtitle(history),
                        artwork: AppArtwork(
                          path: history.artworkPath,
                          borderRadius: AppArtwork.rowRadius,
                        ),
                        playback: nowPlaying.playbackForPath(history.filePath),
                        semanticHint: '继续播放',
                        onTap: () => _resume(history),
                      ),
                    ),
                _SectionTitle(
                  ListenHomeScreen.libraryTitle,
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    layout.sectionGap,
                    gutter,
                    AppSpacing.sm,
                  ),
                ),
                _LibraryShortcuts(
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

  static String _recentSubtitle(PlayHistory history) {
    final artist = history.artist?.trim();
    final position = history.lastPosition;
    return [
      artist == null || artist.isEmpty ? '本地音乐' : artist,
      if (position != null && position > Duration.zero)
        '听到 ${_clock(position)}',
    ].join(' · ');
  }

  static String _clock(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// The page title, the library size and a search shortcut.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.songCount,
    required this.loading,
    required this.onSearch,
  });

  final int songCount;
  final bool loading;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        const AppBrandMark(size: 22, semanticLabel: ''),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  ListenHomeScreen.title,
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                loading ? '离线播放' : '离线播放 · $songCount 首本地歌曲',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '搜索音乐库',
          onPressed: onSearch,
          icon: const Icon(Icons.search_rounded),
        ),
      ],
    );
  }
}

/// Edge of the hero record on a page [width] wide: most of a phone's width,
/// capped so it does not fill a tablet.
double _discSizeFor(double width) => math.min(width * 0.62, 280);

/// The record that is on, its title and its transport.
class _PlayingHero extends StatelessWidget {
  const _PlayingHero({
    required this.item,
    required this.isPlaying,
    required this.dependencies,
    required this.onOpen,
  });

  final PlaybackItem item;
  final bool isPlaying;
  final LocalLibraryDependencies dependencies;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final session = dependencies.playbackSession;
    final audio = dependencies.audioPlayer;
    final subtitle = PlayerBarSemantics.subtitleFor(
      item,
      projectLabel: '歌词工程',
      remoteLabel: '桌面音乐库',
      localLabel: '本地音乐',
    );
    final discSize = _discSizeFor(MediaQuery.sizeOf(context).width);

    return Column(
      children: [
        AppTapTarget(
          label: PlayerBarSemantics.nowPlaying(item.title, subtitle),
          hint: ListenHomeScreen.openPlayerHint,
          onTap: onOpen,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onOpen,
            child: AppVinylDisc(
              size: discSize,
              spinning: isPlaying,
              glow: true,
              label: PlaybackArtwork(item: item, borderRadius: 0),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        StreamBuilder<PlaybackState>(
          stream: audio.stateStream,
          initialData: audio.currentState,
          builder: (context, snapshot) {
            final playback = snapshot.data ?? const PlaybackState.idle();
            final busy = PlayerBarSemantics.isBusy(playback);
            final state = session.currentState;
            return Column(
              children: [
                SeekableProgressBar(
                  state: playback,
                  onSeek: session.seek,
                  compact: true,
                  activeColor: AppColors.vinylBrass,
                  thumbColor: AppColors.vinylBrass,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: '上一首',
                      iconSize: AppSpacing.iconSizeLarge,
                      onPressed: state.canSkipPrevious
                          ? () => runPlaybackActionWithFeedback(
                              context,
                              session.skipPrevious,
                            )
                          : null,
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    SizedBox.square(
                      dimension: 68,
                      child: IconButton(
                        tooltip: PlayerBarSemantics.playPause(playback),
                        iconSize: AppSpacing.iconSizeLarge,
                        style: AppTheme.vinylPlayDisc,
                        onPressed: busy
                            ? null
                            : () => runPlaybackActionWithFeedback(
                                context,
                                session.togglePlayPause,
                              ),
                        icon: busy
                            ? const AppButtonSpinner(size: 24)
                            : Icon(
                                playback.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    IconButton(
                      tooltip: '下一首',
                      iconSize: AppSpacing.iconSizeLarge,
                      onPressed: state.canSkipNext
                          ? () => runPlaybackActionWithFeedback(
                              context,
                              session.skipNext,
                            )
                          : null,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// A still record and a way to start, when nothing is loaded.
class _IdleHero extends StatelessWidget {
  const _IdleHero({
    required this.hasSongs,
    required this.songCount,
    required this.onShuffle,
    required this.onOpenLibrary,
  });

  final bool hasSongs;
  final int songCount;
  final VoidCallback onShuffle;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final layout = AppResponsive.of(context);
    final minimum = Size(0, layout.minimumInteractiveExtent);
    final discSize = _discSizeFor(MediaQuery.sizeOf(context).width) * 0.8;

    return Column(
      children: [
        AppVinylDisc(size: discSize, glow: true),
        const SizedBox(height: AppSpacing.lg),
        Text(
          ListenHomeScreen.idleTitle,
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          hasSongs
              ? '从 $songCount 首本地歌曲里挑一首，或者随便听听。'
              : '先把歌曲放进音乐库：添加手机里的音乐文件夹，或从电脑传过来。',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: hasSongs
              ? [
                  FilledButton.icon(
                    style: AppTheme.vinylFilled.copyWith(
                      minimumSize: WidgetStatePropertyAll(minimum),
                    ),
                    onPressed: onShuffle,
                    icon: const Icon(Icons.shuffle_rounded),
                    label: const Text(ListenHomeScreen.shuffleLabel),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: minimum),
                    onPressed: onOpenLibrary,
                    icon: const Icon(Icons.library_music_rounded),
                    label: const Text(ListenHomeScreen.openLibraryLabel),
                  ),
                ]
              : [
                  FilledButton.icon(
                    style: AppTheme.vinylFilled.copyWith(
                      minimumSize: WidgetStatePropertyAll(minimum),
                    ),
                    onPressed: onOpenLibrary,
                    icon: const Icon(Icons.library_music_rounded),
                    label: const Text(ListenHomeScreen.openLibraryLabel),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: minimum),
                    onPressed: () =>
                        TransferEntry.open(context, desktop: false),
                    icon: const Icon(TransferEntry.icon),
                    label: const Text('从电脑传歌'),
                  ),
                ],
        ),
      ],
    );
  }
}

/// 播放全部 and 随机播放 over the whole library.
class _QuickPlayRow extends StatelessWidget {
  const _QuickPlayRow({
    required this.enabled,
    required this.onPlayAll,
    required this.onShuffle,
  });

  final bool enabled;
  final VoidCallback onPlayAll;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final height = math.max(
      52.0,
      AppResponsive.of(context).minimumInteractiveExtent,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusCircular),
    );
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            key: ListenHomeScreen.playAllKey,
            style: AppTheme.vinylFilled.copyWith(
              minimumSize: WidgetStatePropertyAll(Size(0, height)),
              shape: WidgetStatePropertyAll(shape),
            ),
            onPressed: enabled ? onPlayAll : null,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text(ListenHomeScreen.playAllLabel),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: FilledButton.tonalIcon(
            key: ListenHomeScreen.shuffleKey,
            style: FilledButton.styleFrom(
              minimumSize: Size(0, height),
              shape: shape,
            ),
            onPressed: enabled ? onShuffle : null,
            icon: const Icon(Icons.shuffle_rounded),
            label: const Text(ListenHomeScreen.shuffleLabel),
          ),
        ),
      ],
    );
  }
}

/// Offers lyric import for the song playing when it has none.
class _LyricsNudge extends StatelessWidget {
  const _LyricsNudge({super.key, required this.title, required this.onImport});

  final String title;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: AppColors.vinylSurface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(Icons.lyrics_rounded, color: AppColors.vinylBrass),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '「$title」还没有歌词',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '导入 LRC 或文本歌词，播放时跟着滚动。',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onImport,
              child: const Text(ListenHomeScreen.importLyricsLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {required this.padding});

  final String title;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

/// One library section the home can jump to.
class _Shortcut {
  const _Shortcut(this.label, this.icon, this.route);

  final String label;
  final IconData icon;
  final String route;
}

/// The five library sections as a row of record-sleeve tiles.
class _LibraryShortcuts extends StatelessWidget {
  const _LibraryShortcuts({
    required this.gutter,
    required this.songCount,
    required this.onOpen,
  });

  final double gutter;
  final int songCount;
  final ValueChanged<String> onOpen;

  static const List<_Shortcut> shortcuts = [
    _Shortcut('歌曲', Icons.music_note_rounded, Routes.library),
    _Shortcut('艺人', Icons.person_rounded, Routes.libraryArtists),
    _Shortcut('专辑', Icons.album_rounded, Routes.libraryAlbums),
    _Shortcut('收藏', Icons.favorite_rounded, Routes.collections),
    _Shortcut('歌单', Icons.queue_music_rounded, Routes.playlists),
  ];

  static const double tileWidth = 96;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: gutter),
        itemCount: shortcuts.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final shortcut = shortcuts[index];
          final caption = index == 0 ? '$songCount 首' : null;
          return SizedBox(
            width: tileWidth,
            child: AppTapTarget(
              label: AppTapTarget.join([shortcut.label, caption]),
              hint: '打开',
              onTap: () => onOpen(shortcut.route),
              child: Material(
                color: AppColors.bgElevated,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onOpen(shortcut.route),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.vinylSurfaceHigh,
                        ),
                        child: Icon(
                          shortcut.icon,
                          color: AppColors.vinylBrass,
                          size: AppSpacing.iconSizeMedium,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        shortcut.label,
                        style: textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (caption != null)
                        Text(
                          caption,
                          style: textTheme.labelSmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
