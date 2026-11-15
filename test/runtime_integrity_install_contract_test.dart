import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'managed runtime install verifies release metadata before extraction',
    () async {
      final source = await File(
        'lib/features/transcription/data/services/managed_asr_runtime_manager.dart',
      ).readAsString();

      // The call may be wrapped across lines, so match the profile argument
      // instead of an exact single-line spelling.
      expect(
        source,
        matches(RegExp(r'_fetchRuntimeReleaseAssetMetadata\(\s*profile')),
      );
      expect(source, contains('metadata.downloadUri'));
      expect(source, contains('resumable: true'));
      expect(source, contains('actualSize != metadata.sizeBytes'));
      expect(source, contains('metadata.sha256'));
      expect(source, contains("await archive.delete();"));
      expect(source, contains('正在校验 LyricForge 识别引擎完整性'));

      final checksumIndex = source.indexOf('metadata.sha256');
      final extractionIndex = source.indexOf(
        'await _extractZip(archive.path, staging.path)',
      );
      expect(checksumIndex, greaterThanOrEqualTo(0));
      expect(extractionIndex, greaterThan(checksumIndex));
    },
  );
  test(
    'managed Qwen runtime upgrades outdated bundles and validates patch revision',
    () async {
      final source = await File(
        'lib/features/transcription/data/services/managed_asr_runtime_manager.dart',
      ).readAsString();
      final modelManagerSource = await File(
        'lib/features/transcription/data/services/managed_model_asr_runtime_manager.dart',
      ).readAsString();
      final workflow = await File(
        '.github/workflows/build-asr-runtime.yml',
      ).readAsString();

      expect(source, contains("_runtimeReleaseTag = 'asr-runtime-v3'"));
      expect(
        modelManagerSource,
        contains("_runtimeReleaseTag = 'asr-runtime-v3'"),
      );
      expect(source, contains("['state', 'runtime-build-revision.txt']"));
      expect(source, contains('needsManagedRuntimeRefresh'));
      expect(source, contains('_managedRuntimeBuildIsCurrent(root)'));
      expect(source, contains('requiresManagedModelHealth'));
      expect(source, contains('qwenModelReady'));
      expect(source, contains('alignerReady'));
      expect(source, contains("decoded['runtimePatchRevision']"));
      expect(
        source,
        contains("'runtimePatchRevision': _managedRuntimeBuildRevision"),
      );
      expect(source, contains('await staging.rename(bundle.path)'));
      expect(source, contains('await backup.rename(bundle.path)'));
      expect(workflow, contains('RUNTIME_TAG: asr-runtime-v3'));
      expect(
        workflow,
        contains(
          'runtimePatchRevision = "'
          'qwen-eager-attention-contiguous-v1+forced-align-http-v1+session-security-v1"',
        ),
      );
      expect(
        workflow,
        contains(
          '"runtimePatchRevision": "'
          'qwen-eager-attention-contiguous-v1+forced-align-http-v1+session-security-v1"',
        ),
      );
    },
  );

  test(
    'managed Qwen model preparation uses the pinned authenticated child session',
    () async {
      final source = await File(
        'lib/features/transcription/data/services/managed_asr_runtime_manager.dart',
      ).readAsString();

      expect(source, contains('createQwenRuntimeSessionToken()'));
      expect(source, contains('qwenRuntimeSessionTokenEnvironment'));
      expect(source, contains('parseQwenRuntimeReadyRecord(line)'));
      expect(source, contains('readySession.createHttpClient()'));
      expect(source, contains("session.endpoint('/healthz')"));
      expect(source, contains('session.authorize(request)'));
      expect(source, contains('environment: environment'));
      expect(source, contains('includeParentEnvironment: false'));
      expect(source, contains('await _terminateManagedRuntimeProcess(process)'));
      expect(source, contains('await process.exitCode'));
      expect(source, contains('_qwenPreparationInProgress'));
      expect(source, contains('await qwenPreparation'));
      expect(source, contains("'--port',\n      '0'"));
      expect(source, isNot(contains('_reservePort')));
      expect(source, isNot(contains(r'http://127.0.0.1:$port/healthz')));
    },
  );

  test(
    'managed FFmpeg assets are pinned and verified before staging or activation',
    () async {
      final source = await File(
        'lib/features/transcription/data/services/managed_asr_runtime_manager.dart',
      ).readAsString();

      expect(source, contains('FfmpegRuntimeRelease.forTarget'));
      expect(source, contains('_verifySha256(archive.path, release.sha256)'));
      expect(source, contains('await archive.delete();'));
      expect(source, contains("['ffmpeg-staging']"));
      expect(source, contains("['ffmpeg-backup']"));

      final installerStart = source.indexOf('Future<String> _installFfmpeg(');
      final installerEnd = source.indexOf(
        'Future<String> _runtimeArchitecture()',
        installerStart,
      );
      expect(installerStart, greaterThanOrEqualTo(0));
      expect(installerEnd, greaterThan(installerStart));

      final installer = source.substring(installerStart, installerEnd);
      final verifyIndex = installer.indexOf(
        '_verifySha256(archive.path, release.sha256)',
      );
      final extractionIndex = installer.indexOf(
        'await _extractZip(archive.path, staging.path)',
      );
      final activationIndex = installer.indexOf(
        'await staging.rename(ffmpegRoot.path)',
      );
      expect(verifyIndex, greaterThanOrEqualTo(0));
      expect(extractionIndex, greaterThan(verifyIndex));
      expect(activationIndex, greaterThan(extractionIndex));
    },
  );
}
