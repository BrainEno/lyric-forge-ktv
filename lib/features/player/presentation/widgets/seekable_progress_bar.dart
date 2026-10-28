import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/playback_state.dart';

/// 可交互的播放进度条，供所有播放界面与底部固定播放条共用。
///
/// 交互约定：
/// - 鼠标悬停：在轨道上方显示光标处的 `mm:ss` 气泡；
/// - 点击或拖动：均只在松手时落一次最终位置，点击触发一次 seek、
///   拖动触发一次最终 seek，短距离拖动同样按落点跳转；
/// - 时长未知或 [enabled] 为 false 时只显示进度，不响应交互。
///
/// [SeekableProgressBar.mini] 用于主界面底部固定播放条：细轨道、无滑块、
/// 无时间文本行，但保留悬停气泡与点击/拖动跳转。
class SeekableProgressBar extends StatefulWidget {
  final PlaybackState state;
  final ValueChanged<Duration> onSeek;
  final bool compact;
  final bool enabled;
  final bool mini;
  final double? hitHeight;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? thumbColor;

  const SeekableProgressBar({
    super.key,
    required this.state,
    required this.onSeek,
    this.compact = false,
    this.enabled = true,
    this.hitHeight,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
  }) : mini = false;

  const SeekableProgressBar.mini({
    super.key,
    required this.state,
    required this.onSeek,
    this.enabled = true,
    this.hitHeight,
    this.activeColor,
    this.inactiveColor,
  }) : mini = true,
       compact = true,
       thumbColor = null;

  @override
  State<SeekableProgressBar> createState() => _SeekableProgressBarState();
}

class _SeekableProgressBarState extends State<SeekableProgressBar> {
  /// 拖动中的目标位置（0..1），非拖动时为 null。
  double? _dragFraction;

  /// 鼠标悬停位置（0..1），离开后为 null。
  double? _hoverFraction;

