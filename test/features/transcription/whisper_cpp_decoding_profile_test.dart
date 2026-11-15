import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_process_supervisor.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/whisper_cpp_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';

const _helpWithLyricFlags = '''
usage: whisper-cli [options] file0 file1 ...
  -h,        --help              [default] show this help message and exit
  -pp,       --print-progress    [false  ] print progress
  -sns,      --suppress-nst      [false  ] suppress non-speech tokens
  --prompt PROMPT                [       ] initial prompt
  -m FNAME,  --model FNAME       [models/ggml-base.en.bin] model path
  -f FNAME,  --file FNAME        [       ] input audio file path
''';

const _helpWithoutLyricFlags = '''
usage: whisper-cli [options] file0 file1 ...
  -h,        --help              [default] show this help message and exit
  -m FNAME,  --model FNAME       [models/ggml-base.en.bin] model path
  -f FNAME,  --file FNAME        [       ] input audio file path
''';

/// Scripted whisper-cli: answers `-h`, honours or rejects flags, and writes the
/// JSON a real run would write.
class _FakeWhisper {
  String helpText;
  Set<String> rejectedFlags;
  bool supportsResponseFile;
  List<Map<String, Object>> segments;
  final List<List<String>> invocations = [];
  final List<List<String>> responseFileContents = [];
  int helpCalls = 0;

  _FakeWhisper({
    this.helpText = _helpWithLyricFlags,
    this.rejectedFlags = const {},
    this.supportsResponseFile = true,
    List<Map<String, Object>>? segments,
  }) : segments =
           segments ??
           [
             _segment('first line here', 0, 2000),
             _segment('second line here', 2000, 4000),
           ];

  Future<Process> start(String executable, List<String> arguments) async {
    invocations.add(List.of(arguments));
    final process = _FakeProcess();
    if (arguments.length == 1 && arguments.single == '-h') {
      helpCalls++;
      scheduleMicrotask(() {
        for (final line in const LineSplitter().convert(helpText)) {
          process.emitStderr('$line\n');
        }
        process.finish(0);
      });
      return process;
    }

    var effective = arguments;
    if (arguments.length == 1 && arguments.single.startsWith('@')) {
      if (!supportsResponseFile) {
        scheduleMicrotask(() {
          process.emitStderr('error: failed to open ${arguments.single}\n');
          process.finish(10);
        });
        return process;
      }
      final file = File(arguments.single.substring(1));
      final bytes = await file.readAsBytes();
      effective = const LineSplitter().convert(utf8.decode(bytes));
      responseFileContents.add(effective);
    }

    final rejected = effective.where(rejectedFlags.contains).toList();
    scheduleMicrotask(() async {
      if (rejected.isNotEmpty) {
        // whisper-cli prints usage and exits 0 without writing JSON.
        process.emitStderr('error: unknown argument: ${rejected.first}\n');
        process.emitStderr('usage: whisper-cli [options] file0 file1 ...\n');
        process.finish(0);
        return;
      }
      final outputBase = effective[effective.indexOf('-of') + 1];
      await File('$outputBase.json').writeAsString(
        jsonEncode({
          'result': {'language': 'en'},
          'transcription': segments,
        }),
      );
      process.emitStderr('whisper_print_progress_callback: progress = 100%\n');
      process.finish(0);
    });
    return process;
  }
}

Map<String, Object> _segment(String text, int from, int to) => {
  'text': text,
  'offsets': {'from': from, 'to': to},
};

