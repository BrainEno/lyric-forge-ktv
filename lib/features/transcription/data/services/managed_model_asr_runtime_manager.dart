import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/models/transcription_models.dart';
import '../../domain/services/asr_runtime_manager.dart';
import '../../domain/services/transcription_profile_resolver.dart';
import 'hugging_face_file_metadata.dart';

/// Adds LyricForge-managed Qwen model downloads in front of the existing
/// runtime installer so normal users never need to locate a Hugging Face cache.
class ManagedModelAsrRuntimeManager implements AsrRuntimeManager {
  static const String _qwen17 = 'Qwen/Qwen3-ASR-1.7B';
  static const String _qwen06 = 'Qwen/Qwen3-ASR-0.6B';
  static const String _aligner06 = 'Qwen/Qwen3-ForcedAligner-0.6B';
  static const String _runtimeReleaseTag = 'asr-runtime-v1';

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
        await _preflightRuntimeBundle(prepared, resolved.profile);
        _throwIfCancelled();

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

  Future<void> _preflightRuntimeBundle(
    TranscriptionConfig config,
    TranscriptionProfilePreference profile,
  ) async {
    final status = await delegate.inspect(config);
    final whisperReady = _componentReady(
      status,
      AsrRuntimeComponent.whisperRuntime,
    );
    final qwenReady = config.mode != TranscriptionMode.highestQuality ||
        _componentReady(status, AsrRuntimeComponent.qwenRuntime);
    if (whisperReady && qwenReady) return;

    final asset = switch (profile) {
      TranscriptionProfilePreference.rtx5080HighQuality =>
        'lyricforge-asr-runtime-windows-x64-cuda.zip',
      TranscriptionProfilePreference.intelMacHighQuality =>
        'lyricforge-asr-runtime-macos-x64.zip',
      _ => null,
    };
    if (asset == null) return;

    final uri = Uri.parse(
      'https://github.com/BrainEno/lyric-forge-ktv/releases/download/'
      '$_runtimeReleaseTag/$asset',
    );
    final client = HttpClient()..userAgent = 'LyricForge/1.0';
    _activeClient = client;

    try {
      _emit(
        AsrRuntimeComponent.qwenRuntime,
        0.005,
        '正在检查识别引擎安装包是否可用',
      );
      final request = await client.headUrl(uri);
      _activeRequest = request;
      final response = await request.close();
      _activeRequest = null;
      await response.drain<void>();

      if (response.statusCode < 200 || response.statusCode >= 400) {
        throw TranscriptionException(
          'LyricForge 识别引擎安装包暂不可用，因此尚未开始下载大型模型。',
          details: '$asset: HTTP ${response.statusCode}',
        );
      }
    } on TranscriptionException {
      rethrow;
    } catch (error) {
      if (_cancelRequested) {
        throw const TranscriptionException('识别环境安装已取消');
      }
      throw TranscriptionException(
        '无法确认 LyricForge 识别引擎安装包，因此尚未开始下载大型模型。',
        details: error.toString(),
      );
    } finally {
      _activeRequest = null;
      _activeClient = null;
      client.close(force: true);
    }
  }

