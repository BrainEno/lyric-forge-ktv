from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    assert count == 1, f'{label}: expected 1 match, got {count}'
    return text.replace(old, new, 1)


# Managed runtime: publish real transfer metrics.
path = Path('lib/features/transcription/data/services/managed_asr_runtime_manager.dart')
text = path.read_text(encoding='utf-8')
old = '''      final contentLength = response.contentLength;
      final total = contentLength > 0 ? existing + contentLength : -1;
      var received = existing;

      try {'''
new = '''      final contentLength = response.contentLength;
      final total = contentLength > 0 ? existing + contentLength : -1;
      var received = existing;
      final transferStartBytes = existing;
      final transferWatch = Stopwatch()..start();

      try {'''
text = replace_once(text, old, new, 'managed runtime stopwatch')
old = '''          _emit(
            component,
            mapped,
            total > 0 ? '正在下载 ${_percent(fraction)}' : '正在下载…',
          );'''
new = '''          final elapsedSeconds =
              transferWatch.elapsedMicroseconds / Duration.microsecondsPerSecond;
          final transferred = received - transferStartBytes;
          final speed = elapsedSeconds >= 0.5 && transferred > 0
              ? transferred / elapsedSeconds
              : null;
          final remainingSeconds = total > 0 && speed != null && speed > 0
              ? ((total - received) / speed).ceil()
              : null;
          _emit(
            component,
            mapped,
            total > 0 ? '正在下载 ${_percent(fraction)}' : '正在下载…',
            downloadedBytes: received,
            totalBytes: total > 0 ? total : null,
            bytesPerSecond: speed,
            estimatedRemaining: remainingSeconds == null
                ? null
                : Duration(seconds: remainingSeconds),
          );'''
text = replace_once(text, old, new, 'managed runtime metric emit')
old = '''  void _emit(
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
  }'''
new = '''  void _emit(
    AsrRuntimeComponent? component,
    double progress,
    String message, {
    int? downloadedBytes,
    int? totalBytes,
    double? bytesPerSecond,
    Duration? estimatedRemaining,
  }) {
    if (_progressController.isClosed) return;
    _progressController.add(
      AsrRuntimeInstallProgress(
        component: component,
        progress: progress.clamp(0.0, 1.0).toDouble(),
        message: message,
        downloadedBytes: downloadedBytes,
        totalBytes: totalBytes,
        bytesPerSecond: bytesPerSecond,
        estimatedRemaining: estimatedRemaining,
      ),
    );
  }'''
text = replace_once(text, old, new, 'managed runtime emit signature')
path.write_text(text, encoding='utf-8')


# Managed Qwen models: expose per-file metrics and preserve delegate metrics.
path = Path('lib/features/transcription/data/services/managed_model_asr_runtime_manager.dart')
text = path.read_text(encoding='utf-8')
old = '''          onProgress: (fraction) {
            final modelFraction =
                fileStart + (fileEnd - fileStart) * fraction;
            _emit(
              component,
              _mapProgress(modelFraction, startProgress, endProgress),
              '正在下载 ${_modelLabel(modelId)} · ${_percent(modelFraction)}',
            );
          },'''
new = '''          onProgress: (
            fraction,
            downloadedBytes,
            totalBytes,
            bytesPerSecond,
            estimatedRemaining,
          ) {
            final modelFraction =
                fileStart + (fileEnd - fileStart) * fraction;
            _emit(
              component,
              _mapProgress(modelFraction, startProgress, endProgress),
              '正在下载 ${_modelLabel(modelId)} · ${index + 1}/${files.length}',
              downloadedBytes: downloadedBytes,
              totalBytes: totalBytes,
              bytesPerSecond: bytesPerSecond,
              estimatedRemaining: estimatedRemaining,
            );
          },'''
text = replace_once(text, old, new, 'qwen progress callback')
old = '''    required HuggingFaceFileMetadata metadata,
    required void Function(double fraction) onProgress,
  }) async {'''
new = '''    required HuggingFaceFileMetadata metadata,
    required void Function(
      double fraction,
      int downloadedBytes,
      int totalBytes,
      double? bytesPerSecond,
      Duration? estimatedRemaining,
    ) onProgress,
  }) async {'''
text = replace_once(text, old, new, 'qwen callback signature')
text = text.replace(
    '        onProgress(1.0);\n        return;',
    '        onProgress(1.0, metadata.sizeBytes, metadata.sizeBytes, null, Duration.zero);\n        return;',
    1,
)
old = '''      var received = existing;
      final sink = part.openWrite(
        mode: append ? FileMode.append : FileMode.write,
      );'''
