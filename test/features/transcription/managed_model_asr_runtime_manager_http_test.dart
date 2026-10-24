import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_download_http_client_factory.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/managed_model_asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_profile_resolver.dart';

const _config = TranscriptionConfig(
  mode: TranscriptionMode.highestQuality,
  profilePreference: TranscriptionProfilePreference.intelMacHighQuality,
  whisperExecutable: 'whisper-cli',
  modelPath: 'whisper-model.bin',
);

void main() {
  group('Managed Qwen model download HTTP behavior', () {
    late Directory root;
    late _DownloadFixture fixture;
    late ManagedModelAsrRuntimeManager manager;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('lyricforge-qwen-http-');
      fixture = await _DownloadFixture.start();
      manager = ManagedModelAsrRuntimeManager(
        delegate: _FakeRuntimeManager(),
        profileResolver: _FakeProfileResolver(),
        managedRootResolver: () async => root,
        httpClientFactory: AsrDownloadHttpClientFactory(
          environment: () => const <String, String>{},
          systemProxyLookup: () async => null,
        ),
        downloadEndpoints: fixture.endpoints,
      );
    });

    tearDown(() async {
      await fixture.close();
      await root.delete(recursive: true);
    });

    test('falls back to ModelScope and resumes a matching partial file', () async {
      final modelDirectory = Directory(
        '${root.path}${Platform.pathSeparator}models'
        '${Platform.pathSeparator}qwen'
        '${Platform.pathSeparator}Qwen--Qwen3-ASR-0.6B',
      );
      final partial = File(
        '${modelDirectory.path}${Platform.pathSeparator}tokenizer_config.json.part',
      );
      await partial.parent.create(recursive: true);
      await partial.writeAsBytes(_DownloadFixture.payload.sublist(0, 3));

      final installed = await manager.installRecommended(_config);

      expect(fixture.huggingFaceConfigFailures, 1);
      expect(
        fixture.modelScopeFileRequests,
        contains('Qwen/Qwen3-ASR-0.6B/config.json'),
      );
      expect(fixture.manifestRequests['Qwen/Qwen3-ASR-0.6B'], 1);
      expect(
        fixture.rangeRequests,
        contains('/hf/Qwen/Qwen3-ASR-0.6B/resolve/main/tokenizer_config.json=bytes=3-'),
      );
      expect(await partial.exists(), isFalse);
      expect(
        await File(
          '${modelDirectory.path}${Platform.pathSeparator}tokenizer_config.json',
        ).readAsBytes(),
        _DownloadFixture.payload,
      );
      expect(installed.qwenModelPath, modelDirectory.path);
      final marker = File(
        '${modelDirectory.path}${Platform.pathSeparator}.lyricforge-model.json',
      );
      expect(await marker.exists(), isTrue);
      final decoded = jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
      expect(decoded['schemaVersion'], 2);
      expect(decoded['modelId'], 'Qwen/Qwen3-ASR-0.6B');
      expect((decoded['files'] as List).length, 8);
    });

    test(
      'restarts from ModelScope when Hugging Face size metadata is stale',
      () async {
        fixture.staleChatTemplateHeadMetadata = true;
        final installed = await manager.installRecommended(_config);
        final modelDirectory = Directory(installed.qwenModelPath);
        final chatTemplate = File(
          '${modelDirectory.path}${Platform.pathSeparator}chat_template.json',
        );

        expect(
          fixture.modelScopeFileRequests,
          contains('Qwen/Qwen3-ASR-0.6B/chat_template.json'),
        );
        expect(await chatTemplate.length(), 1161);
        expect(
          await chatTemplate.readAsBytes(),
          _DownloadFixture.staleChatTemplatePayload,
        );
        final marker = File(
          '${modelDirectory.path}${Platform.pathSeparator}.lyricforge-model.json',
        );
        final decoded =
            jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
        final entries = (decoded['files'] as List).cast<Map>();
        final entry = entries.firstWhere(
          (item) => item['name'] == 'chat_template.json',
        );
        expect(entry['sizeBytes'], 1161);
        expect(entry['sha256'], _DownloadFixture.staleChatTemplateSha256);
        expect(
          fixture.rangeRequests,
          isNot(contains(
            '/models/Qwen/Qwen3-ASR-0.6B/resolve/master/chat_template.json=bytes=',
          )),
        );
      },
    );

    test(
      'does not reuse a partial file when source SHA-256 metadata differs',
      () async {
        fixture.mismatchModelScopeChecksum = true;
        final modelDirectory = Directory(
          '${root.path}${Platform.pathSeparator}models'
          '${Platform.pathSeparator}qwen'
          '${Platform.pathSeparator}Qwen--Qwen3-ASR-0.6B',
        );
        final partial = File(
          '${modelDirectory.path}${Platform.pathSeparator}config.json.part',
        );
        await partial.parent.create(recursive: true);
        await partial.writeAsBytes(_DownloadFixture.payload.sublist(0, 3));

        await expectLater(
          manager.installRecommended(_config),
          throwsA(isA<TranscriptionException>()),
        );

        expect(
          fixture.modelScopeFileRequests,
          contains('Qwen/Qwen3-ASR-0.6B/config.json'),
        );
        expect(
          fixture.rangeRequests,
          isNot(contains(
            '/models/Qwen/Qwen3-ASR-0.6B/resolve/master/config.json=bytes=3-',
          )),
        );
        expect(await partial.exists(), isFalse);
      final marker = File(
        '${root.path}${Platform.pathSeparator}models'
        '${Platform.pathSeparator}qwen'
        '${Platform.pathSeparator}Qwen--Qwen3-ASR-0.6B'
        '${Platform.pathSeparator}.lyricforge-model.json',
      );
      expect(await marker.exists(), isFalse);
    });
  });
}

