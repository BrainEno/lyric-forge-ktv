import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/models/transcription_models.dart';
import 'asr_download_http_client_factory.dart';
import 'asr_endpoints.dart';
import 'local_asr_storage_preflight_service.dart';
import 'resumable_file_download.dart';
import 'runtime_release_asset_metadata.dart';
import 'runtime_sha256.dart';
import 'separator_manifest.dart';
import 'zip_bundle_extractor.dart';

/// A verified separator bundle on disk.
class VocalSeparatorInstallation {
  final String root;
  final SeparatorManifest manifest;

  const VocalSeparatorInstallation({
    required this.root,
    required this.manifest,
  });

  String get executablePath => _resolve(manifest.executable);
  String get modelPath => _resolve(manifest.modelFile);

  String _resolve(String relative) =>
      [root, ...relative.split('/')].join(Platform.pathSeparator);
}

class VocalSeparatorInstallException implements Exception {
  final String message;
  final String? details;

  const VocalSeparatorInstallException(this.message, {this.details});

  @override
  String toString() => details == null ? message : '$message ($details)';
}

/// Installs and locates the vocal separator (D-043).
abstract interface class VocalSeparatorRuntime {
  /// The separator revision whose stems this runtime produces.
  String get separatorRevision;

  /// Whether a separator bundle exists for this platform.
  bool get supportsCurrentPlatform;

  /// The installed bundle, or null when missing, stale or damaged.
  Future<VocalSeparatorInstallation?> inspect();

  /// Returns the installed bundle, downloading and verifying it first when
  /// needed. Throws [VocalSeparatorInstallException], or the cancellation
  /// [TranscriptionException] after [cancel].
  Future<VocalSeparatorInstallation> ensureInstalled({
    String proxy = '',
    void Function(double fraction, String message)? onProgress,
  });

  /// Aborts a download in progress.
  void cancel();
}

typedef SeparatorReleaseMetadataFetcher =
    Future<RuntimeReleaseAssetMetadata> Function({
      required String tag,
      required String assetName,
      required String proxy,
      required AsrTransferCancellation cancellation,
    });

typedef SeparatorAssetDownloader =
    Future<void> Function(
      Uri uri,
      File part, {
      required AsrTransferCancellation cancellation,
      required String proxy,
      required int expectedBytes,
      required void Function(DownloadProgress progress) onProgress,
    });

typedef SeparatorArchiveExtractor =
    Future<void> Function(String archive, String destination);

/// Returns the `--version` output of the separator executable.
typedef SeparatorVersionProbe = Future<String> Function(String executable);

/// Downloads the separator bundle from the `vocal-separator-v1` release of
/// [AsrEndpoints.releaseRepository], verifies the archive against the size
/// and SHA-256 digest GitHub publishes for it and the model against the
/// bundle manifest, then swaps it into place atomically.
///
/// Layout under the root (`<app support>/LyricForge/VocalSeparator`):
/// `current/` is the active bundle, `staging/` and `previous/` exist only
/// during an install, `downloads/` keeps a resumable part file.
class ManagedVocalSeparatorRuntime implements VocalSeparatorRuntime {
  static const String releaseTag = 'vocal-separator-v1';
  static const String windowsAssetName =
      'lyricforge-vocal-separator-windows-x64.zip';
  static const String revision = 'htdemucs-ft-vocals-onnx-v1';
  static const String manifestFileName = 'separator-manifest.json';
  static const String _verifiedMarker = '.model-verified';
  static const Duration _timeout = Duration(seconds: 60);

  final Future<Directory> Function()? rootResolver;
  final bool? platformSupportedOverride;
  final AsrDownloadHttpClientFactory _httpClientFactory;
  final SeparatorReleaseMetadataFetcher? _fetchMetadata;
  final SeparatorAssetDownloader? _download;
  final SeparatorArchiveExtractor? _extract;
  final SeparatorVersionProbe? _probeVersion;

  final AsrTransferCancellation _transfer = AsrTransferCancellation();
  Future<VocalSeparatorInstallation>? _install;