  bool _componentReady(
    AsrRuntimeStatus status,
    AsrRuntimeComponent component,
  ) {
    for (final item in status.components) {
      if (item.component == component) {
        return item.state == AsrRuntimeComponentState.ready;
      }
    }
    return false;
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
    if (await _modelDirectoryComplete(
      managed.path,
      modelId,
      requireIntegrityMarker: true,
    )) {
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
    if (await _modelDirectoryComplete(
      managed.path,
      modelId,
      requireIntegrityMarker: true,
    )) {
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
    final verifiedFiles = <Map<String, Object?>>[];

    for (var index = 0; index < files.length; index++) {
      _throwIfCancelled();
      final fileName = files[index];
      final target = File(_join(directory.path, [fileName]));
      final fileStart = index / files.length;
      final fileEnd = (index + 1) / files.length;
      final metadata = await _fetchModelFileMetadata(
        modelId: modelId,
        fileName: fileName,
      );

      var reusable = false;
      if (await target.exists()) {
        reusable = await _verifyLocalModelFile(target, metadata);
        if (!reusable) {
          await target.delete();
        }
      }

      if (reusable) {
        final progress = _mapProgress(fileEnd, startProgress, endProgress);
        _emit(
          component,
          progress,
          '已校验 ${_modelLabel(modelId)} · ${index + 1}/${files.length}',
        );
      } else {
        await _downloadModelFile(
          modelId: modelId,
          fileName: fileName,
          target: target,
          metadata: metadata,
          onProgress: (fraction) {
            final modelFraction =
                fileStart + (fileEnd - fileStart) * fraction;
            _emit(
              component,
              _mapProgress(modelFraction, startProgress, endProgress),
              '正在下载 ${_modelLabel(modelId)} · ${_percent(modelFraction)}',
            );
          },
        );
      }

      verifiedFiles.add({
        'name': fileName,
        ...metadata.toJson(),
      });
    }

    final marker = File(_join(directory.path, ['.lyricforge-model.json']));
    await marker.writeAsString(
      jsonEncode({
        'schemaVersion': 2,
        'modelId': modelId,
        'verifiedAt': DateTime.now().toUtc().toIso8601String(),
        'files': verifiedFiles,
      }),
      flush: true,
    );

    if (!await _modelDirectoryComplete(
      directory.path,
      modelId,
      requireIntegrityMarker: true,
    )) {
      throw TranscriptionException('${_modelLabel(modelId)} 完整性记录写入后检查失败');
    }

    _emit(
      component,
      endProgress,
      '${_modelLabel(modelId)} 已下载并通过完整性校验',
    );
    return directory.path;
  }

  Future<void> _downloadModelFile({
    required String modelId,
    required String fileName,
    required File target,
    required HuggingFaceFileMetadata metadata,
    required void Function(double fraction) onProgress,
  }) async {
    await target.parent.create(recursive: true);
    final part = File('${target.path}.part');
    var existing = await part.exists() ? await part.length() : 0;

    if (existing > metadata.sizeBytes) {
      await part.delete();
      existing = 0;
    } else if (existing == metadata.sizeBytes && existing > 0) {
      if (await _verifyLocalModelFile(part, metadata)) {
        if (await target.exists()) await target.delete();
        await part.rename(target.path);
        onProgress(1.0);
        return;
      }
      await part.delete();
      existing = 0;
    }

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

      final append =
          existing > 0 && response.statusCode == HttpStatus.partialContent;
      if (append) {
        final contentRange =
            response.headers.value(HttpHeaders.contentRangeHeader)?.toLowerCase();
        if (contentRange == null ||
            !contentRange.startsWith('bytes $existing-')) {
          await response.drain<void>();
          if (await part.exists()) await part.delete();
          throw TranscriptionException(
            '${_modelLabel(modelId)} 断点续传响应不一致，已清理临时文件',
            details: '$fileName: content-range=$contentRange',
          );
        }
      } else {
        existing = 0;
      }

      var received = existing;
      final sink = part.openWrite(
        mode: append ? FileMode.append : FileMode.write,
      );

      try {
        await for (final chunk in response) {
          _throwIfCancelled();
          sink.add(chunk);
          received += chunk.length;
          onProgress(
            (received / metadata.sizeBytes).clamp(0.0, 1.0).toDouble(),
          );
        }
      } finally {
        await sink.close();
      }

      _throwIfCancelled();
      final actualSize = await part.length();
      if (actualSize < metadata.sizeBytes) {
        throw TranscriptionException(
          '${_modelLabel(modelId)} 下载未完成，下次将从断点继续',
          details: '$fileName: expected=${metadata.sizeBytes}, actual=$actualSize',
        );
      }
      if (actualSize > metadata.sizeBytes) {
        await part.delete();
        throw TranscriptionException(
          '${_modelLabel(modelId)} 文件大小异常，已清理损坏的临时文件',
          details: '$fileName: expected=${metadata.sizeBytes}, actual=$actualSize',
        );
      }

      if (!await _verifyLocalModelFile(part, metadata)) {
        await part.delete();
        if (await target.exists()) await target.delete();
        throw TranscriptionException(
          '${_modelLabel(modelId)} 完整性校验失败，已删除损坏文件',
          details: '$fileName: etag=${metadata.etag}',
        );
      }

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

  Future<HuggingFaceFileMetadata> _fetchModelFileMetadata({
    required String modelId,
    required String fileName,
  }) async {
    final uri = Uri.parse(
      'https://huggingface.co/$modelId/resolve/main/$fileName?download=true',
    );
    final client = HttpClient()..userAgent = 'LyricForge/1.0';
    _activeClient = client;

    try {
      final request = await client.headUrl(uri);
      _activeRequest = request;
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close();
      _activeRequest = null;

      if (response.statusCode < 200 || response.statusCode >= 400) {
        await response.drain<void>();
        throw TranscriptionException(
          '无法读取 ${_modelLabel(modelId)} 文件元数据',
          details: '$fileName: HTTP ${response.statusCode}',
        );
      }

      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        headers[name.toLowerCase()] = values.join(',');
      });
      await response.drain<void>();

      try {
        return HuggingFaceFileMetadata.fromHeaders(headers);
      } on FormatException catch (error) {
        throw TranscriptionException(
          '${_modelLabel(modelId)} 缺少可信的远端完整性元数据',
          details: '$fileName: ${error.message}',
        );
      }
    } on TranscriptionException {
      rethrow;
    } catch (error) {
      if (_cancelRequested) {
        throw const TranscriptionException('识别环境安装已取消');
      }
      throw TranscriptionException(
        '无法读取 ${_modelLabel(modelId)} 文件元数据',
        details: '$fileName: $error',
      );
    } finally {
      _activeRequest = null;
      _activeClient = null;
      client.close(force: true);
    }
  }

  Future<bool> _verifyLocalModelFile(
    File file,
    HuggingFaceFileMetadata metadata,
  ) async {
    if (!await file.exists()) return false;
    if (await file.length() != metadata.sizeBytes) return false;

    final expectedSha256 = metadata.sha256;
    if (expectedSha256 == null) return true;
    return _verifySha256(file.path, expectedSha256);
  }

  Future<bool> _verifySha256(String path, String expected) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('certutil', ['-hashfile', path, 'SHA256']);
        if (result.exitCode != 0) return false;
        final output = result.stdout.toString().toLowerCase();
        return output.contains(expected.toLowerCase());
      }

