import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/models/transcription_models.dart';
import '../../domain/services/asr_runtime_manager.dart';
import '../../domain/services/transcription_profile_resolver.dart';

/// Adds LyricForge-managed Qwen model downloads in front of the existing
/// runtime installer so normal users never need to locate a Hugging Face cache.
class ManagedModelAsrRuntimeManager implements AsrRuntimeManager {
  static const String _qwen17 = 'Qwen/Qwen3-ASR-1.7B';
  static const String _qwen06 = 'Qwen/Qwen3-ASR-0.6B';
  static const String _aligner06 = 'Qwen/Qwen3-ForcedAligner-0.6B';

  static const Map<String, List<String>> _modelFiles = {
    _qwen17: [
      'chat_template.json',
      'config.json',
      'generation_config.json',
      'merges.txt',
      'model-00001-of-00002.safetensors',
      'model-00002-of-00002.safetensors',
      'model.safetensors.index.json',
      'preprocessor_config.json',
      'tokenizer_config.json',
      'vocab.json',
    ],
    _qwen06: [
      'chat_template.json',
      'config.json',
      'generation_config.json',
      'merges.txt',
      'model.safetensors',
      'preprocessor_config.json',
      'tokenizer_config.json',
      'vocab.json',
    ],
    _aligner06: [
      'chat_template.json',
      'config.json',
      'generation_config.json',
      'merges.txt',
      'model.safetensors',
      'preprocessor_config.json',
      'tokenizer_config.json',
      'vocab.json',
    ],
  };

  final AsrRuntimeManager delegate;
  final TranscriptionProfileResolver profileResolver;

  final StreamController<AsrRuntimeInstallProgress> _progressController =
      StreamController<AsrRuntimeInstallProgress>.broadcast();

  bool _installingModels = false;
  bool _cancelRequested = false;
  double _delegateProgressBase = 0;
  HttpClientRequest? _activeRequest;
  HttpClient? _activeClient;

  ManagedModelAsrRuntimeManager({
    required this.delegate,
    required this.profileResolver,
  }) {
    delegate.progressStream.listen(_forwardDelegateProgress);
  }

  @override
  Stream<AsrRuntimeInstallProgress> get progressStream =>
      _progressController.stream;

