import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/spacing_tokens.dart';
import '../../domain/models/transcription_models.dart';
import '../../domain/services/asr_download_connection_checker.dart';
import '../../domain/services/transcription_profile_resolver.dart';
import '../../domain/services/transcription_settings_store.dart';

class TranscriptionConfigDialog extends StatefulWidget {
  final TranscriptionConfig? initialConfig;

  const TranscriptionConfigDialog({super.key, this.initialConfig});

  @override
  State<TranscriptionConfigDialog> createState() =>
      _TranscriptionConfigDialogState();
}

class _TranscriptionConfigDialogState extends State<TranscriptionConfigDialog> {
  late final TranscriptionProfileResolver _profileResolver;

  late final TextEditingController _qwenExecutableController;
  late final TextEditingController _qwenModelController;
  late final TextEditingController _qwenAlignerController;
  late final TextEditingController _whisperController;
  late final TextEditingController _whisperModelController;
  late final TextEditingController _ffmpegController;
  late final TextEditingController _downloadProxyController;
  late final AsrDownloadConnectionChecker _downloadConnectionChecker;
  late final TranscriptionDownloadProxyStore _downloadProxyStore;

  late TranscriptionMode _mode;
  late TranscriptionProfilePreference _profilePreference;
  late String _language;
  late String _qwenDevice;
  late String _qwenDtype;
  late int _fallbackThreshold;
  late int _maxFallbackSegments;
  bool _testingDownloadConnection = false;
  String? _downloadConnectionMessage;
  bool _downloadConnectionSucceeded = false;
  bool _saving = false;
  String? _validationMessage;
  bool _loadingSavedProxy = false;
  bool _downloadProxyEdited = false;

  ResolvedTranscriptionProfile? _resolvedProfile;
  bool _resolvingProfile = false;

  @override
  void initState() {
    super.initState();
    final services = ServiceLocatorGlobal.I;
    _profileResolver = services.transcriptionProfileResolver;
    _downloadConnectionChecker = services.asrDownloadConnectionChecker;
    _downloadProxyStore = services.transcriptionDownloadProxyStore;

    final config = widget.initialConfig;
    _mode = config?.mode ?? TranscriptionMode.highestQuality;
    _profilePreference =
        config?.profilePreference ?? TranscriptionProfilePreference.automatic;

    _qwenExecutableController = TextEditingController(
      text: config?.qwenExecutable ?? 'qwen3-asr',
    );
    _qwenModelController = TextEditingController(
      text: config?.qwenModelPath ?? 'Qwen/Qwen3-ASR-1.7B',
    );
    _qwenAlignerController = TextEditingController(
      text: config?.qwenAlignerModelPath ?? 'Qwen/Qwen3-ForcedAligner-0.6B',
    );
    _whisperController = TextEditingController(
      text: config?.whisperExecutable ?? 'whisper-cli',
    );
    _whisperModelController = TextEditingController(
      text: config?.modelPath ?? '',
    );
    _ffmpegController = TextEditingController(
      text: config?.ffmpegExecutable ?? 'ffmpeg',
    );
    _downloadProxyController = TextEditingController(
      text: config?.downloadProxy ?? '',
    );
    if (_downloadProxyController.text.isEmpty) {
      _loadingSavedProxy = true;
      unawaited(_loadSavedDownloadProxy());
    }

    _language = config?.language ?? 'auto';
    _qwenDevice = config?.qwenDevice ?? 'cuda';
    _qwenDtype = config?.qwenDtype ?? 'bf16';
    _fallbackThreshold = config?.fallbackConfidenceThreshold ?? 70;
    _maxFallbackSegments = config?.maxFallbackSegments ?? 20;

    for (final controller in [
      _qwenExecutableController,
      _qwenModelController,
      _qwenAlignerController,
      _whisperController,
      _whisperModelController,
      _ffmpegController,
      _downloadProxyController,
    ]) {
      controller.addListener(_onDraftChanged);
    }

    unawaited(_resolveProfile(applyRecommendation: true));
  }

  void _onDraftChanged() {
    if (!mounted) return;
    setState(() => _validationMessage = null);
  }

  @override
  void dispose() {
    for (final controller in [
      _qwenExecutableController,
      _qwenModelController,
      _qwenAlignerController,
      _whisperController,
      _whisperModelController,
      _ffmpegController,
      _downloadProxyController,
    ]) {
      controller
        ..removeListener(_onDraftChanged)
        ..dispose();
    }
    super.dispose();
  }

