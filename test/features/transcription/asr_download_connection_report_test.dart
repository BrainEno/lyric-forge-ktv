import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_download_connection_checker.dart';

void main() {
  group('AsrDownloadConnectionReport', () {
    test('ModelScope is available only when both manifest and file probes pass', () {
      const manifestOnly = AsrDownloadConnectionReport(
        whisperAvailable: true,
        huggingFaceQwenAvailable: false,
        modelScopeManifestAvailable: true,
        modelScopeFileAvailable: false,
      );
      const fileOnly = AsrDownloadConnectionReport(
        whisperAvailable: true,
        huggingFaceQwenAvailable: false,
        modelScopeManifestAvailable: false,
        modelScopeFileAvailable: true,
      );
      const modelScopeReady = AsrDownloadConnectionReport(
        whisperAvailable: true,
        huggingFaceQwenAvailable: false,
        modelScopeManifestAvailable: true,
        modelScopeFileAvailable: true,
      );

      expect(manifestOnly.modelScopeAvailable, isFalse);
      expect(manifestOnly.qwenAvailable, isFalse);
      expect(fileOnly.modelScopeAvailable, isFalse);
      expect(fileOnly.qwenAvailable, isFalse);
      expect(modelScopeReady.modelScopeAvailable, isTrue);
      expect(modelScopeReady.qwenAvailable, isTrue);
    });

    test('summary lists the source that passed and keeps the full-download caveat', () {
      const report = AsrDownloadConnectionReport(
        whisperAvailable: true,
        huggingFaceQwenAvailable: false,
        modelScopeManifestAvailable: true,
        modelScopeFileAvailable: true,
        diagnostics: ['Qwen3-ASR (Hugging Face): HTTP 403'],
      );

      expect(report.summary, contains('Whisper large-v3 可用'));
      expect(report.summary, contains('ModelScope（清单与文件端点均通过）'));
      expect(report.summary, contains('HTTP 403'));
      expect(report.summary, contains('不代表完整模型下载或引擎启动成功'));
    });

    test('report includes both official Qwen sources when both pass', () {
      const report = AsrDownloadConnectionReport(
        whisperAvailable: true,
        huggingFaceQwenAvailable: true,
        modelScopeManifestAvailable: true,
        modelScopeFileAvailable: true,
      );

      expect(report.summary, contains('Hugging Face'));
      expect(report.summary, contains('ModelScope'));
      expect(report.diagnostics, isEmpty);
    });
  });
}