class _DownloadFixture {
  static final List<int> payload = utf8.encode('valid model payload\n');
  static const String sha256 =
      '2cb79648d94c9a2aa10f9a1164f92c8090e37d753749aa3c8ca125c281598812';
  static const String differentSha256 =
      'c2d9eddc8c765da08e84b1835f0a55fdf0f5f3aad8269c8709b076ca67f3785d';
  static final List<int> staleChatTemplatePayload =
      List<int>.filled(1161, 0x61, growable: false);
  static const String staleChatTemplateSha256 =
      'b05f477a1425a7bb180a7323fb60e567970d71e4e5b1d52407d96e8b20f6cb7a';
  static const List<String> modelFiles = <String>[
    'chat_template.json',
    'config.json',
    'generation_config.json',
    'merges.txt',
    'model.safetensors',
    'preprocessor_config.json',
    'tokenizer_config.json',
    'vocab.json',
  ];

  final HttpServer server;
  final Map<String, int> manifestRequests = <String, int>{};
  final List<String> modelScopeFileRequests = <String>[];
  final List<String> rangeRequests = <String>[];
  bool mismatchModelScopeChecksum = false;
  bool staleChatTemplateHeadMetadata = false;
  int huggingFaceConfigFailures = 0;

  _DownloadFixture._(this.server) {
    server.listen((request) {
      unawaited(_handle(request));
    });
  }

