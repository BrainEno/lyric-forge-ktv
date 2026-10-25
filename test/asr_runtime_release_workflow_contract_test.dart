import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('managed ASR release publishes any successful platform bundle', () async {
    final workflow = await File(
      '.github/workflows/build-asr-runtime.yml',
    ).readAsString();

    expect(workflow, contains('RUNTIME_TAG: asr-runtime-v2'));
    expect(
      workflow,
      contains('runtimePatchRevision = "qwen-eager-attention-contiguous-v1+forced-align-http-v1"'),
    );
    expect(
      workflow,
      contains('"runtimePatchRevision": "qwen-eager-attention-contiguous-v1+forced-align-http-v1"'),
    );
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

  test('managed Qwen builds apply the eager-attention contiguous-layout patch', () async {
    final workflow = await File(
      '.github/workflows/build-asr-runtime.yml',
    ).readAsString();
    final patch = await File(
      'tool/patches/qwen3-asr-eager-attention-contiguous.patch',
    ).readAsString();

    expect(workflow, contains('Apply eager attention matmul layout fix'));
    expect(
      workflow,
      contains('tool/patches/qwen3-asr-eager-attention-contiguous.patch'),
    );
    expect(workflow, contains('git apply --check'));
    expect(
      workflow,
      contains('Test eager attention matmul layout regression'),
      reason: 'the patched Rust regression test must run in CI',
    );
    expect(
      patch,
      contains('fn contiguous_for_attention_matmul(x: Tensor) -> Result<Tensor>'),
    );
    expect(patch, contains('x.contiguous()'));
    expect(patch, contains('let q = contiguous_for_attention_matmul(q)?;'));
    expect(
      patch,
      contains('contiguous_for_attention_matmul(k.transpose(2, 3)?)?'),
    );
    expect(patch, contains('test_eager_attention_matmul_materializes_transposed_inputs'));
  });

  test('managed Qwen builds expose explicit forced alignment', () async {
    final workflow = await File(
      '.github/workflows/build-asr-runtime.yml',
    ).readAsString();
    final patch = await File(
      'tool/patches/qwen3-asr-forced-align-http-endpoint.patch',
    ).readAsString();

    expect(workflow, contains('Apply arbitrary-text forced-alignment endpoint'));
    expect(
      workflow,
      contains('tool/patches/qwen3-asr-forced-align-http-endpoint.patch'),
    );
    expect(
      workflow,
      contains('mock_serve_align_rejects_missing_contract_fields'),
      reason: 'native CI must exercise the explicit alignment request contract',
    );
    expect(patch, contains('WorkerCommand::Align'));
    expect(patch, contains('align(&audio_inputs, &texts, &languages)'));
    expect(patch, contains('.route("/v1/align", post(align).options(options_ok))'));
    expect(patch, contains('"text must not be empty"'));
    expect(patch, contains('"language must not be empty"'));
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
