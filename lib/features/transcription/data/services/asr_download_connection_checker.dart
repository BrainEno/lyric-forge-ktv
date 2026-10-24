import 'dart:io';

import '../../domain/services/asr_download_connection_checker.dart';
import 'asr_download_http_client_factory.dart';

class HttpAsrDownloadConnectionChecker implements AsrDownloadConnectionChecker {
  final AsrDownloadHttpClientFactory clientFactory;

  const HttpAsrDownloadConnectionChecker({required this.clientFactory});

  static const Map<String, String> _probeUris = {
    'Whisper large-v3': 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin?download=true',
    'Qwen3-ASR': 'https://huggingface.co/Qwen/Qwen3-ASR-1.7B/resolve/main/model-00001-of-00002.safetensors?download=true',
  };

  @override
  Future<void> testConnection({String? proxyOverride}) async {
    for (final probe in _probeUris.entries) {
      final currentSource = probe.key;
      final client = await clientFactory.create(manualProxy: proxyOverride);
      try {
        final request = await client
            .getUrl(Uri.parse(probe.value))
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
            '$currentSource 文件范围下载测试返回 HTTP ${response.statusCode}，期望 206 Partial Content',
          );
        }

        final contentRange = response.headers
            .value(HttpHeaders.contentRangeHeader)
            ?.toLowerCase();
        if (contentRange == null || !contentRange.startsWith('bytes 0-0/')) {
          await response.listen((_) {}).cancel();
          throw HttpException(
            '$currentSource 文件范围下载测试返回无效的 Content-Range：$contentRange',
          );
        }

        final firstChunk = await response.first.timeout(
          const Duration(seconds: 15),
        );
        if (firstChunk.isEmpty) {
          throw HttpException('$currentSource 文件范围下载测试没有收到数据');
        }
      } on FormatException {
        rethrow;
      } catch (error) {
        throw Exception(
          '无法完成 $currentSource 模型文件下载测试：$error。'
          '请确认代理允许 huggingface.co 与 hf.co 的模型存储/CDN 子域名访问。',
        );
      } finally {
        client.close(force: true);
      }
    }
  }
}
