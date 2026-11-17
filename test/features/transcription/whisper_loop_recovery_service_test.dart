import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_process_supervisor.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/whisper_cpp_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/whisper_loop_recovery.dart';

import 'domain/whisper_loop_fixtures.dart';

const _helpWithRecoveryFlags = '''
usage: whisper-cli [options] file0 file1 ...
  -ot N,     --offset-t N           [0      ] time offset in milliseconds
  -d  N,     --duration N           [0      ] duration of audio to process in milliseconds
  -mc N,     --max-context N        [-1     ] maximum number of text context tokens to store
  -sns,      --suppress-nst         [false  ] suppress non-speech tokens
  --prompt PROMPT                   [       ] initial prompt
  -m FNAME,  --model FNAME          [models/ggml-base.en.bin] model path
  -f FNAME,  --file FNAME           [       ] input audio file path
''';

const _helpWithoutRecoveryFlags = '''
usage: whisper-cli [options] file0 file1 ...
  -sns,      --suppress-nst         [false  ] suppress non-speech tokens
  --prompt PROMPT                   [       ] initial prompt
  -m FNAME,  --model FNAME          [models/ggml-base.en.bin] model path
  -f FNAME,  --file FNAME           [       ] input audio file path
''';

Map<String, Object> _segment(LyricLine line) => {
  'text': line.text,
  'offsets': {
    'from': line.startTime.inMilliseconds,
    'to': line.endTime.inMilliseconds,
  },
};

/// whisper-cli double: the first call decodes the whole file into a loop,
/// calls with `--offset-t` answer with [redecode].
class _LoopingWhisper {
  String helpText;
  List<LyricLine> firstPass;
  List<LyricLine> redecode;
  bool failRedecode;
  final List<List<String>> invocations = [];

  _LoopingWhisper({
    this.helpText = _helpWithRecoveryFlags,
    List<LyricLine>? firstPass,
    List<LyricLine>? redecode,
    this.failRedecode = false,
  }) : firstPass = firstPass ?? whisperLoopedSong(),
       redecode = redecode ?? const [];

  List<List<String>> get redecodeCalls => [
    for (final args in invocations)
      if (args.contains('--offset-t')) args,
  ];

  Future<Process> start(String executable, List<String> arguments) async {
    invocations.add(List.of(arguments));
    final process = _FakeProcess();
    if (arguments.length == 1 && arguments.single == '-h') {
      scheduleMicrotask(() {
        for (final line in const LineSplitter().convert(helpText)) {
          process.emitStderr('$line\n');
        }
        process.finish(0);
      });
      return process;
    }
    final isRedecode = arguments.contains('--offset-t');
    scheduleMicrotask(() async {
      if (isRedecode && failRedecode) {
        process.emitStderr('whisper_full_with_state: failed to encode\n');
        process.finish(3);
        return;
      }
      final outputBase = arguments[arguments.indexOf('-of') + 1];
      final rows = isRedecode ? redecode : firstPass;
      await File('$outputBase.json').writeAsString(
        jsonEncode({
          'result': {'language': 'en'},
          'transcription': [for (final row in rows) _segment(row)],
        }),
      );
      process.emitStderr('whisper_print_progress_callback: progress = 100%\n');
      process.finish(0);
    });
    return process;
  }
}

List<LyricLine> _cleanRedecode() => [
  loopLine('How far is the harbour, is it under the water?', 89500, 95000),
  loopLine('I hope we arrive in time', 95500, 99000),
  loopLine('Now you never look back on the way', 101500, 107000),
  loopLine('Oh, and the lanterns that you hold', 107500, 113500),
  loopLine('Oh, but the people you know', 114000, 117000),
];

