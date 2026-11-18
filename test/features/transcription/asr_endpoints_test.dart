import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_endpoints.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/ffmpeg_runtime_release.dart';

void main() {
  test('model files resolve on Hugging Face and ModelScope', () {
    expect(
      AsrEndpoints.huggingFaceFile(
        'Qwen/Qwen3-ASR-1.7B',
        'config.json',
      ).toString(),
      'https://huggingface.co/Qwen/Qwen3-ASR-1.7B/resolve/main/'
      'config.json?download=true',
    );
    expect(
      AsrEndpoints.whisperGgmlModel('ggml-large-v3.bin').toString(),
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/'
      'ggml-large-v3.bin?download=true',
    );
    expect(
      AsrEndpoints.modelScopeFile(
        'Qwen/Qwen3-ASR-0.6B',
        'vocab.json',
      ).toString(),
      'https://modelscope.cn/models/Qwen/Qwen3-ASR-0.6B/resolve/master/'
      'vocab.json',
    );
    final manifest = AsrEndpoints.modelScopeManifest('Qwen/Qwen3-ASR-0.6B');
    expect(manifest.host, 'modelscope.cn');
    expect(manifest.path, '/api/v1/models/Qwen/Qwen3-ASR-0.6B/repo/files');
    expect(manifest.queryParameters, {
      'Revision': 'master',
      'Recursive': 'true',
    });
  });

  test('runtime releases come from the configured repository', () {
    expect(AsrEndpoints.releaseRepository, 'BrainEno/lyric-forge-ktv');
    expect(
      AsrEndpoints.runtimeReleaseAsset(
        'asr-runtime-v3',
        'bundle.zip',
      ).toString(),
      'https://github.com/BrainEno/lyric-forge-ktv/releases/download/'
      'asr-runtime-v3/bundle.zip',
    );
    expect(
      AsrEndpoints.runtimeReleaseMetadata('asr-runtime-v3').toString(),
      'https://api.github.com/repos/BrainEno/lyric-forge-ktv/releases/tags/'
      'asr-runtime-v3',
    );
    expect(
      AsrEndpoints.whisperCppReleaseAsset(
        'v1.8.2',
        'whisper-bin-x64.zip',
      ).toString(),
      'https://github.com/ggml-org/whisper.cpp/releases/download/'
      'v1.8.2/whisper-bin-x64.zip',
    );
    expect(AsrEndpoints.proxyProbe.toString(), 'https://huggingface.co/');
  });

  test('pinned FFmpeg assets keep their release download roots', () {
    for (final release in FfmpegRuntimeRelease.supported) {
      expect(release.downloadUri.scheme, 'https');
      expect(release.downloadUri.host, 'github.com');
      expect(
        release.downloadUrl.startsWith(
              AsrEndpoints.btbnFfmpegReleaseDownloads,
            ) ||
            release.downloadUrl.startsWith(
              AsrEndpoints.boul2gomFfmpegReleaseDownloads,
            ),
        isTrue,
        reason: release.downloadUrl,
      );
    }
    expect(
      FfmpegRuntimeRelease.macosArm64.downloadUrl,
      'https://github.com/boul2gom/ffmpeg-builds/releases/download/'
      'v9.0.2/ffmpeg-osx-arm64.zip',
    );
  });
}
