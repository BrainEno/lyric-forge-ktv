import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/diagnostics/best_effort.dart';
import '../../../player/domain/services/audio_library_import_service.dart';
import '../../domain/models/media_hub_session.dart';

typedef IncomingMediaCallback = Future<void> Function(String path);
typedef IncomingDiskSpaceProbe = Future<int?> Function(Directory directory);
typedef MediaHubJsonWriter =
    Future<void> Function(
      HttpResponse response,
      int statusCode,
      Map<String, dynamic> body,
    );

/// Handles authenticated incoming audio uploads to the Media Hub, including
/// concurrency limits, disk-space checks, timeouts, and atomic `.part`
/// reservation/commit.
class HttpMediaHubIncomingUploadHandler {
  static const int _maximumRejectedBodyDrainBytes = 16 * 1024 * 1024;
  static const int _incomingUploadDiskSpaceCheckIntervalBytes =
      64 * 1024 * 1024;
  static const int _maximumConcurrentIncomingUploads = 2;
  static int _activeIncomingUploads = 0;
  static final Set<String> _activeIncomingSessionTokens = <String>{};

  final String _logTag;
  final Uuid _uuid;
  final Directory? incomingDirectory;
  final IncomingMediaCallback? onIncomingFile;
  final int maxIncomingAudioBytes;
  final Duration incomingUploadIdleTimeout;
  final Duration incomingUploadTotalTimeout;
  final Duration incomingRejectionDrainGrace;
  final int minimumFreeSpaceBytes;
  final IncomingDiskSpaceProbe _diskSpaceProbe;
  final MediaHubJsonWriter _writeJson;

  const HttpMediaHubIncomingUploadHandler({
    String logTag = 'transfer.hub',
    required Uuid uuid,
    required this.incomingDirectory,
    required this.onIncomingFile,
    required this.maxIncomingAudioBytes,
    required this.incomingUploadIdleTimeout,
    required this.incomingUploadTotalTimeout,
    required this.incomingRejectionDrainGrace,
    required this.minimumFreeSpaceBytes,
    required IncomingDiskSpaceProbe diskSpaceProbe,
    required MediaHubJsonWriter writeJson,
  }) : _logTag = logTag,
       _uuid = uuid,
       _diskSpaceProbe = diskSpaceProbe,
       _writeJson = writeJson;

