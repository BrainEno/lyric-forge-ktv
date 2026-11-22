import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/navigation/transfer_entry.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../../../core/widgets/app_artwork.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_loading_state.dart';
import '../../../../core/widgets/app_song_row.dart';
import '../../../project/domain/models/audio_asset.dart';
import '../../domain/models/local_media_library_entry.dart';
import '../../domain/models/local_media_metadata.dart';
import '../../domain/services/media_file_names.dart';
import '../../domain/services/playback_session_service.dart';
import '../local_library_dependencies.dart';
import '../widgets/local_song_lyrics_import_action.dart';
import '../widgets/local_store_integrity_banner.dart';

/// The phone's 歌词 page (decision D-058).
///
/// A phone cannot run the recognition models, so the page the desktop fills
/// with recognition projects and review queues is, on a phone, about giving
/// the songs on it lyrics: the songs still without lyrics first, each one tap
/// away from 联网获取歌词, a lyric file (LRC or TXT) or pasted plain text, and
/// the way to swap songs and lyric files with the computer.
class MobileLyricsScreen extends StatefulWidget {
  final LocalLibraryDependencies dependencies;

  const MobileLyricsScreen({super.key, required this.dependencies});

  static const String title = '歌词';
  static const String intro = '给手机里的歌曲配歌词：联网获取、导入 LRC / TXT 歌词文件，或直接粘贴纯文本歌词。';
  static const String transferTitle = '和电脑互传歌曲与歌词';
  static const String transferDetail =
      '连接电脑上的 Elysium Player，下载���曲和配好的歌词，或把手机里的歌传过去。';
  static const String missingTitle = '还没有歌词';
  static const String pairedTitle = '已有歌词';
  static const String allPairedMessage = '每首歌都有歌词了。';
  static const String addLyricsHint = '添加歌词';
  static const String playHint = '播放';

  static const Key transferKey = ValueKey('mobile-lyrics:transfer');
  static const Key missingHeaderKey = ValueKey('mobile-lyrics:missing');
  static const Key pairedHeaderKey = ValueKey('mobile-lyrics:paired');

  static String songKey(String path) => 'mobile-lyrics:song:$path';

  @override
  State<MobileLyricsScreen> createState() => _MobileLyricsScreenState();
}

/// One song of the page: its library entry and the user's overrides.
class MobileLyricsSong {
  final LocalMediaLibraryEntry entry;
  final LocalMediaMetadata? override;

  const MobileLyricsSong({required this.entry, this.override});

  String get path => entry.sourcePath;

  String get title {
    final tagged = entry.embeddedTitle?.trim();
    final fallback = tagged != null && tagged.isNotEmpty
        ? tagged
        : songTitleFromPath(entry.sourcePath);
    return override?.resolvedTitle(fallback) ?? fallback;
  }

  String? get artist =>
      override?.resolvedArtist(entry.embeddedArtist) ?? entry.embeddedArtist;

  String? get artworkPath =>
      override?.resolvedArtwork(entry.embeddedArtworkPath) ??
      entry.embeddedArtworkPath;

  bool get hasLyrics => override?.metadata['linkedProjectId'] is String;

  PlaybackItem get playbackItem => PlaybackItem(
    id: 'local:${entry.sourcePath}',
    title: title,
    artist: artist,
    artworkPath: artworkPath,
    hasLyrics: hasLyrics,
    audioAsset: AudioAsset(
      originalPath: entry.sourcePath,
      format: entry.format,
      thumbnailPath: artworkPath,
    ),
    preferredSource: AudioSourceType.original,
  );

  /// The songs of [entries] that can be played, sorted by title, with the
  /// override of each from [overrides].
  static List<MobileLyricsSong> from(
    Iterable<LocalMediaLibraryEntry> entries,
    Iterable<LocalMediaMetadata> overrides, {
    bool Function(String path)? exists,
  }) {
    final fileExists = exists ?? (path) => File(path).existsSync();
    final byPath = {for (final item in overrides) item.sourcePath: item};
    final songs = [
      for (final entry in entries)
        if (!entry.isMissing && fileExists(entry.sourcePath))
          MobileLyricsSong(entry: entry, override: byPath[entry.sourcePath]),
    ];
    songs.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return songs;
  }
}