  static Future<_DownloadFixture> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _DownloadFixture._(server);
  }

  Uri get _baseUri => Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: server.port,
      );

  AsrModelDownloadEndpoints get endpoints => AsrModelDownloadEndpoints(
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
      if (request.uri.path.startsWith('/api/v1/models/')) {
        await _serveManifest(request);
        return;
      }
      if (request.uri.path.startsWith('/hf/')) {
        await _serveHuggingFace(request);
        return;
      }
      if (request.uri.path.startsWith('/models/')) {
        await _serveModelScopeFile(request);
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {
        // The client may have already closed a failed test request.
      }
    }
  }

  Future<void> _serveManifest(HttpRequest request) async {
    const prefix = '/api/v1/models/';
    const suffix = '/repo/files';
    final modelId = request.uri.path
        .substring(prefix.length, request.uri.path.length - suffix.length);
    manifestRequests.update(modelId, (value) => value + 1, ifAbsent: () => 1);

    final files = modelFiles.map((fileName) {
      final mismatched = mismatchModelScopeChecksum &&
          modelId == 'Qwen/Qwen3-ASR-0.6B' &&
          fileName == 'config.json';
      final staleChatTemplate = staleChatTemplateHeadMetadata &&
          modelId == 'Qwen/Qwen3-ASR-0.6B' &&
          fileName == 'chat_template.json';
      return <String, Object>{
        'Type': 'blob',
        'Path': fileName,
        'Size': staleChatTemplate ? staleChatTemplatePayload.length : payload.length,
        'Sha256': staleChatTemplate
            ? staleChatTemplateSha256
            : mismatched
                ? differentSha256
                : sha256,
      };
    }).toList(growable: false);

    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(<String, Object>{
      'Success': true,
      'Data': <String, Object>{'Files': files},
    }));
    await request.response.close();
  }

  Future<void> _serveHuggingFace(HttpRequest request) async {
    final path = request.uri.path.substring('/hf/'.length);
    final segments = path.split('/');
    final modelId = '${segments[0]}/${segments[1]}';
    final fileName = segments.last;
    if (request.method == 'HEAD') {
      final staleChatTemplate = staleChatTemplateHeadMetadata &&
          modelId == 'Qwen/Qwen3-ASR-0.6B' &&
          fileName == 'chat_template.json';
      request.response.headers.set('etag', '"$sha256"');
      request.response.headers.set(
        HttpHeaders.contentLengthHeader,
        staleChatTemplate ? 206 : payload.length,
      );
      request.response.headers.set('accept-ranges', 'bytes');
      await request.response.close();
      return;
    }
    if (request.method != 'GET') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    if (modelId == 'Qwen/Qwen3-ASR-0.6B' && fileName == 'config.json') {
      huggingFaceConfigFailures++;
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.write('simulated Hugging Face outage');
      await request.response.close();
      return;
    }
    if (staleChatTemplateHeadMetadata &&
        modelId == 'Qwen/Qwen3-ASR-0.6B' &&
        fileName == 'chat_template.json') {
      request.response.headers.contentType = ContentType.text;
      request.response.add(staleChatTemplatePayload);
      await request.response.close();
      return;
    }

    await _writeFileResponse(request);
  }

  Future<void> _serveModelScopeFile(HttpRequest request) async {
    final path = request.uri.path.substring('/models/'.length);
    final segments = path.split('/');
    final modelId = '${segments[0]}/${segments[1]}';
    final fileName = segments.last;
    if (request.method == 'GET') {
      modelScopeFileRequests.add('$modelId/$fileName');
    }
    if (staleChatTemplateHeadMetadata &&
        modelId == 'Qwen/Qwen3-ASR-0.6B' &&
        fileName == 'chat_template.json') {
      await _writeFileResponse(request, bytes: staleChatTemplatePayload);
      return;
    }
    await _writeFileResponse(request);
  }

  Future<void> _writeFileResponse(
    HttpRequest request, {
    List<int>? bytes,
  }) async {
    final responseBytes = bytes ?? payload;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null) {
      rangeRequests.add('${request.uri.path}=$range');
      final match = RegExp(r'^bytes=(\d+)-$').firstMatch(range);
      final offset = int.tryParse(match?.group(1) ?? '');
      if (offset == null || offset >= responseBytes.length) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $offset-${responseBytes.length - 1}/${responseBytes.length}',
      );
      request.response.contentLength = responseBytes.length - offset;
      request.response.add(responseBytes.sublist(offset));
      await request.response.close();
      return;
    }

    request.response.contentLength = responseBytes.length;
    request.response.add(responseBytes);
    await request.response.close();
  }

  Future<void> close() => server.close(force: true);
}

class _FakeProfileResolver implements TranscriptionProfileResolver {
  static const _hardware = TranscriptionHardwareInfo(
    operatingSystem: 'macos',
    architecture: 'x86_64',
  );

  @override
  Future<TranscriptionHardwareInfo> detectHardware() async => _hardware;

  @override
  Future<ResolvedTranscriptionProfile> resolve(
    TranscriptionConfig config,
  ) async =>
      ResolvedTranscriptionProfile(
        profile: config.profilePreference,
        label: 'Local HTTP test profile',
        description: 'No native runtime is launched by this test.',
        hardware: _hardware,
        config: config,
      );
}

class _FakeRuntimeManager implements AsrRuntimeManager {
  @override
  Stream<AsrRuntimeInstallProgress> get progressStream =>
      const Stream<AsrRuntimeInstallProgress>.empty();

  @override
  bool get isInstalling => false;

  @override
  Future<AsrRuntimeStatus> inspect(TranscriptionConfig config) async {
    const hardware = TranscriptionHardwareInfo(
      operatingSystem: 'macos',
      architecture: 'x86_64',
    );
    return AsrRuntimeStatus(
      profile: ResolvedTranscriptionProfile(
        profile: config.profilePreference,
        label: 'Local HTTP test profile',
        description: 'Fake delegate reports runtime prerequisites as ready.',
        hardware: hardware,
        config: config,
      ),
      components: const <AsrRuntimeComponentStatus>[
        AsrRuntimeComponentStatus(
          component: AsrRuntimeComponent.whisperRuntime,
          state: AsrRuntimeComponentState.ready,
          label: 'Whisper runtime',
          detail: 'ready',
        ),
        AsrRuntimeComponentStatus(
          component: AsrRuntimeComponent.qwenRuntime,
          state: AsrRuntimeComponentState.ready,
          label: 'Qwen runtime',
          detail: 'ready',
        ),
      ],
      managedRoot: '',
    );
  }

  @override
  Future<TranscriptionConfig> installRecommended(
    TranscriptionConfig config,
  ) async =>
      config;

  @override
  Future<TranscriptionConfig> repair(TranscriptionConfig config) async =>
      config;

  @override
  Future<void> cancel() async {}
}
