import 'dart:async';

/// Runs a store's one-time load lazily, sharing one attempt between concurrent
/// callers, without caching a failed attempt.
///
/// `_loadFuture ??= _load()` remembers a rejected future forever: a temporary
/// permission or directory problem during the first read then keeps failing
/// every later refresh of the same repository instance, even after the user
/// fixed the file. With this helper a failed attempt is forgotten once it
/// completes, so the next call starts a fresh one (#440).
///
/// [load] must leave the store unchanged when it throws; parse into locals and
/// commit them only after the whole read succeeded, so a retry never mixes rows
/// from a half-finished attempt.
class RetryableLoad {
  RetryableLoad(this._load);

  final Future<void> Function() _load;
  Future<void>? _pending;
  bool _loaded = false;

  /// Whether a load attempt has completed successfully.
  bool get isLoaded => _loaded;

  /// Completes once the store is loaded. Concurrent calls share the attempt in
  /// flight; after a failure the next call retries.
  Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    final pending = _pending;
    if (pending != null) return pending;
    final attempt = _attempt();
    _pending = attempt;
    return attempt;
  }

  Future<void> _attempt() async {
    // Yield once so `_pending` is assigned before a synchronously failing
    // loader reaches the cleanup below; otherwise the failed attempt would be
    // stored after it was cleared and cached after all.
    await Future<void>.value();
    try {
      await _load();
      _loaded = true;
    } finally {
      _pending = null;
    }
  }
}
