import 'dart:convert';
import 'dart:io';

import '../../domain/services/asr_download_connection_checker.dart';
import 'asr_download_http_client_factory.dart';
import 'hugging_face_file_metadata.dart';

/// Endpoint builders are injectable so connectivity preflight can be exercised
/// with a local HTTP server. Production defaults remain the official sources.
class AsrDownloadConnectionEndpoints {
  final Uri Function() whisperFileUri;
  final Uri Function(String modelId, String fileName) huggingFaceFileUri;
  final Uri Function(String modelId) modelScopeManifestUri;
  final Uri Function(String modelId, String fileName) modelScopeFileUri;

  const AsrDownloadConnectionEndpoints({
    required this.whisperFileUri,
    required this.huggingFaceFileUri,
    required this.modelScopeManifestUri,
    required this.modelScopeFileUri,
  });

  static const official = AsrDownloadConnectionEndpoints(
    whisperFileUri: _officialWhisperFileUri,
    huggingFaceFileUri: _officialHuggingFaceFileUri,
    modelScopeManifestUri: _officialModelScopeManifestUri,
    modelScopeFileUri: _officialModelScopeFileUri,
  );
}

Uri _officialWhisperFileUri() => Uri.parse(
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin?download=true',
    );

Uri _officialHuggingFaceFileUri(String modelId, String fileName) => Uri.parse(
      'https://huggingface.co/$modelId/resolve/main/$fileName?download=true',
    );

Uri _officialModelScopeManifestUri(String modelId) => Uri.https(
      'modelscope.cn',
      '/api/v1/models/$modelId/repo/files',
      const {'Revision': 'master', 'Recursive': 'true'},
    );

Uri _officialModelScopeFileUri(String modelId, String fileName) => Uri.https(
      'modelscope.cn',
      '/models/$modelId/resolve/master/$fileName',
    );

class HttpAsrDownloadConnectionChecker implements AsrDownloadConnectionChecker {
  final AsrDownloadHttpClientFactory clientFactory;
  final AsrDownloadConnectionEndpoints endpoints;

  const HttpAsrDownloadConnectionChecker({
    required this.clientFactory,
    this.endpoints = AsrDownloadConnectionEndpoints.official,
  });

  @override
  Future<AsrDownloadConnectionReport> testConnection({
    String? proxyOverride,
    String qwenModelId = 'Qwen/Qwen3-ASR-1.7B',
    String alignerModelId = 'Qwen/Qwen3-ForcedAligner-0.6B',
  }) async {
    final qwenFile = _qwenWeightFile(qwenModelId);
    final alignerFile = _alignerWeightFile(alignerModelId);
    final qwenLabel = 'Qwen3-ASR ($qwenModelId)';
    final alignerLabel = 'ForcedAligner ($alignerModelId)';

    final outcomes = <_ProbeResult>[];
    outcomes.add(await _probeRange(
      name: 'Whisper large-v3',
      uri: endpoints.whisperFileUri(),
      proxyOverride: proxyOverride,
    ));

    final modelProbes = await Future.wait<List<_ProbeResult>>([
      _probeHuggingFaceModel(
        name: '$qwenLabel (Hugging Face)',
        modelId: qwenModelId,
        fileName: qwenFile,
        proxyOverride: proxyOverride,
      ),
      _probeHuggingFaceModel(
        name: '$alignerLabel (Hugging Face)',
        modelId: alignerModelId,
        fileName: alignerFile,
        proxyOverride: proxyOverride,
      ),
      _probeModelScopeModel(
        name: qwenLabel,
        modelId: qwenModelId,
        fileName: qwenFile,
        proxyOverride: proxyOverride,
      ),
      _probeModelScopeModel(
        name: alignerLabel,
        modelId: alignerModelId,
        fileName: alignerFile,
        proxyOverride: proxyOverride,
      ),
    ]);
    for (final probe in modelProbes) {
      outcomes.addAll(probe);
    }

    final reachable = outcomes
        .where((outcome) => outcome.available)
        .map((outcome) => outcome.name)
        .toSet();
    final failures = outcomes
        .where((outcome) => !outcome.available)
        .map((outcome) => '${outcome.name}: ${outcome.error}')
        .toList(growable: false);

    final report = AsrDownloadConnectionReport(
      whisperAvailable: reachable.contains('Whisper large-v3'),
      huggingFaceQwenAvailable: reachable.contains('$qwenLabel (Hugging Face)'),
      huggingFaceAlignerAvailable:
          reachable.contains('$alignerLabel (Hugging Face)'),
      modelScopeManifestAvailable:
          reachable.contains('$qwenLabel (ModelScope 文件清单)'),
      modelScopeFileAvailable: reachable.contains('$qwenLabel (ModelScope)'),
      modelScopeAlignerManifestAvailable:
          reachable.contains('$alignerLabel (ModelScope 文件清单)'),
      modelScopeAlignerFileAvailable:
          reachable.contains('$alignerLabel (ModelScope)'),
      diagnostics: failures,
    );

    if (!report.whisperAvailable ||
        !report.qwenAvailable ||
        !report.alignerAvailable) {
      final missing = <String>[
        if (!report.whisperAvailable) 'Whisper large-v3',
        if (!report.qwenAvailable) 'Qwen ASR 模型（$qwenModelId）',
        if (!report.alignerAvailable) 'ForcedAligner 模型（$alignerModelId）',
      ];
      throw HttpException(
        '下载源连接测试未通过，以下必需组件没有可用来源：${missing.join('、')}。'
        '\\n${failures.join('\\n')}'
        '\\n请确认代理允许 huggingface.co 与 hf.co 的模型存储/CDN 子域名访问，'
        '并允许 modelscope.cn 的文件清单 API 和模型下载端点访问。',
      );
    }

    return report;
  }

