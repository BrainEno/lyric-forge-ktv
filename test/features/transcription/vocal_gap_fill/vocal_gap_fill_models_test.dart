import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/models/vocal_check_record.dart';
import 'package:lyric_forge_ktv/features/lyrics/domain/services/lyric_span_rerecognition.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/vocal_gap_fill_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/asr_runtime_manager.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_vocal_gap_fill.dart';

Duration _s(int value) => Duration(seconds: value);

VocalGapFillSpanReport _span(
  VocalGapFillOutcome outcome, {
  int inserted = 0,
  bool fellBack = false,
  LyricSpanEngine? engine,
}) => VocalGapFillSpanReport(
  start: _s(8),
  end: _s(11),
  outcome: outcome,
  insertedLines: inserted,
  fellBack: fellBack,
  engine: engine,
);

AsrRuntimeStatus _status(Set<AsrRuntimeComponent> ready) {
  const config = TranscriptionConfig(whisperExecutable: 'w', modelPath: 'm');
  return AsrRuntimeStatus(
    profile: const ResolvedTranscriptionProfile(
      profile: TranscriptionProfilePreference.custom,
      label: 'test',
      description: 'test',
      hardware: TranscriptionHardwareInfo(
        operatingSystem: 'windows',
        architecture: 'x86_64',
      ),
      config: config,
    ),
    components: [
      for (final component in ready)
        AsrRuntimeComponentStatus(
          component: component,
          label: component.name,
          state: AsrRuntimeComponentState.ready,
          detail: 'ok',
        ),
    ],
    managedRoot: '',
  );
}

const _whisperParts = {
  AsrRuntimeComponent.ffmpeg,
  AsrRuntimeComponent.whisperRuntime,
  AsrRuntimeComponent.whisperModel,
};
const _qwenParts = {
  AsrRuntimeComponent.qwenRuntime,
  AsrRuntimeComponent.qwenModel,
  AsrRuntimeComponent.qwenAligner,
};