new = '''      var received = existing;
      final transferStartBytes = existing;
      final transferWatch = Stopwatch()..start();
      final sink = part.openWrite(
        mode: append ? FileMode.append : FileMode.write,
      );'''
text = replace_once(text, old, new, 'qwen stopwatch')
old = '''          onProgress(
            (received / metadata.sizeBytes).clamp(0.0, 1.0).toDouble(),
          );'''
new = '''          final elapsedSeconds =
              transferWatch.elapsedMicroseconds / Duration.microsecondsPerSecond;
          final transferred = received - transferStartBytes;
          final speed = elapsedSeconds >= 0.5 && transferred > 0
              ? transferred / elapsedSeconds
              : null;
          final remainingSeconds = speed != null && speed > 0
              ? ((metadata.sizeBytes - received) / speed).ceil()
              : null;
          onProgress(
            (received / metadata.sizeBytes).clamp(0.0, 1.0).toDouble(),
            received,
            metadata.sizeBytes,
            speed,
            remainingSeconds == null
                ? null
                : Duration(seconds: remainingSeconds),
          );'''
text = replace_once(text, old, new, 'qwen chunk metrics')
text = text.replace(
    '      onProgress(1.0);\n    } on TranscriptionException {',
    '      onProgress(1.0, metadata.sizeBytes, metadata.sizeBytes, null, Duration.zero);\n    } on TranscriptionException {',
    1,
)
old = '''    _emit(progress.component, mapped, progress.message);'''
new = '''    _emit(
      progress.component,
      mapped,
      progress.message,
      downloadedBytes: progress.downloadedBytes,
      totalBytes: progress.totalBytes,
      bytesPerSecond: progress.bytesPerSecond,
      estimatedRemaining: progress.estimatedRemaining,
    );'''
text = replace_once(text, old, new, 'delegate metric forwarding')
old = '''  void _emit(
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
  }'''
new = '''  void _emit(
    AsrRuntimeComponent? component,
    double progress,
    String message, {
    int? downloadedBytes,
    int? totalBytes,
    double? bytesPerSecond,
    Duration? estimatedRemaining,
  }) {
    if (_progressController.isClosed) return;
    _progressController.add(
      AsrRuntimeInstallProgress(
        component: component,
        progress: progress.clamp(0.0, 1.0).toDouble(),
        message: message,
        downloadedBytes: downloadedBytes,
        totalBytes: totalBytes,
        bytesPerSecond: bytesPerSecond,
        estimatedRemaining: estimatedRemaining,
      ),
    );
  }'''
text = replace_once(text, old, new, 'qwen emit signature')
path.write_text(text, encoding='utf-8')


# Setup dialog: pause/resume/retry and shared rich progress card.
path = Path('lib/features/transcription/presentation/widgets/asr_runtime_setup_dialog.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    "import 'transcription_config_dialog.dart';\n",
    "import 'asr_install_progress_card.dart';\nimport 'transcription_config_dialog.dart';\n",
    'setup progress import',
)
old = '''  bool _loading = true;
  bool _installing = false;
  String? _error;'''
new = '''  bool _loading = true;
  bool _installing = false;
  bool _paused = false;
  bool _pauseRequested = false;
  AsrRuntimeComponent? _failedComponent;
  String? _error;'''
text = replace_once(text, old, new, 'setup state fields')
start = text.index('  Future<void> _install() async {')
end = text.index('  Future<void> _openAdvanced() async {', start)
replacement = '''  Future<void> _install({bool resume = false}) async {
    var completed = false;
    setState(() {
      _installing = true;
      _paused = false;
      _pauseRequested = false;
      _failedComponent = null;
      _error = null;
      if (!resume || _installProgress == null) {
        _installProgress = const AsrRuntimeInstallProgress(
          progress: 0,
          message: '准备自动安装本地识别环境',
        );
      }
    });

    try {
      final installed = await _runtimeManager.installRecommended(_config);
      completed = true;
      if (!mounted) return;
      setState(() => _config = installed);
      await _refresh();
    } on TranscriptionException catch (error) {
      if (!mounted) return;
      if (_pauseRequested) {
        setState(() {
          _paused = true;
          _error = null;
        });
      } else {
        setState(() {
          _failedComponent = _installProgress?.component;
          _error = error.toString();
        });
      }
    } catch (error) {
      if (!mounted) return;
      if (_pauseRequested) {
        setState(() {
          _paused = true;
          _error = null;
        });
      } else {
        setState(() {
          _failedComponent = _installProgress?.component;
          _error = '安装识别环境失败：$error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _installing = false;
          _pauseRequested = false;
          if (completed) _installProgress = null;
        });
      }
    }
  }

  Future<void> _pauseInstall() async {
    if (!_installing) return;
    setState(() => _pauseRequested = true);
    await _runtimeManager.cancel();
  }

  Future<void> _resumeInstall() => _install(resume: true);

'''
text = text[:start] + replacement + text[end:]
old = '''                  if (_installing && _installProgress != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _InstallProgressCard(
                      progress: progress ?? 0,
                      message: _installProgress!.message,
                    ),
                  ],'''
