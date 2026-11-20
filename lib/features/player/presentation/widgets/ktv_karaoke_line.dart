import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../../../core/theme/color_tokens.dart';
import '../../../lyrics/domain/services/lyric_karaoke_timing_service.dart';
import '../../../lyrics/domain/services/lyric_word_timing_service.dart';
import '../../../project/domain/models/lyric_document.dart';

/// One display unit of a karaoke row and how much of it has been sung, from
/// 0 (not yet) to 1 (done).
typedef KtvSungUnit = ({String text, double sung});

/// Splits [line] into karaoke units (a Han character, a kana, a Latin word
/// with its punctuation) and reports how far each one is sung at [position].
///
/// Real word timing (forced aligner, word-by-word tap-to-sync) places every
/// unit where it was sung; without it the row's span is spread over the units
/// by how long each takes to sing, the same estimate karaoke exports use.
/// [offset] is the document's global offset. When the row has no usable end,
/// [fallbackEnd] (usually the next row's start) closes it; without either the
/// whole row counts as sung once it starts.
List<KtvSungUnit> ktvSungUnits(
  LyricLine line,
  Duration position, {
  Duration offset = Duration.zero,
  Duration? fallbackEnd,
  LyricKaraokeTimingService timing = const LyricKaraokeTimingService(),
  LyricWordTimingService wordTiming = const LyricWordTimingService(),
}) {
  final start = line.startTime;
  var end = line.endTime;
  if (end <= start && fallbackEnd != null) end = fallbackEnd;
  // Null when the row has no usable word timing (or no usable end).
  final times = wordTiming.characterTimes(line);
  final syllables = timing.syllables(
    line.text,
    start,
    end,
    characterStarts: times == null
        ? null
        : [for (final time in times) time.start],
  );
  final local = position - offset;
  return [
    for (final syllable in syllables)
      (text: syllable.text, sung: _sungFraction(syllable, local)),
  ];
}

double _sungFraction(LyricKaraokeSyllable syllable, Duration local) {
  if (local < syllable.start) return 0;
  final length = syllable.duration.inMicroseconds;
  if (length <= 0) return 1;
  final done = (local - syllable.start).inMicroseconds / length;
  return done.clamp(0.0, 1.0).toDouble();
}

/// The line being sung on the KTV stage, coloured unit by unit as it is sung.
///
/// Sung units take [sungColor], the unit being sung blends towards it, and
/// the rest keep the colour of [style]. Playback positions arrive a few
/// times a second, so while [isPlaying] the widget advances its own estimate
/// every frame from the last reported position (never more than
/// [maxExtrapolation] ahead) to keep the colour moving smoothly.
class KtvKaraokeLine extends StatefulWidget {
  const KtvKaraokeLine({
    super.key,
    required this.line,
    required this.position,
    required this.style,
    required this.maxLines,
    this.textKey,
    this.offset = Duration.zero,
    this.fallbackEnd,
    this.isPlaying = false,
    this.sungColor,
  });

  final LyricLine line;
  final Duration position;
  final TextStyle? style;
  final int maxLines;

  /// Key of the rendered [Text], so tests and callers can find the line.
  final Key? textKey;
  final Duration offset;
  final Duration? fallbackEnd;
  final bool isPlaying;
  /// Defaults to [AppColors.accent] of the theme in use.
  final Color? sungColor;

  /// How far past the last reported position the estimate may run.
  static const Duration maxExtrapolation = Duration(milliseconds: 400);

  @override
  State<KtvKaraokeLine> createState() => _KtvKaraokeLineState();
}

class _KtvKaraokeLineState extends State<KtvKaraokeLine>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);

  /// Frame time of the ticker now and when [KtvKaraokeLine.position] last
  /// changed; both restart at zero whenever the ticker starts.
  Duration _now = Duration.zero;
  Duration _reportedAt = Duration.zero;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(KtvKaraokeLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.position != oldWidget.position) _reportedAt = _now;
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) => setState(() => _now = elapsed);

  void _syncTicker() {
    if (widget.isPlaying && !_ticker.isActive) {
      _now = Duration.zero;
      _reportedAt = Duration.zero;
      _ticker.start();
    } else if (!widget.isPlaying && _ticker.isActive) {
      _ticker.stop();
    }
  }

  Duration get _estimatedPosition {
    if (!widget.isPlaying) return widget.position;
    var ahead = _now - _reportedAt;
    if (ahead > KtvKaraokeLine.maxExtrapolation) {
      ahead = KtvKaraokeLine.maxExtrapolation;
    }
    return widget.position + ahead;
  }

  @override
  Widget build(BuildContext context) {
    final units = ktvSungUnits(
      widget.line,
      _estimatedPosition,
      offset: widget.offset,
      fallbackEnd: widget.fallbackEnd,
    );
    final unsungColor = widget.style?.color ?? AppColors.textPrimary;
    final sungColor = widget.sungColor ?? AppColors.accent;
    return Text.rich(
      TextSpan(
        children: [
          for (final unit in units)
            TextSpan(
              text: unit.text,
              style: TextStyle(
                color: Color.lerp(unsungColor, sungColor, unit.sung),
              ),
            ),
        ],
      ),
      key: widget.textKey,
      textAlign: TextAlign.center,
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
      style: widget.style,
    );
  }
}