  Future<void> receiveIncomingAudio(
    HttpRequest request,
    MediaHubSession session,
  ) async {
    final rawName = request.uri.queryParameters['filename']?.trim();
    if (rawName == null || rawName.isEmpty) {
      await _rejectIncomingUpload(
        request,
        HttpStatus.badRequest,
        'missing_filename',
      );
      return;
    }

    final safeName = _safeIncomingName(rawName);
    final dot = safeName.lastIndexOf('.');
    final extension = dot < 0 ? '' : safeName.substring(dot + 1).toLowerCase();
    if (!supportedLocalAudioExtensions.contains(extension)) {
      await _rejectIncomingUpload(
        request,
        HttpStatus.unsupportedMediaType,
        'unsupported_audio_extension',
      );
      return;
    }

    final expectedLength = request.contentLength >= 0
        ? request.contentLength
        : null;
    if (expectedLength != null && expectedLength > maxIncomingAudioBytes) {
      await _rejectIncomingUpload(
        request,
        HttpStatus.requestEntityTooLarge,
        'upload_too_large',
        details: {'maxBytes': maxIncomingAudioBytes},
      );
      return;
    }

    if (!_tryReserveIncomingUpload(session.token)) {
      await _rejectIncomingUpload(
        request,
        HttpStatus.tooManyRequests,
        'upload_limit_reached',
        retryAfterSeconds: 5,
      );
      return;
    }

    File? partialFile;
    _IncomingUploadReservation? incomingReservation;
    IOSink? uploadSink;
    StreamIterator<List<int>>? uploadIterator;
    Future<bool>? pendingMoveNext;
    Timer? idleTimer;
    Timer? totalTimer;
    var resourcesReleased = false;

    void cancelUploadTimers() {
      idleTimer?.cancel();
      idleTimer = null;
      totalTimer?.cancel();
      totalTimer = null;
    }

    // Everything the upload holds on disk and in the session is released
    // before the client is told the outcome, so a client (or test) that reacts
    // to the response never observes a stale partial file, reservation marker,
    // or busy upload slot.
    Future<void> releaseUploadResources() async {
      if (resourcesReleased) return;
      resourcesReleased = true;
      cancelUploadTimers();
      await _discardPartialUpload(uploadSink, partialFile);
      uploadSink = null;
      partialFile = null;
      final reservation = incomingReservation;
      incomingReservation = null;
      if (reservation != null) {
        await _releaseIncomingDestinationReservation(reservation);
      }
      _releaseIncomingUpload(session.token);
    }

    Future<void> rejectInFlight(
      int statusCode,
      String errorCode, {
      Map<String, dynamic> details = const {},
    }) async {
      await releaseUploadResources();
      await _rejectIncomingUpload(
        request,
        statusCode,
        errorCode,
        details: details,
        body: uploadIterator,
        pendingMoveNext: pendingMoveNext,
      );
    }

    try {
      final directory = await _resolveIncomingDirectory();
      await directory.create(recursive: true);

      final availableBytes = await _availableDiskSpace(directory);
      if (availableBytes == null) {
        throw const _IncomingUploadStorageCheckUnavailable();
      }
      if (!_hasEnoughFreeSpace(availableBytes, expectedLength ?? 0)) {
        throw const _IncomingUploadInsufficientSpace();
      }

      final reservation = await _reserveIncomingDestination(
        directory,
        safeName,
      );
      incomingReservation = reservation;
      final destination = reservation.destination;
      final partial = reservation.partial;
      partialFile = partial;

      final sink = partial.openWrite();
      uploadSink = sink;
      var received = 0;
      var nextDiskSpaceCheckAt = _incomingUploadDiskSpaceCheckIntervalBytes;
      final iterator = StreamIterator<List<int>>(request);
      uploadIterator = iterator;
      final timeoutSignal = Completer<String>();

      void reportTimeout(String reason) {
        if (!timeoutSignal.isCompleted) timeoutSignal.complete(reason);
      }

      void resetIdleTimer() {
        idleTimer?.cancel();
        idleTimer = Timer(
          incomingUploadIdleTimeout,
          () => reportTimeout('idle'),
        );
      }

      Never throwUploadTimeout(String reason) {
        if (reason == 'idle') {
          throw TimeoutException('Incoming audio upload was idle.');
        }
        throw const _IncomingUploadTotalTimeout();
      }

      resetIdleTimer();
      totalTimer = Timer(
        incomingUploadTotalTimeout,
        () => reportTimeout('total'),
      );

      while (true) {
        final move = iterator.moveNext();
        // Kept until the move resolves: a timeout can win the race below, and
        // the rejection drain must continue this pending read rather than
        // start a second one on the same iterator.
        pendingMoveNext = move;
        final event = await Future.any<Object>([
          move.then((hasNext) => _IncomingUploadChunkSignal(hasNext)),
          timeoutSignal.future.then(
            (reason) => _IncomingUploadTimeoutSignal(reason),
          ),
        ]);
        if (event is _IncomingUploadTimeoutSignal) {
          throwUploadTimeout(event.reason);
        }
        pendingMoveNext = null;
        if (timeoutSignal.isCompleted) {
          throwUploadTimeout(await timeoutSignal.future);
        }

        final chunkEvent = event as _IncomingUploadChunkSignal;
        if (!chunkEvent.hasNext) break;
        resetIdleTimer();
        final chunk = iterator.current;
        if (chunk.length > maxIncomingAudioBytes - received) {
          throw const _IncomingUploadTooLarge();
        }

        if (received + chunk.length >= nextDiskSpaceCheckAt) {
          final latestFreeBytes = await _availableDiskSpace(directory);
          if (timeoutSignal.isCompleted) {
            throwUploadTimeout(await timeoutSignal.future);
          }
          if (latestFreeBytes == null) {
            throw const _IncomingUploadStorageCheckUnavailable();
          }
          if (!_hasEnoughFreeSpace(latestFreeBytes, chunk.length)) {
            throw const _IncomingUploadInsufficientSpace();
          }
          nextDiskSpaceCheckAt =
              received +
              chunk.length +
              _incomingUploadDiskSpaceCheckIntervalBytes;
        }

        sink.add(chunk);
        received += chunk.length;
      }
      cancelUploadTimers();

      await sink.flush();
      await sink.close();
      uploadSink = null;

      if (expectedLength != null && received != expectedLength) {
        await releaseUploadResources();
        await _writeJson(request.response, HttpStatus.badRequest, {
          'error': 'length_mismatch',
          'expected': expectedLength,
          'received': received,
        });
        return;
      }

      await partial.rename(destination.path);
      partialFile = null;
      final callback = onIncomingFile;
      if (callback != null) {
        try {
          await callback(destination.path);
        } catch (error) {
          if (await destination.exists()) await destination.delete();
          await releaseUploadResources();
          await _writeJson(request.response, HttpStatus.internalServerError, {
            'error': 'library_import_failed',
            'message': error.toString(),
          });
          return;
        }
      }

      await releaseUploadResources();
      await _writeJson(request.response, HttpStatus.created, {
        'status': 'ok',
        'filename': destination.uri.pathSegments.last,
        'byteLength': received,
        'imported': callback != null,
      });
    } on _IncomingUploadTooLarge {
      await rejectInFlight(
        HttpStatus.requestEntityTooLarge,
        'upload_too_large',
        details: {'maxBytes': maxIncomingAudioBytes},
      );
    } on TimeoutException {
      await rejectInFlight(HttpStatus.requestTimeout, 'upload_idle_timeout');
    } on _IncomingUploadTotalTimeout {
      await rejectInFlight(HttpStatus.requestTimeout, 'upload_total_timeout');
    } on _IncomingUploadStorageCheckUnavailable {
      await rejectInFlight(
        HttpStatus.insufficientStorage,
        'storage_check_unavailable',
      );
    } on _IncomingUploadInsufficientSpace {
      await rejectInFlight(
        HttpStatus.insufficientStorage,
        'insufficient_storage',
        details: {'minimumFreeBytes': minimumFreeSpaceBytes},
      );
    } on FileSystemException {
      await rejectInFlight(
        HttpStatus.insufficientStorage,
        'storage_write_failed',
      );
    } catch (_) {
      await releaseUploadResources();
      rethrow;
    } finally {
      await releaseUploadResources();
      try {
        await uploadIterator?.cancel();
      } catch (_) {
        // The request may already have been closed by the client.
      }
    }
  }

