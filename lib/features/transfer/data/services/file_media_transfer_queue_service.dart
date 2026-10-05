import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/media_transfer_batch.dart';
import '../../domain/models/media_transfer_queue.dart';
import '../../domain/models/remote_audio_track.dart';
import '../../domain/services/media_hub_client_service.dart';
import '../../domain/services/media_transfer_queue_service.dart';
import '../../domain/services/media_transfer_service.dart';

class FileMediaTransferQueueService implements MediaTransferQueueService {
  final MediaTransferService transfers;
  final MediaHubClientService client;
  final Directory? rootDirectory;
  final Uuid _uuid;

  final StreamController<MediaTransferQueueSnapshot> _controller =
      StreamController<MediaTransferQueueSnapshot>.broadcast();
  final List<MediaTransferQueueItem> _items = <MediaTransferQueueItem>[];
  Future<void> _writeChain = Future<void>.value();

  MediaTransferQueueSnapshot _state = const MediaTransferQueueSnapshot();
  bool _initialized = false;
  bool _processing = false;

  FileMediaTransferQueueService({
    required this.transfers,
    required this.client,
    this.rootDirectory,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  @override
  Stream<MediaTransferQueueSnapshot> get stateStream => _controller.stream;

  @override
  MediaTransferQueueSnapshot get currentState => _state;

  Future<Directory> _dataDirectory() async {
    if (rootDirectory != null) {
      await rootDirectory!.create(recursive: true);
      return rootDirectory!;
    }
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}LyricForge${Platform.pathSeparator}Data',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> _storeFile() async {
    final directory = await _dataDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}media_transfer_queue.json',
    );
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final file = await _storeFile();
    var recoveredInterrupted = false;

    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          final rawItems = decoded['items'];
          if (rawItems is List) {
            for (final raw in rawItems) {
              if (raw is! Map) continue;
              try {
                var item = MediaTransferQueueItem.fromJson(
                  Map<String, dynamic>.from(raw),
                );
                if (item.status == MediaTransferQueueStatus.transferring) {
                  item = item.copyWith(
                    status: MediaTransferQueueStatus.queued,
                    updatedAt: DateTime.now(),
                    bytesTransferred: 0,
                    clearError: true,
                  );
                  recoveredInterrupted = true;
                }
                _items.add(item);
              } catch (_) {
                // One malformed transfer row must not destroy the full queue.
              }
            }
          }
          final paused = decoded['paused'] as bool? ?? false;
          _state = MediaTransferQueueSnapshot(
            items: List.unmodifiable(_items),
            isPaused: paused,
            pauseReason: decoded['pauseReason'] as String?,
          );
        }
      } catch (_) {
        _items.clear();
        _state = const MediaTransferQueueSnapshot();
      }
    }

    _emit();
    if (recoveredInterrupted) await _persist();
    if (!_state.isPaused && client.isConnected && _items.any(_isQueued)) {
      unawaited(processPending());
    }
  }

  @override
  Future<void> enqueueDownloads(List<RemoteAudioTrack> tracks) async {
    await _ensureInitialized();
    if (tracks.isEmpty) return;
    final now = DateTime.now();

    for (final track in tracks) {
      final existingIndex = _items.indexWhere(
        (item) =>
            item.direction == MediaTransferDirection.downloadFromDesktop &&
            item.remoteTrack?.id == track.id,
      );
      if (existingIndex >= 0) {
        final existing = _items[existingIndex];
        if (existing.status == MediaTransferQueueStatus.failed) {
          _items[existingIndex] = existing.copyWith(
            status: MediaTransferQueueStatus.queued,
            updatedAt: now,
            bytesTransferred: 0,
            clearError: true,
            clearDestinationPath: true,
          );
        }
        // queued/transferring/completed downloads remain a single logical task.
        continue;
      }

      _items.add(
        MediaTransferQueueItem(
          id: 'download:${track.id}',
          direction: MediaTransferDirection.downloadFromDesktop,
          title: track.title,
          status: MediaTransferQueueStatus.queued,
          createdAt: now,
          updatedAt: now,
          remoteTrack: track,
          totalBytes: track.byteLength > 0 ? track.byteLength : null,
        ),
      );
    }

    await _persistAndEmit();
    if (!_state.isPaused && client.isConnected) unawaited(processPending());
  }

  @override
  Future<void> enqueueUploads(List<String> sourcePaths) async {
    await _ensureInitialized();
    if (sourcePaths.isEmpty) return;
    final now = DateTime.now();

    for (final rawPath in sourcePaths) {
      if (rawPath.trim().isEmpty) continue;
      final path = File(rawPath).absolute.path;
      final duplicate = _items.any(
        (item) =>
            item.direction == MediaTransferDirection.uploadToDesktop &&
            _pathKey(item.sourcePath) == _pathKey(path) &&
            (item.status == MediaTransferQueueStatus.queued ||
                item.status == MediaTransferQueueStatus.transferring),
      );
      if (duplicate) continue;

      final file = File(path);
      final fileName = file.uri.pathSegments.isEmpty
          ? path
          : file.uri.pathSegments.last;
      final total = await file.exists() ? await file.length() : null;
      _items.add(
        MediaTransferQueueItem(
          id: 'upload:${_uuid.v4()}',
          direction: MediaTransferDirection.uploadToDesktop,
          title: _titleFromFileName(fileName),
          status: MediaTransferQueueStatus.queued,
          createdAt: now,
          updatedAt: now,
          sourcePath: path,
          totalBytes: total,
        ),
      );
    }

    await _persistAndEmit();
    if (!_state.isPaused && client.isConnected) unawaited(processPending());
  }

  @override
  Future<void> processPending() async {
    await _ensureInitialized();
    if (_processing || _state.isPaused) return;
    if (!client.isConnected) {
      _state = _state.copyWith(
        isPaused: true,
        pauseReason: '尚未连接另一台设备，连接后可继续传输',
      );
      await _persistAndEmit();
      return;
    }

    _processing = true;
    _state = _state.copyWith(isProcessing: true);
    _emit();

    try {
      while (!_state.isPaused) {
        final index = _items.indexWhere(_isQueued);
        if (index < 0) break;
        await _processItem(index);
      }
    } finally {
      _processing = false;
      _state = _state.copyWith(isProcessing: false);
      _emit();
    }
  }

  Future<void> _processItem(int index) async {
    final initial = _items[index];
    _items[index] = initial.copyWith(
      status: MediaTransferQueueStatus.transferring,
      updatedAt: DateTime.now(),
      bytesTransferred: 0,
      clearError: true,
    );
    await _persistAndEmit();

    MediaTransferBatchResult result;
    try {
      if (initial.direction == MediaTransferDirection.downloadFromDesktop) {
        final track = initial.remoteTrack;
        if (track == null) throw StateError('下载任务缺少远程歌曲信息');
        result = await transfers.downloadRemoteTracks(
          [track],
          onProgress: (progress) => _applyProgress(initial.id, progress),
        );
      } else {
        final path = initial.sourcePath;
        if (path == null || path.isEmpty) {
          throw StateError('上传任务缺少本地文件路径');
        }
        result = await transfers.uploadLocalFiles(
          [path],
          onProgress: (progress) => _applyProgress(initial.id, progress),
        );
      }
    } catch (error) {
      _markFailed(initial.id, error.toString());
      await _persistAndEmit();
      return;
    }

    final itemResult = result.items.isEmpty ? null : result.items.first;
    final currentIndex = _items.indexWhere((item) => item.id == initial.id);
    if (currentIndex < 0) return;
    final current = _items[currentIndex];

    if (itemResult?.succeeded == true) {
      _items[currentIndex] = current.copyWith(
        status: MediaTransferQueueStatus.completed,
        updatedAt: DateTime.now(),
        bytesTransferred: current.totalBytes ?? current.bytesTransferred,
        destinationPath: itemResult?.destinationPath,
        clearError: true,
      );
    } else {
      _items[currentIndex] = current.copyWith(
        status: MediaTransferQueueStatus.failed,
        updatedAt: DateTime.now(),
        error: itemResult?.error ?? '传输失败',
      );
    }
    await _persistAndEmit();
  }

  void _applyProgress(String queueId, MediaTransferItemProgress progress) {
    final index = _items.indexWhere((item) => item.id == queueId);
    if (index < 0) return;
    final current = _items[index];
    final nextStatus = switch (progress.status) {
      MediaTransferItemStatus.queued =>
        current.status == MediaTransferQueueStatus.transferring
            ? MediaTransferQueueStatus.transferring
            : MediaTransferQueueStatus.queued,
      MediaTransferItemStatus.transferring =>
        MediaTransferQueueStatus.transferring,
      MediaTransferItemStatus.completed => MediaTransferQueueStatus.completed,
      MediaTransferItemStatus.failed => MediaTransferQueueStatus.failed,
    };
    _items[index] = current.copyWith(
      status: nextStatus,
      updatedAt: DateTime.now(),
      bytesTransferred: progress.bytesTransferred,
      totalBytes: progress.totalBytes,
      destinationPath: progress.destinationPath,
      error: progress.error,
      clearError: progress.error == null,
    );
    _emit();
  }

  void _markFailed(String id, String message) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    _items[index] = _items[index].copyWith(
      status: MediaTransferQueueStatus.failed,
      updatedAt: DateTime.now(),
      error: message,
    );
  }

  @override
  Future<void> pause({String? reason}) async {
    await _ensureInitialized();
    _state = _state.copyWith(
      isPaused: true,
      pauseReason: reason ?? '已暂停，当前文件完成后停止后续传输',
    );
    await _persistAndEmit();
  }

  @override
  Future<void> resume() async {
    await _ensureInitialized();
    _state = _state.copyWith(
      isPaused: false,
      clearPauseReason: true,
    );
    await _persistAndEmit();
    unawaited(processPending());
  }

  @override
  Future<void> retry(String id) async {
    await _ensureInitialized();
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0 || _items[index].status != MediaTransferQueueStatus.failed) {
      return;
    }
    _items[index] = _items[index].copyWith(
      status: MediaTransferQueueStatus.queued,
      updatedAt: DateTime.now(),
      bytesTransferred: 0,
      clearError: true,
      clearDestinationPath: true,
    );
    await _persistAndEmit();
    if (!_state.isPaused && client.isConnected) unawaited(processPending());
  }

  @override
  Future<void> retryFailed() async {
    await _ensureInitialized();
    final now = DateTime.now();
    var changed = false;
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (item.status != MediaTransferQueueStatus.failed) continue;
      _items[i] = item.copyWith(
        status: MediaTransferQueueStatus.queued,
        updatedAt: now,
        bytesTransferred: 0,
        clearError: true,
        clearDestinationPath: true,
      );
      changed = true;
    }
    if (!changed) return;
    await _persistAndEmit();
    if (!_state.isPaused && client.isConnected) unawaited(processPending());
  }

  @override
  Future<void> remove(String id) async {
    await _ensureInitialized();
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0 ||
        _items[index].status == MediaTransferQueueStatus.transferring) {
      return;
    }
    _items.removeAt(index);
    await _persistAndEmit();
  }

  @override
  Future<void> clearCompleted() async {
    await _ensureInitialized();
    _items.removeWhere(
      (item) => item.status == MediaTransferQueueStatus.completed,
    );
    await _persistAndEmit();
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) await initialize();
  }

  bool _isQueued(MediaTransferQueueItem item) =>
      item.status == MediaTransferQueueStatus.queued;

  String _pathKey(String? path) {
    if (path == null) return '';
    final normalized = File(path).absolute.path;
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  String _titleFromFileName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  Future<void> _persistAndEmit() async {
    _emit();
    await _persist();
  }

  Future<void> _persist() {
    final payload = const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'paused': _state.isPaused,
      'pauseReason': _state.pauseReason,
      'items': _items.map((item) => item.toJson()).toList(growable: false),
    });
    final previous = _writeChain;
    final operation = () async {
      try {
        await previous;
      } catch (_) {}
      final file = await _storeFile();
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(payload, flush: true);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    }();
    _writeChain = operation;
    return operation;
  }

  void _emit() {
    _state = _state.copyWith(
      items: List.unmodifiable(_items),
      isProcessing: _processing,
    );
    if (!_controller.isClosed) _controller.add(_state);
  }

  @override
  Future<void> dispose() async {
    await _writeChain;
    await _controller.close();
  }
}