void main() {
  const base = TranscriptionConfig(
    whisperExecutable: 'whisper',
    modelPath: 'model',
    qwenExecutable: 'qwen',
  );

  group('VocalGapFillPreference', () {
    test('defaults to automatic and survives a JSON round trip', () {
      expect(base.vocalGapFill, VocalGapFillPreference.automatic);
      for (final value in VocalGapFillPreference.values) {
        final restored = TranscriptionConfig.fromJson(
          base.copyWith(vocalGapFill: value).toJson(),
        );
        expect(restored.vocalGapFill, value);
      }
    });

    test('settings saved before the option existed read as automatic', () {
      final json = base.toJson()..remove('vocalGapFill');
      expect(
        TranscriptionConfig.fromJson(json).vocalGapFill,
        VocalGapFillPreference.automatic,
      );
      expect(
        TranscriptionConfig.fromJson({
          ...json,
          'vocalGapFill': 'sometimes',
        }).vocalGapFill,
        VocalGapFillPreference.automatic,
      );
    });

    test('copyWith keeps the choice unless asked', () {
      final off = base.copyWith(vocalGapFill: VocalGapFillPreference.off);
      expect(
        off.copyWith(language: 'ja').vocalGapFill,
        VocalGapFillPreference.off,
      );
    });
  });

  group('VocalGapFillReport', () {
    test('counts outcomes and inserted rows', () {
      final report = VocalGapFillReport.applied(
        engines: const [LyricSpanEngine.qwen, LyricSpanEngine.whisper],
        spans: [
          _span(
            VocalGapFillOutcome.filled,
            inserted: 2,
            engine: LyricSpanEngine.qwen,
          ),
          _span(
            VocalGapFillOutcome.filled,
            inserted: 1,
            fellBack: true,
            engine: LyricSpanEngine.whisper,
          ),
          _span(VocalGapFillOutcome.empty),
          _span(VocalGapFillOutcome.failed),
          _span(VocalGapFillOutcome.unsendable),
          _span(VocalGapFillOutcome.overBudget),
          _span(VocalGapFillOutcome.notTried),
        ],
        elapsed: const Duration(seconds: 12),
      );
      expect(report.filledSpans, 2);
      expect(report.emptySpans, 1);
      expect(report.failedSpans, 1);
      expect(report.unattemptedSpans, 3);
      expect(report.fallbackSpans, 1);
      expect(report.insertedLines, 3);
      expect(report.summary, '已自动补上 2 处漏句（3 行），1 处没有识别出文字，1 处识别失败，3 处未识别');

      final json = report.toJson();
      expect(json['applied'], isTrue);
      expect(json['engines'], ['qwen', 'whisper']);
      expect(json['gaps'], 7);
      expect(json['insertedLines'], 3);
      expect(json['elapsedMs'], 12000);
      expect(json.containsKey('stopReason'), isFalse);
      final spans = json['spans'] as List;
      expect(spans.first, {
        'startMs': 8000,
        'endMs': 11000,
        'outcome': 'filled',
        'engine': 'qwen',
        'insertedLines': 2,
      });
      expect((spans[1] as Map)['fellBack'], isTrue);
    });

    test('says why it was skipped', () {
      for (final reason in VocalGapFillSkipReason.values) {
        final report = VocalGapFillReport.skipped(reason);
        expect(report.applied, isFalse);
        expect(report.summary, isNotEmpty);
        expect(report.toJson()['skipReason'], reason.name);
      }
      expect(
        const VocalGapFillReport.skipped(
          VocalGapFillSkipReason.failed,
          error: 'boom',
        ).toJson()['error'],
        'boom',
      );
    });

    test('notes an early stop', () {
      final report = VocalGapFillReport.applied(
        engines: const [LyricSpanEngine.whisper],
        spans: [_span(VocalGapFillOutcome.notTried)],
        elapsed: Duration.zero,
        stopReason: VocalGapFillStopReason.cancelled,
      );
      expect(report.summary, endsWith('（已取消）'));
      expect(report.toJson()['stopReason'], 'cancelled');
    });

    test('becomes the editor record with the inserted ids', () {
      final report = VocalGapFillReport.applied(
        engines: const [LyricSpanEngine.qwen],
        spans: [
          _span(VocalGapFillOutcome.filled, inserted: 1, fellBack: true),
          _span(VocalGapFillOutcome.empty),
          _span(VocalGapFillOutcome.overBudget),
        ],
        elapsed: Duration.zero,
      );
      final record = report.record(const ['x']);
      expect(record.insertedLineIds, ['x']);
      expect(record.filledSpans, [LyricVocalCheckSpan(_s(8), _s(11))]);
      expect(record.emptySpans, 1);
      expect(record.unattemptedSpans, 1);
      expect(record.fallbackSpans, 1);
      expect(record.totalSpans, 3);
    });
  });

  group('vocalGapFillEngines', () {
    final highQuality = base.copyWith(mode: TranscriptionMode.highestQuality);

    test('Qwen first, then Whisper, when both are ready', () {
      expect(
        vocalGapFillEngines(
          config: highQuality,
          status: _status({..._whisperParts, ..._qwenParts}),
          degraded: false,
        ),
        [LyricSpanEngine.qwen, LyricSpanEngine.whisper],
      );
    });

    test('follows the run engine order', () {
      expect(
        vocalGapFillEngines(
          config: highQuality.copyWith(
            engineOrder: TranscriptionEngineOrder.whisperPrimary,
          ),
          status: _status({..._whisperParts, ..._qwenParts}),
          degraded: false,
        ),
        [LyricSpanEngine.whisper, LyricSpanEngine.qwen],
      );
    });

    test('Whisper only for a Whisper-only run', () {
      expect(
        vocalGapFillEngines(
          config: base.copyWith(mode: TranscriptionMode.whisperOnly),
          status: _status({..._whisperParts, ..._qwenParts}),
          degraded: false,
        ),
        [LyricSpanEngine.whisper],
      );
    });

    test('Whisper only after a run degraded from Qwen', () {
      expect(
        vocalGapFillEngines(
          config: highQuality,
          status: _status({..._whisperParts, ..._qwenParts}),
          degraded: true,
        ),
        [LyricSpanEngine.whisper],
      );
    });

    test('Whisper only while the Qwen model is missing', () {
      expect(
        vocalGapFillEngines(
          config: highQuality,
          status: _status({
            ..._whisperParts,
            AsrRuntimeComponent.qwenRuntime,
            AsrRuntimeComponent.qwenAligner,
          }),
          degraded: false,
        ),
        [LyricSpanEngine.whisper],
      );
    });

    test('nothing without a configured Whisper', () {
      expect(
        vocalGapFillEngines(
          config: const TranscriptionConfig(
            mode: TranscriptionMode.whisperOnly,
            whisperExecutable: '',
            modelPath: '',
          ),
          status: _status(_whisperParts),
          degraded: false,
        ),
        isEmpty,
      );
    });
  });
}
