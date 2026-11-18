import 'dart:async';

import 'app_logger.dart';
import 'log_record.dart';

/// How much a failed best-effort step matters.
enum BestEffortImpact {
  /// Housekeeping whose failure changes nothing the user can notice:
  /// deleting a temporary file, stopping a process that already exited,
  /// cancelling a subscription that already ended. Logged at debug level, so
  /// it shows up only in verbose diagnostics.
  housekeeping(LogLevel.debug),

  /// A step whose failure can leave something behind or degrade a result —
  /// a recording that may not be finalised, a cache that keeps growing, a
  /// device that may stay busy — but must not turn the surrounding operation
  /// into a failure. Logged as a warning, so it reaches the diagnostics
  /// report.
  degraded(LogLevel.warning);

  const BestEffortImpact(this.level);

  final LogLevel level;
}

/// Runs a step whose failure must not change the outcome of the surrounding
/// operation, and records the failure instead of swallowing it.
///
/// This replaces `try { … } catch (_) {}`: the call site has to say what the
/// step is ([operation]) and how much a failure matters ([impact]), and the
/// error reaches the log with that context. Use it only where continuing is
/// genuinely correct; errors the caller must handle still have to propagate.
///
/// [operation] is a short, content-free description (no lyric text, no file
/// names of user media); the logger redacts anyway.
Future<void> bestEffort(
  String tag,
  String operation,
  FutureOr<void> Function() step, {
  BestEffortImpact impact = BestEffortImpact.housekeeping,
  AppLogger? logger,
}) async {
  try {
    await step();
  } on Object catch (error, stackTrace) {
    _report(logger ?? appLog, tag, operation, impact, error, stackTrace);
  }
}

/// Synchronous form of [bestEffort], for steps such as `Process.kill` that
/// must run before the caller continues.
void bestEffortSync(
  String tag,
  String operation,
  void Function() step, {
  BestEffortImpact impact = BestEffortImpact.housekeeping,
  AppLogger? logger,
}) {
  try {
    step();
  } on Object catch (error, stackTrace) {
    _report(logger ?? appLog, tag, operation, impact, error, stackTrace);
  }
}

/// Returns [read]'s value, or [fallback] when it fails; the failure is
/// logged like a [bestEffort] step. For optional facts such as a file size
/// shown in a summary.
Future<T> bestEffortValue<T>(
  String tag,
  String operation,
  FutureOr<T> Function() read, {
  required T fallback,
  BestEffortImpact impact = BestEffortImpact.housekeeping,
  AppLogger? logger,
}) async {
  try {
    return await read();
  } on Object catch (error, stackTrace) {
    _report(logger ?? appLog, tag, operation, impact, error, stackTrace);
    return fallback;
  }
}

void _report(
  AppLogger logger,
  String tag,
  String operation,
  BestEffortImpact impact,
  Object error,
  StackTrace stackTrace,
) {
  logger.log(
    impact.level,
    tag,
    '$operation 失败，已忽略',
    error: error,
    // Housekeeping failures are expected now and then; their stack adds noise
    // without telling anyone what to fix.
    stackTrace: impact == BestEffortImpact.degraded ? stackTrace : null,
  );
}
