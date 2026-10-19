import 'dart:io';

import '../../domain/services/asr_download_connection_checker.dart';
import 'asr_download_http_client_factory.dart';

class HttpAsrDownloadConnectionChecker implements AsrDownloadConnectionChecker {
  final AsrDownloadHttpClientFactory clientFactory;

  const HttpAsrDownloadConnectionChecker({required this.clientFactory});

  @override
  Future<void> testConnection({String? proxyOverride}) async {
    final client = await clientFactory.create(manualProxy: proxyOverride);
    try {
      final request = await client
          .headUrl(
            Uri.parse(
              'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/'
              'ggml-large-v3.bin?download=true',
            ),
          )
          .timeout(const Duration(seconds: 15));
      request.followRedirects = true;
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      await response.drain<void>().timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 400) {
        throw HttpException('Hugging Face 模型源返回 HTTP ${response.statusCode}');
      }
    } on FormatException {
      rethrow;
    } catch (error) {
      throw Exception('无法连接 Hugging Face 模型源：$error');
    } finally {
      client.close(force: true);
    }
  }
}