  static String _qwenWeightFile(String modelId) {
    return switch (modelId) {
      'Qwen/Qwen3-ASR-1.7B' => 'model-00001-of-00002.safetensors',
      'Qwen/Qwen3-ASR-0.6B' => 'model.safetensors',
      _ => throw ArgumentError.value(
          modelId,
          'qwenModelId',
          '只支持已验证的官方 Qwen3-ASR 模型 ID',
        ),
    };
  }

  static String _alignerWeightFile(String modelId) {
    if (modelId == 'Qwen/Qwen3-ForcedAligner-0.6B') {
      return 'model.safetensors';
    }
    throw ArgumentError.value(
      modelId,
      'alignerModelId',
      '只支持已验证的官方 Qwen ForcedAligner 模型 ID',
    );
  }

  Future<List<_ProbeResult>> _probeHuggingFaceModel({
    required String name,
    required String modelId,
    required String fileName,
    required String? proxyOverride,
  }) async {
    final metadata = await _probeHuggingFaceMetadata(
      name: name,
      modelId: modelId,
      fileName: fileName,
      proxyOverride: proxyOverride,
    );
    if (!metadata.available) {
      return [_ProbeResult.failure(name, 'HEAD 元数据检查失败：${metadata.error}')];
    }

    final range = await _probeRange(
      name: name,
      uri: endpoints.huggingFaceFileUri(modelId, fileName),
      proxyOverride: proxyOverride,
    );
    if (!range.available) {
      return [_ProbeResult.failure(name, '1 字节 Range GET 失败：${range.error}')];
    }
    return [_ProbeResult.success(name)];
  }

  Future<_ProbeResult> _probeHuggingFaceMetadata({
    required String name,
    required String modelId,
    required String fileName,
    required String? proxyOverride,
  }) async {
    HttpClient? activeClient;
    try {
      final client = await clientFactory.create(manualProxy: proxyOverride);
      activeClient = client;
      final request = await client
          .headUrl(endpoints.huggingFaceFileUri(modelId, fileName))
          .timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(
            const Duration(seconds: 20),
          );
      if (response.statusCode < 200 || response.statusCode >= 400) {
        await response.drain<void>().timeout(const Duration(seconds: 20));
        throw HttpException(
          '$name HEAD 元数据端点返回 HTTP ${response.statusCode}',
        );
      }

      final headers = <String, String>{};
      response.headers.forEach((key, values) {
        headers[key.toLowerCase()] = values.join(',');
      });
      await response.drain<void>().timeout(const Duration(seconds: 20));
      HuggingFaceFileMetadata.fromHeaders(headers);
      return _ProbeResult.success(name);
    } catch (error) {
      return _ProbeResult.failure(name, error);
    } finally {
      activeClient?.close(force: true);
    }
  }

