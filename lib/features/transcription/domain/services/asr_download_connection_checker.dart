class AsrDownloadConnectionReport {
  final bool whisperAvailable;
  final bool huggingFaceQwenAvailable;
  final bool huggingFaceAlignerAvailable;
  final bool modelScopeManifestAvailable;
  final bool modelScopeFileAvailable;
  final bool modelScopeAlignerManifestAvailable;
  final bool modelScopeAlignerFileAvailable;
  final List<String> diagnostics;

  const AsrDownloadConnectionReport({
    required this.whisperAvailable,
    required this.huggingFaceQwenAvailable,
    this.huggingFaceAlignerAvailable = false,
    required this.modelScopeManifestAvailable,
    required this.modelScopeFileAvailable,
    this.modelScopeAlignerManifestAvailable = false,
    this.modelScopeAlignerFileAvailable = false,
    this.diagnostics = const [],
  });

  bool get modelScopeQwenAvailable =>
      modelScopeManifestAvailable && modelScopeFileAvailable;

  bool get modelScopeAlignerAvailable =>
      modelScopeAlignerManifestAvailable && modelScopeAlignerFileAvailable;

  bool get modelScopeAvailable =>
      modelScopeQwenAvailable && modelScopeAlignerAvailable;

  bool get qwenAvailable =>
      huggingFaceQwenAvailable || modelScopeQwenAvailable;

  bool get alignerAvailable =>
      huggingFaceAlignerAvailable || modelScopeAlignerAvailable;

  bool get requiredModelsAvailable => qwenAvailable && alignerAvailable;

  String _availableSources({required bool huggingFace, required bool modelScope}) {
    final sources = <String>[
      if (huggingFace) 'Hugging Face',
      if (modelScope) 'ModelScope（清单与文件端点均通过）',
    ];
    return sources.isEmpty ? '无可用来源' : sources.join('、');
  }

  String get summary {
    final lines = <String>[
      '连接检查结果：Whisper large-v3 ${whisperAvailable ? '可用' : '不可用'}。',
      'Qwen ASR 模型来源：${_availableSources(huggingFace: huggingFaceQwenAvailable, modelScope: modelScopeQwenAvailable)}。',
      'ForcedAligner 模型来源：${_availableSources(huggingFace: huggingFaceAlignerAvailable, modelScope: modelScopeAlignerAvailable)}。',
      'ModelScope 只有在对应模型的文件清单 API 与文件范围下载都通过时才计为可用。',
      '本测试验证模型元数据和 1 字节范围下载，不代表完整模型下载或引擎启动成功。',
    ];
    if (diagnostics.isNotEmpty) {
      lines.add('其他来源未通过：${diagnostics.join('；')}');
    }
    return lines.join('\n');
  }
}

abstract interface class AsrDownloadConnectionChecker {
  Future<AsrDownloadConnectionReport> testConnection({
    String? proxyOverride,
    String qwenModelId = 'Qwen/Qwen3-ASR-1.7B',
    String alignerModelId = 'Qwen/Qwen3-ForcedAligner-0.6B',
  });
}
