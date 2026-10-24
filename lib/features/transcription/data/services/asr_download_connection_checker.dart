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
    final client = await clientFactory.create(manualProxy: proxyOverride);
    var currentSource = 'Hugging Face';
    try {
      for (final probe in _probeUris.entries) {
        currentSource = probe.key;
        final request = await client
            .headUrl(Uri.parse(probe.value))
            .timeout(const Duration(seconds: 15));
        request.followRedirects = true;
        final response = await request.close().timeout(
          const Duration(seconds: 20),
        );
        await response.drain<void>().timeout(const Duration(seconds: 15));
        if (response.statusCode < 200 || response.statusCode >= 400) {
          throw HttpException(
            '$currentSource 模型源返回 HTTP ${response.statusCode}',
          );
        }
      }
    } on FormatException {
      rethrow;
    } catch (error) {
      throw Exception(
        '无法连接 $currentSource 模型源：$error。请确认代理允许 huggingface.co 与 hf.co 的模型存储/CDN 子域名访问。',
      );
    } finally {
      client.close(force: true);
    }
  }
}
