/// A single-isolate, non-queuing gate for operations sharing ASR resources.
///
/// All participating operations must use the same instance. It does not lock
/// other isolates or processes and does not stop an idle native model server.
enum AsrResourceUse { transcription, independentRerun, alignment, installation }

class AsrResourceCoordinator {
  AsrResourceLease? _active;

  AsrResourceUse? get activeUse => _active?.use;

  /// Acquires synchronously or returns null without changing the current owner.
  AsrResourceLease? tryAcquire(AsrResourceUse use) {
    if (_active != null) return null;
    return _active = AsrResourceLease._(this, use);
  }

  void _release(AsrResourceLease lease) {
    if (identical(_active, lease)) _active = null;
  }
}

/// Only the owner of this lease should release it, after asynchronous cleanup.
class AsrResourceLease {
  final AsrResourceCoordinator _coordinator;
  final AsrResourceUse use;
  bool _released = false;

  AsrResourceLease._(this._coordinator, this.use);

  /// Idempotent: a stale release cannot unlock a newer owner's lease.
  void release() {
    if (_released) return;
    _released = true;
    _coordinator._release(this);
  }
}
