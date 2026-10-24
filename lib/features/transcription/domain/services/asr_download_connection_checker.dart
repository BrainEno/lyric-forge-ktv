class AsrDownloadConnectionReport {
  final bool whisperAvailable;
  final bool huggingFaceQwenAvailable;
  final bool modelScopeManifestAvailable;
  final bool modelScopeFileAvailable;
  final List<String> diagnostics;

  const AsrDownloadConnectionReport({
    required this.whisperAvailable,
    required this.huggingFaceQwenAvailable,
    required this.modelScopeManifestAvailable,
    required this.modelScopeFileAvailable,
    this.diagnostics = const [],
  });

  bool get modelScopeAvailable =>
      modelScopeManifestAvailable && modelScopeFileAvailable;

  bool get qwenAvailable => huggingFaceQwenAvailable || modelScopeAvailable;

  String get summary {
    final sources = <String>[
      if (huggingFaceQwenAvailable) 'Hugging Face',
      if (modelScopeAvailable) 'ModelScope（清单与文件端点均通过）',
    ];
    final lines = <String>[
      '连接测试通过：Whisper large-v3 可用；Qwen 可用来源：${sources.join('、')}。',
      'ModelScope 只有在文件清单 API 和模型文件下载端点都可用时才计为可用。',
      '本测试只验证文件清单与 1 字节范围下载，不代表完整模型下载或引擎启动成功。',
    ];
    if (diagnostics.isNotEmpty) {
      lines.add('其他来源未通过：${diagnostics.join('；')}');
    }
    return lines.join('\n');
  }
}

abstract interface class AsrDownloadConnectionChecker {
  Future<AsrDownloadConnectionReport> testConnection({String? proxyOverride});
}
