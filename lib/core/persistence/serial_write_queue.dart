import 'dart:async';

/// Runs the writes of one store strictly one after another.
///
/// Every file-backed store used to hand-roll the same chain: remember the
/// previous write, await it inside a `try` with an empty `catch`, then write.
/// The empty `catch` was deliberate — a failed write belongs to the caller
/// that started it, and must not make every later write fail too — but it was
/// copied into eleven places and indistinguishable from an accidentally
/// swallowed error. This class is that rule, written once.
///
/// * A write starts only after every earlier write has settled.
/// * A failed write fails the future [run] returned for it, and nothing else:
///   the next write still runs, so one full disk does not poison later saves.
/// * [idle] completes once the writes queued so far have settled and never
///   throws, so a reader can wait for pending saves without inheriting their
///   errors.
class SerialWriteQueue {
  Future<void> _tail = Future<void>.value();
  int _pending = 0;

  /// Writes queued and not yet settled.
  int get pending => _pending;

  /// Completes when every write queued before this call has settled.
  Future<void> get idle => _tail;

  /// Queues [write] behind the writes already queued and returns its result.
  Future<T> run<T>(Future<T> Function() write) {
    final previous = _tail;
    _pending++;
    final result = () async {
      await previous;
      return write();
    }();
    _tail = _settle(result);
    return result;
  }

  Future<void> _settle(Future<Object?> write) async {
    try {
      await write;
    } on Object {
      // Reported to the caller of [run] through its own future; the queue
      // only needs to know the write is over.
    } finally {
      _pending--;
    }
  }
}