void main() {
  late Directory root;
  late String executable;
  late String ffmpeg;
  late String model;
  late String wav;

  setUp(() async {
    WhisperCppTranscriptionService.clearCapabilityCache();
    root = await Directory.systemTemp.createTemp('whisper_loop_recovery');
    executable = '${root.path}/whisper-cli';
    ffmpeg = '${root.path}/ffmpeg';
    model = '${root.path}/ggml-large-v3.bin';
    wav = '${root.path}/normalized.wav';
    for (final path in [executable, ffmpeg, model]) {
      await File(path).writeAsString('x');
    }
    // 180 s of 16 kHz mono 16-bit PCM.
    await File(wav).writeAsBytes(List<int>.filled(44 + 32000 * 180, 0));
  });

  tearDown(() async {
    WhisperCppTranscriptionService.clearCapabilityCache();
    if (await root.exists()) await root.delete(recursive: true);
  });

  TranscriptionRequest request({
    WhisperDecodingProfile profile = WhisperDecodingProfile.lyrics,
    String language = 'auto',
  }) => TranscriptionRequest(
    inputAudioPath: wav,
    normalizedInputAudioPath: wav,
    outputDirectory: '${root.path}/out',
    config: TranscriptionConfig(
      mode: TranscriptionMode.whisperOnly,
      whisperExecutable: executable,
      ffmpegExecutable: ffmpeg,
      modelPath: model,
      language: language,
      whisperDecodingProfile: profile,
    ),
    recognitionHints: const RecognitionHints(
      songTitle: 'Harbour Lights',
      artist: 'Mira',
    ),
  );

  // Recovery only runs when the first pass kept the text history, which the
  // lyrics profile switches off on any runtime that has the flags (D-027).
  Future<TranscriptionResult> run(
    _LoopingWhisper fake, {
    WhisperDecodingProfile profile = WhisperDecodingProfile.standard,
    String language = 'auto',
  }) async {
    final service = WhisperCppTranscriptionService(
      processSupervisor: AsrProcessSupervisor(
        startProcess: fake.start,
        streamDrainGrace: const Duration(milliseconds: 20),
      ),
      isWindows: false,
    );
    try {
      return await service.transcribe(
        request(profile: profile, language: language),
      );
    } finally {
      await service.dispose();
    }
  }

  test(
    're-decodes a looped span without text history and splices it in',
    () async {
      final fake = _LoopingWhisper(redecode: _cleanRedecode());
      final result = await run(fake);

      final call = fake.redecodeCalls.single;
      expect(call[call.indexOf('--offset-t') + 1], '89280');
      expect(call[call.indexOf('--duration') + 1], '${117360 - 89280}');
      expect(call[call.indexOf('--max-context') + 1], '0');
      // The standard profile sends no lyric-only flags, so neither does its
      // re-decode.
      expect(call, isNot(contains('--suppress-nst')));
      expect(call, isNot(contains('--prompt')));
      // The clip reuses the language the full-song pass detected.
      expect(call[call.indexOf('-l') + 1], 'en');
      expect(call[call.indexOf('-of') + 1], endsWith('whisper_result.loop0'));

      final texts = result.lyrics.lines.map((line) => line.text).toList();
      expect(texts.where((text) => text == loopVerse), isEmpty);
      expect(texts, contains('Oh, but the people you know'));
      expect(result.lyrics.lines, hasLength(4 + 5 + 2));
      expect(result.lyrics.metadata['segmentCount'], 11);
      // Re-decoded rows are genuine Whisper output with Whisper's own scores.
      expect(
        result.lyrics.lines[4].confidenceSource,
        isNot(LyricConfidenceSource.heuristic),
      );

      final report =
          result.lyrics.metadata[kWhisperLoopRecoveryMetadataKey] as Map;
      expect(report['policy'], WhisperLoopRecoveryPolicy.id);
      expect(report['status'], 'all_regions_replaced');
      expect(report['language'], 'en');
      final region = (report['regions'] as List).single as Map;
      expect(region['outcome'], 'replaced');
      expect(region['insertedCount'], 5);
      expect((report['detectedLoops'] as List).single['repeats'], 11);
    },
  );

  test('keeps the first pass when the history-free decode loops too', () async {
    final fake = _LoopingWhisper(
      redecode: [
        for (var i = 0; i < 8; i++)
          loopLine(loopVerse, 90000 + i * 3000, 93000 + i * 3000),
      ],
    );
    final result = await run(fake);

    expect(fake.redecodeCalls, hasLength(1));
    expect(result.lyrics.lines, hasLength(whisperLoopedSong().length));
    final report =
        result.lyrics.metadata[kWhisperLoopRecoveryMetadataKey] as Map;
    expect(report['status'], 'no_region_replaced');
    expect((report['regions'] as List).single['outcome'], 'stillLooping');
  });

  test('a failed re-decode never fails the recognition', () async {
    final fake = _LoopingWhisper(failRedecode: true);
    final result = await run(fake);

    expect(result.lyrics.lines, hasLength(whisperLoopedSong().length));
    final report =
        result.lyrics.metadata[kWhisperLoopRecoveryMetadataKey] as Map;
    final region = (report['regions'] as List).single as Map;
    expect(region['outcome'], 'failed');
    expect(region['error'], isNotNull);
  });

  test('a runtime without the flags is reported, not guessed at', () async {
    final fake = _LoopingWhisper(helpText: _helpWithoutRecoveryFlags);
    final result = await run(fake);

    expect(fake.redecodeCalls, isEmpty);
    final report =
        result.lyrics.metadata[kWhisperLoopRecoveryMetadataKey] as Map;
    expect(report['status'], 'runtime_lacks_loop_recovery_flags');
    expect(report['regions'], hasLength(1));
  });

  test('an explicit language is reused for the re-decode', () async {
    final fake = _LoopingWhisper(redecode: _cleanRedecode());
    final result = await run(fake, language: 'en');

    final call = fake.redecodeCalls.single;
    expect(call[call.indexOf('-l') + 1], 'en');
    final report =
        result.lyrics.metadata[kWhisperLoopRecoveryMetadataKey] as Map;
    expect(report['status'], 'all_regions_replaced');
  });

  test('a history-free first pass is not decoded again', () async {
    // The lyrics profile already ran with `--max-context 0`; the same decode
    // of the same audio would only repeat itself, so the loop is reported
    // and left to the Qwen arbiter.
    final fake = _LoopingWhisper(redecode: _cleanRedecode());
    final result = await run(fake, profile: WhisperDecodingProfile.lyrics);

    final main = fake.invocations.firstWhere(
      (args) => args.contains('-of') && !args.contains('--offset-t'),
    );
    expect(main[main.indexOf('--max-context') + 1], '0');
    expect(fake.redecodeCalls, isEmpty);
    expect(result.lyrics.lines, hasLength(whisperLoopedSong().length));
    final report =
        result.lyrics.metadata[kWhisperLoopRecoveryMetadataKey] as Map;
    expect(report['status'], 'history_already_off_left_for_fusion');
    expect(report['regions'], hasLength(1));
  });

  test('a lyrics run without the history switch says why', () async {
    // Runtime without `--max-context`: no history switch in the main pass,
    // and no re-decode either, because the clip decode needs the same flag.
    final fake = _LoopingWhisper(helpText: _helpWithoutRecoveryFlags);
    final result = await run(fake, profile: WhisperDecodingProfile.lyrics);

    expect(fake.redecodeCalls, isEmpty);
    final report =
        result.lyrics.metadata[kWhisperLoopRecoveryMetadataKey] as Map;
    expect(report['status'], 'runtime_lacks_loop_recovery_flags');
  });

  test('loop-free output runs whisper once and adds no report', () async {
    final fake = _LoopingWhisper(
      firstPass: [
        loopLine('city lights are calling', 0, 3000),
        loopLine('every window burning gold', 3000, 6000),
      ],
    );
    final result = await run(fake);

    expect(fake.redecodeCalls, isEmpty);
    expect(
      result.lyrics.metadata.containsKey(kWhisperLoopRecoveryMetadataKey),
      isFalse,
    );
  });

  test('weak repetition is reported for the fusion step only', () async {
    final fake = _LoopingWhisper(
      firstPass: [
        loopLine('verse line here', 0, 3000),
        for (var i = 0; i < 3; i++)
          loopLine('let it go', 3000 + i * 3000, 6000 + i * 3000),
      ],
    );
    final result = await run(fake);

    expect(fake.redecodeCalls, isEmpty);
    final report =
        result.lyrics.metadata[kWhisperLoopRecoveryMetadataKey] as Map;
    expect(report['status'], 'weak_loops_left_for_fusion');
  });
}

class _FakeProcess implements Process {
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();

  @override
  IOSink get stdin => IOSink(_DiscardingConsumer());

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  int get pid => 4343;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    finish(137);
    return true;
  }

  void emitStderr(String text) => _stderr.add(utf8.encode(text));

  void finish(int code) {
    if (!_exitCode.isCompleted) _exitCode.complete(code);
    unawaited(_stdout.close());
    unawaited(_stderr.close());
  }
}

class _DiscardingConsumer implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<void> close() async {}
}
