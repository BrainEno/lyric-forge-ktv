import 'dart:io';

const int _mebibyte = 1024 * 1024;

/// Current and peak resident memory of this process, in MiB, for timing
/// samples of heavy operations (long-song recognition, mix export).
///
/// Peak RSS covers in-process engines (the native Qwen library, SoLoud) but
/// not child processes such as `whisper-cli` or FFmpeg; the measurement docs
/// say how to read those. Returns an empty map where the platform does not
/// report memory, so a missing number is never shown as zero.
Map<String, Object?> processMemoryAttributes() {
  try {
    final current = ProcessInfo.currentRss;
    final peak = ProcessInfo.maxRss;
    return {
      if (current > 0) 'rssMb': current ~/ _mebibyte,
      if (peak > 0) 'peakRssMb': peak ~/ _mebibyte,
    };
  } catch (_) {
    return const {};
  }
}
