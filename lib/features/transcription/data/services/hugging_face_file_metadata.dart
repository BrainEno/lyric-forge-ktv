enum AsrModelDownloadSource { huggingFace, modelScope }

class HuggingFaceFileMetadata {
  final String etag;
  final int sizeBytes;
  final String? sha256;
  final AsrModelDownloadSource source;

  const HuggingFaceFileMetadata({
    required this.etag,
    required this.sizeBytes,
    required this.sha256,
    this.source = AsrModelDownloadSource.huggingFace,
  });

  bool isContentCompatibleWith(HuggingFaceFileMetadata other) {
    if (sizeBytes != other.sizeBytes) return false;
    final currentSha256 = sha256;
    final otherSha256 = other.sha256;
    return currentSha256 == null ||
        otherSha256 == null ||
        currentSha256 == otherSha256;
  }

  factory HuggingFaceFileMetadata.fromModelScopeFile(
    Map<String, Object?> file,
  ) {
    final type = (file['Type'] ?? file['type'])?.toString().toLowerCase();
    if (type != null && type != 'blob') {
      throw const FormatException('ModelScope entry is not a file blob');
    }

    final rawSize = file['Size'] ?? file['size'];
    final sizeBytes = rawSize is int
        ? rawSize
        : int.tryParse(rawSize?.toString() ?? '');
    if (sizeBytes == null || sizeBytes <= 0) {
      throw const FormatException('ModelScope file is missing a positive size');
    }

    final rawSha256 = (file['Sha256'] ?? file['sha256'])?.toString().trim();
    if (rawSha256 == null ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(rawSha256)) {
      throw const FormatException(
        'ModelScope file is missing a trustworthy SHA-256 checksum',
      );
    }
    final sha256 = rawSha256.toLowerCase();

    return HuggingFaceFileMetadata(
      etag: sha256,
      sizeBytes: sizeBytes,
      sha256: sha256,
      source: AsrModelDownloadSource.modelScope,
    );
  }

  static Map<String, HuggingFaceFileMetadata> fromModelScopeManifest(
    Object? decoded,
  ) {
    if (decoded is! Map) {
      throw const FormatException('ModelScope manifest is not a JSON object');
    }
    final response = Map<String, Object?>.from(decoded);
    final success = response['Success'] ?? response['success'];
    final message = response['Message'] ?? response['message'];
    if (success != true) {
      throw FormatException(
        'ModelScope API did not report success: ${message ?? 'unknown error'}',
      );
    }

    final rawData = response['Data'] ?? response['data'];
    if (rawData is! Map) {
      throw const FormatException('ModelScope manifest has no Data object');
    }
    final data = Map<String, Object?>.from(rawData);
    final rawFiles = data['Files'] ?? data['files'];
    if (rawFiles is! List) {
      throw const FormatException('ModelScope manifest has no Files list');
    }

    final files = <String, HuggingFaceFileMetadata>{};
    for (final rawFile in rawFiles) {
      if (rawFile is! Map) continue;
      final file = Map<String, Object?>.from(rawFile);
      final type = (file['Type'] ?? file['type'])?.toString().toLowerCase();
      if (type != 'blob') continue;

      final path = (file['Path'] ?? file['path'])?.toString().trim();
      if (path == null || path.isEmpty) continue;
      files[path] = HuggingFaceFileMetadata.fromModelScopeFile(file);
    }
    if (files.isEmpty) {
      throw const FormatException('ModelScope manifest contains no verifiable files');
    }
    return files;
  }

  factory HuggingFaceFileMetadata.fromHeaders(
    Map<String, String> headers,
  ) {
    String? header(String name) => headers[name.toLowerCase()]?.trim();

    final rawEtag = header('x-linked-etag') ?? header('etag');
    final rawSize = header('x-linked-size') ?? header('content-length');

    if (rawEtag == null || rawEtag.isEmpty) {
      throw const FormatException('Hugging Face response is missing ETag metadata');
    }

    final sizeBytes = int.tryParse(rawSize ?? '');
    if (sizeBytes == null || sizeBytes <= 0) {
      throw const FormatException('Hugging Face response is missing file size metadata');
    }

    final etag = _normalizeEtag(rawEtag);
    if (etag.isEmpty) {
      throw const FormatException('Hugging Face response contains an invalid ETag');
    }

    final sha256 = RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(etag)
        ? etag.toLowerCase()
        : null;

    return HuggingFaceFileMetadata(
      etag: etag,
      sizeBytes: sizeBytes,
      sha256: sha256,
    );
  }

  factory HuggingFaceFileMetadata.fromJson(Map<String, Object?> json) {
    final etag = json['etag'];
    final sizeBytes = json['sizeBytes'];
    final sha256 = json['sha256'];

    if (etag is! String || etag.isEmpty || sizeBytes is! int || sizeBytes <= 0) {
      throw const FormatException('Invalid cached Hugging Face file metadata');
    }
    if (sha256 != null &&
        (sha256 is! String ||
            !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256))) {
      throw const FormatException('Invalid cached Hugging Face SHA-256 metadata');
    }

    return HuggingFaceFileMetadata(
      etag: etag,
      sizeBytes: sizeBytes,
      sha256: (sha256 as String?)?.toLowerCase(),
    );
  }

  Map<String, Object?> toJson() => {
        'etag': etag,
        'sizeBytes': sizeBytes,
        'sha256': sha256,
      };

  static String _normalizeEtag(String value) {
    var normalized = value.trim();
    if (normalized.startsWith('W/')) {
      normalized = normalized.substring(2).trim();
    }
    if (normalized.length >= 2 &&
        normalized.startsWith('"') &&
        normalized.endsWith('"')) {
      normalized = normalized.substring(1, normalized.length - 1);
    }
    return normalized.trim();
  }
}
