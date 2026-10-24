import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_download_connection_checker.dart';

void main() {
  group('AsrDownloadConnectionReport', () {
    test('each ModelScope model requires both a manifest and file probe', () {
      const report = AsrDownloadConnectionReport(
        whisperAvailable: true,
        huggingFaceQwenAvailable: false,
        huggingFaceAlignerAvailable: false,
        modelScopeManifestAvailable: true,
        modelScopeFileAvailable: false,
        modelScopeAlignerManifestAvailable: true,
        modelScopeAlignerFileAvailable: true,
      );

      expect(report.modelScopeQwenAvailable, isFalse);
      expect(report.modelScopeAlignerAvailable, isTrue);
      expect(report.qwenAvailable, isFalse);
      expect(report.alignerAvailable, isTrue);
      expect(report.requiredModelsAvailable, isFalse);
    });

    test('summary distinguishes Qwen and ForcedAligner sources', () {
      const report = AsrDownloadConnectionReport(
        whisperAvailable: true,
        huggingFaceQwenAvailable: true,
        huggingFaceAlignerAvailable: false,
        modelScopeManifestAvailable: true,
        modelScopeFileAvailable: true,
        modelScopeAlignerManifestAvailable: true,
        modelScopeAlignerFileAvailable: true,
        diagnostics: ['ForcedAligner (Hugging Face): HTTP 403'],
      );

      expect(report.summary, contains('Whisper large-v3 可用'));
      expect(report.summary, contains('Qwen ASR 模型来源：Hugging Face、ModelScope'));
      expect(report.summary, contains('ForcedAligner 模型来源：ModelScope'));
      expect(report.summary, contains('HTTP 403'));
      expect(report.summary, contains('不代表完整模型下载或引擎启动成功'));
    });

    test('Qwen and aligner can use different official sources', () {
      const report = AsrDownloadConnectionReport(
        whisperAvailable: true,
        huggingFaceQwenAvailable: true,
        huggingFaceAlignerAvailable: false,
        modelScopeManifestAvailable: false,
        modelScopeFileAvailable: false,
        modelScopeAlignerManifestAvailable: true,
        modelScopeAlignerFileAvailable: true,
      );

      expect(report.qwenAvailable, isTrue);
      expect(report.alignerAvailable, isTrue);
      expect(report.requiredModelsAvailable, isTrue);
    });
  });
}