  ManagedVocalSeparatorRuntime({
    this.rootResolver,
    this.platformSupportedOverride,
    AsrDownloadHttpClientFactory? httpClientFactory,
    SeparatorReleaseMetadataFetcher? fetchMetadata,
    SeparatorAssetDownloader? download,
    SeparatorArchiveExtractor? extract,
    SeparatorVersionProbe? probeVersion,
  }) : _httpClientFactory = httpClientFactory ?? AsrDownloadHttpClientFactory(),
       _fetchMetadata = fetchMetadata,
       _download = download,
       _extract = extract,
       _probeVersion = probeVersion;

  @override
  String get separatorRevision => revision;

  @override
  bool get supportsCurrentPlatform =>
      platformSupportedOverride ??
      (Platform.isWindows && Platform.version.contains('windows_x64'));

  @override
  Future<VocalSeparatorInstallation?> inspect() async {
    final root = await _root();
    return _verified(Directory(_join(root.path, ['current'])));
  }

  @override
  Future<VocalSeparatorInstallation> ensureInstalled({
    String proxy = '',
    void Function(double fraction, String message)? onProgress,
  }) {
    // Two workflows starting at once share one download.
    return _install ??= _ensureInstalled(
      proxy,
      onProgress ?? (_, _) {},
    ).whenComplete(() => _install = null);
  }

  @override
  void cancel() => _transfer.cancel();

  Future<VocalSeparatorInstallation> _ensureInstalled(
    String proxy,
    void Function(double, String) onProgress,
  ) async {
    _transfer.reset();
    final existing = await inspect();
    if (existing != null) return existing;
    if (!supportsCurrentPlatform) {
      throw const VocalSeparatorInstallException('当前平台暂无人声分离组件');
    }

    final root = await _root();
    onProgress(0, '正在获取人声分离组件信息');
    final metadata = await _metadata(proxy);
    _transfer.throwIfRequested();

    final downloads = Directory(_join(root.path, ['downloads']));
    await downloads.create(recursive: true);
    final archive = File(_join(downloads.path, ['vocal-separator.zip']));
    final part = ResumableFileDownload.partFileFor(archive);
    await _fetch(metadata, part, proxy, onProgress);
    _transfer.throwIfRequested();

    onProgress(0.82, '正在校验人声分离组件');
    final size = await part.length();
    if (size != metadata.sizeBytes ||
        !await verifyFileSha256(part, metadata.sha256)) {
      await _deleteQuietly(part);
      throw VocalSeparatorInstallException(
        '人声分离组件校验失败，已删除损坏的下载文件',
        details: 'expected ${metadata.sizeBytes} bytes, got $size',
      );
    }
    await ResumableFileDownload.promote(part, archive);

    final staging = Directory(_join(root.path, ['staging']));
    await _deleteQuietly(staging);
    await staging.create(recursive: true);
    try {
      onProgress(0.86, '正在安装人声分离组件');
      await (_extract ?? _defaultExtract)(archive.path, staging.path);
      _transfer.throwIfRequested();
      final bundle = await _bundleRoot(staging);

      onProgress(0.92, '正在校验人声分离模型');
      final installation = await _verified(bundle, requireHash: true);
      if (installation == null) {
        throw const VocalSeparatorInstallException('人声分离组件不完整或版本不匹配，已保留原有安装');
      }
      await _checkVersion(installation.executablePath);

      onProgress(0.97, '正在启用人声分离组件');
      final current = Directory(_join(root.path, ['current']));
      await _swapIn(bundle, current, Directory(_join(root.path, ['previous'])));
      await _deleteQuietly(archive);
      final active = await _verified(current);
      if (active == null) {
        throw const VocalSeparatorInstallException('人声分离组件启用后校验失败');
      }
      onProgress(1, '人声分离组件已就绪');
      return active;
    } finally {
      await _deleteQuietly(staging);
    }
  }

