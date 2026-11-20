import 'dart:convert';

/// `separator-manifest.json` at the root of the vocal separator bundle,
/// written by `.github/workflows/build-vocal-separator.yml`.
class SeparatorManifest {
  static const int supportedSchemaVersion = 1;

  final String separatorRevision;
  final String platform;

  /// Bundle-relative path of the executable, with `/` separators.
  final String executable;

  /// Bundle-relative path of the ONNX model, with `/` separators.
  final String modelFile;
  final int modelBytes;
  final String modelSha256;
  final int vocalsIndex;
  final List<String> providers;

  const SeparatorManifest({
    required this.separatorRevision,
    required this.platform,
    required this.executable,
    required this.modelFile,
    required this.modelBytes,
    required this.modelSha256,
    required this.vocalsIndex,
    required this.providers,
  });

  /// Parses and validates [source]; throws [FormatException] when anything a
  /// later step relies on is missing or unsafe.
  static SeparatorManifest parse(String source) {
    // PowerShell's UTF-8 writer may add a byte-order mark.
    final text = source.startsWith('\uFEFF') ? source.substring(1) : source;
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const FormatException('separator manifest is not valid JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('separator manifest must be an object');
    }
    final schema = decoded['schemaVersion'];
    if (schema != supportedSchemaVersion) {
      throw FormatException('unsupported separator manifest schema: $schema');
    }
    final model = decoded['model'];
    if (model is! Map<String, dynamic>) {
      throw const FormatException('separator manifest has no model entry');
    }

    final bytes = model['bytes'];
    if (bytes is! int || bytes <= 0) {
      throw const FormatException('separator model size is invalid');
    }
    final sha256 = _string(model, 'sha256').toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw const FormatException('separator model SHA-256 is invalid');
    }
    final vocalsIndex = model['vocalsIndex'];
    if (vocalsIndex is! int || vocalsIndex < 0 || vocalsIndex > 15) {
      throw const FormatException('separator vocals index is invalid');
    }
    final providers = decoded['providers'];
    return SeparatorManifest(
      separatorRevision: _string(decoded, 'separatorRevision'),
      platform: _string(decoded, 'platform'),
      executable: _relativePath(_string(decoded, 'executable')),
      modelFile: _relativePath(_string(model, 'file')),
      modelBytes: bytes,
      modelSha256: sha256,
      vocalsIndex: vocalsIndex,
      providers: providers is List
          ? [
              for (final provider in providers)
                if (provider is String) provider,
            ]
          : const [],
    );
  }

  static String _string(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('separator manifest field "$key" is missing');
    }
    return value.trim();
  }

  /// Rejects absolute paths and `..` so a manifest cannot point outside the
  /// bundle it came with.
  static String _relativePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final segments = normalized.split('/');
    final absolute =
        normalized.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(path);
    if (absolute ||
        segments.any((segment) => segment == '..' || segment.isEmpty)) {
      throw FormatException('separator manifest path is not relative: $path');
    }
    return normalized;
  }
}