  bool _tryReserveIncomingUpload(String sessionToken) {
    if (_activeIncomingUploads >= _maximumConcurrentIncomingUploads ||
        !_activeIncomingSessionTokens.add(sessionToken)) {
      return false;
    }
    _activeIncomingUploads++;
    return true;
  }

  void _releaseIncomingUpload(String sessionToken) {
    if (_activeIncomingSessionTokens.remove(sessionToken)) {
      _activeIncomingUploads--;
    }
  }

  Future<int?> _availableDiskSpace(Directory directory) async {
    try {
      return await _diskSpaceProbe(directory);
    } catch (_) {
      return null;
    }
  }

  bool _hasEnoughFreeSpace(int availableBytes, int payloadBytes) {
    if (availableBytes < minimumFreeSpaceBytes) return false;
    return payloadBytes <= availableBytes - minimumFreeSpaceBytes;
  }

  Future<void> _rejectIncomingUpload(
    HttpRequest request,
    int statusCode,
    String errorCode, {
    Map<String, dynamic> details = const {},
    int? retryAfterSeconds,
    StreamIterator<List<int>>? body,
    Future<bool>? pendingMoveNext,
  }) async {
    final response = request.response;
    response.persistentConnection = false;
    if (retryAfterSeconds != null) {
      response.headers.set('Retry-After', retryAfterSeconds.toString());
    }
    final bytes = utf8.encode(jsonEncode({'error': errorCode, ...details}));
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.contentLength = bytes.length;
    response.add(bytes);
    try {
      // Send the answer first, then consume what the client is still sending
      // so closing does not reset the connection under an unread response.
      await response.flush();
      await _drainRejectedUploadBody(
        request,
        iterator: body,
        pendingMoveNext: pendingMoveNext,
      );
    } catch (_) {
      // The client may already have gone away; closing below still releases
      // the connection.
    }
    try {
      await response.close();
    } catch (_) {
      // Nothing is left to report to a client that disconnected.
    }
  }

  /// Reads and discards the rest of a rejected request body for at most
  /// [incomingRejectionDrainGrace] and [_maximumRejectedBodyDrainBytes].
  ///
  /// Uses [iterator] (continuing [pendingMoveNext] if a read is in flight)
  /// when the body was already being consumed; otherwise reads the request
  /// directly. Never stores the bytes.
  Future<void> _drainRejectedUploadBody(
    HttpRequest request, {
    StreamIterator<List<int>>? iterator,
    Future<bool>? pendingMoveNext,
  }) async {
    final grace = incomingRejectionDrainGrace;
    if (grace <= Duration.zero) return;
    final ownsIterator = iterator == null;
    final body = iterator ?? StreamIterator<List<int>>(request);
    final elapsed = Stopwatch()..start();
    var drained = 0;
    var next = pendingMoveNext;
    try {
      while (drained <= _maximumRejectedBodyDrainBytes) {
        final remaining = grace - elapsed.elapsed;
        if (remaining <= Duration.zero) break;
        final move = next ?? body.moveNext();
        next = null;
        final hasNext = await move.timeout(remaining, onTimeout: () => false);
        if (!hasNext) break;
        drained += body.current.length;
      }
    } catch (_) {
      // A client that disconnects mid-drain needs nothing more from us.
    } finally {
      if (ownsIterator) {
        await bestEffort(_logTag, '取消被拒绝的请求体', body.cancel);
      }
    }
  }

