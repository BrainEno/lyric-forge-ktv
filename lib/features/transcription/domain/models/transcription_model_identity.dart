/// Resolves stable, non-secret model identities from the configured model path.
///
/// Runtime paths may be absolute local directories or Hugging Face model IDs.
/// Persist the final path component rather than an absolute path so project
/// metadata remains useful without leaking a user's directory structure.
class TranscriptionModelIdentity {
  TranscriptionModelIdentity._();

  static String qwenAsrEngine(String configuredPath) =>
      _engineKey(
        configuredPath,
        prefix: 'qwen3-asr',
        fallback: 'Qwen3-ASR-1.7B',
        knownPrefix: 'Qwen3-ASR',
      );

  static String qwenAlignerEngine(String configuredPath) =>
      _engineKey(
        configuredPath,
        prefix: 'qwen3-forced-aligner',
        fallback: 'Qwen3-ForcedAligner-0.6B',
        knownPrefix: 'Qwen3-ForcedAligner',
      );

  static String whisperEngine(String configuredPath) {
    var model = _basename(configuredPath, fallback: 'ggml-large-v3.bin');
    model = model
        .replaceFirst(RegExp(r'^ggml[-_]', caseSensitive: false), '')
        .replaceFirst(
          RegExp(r'\.(?:bin|gguf|onnx)$', caseSensitive: false),
          '',
        );
    final slug = _slug(model);
    return 'whisper.cpp-${slug.isEmpty ? 'large-v3' : slug}';
  }

  static String qwenAsrLabel(String configuredPath) {
    final model = _basename(configuredPath, fallback: 'Qwen3-ASR-1.7B');
    return model.replaceFirst(
      RegExp(r'^Qwen3[-_]ASR[-_]', caseSensitive: false),
      'Qwen3-ASR ',
    );
  }

  static String qwenAlignerLabel(String configuredPath) {
    final model = _basename(
      configuredPath,
      fallback: 'Qwen3-ForcedAligner-0.6B',
    );
    return model.replaceFirst(
      RegExp(r'^Qwen3[-_]ForcedAligner[-_]', caseSensitive: false),
      'Qwen3-ForcedAligner ',
    );
  }

  static String whisperLabel(String configuredPath) {
    var model = _basename(configuredPath, fallback: 'ggml-large-v3.bin');
    model = model
        .replaceFirst(RegExp(r'^ggml[-_]', caseSensitive: false), '')
        .replaceFirst(
          RegExp(r'\.(?:bin|gguf|onnx)$', caseSensitive: false),
          '',
        );
    return 'Whisper ${model.isEmpty ? 'large-v3' : model}';
  }

  static String _engineKey(
    String configuredPath, {
    required String prefix,
    required String fallback,
    required String knownPrefix,
  }) {
    final model = _basename(configuredPath, fallback: fallback);
    final lower = model.toLowerCase();
    final version = RegExp(r'(\d+(?:\.\d+)?b)').firstMatch(lower);
    if (version != null) return '$prefix-${version.group(1)}';

    final prefixPattern = RegExp(
      '^' + RegExp.escape(knownPrefix) + r'[-_ ]*',
      caseSensitive: false,
    );
    final slug = _slug(model.replaceFirst(prefixPattern, ''));
    return '$prefix-${slug.isEmpty ? 'custom' : slug}';
  }

  static String _basename(String configuredPath, {required String fallback}) {
    final normalized = configuredPath.trim().replaceAll(r'\\', '/');
    for (final part in normalized.split('/').reversed) {
      if (part.isNotEmpty) return part;
    }
    return fallback;
  }

  static String _slug(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\.(?:bin|gguf|onnx)$'), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}
