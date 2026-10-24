import 'dart:convert';
import 'dart:io';

import '../../domain/services/asr_download_connection_checker.dart';
import 'asr_download_http_client_factory.dart';
import 'hugging_face_file_metadata.dart';

class HttpAsrDownloadConnectionChecker
    implements AsrDownloadConnectionChecker {
  final AsrDownloadHttpClientFactory clientFactory;

  const HttpAsrDownloadConnectionChecker({required this.clientFactory});

  static const Map<String, String> _rangeProbeUris = {
    'Whisper large-v3':
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin?download=true',
    'Qwen3-ASR (Hugging Face)':
        'https://huggingface.co/Qwen/Qwen3-ASR-1.7B/resolve/main/model-00001-of-00002.safetensors?download=true',
    'Qwen3-ASR (ModelScope)':
        'https://modelscope.cn/models/Qwen/Qwen3-ASR-1.7B/resolve/master/model-00001-of-00002.safetensors',
  };

  static final Uri _modelScopeManifestUri = Uri.https(
    'modelscope.cn',
    '/api/v1/models/Qwen/Qwen3-ASR-1.7B/repo/files',
    const {'Revision': 'master', 'Recursive': 'true'},
  );

  @override
  Future<AsrDownloadConnectionReport> testConnection({
    String? proxyOverride,
  }) async {
    final outcomes = await Future.wait<_ProbeResult>([
      ..._rangeProbeUris.entries.map(
        (probe) => _probeRange(
          name: probe.key,
          uri: Uri.parse(probe.value),
          proxyOverride: proxyOverride,
        ),
      ),
      _probeModelScopeManifest(proxyOverride: proxyOverride),
    ]);

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
      huggingFaceQwenAvailable:
          reachable.contains('Qwen3-ASR (Hugging Face)'),
      modelScopeManifestAvailable:
          reachable.contains('Qwen3-ASR (ModelScope 文件清单)'),
      modelScopeFileAvailable: reachable.contains('Qwen3-ASR (ModelScope)'),
      diagnostics: failures,
    );

    if (!report.whisperAvailable || !report.qwenAvailable) {
      throw Exception(
        '下载源连接测试未通过：双引擎至少需要 Whisper 和一个 Qwen 源可用。'
        '${failures.join('\n')}\n'
        '请确认代理允许 huggingface.co 与 hf.co 的模型存储/CDN 子域名访问，'
        '并允许 modelscope.cn 的文件清单 API 和模型下载端点访问。',
      );
    }
    return report;
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
          '$name 文件范围下载测试返回 HTTP '
          '${response.statusCode}，期望 206 Partial Content',
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

  Future<_ProbeResult> _probeModelScopeManifest({
    required String? proxyOverride,
  }) async {
    const name = 'Qwen3-ASR (ModelScope 文件清单)';
    HttpClient? activeClient;
    try {
      final client = await clientFactory.create(manualProxy: proxyOverride);
      activeClient = client;
      final request = await client
          .getUrl(_modelScopeManifestUri)
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
      final requiredModelFile =
          files['model-00001-of-00002.safetensors'];
      if (requiredModelFile == null || requiredModelFile.sha256 == null) {
        throw const FormatException(
          'ModelScope 清单缺少 Qwen3-ASR 模型分片或 SHA-256',
        );
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