  Future<List<_ProbeResult>> _probeModelScopeModel({
    required String name,
    required String modelId,
    required String fileName,
    required String? proxyOverride,
  }) async {
    final manifestName = '$name (ModelScope 文件清单)';
    final manifest = await _probeModelScopeManifest(
      name: manifestName,
      modelId: modelId,
      fileName: fileName,
      proxyOverride: proxyOverride,
    );
    final range = await _probeRange(
      name: '$name (ModelScope)',
      uri: endpoints.modelScopeFileUri(modelId, fileName),
      proxyOverride: proxyOverride,
    );
    return [manifest, range];
  }

  Future<_ProbeResult> _probeModelScopeManifest({
    required String name,
    required String modelId,
    required String fileName,
    required String? proxyOverride,
  }) async {
    HttpClient? activeClient;
    try {
      final client = await clientFactory.create(manualProxy: proxyOverride);
      activeClient = client;
      final request = await client
          .getUrl(endpoints.modelScopeManifestUri(modelId))
          .timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(
            const Duration(seconds: 20),
          );
      if (response.statusCode != HttpStatus.ok) {
        final body = await utf8.decoder.bind(response).join().timeout(
              const Duration(seconds: 20),
            );
        throw HttpException(
          'ModelScope 文件清单 API 返回 HTTP ${response.statusCode}: $body',
        );
      }

      final body = await utf8.decoder.bind(response).join().timeout(
            const Duration(seconds: 20),
          );
      final files = HuggingFaceFileMetadata.fromModelScopeManifest(
        jsonDecode(body),
      );
      final requiredFile = files[fileName];
      if (requiredFile == null ||
          requiredFile.sizeBytes <= 0 ||
          requiredFile.sha256 == null) {
        throw FormatException(
          'ModelScope 清单缺少 $fileName 或可信 SHA-256',
        );
      }
      return _ProbeResult.success(name);
    } catch (error) {
      return _ProbeResult.failure(name, error);
    } finally {
      activeClient?.close(force: true);
    }
  }

  Future<_ProbeResult> _probeRange({
    required String name,
    required Uri uri,
    required String? proxyOverride,
  }) async {
    HttpClient? activeClient;
    try {
      final client = await clientFactory.create(manualProxy: proxyOverride);
      activeClient = client;
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 15));
      request.followRedirects = true;
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(
            const Duration(seconds: 20),
          );
      if (response.statusCode != HttpStatus.partialContent) {
        await response.listen((_) {}).cancel();
        throw HttpException(
          '$name 文件范围下载测试返回 HTTP ${response.statusCode}，期望 206 Partial Content',
        );
      }

      final contentRange = response.headers
          .value(HttpHeaders.contentRangeHeader)
          ?.toLowerCase();
      if (contentRange == null || !contentRange.startsWith('bytes 0-0/')) {
        await response.listen((_) {}).cancel();
        throw HttpException(
          '$name 文件范围下载测试返回无效的 Content-Range：$contentRange',
        );
      }
      final firstChunk = await response.first.timeout(
        const Duration(seconds: 15),
      );
      if (firstChunk.isEmpty) {
        throw HttpException('$name 文件范围下载测试没有收到数据');
      }
      return _ProbeResult.success(name);
    } catch (error) {
      return _ProbeResult.failure(name, error);
    } finally {
      activeClient?.close(force: true);
    }
  }
}

class _ProbeResult {
  final String name;
  final String? error;

  const _ProbeResult._(this.name, this.error);

  factory _ProbeResult.success(String name) => _ProbeResult._(name, null);

  factory _ProbeResult.failure(String name, Object error) =>
      _ProbeResult._(name, error.toString());

  bool get available => error == null;
}
