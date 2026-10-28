import 'dart:convert';

class RuntimeReleaseAssetMetadata {
  final String name;
  final Uri downloadUri;
  final int sizeBytes;
  final String sha256;

  const RuntimeReleaseAssetMetadata({
    required this.name,
    required this.downloadUri,
    required this.sizeBytes,
    required this.sha256,
  });

  static RuntimeReleaseAssetMetadata fromReleaseJson(
    String source, {
    required String assetName,
  }) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('release metadata must be a JSON object');
    }

    final assets = decoded['assets'];
    if (assets is! List) {
      throw const FormatException('release metadata does not contain assets');
    }

    Map<String, dynamic>? match;
    for (final asset in assets) {
      if (asset is Map<String, dynamic> && asset['name'] == assetName) {
        match = asset;
        break;
      }
    }
    if (match == null) {
      throw FormatException('release asset not found: $assetName');
    }

    final rawUrl = match['browser_download_url'];
    final size = match['size'];
    final digest = match['digest'];
    if (rawUrl is! String || rawUrl.isEmpty) {
      throw FormatException('release asset has no download URL: $assetName');
    }
    final downloadUri = Uri.tryParse(rawUrl);
    if (downloadUri == null || downloadUri.scheme != 'https') {
      throw FormatException('release asset download URL is not HTTPS: $assetName');
    }
    if (size is! int || size <= 0) {
      throw FormatException('release asset has invalid size: $assetName');
    }
    if (digest is! String || !digest.startsWith('sha256:')) {
      throw FormatException('release asset has no SHA-256 digest: $assetName');
    }

    final sha256 = digest.substring('sha256:'.length).toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw FormatException('release asset has invalid SHA-256 digest: $assetName');
    }

    return RuntimeReleaseAssetMetadata(
      name: assetName,
      downloadUri: downloadUri,
      sizeBytes: size,
      sha256: sha256,
    );
  }
}