void main() {
  late Directory root;
  late String executable;
  late String ffmpeg;
  late String model;
  late String wav;

  setUp(() async {
    WhisperCppTranscriptionService.clearCapabilityCache();
    root = await Directory.systemTemp.createTemp('whisper_profile_test');
    executable = '${root.path}/whisper-cli';
    ffmpeg = '${root.path}/ffmpeg';
    model = '${root.path}/ggml-small.bin';
    wav = '${root.path}/normalized.wav';
    for (final path in [executable, ffmpeg, model]) {
      await File(path).writeAsString('x');
    }
    await File(wav).writeAsBytes(List<int>.filled(44 + 32000, 0));
  });

  tearDown(() async {
    WhisperCppTranscriptionService.clearCapabilityCache();
    if (await root.exists()) await root.delete(recursive: true);
  });

  TranscriptionRequest request({
    WhisperDecodingProfile profile = WhisperDecodingProfile.lyrics,
    RecognitionHints hints = const RecognitionHints(
      songTitle: 'Neon Harbor',
      artist: 'Mira',
    ),
    String language = 'en',
    String? modelPath,
    String? outputDirectory,
  }) => TranscriptionRequest(
    inputAudioPath: wav,
    normalizedInputAudioPath: wav,
    outputDirectory: outputDirectory ?? '${root.path}/out',
    config: TranscriptionConfig(
      mode: TranscriptionMode.whisperOnly,
      whisperExecutable: executable,
      ffmpegExecutable: ffmpeg,
      modelPath: modelPath ?? model,
      language: language,
      whisperDecodingProfile: profile,
    ),
    recognitionHints: hints,
  );

  WhisperCppTranscriptionService service(
    _FakeWhisper fake, {
    bool isWindows = false,
  }) => WhisperCppTranscriptionService(
    processSupervisor: AsrProcessSupervisor(
      startProcess: fake.start,
      streamDrainGrace: const Duration(milliseconds: 20),
    ),
    isWindows: isWindows,
  );

  List<String> recognitionArgs(_FakeWhisper fake) => fake.invocations.lastWhere(
    (args) => !(args.length == 1 && args[0] == '-h'),
  );

  test('lyrics profile sends a metadata prompt and records it', () async {
    final fake = _FakeWhisper();
    final result = await service(fake).transcribe(request());

    final args = recognitionArgs(fake);
    expect(args.sublist(0, 11), [
      '-m',
      model,
      '-f',
      wav,
      '-l',
      'en',
      '-ojf',
      '-of',
      '${root.path}/out/whisper_result',
      '-pp',
      '--prompt',
    ]);
    expect(args[11], 'Song: Neon Harbor. Artist: Mira.');
    expect(args.last, '--suppress-nst');

    final decoding = result.lyrics.metadata[kWhisperDecodingMetadataKey] as Map;
    expect(decoding['requestedProfile'], 'whisper-lyrics-v1');
    expect(decoding['effectiveProfile'], 'whisper-lyrics-v1');
    expect(decoding['promptTransport'], 'argv');
    expect(decoding['promptSources'], ['title', 'artist']);
    expect(decoding.containsKey('fallbackReason'), isFalse);
    expect(result.lyrics.lines.map((line) => line.text), [
      'first line here',
      'second line here',
    ]);
  });

  test('standard profile is byte-identical to the old command line', () async {
    final fake = _FakeWhisper();
    final result = await service(
      fake,
    ).transcribe(request(profile: WhisperDecodingProfile.standard));

    expect(fake.helpCalls, 0, reason: 'standard never probes');
    expect(recognitionArgs(fake), [
      '-m',
      model,
      '-f',
      wav,
      '-l',
      'en',
      '-ojf',
      '-of',
      '${root.path}/out/whisper_result',
      '-pp',
    ]);
    final decoding = result.lyrics.metadata[kWhisperDecodingMetadataKey] as Map;
    expect(decoding['effectiveProfile'], 'whisper-standard-v1');
    expect(decoding['requestedProfile'], 'whisper-standard-v1');
  });

  test('a runtime without the flags gets the standard line', () async {
    final fake = _FakeWhisper(helpText: _helpWithoutLyricFlags);
    final result = await service(fake).transcribe(request());

    expect(recognitionArgs(fake), isNot(contains('--prompt')));
    expect(recognitionArgs(fake), isNot(contains('--suppress-nst')));
    final decoding = result.lyrics.metadata[kWhisperDecodingMetadataKey] as Map;
    expect(decoding['requestedProfile'], 'whisper-lyrics-v1');
    expect(decoding['effectiveProfile'], 'whisper-standard-v1');
    expect(decoding['omittedFlags'], ['--prompt', '--suppress-nst']);
  });

  test('help that is unreadable means unknown, never a failure', () async {
    final fake = _FakeWhisper(helpText: 'segmentation fault');
    final result = await service(fake).transcribe(request());
    expect(recognitionArgs(fake).last, '-pp');
    expect(result.lyrics.lines, hasLength(2));
  });

  test('help probe is cached per binary', () async {
    final fake = _FakeWhisper();
    await service(fake).transcribe(request(outputDirectory: '${root.path}/a'));
    await service(fake).transcribe(request(outputDirectory: '${root.path}/b'));
    expect(fake.helpCalls, 1);

    // Replacing the runtime (new size/mtime) is probed again.
    await File(executable).writeAsString('a newer, longer binary');
    await service(fake).transcribe(request(outputDirectory: '${root.path}/c'));
    expect(fake.helpCalls, 2);
  });

  test(
    'an advertised flag the runtime rejects triggers one standard retry',
    () async {
      final fake = _FakeWhisper(rejectedFlags: {'--suppress-nst'});
      final whisper = service(fake);
      final messages = <String>[];
      final subscription = whisper.progressStream.listen(
        (progress) => messages.add(progress.message),
      );
      final result = await whisper.transcribe(request());
      await subscription.cancel();

      final runs = fake.invocations
          .where((args) => !(args.length == 1 && args[0] == '-h'))
          .toList();
      expect(runs, hasLength(2));
      expect(runs.first, contains('--suppress-nst'));
      expect(runs.last.last, '-pp');
      final decoding =
          result.lyrics.metadata[kWhisperDecodingMetadataKey] as Map;
      expect(decoding['effectiveProfile'], 'whisper-standard-v1');
      expect(
        decoding['fallbackReason'],
        startsWith('runtime_rejected_arguments:'),
      );
      expect(
        decoding['omittedFlags'],
        containsAll(['--prompt', '--suppress-nst']),
      );
      expect(messages, contains('Whisper 运行时不支持歌词参数，改用标准参数重试'));
    },
  );

  group('Windows transport', () {
    test('a CJK prompt goes through a UTF-8 response file', () async {
      final fake = _FakeWhisper();
      final result = await service(fake, isWindows: true).transcribe(
        request(
          language: 'zh',
          hints: const RecognitionHints(songTitle: '夜航', artist: '林'),
        ),
      );

      final args = recognitionArgs(fake);
      expect(args, hasLength(1));
      expect(args.single, startsWith('@'));
      expect(args.single, endsWith('whisper_result.args.rsp'));
      final lines = fake.responseFileContents.single;
      expect(lines[lines.indexOf('--prompt') + 1], '歌曲《夜航》，演唱：林。');
      expect(lines, contains('--suppress-nst'));
      expect(await File(args.single.substring(1)).exists(), isFalse);

      final decoding =
          result.lyrics.metadata[kWhisperDecodingMetadataKey] as Map;
      expect(decoding['promptTransport'], 'response-file');
      expect(decoding['effectiveProfile'], 'whisper-lyrics-v1');
    });

    test('an ASCII prompt stays on argv', () async {
      final fake = _FakeWhisper();
      await service(fake, isWindows: true).transcribe(request());
      expect(recognitionArgs(fake), contains('--prompt'));
    });

    test('non-ASCII paths drop the prompt instead of mangling it', () async {
      final cjkModel = '${root.path}/模型.bin';
      await File(cjkModel).writeAsString('x');
      final fake = _FakeWhisper();
      final result = await service(fake, isWindows: true).transcribe(
        request(
          modelPath: cjkModel,
          language: 'zh',
          hints: const RecognitionHints(songTitle: '夜航'),
        ),
      );

      final args = recognitionArgs(fake);
      expect(args, isNot(contains('--prompt')));
      expect(args.last, '--suppress-nst');
      final decoding =
          result.lyrics.metadata[kWhisperDecodingMetadataKey] as Map;
      expect(
        decoding['fallbackReason'],
        'windows_non_ascii_paths_prompt_omitted',
      );
      expect(decoding['omittedFlags'], contains('--prompt'));
      expect(decoding['effectiveProfile'], 'whisper-lyrics-v1');
    });

    test('a runtime ignoring response files is retried with argv', () async {
      final fake = _FakeWhisper(supportsResponseFile: false);
      final result = await service(fake, isWindows: true).transcribe(
        request(
          language: 'zh',
          hints: const RecognitionHints(songTitle: '夜航'),
        ),
      );

      expect(recognitionArgs(fake).last, '-pp');
      final decoding =
          result.lyrics.metadata[kWhisperDecodingMetadataKey] as Map;
      expect(decoding['effectiveProfile'], 'whisper-standard-v1');
      expect(
        decoding['fallbackReason'],
        'runtime_rejected_arguments: response file not honoured',
      );
    });
  });

  group('prompt echo', () {
    test('only rows repeating the entire prompt are removed', () async {
      final fake = _FakeWhisper(
        segments: [
          _segment('Song: Neon Harbor. Artist: Mira.', 0, 1500),
          _segment('Neon Harbor, take me home', 1500, 4000),
          _segment('song neon harbor artist mira', 4000, 5000),
        ],
      );
      final result = await service(fake).transcribe(request());
      expect(result.lyrics.lines.map((line) => line.text), [
        'Neon Harbor, take me home',
      ]);
      final decoding =
          result.lyrics.metadata[kWhisperDecodingMetadataKey] as Map;
      expect(decoding['promptEchoRemovedCount'], 2);
      expect(result.lyrics.metadata['segmentCount'], 1);
    });

    test('a result that is nothing but the echo is not a success', () async {
      final fake = _FakeWhisper(
        segments: [_segment('Song: Neon Harbor. Artist: Mira.', 0, 1500)],
      );
      await expectLater(
        service(fake).transcribe(request()),
        throwsA(isA<TranscriptionException>()),
      );
    });

    test('short prompts never remove anything', () {
      final lines = [
        const LyricLine(
          text: 'Blue',
          startTime: Duration.zero,
          endTime: Duration(seconds: 1),
        ),
      ];
      final result = WhisperCppTranscriptionService.removePromptEchoes(
        lines,
        'Blue',
      );
      expect(result.removedCount, 0);
      expect(result.lines, same(lines));
    });

    test('no prompt means no change', () {
      final result = WhisperCppTranscriptionService.removePromptEchoes(
        const [],
        null,
      );
      expect(result.removedCount, 0);
    });
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
  int get pid => 4242;

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