  Future<RuntimeReleaseAssetMetadata> _metadata(String proxy) async {
    try {
      return await (_fetchMetadata ?? _defaultFetchMetadata)(
        tag: releaseTag,
        assetName: windowsAssetName,
        proxy: proxy,
        cancellation: _transfer,
      );
    } on VocalSeparatorInstallException {
      rethrow;
    } on TranscriptionException catch (error) {
      if (error.kind == TranscriptionFailureKind.cancelled) rethrow;
      throw VocalSeparatorInstallException(
        '无法读取人声分离组件发布信息',
        details: error.details ?? error.message,
      );
    } on FormatException catch (error) {
      throw VocalSeparatorInstallException(
        '人声分离组件发布信息缺少完整性校验数据',
        details: error.message,
      );
    } catch (error) {
      _transfer.throwIfRequested();
      throw VocalSeparatorInstallException(
        '无法读取人声分离组件发布信息',
        details: error.toString(),
      );
    }
  }

  Future<void> _fetch(
    RuntimeReleaseAssetMetadata metadata,
    File part,
    String proxy,
    void Function(double, String) onProgress,
  ) async {
    void report(DownloadProgress progress) {
      final fraction = progress.fraction ?? 0;
      onProgress(
        0.02 + 0.78 * fraction,
        '正在下载人声分离组件 ${(fraction * 100).toStringAsFixed(0)}%',
      );
    }

    try {
      await (_download ?? _defaultDownload)(
        metadata.downloadUri,
        part,
        cancellation: _transfer,
        proxy: proxy,
        expectedBytes: metadata.sizeBytes,
        onProgress: report,
      );
    } on TranscriptionException {
      rethrow;
    } catch (error) {
      _transfer.throwIfRequested();
      throw VocalSeparatorInstallException(
        '人声分离组件下载失败，下次识别时会继续下载',
        details: error.toString(),
      );
    }
  }

