import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/models/transcription_models.dart';
import '../../domain/services/asr_runtime_manager.dart';
import '../../domain/services/transcription_profile_resolver.dart';

class ManagedAsrRuntimeManager implements AsrRuntimeManager {
  static const String _runtimeReleaseTag = 'asr-runtime-v1';
  static const String _whisperModelName = 'ggml-large-v3.bin';
  static const String _whisperModelSha256 =
      '64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2';

  static final Uri _whisperModelUri = Uri.parse(
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/'
    'ggml-large-v3.bin?download=true',
  );

  final TranscriptionProfileResolver profileResolver;

  final StreamController<AsrRuntimeInstallProgress> _progressController =
      StreamController<AsrRuntimeInstallProgress>.broadcast();

  bool _installing = false;
  bool _cancelRequested = false;
  HttpClientRequest? _activeRequest;
  Process? _activeProcess;

  ManagedAsrRuntimeManager({
    required this.profileResolver,
  });

  @override
  Stream<AsrRuntimeInstallProgress> get progressStream =>
      _progressController.stream;

  @override
  bool get isInstalling => _installing;

  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) async {
    final profile = await profileResolver.resolve(config);
    final root = await _managedRoot();
    final repaired = await _repairPaths(profile.config, root);

    final ffmpeg = await _resolveExecutable(
      repaired.ffmpegExecutable,
      managedCandidates: [
        _join(root.path, ['ffmpeg', 'bin', _ffmpegName]),
      ],
      commandName: _ffmpegName,
    );
    final whisper = await _resolveExecutable(
      repaired.whisperExecutable,
      managedCandidates: [
        _join(root.path, ['bundle', 'bin', _whisperName]),
      ],
      commandName: _whisperName,
    );
    final qwen = await _resolveExecutable(
      repaired.qwenExecutable,
      managedCandidates: [
        _join(root.path, ['bundle', 'bin', _qwenName]),
      ],
      commandName: _qwenName,
    );

    final managedWhisperModel =
        _join(root.path, ['models', 'whisper', _whisperModelName]);
    final whisperModel = await _resolveFile(
      repaired.modelPath,
      managedWhisperModel,
    );
    final whisperModelReady = whisperModel != null &&
        await _validWhisperModel(whisperModel);

    final qwenMarker = _qwenReadyMarker(root, profile.profile);
    final markerReady =
        await _qwenMarkerMatches(qwenMarker, repaired);
    final qwenModelLocal = await _modelReferenceExists(
      repaired.qwenModelPath,
    );
    final alignerLocal = await _modelReferenceExists(
      repaired.qwenAlignerModelPath,
    );

    final components = <AsrRuntimeComponentStatus>[
      _component(
        AsrRuntimeComponent.ffmpeg,
        'FFmpeg 音频处理',
        ffmpeg != null,
        readyDetail: '已自动找到音频处理组件',
        missingDetail: '尚未安装；可由 LyricForge 自动安装',
        path: ffmpeg,
      ),
      _component(
        AsrRuntimeComponent.whisperRuntime,
        'Whisper 识别引擎',
        whisper != null,
        readyDetail: 'Whisper runtime 已就绪',
        missingDetail: '尚未安装；可由 LyricForge 自动安装',
        path: whisper,
      ),
      _component(
        AsrRuntimeComponent.whisperModel,
        'Whisper large-v3 模型',
        whisperModelReady,
        readyDetail: 'large-v3 模型已下载并通过大小检查',
        missingDetail: '需要下载约 3.1 GB 模型',
        path: whisperModelReady ? whisperModel : null,
      ),
      if (repaired.mode == TranscriptionMode.highestQuality) ...[
        _component(
          AsrRuntimeComponent.qwenRuntime,
          'Qwen3-ASR 识别引擎',
          qwen != null,
          readyDetail: 'Qwen native runtime 已就绪',
          missingDetail: _profileSupportsManagedRuntime(profile.profile)
              ? '尚未安装；可由 LyricForge 自动安装'
              : '当前自定义 Profile 需要在高级设置中指定 runtime',
          path: qwen,
          unavailable: !_profileSupportsManagedRuntime(profile.profile),
        ),
        _component(
          AsrRuntimeComponent.qwenModel,
          _qwenModelLabel(repaired.qwenModelPath),
          markerReady || qwenModelLocal,
          readyDetail: markerReady
              ? 'Qwen 模型已下载并通过启动检查'
              : '已找到本地 Qwen 模型',
          missingDetail: '首次安装时会自动下载并缓存',
        ),
        _component(
          AsrRuntimeComponent.qwenAligner,
          'Qwen ForcedAligner 0.6B',
          markerReady || alignerLocal,
          readyDetail: markerReady
              ? 'ForcedAligner 已下载并通过启动检查'
              : '已找到本地 ForcedAligner',
          missingDetail: '首次安装时会自动下载并缓存',
        ),
      ],
    ];;

    return AsrRuntimeStatus(
      profile: profile,
      components: components,
      managedRoot: root.path,
    );
  }

  @override
  Future<TranscriptionConfig> repair(
    TranscriptionConfig config,
  ) async {
    final profile = await profileResolver.resolve(config);
    final root = await _managedRoot();
    return _repairPaths(profile.config, root);
  }

  Future<TranscriptionConfig> _repairPaths(
    TranscriptionConfig config,
    Directory root,
  ) async {
    final ffmpeg = await _resolveExecutable(
      config.ffmpegExecutable,
      managedCandidates: [
        _join(root.path, ['ffmpeg', 'bin', _ffmpegName]),
      ],
      commandName: _ffmpegName,
    );
    final whisper = await _resolveExecutable(
      config.whisperExecutable,
      managedCandidates: [
        _join(root.path, ['bundle', 'bin', _whisperName]),
      ],
      commandName: _whisperName,
    );
    final qwen = await _resolveExecutable(
      config.qwenExecutable,
      managedCandidates: [
        _join(root.path, ['bundle', 'bin', _qwenName]),
      ],
      commandName: _qwenName,
    );

    final managedWhisperModel =
        _join(root.path, ['models', 'whisper', _whisperModelName]);
    final whisperModel =
        await _resolveFile(config.modelPath, managedWhisperModel);

    return config.copyWith(
      ffmpegExecutable: ffmpeg ?? config.ffmpegExecutable,
      whisperExecutable: whisper ?? config.whisperExecutable,
      qwenExecutable: qwen ?? config.qwenExecutable,
      modelPath: whisperModel ?? config.modelPath,
    );
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

    try {
      final profile = await profileResolver.resolve(config);
      if (!_profileSupportsManagedRuntime(profile.profile)) {
        throw const TranscriptionException(
          '自动安装目前支持 RTX 5080 和 Intel Mac Profile；'
          '自定义 Profile 请使用高级设置',
        );
      }

      final root = await _managedRoot();
      await _ensureDirectories(root);

      _emit(null, 0.01, '正在检查本机已有的识别组件');

      var repaired = await _repairPaths(profile.config, root);

      var qwenPath = await _resolveExecutable(
        repaired.qwenExecutable,
        managedCandidates: [
          _join(root.path, ['bundle', 'bin', _qwenName]),
        ],
        commandName: _qwenName,
      );
      var whisperPath = await _resolveExecutable(
        repaired.whisperExecutable,
        managedCandidates: [
          _join(root.path, ['bundle', 'bin', _whisperName]),
        ],
        commandName: _whisperName,
      );

      final needsQwen =
          repaired.mode == TranscriptionMode.highestQuality;
      if (whisperPath == null || (needsQwen && qwenPath == null)) {
        final installed = await _installManagedRuntimeBundle(
          root,
          profile.profile,
        );
        qwenPath = installed.$1;
        whisperPath = installed.$2;
      }

      _throwIfCancelled();

      var ffmpegPath = await _resolveExecutable(
        repaired.ffmpegExecutable,
        managedCandidates: [
          _join(root.path, ['ffmpeg', 'bin', _ffmpegName]),
        ],
        commandName: _ffmpegName,
      );
      if (ffmpegPath == null) {
        ffmpegPath = await _installFfmpeg(root);
      }

      _throwIfCancelled();

      final whisperModelPath =
          _join(root.path, ['models', 'whisper', _whisperModelName]);
      if (!await _validWhisperModel(whisperModelPath)) {
        await _installWhisperModel(root, whisperModelPath);
      }

      _throwIfCancelled();

      repaired = profile.config.copyWith(
        qwenExecutable: qwenPath ?? profile.config.qwenExecutable,
        whisperExecutable: whisperPath,
        ffmpegExecutable: ffmpegPath,
        modelPath: whisperModelPath,
      );

      if (needsQwen) {
        final marker = _qwenReadyMarker(root, profile.profile);
        final markerReady = await _qwenMarkerMatches(marker, repaired);
        if (!markerReady) {
          final executable = qwenPath;
          if (executable == null) {
            throw const TranscriptionException(
              'Qwen runtime 安装失败，请重新安装识别环境',
            );
          }
          await _prepareQwenModels(
            root: root,
            executable: executable,
            config: repaired,
            profile: profile.profile,
          );
        }
      }

      _emit(null, 1.0, '本地歌词识别环境已准备完成');
      return repaired;
    } finally {
      _activeRequest = null;
      _activeProcess = null;
      _installing = false;
      _cancelRequested = false;
    }
  }

  Future<(String, String)> _installManagedRuntimeBundle(
    Directory root,
    TranscriptionProfilePreference profile,
  ) async {
    _emit(
      AsrRuntimeComponent.qwenRuntime,
      0.05,
      '正在下载 LyricForge 识别引擎',
    );

    final downloads = Directory(_join(root.path, ['downloads']));
    final archive = File(_join(downloads.path, ['asr-runtime.zip']));
    final uri = _runtimeBundleUri(profile);

    try {
      await _download(
        uri,
        archive,
        component: AsrRuntimeComponent.qwenRuntime,
        startProgress: 0.05,
        endProgress: 0.22,
      );
    } on HttpException catch (error) {
      throw TranscriptionException(
        '无法下载 LyricForge Qwen runtime。'
        '可能是当前版本的 runtime release 尚未发布，请稍后重试。',
        details: error.message,
      );
    }

    final bundle = Directory(_join(root.path, ['bundle']));
    if (await bundle.exists()) {
      await bundle.delete(recursive: true);
    }
    await bundle.create(recursive: true);

    _emit(
      AsrRuntimeComponent.qwenRuntime,
      0.23,
      '正在安装本地识别引擎',
    );
    await _extractZip(archive.path, bundle.path);

    final qwen = await _findFile(bundle, _qwenName);
    final whisper = await _findFile(bundle, _whisperName);
    if (qwen == null || whisper == null) {
      throw const TranscriptionException(
        '识别引擎安装包不完整，请重新安装',
      );
    }

    if (!Platform.isWindows) {
      await _makeExecutable(qwen.path);
      await _makeExecutable(whisper.path);
    }

    await _verifyExecutable(
      qwen.path,
      const ['--help'],
      'Qwen3-ASR runtime',
    );
    await _verifyExecutable(
      whisper.path,
      const ['--help'],
      'Whisper runtime',
    );

    final bin = Directory(_join(bundle.path, ['bin']));
    await bin.create(recursive: true);

    final qwenTarget = File(_join(bin.path, [_qwenName]));
    if (qwen.path != qwenTarget.path) {
      await qwen.copy(qwenTarget.path);
      if (!Platform.isWindows) await _makeExecutable(qwenTarget.path);
    }

    final whisperTarget = File(_join(bin.path, [_whisperName]));
    if (whisper.path != whisperTarget.path) {
      await whisper.copy(whisperTarget.path);
      if (!Platform.isWindows) await _makeExecutable(whisperTarget.path);
    }

    return (qwenTarget.path, whisperTarget.path);
  }

  Future<String> _installFfmpeg(Directory root) async {
    _emit(
      AsrRuntimeComponent.ffmpeg,
      0.25,
      '正在下载 FFmpeg 音频处理组件',
    );

    final downloads = Directory(_join(root.path, ['downloads']));
    final archive = File(_join(downloads.path, ['ffmpeg.zip']));
    final uri = Platform.isWindows
        ? Uri.parse(
            'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/'
            'ffmpeg-master-latest-win64-lgpl.zip',
          )
        : Uri.parse('https://evermeet.cx/ffmpeg/getrelease/zip');

    await _download(
      uri,
      archive,
      component: AsrRuntimeComponent.ffmpeg,
      startProgress: 0.25,
      endProgress: 0.34,
    );

    final ffmpegRoot = Directory(_join(root.path, ['ffmpeg']));
    if (await ffmpegRoot.exists()) {
      await ffmpegRoot.delete(recursive: true);
    }
    await ffmpegRoot.create(recursive: true);

    await _extractZip(archive.path, ffmpegRoot.path);
    final ffmpeg = await _findFile(ffmpegRoot, _ffmpegName);
    if (ffmpeg == null) {
      throw const TranscriptionException('FFmpeg 安装包中没有找到可执行文件');
    }

    if (!Platform.isWindows) {
      await _makeExecutable(ffmpeg.path);
    }

    await _verifyExecutable(
      ffmpeg.path,
      const ['-version'],
      'FFmpeg',
    );

    final managedBin = Directory(_join(ffmpegRoot.path, ['bin']));
    await managedBin.create(recursive: true);
    final target = File(_join(managedBin.path, [_ffmpegName]));
    if (ffmpeg.path != target.path) {
      await ffmpeg.copy(target.path);
      if (!Platform.isWindows) await _makeExecutable(target.path);
    }

    return target.path;
  }

  Future<void> _installWhisperModel(
    Directory root,
    String targetPath,
  ) async {
    _emit(
      AsrRuntimeComponent.whisperModel,
      0.36,
      '正在下载 Whisper large-v3（约 3.1 GB，可断点续传）',
    );

    final target = File(targetPath);
    await target.parent.create(recursive: true);

    await _download(
      _whisperModelUri,
      target,
      component: AsrRuntimeComponent.whisperModel,
      startProgress: 0.36,
      endProgress: 0.68,
      resumable: true,
    );

    _emit(
      AsrRuntimeComponent.whisperModel,
      0.69,
      '正在校验 Whisper large-v3 文件',
    );

    final valid = await _verifySha256(
      target.path,
      _whisperModelSha256,
    );
    if (!valid) {
      await target.delete();
      throw const TranscriptionException(
        'Whisper 模型校验失败，已删除损坏文件，请重新安装',
      );
    }
  }

  Future<void> _prepareQwenModels({
    required Directory root,
    required String executable,
    required TranscriptionConfig config,
    required TranscriptionProfilePreference profile,
  }) async {
    _emit(
      AsrRuntimeComponent.qwenModel,
      0.72,
      '正在下载并准备 Qwen 模型；首次安装可能需要较长时间',
    );

    final port = await _reservePort();
    final args = [
      '--device',
      config.qwenDevice,
      '--dtype',
      config.qwenDtype,
      'serve',
      '--model',
      config.qwenModelPath,
      '--host',
      '127.0.0.1',
      '--port',
      port.toString(),
      '--forced-aligner',
      config.qwenAlignerModelPath,
    ];

    Process process;
    try {
      process = await Process.start(
        executable,
        args,
        workingDirectory: File(executable).parent.path,
      );
    } on ProcessException catch (error) {
      throw TranscriptionException(
        '无法启动 Qwen 模型准备程序',
        details: error.message,
      );
    }

    _activeProcess = process;
    final logTail = <String>[];

    void capture(String line) {
      if (logTail.length >= 60) logTail.removeAt(0);
      logTail.add(line);
      final lower = line.toLowerCase();
      if (lower.contains('download') ||
          lower.contains('fetch') ||
          lower.contains('loading')) {
        _emit(
          AsrRuntimeComponent.qwenModel,
          0.78,
          '正在下载 / 加载 Qwen 模型，请保持网络连接',
        );
      }
    }

    final stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(capture);
    final stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(capture);

    var exited = false;
    unawaited(process.exitCode.then((_) => exited = true));

    try {
      const attempts = 2700;
      for (var attempt = 0; attempt < attempts; attempt++) {
        _throwIfCancelled();

        if (exited) {
          throw TranscriptionException(
            'Qwen 模型准备失败',
            details: logTail.join('\n'),
          );
        }

        if (await _healthReady(port)) {
          final marker = _qwenReadyMarker(root, profile);
          await marker.parent.create(recursive: true);
          await marker.writeAsString(
            jsonEncode({
              'preparedAt': DateTime.now().toUtc().toIso8601String(),
              'qwenModel': config.qwenModelPath,
              'alignerModel': config.qwenAlignerModelPath,
              'device': config.qwenDevice,
              'dtype': config.qwenDtype,
            }),
            flush: true,
          );
          _emit(
            AsrRuntimeComponent.qwenAligner,
            0.96,
            'Qwen 与 ForcedAligner 已准备完成',
          );
          return;
        }

        await Future<void>.delayed(const Duration(seconds: 1));
      }

      throw TranscriptionException(
        'Qwen 模型准备超时',
        details: logTail.join('\n'),
      );
    } finally {
      process.kill();
      _activeProcess = null;
      await stdoutSub.cancel();
      await stderrSub.cancel();
    }
  }

  Future<void> _download(
    Uri uri,
    File target, {
    required AsrRuntimeComponent component,
    required double startProgress,
    required double endProgress,
    bool resumable = false,
  }) async {
    await target.parent.create(recursive: true);
    final part = File(target.path + '.part');

    var existing = 0;
    if (resumable && await part.exists()) {
      existing = await part.length();
    } else if (await part.exists()) {
      await part.delete();
    }

    final client = HttpClient();
    client.userAgent = 'LyricForge/1.0';

    try {
      final request = await client.getUrl(uri);
      _activeRequest = request;
      if (existing > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
      }

      final response = await request.close();
      _activeRequest = null;

      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        await response.drain<void>();
        throw HttpException(
          'HTTP ${response.statusCode}',
          uri: uri,
        );
      }

      final append = existing > 0 &&
          response.statusCode == HttpStatus.partialContent;
      if (!append) existing = 0;

      final sink = part.openWrite(
        mode: append ? FileMode.append : FileMode.write,
      );

      final contentLength = response.contentLength;
      final total = contentLength > 0 ? existing + contentLength : -1;
      var received = existing;

      try {
        await for (final chunk in response) {
          _throwIfCancelled();
          sink.add(chunk);
          received += chunk.length;

          final fraction = total > 0
              ? (received / total).clamp(0.0, 1.0).toDouble()
              : 0.0;
          final mapped = startProgress +
              (endProgress - startProgress) * fraction;
          _emit(
            component,
            mapped,
            total > 0
                ? '正在下载 ${_percent(fraction)}'
                : '正在下载…',
          );
        }
      } finally {
        await sink.close();
      }

      if (await target.exists()) await target.delete();
      await part.rename(target.path);
    } finally {
      _activeRequest = null;
      client.close(force: true);
    }
  }

  Future<void> _extractZip(String archive, String destination) async {
    _throwIfCancelled();

    ProcessResult result;
    if (Platform.isWindows) {
      result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          'Expand-Archive -LiteralPath ' +
              _psQuote(archive) +
              ' -DestinationPath ' +
              _psQuote(destination) +
              ' -Force',
        ],
      );
    } else {
      result = await Process.run(
        '/usr/bin/unzip',
        ['-o', archive, '-d', destination],
      );
    }

    if (result.exitCode != 0) {
      throw TranscriptionException(
        '安装包解压失败',
        details: result.stderr.toString(),
      );
    }
  }

  Future<void> _verifyExecutable(
    String executable,
    List<String> args,
    String label,
  ) async {
    try {
      final result = await Process.run(executable, args);
      if (result.exitCode != 0) {
        throw TranscriptionException(
          '$label 安装后无法启动',
          details: result.stderr.toString(),
        );
      }
    } on ProcessException catch (error) {
      throw TranscriptionException(
        '$label 安装后无法启动',
        details: error.message,
      );
    }
  }

  Future<bool> _verifySha256(
    String path,
    String expected,
  ) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run(
          'certutil',
          ['-hashfile', path, 'SHA256'],
        );
        if (result.exitCode != 0) return false;
        final text = result.stdout.toString().toLowerCase();
        return text.contains(expected.toLowerCase());
      }

      final result = await Process.run(
        '/usr/bin/shasum',
        ['-a', '256', path],
      );
      if (result.exitCode != 0) return false;
      final actual = result.stdout.toString().trim().split(' ').first;
      return actual.toLowerCase() == expected.toLowerCase();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _validWhisperModel(String path) async {
    final file = File(path);
    if (!await file.exists()) return false;
    final length = await file.length();
    return length > 2 * 1024 * 1024 * 1024;
  }

  Future<bool> _healthReady(int port) async {
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(Uri.parse('http://127.0.0.1:$port/healthz'))
          .timeout(const Duration(seconds: 2));
      final response =
          await request.close().timeout(const Duration(seconds: 2));
      await response.drain<void>();
      return response.statusCode == HttpStatus.ok;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<int> _reservePort() async {
    final socket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<Directory> _managedRoot() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(
      _join(support.path, ['LyricForge', 'ASRRuntime']),
    );
    await root.create(recursive: true);
    return root;
  }

  Future<void> _ensureDirectories(Directory root) async {
    for (final relative in [
      ['downloads'],
      ['bundle'],
      ['ffmpeg'],
      ['models', 'whisper'],
      ['state'],
    ]) {
      await Directory(_join(root.path, relative)).create(recursive: true);
    }
  }

  Future<String?> _resolveExecutable(
    String configured, {
    required List<String> managedCandidates,
    required String commandName,
  }) async {
    final configuredValue = configured.trim();
    if (configuredValue.isNotEmpty) {
      if (_looksLikePath(configuredValue)) {
        if (await File(configuredValue).exists()) return configuredValue;
      } else {
        final fromPath = await _which(configuredValue);
        if (fromPath != null) return fromPath;
      }
    }

    for (final path in managedCandidates) {
      if (await File(path).exists()) return path;
    }

    return _which(commandName);
  }

  Future<String?> _resolveFile(
    String configured,
    String managedCandidate,
  ) async {
    final value = configured.trim();
    if (value.isNotEmpty && _looksLikePath(value)) {
      final file = File(value);
      if (await file.exists()) return file.path;
    }
    if (await File(managedCandidate).exists()) return managedCandidate;
    return null;
  }

  Future<String?> _which(String command) async {
    try {
      final result = Platform.isWindows
          ? await Process.run('where.exe', [command])
          : await Process.run('/usr/bin/which', [command]);
      if (result.exitCode != 0) return null;
      final line = result.stdout
          .toString()
          .split(RegExp(r'[\r\n]+'))
          .map((value) => value.trim())
          .firstWhere(
            (value) => value.isNotEmpty,
            orElse: () => '',
          );
      return line.isEmpty ? null : line;
    } catch (_) {
      return null;
    }
  }

  Future<File?> _findFile(
    Directory root,
    String fileName,
  ) async {
    if (!await root.exists()) return null;
    await for (final entity in root.list(recursive: true)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.isEmpty
          ? entity.path
          : entity.uri.pathSegments.last;
      if (name.toLowerCase() == fileName.toLowerCase()) {
        return entity;
      }
    }
    return null;
  }

  Future<bool> _modelReferenceExists(String reference) async {
    final value = reference.trim();
    if (value.isEmpty || !_looksLikePath(value)) return false;
    final type = await FileSystemEntity.type(value, followLinks: true);
    return type != FileSystemEntityType.notFound;
  }

  AsrRuntimeComponentStatus _component(
    AsrRuntimeComponent component,
    String label,
    bool ready, {
    required String readyDetail,
    required String missingDetail,
    String? path,
    bool unavailable = false,
  }) {
    return AsrRuntimeComponentStatus(
      component: component,
      state: unavailable && !ready
          ? AsrRuntimeComponentState.unavailable
          : ready
              ? AsrRuntimeComponentState.ready
              : AsrRuntimeComponentState.missing,
      label: label,
      detail: ready ? readyDetail : missingDetail,
      resolvedPath: path,
    );
  }

  Future<bool> _qwenMarkerMatches(
    File marker,
    TranscriptionConfig config,
  ) async {
    if (!await marker.exists()) return false;
    try {
      final decoded = jsonDecode(await marker.readAsString());
      if (decoded is! Map) return false;
      return decoded['qwenModel'] == config.qwenModelPath &&
          decoded['alignerModel'] == config.qwenAlignerModelPath &&
          decoded['device'] == config.qwenDevice &&
          decoded['dtype'] == config.qwenDtype;
    } catch (_) {
      return false;
    }
  }

  File _qwenReadyMarker(
    Directory root,
    TranscriptionProfilePreference profile,
  ) {
    return File(
      _join(root.path, ['state', 'qwen_${profile.name}.ready.json']),
    );
  }

  bool _profileSupportsManagedRuntime(
    TranscriptionProfilePreference profile,
  ) {
    return profile == TranscriptionProfilePreference.rtx5080HighQuality ||
        profile == TranscriptionProfilePreference.intelMacHighQuality;
  }

  Uri _runtimeBundleUri(
    TranscriptionProfilePreference profile,
  ) {
    final asset = switch (profile) {
      TranscriptionProfilePreference.rtx5080HighQuality =>
        'lyricforge-asr-runtime-windows-x64-cuda.zip',
      TranscriptionProfilePreference.intelMacHighQuality =>
        'lyricforge-asr-runtime-macos-x64.zip',
      _ => throw const TranscriptionException(
          '当前 Profile 没有自动安装包',
        ),
    };

    return Uri.parse(
      'https://github.com/BrainEno/lyric-forge-ktv/releases/download/'
      '$_runtimeReleaseTag/$asset',
    );
  }

  String _qwenModelLabel(String modelReference) {
    return modelReference.toLowerCase().contains('0.6b')
        ? 'Qwen3-ASR 0.6B 模型'
        : 'Qwen3-ASR 1.7B 模型';
  }

  bool _looksLikePath(String value) {
    return value.contains('/') ||
        value.contains('\\') ||
        (value.length > 2 && value[1] == ':');
  }

  String get _qwenName => Platform.isWindows ? 'qwen3-asr.exe' : 'qwen3-asr';
  String get _whisperName =>
      Platform.isWindows ? 'whisper-cli.exe' : 'whisper-cli';
  String get _ffmpegName => Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';

  Future<void> _makeExecutable(String path) async {
    final result = await Process.run('/bin/chmod', ['+x', path]);
    if (result.exitCode != 0) {
      throw TranscriptionException(
        '无法设置运行权限',
        details: result.stderr.toString(),
      );
    }
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

  String _psQuote(String value) {
    return "'" + value.replaceAll("'", "''") + "'";
  }

  String _percent(double fraction) {
    return (fraction * 100).clamp(0, 100).toStringAsFixed(0) + '%';
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

  void _throwIfCancelled() {
    if (_cancelRequested) {
      throw const TranscriptionException('识别环境安装已取消');
    }
  }

  @override
  Future<void> cancel() async {
    if (!_installing) return;
    _cancelRequested = true;
    _activeRequest?.abort();
    _activeProcess?.kill();
    _activeProcess = null;
  }

  Future<void> dispose() async {
    _cancelRequested = true;
    _activeRequest?.abort();
    _activeProcess?.kill();
    await _progressController.close();
  }
}
