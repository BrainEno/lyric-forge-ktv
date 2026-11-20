import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/resumable_file_download.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/runtime_release_asset_metadata.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/vocal_separator_runtime.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';

final _archiveBytes = utf8.encode('pretend this is a zip archive');
final _modelBytes = List<int>.generate(4096, (i) => (i * 31) % 251);

String _hex(List<int> bytes) => sha256.convert(bytes).toString();

/// A fake release: metadata, a download that writes [_archiveBytes], and an
/// extractor that lays out a bundle the way the workflow zips it.
class _Release {
  _Release(this.root);

  final Directory root;
  int metadataCalls = 0;
  int downloads = 0;
  int extracts = 0;
  String? archiveSha;
  int? archiveSize;
  String revision = ManagedVocalSeparatorRuntime.revision;
  String versionOutput =
      'lyricforge-separator 1.0.0 ${ManagedVocalSeparatorRuntime.revision}';
  List<int> shippedModel = _modelBytes;
  String manifestModelSha = _hex(_modelBytes);
  bool nestedFolder = false;
  Object? metadataError;
  Future<void> Function()? onDownload;

  ManagedVocalSeparatorRuntime runtime({bool supported = true}) =>
      ManagedVocalSeparatorRuntime(
        rootResolver: () async => root,
        platformSupportedOverride: supported,
        fetchMetadata: _metadata,
        download: _download,
        extract: _extract,
        probeVersion: (executable) async => versionOutput,
      );

  Future<RuntimeReleaseAssetMetadata> _metadata({
    required String tag,
    required String assetName,
    required String proxy,
    required AsrTransferCancellation cancellation,
  }) async {
    metadataCalls++;
    expect(tag, 'vocal-separator-v1');
    expect(assetName, 'lyricforge-vocal-separator-windows-x64.zip');
    final error = metadataError;
    if (error != null) throw error;
    return RuntimeReleaseAssetMetadata(
      name: assetName,
      downloadUri: Uri.parse('https://example.invalid/sep.zip'),
      sizeBytes: archiveSize ?? _archiveBytes.length,
      sha256: archiveSha ?? _hex(_archiveBytes),
    );
  }

  Future<void> _download(
    Uri uri,
    File part, {
    required AsrTransferCancellation cancellation,
    required String proxy,
    required int expectedBytes,
    required void Function(DownloadProgress progress) onProgress,
  }) async {
    downloads++;
    await onDownload?.call();
    cancellation.throwIfRequested();
    await part.parent.create(recursive: true);
    await part.writeAsBytes(_archiveBytes);
    onProgress(
      DownloadProgress(
        receivedBytes: _archiveBytes.length,
        totalBytes: expectedBytes,
      ),
    );
  }

  Future<void> _extract(String archive, String destination) async {
    extracts++;
    expect(await File(archive).readAsBytes(), _archiveBytes);
    final base = nestedFolder ? '$destination/separator' : destination;
    await Directory('$base/bin').create(recursive: true);
    await Directory('$base/models').create(recursive: true);
    await File('$base/bin/lyricforge-separator.exe').writeAsString('exe');
    await File(
      '$base/models/htdemucs_ft_vocals.onnx',
    ).writeAsBytes(shippedModel);
    await File('$base/separator-manifest.json').writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'separatorRevision': revision,
        'platform': 'windows-x64',
        'executable': 'bin/lyricforge-separator.exe',
        'providers': ['dml', 'cpu'],
        'model': {
          'file': 'models/htdemucs_ft_vocals.onnx',
          'bytes': _modelBytes.length,
          'sha256': manifestModelSha,
          'sources': ['drums', 'bass', 'other', 'vocals'],
          'vocalsIndex': 3,
          'sampleRate': 44100,
        },
      }),
    );
  }
}

Future<_Release> _release() async {
  final root = await Directory.systemTemp.createTemp('vocal-separator-');
  addTearDown(() => root.delete(recursive: true));
  return _Release(root);
}

