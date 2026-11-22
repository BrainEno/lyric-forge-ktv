import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_process_supervisor.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/pcm_wav_clip_writer.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/whisper_spoken_language_detector.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/spoken_language.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/vocal_activity.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/whisper_decoding_policy.dart';

/// A 16 kHz mono 16-bit WAV of [seconds]; sample values count up per second
/// so a test can tell which second a byte came from.
Uint8List _wav(int seconds, {int sampleRate = 16000}) {
  final samples = seconds * sampleRate;
  final data = ByteData(44 + samples * 2);
  void tag(int offset, String value) {
    for (var index = 0; index < 4; index++) {
      data.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  tag(0, 'RIFF');
  data.setUint32(4, 36 + samples * 2, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (var index = 0; index < samples; index++) {
    data.setInt16(44 + index * 2, index ~/ sampleRate, Endian.little);
  }
  return data.buffer.asUint8List();
}

/// 20 ms frames: silent for [silentSeconds], then loud.
VocalEnergyEnvelope _envelope(int seconds, int silentSeconds) =>
    VocalEnergyEnvelope(
      frameLength: const Duration(milliseconds: 20),
      frameRms: [
        for (var index = 0; index < seconds * 50; index++)
          index < silentSeconds * 50 ? 0.0001 : 0.3,
      ],
    );

class _Call {
  _Call(this.executable, this.arguments);
  final String executable;
  final List<String> arguments;
}

void main() {
  late Directory root;
  late String modelPath;
  late String audioPath;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('spoken-language-');
    modelPath = '${root.path}/ggml-large-v3.bin';
    await File(modelPath).writeAsBytes([0]);
    audioPath = '${root.path}/riders.wav';
    await File(audioPath).writeAsBytes(_wav(90));
  });
  tearDown(() => root.delete(recursive: true));

  TranscriptionRequest request({
    String? normalized,
    String title = 'Riders on the Storm',
    String artist = 'The Doors',
  }) => TranscriptionRequest(
    inputAudioPath: audioPath,
    normalizedInputAudioPath: normalized,
    outputDirectory: '${root.path}/out',
    config: TranscriptionConfig(
      mode: TranscriptionMode.whisperOnly,
      whisperExecutable: 'whisper-cli',
      modelPath: modelPath,
      ffmpegExecutable: 'ffmpeg',
    ),
    recognitionHints: RecognitionHints(songTitle: title, artist: artist),
  );

  group('parseDetectedLanguage', () {
    test('reads whisper.cpp\'s line', () {
      final probe = WhisperSpokenLanguageDetector.parseDetectedLanguage(
        'whisper_full_with_state: auto-detected language: en (p = 0.981234)',
      );
      expect(probe?.language, 'en');
      expect(probe?.probability, closeTo(0.981234, 1e-9));
      expect(
        WhisperSpokenLanguageDetector.parseDetectedLanguage(
          'auto-detected language: NN (p = 0.5)',
        )?.language,
        'nn',
      );
      expect(
        WhisperSpokenLanguageDetector.parseDetectedLanguage('whisper_init'),
        isNull,
      );
    });
  });

  test('probes the sung part, not the intro, and settles on it', () async {
    final calls = <_Call>[];
    List<int>? heardSeconds;
    final detector = WhisperSpokenLanguageDetector(
      readEnvelope: (path) async => _envelope(90, 40),
      runProcess:
          (
            executable,
            arguments, {
            required timeout,
            required operation,
            onStderrLine,
            onProcessChanged,
          }) async {
            calls.add(_Call(executable, arguments));
            if (executable == 'ffmpeg') {
              await File(audioPath).copy(arguments.last);
            } else {
              final clip = arguments[arguments.indexOf('-f') + 1];
              final bytes = await File(clip).readAsBytes();
              final view = ByteData.sublistView(bytes);
              heardSeconds = {
                for (var at = 44; at < bytes.length; at += 32000)
                  view.getInt16(at, Endian.little),
              }.toList();
              onStderrLine?.call(
                'whisper_full_with_state: auto-detected language: en '
                '(p = 0.962000)',
              );
            }
            return const AsrProcessResult(
              exitCode: 0,
              stdoutTail: [],
              stderrTail: [],
            );
          },
    );

    final resolution = await detector.detect(request());

    expect(resolution.language, 'en');
    expect(resolution.source, SpokenLanguageSource.detected);
    expect(resolution.probes.single.probability, closeTo(0.962, 1e-9));
    expect(resolution.songInfoLanguage, 'en');
    expect(calls.map((call) => call.executable), ['ffmpeg', 'whisper-cli']);
    final whisper = calls.last.arguments;
    expect(whisper, containsAllInOrder(['-m', modelPath]));
    expect(whisper, containsAllInOrder(['-l', 'auto']));
    expect(whisper, contains('--detect-language'));
    // Only the singing after the 40 s intro reached whisper.
    expect(heardSeconds, hasLength(30));
    expect(heardSeconds!.every((second) => second >= 40), isTrue);
    expect(
      resolution.windows.first.start,
      greaterThanOrEqualTo(const Duration(seconds: 40)),
    );
    // The probe files are gone.
    expect(Directory('${root.path}/out/spoken_language').existsSync(), isFalse);
  });

  test('a misdetected first probe is checked with a second one', () async {
    final answers = [
      'auto-detected language: nn (p = 0.70)',
      'auto-detected language: en (p = 0.88)',
    ];
    var whisperCalls = 0;
    final detector = WhisperSpokenLanguageDetector(
      readEnvelope: (path) async => _envelope(90, 0),
      runProcess:
          (
            executable,
            arguments, {
            required timeout,
            required operation,
            onStderrLine,
            onProcessChanged,
          }) async {
            if (executable == 'whisper-cli') {
              onStderrLine?.call(answers[whisperCalls++]);
            }
            return const AsrProcessResult(
              exitCode: 0,
              stdoutTail: [],
              stderrTail: [],
            );
          },
    );

    final resolution = await detector.detect(request(normalized: audioPath));

    expect(whisperCalls, 2);
    expect(resolution.language, 'en');
    expect(resolution.probes.map((probe) => probe.language), ['nn', 'en']);
    expect(resolution.windows, hasLength(6));
  });

  test('an old whisper-cli without --detect-language still answers', () async {
    final whisperArguments = <List<String>>[];
    final detector = WhisperSpokenLanguageDetector(
      readEnvelope: (path) async => _envelope(90, 0),
      runProcess:
          (
            executable,
            arguments, {
            required timeout,
            required operation,
            onStderrLine,
            onProcessChanged,
          }) async {
            whisperArguments.add(arguments);
            if (arguments.contains('--detect-language')) {
              onStderrLine?.call('error: unknown argument: --detect-language');
            } else {
              onStderrLine?.call('auto-detected language: ja (p = 0.91)');
            }
            return const AsrProcessResult(
              exitCode: 0,
              stdoutTail: [],
              stderrTail: [],
            );
          },
    );

    final resolution = await detector.detect(
      request(normalized: audioPath, title: '', artist: ''),
    );

    expect(resolution.language, 'ja');
    expect(whisperArguments, hasLength(2));
    expect(whisperArguments.last, isNot(contains('--detect-language')));
  });

  test('a failing whisper falls back to the song info', () async {
    final detector = WhisperSpokenLanguageDetector(
      readEnvelope: (path) async => _envelope(90, 0),
      runProcess:
          (
            executable,
            arguments, {
            required timeout,
            required operation,
            onStderrLine,
            onProcessChanged,
          }) async => throw const ProcessException('whisper-cli', [], 'gone'),
    );

    final resolution = await detector.detect(request(normalized: audioPath));

    expect(resolution.language, 'en');
    expect(resolution.source, SpokenLanguageSource.songInfo);
    expect(resolution.error, contains('无法启动'));
  });

  test('without a model or singing it stays unresolved', () async {
    final detector = WhisperSpokenLanguageDetector(
      readEnvelope: (path) async => _envelope(90, 90),
      runProcess:
          (
            executable,
            arguments, {
            required timeout,
            required operation,
            onStderrLine,
            onProcessChanged,
          }) async => fail('nothing to run'),
    );

    final silent = await detector.detect(
      request(normalized: audioPath, title: 'Despacito', artist: ''),
    );
    expect(silent.isResolved, isFalse);
    expect(silent.probes, isEmpty);

    await File(modelPath).delete();
    final noModel = await detector.detect(request(normalized: audioPath));
    expect(noModel.source, SpokenLanguageSource.songInfo);
    expect(noModel.error, contains('模型不存在'));
  });

  test('cancelling stops the probe with a cancelled error', () async {
    late final WhisperSpokenLanguageDetector detector;
    detector = WhisperSpokenLanguageDetector(
      readEnvelope: (path) async => _envelope(90, 0),
      runProcess:
          (
            executable,
            arguments, {
            required timeout,
            required operation,
            onStderrLine,
            onProcessChanged,
          }) async {
            await detector.cancel();
            return const AsrProcessResult(
              exitCode: 0,
              stdoutTail: [],
              stderrTail: [],
            );
          },
    );

    await expectLater(
      detector.detect(request(normalized: audioPath)),
      throwsA(
        isA<TranscriptionException>().having(
          (error) => error.kind,
          'kind',
          TranscriptionFailureKind.cancelled,
        ),
      ),
    );
  });

  group('writePcmWavClip', () {
    test('joins the windows into one valid WAV', () async {
      final target = '${root.path}/clip.wav';
      final length = await writePcmWavClip(
        sourcePath: audioPath,
        targetPath: target,
        windows: const [
          SpokenLanguageWindow(Duration(seconds: 2), Duration(seconds: 4)),
          SpokenLanguageWindow(Duration(seconds: 88), Duration(seconds: 95)),
        ],
      );
      expect(length, const Duration(seconds: 4));
      final bytes = await File(target).readAsBytes();
      final view = ByteData.sublistView(bytes);
      expect(String.fromCharCodes(bytes, 0, 4), 'RIFF');
      expect(view.getUint32(4, Endian.little), bytes.length - 8);
      expect(view.getUint32(24, Endian.little), 16000);
      expect(view.getUint32(40, Endian.little), 4 * 32000);
      expect(bytes.length, 44 + 4 * 32000);
      expect(view.getInt16(44, Endian.little), 2);
      expect(view.getInt16(44 + 2 * 32000, Endian.little), 88);
      expect(view.getInt16(bytes.length - 2, Endian.little), 89);
    });

    test('rejects what is not 16-bit PCM', () async {
      final bad = '${root.path}/bad.wav';
      await File(bad).writeAsBytes(List.filled(64, 0));
      await expectLater(
        writePcmWavClip(
          sourcePath: bad,
          targetPath: '${root.path}/out.wav',
          windows: const [
            SpokenLanguageWindow(Duration.zero, Duration(seconds: 1)),
          ],
        ),
        throwsFormatException,
      );
    });
  });
}
