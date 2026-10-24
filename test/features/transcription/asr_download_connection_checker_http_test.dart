import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_download_connection_checker.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_download_http_client_factory.dart';

void main() {
  group('ASR source preflight HTTP behavior', () {
    late _Fixture fixture;
    late HttpAsrDownloadConnectionChecker checker;

    setUp(() async {
      fixture = await _Fixture.start();
      checker = HttpAsrDownloadConnectionChecker(
        clientFactory: AsrDownloadHttpClientFactory(
          environment: () => const <String, String>{},
          systemProxyLookup: () async => null,
        ),
        endpoints: fixture.endpoints,
      );
    });

    tearDown(() => fixture.close());

    test('checks metadata and Range access for both selected model repositories', () async {
      final report = await checker.testConnection(
        qwenModelId: 'Qwen/Qwen3-ASR-0.6B',
        alignerModelId: 'Qwen/Qwen3-ForcedAligner-0.6B',
      );

      expect(report.whisperAvailable, isTrue);
      expect(report.huggingFaceQwenAvailable, isTrue);
      expect(report.huggingFaceAlignerAvailable, isTrue);
      expect(report.modelScopeQwenAvailable, isTrue);
      expect(report.modelScopeAlignerAvailable, isTrue);
      expect(report.requiredModelsAvailable, isTrue);
      expect(fixture.headRequests, contains('Qwen/Qwen3-ASR-0.6B/model.safetensors'));
      expect(fixture.headRequests, contains('Qwen/Qwen3-ForcedAligner-0.6B/model.safetensors'));
      expect(fixture.manifestRequests, contains('Qwen/Qwen3-ASR-0.6B'));
      expect(fixture.manifestRequests, contains('Qwen/Qwen3-ForcedAligner-0.6B'));
      expect(fixture.rangeRequests, contains('/hf/Qwen/Qwen3-ASR-0.6B/resolve/main/model.safetensors'));
      expect(fixture.rangeRequests, contains('/models/Qwen/Qwen3-ForcedAligner-0.6B/resolve/master/model.safetensors'));
    });

    test('does not call Hugging Face available when HEAD metadata is unavailable', () async {
      fixture.failAlignerHead = true;

      final report = await checker.testConnection();

      expect(report.huggingFaceQwenAvailable, isTrue);
      expect(report.huggingFaceAlignerAvailable, isFalse);
      expect(report.modelScopeAlignerAvailable, isTrue);
      expect(report.requiredModelsAvailable, isTrue);
      expect(
        report.diagnostics,
        contains(
          startsWith(
            'ForcedAligner (Qwen/Qwen3-ForcedAligner-0.6B) (Hugging Face): HEAD 元数据检查失败',
          ),
        ),
      );
      expect(report.summary, contains('ForcedAligner 模型来源：ModelScope'));
    });

    test('fails when no source can prepare the required ForcedAligner', () async {
      fixture.failAlignerHead = true;
      fixture.omitAlignerFromModelScopeManifest = true;

      await expectLater(
        checker.testConnection(),
        throwsA(
          isA<HttpException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('ForcedAligner 模型'),
              contains('ModelScope'),
              contains('HEAD 元数据检查失败'),
            ),
          ),
        ),
      );
    });
  });
}

class _Fixture {
  static final List<int> payload = utf8.encode('one byte response fixture');
  static const String sha256 =
      '2cb79648d94c9a2aa10f9a1164f92c8090e37d753749aa3c8ca125c281598812';

  final HttpServer server;
  final Set<String> headRequests = <String>{};
  final Set<String> manifestRequests = <String>{};
  final Set<String> rangeRequests = <String>{};
  bool failAlignerHead = false;
  bool omitAlignerFromModelScopeManifest = false;

  _Fixture._(this.server) {
    server.listen((request) {
      unawaited(_handle(request));
    });
  }