  TranscriptionConfig _draftConfig() {
    return TranscriptionConfig(
      mode: _mode,
      profilePreference: _profilePreference,
      qwenExecutable: _qwenExecutableController.text.trim(),
      qwenModelPath: _qwenModelController.text.trim(),
      qwenAlignerModelPath: _qwenAlignerController.text.trim(),
      qwenDevice: _qwenDevice,
      qwenDtype: _qwenDtype,
      whisperExecutable: _whisperController.text.trim(),
      modelPath: _whisperModelController.text.trim(),
      ffmpegExecutable: _ffmpegController.text.trim(),
      language: _language,
      downloadProxy: _downloadProxyController.text.trim(),
      fallbackConfidenceThreshold: _fallbackThreshold,
      maxFallbackSegments: _maxFallbackSegments,
    );
  }

  Future<void> _loadSavedDownloadProxy() async {
    try {
      final savedProxy = await _downloadProxyStore.loadDownloadProxy();
      if (!mounted) return;
      if (savedProxy != null &&
          !_downloadProxyEdited &&
          _downloadProxyController.text.isEmpty) {
        _downloadProxyController.text = savedProxy;
      }
    } catch (error) {
      if (mounted) {
        setState(() => _validationMessage = '读取已保存代理失败：$error');
      }
    } finally {
      if (mounted) setState(() => _loadingSavedProxy = false);
    }
  }

  Future<void> _resolveProfile({required bool applyRecommendation}) async {
    if (_resolvingProfile) return;

    setState(() => _resolvingProfile = true);
    try {
      final resolved = await _profileResolver.resolve(_draftConfig());
      if (!mounted) return;

      setState(() {
        _resolvedProfile = resolved;
        if (applyRecommendation &&
            resolved.profile != TranscriptionProfilePreference.custom) {
          final config = resolved.config;
          _qwenModelController.text = config.qwenModelPath;
          _qwenAlignerController.text = config.qwenAlignerModelPath;
          _qwenDevice = config.qwenDevice;
          _qwenDtype = config.qwenDtype;
        }
      });
    } finally {
      if (mounted) setState(() => _resolvingProfile = false);
    }
  }