  /// The installation in [directory] when its manifest, revision, files and
  /// model checksum all hold. The checksum of an unchanged model is
  /// remembered in a marker so it is not re-hashed on every song.
  Future<VocalSeparatorInstallation?> _verified(
    Directory directory, {
    bool requireHash = false,
  }) async {
    final manifestFile = File(_join(directory.path, [manifestFileName]));
    if (!await manifestFile.exists()) return null;
    final SeparatorManifest manifest;
    try {
      manifest = SeparatorManifest.parse(await manifestFile.readAsString());
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
    if (manifest.separatorRevision != revision) return null;

    final installation = VocalSeparatorInstallation(
      root: directory.path,
      manifest: manifest,
    );
    final executable = File(installation.executablePath);
    final model = File(installation.modelPath);
    if (!await executable.exists() || !await model.exists()) return null;
    final stat = await model.stat();
    if (stat.size != manifest.modelBytes) return null;

    final marker = File(_join(directory.path, [_verifiedMarker]));
    final expectedMarker =
        '${manifest.modelSha256} ${stat.size} '
        '${stat.modified.toUtc().millisecondsSinceEpoch}';
    if (!requireHash &&
        await marker.exists() &&
        (await marker.readAsString()).trim() == expectedMarker) {
      return installation;
    }
    if (!await verifyFileSha256(model, manifest.modelSha256)) return null;
    try {
      await marker.writeAsString(expectedMarker, flush: true);
    } on FileSystemException {
      // Verification still holds for this call; it is just repeated later.
    }
    return installation;
  }

  /// The directory holding the manifest: the archive root, or its only
  /// subdirectory when the bundle was zipped with a parent folder.
  Future<Directory> _bundleRoot(Directory staging) async {
    if (await File(_join(staging.path, [manifestFileName])).exists()) {
      return staging;
    }
    final children = await staging.list().toList();
    final directories = children.whereType<Directory>().toList();
    if (directories.length == 1 &&
        await File(
          _join(directories.single.path, [manifestFileName]),
        ).exists()) {
      return directories.single;
    }
    throw const VocalSeparatorInstallException('人声分离组件缺少清单文件，已停止安装');
  }

  Future<void> _checkVersion(String executable) async {
    final String output;
    try {
      output = await (_probeVersion ?? _defaultProbeVersion)(executable);
    } catch (error) {
      throw VocalSeparatorInstallException(
        '人声分离程序无法启动，可能缺少系统组件或被安全软件拦截',
        details: error.toString(),
      );
    }
    if (!output.contains(revision)) {
      throw VocalSeparatorInstallException(
        '人声分离程序版本不匹配',
        details: output.trim(),
      );
    }
  }

  Future<void> _swapIn(
    Directory bundle,
    Directory current,
    Directory previous,
  ) async {
    await _deleteQuietly(previous);
    var moved = false;
    try {
      if (await current.exists()) {
        await current.rename(previous.path);
        moved = true;
      }
      await bundle.rename(current.path);
    } catch (error) {
      if (moved && !await current.exists() && await previous.exists()) {
        await previous.rename(current.path);
      }
      throw VocalSeparatorInstallException(
        '无法启用人声分离组件，旧版本已保留（可能有文件正被占用）',
        details: error.toString(),
      );
    }
    // The previous bundle may still be locked by an exiting process.
    await _deleteQuietly(previous);
  }

  Future<Directory> _root() async {
    final injected = rootResolver;
    final root = injected != null
        ? await injected()
        : Directory(
            _join((await getApplicationSupportDirectory()).path, [
              'LyricForge',
              'VocalSeparator',
            ]),
          );
    await root.create(recursive: true);
    return root;
  }

  Future<RuntimeReleaseAssetMetadata> _defaultFetchMetadata({
    required String tag,
    required String assetName,
    required String proxy,
    required AsrTransferCancellation cancellation,
  }) async {
    final client = await _httpClientFactory.create(manualProxy: proxy);
    client.userAgent = 'LyricForge/1.0';
    try {
      final request = await client.getUrl(
        AsrEndpoints.runtimeReleaseMetadata(tag),
      );
      cancellation.track(client, request);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      final response = await request.close().timeout(_timeout);
      cancellation.requestDone();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>().timeout(_timeout);
        throw VocalSeparatorInstallException(
          response.statusCode == HttpStatus.notFound
              ? '人声分离组件尚未发布，暂时改用原曲识别'
              : '无法读取人声分离组件发布信息',
          details: 'GitHub release API HTTP ${response.statusCode}',
        );
      }
      final body = await utf8.decoder.bind(response.timeout(_timeout)).join();
      return RuntimeReleaseAssetMetadata.fromReleaseJson(
        body,
        assetName: assetName,
      );
    } finally {
      cancellation.release(client);
      client.close(force: true);
    }
  }

  Future<void> _defaultDownload(
    Uri uri,
    File part, {
    required AsrTransferCancellation cancellation,
    required String proxy,
    required int expectedBytes,
    required void Function(DownloadProgress progress) onProgress,
  }) {
    return ResumableFileDownload(
      clientFactory: _httpClientFactory,
      timeout: _timeout,
      transientRetries: 3,
    ).fetch(
      uri,
      part,
      cancellation: cancellation,
      proxy: proxy,
      resume: true,
      expectedBytes: expectedBytes,
      onProgress: onProgress,
    );
  }

  static Future<void> _defaultExtract(
    String archive,
    String destination,
  ) async {
    try {
      await ZipBundleExtractor(
        freeSpaceReader: LocalAsrStoragePreflightService.readAvailableBytes,
      ).extract(File(archive), Directory(destination));
    } on ZipExtractionException catch (error) {
      throw VocalSeparatorInstallException(
        '人声分离组件解压失败：${error.message}',
        details: error.details,
      );
    }
  }

  static Future<String> _defaultProbeVersion(String executable) async {
    final result = await Process.run(executable, const [
      '--version',
    ]).timeout(const Duration(seconds: 30));
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        const ['--version'],
        '${result.stderr}'.trim(),
        result.exitCode,
      );
    }
    return '${result.stdout}';
  }

  static Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      if (await entity.exists()) await entity.delete(recursive: true);
    } on FileSystemException {
      // Leftovers are cleaned up by the next install.
    }
  }

  static String _join(String root, List<String> parts) =>
      [root, ...parts].join(Platform.pathSeparator);
}