  @override
  bool get isInstalling => _installingModels || delegate.isInstalling;

  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) async {
    final repaired = await repair(config);
    return delegate.inspect(repaired);
  }

  @override
  Future<TranscriptionConfig> repair(TranscriptionConfig config) async {
    final repaired = await delegate.repair(config);
    if (repaired.mode != TranscriptionMode.highestQuality) return repaired;

    final resolved = await profileResolver.resolve(repaired);
    final expectedModel = _qwenModelForProfile(resolved.profile);
    final expectedAligner = _alignerForProfile(resolved.profile);
    if (expectedModel == null || expectedAligner == null) return repaired;

    final root = await _managedRoot();
    final qwenPath = await _resolvePreparedModel(
      configured: resolved.config.qwenModelPath,
      root: root,
      modelId: expectedModel,
    );
    final alignerPath = await _resolvePreparedModel(
      configured: resolved.config.qwenAlignerModelPath,
      root: root,
      modelId: expectedAligner,
    );

    return repaired.copyWith(
      qwenModelPath: qwenPath ?? expectedModel,
      qwenAlignerModelPath: alignerPath ?? expectedAligner,
    );
  }

  @override
  Future<TranscriptionConfig> installRecommended(
    TranscriptionConfig config,
  ) async {
    if (isInstalling) {
      throw const TranscriptionException('识别环境正在安装，请稍候');
    }

    _cancelRequested = false;
    _delegateProgressBase = 0;

    try {
      final resolved = await profileResolver.resolve(config);
      var prepared = resolved.config;

      final expectedModel = _qwenModelForProfile(resolved.profile);
      final expectedAligner = _alignerForProfile(resolved.profile);
      final shouldManageModels =
          prepared.mode == TranscriptionMode.highestQuality &&
              expectedModel != null &&
              expectedAligner != null;

      if (shouldManageModels) {
        _installingModels = true;
        _delegateProgressBase = 0.62;
        final root = await _managedRoot();

        _emit(
          AsrRuntimeComponent.qwenModel,
          0.01,
          '正在准备 Qwen 模型目录；最高质量模式首次约需下载 6.5 GB',
        );

        final qwenPath = await _useOrInstallModel(
          configured: prepared.qwenModelPath,
          root: root,
          modelId: expectedModel,
          component: AsrRuntimeComponent.qwenModel,
          startProgress: 0.02,
          endProgress: 0.43,
        );
        _throwIfCancelled();

        final alignerPath = await _useOrInstallModel(
          configured: prepared.qwenAlignerModelPath,
          root: root,
          modelId: expectedAligner,
          component: AsrRuntimeComponent.qwenAligner,
          startProgress: 0.43,
          endProgress: 0.61,
        );
        _throwIfCancelled();

        prepared = prepared.copyWith(
          qwenModelPath: qwenPath,
          qwenAlignerModelPath: alignerPath,
        );
        _installingModels = false;
      }

      final installed = await delegate.installRecommended(prepared);
      return repair(installed);
    } finally {
      _activeRequest = null;
      _activeClient = null;
      _installingModels = false;
      _cancelRequested = false;
      _delegateProgressBase = 0;
    }
  }

  Future<String> _useOrInstallModel({
    required String configured,
    required Directory root,
    required String modelId,
    required AsrRuntimeComponent component,
    required double startProgress,
    required double endProgress,
  }) async {
    final configuredPath = configured.trim();
    if (configuredPath.isNotEmpty &&
        await _modelDirectoryComplete(configuredPath, modelId)) {
      _emit(
        component,
        endProgress,
        '${_modelLabel(modelId)} 已在本机找到，无需重复下载',
      );
      return configuredPath;
    }

    final managed = _modelDirectory(root, modelId);
    if (await _modelDirectoryComplete(managed.path, modelId)) {
      _emit(
        component,
        endProgress,
        '${_modelLabel(modelId)} 已安装，正在复用本地文件',
      );
      return managed.path;
    }

    return _installModel(
      root: root,
      modelId: modelId,
      component: component,
      startProgress: startProgress,
      endProgress: endProgress,
    );
  }

  Future<String?> _resolvePreparedModel({
    required String configured,
    required Directory root,
    required String modelId,
  }) async {
    final configuredPath = configured.trim();
    if (configuredPath.isNotEmpty &&
        await _modelDirectoryComplete(configuredPath, modelId)) {
      return configuredPath;
    }

    final managed = _modelDirectory(root, modelId);
    if (await _modelDirectoryComplete(managed.path, modelId)) {
      return managed.path;
    }
    return null;
  }

  Future<String> _installModel({
    required Directory root,
    required String modelId,
    required AsrRuntimeComponent component,
    required double startProgress,
    required double endProgress,
  }) async {
    final files = _modelFiles[modelId];
    if (files == null) {
      throw TranscriptionException('LyricForge 尚未定义 $modelId 的自动下载清单');
    }

    final directory = _modelDirectory(root, modelId);
    await directory.create(recursive: true);

    for (var index = 0; index < files.length; index++) {
      _throwIfCancelled();
      final fileName = files[index];
      final target = File(_join(directory.path, [fileName]));
      final fileStart = index / files.length;
      final fileEnd = (index + 1) / files.length;

      if (await target.exists() && await target.length() > 0) {
        final progress = _mapProgress(
          fileEnd,
          startProgress,
          endProgress,
        );
        _emit(
          component,
          progress,
          '正在检查 ${_modelLabel(modelId)} · ${index + 1}/${files.length}',
        );
        continue;
      }

      await _downloadModelFile(
        modelId: modelId,
        fileName: fileName,
        target: target,
        onProgress: (fraction) {
          final modelFraction = fileStart +
              (fileEnd - fileStart) * fraction;
          _emit(
            component,
            _mapProgress(modelFraction, startProgress, endProgress),
            '正在下载 ${_modelLabel(modelId)} · ${_percent(modelFraction)}',
          );
        },
      );
    }

    if (!await _modelDirectoryComplete(directory.path, modelId)) {
      throw TranscriptionException('${_modelLabel(modelId)} 下载完成后文件检查失败');
    }

    final marker = File(_join(directory.path, ['.lyricforge-model.json']));
    await marker.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'modelId': modelId,
        'downloadedAt': DateTime.now().toUtc().toIso8601String(),
        'files': files,
      }),
      flush: true,
    );

    _emit(
      component,
      endProgress,
      '${_modelLabel(modelId)} 已下载到 LyricForge 托管目录',
    );
    return directory.path;
  }

  Future<void> _downloadModelFile({
    required String modelId,
    required String fileName,
    required File target,
    required void Function(double fraction) onProgress,
  }) async {
    await target.parent.create(recursive: true);
    final part = File('${target.path}.part');
    var existing = await part.exists() ? await part.length() : 0;

    final uri = Uri.parse(
      'https://huggingface.co/$modelId/resolve/main/$fileName?download=true',
    );
    final client = HttpClient()..userAgent = 'LyricForge/1.0';
    _activeClient = client;

    try {
      final request = await client.getUrl(uri);
      _activeRequest = request;
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (existing > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
      }

      final response = await request.close();
      _activeRequest = null;
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        await response.drain<void>();
        throw TranscriptionException(
          '无法下载 ${_modelLabel(modelId)}',
          details: '$fileName: HTTP ${response.statusCode}',
        );
      }

      final append = existing > 0 &&
          response.statusCode == HttpStatus.partialContent;
      if (!append) existing = 0;

      final contentLength = response.contentLength;
      final total = contentLength > 0 ? existing + contentLength : -1;
      var received = existing;
      final sink = part.openWrite(
        mode: append ? FileMode.append : FileMode.write,
      );

      try {
        await for (final chunk in response) {
          _throwIfCancelled();
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            onProgress((received / total).clamp(0.0, 1.0).toDouble());
          }
        }
      } finally {
        await sink.close();
      }

      _throwIfCancelled();
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      onProgress(1.0);
    } on TranscriptionException {
      rethrow;
    } catch (error) {
      if (_cancelRequested) {
        throw const TranscriptionException('识别环境安装已取消');
      }
      throw TranscriptionException(
        '下载 ${_modelLabel(modelId)} 失败',
        details: '$fileName: $error',
      );
    } finally {
      _activeRequest = null;
      _activeClient = null;
      client.close(force: true);
    }
  }

  Future<bool> _modelDirectoryComplete(
    String path,
    String modelId,
  ) async {
    if (path.isEmpty) return false;
    final files = _modelFiles[modelId];
    if (files == null) return false;

    final directory = Directory(path);
    if (!await directory.exists()) return false;

    for (final fileName in files) {
      final file = File(_join(directory.path, [fileName]));
      if (!await file.exists() || await file.length() == 0) return false;
    }
    return true;
  }

  Future<Directory> _managedRoot() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(
      _join(support.path, ['LyricForge', 'ASRRuntime']),
    );
    await Directory(_join(root.path, ['models', 'qwen']))
        .create(recursive: true);
    return root;
  }

  Directory _modelDirectory(Directory root, String modelId) {
    final directoryName = modelId.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]+'),
      '--',
    );
    return Directory(
      _join(root.path, ['models', 'qwen', directoryName]),
    );
  }

  String? _qwenModelForProfile(TranscriptionProfilePreference profile) {
    return switch (profile) {
      TranscriptionProfilePreference.rtx5080HighQuality => _qwen17,
      TranscriptionProfilePreference.intelMacHighQuality => _qwen06,
      _ => null,
    };
  }

  String? _alignerForProfile(TranscriptionProfilePreference profile) {
    return switch (profile) {
      TranscriptionProfilePreference.rtx5080HighQuality ||
      TranscriptionProfilePreference.intelMacHighQuality => _aligner06,
      _ => null,
    };
  }

  String _modelLabel(String modelId) {
    return switch (modelId) {
      _qwen17 => 'Qwen3-ASR 1.7B',
      _qwen06 => 'Qwen3-ASR 0.6B',
      _aligner06 => 'Qwen ForcedAligner 0.6B',
      _ => modelId,
    };
  }

  void _forwardDelegateProgress(AsrRuntimeInstallProgress progress) {
    final base = _delegateProgressBase;
    final mapped = base <= 0
        ? progress.progress
        : base + (1 - base) * progress.progress;
    _emit(progress.component, mapped, progress.message);
  }

  void _emit(
    AsrRuntimeComponent? component,
    double progress,
    String message,
  ) {
    if (_progressController.isClosed) return;
    _progressController.add(
      AsrRuntimeInstallProgress(
        component: component,
        progress: progress.clamp(0.0, 1.0).toDouble(),
        message: message,
      ),
    );
  }

  double _mapProgress(double fraction, double start, double end) {
    return start + (end - start) * fraction.clamp(0.0, 1.0);
  }

  String _percent(double fraction) {
    return '${(fraction * 100).clamp(0, 100).toStringAsFixed(0)}%';
  }

  String _join(String base, List<String> parts) {
    var current = base;
    for (final part in parts) {
      if (current.endsWith(Platform.pathSeparator)) {
        current += part;
      } else {
        current += Platform.pathSeparator + part;
      }
    }
    return current;
  }

  void _throwIfCancelled() {
    if (_cancelRequested) {
      throw const TranscriptionException('识别环境安装已取消');
    }
  }

  @override
  Future<void> cancel() async {
    _cancelRequested = true;
    _activeRequest?.abort();
    _activeClient?.close(force: true);
    _activeRequest = null;
    _activeClient = null;
    await delegate.cancel();
  }
}
