/// Formats a recording or audition duration as `mm:ss`, adding hours only when
/// the recording is long enough to need them.
///
/// Kept out of the player screen because the take sheet — now its own widget —
/// shows the same timestamps.
String formatRecordingTime(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '$minutes:$seconds';
}
