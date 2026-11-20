import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../layout/app_responsive.dart';
import '../theme/color_tokens.dart';
import '../theme/spacing_tokens.dart';
import 'app_artwork.dart';
import 'app_tap_target.dart';
import 'app_vinyl_disc.dart';

/// Where a row's song stands in playback.
enum AppSongRowPlayback {
  /// Not the current song.
  none,

  /// The current song, paused.
  paused,

  /// The current song, playing.
  playing,
}

/// One song in a list: the row shared by the music library's songs, artist,
/// album, favourite and playlist lists and the phone's desktop-library and
/// download lists (decision D-041).
///
/// Each of those lists used to lay its row out by hand — a `ListTile` here,
/// a hand-made `Row` with its own padding, cover size and progress bar
/// there — so the same song looked different on every page, the phone rows
/// alone had a download button and a progress bar, and none of them showed
/// which song was playing. The row now owns:
///
///  * the cover (or a track number), at one size per layout, with a brass
///    rhythm-bar overlay while the song is the current one;
///  * the title, the subtitle with small [badges] before it, and the
///    unavailable state (dimmed, with [unavailableLabel] in the error red);
///  * an optional progress bar and one-line [notice] under the text, for a
///    download in flight or one that failed;
///  * a [trailing] slot for the ⋯ menu, a download button or a favourite
///    heart, kept outside the tap area so it stays its own control;
///  * the screen-reader reading: one button with [semanticLabel] (the title
///    and subtitle when null), the playback state in words, [semanticHint]
///    and [semanticActions] for the menu entries, in the menu's wording;
///  * the 48 dp minimum height on touch layouts.
class AppSongRow extends StatelessWidget {
  const AppSongRow({
    super.key,
    required this.title,
    this.subtitle,
    this.artwork,
    this.index,
    this.badges = const [],
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.playback = AppSongRowPlayback.none,
    this.unavailable = false,
    this.unavailableLabel = defaultUnavailableLabel,
    this.showProgress = false,
    this.progress,
    this.notice,
    this.noticeIsError = false,
    this.semanticLabel,
    this.semanticHint = defaultHint,
    this.semanticValue,
    this.semanticActions = const {},
    this.card = false,
  });

  final String title;
  final String? subtitle;

  /// The cover, usually an [AppArtwork] with [AppArtwork.rowRadius]. The row
  /// sizes it to [artworkExtentFor].
  final Widget? artwork;

  /// A track or position number shown before the cover, or in its place
  /// when [artwork] is null.
  final String? index;

  /// Small marks before the subtitle, such as [AppSongRowBadge]. They are
  /// not read; say what they mean in [semanticLabel].
  final List<Widget> badges;

  /// A control at the end of the row. It keeps its own semantics; add its
  /// entries to [semanticActions] too when it is a menu.
  final Widget? trailing;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  final AppSongRowPlayback playback;

  /// The file is gone: the row is dimmed, its tap is off and the subtitle is
  /// replaced by [unavailableLabel]. [semanticActions] stay, so the song can
  /// still be relinked or removed.
  final bool unavailable;
  final String unavailableLabel;

  /// Draws a progress bar under the text: [progress] from 0 to 1, or an
  /// indeterminate bar when it is null.
  final bool showProgress;
  final double? progress;

  /// One line under the text, e.g. 已下载 or the reason a download failed.
  final String? notice;
  final bool noticeIsError;

  /// What the row is, read as one sentence. Defaults to the title and the
  /// subtitle (or [unavailableLabel]).
  final String? semanticLabel;

  /// What a tap does.
  final String semanticHint;

  /// A changing value, e.g. a download percentage.
  final String? semanticValue;

  /// The menu entries as screen-reader actions, in menu order.
  final Map<String, VoidCallback?> semanticActions;

  /// Draws the row as a rounded card on the elevated surface, for lists
  /// that sit on a plain page (the phone's desktop library and downloads).
  final bool card;

  static const String defaultHint = '播放';
  static const String defaultUnavailableLabel = '文件不可用';

  /// Read after the label while the song plays or is paused.
  static const String playingLabel = '正在播放';
  static const String pausedLabel = '当前歌曲，已暂停';

  /// Cover edge on a phone and on wider layouts.
  static const double compactArtworkExtent = 48;
  static const double artworkExtent = 52;

  /// Width of the [index] column when a cover follows it.
  static const double indexWidth = 28;

  /// Cover edge for [layout]: never below its touch minimum, so the cover
  /// column lines up with 48 dp buttons.
  static double artworkExtentFor(AppLayoutSpec layout) => math.max(
    layout.isCompact ? compactArtworkExtent : artworkExtent,
    layout.minimumInteractiveExtent,
  );

  /// The sentence a screen reader hears for a row: [label], then the
  /// playback state.
  static String spokenLabel(String label, AppSongRowPlayback playback) {
    return AppTapTarget.join([
      label,
      switch (playback) {
        AppSongRowPlayback.none => null,
        AppSongRowPlayback.paused => pausedLabel,
        AppSongRowPlayback.playing => playingLabel,
      },
    ]);
  }

  /// [AppSongRowPlayback] of a row whose song [isCurrent], while the player
  /// [isPlaying].
  static AppSongRowPlayback playbackFor({
    required bool isCurrent,
    required bool isPlaying,
  }) {
    if (!isCurrent) return AppSongRowPlayback.none;
    return isPlaying ? AppSongRowPlayback.playing : AppSongRowPlayback.paused;
  }

