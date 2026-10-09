import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('managed ASR release publishes any successful platform bundle', () async {
    final workflow = await File(
      '.github/workflows/build-asr-runtime.yml',
    ).readAsString();

    expect(
      workflow,
      contains("needs: [flutter-validation, windows-cuda, macos-intel]"),
      reason: 'publish must observe validation plus both platform build results',
    );
    expect(
      workflow,
      contains('always() &&'),
      reason: 'publish must still be evaluated when one platform build fails',
    );
    expect(
      workflow,
      contains("needs.flutter-validation.result == 'success'"),
      reason: 'a broken Flutter validation must still block release publication',
    );
    expect(
      workflow,
      contains("needs.windows-cuda.result == 'success'"),
    );
    expect(
      workflow,
      contains("needs.macos-intel.result == 'success'"),
    );
    expect(
      workflow,
      contains("if: needs.windows-cuda.result == 'success'"),
      reason: 'Windows artifact download must be conditional on its own build',
    );
    expect(
      workflow,
      contains("if: needs.macos-intel.result == 'success'"),
      reason: 'macOS artifact download must be conditional on its own build',
    );
    expect(
      workflow,
      contains('gh release upload "\$RUNTIME_TAG" dist/*.zip --clobber'),
      reason: 'release upload must accept whichever platform artifacts exist',
    );
    expect(
      workflow,
      isNot(contains(
        'gh release upload "\$RUNTIME_TAG" '
        'dist/lyricforge-asr-runtime-windows-x64-cuda.zip '
        'dist/lyricforge-asr-runtime-macos-x64.zip --clobber',
      )),
      reason: 'publication must not require both platform files to exist',
    );
  });

  test('Windows bundle keeps Qwen on CUDA and Whisper as CPU fallback', () async {
    final workflow = await File(
      '.github/workflows/build-asr-runtime.yml',
    ).readAsString();

    expect(
      workflow,
      contains('Build Qwen CUDA runtime for RTX 5080'),
      reason: 'the primary Qwen engine must retain RTX 5080 CUDA acceleration',
    );
    expect(
      workflow,
      contains('Build whisper.cpp CPU fallback'),
      reason: 'Whisper is only the low-confidence fallback in the Windows bundle',
    );
    expect(workflow, contains('-DGGML_CUDA=OFF'));
    expect(workflow, contains('whisperAccelerator = "cpu"'));
    expect(workflow, contains('qwenAccelerator = "cuda"'));
    expect(
      workflow,
      isNot(contains('Build whisper.cpp CUDA runtime for RTX 5080')),
      reason: 'the fallback must not block first release on a second CUDA build',
    );
  });
}
