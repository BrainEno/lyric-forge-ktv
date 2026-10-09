import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/models/transcription_models.dart';
import '../../domain/services/asr_runtime_manager.dart';

/// Keeps local transcription usable even when the optional Qwen runtime is
/// temporarily unavailable.
///
/// The existing managed installer remains authoritative for FFmpeg, models and
/// Qwen. This wrapper only guarantees a standalone Whisper runtime first, then
/// prepares a complete Whisper-only baseline before attempting the optional
/// highest-quality upgrade.
class ResilientAsrRuntimeManager implements AsrRuntimeManager {
  static const String _whisperCppReleaseTag = 'b5130';
  static const String _whisperWindowsX64Asset = 'whisper-bin-x64.zip';

  final AsrRuntimeManager delegate;
  final Future<String?> Function(TranscriptionConfig config)?
      whisperRuntimeBootstrap;

  final StreamController<AsrRuntimeInstallProgress> _progressController =
      StreamController<AsrRuntimeInstallProgress>.broadcast();

  StreamSubscription<AsrRuntimeInstallProgress>? _delegateSubscription;
  bool _installing = false;
  bool _cancelRequested = false;
  HttpClientRequest? _activeRequest;
  HttpClient? _activeClient;
  double _delegatePhaseStart = 0;
  double _delegatePhaseEnd = 1;

  ResilientAsrRuntimeManager({
    required this.delegate,
    this.whisperRuntimeBootstrap,
  }) {
    _delegateSubscription =
        delegate.progressStream.listen(_forwardDelegateProgress);
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
    if (isInstalling) {
      throw const TranscriptionException('识别环境正在安装，请稍候');
    }

    _installing = true;
    _cancelRequested = false;
    _delegatePhaseStart = 0;
    _delegatePhaseEnd = 1;

    try {
      final wantsHighestQuality =
          config.mode == TranscriptionMode.highestQuality;

      _emit(
        AsrRuntimeComponent.whisperRuntime,
        0.01,
        wantsHighestQuality
            ? '先准备可独立工作的 Whisper 基线，再安装最高质量组件'
            : '正在准备 Whisper 本地识别环境',
      );

      final whisperPath = await _ensureWhisperRuntime(config);
      _throwIfCancelled();

      final baselineConfig = config.copyWith(
        mode: TranscriptionMode.whisperOnly,
        whisperExecutable: whisperPath ?? config.whisperExecutable,
      );

      _delegatePhaseStart = 0.08;
      _delegatePhaseEnd = wantsHighestQuality ? 0.55 : 1.0;
      final baseline = await delegate.installRecommended(baselineConfig);
      _throwIfCancelled();

      if (!wantsHighestQuality) {
        _emit(null, 1.0, 'Whisper 本地歌词识别环境已准备完成');
        return await repair(baseline);
      }

      _emit(
        AsrRuntimeComponent.qwenRuntime,
        0.56,
        'Whisper 已可用，继续尝试最高质量 Qwen 组件',
      );

      final upgradeConfig = config.copyWith(
        whisperExecutable: baseline.whisperExecutable,
        modelPath: baseline.modelPath,
        ffmpegExecutable: baseline.ffmpegExecutable,
      );

      _delegatePhaseStart = 0.56;
      _delegatePhaseEnd = 1.0;
      try {
        final upgraded = await delegate.installRecommended(upgradeConfig);
        _throwIfCancelled();
        _emit(null, 1.0, '最高质量本地歌词识别环境已准备完成');
        return await repair(upgraded);
      } on TranscriptionException catch (error) {
        if (_cancelRequested || _isCancellation(error)) rethrow;

        _emit(
          AsrRuntimeComponent.qwenRuntime,
          1.0,
          'Qwen 高质量组件暂不可用；已自动保留 Whisper 基线，可立即开始识别',
        );
        return await repair(baseline);
      }
    } finally {
      _activeRequest = null;
      _activeClient?.close(force: true);
      _activeClient = null;
      _delegatePhaseStart = 0;
      _delegatePhaseEnd = 1;
      _installing = false;
      _cancelRequested = false;
    }
  }

  Future<String?> _ensureWhisperRuntime(
    TranscriptionConfig config,
  ) async {
    final injected = whisperRuntimeBootstrap;
    if (injected != null) {
      return injected(config);
    }

    final baseline = config.copyWith(mode: TranscriptionMode.whisperOnly);
    try {
      final status = await delegate.inspect(baseline);
      for (final component in status.components) {
        if (component.component == AsrRuntimeComponent.whisperRuntime &&
            component.state == AsrRuntimeComponentState.ready) {
          final path = component.resolvedPath;
          if (path != null && path.trim().isNotEmpty) return path;
          return config.whisperExecutable;
        }
      }
    } catch (_) {
      // Detection should never prevent the managed bootstrap from trying.
    }

    final root = await _managedRoot();
    final whisperRoot = Directory(
      _join(root.path, ['whisper', _whisperCppReleaseTag]),
    );
    final existing = await _findFile(whisperRoot, _whisperName);
    if (existing != null && await _executableLooksUsable(existing.path)) {
      _emit(
        AsrRuntimeComponent.whisperRuntime,
        0.08,
        '已找到 LyricForge 托管的 Whisper runtime',
      );
      return existing.path;
    }

    if (!Platform.isWindows) {
      // The existing managed bundle still owns macOS installation. Keeping the
      // fallback Windows-only avoids silently depending on Homebrew or Xcode.
      return null;
    }

    final downloads = Directory(_join(root.path, ['downloads']));
    await downloads.create(recursive: true);
    final archive = File(
      _join(downloads.path, ['whisper-$_whisperCppReleaseTag-x64.zip']),
    );

    final uri = Uri.parse(
      'https://github.com/ggml-org/whisper.cpp/releases/download/'
      '$_whisperCppReleaseTag/$_whisperWindowsX64Asset',
    );

    _emit(
      AsrRuntimeComponent.whisperRuntime,
      0.02,
      '正在下载独立 Whisper runtime（无需等待 Qwen 发布包）',
    );
    await _download(
      uri,
      archive,
      startProgress: 0.02,
      endProgress: 0.06,
    );
    _throwIfCancelled();

    if (await whisperRoot.exists()) {
      await whisperRoot.delete(recursive: true);
    }
    await whisperRoot.create(recursive: true);

    _emit(
      AsrRuntimeComponent.whisperRuntime,
      0.065,
      '正在安装 Whisper runtime',
    );
    await _extractZip(archive.path, whisperRoot.path);
    _throwIfCancelled();

    final executable = await _findFile(whisperRoot, _whisperName);
    if (executable == null) {
      throw const TranscriptionException(
        'Whisper 安装包不完整：没有找到 whisper-cli.exe',
      );
    }

    if (!await _executableLooksUsable(executable.path)) {
      throw const TranscriptionException(
        'Whisper runtime 已下载，但启动检查失败',
      );
    }

    _emit(
      AsrRuntimeComponent.whisperRuntime,
      0.08,
      'Whisper runtime 已准备完成',
    );
    return executable.path;
  }

