import 'package:flutter/material.dart';

import '../../../../core/layout/app_responsive.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';

/// Previous, play/pause and next buttons shared by every player surface.
///
/// Now Playing, quick play, the project player and the immersive KTV screen
/// each used to build their own row with different tooltips, play-button
/// sizes, spinner sizes and disabled colours. This widget keeps one look:
///
/// * a white round play button sized by the layout's primary player extent
///   (or the minimum touch extent when [compact]), with a spinner while the
///   player is [isBusy];
/// * secondary buttons at the layout's minimum interactive extent;
/// * optional 10-second seek buttons, shown only when their callbacks are set.
class TransportBar extends StatelessWidget {
  const TransportBar({
    super.key,
    required this.isPlaying,
    required this.onPlayPause,
    this.isBusy = false,
    this.onPrevious,
    this.onNext,
    this.onSeekBack,
    this.onSeekForward,
    this.compact = false,
    this.wrap = false,
    this.layout,
  });

  final bool isPlaying;

  /// Loading or buffering: the play button shows a spinner and is disabled.
  final bool isBusy;

  final VoidCallback onPlayPause;

  /// Skips to the previous item or back to the start; null disables it.
  final VoidCallback? onPrevious;

  /// Skips to the next item; null disables it.
  final VoidCallback? onNext;

  /// Shows the 10-second back button when set.
  final VoidCallback? onSeekBack;

  /// Shows the 10-second forward button when set.
  final VoidCallback? onSeekForward;

  /// Smaller play button for side panels, mini players and short windows.
  final bool compact;

  /// Lets the buttons flow onto a second line in narrow containers instead of
  /// laying them out in a single row.
  final bool wrap;

  /// Layout used for button extents; defaults to the window layout. Pass the
  /// spec of a constrained panel when the bar lives inside one.
  final AppLayoutSpec? layout;

  static const String previousTooltip = '上一首 / 回到开头';
  static const String nextTooltip = '下一首';
  static const String seekBackTooltip = '后退 10 秒';
  static const String seekForwardTooltip = '前进 10 秒';
  static const String playTooltip = '播放';
  static const String pauseTooltip = '暂停';
  static const String busyTooltip = '正在加载';

  /// Play buttons never shrink below the touch-target minimum.
  static const double minimumPlayExtent = 48;

  /// Play or pause icon size for a play button of [extent].
  static double playIconSizeFor(double extent) {
    return (extent * 0.55).roundToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final spec = layout ?? AppResponsive.of(context);
    final secondaryExtent = spec.minimumInteractiveExtent;
    final playExtent = compact
        ? minimumPlayExtent
        : spec.primaryPlayerControlExtent;
    final gap = compact ? AppSpacing.xs : AppSpacing.sm;

    final buttons = <Widget>[
      _SecondaryButton(
        extent: secondaryExtent,
        tooltip: previousTooltip,
        icon: Icons.skip_previous_rounded,
        onPressed: onPrevious,
      ),
      if (onSeekBack != null)
        _SecondaryButton(
          extent: secondaryExtent,
          tooltip: seekBackTooltip,
          icon: Icons.replay_10_rounded,
          onPressed: onSeekBack,
        ),
      _PlayButton(
        extent: playExtent,
        isPlaying: isPlaying,
        isBusy: isBusy,
        onPressed: onPlayPause,
      ),
      if (onSeekForward != null)
        _SecondaryButton(
          extent: secondaryExtent,
          tooltip: seekForwardTooltip,
          icon: Icons.forward_10_rounded,
          onPressed: onSeekForward,
        ),
      _SecondaryButton(
        extent: secondaryExtent,
        tooltip: nextTooltip,
        icon: Icons.skip_next_rounded,
        onPressed: onNext,
      ),
    ];

    if (wrap) {
      return Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: gap,
        runSpacing: AppSpacing.xs,
        children: buttons,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < buttons.length; index++) ...[
          if (index > 0) SizedBox(width: gap),
          buttons[index],
        ],
      ],
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.extent,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final double extent;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: extent,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.extent,
    required this.isPlaying,
    required this.isBusy,
    required this.onPressed,
  });

  final double extent;
  final bool isPlaying;
  final bool isBusy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final iconSize = TransportBar.playIconSizeFor(extent);
    final spinnerSize = (iconSize * 0.65).roundToDouble();
    final tooltip = isBusy
        ? TransportBar.busyTooltip
        : isPlaying
        ? TransportBar.pauseTooltip
        : TransportBar.playTooltip;

    return SizedBox.square(
      dimension: extent,
      child: IconButton(
        onPressed: isBusy ? null : onPressed,
        tooltip: tooltip,
        style: IconButton.styleFrom(
          backgroundColor: AppColors.pureWhite,
          foregroundColor: AppColors.pureBlack,
          disabledBackgroundColor: AppColors.textDisabled,
        ),
        icon: isBusy
            ? SizedBox.square(
                dimension: spinnerSize,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.pureBlack,
                ),
              )
            : Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: iconSize,
              ),
      ),
    );
  }
}
