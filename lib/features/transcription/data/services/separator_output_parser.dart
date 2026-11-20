import '../../domain/models/vocal_separation_models.dart';

/// One machine-readable line of `lyricforge-separator` stdout.
///
/// The protocol is defined in `native/vocal_separator/src/report.hpp`; any
/// line that does not start with a known `LF_` tag is log output and parses
/// to null.
sealed class SeparatorEvent {
  const SeparatorEvent();
}

class SeparatorStageEvent extends SeparatorEvent {
  final String stage;
  const SeparatorStageEvent(this.stage);
}

class SeparatorProviderEvent extends SeparatorEvent {
  final String provider;
  const SeparatorProviderEvent(this.provider);
}

class SeparatorFallbackEvent extends SeparatorEvent {
  final String reason;
  const SeparatorFallbackEvent(this.reason);
}

class SeparatorProgressEvent extends SeparatorEvent {
  final double fraction;
  const SeparatorProgressEvent(this.fraction);
}

class SeparatorStatsEvent extends SeparatorEvent {
  final SeparatorStemStats stats;
  const SeparatorStatsEvent(this.stats);
}

class SeparatorDoneEvent extends SeparatorEvent {
  const SeparatorDoneEvent();
}

class SeparatorErrorEvent extends SeparatorEvent {
  final int code;
  final String message;
  const SeparatorErrorEvent(this.code, this.message);
}

/// Parses one stdout line; tolerant of `\r` from Windows consoles.
SeparatorEvent? parseSeparatorLine(String rawLine) {
  final line = rawLine.trimRight();
  final space = line.indexOf(' ');
  final tag = space < 0 ? line : line.substring(0, space);
  final rest = space < 0 ? '' : line.substring(space + 1).trim();
  switch (tag) {
    case 'LF_STAGE':
      return rest.isEmpty ? null : SeparatorStageEvent(rest);
    case 'LF_PROVIDER':
      return rest.isEmpty ? null : SeparatorProviderEvent(rest);
    case 'LF_FALLBACK':
      return SeparatorFallbackEvent(rest);
    case 'LF_PROGRESS':
      final value = double.tryParse(rest);
      if (value == null || !value.isFinite) return null;
      return SeparatorProgressEvent(value.clamp(0.0, 1.0).toDouble());
    case 'LF_STATS':
      return _parseStats(rest);
    case 'LF_DONE':
      return const SeparatorDoneEvent();
    case 'LF_ERROR':
      final separator = rest.indexOf(' ');
      final codeText = separator < 0 ? rest : rest.substring(0, separator);
      final code = int.tryParse(codeText);
      if (code == null) return null;
      return SeparatorErrorEvent(
        code,
        separator < 0 ? '' : rest.substring(separator + 1).trim(),
      );
  }
  return null;
}

SeparatorStatsEvent? _parseStats(String rest) {
  final values = <String, double>{};
  for (final pair in rest.split(RegExp(r'\s+'))) {
    final equals = pair.indexOf('=');
    if (equals <= 0) continue;
    final value = double.tryParse(pair.substring(equals + 1));
    if (value == null || !value.isFinite || value < 0) continue;
    values[pair.substring(0, equals)] = value;
  }
  final mix = values['mix_rms'];
  final vocals = values['vocals_rms'];
  if (mix == null || vocals == null) return null;
  return SeparatorStatsEvent(
    SeparatorStemStats(
      mixRms: mix,
      vocalsRms: vocals,
      accompanimentRms: values['accompaniment_rms'] ?? 0,
      seconds: values['seconds'] ?? 0,
    ),
  );
}

/// Everything one separator run reported, accumulated from its events.
class SeparatorRunReport {
  String? stage;
  String? provider;
  final List<String> fallbacks = [];
  double progress = 0;
  SeparatorStemStats? stats;
  bool done = false;
  SeparatorErrorEvent? error;

  /// Separator-reported progress mapped onto the whole run: loading the
  /// model is the first 5 %, inference the next 90 %, writing the rest.
  double get overallProgress {
    if (done) return 1.0;
    return switch (stage) {
      'write' => 0.95,
      'separate' => 0.05 + 0.9 * progress,
      _ => 0.0,
    };
  }

  void add(SeparatorEvent event) {
    switch (event) {
      case SeparatorStageEvent(:final stage):
        this.stage = stage;
      case SeparatorProviderEvent(:final provider):
        this.provider = provider;
      case SeparatorFallbackEvent(:final reason):
        // The reason names the abandoned provider; inference starts over.
        fallbacks.add(reason);
        provider = null;
        progress = 0;
      case SeparatorProgressEvent(:final fraction):
        if (fraction > progress) progress = fraction;
      case SeparatorStatsEvent(:final stats):
        this.stats = stats;
      case SeparatorDoneEvent():
        done = true;
      case SeparatorErrorEvent():
        error = event;
    }
  }
}