new = '''                  if (_installProgress != null &&
                      (_installing || _paused || _error != null)) ...[
                    const SizedBox(height: AppSpacing.lg),
                    AsrInstallProgressCard(
                      progress: _installProgress!,
                      paused: _paused,
                      failed: _error != null && !_paused,
                      onPause: _installing ? _pauseInstall : null,
                      onResume: _paused ? _resumeInstall : null,
                      onRetry: _error != null && !_paused
                          ? () => _install(resume: true)
                          : null,
                      retryLabel: _failedComponent == null
                          ? '重试未完成组件'
                          : '重试 ${_failedComponentLabel(_failedComponent!)}',
                    ),
                  ],'''
text = replace_once(text, old, new, 'setup progress card')
old = '''          if (_installing)
            TextButton.icon(
              onPressed: _cancelInstall,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('取消安装'),
            )
          else ...['''
new = '''          if (_installing)
            TextButton.icon(
              onPressed: _pauseInstall,
              icon: const Icon(Icons.pause_rounded, size: 18),
              label: const Text('暂停下载'),
            )
          else if (_paused) ...[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('以后继续'),
            ),
            FilledButton.icon(
              onPressed: _resumeInstall,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('继续下载'),
            ),
          ]
          else ...['''
text = replace_once(text, old, new, 'setup actions')
insert = '''
  String _failedComponentLabel(AsrRuntimeComponent component) {
    return switch (component) {
      AsrRuntimeComponent.ffmpeg => 'FFmpeg',
      AsrRuntimeComponent.whisperRuntime => 'Whisper runtime',
      AsrRuntimeComponent.whisperModel => 'Whisper 模型',
      AsrRuntimeComponent.qwenRuntime => 'Qwen runtime',
      AsrRuntimeComponent.qwenModel => 'Qwen 模型',
      AsrRuntimeComponent.qwenAligner => 'ForcedAligner',
    };
  }
'''
anchor = '  String _hardwareSummary(TranscriptionHardwareInfo hardware) {'
text = replace_once(text, anchor, insert + '\n' + anchor, 'setup component label')
# Remove obsolete private progress widget.
start = text.index('class _InstallProgressCard extends StatelessWidget {')
end = text.index('class _ErrorCard extends StatelessWidget {', start)
text = text[:start] + text[end:]
# Remove now-unused local progress variable.
text = text.replace("    final progress = _installProgress?.progress.clamp(0.0, 1.0).toDouble();\n", '', 1)
path.write_text(text, encoding='utf-8')


# Settings: same pause/resume/retry UX and shared card.
path = Path('lib/features/settings/presentation/widgets/ai_transcription_settings_section.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    "import '../../../transcription/presentation/widgets/transcription_config_dialog.dart';\n",
    "import '../../../transcription/presentation/widgets/asr_install_progress_card.dart';\nimport '../../../transcription/presentation/widgets/transcription_config_dialog.dart';\n",
    'settings progress import',
)
old = '''  bool _loading = true;
  bool _installing = false;
  bool _deleting = false;
  String? _error;'''
new = '''  bool _loading = true;
  bool _installing = false;
  bool _paused = false;
  bool _pauseRequested = false;
  bool _deleting = false;
  AsrRuntimeComponent? _failedComponent;
  String? _error;'''