  Future<void> _pickFileInto(TextEditingController controller) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path != null && path.isNotEmpty) {
      controller.text = path;
    }
  }

  Future<void> _pickDirectoryInto(TextEditingController controller) async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null && path.isNotEmpty) {
      controller.text = path;
    }
  }

  Future<void> _selectProfile(TranscriptionProfilePreference preference) async {
    setState(() => _profilePreference = preference);
    await _resolveProfile(applyRecommendation: true);
  }

  Future<void> _testDownloadConnection() async {
    setState(() {
      _testingDownloadConnection = true;
      _downloadConnectionMessage = null;
    });
    try {
      await _downloadConnectionChecker.testConnection(
        proxyOverride: _downloadProxyController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _downloadConnectionSucceeded = true;
        _downloadConnectionMessage = 'Whisper 与至少一个 Qwen（Hugging Face / 官方 ModelScope）来源完成 1 字节范围下载测试。完整模型下载及引擎启动仍需单独验证。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _downloadConnectionSucceeded = false;
        _downloadConnectionMessage = '连接测试失败：$error';
      });
    } finally {
      if (mounted) setState(() => _testingDownloadConnection = false);
    }
  }

  Future<void> _submit() async {
    final config = _draftConfig();

    setState(() => _saving = true);

    try {
      await _downloadProxyStore.saveDownloadProxy(config.downloadProxy);
      if (!mounted) return;
      Navigator.pop(context, config);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _validationMessage = '保存下载代理失败：$error';
      });
    }
  }

  String _missingConfigurationSummary() {
    final missing = <String>[];
    if (_mode == TranscriptionMode.whisperOnly) {
      if (_whisperController.text.trim().isEmpty) {
        missing.add('Whisper runtime');
      }
      if (_whisperModelController.text.trim().isEmpty) {
        missing.add('Whisper 模型');
      }
    } else {
      if (_qwenExecutableController.text.trim().isEmpty) {
        missing.add('Qwen runtime');
      }
      if (_qwenModelController.text.trim().isEmpty) {
        missing.add('Qwen 模型');
      }
      if (_qwenAlignerController.text.trim().isEmpty) {
        missing.add('ForcedAligner');
      }
      if (_whisperController.text.trim().isEmpty) {
        missing.add('Whisper runtime');
      }
      if (_whisperModelController.text.trim().isEmpty) {
        missing.add('Whisper 模型');
      }
    }
    if (_ffmpegController.text.trim().isEmpty) missing.add('FFmpeg');
    return missing.isEmpty ? '' : missing.join('、');
  }

  String _profileName(TranscriptionProfilePreference profile) {
    return switch (profile) {
      TranscriptionProfilePreference.automatic => '自动 · 根据本机硬件',
      TranscriptionProfilePreference.rtx5080HighQuality => 'RTX 5080 · 最高质量',
      TranscriptionProfilePreference.intelMacHighQuality => 'Intel Mac · 高质量',
      TranscriptionProfilePreference.custom => '自定义',
    };
  }

  String _hardwareSummary(TranscriptionHardwareInfo hardware) {
    final parts = <String>[
      '${hardware.operatingSystem} / ${hardware.architecture}',
      if (hardware.cpuName != null && hardware.cpuName!.isNotEmpty)
        hardware.cpuName!,
      if (hardware.gpuName != null && hardware.gpuName!.isNotEmpty)
        hardware.gpuName!,
      if (hardware.gpuMemoryMb != null)
        '${(hardware.gpuMemoryMb! / 1024).toStringAsFixed(0)} GB VRAM',
      if (hardware.systemMemoryMb != null)
        '${(hardware.systemMemoryMb! / 1024).toStringAsFixed(0)} GB RAM',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final highQuality = _mode == TranscriptionMode.highestQuality;
    final resolved = _resolvedProfile;
    final whisperPrimary =
        resolved?.config.engineOrder == TranscriptionEngineOrder.whisperPrimary;

    return AlertDialog(
      title: const Text('本地歌词识别设置'),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<TranscriptionMode>(
                initialValue: _mode,
                decoration: const InputDecoration(labelText: '识别模式'),
                items: const [
                  DropdownMenuItem(
                    value: TranscriptionMode.highestQuality,
                    child: Text('最高质量 · 双引擎 + 时间轴校对'),
                  ),
                  DropdownMenuItem(
                    value: TranscriptionMode.whisperOnly,
                    child: Text('仅 Whisper · 兼容模式'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _mode = value);
                },
              ),
              if (highQuality) ...[
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<TranscriptionProfilePreference>(
                  initialValue: _profilePreference,
                  decoration: const InputDecoration(labelText: '硬件 Profile'),
                  items: TranscriptionProfilePreference.values
                      .map(
                        (profile) => DropdownMenuItem(
                          value: profile,
                          child: Text(_profileName(profile)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _resolvingProfile
                      ? null
                      : (value) {
                          if (value != null) {
                            unawaited(_selectProfile(value));
                          }
                        },
                ),
                const SizedBox(height: AppSpacing.md),
                _InfoCard(
                  title:
                      resolved?.label ??
                      (_resolvingProfile ? '正在检测本机硬件…' : '硬件检测'),
                  body: resolved == null
                      ? '正在根据操作系统、CPU 架构和 GPU 选择本机识别链路。'
                      : '${resolved.description}\n${_hardwareSummary(resolved.hardware)}',
                ),
                const SizedBox(height: AppSpacing.md),
                _PathField(
                  controller: _qwenExecutableController,
                  label: 'Qwen3-ASR native runtime',
                  hint: 'qwen3-asr / qwen3-asr.exe',
                  onBrowse: () => _pickFileInto(_qwenExecutableController),
                ),
                const SizedBox(height: AppSpacing.md),
                _PathField(
                  controller: _qwenModelController,
                  label: whisperPrimary
                      ? 'Qwen3-ASR 0.6B 第二意见模型'
                      : 'Qwen3-ASR 1.7B 主模型',
                  hint: whisperPrimary
                      ? 'Qwen/Qwen3-ASR-0.6B'
                      : 'Qwen/Qwen3-ASR-1.7B',
                  onBrowse: () => _pickDirectoryInto(_qwenModelController),
                ),
                const SizedBox(height: AppSpacing.md),
                _PathField(
                  controller: _qwenAlignerController,
                  label: 'Qwen3 ForcedAligner 0.6B',
                  hint: 'Qwen/Qwen3-ForcedAligner-0.6B',
                  onBrowse: () => _pickDirectoryInto(_qwenAlignerController),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Qwen backend：${_qwenDevice.toUpperCase()} / ${_qwenDtype.toUpperCase()}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              _PathField(
                controller: _whisperController,
                label: highQuality
                    ? whisperPrimary
                          ? 'Whisper 主识别 runtime'
                          : 'Whisper 第二意见 runtime'
                    : 'whisper-cli',
                hint: 'whisper-cli / whisper-cli.exe',
                onBrowse: () => _pickFileInto(_whisperController),
              ),
              const SizedBox(height: AppSpacing.md),
              _PathField(
                controller: _whisperModelController,
                label: highQuality
                    ? whisperPrimary
                          ? 'Whisper large-v3 主模型'
                          : 'Whisper large-v3 第二意见模型'
                    : 'Whisper 模型',
                hint: highQuality
                    ? '建议 ggml-large-v3.bin'
                    : '例如 ggml-medium.bin',
                onBrowse: () => _pickFileInto(_whisperModelController),
              ),
              const SizedBox(height: AppSpacing.md),
              _PathField(
                controller: _ffmpegController,
                label: 'FFmpeg',
                hint: 'ffmpeg / ffmpeg.exe',
                onBrowse: () => _pickFileInto(_ffmpegController),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _downloadProxyController,
                autocorrect: false,
                keyboardType: TextInputType.url,
                onChanged: (_) {
                  _downloadProxyEdited = true;
                  if (_downloadConnectionMessage != null) {
                    setState(() => _downloadConnectionMessage = null);
                  }
                },
                decoration: const InputDecoration(
                  labelText: '模型下载代理（可选）',
                  hintText: 'http://127.0.0.1:7890',
                  helperText:
                      '留空读取代理环境变量；Windows/macOS 还会读取静态系统代理。PAC/WPAD 请手动填写 HTTP 代理。大模型下载还需要代理放行 huggingface.co、hf.co 存储/CDN 子域名及 modelscope.cn；支持 HTTP，不支持 SOCKS 和代理账号密码。',
                  helperMaxLines: 3,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _testingDownloadConnection
                      ? null
                      : _testDownloadConnection,
                  icon: _testingDownloadConnection
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check_rounded, size: 18),
                  label: Text(
                    _testingDownloadConnection ? '正在测试模型源连接…' : '测试下载连接',
                  ),
                ),
              ),
              if (_downloadConnectionMessage != null)
                Text(
                  _downloadConnectionMessage!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _downloadConnectionSucceeded
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _language,
                decoration: const InputDecoration(labelText: '识别语言'),
                items: const [
                  DropdownMenuItem(value: 'auto', child: Text('自动检测')),
                  DropdownMenuItem(value: 'zh', child: Text('中文')),
                  DropdownMenuItem(value: 'en', child: Text('英文')),
                  DropdownMenuItem(value: 'ja', child: Text('日文')),
                  DropdownMenuItem(value: 'ko', child: Text('韩文')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _language = value);
                },
              ),
              if (highQuality) ...[
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<int>(
                  initialValue: _fallbackThreshold,
                  decoration: const InputDecoration(
                    labelText: '重点校对触发阈值',
                    helperText: '分数越高，越多低置信度主引擎结果会进入重点校对',
                  ),
                  items: const [
                    DropdownMenuItem(value: 60, child: Text('60 · 保守')),
                    DropdownMenuItem(value: 70, child: Text('70 · 推荐')),
                    DropdownMenuItem(value: 80, child: Text('80 · 严格')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _fallbackThreshold = value);
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<int>(
                  initialValue: _maxFallbackSegments,
                  decoration: const InputDecoration(
                    labelText: '最多突出显示分歧行',
                    helperText: '两套引擎仍会跑完整歌曲；这里只限制编辑器重点列出的数量',
                  ),
                  items: const [
                    DropdownMenuItem(value: 8, child: Text('8')),
                    DropdownMenuItem(value: 12, child: Text('12')),
                    DropdownMenuItem(value: 20, child: Text('20 · 推荐')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _maxFallbackSegments = value);
                    }
                  },
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (!_draftConfig().isConfigured)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.errorContainer.withAlpha(70),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                  ),
                  child: Text(
                    '识别配置尚不完整（缺少：${_missingConfigurationSummary()}）。'
                    '下载代理可以单独保存；完整识别配置稍后再补齐即可。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (_validationMessage != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _validationMessage!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Text(
                'Profile 只决定本机 runtime/model/device。工程本身只保存识别模式和结果，不绑定某台电脑的绝对路径。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving || _loadingSavedProxy ? null : _submit,
          child: Text(
            _saving
                ? '正在保存…'
                : _loadingSavedProxy
                ? '正在读取代理…'
                : (_draftConfig().isConfigured ? '保存并退出' : '保存代理并退出'),
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String body;

  const _InfoCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(body, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _PathField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final VoidCallback onBrowse;

  const _PathField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.onBrowse,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: IconButton(
          tooltip: '选择路径',
          onPressed: onBrowse,
          icon: const Icon(Icons.folder_open_outlined),
        ),
      ),
    );
  }
}
