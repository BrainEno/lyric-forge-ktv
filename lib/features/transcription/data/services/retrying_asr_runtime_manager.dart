import 'dart:async';

import '../../domain/models/transcription_models.dart';
import '../../domain/services/asr_runtime_manager.dart';

/// Retries transient managed-runtime download failures without discarding the
/// delegate's retained `.part` files.
///
/// Managed model/runtime downloaders remain responsible for byte-range resume,
/// integrity checks and atomic promotion. This wrapper only reconnects the
/// install flow after transport failures so a brief network interruption does
/// not force the user to press "resume" manually.
class RetryingAsrRuntimeManager implements AsrRuntimeManager {
  final AsrRuntimeManager delegate;
  final int maxAttempts;
  final Duration retryDelay;

  final StreamController<AsrRuntimeInstallProgress> _progressController =
      StreamController<AsrRuntimeInstallProgress>.broadcast();

  late final StreamSubscription<AsrRuntimeInstallProgress>
      _delegateSubscription;
  bool _installing = false;
  bool _cancelRequested = false;
  AsrRuntimeInstallProgress? _lastProgress;
  double _progressHighWatermark = 0;

  RetryingAsrRuntimeManager({
    required this.delegate,
    this.maxAttempts = 4,
    this.retryDelay = const Duration(seconds: 2),
  }) : assert(maxAttempts >= 1) {
    _delegateSubscription = delegate.progressStream.listen((progress) {
      _progressHighWatermark =
          progress.progress > _progressHighWatermark
              ? progress.progress
              : _progressHighWatermark;
      final forwarded = AsrRuntimeInstallProgress(
        component: progress.component,
        progress: _progressHighWatermark,
        message: progress.message,
        downloadedBytes: progress.downloadedBytes,
        totalBytes: progress.totalBytes,
        bytesPerSecond: progress.bytesPerSecond,
        estimatedRemaining: progress.estimatedRemaining,
      );
      _lastProgress = forwarded;
      if (!_progressController.isClosed) {
        _progressController.add(forwarded);
      }
    });
  }

  @override
  Stream<AsrRuntimeInstallProgress> get progressStream =>
      _progressController.stream;

  @override
  bool get isInstalling => _installing || delegate.isInstalling;

  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) {
    return delegate.inspect(config);
  }

  @override
  Future<TranscriptionConfig> repair(TranscriptionConfig config) {
    return delegate.repair(config);
  }

  @override
  Future<TranscriptionConfig> installRecommended(
    TranscriptionConfig config,
  ) async {
    if (_installing) {
      throw const TranscriptionException('识别环境正在安装，请稍候');
    }

    _installing = true;
    _cancelRequested = false;
    _lastProgress = null;
    _progressHighWatermark = 0;

    try {
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        _throwIfCancelled();
        try {
          return await delegate.installRecommended(config);
        } on TranscriptionException catch (error) {
          if (_cancelRequested || _isCancellation(error)) rethrow;
          if (attempt >= maxAttempts || !_isRetryable(error)) rethrow;

          _emitRetryProgress(attempt + 1);
          await _waitBeforeRetry(attempt);
        }
      }

      throw const TranscriptionException('识别环境安装重试次数已用尽');
    } finally {
      _installing = false;
      _cancelRequested = false;
      _lastProgress = null;
      _progressHighWatermark = 0;
    }
  }

  bool _isRetryable(TranscriptionException error) {
    if (error.kind == TranscriptionFailureKind.cancelled ||
        error.kind == TranscriptionFailureKind.busy ||
        error.kind == TranscriptionFailureKind.input) {
      return false;
    }

    final text = '${error.message}\n${error.details ?? ''}'.toLowerCase();
    if (text.contains('下载未完成') || text.contains('下次将从断点继续')) {
      return true;
    }

    const transportMarkers = <String>[
      'socketexception',
      'connection reset',
      'connection closed',
      'connection aborted',
      'connection failed',
      'connection refused',
      'broken pipe',
      'network is unreachable',
      'network unreachable',
      'host is down',
      'timed out',
      'timeout',
      'temporary failure',
      'connection terminated',
      'http 408',
      'http 425',
      'http 429',
      'http 500',
      'http 502',
      'http 503',
      'http 504',
    ];
    return transportMarkers.any(text.contains);
  }

  bool _isCancellation(TranscriptionException error) {
    return error.kind == TranscriptionFailureKind.cancelled ||
        error.message.contains('取消');
  }

  void _emitRetryProgress(int nextAttempt) {
    final previous = _lastProgress;
    final downloaded = previous?.downloadedBytes;
    final total = previous?.totalBytes;

    var message = '网络连接中断，正在自动重连（第 $nextAttempt/$maxAttempts 次）';
    if (downloaded != null && total != null && total > 0) {
      message = '网络连接中断，将从 ${_formatBytes(downloaded)} / '
          '${_formatBytes(total)} 继续（第 $nextAttempt/$maxAttempts 次）';
    }

    if (!_progressController.isClosed) {
      _progressController.add(
        AsrRuntimeInstallProgress(
          component: previous?.component,
          progress: _progressHighWatermark,
          message: message,
          downloadedBytes: downloaded,
          totalBytes: total,
          bytesPerSecond: null,
          estimatedRemaining: null,
        ),
      );
    }
  }

  Future<void> _waitBeforeRetry(int completedAttempt) async {
    final exponent = (completedAttempt - 1).clamp(0, 3).toInt();
    final multiplier = 1 << exponent;
    final delay = Duration(
      milliseconds: retryDelay.inMilliseconds * multiplier,
    );
    var remaining = delay;
    const tick = Duration(milliseconds: 100);

    while (remaining > Duration.zero) {
      _throwIfCancelled();
      final current = remaining < tick ? remaining : tick;
      await Future<void>.delayed(current);
      remaining -= current;
    }
  }

  String _formatBytes(int bytes) {
    const gib = 1024 * 1024 * 1024;
    const mib = 1024 * 1024;
    if (bytes >= gib) {
      return '${(bytes / gib).toStringAsFixed(2)} GB';
    }
    if (bytes >= mib) {
      return '${(bytes / mib).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  void _throwIfCancelled() {
    if (_cancelRequested) {
      throw const TranscriptionException.cancelled('识别环境安装已取消');
    }
  }

  @override
  Future<void> cancel() async {
    _cancelRequested = true;
    await delegate.cancel();
  }

  Future<void> dispose() async {
    _cancelRequested = true;
    await delegate.cancel();
    await _delegateSubscription.cancel();
    await _progressController.close();
  }
}
