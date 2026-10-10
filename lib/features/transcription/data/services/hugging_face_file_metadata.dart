class HuggingFaceFileMetadata {
  final String etag;
  final int sizeBytes;
  final String? sha256;

  const HuggingFaceFileMetadata({
    required this.etag,
    required this.sizeBytes,
    required this.sha256,
  });

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
