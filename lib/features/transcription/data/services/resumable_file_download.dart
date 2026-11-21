import 'dart:async';
import 'dart:io';

import '../../domain/models/transcription_models.dart';
import 'asr_download_http_client_factory.dart';

/// Cancels the network transfers of one runtime install run.
///
/// The install managers used to keep a cancel flag plus the active request
/// and client in loose fields, each aborting a slightly different subset on
/// cancel. Transfers register here instead, and [cancel] stops whichever is
/// in flight.
class AsrTransferCancellation {
  bool _requested = false;
  HttpClient? _client;
  HttpClientRequest? _request;

  bool get isRequested => _requested;

  /// Throws the cancellation every install step reports.
  void throwIfRequested() {
    if (_requested) {
      throw const TranscriptionException.cancelled('识别环境安装已取消');
    }
  }

  /// Starts a new run: forgets an earlier cancel and earlier transfers.
  void reset() {
    _requested = false;
    _client = null;
    _request = null;
  }

  /// Stops the transfer in flight, and makes later checks throw.
  void cancel() {
    _requested = true;
    _request?.abort();
    _client?.close(force: true);
    _request = null;
    _client = null;
  }

  /// Registers [client] (and, once sent, [request]) as in flight.
  void track(HttpClient client, [HttpClientRequest? request]) {
    _client = client;
    _request = request;
  }

  /// The request was answered; only the client is left to stop.
  void requestDone() => _request = null;

  /// [client] is finished; forgets it unless a newer one replaced it.
  void release(HttpClient client) {
    if (!identical(_client, client)) return;
    _client = null;
    _request = null;
  }
}

/// One progress sample of a [ResumableFileDownload].
class DownloadProgress {
  const DownloadProgress({
    required this.receivedBytes,
    this.totalBytes,
    this.bytesPerSecond,
    this.estimatedRemaining,
  });

  /// Bytes in the part file, including those kept from earlier attempts.
  final int receivedBytes;

  /// The full size, when the server or the caller knows it.
  final int? totalBytes;

  /// Speed of this attempt, once it has run long enough to measure.
  final double? bytesPerSecond;
  final Duration? estimatedRemaining;

  /// Share of [totalBytes] received; null while the size is unknown.
  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0.0, 1.0).toDouble();
  }
}

/// Why a [ResumableFileDownload] stopped; callers turn it into their own
/// user-facing message.
enum DownloadFailure {
  /// The server answered neither 200 nor 206. The part file is kept.
  httpStatus,

  /// A 206 whose `Content-Range` does not continue the part file. Appending
  /// would corrupt it, so the part file was deleted.
  inconsistentResume,

  /// The connection ended before the full size arrived. The part file is
  /// kept for the next attempt.
  incomplete,

  /// More bytes arrived than the full size. The part file was deleted.
  oversized,
}

/// A transport failure that [ResumableFileDownload.fetch] is about to retry
/// from the kept part file.
class DownloadRetry {
  const DownloadRetry({
    required this.attempt,
    required this.maxConsecutiveAttempts,
    required this.keptBytes,
    required this.totalBytes,
    required this.delay,
    required this.error,
  });

  /// 1 for the first retry of this fetch.
  final int attempt;

  /// How many failures in a row without new bytes end the fetch.
  final int maxConsecutiveAttempts;

  /// Bytes already in the part file; the retry asks for the rest.
  final int keptBytes;
  final int? totalBytes;
  final Duration delay;
  final Object error;
}

/// The progress line shown while [retry] waits to continue [label].
String describeDownloadRetry(String label, DownloadRetry retry) {
  final total = retry.totalBytes;
  final kept = total != null && total > 0
      ? '${formatDownloadBytes(retry.keptBytes)} / ${formatDownloadBytes(total)}'
      : formatDownloadBytes(retry.keptBytes);
  return '$label 网络中断，已保留 $kept，'
      '${retry.delay.inSeconds > 0 ? '${retry.delay.inSeconds} 秒后' : '正在'}'
      '从断点继续下载（第 ${retry.attempt} 次重连）';
}