  Future<void> _download(
    Uri uri,
    File target, {
    required double startProgress,
    required double endProgress,
  }) async {
    await target.parent.create(recursive: true);
    final part = File('${target.path}.part');
    var existing = await part.exists() ? await part.length() : 0;

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
          '无法下载 Whisper runtime',
          details: 'HTTP ${response.statusCode}: $uri',
        );
      }

      final append =
          existing > 0 && response.statusCode == HttpStatus.partialContent;
      if (!append) existing = 0;

      final total = response.contentLength > 0
          ? existing + response.contentLength
          : -1;
      var received = existing;
      final sink = part.openWrite(
        mode: append ? FileMode.append : FileMode.write,
      );

      try {
        await for (final chunk in response) {
          _throwIfCancelled();
          sink.add(chunk);
          received += chunk.length;

          final fraction = total > 0
              ? (received / total).clamp(0.0, 1.0).toDouble()
              : 0.0;
          _emit(
            AsrRuntimeComponent.whisperRuntime,
            startProgress + (endProgress - startProgress) * fraction,
            total > 0
                ? '正在下载 Whisper runtime · ${_percent(fraction)}'
                : '正在下载 Whisper runtime…',
          );
        }
      } finally {
        await sink.close();
      }

      _throwIfCancelled();
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
    } on TranscriptionException {
      rethrow;
    } catch (error) {
      if (_cancelRequested) {
        throw const TranscriptionException('识别环境安装已取消');
      }
      throw TranscriptionException(
        '下载 Whisper runtime 失败',
        details: error.toString(),
      );
    } finally {
      _activeRequest = null;
      client.close(force: true);
      if (identical(_activeClient, client)) _activeClient = null;
    }
  }

  Future<void> _extractZip(String archive, String destination) async {
    final result = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'Expand-Archive -LiteralPath ${_psQuote(archive)} '
            '-DestinationPath ${_psQuote(destination)} -Force',
      ],
    );
    if (result.exitCode != 0) {
      throw TranscriptionException(
        'Whisper runtime 解压失败',
        details: result.stderr.toString(),
      );
    }
  }

  Future<bool> _executableLooksUsable(String executable) async {
    try {
      final result = await Process.run(executable, const ['--help']);
      if (result.exitCode == 0) return true;
      final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
      return output.contains('usage') || output.contains('whisper');
    } catch (_) {
      return false;
    }
  }

  Future<File?> _findFile(Directory root, String fileName) async {
    if (!await root.exists()) return null;
    await for (final entity in root.list(recursive: true)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.isEmpty
          ? entity.path
          : entity.uri.pathSegments.last;
      if (name.toLowerCase() == fileName.toLowerCase()) return entity;
    }
    return null;
  }

  Future<Directory> _managedRoot() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(
      _join(support.path, ['LyricForge', 'ASRRuntime']),
    );
    await root.create(recursive: true);
    return root;
  }

  void _forwardDelegateProgress(AsrRuntimeInstallProgress progress) {
    final span = _delegatePhaseEnd - _delegatePhaseStart;
    final mapped = _delegatePhaseStart + span * progress.progress;
    _emit(progress.component, mapped, progress.message);
  }

  bool _isCancellation(TranscriptionException error) {
    return error.message.contains('取消');
  }

  void _throwIfCancelled() {
    if (_cancelRequested) {
      throw const TranscriptionException('识别环境安装已取消');
    }
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

  String get _whisperName =>
      Platform.isWindows ? 'whisper-cli.exe' : 'whisper-cli';

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

  String _psQuote(String value) {
    return "'${value.replaceAll("'", "''")}'";
  }

  String _percent(double fraction) {
    return '${(fraction * 100).clamp(0, 100).toStringAsFixed(0)}%';
  }

  @override
  Future<void> cancel() async {
    if (!isInstalling) return;
    _cancelRequested = true;
    _activeRequest?.abort();
    _activeClient?.close(force: true);
    _activeRequest = null;
    _activeClient = null;
    await delegate.cancel();
  }

  Future<void> dispose() async {
    _cancelRequested = true;
    _activeRequest?.abort();
    _activeClient?.close(force: true);
    await _delegateSubscription?.cancel();
    await _progressController.close();
  }
}