  static Future<_Fixture> start() async =>
      _Fixture._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  Uri get _baseUri => Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: server.port,
      );

  AsrDownloadConnectionEndpoints get endpoints => AsrDownloadConnectionEndpoints(
        whisperFileUri: () => _baseUri.replace(path: '/whisper/ggml-large-v3.bin'),
        huggingFaceFileUri: (modelId, fileName) => _baseUri.replace(
          path: '/hf/$modelId/resolve/main/$fileName',
          queryParameters: const <String, String>{'download': 'true'},
        ),
        modelScopeManifestUri: (modelId) => _baseUri.replace(
          path: '/api/v1/models/$modelId/repo/files',
          queryParameters: const <String, String>{
            'Revision': 'master',
            'Recursive': 'true',
          },
        ),
        modelScopeFileUri: (modelId, fileName) => _baseUri.replace(
          path: '/models/$modelId/resolve/master/$fileName',
        ),
      );

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.uri.path == '/whisper/ggml-large-v3.bin') {
        await _serveRange(request);
        return;
      }
      if (request.uri.path.startsWith('/hf/')) {
        await _serveHuggingFace(request);
        return;
      }
      if (request.uri.path.startsWith('/api/v1/models/')) {
        await _serveManifest(request);
        return;
      }
      if (request.uri.path.startsWith('/models/')) {
        await _serveRange(request);
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {
        // Test client may already have closed the request.
      }
    }
  }

  Future<void> _serveHuggingFace(HttpRequest request) async {
    final remainder = request.uri.path.substring('/hf/'.length);
    final segments = remainder.split('/');
    final modelId = '${segments[0]}/${segments[1]}';
    final fileName = segments.last;
    final key = '$modelId/$fileName';

    if (request.method == 'HEAD') {
      headRequests.add(key);
      if (failAlignerHead && modelId == 'Qwen/Qwen3-ForcedAligner-0.6B') {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.write('simulated missing metadata');
        await request.response.close();
        return;
      }
      request.response.headers.set('etag', '"$sha256"');
      request.response.headers.set('x-linked-size', payload.length.toString());
      request.response.headers.set(HttpHeaders.contentLengthHeader, payload.length);
      await request.response.close();
      return;
    }

    await _serveRange(request);
  }

  Future<void> _serveManifest(HttpRequest request) async {
    const prefix = '/api/v1/models/';
    const suffix = '/repo/files';
    final modelId = request.uri.path.substring(
      prefix.length,
      request.uri.path.length - suffix.length,
    );
    manifestRequests.add(modelId);
    final files = <Map<String, Object>>[];
    if (!omitAlignerFromModelScopeManifest ||
        modelId != 'Qwen/Qwen3-ForcedAligner-0.6B') {
      files.add(<String, Object>{
        'Type': 'blob',
        'Path': 'model.safetensors',
        'Size': payload.length,
        'Sha256': sha256,
      });
    }
    if (modelId == 'Qwen/Qwen3-ASR-1.7B') {
      files.add(<String, Object>{
        'Type': 'blob',
        'Path': 'model-00001-of-00002.safetensors',
        'Size': payload.length,
        'Sha256': sha256,
      });
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(<String, Object>{
      'Success': true,
      'Data': <String, Object>{'Files': files},
    }));
    await request.response.close();
  }

  Future<void> _serveRange(HttpRequest request) async {
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (request.uri.path.startsWith('/hf/') ||
        request.uri.path.startsWith('/models/')) {
      rangeRequests.add(request.uri.path);
    }
    if (range == null) {
      request.response.statusCode = HttpStatus.ok;
      request.response.contentLength = payload.length;
      request.response.add(payload);
      await request.response.close();
      return;
    }

    request.response.statusCode = HttpStatus.partialContent;
    request.response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes 0-0/${payload.length}',
    );
    request.response.contentLength = 1;
    request.response.add(payload.sublist(0, 1));
    await request.response.close();
  }

  Future<void> close() => server.close(force: true);
}