      if (Platform.isMacOS) {
        final result = await Process.run('/usr/bin/shasum', ['-a', '256', path]);
        if (result.exitCode != 0) return false;
        final actual = result.stdout.toString().trim().split(' ').first;
        return actual.toLowerCase() == expected.toLowerCase();
      }

      final result = await Process.run('sha256sum', [path]);
      if (result.exitCode != 0) return false;
      final actual = result.stdout.toString().trim().split(' ').first;
      return actual.toLowerCase() == expected.toLowerCase();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _modelDirectoryComplete(
    String path,
    String modelId, {
    bool requireIntegrityMarker = false,
  }) async {
    if (path.isEmpty) return false;
    final files = _modelFiles[modelId];
    if (files == null) return false;

    final directory = Directory(path);
    if (!await directory.exists()) return false;

    for (final fileName in files) {
      final file = File(_join(directory.path, [fileName]));
      if (!await file.exists() || await file.length() == 0) return false;
    }

    final marker = File(_join(directory.path, ['.lyricforge-model.json']));
    if (!await marker.exists()) return !requireIntegrityMarker;

    try {
      final decoded = jsonDecode(await marker.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['schemaVersion'] != 2 ||
          decoded['modelId'] != modelId ||
          decoded['files'] is! List) {
        return false;
      }

      final entries = (decoded['files'] as List)
          .whereType<Map>()
          .map((entry) => entry.cast<String, Object?>())
          .toList();

      for (final fileName in files) {
        Map<String, Object?>? entry;
        for (final candidate in entries) {
          if (candidate['name'] == fileName) {
            entry = candidate;
            break;
          }
        }
        if (entry == null) return false;

        final metadata = HuggingFaceFileMetadata.fromJson(entry);
        final file = File(_join(directory.path, [fileName]));
        if (await file.length() != metadata.sizeBytes) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
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
    if (profile == TranscriptionProfilePreference.rtx5080HighQuality ||
        profile == TranscriptionProfilePreference.intelMacHighQuality) {
      return _aligner06;
    }
    return null;
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
    final normalized = fraction.clamp(0.0, 1.0).toDouble();
    return start + (end - start) * normalized;
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