  Future<void> _discardPartialUpload(IOSink? sink, File? partial) async {
    if (sink != null) {
      await bestEffort(_logTag, '关闭未完成的上传文件', sink.close);
    }
    if (partial != null) {
      // A leftover partial file wastes space in the import folder.
      await bestEffort(_logTag, '删除未完成的上传文件', () async {
        if (await partial.exists()) await partial.delete();
      }, impact: BestEffortImpact.degraded);
    }
  }

  Future<Directory> _resolveIncomingDirectory() async {
    final configured = incomingDirectory;
    if (configured != null) return configured;
    final documents = await getApplicationDocumentsDirectory();
    return Directory(
      '${documents.path}${Platform.pathSeparator}LyricForge${Platform.pathSeparator}Incoming',
    );
  }

  Future<_IncomingUploadReservation> _reserveIncomingDestination(
    Directory directory,
    String fileName,
  ) async {
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    final extension = dot > 0 ? fileName.substring(dot) : '';
    var suffix = 0;

    while (true) {
      final candidateName = suffix == 0
          ? fileName
          : '${stem}_$suffix$extension';
      final candidate = File(
        '${directory.path}${Platform.pathSeparator}$candidateName',
      );
      suffix++;

      if (await candidate.exists()) continue;

      // Exclusive marker creation serializes destination selection for
      // concurrent uploads without relying on a process-local lock.
      final reservation = File('${candidate.path}.reserve');
      try {
        await reservation.create(exclusive: true);
      } on FileSystemException {
        if (await reservation.exists()) continue;
        rethrow;
      }

      try {
        // Recheck after claiming the marker in case another writer that does
        // not use reservations created the final file between the first check
        // and the exclusive marker creation.
        if (await candidate.exists()) {
          await _releaseReservationFile(reservation);
          continue;
        }
        final partial = await _createUniqueIncomingPartial(directory);
        return _IncomingUploadReservation(
          destination: candidate,
          partial: partial,
          reservationFile: reservation,
        );
      } catch (_) {
        await _releaseReservationFile(reservation);
        rethrow;
      }
    }
  }

  Future<File> _createUniqueIncomingPartial(Directory directory) async {
    while (true) {
      final partial = File(
        '${directory.path}${Platform.pathSeparator}.lyricforge-${_uuid.v4()}.part',
      );
      try {
        await partial.create(exclusive: true);
        return partial;
      } on FileSystemException {
        if (await partial.exists()) continue;
        rethrow;
      }
    }
  }

  Future<void> _releaseIncomingDestinationReservation(
    _IncomingUploadReservation reservation,
  ) async {
    await _releaseReservationFile(reservation.reservationFile);
  }

  Future<void> _releaseReservationFile(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A stale marker is safer than allowing another upload to reuse a name
      // that may still be in the process of being committed or imported.
    }
  }

  String _safeIncomingName(String value) {
    var name = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    while (name.startsWith('.')) {
      name = name.substring(1);
    }
    return name.isEmpty ? 'audio' : name;
  }
}

class _IncomingUploadChunkSignal {
  const _IncomingUploadChunkSignal(this.hasNext);

  final bool hasNext;
}

class _IncomingUploadTimeoutSignal {
  const _IncomingUploadTimeoutSignal(this.reason);

  final String reason;
}

class _IncomingUploadTooLarge implements Exception {
  const _IncomingUploadTooLarge();
}

class _IncomingUploadTotalTimeout implements Exception {
  const _IncomingUploadTotalTimeout();
}

class _IncomingUploadStorageCheckUnavailable implements Exception {
  const _IncomingUploadStorageCheckUnavailable();
}

class _IncomingUploadInsufficientSpace implements Exception {
  const _IncomingUploadInsufficientSpace();
}

class _IncomingUploadReservation {
  const _IncomingUploadReservation({
    required this.destination,
    required this.partial,
    required this.reservationFile,
  });

  final File destination;
  final File partial;
  final File reservationFile;
}