  bool get _canSeek {
    final durationMs = widget.state.duration?.inMilliseconds ?? 0;
    return widget.enabled && durationMs > 0;
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.state.duration;
    final durationMs = duration?.inMilliseconds ?? 0;
    final baseFraction = durationMs > 0
        ? (widget.state.position.inMilliseconds / durationMs).clamp(0.0, 1.0)
        : 0.0;
    final displayFraction = _dragFraction ?? baseFraction;
    final displayPosition = duration != null
        ? Duration(milliseconds: (displayFraction * durationMs).round())
        : widget.state.position;
    final hintFraction = _dragFraction ?? _hoverFraction;
    final hintPosition = hintFraction != null && duration != null
        ? Duration(milliseconds: (hintFraction * durationMs).round())
        : null;
    final hitHeight = widget.hitHeight ?? (widget.mini ? 16.0 : 32.0);
    final trackHeight = widget.mini ? 3.0 : (widget.compact ? 3.0 : 4.0);
    final activeColor = widget.activeColor ?? AppColors.accent;
    final inactiveColor = widget.inactiveColor ?? AppColors.bgHighlight;
    final thumbRadius = widget.mini ? 0.0 : (widget.compact ? 5.0 : 7.0);
    final thumbColor = widget.thumbColor ?? activeColor;

    final bar = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return MouseRegion(
          cursor: _canSeek ? SystemMouseCursors.click : MouseCursor.defer,
          onHover: _canSeek
              ? (event) => _updateHover(event.localPosition.dx, width)
              : null,
          onExit: _canSeek
              ? (_) => setState(() => _hoverFraction = null)
              : null,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: !_canSeek
                ? null
                : (event) => _handlePointerDown(
                    event.localPosition.dx,
                    width,
                    durationMs,
                  ),
            onPointerMove: !_canSeek
                ? null
                : (event) => _updateDrag(event.localPosition.dx, width),
            onPointerUp: !_canSeek
                ? null
                : (event) => _handlePointerUp(
                    event.localPosition.dx,
                    width,
                    durationMs,
                  ),
            onPointerCancel: !_canSeek
                ? null
                : (_) => setState(() {
                    _dragFraction = null;
                  }),
            child: SizedBox(
              height: hitHeight,
              width: double.infinity,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      height: trackHeight,
                      decoration: BoxDecoration(
                        color: inactiveColor,
                        borderRadius: BorderRadius.circular(trackHeight),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: displayFraction,
                      child: Container(
                        height: trackHeight,
                        decoration: BoxDecoration(
                          color: activeColor,
                          borderRadius: BorderRadius.circular(trackHeight),
                        ),
                      ),
                    ),
                  ),
                  if (thumbRadius > 0)
                    Positioned(
                      left: _thumbLeft(width, displayFraction, thumbRadius),
                      top: (hitHeight - thumbRadius * 2) / 2,
                      child: IgnorePointer(
                        child: Container(
                          width: thumbRadius * 2,
                          height: thumbRadius * 2,
                          decoration: BoxDecoration(
                            color: thumbColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  if (_canSeek && hintFraction != null)
                    _TimeHint(
                      left: _hintLeft(width, hintFraction),
                      top: -(AppSpacing.xs + 18),
                      label: _formatDuration(hintPosition ?? Duration.zero),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          slider: true,
          enabled: _canSeek,
          label: '播放进度',
          value: _formatDuration(displayPosition),
          increasedValue: _formatDuration(
            _clampToDuration(
              widget.state.position + const Duration(seconds: 5),
            ),
          ),
          decreasedValue: _formatDuration(
            _clampToDuration(
              widget.state.position - const Duration(seconds: 5),
            ),
          ),
          onIncrease: _canSeek ? () => _seekRelative(1) : null,
          onDecrease: _canSeek ? () => _seekRelative(-1) : null,
          child: bar,
        ),
        if (!widget.mini)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              children: [
                Text(
                  _formatDuration(displayPosition),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
                const Spacer(),
                Text(
                  widget.state.duration != null
                      ? _formatDuration(widget.state.duration!)
                      : '--:--',
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

  double _thumbLeft(double width, double fraction, double radius) {
    return (fraction * width - radius).clamp(
      0.0,
      math.max(0.0, width - radius * 2),
    );
  }

  double _hintLeft(double width, double fraction) {
    const hintWidth = 52.0;
    return (fraction * width - hintWidth / 2).clamp(
      0.0,
      math.max(0.0, width - hintWidth),
    );
  }

  void _updateHover(double dx, double width) {
    if (width <= 0) return;
    setState(() => _hoverFraction = (dx / width).clamp(0.0, 1.0));
  }

  void _updateDrag(double dx, double width) {
    if (width <= 0 || _dragFraction == null) return;
    setState(() => _dragFraction = (dx / width).clamp(0.0, 1.0));
  }

  void _handlePointerDown(double dx, double width, int durationMs) {
    if (width <= 0 || durationMs <= 0) return;
    final fraction = (dx / width).clamp(0.0, 1.0);
    setState(() {
      _dragFraction = fraction;
      _hoverFraction = fraction;
    });
    // 不按下即求：点击与拖动统一在松手时只落一次最终位置，避免拖动
    // 产生“按下一次 + 松手一次”两次 seek。
  }

  void _handlePointerUp(double dx, double width, int durationMs) {
    final wasDragging = _dragFraction != null;
    if (!wasDragging || width <= 0 || durationMs <= 0) return;
    final fraction = (dx / width).clamp(0.0, 1.0);
    final target = Duration(milliseconds: (fraction * durationMs).round());
    setState(() {
      _dragFraction = null;
    });
    // 松手时只执行一次最终跳转；短距离拖动也按落点 seek，不再按移动
    // 距离阈值过滤，保证轻微拖动也能准确落点。
    widget.onSeek(target);
  }

  void _seekRelative(int direction) {
    final duration = widget.state.duration;
    if (duration == null) return;
    widget.onSeek(
      _clampToDuration(
        widget.state.position + Duration(seconds: 5 * direction),
      ),
    );
  }

  Duration _clampToDuration(Duration target) {
    final duration = widget.state.duration;
    if (duration == null) return target;
    if (target < Duration.zero) return Duration.zero;
    if (target > duration) return duration;
    return target;
  }

  static String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _TimeHint extends StatelessWidget {
  final double left;
  final double top;
  final String label;

  const _TimeHint({required this.left, required this.top, required this.label});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: 52,
          padding: const EdgeInsets.symmetric(vertical: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.bgElevated,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
            border: Border.all(color: AppColors.bgHighlight),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
