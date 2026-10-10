import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../project/domain/models/audio_asset.dart';
import '../../../project/domain/models/project_manifest.dart';
import '../../../project/domain/repositories/project_repository.dart';
import '../../domain/models/transcription_models.dart';
import '../../domain/models/transcription_queue_models.dart';
import '../../domain/services/batch_transcription_queue.dart';
import '../../domain/services/project_transcription_workflow.dart';

class FileBatchTranscriptionQueue implements BatchTranscriptionQueue {
  static const _supportedExtensions = <String>{
    'mp3',
    'flac',
    'wav',
    'm4a',
    'aac',
    'ogg',
  };

  final ProjectRepository projectRepository;
  final ProjectTranscriptionWorkflow workflow;
  final Directory? rootDirectory;

  final StreamController<TranscriptionQueueSnapshot> _controller =
      StreamController<TranscriptionQueueSnapshot>.broadcast();
  final List<TranscriptionQueueItem> _items = <TranscriptionQueueItem>[];

  bool _initialized = false;
  bool _paused = false;
  bool _processing = false;
  bool _pauseRequested = false;
  TranscriptionQueuePauseReason? _pauseReason;
  String? _pauseMessage;
  StreamSubscription<TranscriptionProgress>? _progressSubscription;
  Future<void> _writeChain = Future<void>.value();

  FileBatchTranscriptionQueue({
    required this.projectRepository,
    required this.workflow,
    this.rootDirectory,
  });

  @override
  Stream<TranscriptionQueueSnapshot> get snapshots => _controller.stream;

  @override
  TranscriptionQueueSnapshot get current => TranscriptionQueueSnapshot(
        items: List<TranscriptionQueueItem>.unmodifiable(_items),
        isPaused: _paused,
        isProcessing: _processing,
        pauseReason: _pauseReason,
        pauseMessage: _pauseMessage,
      );