void main() {
  test('installs, verifies and then finds the bundle', () async {
    final release = await _release();
    final runtime = release.runtime();
    expect(await runtime.inspect(), isNull);

    final messages = <String>[];
    final fractions = <double>[];
    final installation = await runtime.ensureInstalled(
      onProgress: (fraction, message) {
        fractions.add(fraction);
        messages.add(message);
      },
    );
    expect(installation.manifest.vocalsIndex, 3);
    expect(installation.root, endsWith('current'));
    expect(File(installation.executablePath).existsSync(), isTrue);
    expect(File(installation.modelPath).readAsBytesSync(), _modelBytes);
    expect(messages.last, '人声分离组件已就绪');
    expect(fractions.last, 1);
    for (var i = 1; i < fractions.length; i++) {
      expect(fractions[i], greaterThanOrEqualTo(fractions[i - 1]));
    }

    // Staging, the previous bundle and the archive are gone.
    final leftovers = release.root
        .listSync()
        .map((entity) => entity.path.split(Platform.pathSeparator).last)
        .toSet();
    expect(leftovers, containsAll(['current', 'downloads']));
    expect(leftovers, isNot(contains('staging')));
    expect(leftovers, isNot(contains('previous')));
    expect(Directory('${release.root.path}/downloads').listSync(), isEmpty);

    // A second call is served from disk.
    final again = await runtime.ensureInstalled();
    expect(again.root, installation.root);
    expect(release.downloads, 1);
    expect(release.metadataCalls, 1);
    expect(
      (await runtime.inspect())?.manifest.separatorRevision,
      ManagedVocalSeparatorRuntime.revision,
    );
  });

  test('accepts a bundle zipped inside a parent folder', () async {
    final release = await _release()
      ..nestedFolder = true;
    final installation = await release.runtime().ensureInstalled();
    expect(File(installation.modelPath).existsSync(), isTrue);
  });

  test('concurrent callers share one download', () async {
    final release = await _release();
    final runtime = release.runtime();
    final results = await Future.wait([
      runtime.ensureInstalled(),
      runtime.ensureInstalled(),
    ]);
    expect(results[0].root, results[1].root);
    expect(release.downloads, 1);
  });

  test('a corrupted download is deleted and reported', () async {
    final release = await _release()
      ..archiveSha = 'f' * 64;
    final runtime = release.runtime();
    await expectLater(
      runtime.ensureInstalled(),
      throwsA(
        isA<VocalSeparatorInstallException>().having(
          (error) => error.message,
          'message',
          contains('校验失败'),
        ),
      ),
    );
    expect(Directory('${release.root.path}/downloads').listSync(), isEmpty);
    expect(await runtime.inspect(), isNull);
  });

  test('a size mismatch is rejected before hashing', () async {
    final release = await _release()
      ..archiveSize = 1;
    await expectLater(
      release.runtime().ensureInstalled(),
      throwsA(isA<VocalSeparatorInstallException>()),
    );
  });

  test('a model that does not match the manifest is not activated', () async {
    final release = await _release()
      ..shippedModel = List<int>.filled(_modelBytes.length, 0);
    final runtime = release.runtime();
    await expectLater(
      runtime.ensureInstalled(),
      throwsA(isA<VocalSeparatorInstallException>()),
    );
    expect(await runtime.inspect(), isNull);
    expect(Directory('${release.root.path}/staging').existsSync(), isFalse);
  });

  test('a bundle of another revision is not activated', () async {
    final release = await _release()
      ..revision = 'htdemucs-ft-vocals-onnx-v0';
    await expectLater(
      release.runtime().ensureInstalled(),
      throwsA(isA<VocalSeparatorInstallException>()),
    );
  });

  test('an executable that reports another revision is rejected', () async {
    final release = await _release()
      ..versionOutput = 'lyricforge-separator 0.9.0 something-else';
    await expectLater(
      release.runtime().ensureInstalled(),
      throwsA(
        isA<VocalSeparatorInstallException>().having(
          (error) => error.message,
          'message',
          contains('版本不匹配'),
        ),
      ),
    );
  });

  test('a missing release becomes an install error', () async {
    final release = await _release()
      ..metadataError = const FormatException('release asset not found');
    await expectLater(
      release.runtime().ensureInstalled(),
      throwsA(isA<VocalSeparatorInstallException>()),
    );
    release.metadataError = const SocketException('offline');
    await expectLater(
      release.runtime().ensureInstalled(),
      throwsA(isA<VocalSeparatorInstallException>()),
    );
  });

  test('unsupported platforms never download', () async {
    final release = await _release();
    final runtime = release.runtime(supported: false);
    expect(runtime.supportsCurrentPlatform, isFalse);
    await expectLater(
      runtime.ensureInstalled(),
      throwsA(isA<VocalSeparatorInstallException>()),
    );
    expect(release.metadataCalls, 0);
  });

  test('cancelling a download throws the cancellation', () async {
    final release = await _release();
    final runtime = release.runtime();
    release.onDownload = () async => runtime.cancel();
    await expectLater(
      runtime.ensureInstalled(),
      throwsA(
        isA<TranscriptionException>().having(
          (error) => error.kind,
          'kind',
          TranscriptionFailureKind.cancelled,
        ),
      ),
    );
    // The next run starts fresh.
    release.onDownload = null;
    final installation = await runtime.ensureInstalled();
    expect(installation.manifest.vocalsIndex, 3);
  });

  test('a damaged installed model is detected', () async {
    final release = await _release();
    final runtime = release.runtime();
    final installation = await runtime.ensureInstalled();
    // Same size, different content, newer timestamp: the cached
    // verification no longer applies and the hash check fails.
    final model = File(installation.modelPath);
    await model.writeAsBytes(List<int>.filled(_modelBytes.length, 1));
    await model.setLastModified(DateTime.now().add(const Duration(hours: 1)));
    expect(await runtime.inspect(), isNull);
  });
}