/// `1.23 GB`, `45.6 MB`, `12 KB` or `512 B`.
String formatDownloadBytes(int bytes) {
  const gib = 1024 * 1024 * 1024;
  const mib = 1024 * 1024;
  if (bytes >= gib) return '${(bytes / gib).toStringAsFixed(2)} GB';
  if (bytes >= mib) return '${(bytes / mib).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}

class ResumableDownloadException implements Exception {
  const ResumableDownloadException(
    this.failure,
    this.uri, {
    required this.response,
    this.contentRange,
    this.expectedBytes,
    this.actualBytes,
  });

  final DownloadFailure failure;
  final Uri uri;

  /// The response that failed, for status and header diagnostics. Its body
  /// is already consumed.
  final HttpClientResponse response;
  final String? contentRange;
  final int? expectedBytes;
  final int? actualBytes;

  int get statusCode => response.statusCode;

  /// `expected=…, actual=…` for size failures, else the status line.
  String get sizeDetails => expectedBytes == null
      ? 'HTTP $statusCode'
      : 'expected=$expectedBytes, actual=$actualBytes';

  @override
  String toString() =>
      'ResumableDownloadException(${failure.name}, $uri, $sizeDetails'
      '${contentRange == null ? '' : ', content-range=$contentRange'})';
}

/// Downloads a file into a `.part` sidecar, continuing an earlier attempt
/// with an HTTP byte range.
///
/// The three runtime installers each had their own copy of this loop, and
/// the copies had drifted: one accepted any 206 without checking where its
/// range started, and none of them agreed on when a short or long file was
/// an error. The rules now live here once:
///
/// * a kept part file is resumed only when the server answers 206 with a
///   `Content-Range` that starts exactly at its length; a 200 restarts it;
/// * every chunk checks the [AsrTransferCancellation];
/// * the result must match the known size: short keeps the part file for
///   the next attempt, long deletes it.
///
/// Promoting the part file is left to the caller, which usually verifies a
/// digest first; [promote] does the final rename.
///
/// With [transientRetries] above zero, a dropped connection, a timeout or a
/// short body is retried in place with a byte range for the bytes still
/// missing, so a brief network interruption costs only the bytes that were
/// in flight. Only failures that add no new bytes count against the limit;
/// HTTP errors and corrupt resumes are left to the caller, which may switch
/// to another source.
class ResumableFileDownload {
  ResumableFileDownload({
    required this.clientFactory,
    this.timeout = const Duration(seconds: 60),
    this.userAgent = 'LyricForge/1.0',
    this.transientRetries = 0,
    this.retryDelay = const Duration(seconds: 2),
    Stopwatch Function()? stopwatch,
  }) : assert(transientRetries >= 0),
       _stopwatch = stopwatch ?? Stopwatch.new;

  final AsrDownloadHttpClientFactory clientFactory;

  /// Retries allowed in a row without new bytes for a transport failure.
  final int transientRetries;

  /// Base wait before a retry; it grows with each failure in a row.
  final Duration retryDelay;

  /// Hard cap on the attempts of one fetch, even when every attempt made
  /// progress, so a connection that drops every few kilobytes still ends.
  static const int _maxAttemptsPerFetch = 64;

  /// Bound on connecting, on the response headers and on each gap between
  /// chunks.
  final Duration timeout;
  final String userAgent;
  final Stopwatch Function() _stopwatch;

  /// Speed is reported only after this much time, so the first chunks do not
  /// produce absurd estimates.
  static const Duration _speedWarmUp = Duration(milliseconds: 500);

  static final RegExp _contentRange = RegExp(r'^bytes (\d+)-(\d+)/(\d+|\*)$');

  /// The sidecar a download into [target] writes to.
  static File partFileFor(File target) => File('${target.path}.part');

  /// Replaces [target] with the finished [part] file.
  static Future<void> promote(File part, File target) async {
    if (await target.exists()) await target.delete();
    await part.rename(target.path);
  }

  /// Downloads [uri] into [part].
  ///
  /// With [resume], bytes already in [part] are kept and continued;
  /// otherwise [part] starts empty. [expectedBytes] is the full size when
  /// the caller knows it (from release metadata, say); a part file already
  /// longer than that is discarded before the request.
  ///
  /// Throws [ResumableDownloadException] for the failures it names, the
  /// cancellation once [cancellation] is requested, and network errors
  /// (socket, TLS, timeout) as they are. Before giving up on a transport
  /// failure it retries up to [transientRetries] times in a row, reporting
  /// each retry to [onRetry]; the part file is always kept for that.
  Future<void> fetch(
    Uri uri,
    File part, {
    required AsrTransferCancellation cancellation,
    String proxy = '',
    bool resume = true,
    int? expectedBytes,
    void Function(DownloadProgress progress)? onProgress,
    void Function(DownloadRetry retry)? onRetry,
  }) async {
    var attempts = 0;
    var failuresInARow = 0;
    var resumeThisAttempt = resume;
    while (true) {
      attempts++;
      final before = await _partLength(part);
      try {
        await _fetchOnce(
          uri,
          part,
          cancellation: cancellation,
          proxy: proxy,
          resume: resumeThisAttempt,
          expectedBytes: expectedBytes,
          onProgress: onProgress,
        );
        return;
      } catch (error) {
        if (cancellation.isRequested || !isTransientFailure(error)) rethrow;
        final kept = await _partLength(part);
        failuresInARow = kept > before ? 1 : failuresInARow + 1;
        if (failuresInARow > transientRetries ||
            attempts >= _maxAttemptsPerFetch) {
          rethrow;
        }
        final delay = retryDelay * failuresInARow;
        onRetry?.call(
          DownloadRetry(
            attempt: attempts,
            maxConsecutiveAttempts: transientRetries,
            keptBytes: kept,
            totalBytes: expectedBytes,
            delay: delay,
            error: error,
          ),
        );
        await _waitForRetry(delay, cancellation);
        // The bytes received so far are this transfer's own, so the next
        // attempt continues them even when the caller asked for a fresh
        // start.
        resumeThisAttempt = true;
      }
    }
  }

  /// Whether [error] is a dropped or stalled connection worth retrying
  /// with a byte range, as opposed to an answer from the server.
  static bool isTransientFailure(Object error) {
    if (error is ResumableDownloadException) {
      return error.failure == DownloadFailure.incomplete;
    }
    if (error is FileSystemException) return false;
    return error is SocketException ||
        error is HttpException ||
        error is TimeoutException;
  }

  static Future<int> _partLength(File part) async {
    try {
      return await part.exists() ? await part.length() : 0;
    } on FileSystemException {
      return 0;
    }
  }

  static Future<void> _waitForRetry(
    Duration delay,
    AsrTransferCancellation cancellation,
  ) async {
    const tick = Duration(milliseconds: 100);
    var remaining = delay;
    while (remaining > Duration.zero) {
      cancellation.throwIfRequested();
      final step = remaining < tick ? remaining : tick;
      await Future<void>.delayed(step);
      remaining -= step;
    }
    cancellation.throwIfRequested();
  }

  Future<void> _fetchOnce(
    Uri uri,
    File part, {
    required AsrTransferCancellation cancellation,
    required String proxy,
    required bool resume,
    required int? expectedBytes,
    required void Function(DownloadProgress progress)? onProgress,
  }) async {
    await part.parent.create(recursive: true);
    var existing = await _keptBytes(part, resume, expectedBytes);

    final client = await clientFactory.create(manualProxy: proxy);
    client.userAgent = userAgent;
    cancellation.track(client);
    try {
      final request = await client.getUrl(uri);
      cancellation.track(client, request);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (existing > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
      }
      final response = await request.close().timeout(timeout);
      cancellation.requestDone();

      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        await response.drain<void>().timeout(timeout);
        throw ResumableDownloadException(
          DownloadFailure.httpStatus,
          uri,
          response: response,
        );
      }

      final partial = response.statusCode == HttpStatus.partialContent;
      int? rangeTotal;
      if (partial) {
        rangeTotal = await _checkContentRange(uri, response, part, existing);
      } else {
        existing = 0;
      }
      final contentLength = response.contentLength;
      final total =
          expectedBytes ??
          rangeTotal ??
          (contentLength > 0 ? existing + contentLength : null);

      final received = await _receive(
        response,
        part,
        append: partial && existing > 0,
        alreadyReceived: existing,
        totalBytes: total,
        cancellation: cancellation,
        onProgress: onProgress,
      );
      cancellation.throwIfRequested();
      await _checkSize(uri, response, part, total, received);
    } on ResumableDownloadException {
      rethrow;
    } on TranscriptionException {
      rethrow;
    } catch (_) {
      // An aborted request surfaces as an arbitrary I/O error.
      cancellation.throwIfRequested();
      rethrow;
    } finally {
      cancellation.release(client);
      client.close(force: true);
    }
  }

  Future<int> _keptBytes(File part, bool resume, int? expectedBytes) async {
    if (!await part.exists()) return 0;
    final length = await part.length();
    if (resume && (expectedBytes == null || length <= expectedBytes)) {
      return length;
    }
    await part.delete();
    return 0;
  }

  /// Returns the full size the range announces, or null for `*`.
  Future<int?> _checkContentRange(
    Uri uri,
    HttpClientResponse response,
    File part,
    int existing,
  ) async {
    final header = response.headers.value(HttpHeaders.contentRangeHeader);
    final match = header == null
        ? null
        : _contentRange.firstMatch(header.trim().toLowerCase());
    final start = match == null ? null : int.tryParse(match.group(1)!);
    if (start == existing) {
      final total = match!.group(3)!;
      return total == '*' ? null : int.parse(total);
    }
    await response.drain<void>().timeout(timeout);
    if (await part.exists()) await part.delete();
    throw ResumableDownloadException(
      DownloadFailure.inconsistentResume,
      uri,
      response: response,
      contentRange: header,
    );
  }

  Future<int> _receive(
    HttpClientResponse response,
    File part, {
    required bool append,
    required int alreadyReceived,
    required int? totalBytes,
    required AsrTransferCancellation cancellation,
    required void Function(DownloadProgress progress)? onProgress,
  }) async {
    final sink = part.openWrite(
      mode: append ? FileMode.append : FileMode.write,
    );
    final watch = _stopwatch()..start();
    var received = alreadyReceived;
    try {
      await for (final chunk in response.timeout(timeout)) {
        cancellation.throwIfRequested();
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(
          _sample(received, alreadyReceived, totalBytes, watch.elapsed),
        );
      }
    } finally {
      await sink.close();
    }
    return received;
  }

  static DownloadProgress _sample(
    int received,
    int startedAt,
    int? total,
    Duration elapsed,
  ) {
    final transferred = received - startedAt;
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final speed = elapsed >= _speedWarmUp && transferred > 0
        ? transferred / seconds
        : null;
    final remaining = total != null && total > 0 && speed != null
        ? Duration(seconds: ((total - received) / speed).ceil())
        : null;
    return DownloadProgress(
      receivedBytes: received,
      totalBytes: total,
      bytesPerSecond: speed,
      estimatedRemaining: remaining == null || remaining.isNegative
          ? null
          : remaining,
    );
  }

  Future<void> _checkSize(
    Uri uri,
    HttpClientResponse response,
    File part,
    int? total,
    int received,
  ) async {
    if (total == null || total <= 0 || received == total) return;
    final failure = received < total
        ? DownloadFailure.incomplete
        : DownloadFailure.oversized;
    if (failure == DownloadFailure.oversized) await part.delete();
    throw ResumableDownloadException(
      failure,
      uri,
      response: response,
      expectedBytes: total,
      actualBytes: received,
    );
  }
}