  Future<Directory> _dataDirectory() async {
    if (rootDirectory != null) {
      await rootDirectory!.create(recursive: true);
      return rootDirectory!;
    }
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      support.path +
          Platform.pathSeparator +
          'LyricForge' +
          Platform.pathSeparator +
          'Data',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> _storeFile() async {
    final directory = await _dataDirectory();
    return File(
      directory.path + Platform.pathSeparator + 'transcription_queue.json',
    );
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final file = await _storeFile();
    var recoveredInterruptedItem = false;
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          _paused = decoded['paused'] as bool? ?? false;
          final pauseReasonName = decoded['pauseReason'] as String?;
          _pauseReason = TranscriptionQueuePauseReason.values
              .asNameMap()[pauseReasonName];
          _pauseMessage = decoded['pauseMessage'] as String?;
          if (_paused && _pauseReason == null) {
            // Queue files written before pause reasons existed represent user
            // pauses. Never reinterpret an old pause as an environment fault.
            _pauseReason = TranscriptionQueuePauseReason.manual;
          }
          if (!_paused) {
            _pauseReason = null;
            _pauseMessage = null;
          }

          final values = decoded['items'];
          if (values is List) {
            for (final value in values) {
              if (value is! Map) continue;
              var item = TranscriptionQueueItem.fromJson(
                Map<String, dynamic>.from(value),
              );
              final interruptedRunning =
                  item.status == TranscriptionQueueItemStatus.running;
              final interruptedStopping =
                  !_paused &&
                  item.status == TranscriptionQueueItemStatus.paused;
              if (interruptedRunning || interruptedStopping) {
                recoveredInterruptedItem = true;
                item = item.copyWith(
                  status: TranscriptionQueueItemStatus.queued,
                  message: '应用上次退出时处理中断，已恢复到等待队列',
                  updatedAt: DateTime.now(),
                );
              }
              _items.add(item);
            }
          }
        }
      } catch (_) {
        // A damaged queue file must not prevent the app from starting. A new
        // queue will be written after the next mutation.
      }
    }

    if (recoveredInterruptedItem) await _persist();
    _emit();
    if (!_paused && _items.any(_isQueued)) unawaited(_pump());
  }

  @override
  Future<int> enqueuePaths(Iterable<String> paths) async {
    await initialize();
    final existing = _items.map((item) => _pathKey(item.sourcePath)).toSet();
    var added = 0;
    var seed = DateTime.now().microsecondsSinceEpoch;

    for (final raw in paths) {
      final path = _canonical(raw);
      final key = _pathKey(path);
      if (existing.contains(key) || !_isSupported(path)) continue;
      if (!await File(path).exists()) continue;

      final now = DateTime.now();
      _items.add(
        TranscriptionQueueItem(
          id: (seed++).toString(),
          sourcePath: path,
          projectName: _projectName(path),
          createdAt: now,
          updatedAt: now,
        ),
      );
      existing.add(key);
      added++;
    }

    if (added > 0) {
      await _persist();
      _emit();
      if (!_paused) unawaited(_pump());
    }
    return added;
  }

  @override
  Future<void> pause() async {
    await initialize();
    _paused = true;
    _pauseRequested = true;
    _pauseReason = TranscriptionQueuePauseReason.manual;
    _pauseMessage = null;
    await _persist();
    _emit();
    if (workflow.isRunning) await workflow.cancel();
  }

  @override
  Future<void> resume() async {
    await initialize();
    // UI disables resume while the active worker is still unwinding, but keep
    // the service safe for non-UI callers too.
    if (_processing) return;

    _paused = false;
    _pauseRequested = false;
    _pauseReason = null;
    _pauseMessage = null;
    final now = DateTime.now();
    for (var index = 0; index < _items.length; index++) {
      final item = _items[index];
      if (item.status == TranscriptionQueueItemStatus.paused) {
        _items[index] = item.copyWith(
          status: TranscriptionQueueItemStatus.queued,
          message: '等待继续识别',
          updatedAt: now,
        );
      }
    }
    await _persist();
    _emit();
    unawaited(_pump());
  }

  @override
  Future<void> retryFailed() async {
    await initialize();
    final now = DateTime.now();
    var changed = false;
    for (var index = 0; index < _items.length; index++) {
      final item = _items[index];
      if (item.status != TranscriptionQueueItemStatus.failed) continue;
      changed = true;
      _items[index] = item.copyWith(
        status: TranscriptionQueueItemStatus.queued,
        progress: 0,
        message: '等待重试',
        clearError: true,
        updatedAt: now,
      );
    }
    if (!changed) return;
    await _persist();
    _emit();
    if (!_paused) unawaited(_pump());
  }

  @override
  Future<void> remove(String itemId) async {
    await initialize();
    _items.removeWhere(
      (item) =>
          item.id == itemId &&
          item.status != TranscriptionQueueItemStatus.running,
    );
    await _persist();
    _emit();
  }

  @override
  Future<void> clearCompleted() async {
    await initialize();
    _items.removeWhere(
      (item) => item.status == TranscriptionQueueItemStatus.completed,
    );
    await _persist();
    _emit();
  }

  Future<void> _pump() async {
    if (_processing || _paused) return;
    _processing = true;
    _emit();

    try {
      while (!_paused) {
        final index = _items.indexWhere(_isQueued);
        if (index < 0) break;
        await _processItem(index);
      }
    } finally {
      _processing = false;
      _pauseRequested = false;
      _emit();
    }
  }

  Future<void> _processItem(int index) async {
    var item = _items[index];
    item = item.copyWith(
      status: TranscriptionQueueItemStatus.running,
      progress: item.progress.clamp(0.0, 0.99).toDouble(),
      message: item.projectId == null ? '正在创建工程' : '正在恢复工程识别',
      clearError: true,
      updatedAt: DateTime.now(),
    );
    _items[index] = item;
    await _persist();
    _emit();

    try {
      final source = File(item.sourcePath);
      if (!await source.exists()) {
        throw const TranscriptionException.input('源音频文件已经不存在');
      }

      var project = await _resolveProject(item);
      if (project == null) {
        project = await projectRepository.createProject(name: item.projectName);
        project = await projectRepository.updateProject(
          project.copyWith(
            status: ProjectStatus.draft,
            currentStage: ProcessingStage.audioImported,
            audioAsset: AudioAsset(
              originalPath: item.sourcePath,
              format: _extension(item.sourcePath),
            ),
            metadata: {
              ...project.metadata,
              'batchQueueItemId': item.id,
              'batchImportedAt': DateTime.now().toIso8601String(),
            },
          ),
        );
      }

      if (item.projectId != project.id) {
        item = item.copyWith(
          projectId: project.id,
          message: '工程已关联，准备歌词识别',
          updatedAt: DateTime.now(),
        );
        _items[index] = item;
        await _persist();
        _emit();
      }

      // A crash may happen after the project was committed but before the queue
      // item itself was marked complete. Avoid paying for inference twice.
      if (project.hasLyrics &&
          project.currentStage == ProcessingStage.transcriptionComplete) {
        _items[index] = item.copyWith(
          status: TranscriptionQueueItemStatus.completed,
          progress: 1,
          message: '已从工程结果恢复完成状态',
          clearError: true,
          updatedAt: DateTime.now(),
        );
        await _persist();
        _emit();
        return;
      }

      _progressSubscription = workflow.progressStream.listen((progress) {
        final currentIndex = _items.indexWhere((entry) => entry.id == item.id);
        if (currentIndex < 0) return;
        final currentItem = _items[currentIndex];
        if (currentItem.status != TranscriptionQueueItemStatus.running) return;
        _items[currentIndex] = currentItem.copyWith(
          progress: progress.progress,
          message: progress.message,
          updatedAt: DateTime.now(),
        );
        _emit();
      });

      await workflow.transcribeProject(project.id);
      _items[index] = _items[index].copyWith(
        status: TranscriptionQueueItemStatus.completed,
        progress: 1,
        message: '歌词识别完成',
        clearError: true,
        updatedAt: DateTime.now(),
      );
    } on TranscriptionException catch (error) {
      if (_pauseRequested ||
          (_paused && _pauseReason == TranscriptionQueuePauseReason.manual)) {
        _items[index] = _items[index].copyWith(
          status: TranscriptionQueueItemStatus.paused,
          message: '已暂停，当前歌曲进度已保留',
          updatedAt: DateTime.now(),
        );
      } else if (_isEnvironmentBlocked(error)) {
        _paused = true;
        _pauseReason = TranscriptionQueuePauseReason.environment;
        _pauseMessage = error.toString();
        _items[index] = _items[index].copyWith(
          status: TranscriptionQueueItemStatus.queued,
          message: '识别环境需要修复，队列已保护性暂停',
          error: error.toString(),
          updatedAt: DateTime.now(),
        );
      } else {
        _items[index] = _items[index].copyWith(
          status: TranscriptionQueueItemStatus.failed,
          message: '识别失败，队列将继续处理下一首',
          error: error.toString(),
          updatedAt: DateTime.now(),
        );
      }
    } catch (error) {
      _items[index] = _items[index].copyWith(
        status: TranscriptionQueueItemStatus.failed,
        message: '识别失败，队列将继续处理下一首',
        error: error.toString(),
        updatedAt: DateTime.now(),
      );
    } finally {
      await _progressSubscription?.cancel();
      _progressSubscription = null;
      await _persist();
      _emit();
    }
  }

  Future<ProjectManifest?> _resolveProject(TranscriptionQueueItem item) async {
    final projectId = item.projectId;
    if (projectId != null) {
      final direct = await projectRepository.getProjectById(projectId);
      if (direct != null) return direct;
    }

    // If the app stopped after project persistence but before the queue item
    // received projectId, recover by the durable queue-item marker instead of
    // creating a duplicate project.
    final projects = await projectRepository.getAllProjects();
    for (final project in projects) {
      if (project.metadata['batchQueueItemId']?.toString() == item.id) {
        return project;
      }
    }
    return null;
  }

  bool _isEnvironmentBlocked(TranscriptionException error) {
    if (error.blocksQueue) return true;

    // Backward compatibility for older services and persisted/test errors.
    // New production environment failures should set kind=environment so UI
    // copy can evolve without changing queue behavior.
    final value = error.toString();
    return value.contains('运行时配置') ||
        value.contains('识别环境尚未准备') ||
        value.contains('缺少必要组件') ||
        value.contains('自动安装') ||
        value.contains('模型') ||
        value.contains('磁盘空间不足') ||
        value.contains('运行健康检查失败');
  }

  bool _isQueued(TranscriptionQueueItem item) =>
      item.status == TranscriptionQueueItemStatus.queued;

  bool _isSupported(String path) =>
      _supportedExtensions.contains(_extension(path));

  String _extension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return '';
    return path.substring(dot + 1).toLowerCase();
  }

  String _projectName(String path) {
    final fileName = path.split(Platform.pathSeparator).last;
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  String _canonical(String path) => File(path).absolute.path;

  String _pathKey(String path) {
    final canonical = _canonical(path);
    return Platform.isWindows ? canonical.toLowerCase() : canonical;
  }

  Future<void> _persist() {
    final payload = const JsonEncoder.withIndent('  ').convert({
      'version': 2,
      'paused': _paused,
      'pauseReason': _pauseReason?.name,
      'pauseMessage': _pauseMessage,
      'items': _items.map((item) => item.toJson()).toList(growable: false),
    });
    final previous = _writeChain;
    final operation = () async {
      // A failed previous write should be surfaced to its caller without
      // permanently poisoning all future queue persistence attempts.
      try {
        await previous;
      } catch (_) {}

      final file = await _storeFile();
      final temporary = File(file.path + '.tmp');
      await temporary.writeAsString(payload, flush: true);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    }();
    _writeChain = operation;
    return operation;
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(current);
  }

  @override
  Future<void> dispose() async {
    // Do not persist a user-visible global pause merely because the app is
    // shutting down. If cancellation leaves an item in paused state, startup
    // recovery converts it back to queued when the queue itself was not paused.
    _pauseRequested = true;
    await _progressSubscription?.cancel();
    if (workflow.isRunning) await workflow.cancel();
    await _persist();
    await _controller.close();
  }
}
