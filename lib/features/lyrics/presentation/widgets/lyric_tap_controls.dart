import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/diagnostics/best_effort.dart';
import '../../../../core/theme/color_tokens.dart';
import '../../../player/domain/models/playback_state.dart';

/// Reads "now" on the song timeline for the tap-to-sync dialogs.
///
/// Players report their position only a few times per second, so the time
/// of a key press is the last reported position plus the time elapsed since
/// that report (scaled by the playback speed, and at most
/// [maxExtrapolation]). An optional reaction-time compensation, scaled by the
/// speed too, is subtracted on top, and the document's global offset is
/// removed so the result is on the lyric timeline.
class LyricTapClock {
  LyricTapClock({
    required PlaybackState initial,
    required this.offset,
    Duration Function()? now,
    this.maxExtrapolation = const Duration(milliseconds: 600),
  }) : _now = now,
       _state = initial {
    _reportedAt = this.now();
  }

  /// The document's global offset (audio time = timeline time + offset).
  final Duration offset;

  /// Extrapolation never runs further than this past the last report.
  final Duration maxExtrapolation;

  final Duration Function()? _now;
  final Stopwatch _stopwatch = Stopwatch()..start();
  PlaybackState _state;
  Duration _reportedAt = Duration.zero;

  PlaybackState get state => _state;

  /// The monotonic time used for extrapolation.
  Duration now() => _now?.call() ?? _stopwatch.elapsed;

  /// Records a player report.
  void report(PlaybackState state) {
    _state = state;
    _reportedAt = now();
  }

  /// The audio position now, extrapolated from the last report.
  Duration audioNow() {
    if (!_state.isPlaying) return _state.position;
    var elapsed = now() - _reportedAt;
    if (elapsed.isNegative) elapsed = Duration.zero;
    if (elapsed > maxExtrapolation) elapsed = maxExtrapolation;
    return _state.position +
        Duration(microseconds: (elapsed.inMicroseconds * _state.speed).round());
  }

  /// The press time on the lyric timeline with [latencyMs] of reaction time
  /// removed; never negative.
  Duration pressTime({int latencyMs = 0}) {
    final latency = Duration(
      microseconds: (latencyMs * 1000 * _state.speed).round(),
    );
    final value = audioNow() - offset - latency;
    return value.isNegative ? Duration.zero : value;
  }

  /// [timeline] as an audio position, never negative.
  Duration toAudio(Duration timeline) {
    final value = timeline + offset;
    return value.isNegative ? Duration.zero : value;
  }

  /// [audio] on the lyric timeline, never negative.
  Duration toTimeline(Duration audio) {
    final value = audio - offset;
    return value.isNegative ? Duration.zero : value;
  }
}

/// The big touch target of the tap-to-sync dialogs. It listens to raw
/// pointer events rather than a tap gesture: inside the scrollable dialog a
/// tap recogniser waits up to 100 ms to rule out a scroll before it reports
/// the press, and the moment of the press is the timestamp.
class LyricTapPad extends StatelessWidget {
  const LyricTapPad({
    super.key,
    required this.padKey,
    required this.label,
    required this.enabled,
    required this.onDown,
    required this.onUp,
    this.height = 88,
  });

  /// Key of the listener, for tests.
  final Key padKey;
  final String label;
  final bool enabled;
  final VoidCallback onDown;
  final VoidCallback onUp;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: enabled
          ? AppColors.accent.withValues(alpha: 0.18)
          : AppColors.bgSurface,
      borderRadius: BorderRadius.circular(12),
      child: Listener(
        key: padKey,
        behavior: HitTestBehavior.opaque,
        onPointerDown: enabled ? (_) => onDown() : null,
        onPointerUp: enabled ? (_) => onUp() : null,
        onPointerCancel: enabled ? (_) => onUp() : null,
        child: SizedBox(
          height: height,
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: enabled ? AppColors.textPrimary : AppColors.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Player commands of the tap-to-sync dialogs, with their failures shown.
///
/// The dialogs used to wrap play, pause and speed changes in an empty
/// `catch`, so a player that refused to start left the user pressing a
/// button that did nothing. A failed command now leaves a short message in
/// [transportError] (shown by [LyricTapTransportError]) and a warning in the
/// diagnostics log; the next command that succeeds clears it. The tapping
/// session itself is never touched by a player failure.
mixin LyricTapTransportFeedback<T extends StatefulWidget> on State<T> {
  String? _transportError;

  /// The last player failure, until a later command succeeds.
  String? get transportError => _transportError;

  /// Runs [command]; [action] names it in the message (播放、暂停、跳转…).
  Future<void> runTransport(
    String action,
    Future<void> Function() command,
  ) async {
    try {
      await command();
    } on Object catch (error, stackTrace) {
      appLog.warning(
        'lyrics.tap',
        'Tap-sync player command failed: $action',
        error: error,
        stackTrace: stackTrace,
      );
      _setTransportError('$action失败：播放器没有响应，可以再试一次或关闭后重开');
      return;
    }
    _setTransportError(null);
  }

  /// Fires [command] while the dialog closes, when there is no one left to
  /// show a message to; a failure is only logged.
  void restoreTransport(String action, Future<void> Function() command) {
    unawaited(
      bestEffort(
        'lyrics.tap',
        '关闭打点窗口时$action',
        command,
        impact: BestEffortImpact.degraded,
      ),
    );
  }

  void _setTransportError(String? message) {
    if (!mounted || message == _transportError) return;
    setState(() => _transportError = message);
  }
}

/// The message of [LyricTapTransportFeedback.transportError]; nothing when
/// there is none.
class LyricTapTransportError extends StatelessWidget {
  const LyricTapTransportError({super.key, required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: AppColors.error,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
