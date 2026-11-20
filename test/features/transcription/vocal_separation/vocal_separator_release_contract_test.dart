import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/vocal_separator_runtime.dart';

/// The separator bundle is built by one workflow, described by C++
/// constants and installed by Dart code. Nothing links them at compile time,
/// so these checks keep the three spellings of each name in step.
void main() {
  late String workflow;
  late String cliHeader;
  late String reportHeader;

  setUpAll(() async {
    workflow = await File(
      '.github/workflows/build-vocal-separator.yml',
    ).readAsString();
    cliHeader = await File(
      'native/vocal_separator/src/cli_options.hpp',
    ).readAsString();
    reportHeader = await File(
      'native/vocal_separator/src/report.hpp',
    ).readAsString();
  });

  test('release tag, asset and revision match the installer', () {
    expect(
      workflow,
      contains('SEPARATOR_TAG: ${ManagedVocalSeparatorRuntime.releaseTag}'),
    );
    expect(
      workflow,
      contains('SEPARATOR_REVISION: ${ManagedVocalSeparatorRuntime.revision}'),
    );
    expect(
      RegExp(
        RegExp.escape(ManagedVocalSeparatorRuntime.windowsAssetName),
      ).allMatches(workflow).length,
      greaterThanOrEqualTo(3),
      reason: 'zip, upload artifact and release upload use the asset name',
    );
    expect(
      cliHeader,
      contains(
        'kSeparatorRevision = "${ManagedVocalSeparatorRuntime.revision}"',
      ),
      reason: '--version output is checked against the manifest revision',
    );
  });

  test('the bundle carries the manifest the installer reads', () {
    expect(
      workflow,
      contains('"\$root/${ManagedVocalSeparatorRuntime.manifestFileName}"'),
    );
    for (final field in [
      'schemaVersion = 1',
      'separatorRevision = \$env:SEPARATOR_REVISION',
      'executable = "bin/lyricforge-separator.exe"',
      'file = "models/\$env:MODEL_FILE"',
      'bytes = [int64]\$model.bytes',
      'sha256 = \$model.sha256',
      'vocalsIndex = [int]\$model.vocalsIndex',
    ]) {
      expect(workflow, contains(field));
    }
    // A BOM-free manifest; the parser tolerates one, but other tools may not.
    expect(workflow, contains('Set-Content -Encoding utf8NoBOM'));
    expect(
      workflow,
      contains('Compress-Archive -Path separator/*'),
      reason: 'the manifest must sit at the archive root',
    );
  });

  test('the model is verified before it is shipped', () {
    expect(workflow, contains('export_htdemucs_vocals_onnx.py'));
    expect(workflow, contains('Model hash changed between export and bundle'));
    final export = File(
      'tool/vocal_separator/export_htdemucs_vocals_onnx.py',
    ).readAsStringSync();
    expect(export, contains('MAX_RELATIVE_ERROR'));
    expect(export, contains('"vocalsIndex"'));
    expect(export, contains('"sha256"'));
    expect(export, contains('"bytes"'));
  });

  test('both platforms separate a real song before publishing', () {
    expect(workflow, contains('check_stems.py song.wav stems separator.log'));
    expect(workflow, contains('--output-dir "stems-人声" --provider cpu'));
    expect(
      workflow,
      contains('needs: [flutter-contracts, linux-smoke, windows]'),
    );
    expect(workflow, contains("if: github.event_name != 'pull_request'"));
    expect(workflow, contains('--prerelease'));
  });

  test('the bundle ships the licences of everything inside it', () {
    for (final licence in [
      'demucs.onnx-LICENSE',
      'demucs-LICENSE',
      'eigen-COPYING.txt',
      'onnxruntime-',
      'directml-',
    ]) {
      expect(workflow, contains(licence));
    }
    expect(File('third_party/demucs_onnx/LICENSE').existsSync(), isTrue);
    expect(File('third_party/demucs_onnx/README.md').existsSync(), isTrue);
  });

  test('the stdout protocol the Dart parser reads is the one C++ writes', () {
    for (final tag in [
      'LF_STAGE',
      'LF_PROVIDER',
      'LF_FALLBACK',
      'LF_PROGRESS',
      'LF_STATS mix_rms=<f> vocals_rms=<f>',
      'LF_DONE',
      'LF_ERROR <code> <message>',
    ]) {
      expect(reportHeader, contains(tag));
    }
  });

  test('the workflow pins every external input', () {
    expect(
      RegExp(r'DEMUCS_ONNX_REV: [0-9a-f]{40}\n').hasMatch(workflow),
      isTrue,
    );
    expect(workflow, contains('ORT_VERSION: "1.22.0"'));
    expect(workflow, contains('DIRECTML_VERSION: "1.15.4"'));
    final requirements = File(
      'tool/vocal_separator/requirements.txt',
    ).readAsStringSync();
    for (final line in requirements.split('\n')) {
      final requirement = line.trim();
      if (requirement.isEmpty || requirement.startsWith('#')) continue;
      expect(
        requirement,
        matches(RegExp(r'^[A-Za-z0-9_.-]+(==[0-9.]+|<[0-9]+)$')),
        reason: 'unpinned requirement: $requirement',
      );
    }
  });
}
