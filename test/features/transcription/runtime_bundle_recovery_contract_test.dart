import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keeps the recovery paths of D-051 wired: a verified runtime bundle is not
/// fetched again, every zip goes through the checked extractor, and every
/// installer retries dropped transfers from their part files.
void main() {
  const services = 'lib/features/transcription/data/services';
  String read(String name) => File('$services/$name').readAsStringSync();

  test('a verified runtime bundle on disk is installed without a download', () {
    final source = read('managed_asr_runtime_manager.dart');
    final start = source.indexOf(
      'Future<(String, String)> _installManagedRuntimeBundle(',
    );
    final end = source.indexOf('Future<String> _installFfmpeg(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final installer = source.substring(start, end);

    final reuse = installer.indexOf('_verifiedArchiveOnDisk(');
    final download = installer.indexOf('await _download(');
    final extraction = installer.indexOf(
      'await _extractZip(archive.path, staging.path)',
    );
    expect(reuse, greaterThanOrEqualTo(0));
    expect(download, greaterThan(reuse));
    expect(extraction, greaterThan(download));
    expect(installer, contains('if (reusedArchive)'));
    expect(installer, contains('expectedBytes: metadata.sizeBytes'));
    // A failed extraction must not discard the verified 1.2 GB archive.
    final catchBlock = installer.substring(
      installer.lastIndexOf('} catch (_) {'),
    );
    expect(catchBlock, isNot(contains('archive.delete')));

    expect(source, contains('reuseFfmpegArchive'));
  });

  test('a missing manifest is diagnosed from the archive listing', () {
    final source = read('managed_asr_runtime_manager.dart');

    expect(source, contains('_missingManifestError(extraction, staging)'));
    expect(source, contains("archiveContains(_runtimeManifestName) == false"));
    expect(source, contains('ZipBundleExtractor.describeTree(staging)'));
    expect(source, contains('重试时不会重新下载'));
  });

  test('only the checked extractor runs archive tools', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('zip_bundle_extractor.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('Expand-Archive') ||
          source.contains("'/usr/bin/unzip'")) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty);

    for (final name in const [
      'managed_asr_runtime_manager.dart',
      'resilient_asr_runtime_manager.dart',
      'vocal_separator_runtime.dart',
    ]) {
      expect(read(name), contains('ZipBundleExtractor('), reason: name);
    }
  });

  test('every installer retries dropped transfers from the part file', () {
    for (final name in const [
      'managed_asr_runtime_manager.dart',
      'managed_model_asr_runtime_manager.dart',
      'resilient_asr_runtime_manager.dart',
      'vocal_separator_runtime.dart',
    ]) {
      expect(read(name), contains('transientRetries: 3'), reason: name);
    }
    final managed = read('managed_asr_runtime_manager.dart');
    final models = read('managed_model_asr_runtime_manager.dart');
    expect(managed, contains('describeDownloadRetry(label, retry)'));
    expect(models, contains('describeDownloadRetry('));
    expect(models, contains('_carryPartialAcrossSources('));
    expect(models, contains('_preferSourceWithLongerPartial('));
  });
}