  bool get _isCurrent => playback != AppSongRowPlayback.none;

  @override
  Widget build(BuildContext context) {
    final layout = AppResponsive.of(context);
    final textTheme = Theme.of(context).textTheme;
    final extent = artworkExtentFor(layout);
    final current = _isCurrent;
    final radius = BorderRadius.circular(
      card ? AppSpacing.radiusLarge : AppSpacing.radiusMedium,
    );
    final tap = unavailable ? null : onTap;
    final secondLine = unavailable ? unavailableLabel : subtitle;
    final label = semanticLabel ?? AppTapTarget.join([title, secondLine]);
    final notice = this.notice;

    final titleColor = unavailable
        ? AppColors.textTertiary
        : current
        ? AppColors.vinylBrass
        : AppColors.textPrimary;
    // Tertiary text drops under 4.5:1 on the brass wash of the playing row;
    // secondary stays above 6:1 there.
    final subtitleColor = unavailable
        ? AppColors.errorText
        : current
        ? AppColors.textSecondary
        : AppColors.textTertiary;

    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleSmall?.copyWith(
            color: titleColor,
            fontWeight: current ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        if (secondLine != null && secondLine.isNotEmpty ||
            badges.isNotEmpty) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              for (final badge in badges) ...[
                badge,
                const SizedBox(width: AppSpacing.xs),
              ],
              if (secondLine != null)
                Flexible(
                  child: Text(
                    secondLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(color: subtitleColor),
                  ),
                ),
            ],
          ),
        ],
        if (showProgress) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              color: AppColors.vinylBrass,
              backgroundColor: AppColors.bgHighlight,
            ),
          ),
        ],
        if (notice != null) ...[
          const SizedBox(height: 4),
          Text(
            notice,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: noticeIsError
                  ? AppColors.errorText
                  : AppColors.textTertiary,
            ),
          ),
        ],
      ],
    );

    final body = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: layout.isCompact ? AppSpacing.sm : AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          _SongRowLeading(
            artwork: artwork,
            index: index,
            extent: extent,
            playback: playback,
            unavailable: unavailable,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: text),
        ],
      ),
    );

    return Material(
      color: current
          ? AppColors.vinylBrassMuted
          : card
          ? AppColors.bgElevated
          : Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: layout.minimumInteractiveExtent),
        child: Row(
          children: [
            Expanded(
              child: AppTapTarget(
                label: spokenLabel(label, playback),
                hint: semanticHint,
                value: semanticValue,
                enabled: !unavailable && onTap != null,
                selected: current ? true : null,
                onTap: tap,
                onLongPress: unavailable ? null : onLongPress,
                actions: semanticActions,
                child: InkWell(
                  onTap: tap,
                  onLongPress: unavailable ? null : onLongPress,
                  child: body,
                ),
              ),
            ),
            ?trailing,
            if (trailing != null) const SizedBox(width: AppSpacing.xs),
          ],
        ),
      ),
    );
  }
}

/// The number and cover column of [AppSongRow].
class _SongRowLeading extends StatelessWidget {
  const _SongRowLeading({
    required this.artwork,
    required this.index,
    required this.extent,
    required this.playback,
    required this.unavailable,
  });

  final Widget? artwork;
  final String? index;
  final double extent;
  final AppSongRowPlayback playback;
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final artwork = this.artwork;
    final index = this.index;
    final current = playback != AppSongRowPlayback.none;
    final playing = playback == AppSongRowPlayback.playing;
    final textTheme = Theme.of(context).textTheme;

    Widget number(String value) => Text(
      value,
      maxLines: 1,
      textAlign: TextAlign.center,
      // Long numbers shrink rather than wrap or push the cover.
      overflow: TextOverflow.visible,
      softWrap: false,
      style: textTheme.labelLarge?.copyWith(
        color: current ? AppColors.vinylBrass : AppColors.textTertiary,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    if (artwork == null) {
      // A numbered row without covers (an album's track list): the bars
      // take the number's place while it plays.
      return SizedBox(
        width: extent,
        height: extent,
        child: Center(
          child: current
              ? AppRhythmBars(playing: playing)
              : index == null
              ? null
              : FittedBox(fit: BoxFit.scaleDown, child: number(index)),
        ),
      );
    }

    final cover = SizedBox.square(
      dimension: extent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(opacity: unavailable ? 0.55 : 1, child: artwork),
          if (current)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppArtwork.rowRadius),
              child: ColoredBox(
                color: AppColors.pureBlack.withAlpha(120),
                child: Center(
                  child: AppRhythmBars(
                    playing: playing,
                    color: AppColors.vinylBrassOnDark,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (index == null) return cover;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: AppSongRow.indexWidth,
          child: FittedBox(fit: BoxFit.scaleDown, child: number(index)),
        ),
        const SizedBox(width: AppSpacing.xs),
        cover,
      ],
    );
  }
}

/// A small mark before a song row's subtitle: lyrics, edited, downloaded.
///
/// Not read by screen readers; the row's label says the same in words.
class AppSongRowBadge extends StatelessWidget {
  const AppSongRowBadge({
    super.key,
    required this.icon,
    this.color,
  });

  final IconData icon;

  /// Defaults to [AppColors.textTertiary] of the theme in use.
  final Color? color;

  static const double iconSize = 14;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Icon(
        icon,
        size: iconSize,
        color: color ?? AppColors.textTertiary,
      ),
    );
  }
}