text = replace_once(text, old, new, 'settings state fields')
start = text.index('  Future<void> _install() async {')
end = text.index('  Future<void> _deleteModels(', start)
replacement = '''  Future<void> _install({bool resume = false}) async {
    final current = _config ?? _defaultConfig;
    var completed = false;
    setState(() {
      _installing = true;
      _paused = false;
      _pauseRequested = false;
      _failedComponent = null;
      _error = null;
      if (!resume || _progress == null) {
        _progress = const AsrRuntimeInstallProgress(
          progress: 0,
          message: '准备下载并安装本地歌词识别环境',
        );
      }
    });

    try {
      final installed = await _runtimeManager.installRecommended(current);
      await _settingsStore.save(installed);
      completed = true;
      if (!mounted) return;
      setState(() => _config = installed);
      await _refresh();
    } on TranscriptionException catch (error) {
      if (!mounted) return;
      if (_pauseRequested) {
        setState(() {
          _paused = true;
          _error = null;
        });
      } else {
        setState(() {
          _failedComponent = _progress?.component;
          _error = error.toString();
        });
      }
    } catch (error) {
      if (!mounted) return;
      if (_pauseRequested) {
        setState(() {
          _paused = true;
          _error = null;
        });
      } else {
        setState(() {
          _failedComponent = _progress?.component;
          _error = '安装识别环境失败：$error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _installing = false;
          _pauseRequested = false;
          if (completed) _progress = null;
        });
      }
    }
  }

  Future<void> _pauseInstall() async {
    if (!_installing) return;
    setState(() => _pauseRequested = true);
    await _runtimeManager.cancel();
  }

  Future<void> _resumeInstall() => _install(resume: true);

'''
text = text[:start] + replacement + text[end:]
old = '''        if (_installing && _progress != null) ...[
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _progress!.message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],'''
new = '''        if (_progress != null &&
            (_installing || _paused || _error != null)) ...[
          const SizedBox(height: AppSpacing.md),
          AsrInstallProgressCard(
            progress: _progress!,
            paused: _paused,
            failed: _error != null && !_paused,
            onPause: _installing ? _pauseInstall : null,
            onResume: _paused ? _resumeInstall : null,
            onRetry: _error != null && !_paused
                ? () => _install(resume: true)
                : null,
            retryLabel: _failedComponent == null
                ? '重试未完成组件'
                : '重试 ${_componentLabel(_failedComponent!)}',
          ),
        ],'''
text = replace_once(text, old, new, 'settings progress card')
old = '''            if (_installing)
              OutlinedButton.icon(
                onPressed: _cancelInstall,
                icon: const Icon(Icons.close_rounded),
                label: const Text('取消安装'),
              )
            else
              FilledButton.icon(
                onPressed: _loading ? null : _install,
                icon: const Icon(Icons.download_for_offline_outlined),
                label: Text(ready ? '重新安装 / 修复' : '一键下载安装'),
              ),'''
new = '''            if (_installing)
              OutlinedButton.icon(
                onPressed: _pauseInstall,
                icon: const Icon(Icons.pause_rounded),
                label: const Text('暂停下载'),
              )
            else if (_paused)
              FilledButton.icon(
                onPressed: _resumeInstall,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('继续下载'),
              )
            else
              FilledButton.icon(
                onPressed: _loading ? null : _install,
                icon: Icon(
                  _error != null
                      ? Icons.refresh_rounded
                      : Icons.download_for_offline_outlined,
                ),
                label: Text(
                  _error != null
                      ? (_failedComponent == null
                          ? '重试未完成组件'
                          : '重试 ${_componentLabel(_failedComponent!)}')
                      : ready
                          ? '重新安装 / 修复'
                          : '一键下载安装',
                ),
              ),'''
text = replace_once(text, old, new, 'settings action buttons')
anchor = '  String _modeLabel(TranscriptionMode mode) {'
insert = '''  String _componentLabel(AsrRuntimeComponent component) {
    return switch (component) {
      AsrRuntimeComponent.ffmpeg => 'FFmpeg',
      AsrRuntimeComponent.whisperRuntime => 'Whisper runtime',
      AsrRuntimeComponent.whisperModel => 'Whisper 模型',
      AsrRuntimeComponent.qwenRuntime => 'Qwen runtime',
      AsrRuntimeComponent.qwenModel => 'Qwen 模型',
      AsrRuntimeComponent.qwenAligner => 'ForcedAligner',
    };
  }

'''
text = replace_once(text, anchor, insert + anchor, 'settings component label')
text = text.replace("    final progress = _progress?.progress.clamp(0.0, 1.0).toDouble() ?? 0;\n", '', 1)
path.write_text(text, encoding='utf-8')