class _MobileLyricsScreenState extends State<MobileLyricsScreen> {
  List<MobileLyricsSong> _songs = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final entries = await widget.dependencies.libraryRepository.getAll();
      final overrides = await widget.dependencies.metadataRepository.getAll();
      if (!mounted) return;
      setState(() {
        _songs = MobileLyricsSong.from(entries, overrides);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '音乐库加载失败：${describeLocalLibraryError(error)}';
      });
    }
  }

  Future<void> _addLyrics(MobileLyricsSong song) async {
    await importLyricsForLocalPlaybackItem(
      context,
      song.playbackItem,
      widget.dependencies.lyricsImport,
    );
    if (mounted) await _load();
  }

  Future<void> _play(MobileLyricsSong song) async {
    await widget.dependencies.playbackSession.playItem(song.playbackItem);
    if (!mounted) return;
    await Navigator.pushNamed(context, Routes.nowPlaying);
  }

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    final gutter = layout.pageGutter;
    final textTheme = Theme.of(context).textTheme;
    final missing = [
      for (final song in _songs)
        if (!song.hasLyrics) song,
    ];
    final paired = [
      for (final song in _songs)
        if (song.hasLyrics) song,
    ];

    Widget row(MobileLyricsSong song, {required bool add}) => Padding(
      padding: EdgeInsets.symmetric(
        horizontal: (gutter - AppSpacing.sm).clamp(0, gutter).toDouble(),
      ),
      child: AppSongRow(
        key: ValueKey(MobileLyricsScreen.songKey(song.path)),
        title: song.title,
        subtitle: song.artist,
        artwork: AppArtwork(
          path: song.artworkPath,
          borderRadius: AppArtwork.rowRadius,
        ),
        trailing: add
            ? IconButton(
                tooltip: MobileLyricsScreen.addLyricsHint,
                onPressed: () => _addLyrics(song),
                icon: Icon(Icons.add_rounded, color: AppColors.accent),
              )
            : null,
        semanticHint: add
            ? MobileLyricsScreen.addLyricsHint
            : MobileLyricsScreen.playHint,
        onTap: () => add ? _addLyrics(song) : _play(song),
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        surfaceTintColor: Colors.transparent,
        title: const Text(MobileLyricsScreen.title),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.only(bottom: layout.sectionGap),
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, 0, gutter, AppSpacing.lg),
              child: Text(
                MobileLyricsScreen.intro,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              child: _TransferCard(onTap: () => TransferEntry.open(context)),
            ),
            if (_error != null)
              Padding(
                padding: EdgeInsets.fromLTRB(gutter, AppSpacing.lg, gutter, 0),
                child: Text(
                  _error!,
                  style: TextStyle(color: AppColors.errorText),
                ),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: AppLoadingState(),
              )
            else if (_songs.isEmpty && _error == null)
              Padding(
                padding: EdgeInsets.fromLTRB(gutter, AppSpacing.xl, gutter, 0),
                child: AppEmptyState(
                  icon: Icons.lyrics_outlined,
                  title: '音乐库里还没有歌曲',
                  message: '先导入歌曲，或从电脑传过来，再回来给它们配歌词。',
                  actions: [
                    FilledButton.icon(
                      onPressed: () =>
                          Navigator.pushNamed(context, Routes.library),
                      icon: const Icon(Icons.library_music_rounded),
                      label: const Text('去音乐库'),
                    ),
                  ],
                ),
              )
            else ...[
              _Header(
                key: MobileLyricsScreen.missingHeaderKey,
                title: MobileLyricsScreen.missingTitle,
                count: missing.length,
                gutter: gutter,
                top: layout.sectionGap,
              ),
              if (missing.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: gutter),
                  child: Text(
                    MobileLyricsScreen.allPairedMessage,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                )
              else
                for (final song in missing) row(song, add: true),
              if (paired.isNotEmpty) ...[
                _Header(
                  key: MobileLyricsScreen.pairedHeaderKey,
                  title: MobileLyricsScreen.pairedTitle,
                  count: paired.length,
                  gutter: gutter,
                  top: layout.sectionGap,
                ),
                for (final song in paired) row(song, add: false),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    super.key,
    required this.title,
    required this.count,
    required this.gutter,
    required this.top,
  });

  final String title;
  final int count;
  final double gutter;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, top, gutter, AppSpacing.sm),
      child: Semantics(
        header: true,
        child: Text(
          '$title · $count',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: AppColors.bgSurface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: MobileLyricsScreen.transferKey,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.accentContainer,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Icon(
                    TransferEntry.icon,
                    color: AppColors.onAccentContainer,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      MobileLyricsScreen.transferTitle,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      MobileLyricsScreen.transferDetail,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
