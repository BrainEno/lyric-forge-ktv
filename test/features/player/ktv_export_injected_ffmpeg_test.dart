import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/local_ktv_recording_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/models/ktv_recording_session.dart';

import '../../support/ktv_export_fixture.dart';

void main() {
  late KtvExportFixture fixture;
  late CapturingProcessRunner runner;
  late LocalKtvRecordingService service;
  var loads = 0;
  String? path;

  setUp(() async {
    fixture = await KtvExportFixture.create();
    runner = CapturingProcessRunner();
    loads = 0;
    path = '/configured/ffmpeg';
    service = LocalKtvRecordingService(
      audioService: UnusedAudioPlayer(),
      microphoneService: UnusedMicrophone(),
      loadFfmpegExecutable: () async {
        loads++;
        return path;
      },
      processRunner: runner.run,
    );
  });

  tearDown(() async {
    await service.dispose();
    await fixture.dispose();
  });

  group('KTV mix export with injected executable', () {
    test(
      'keeps Unicode paths as individual arguments without shell quoting',
      () async {
        await service.exportMix(fixture.session);
        final args = runner.argumentLists.single;
        expect(args.where((arg) => arg == '-i').length, 2);
        final first = args.indexOf('-i');
        expect(args[first + 1], fixture.backing.path);
        expect(args[first + 2], '-i');
        expect(args[first + 3], fixture.voice.path);
        expect(args.last, endsWith('${Platform.pathSeparator}mix.wav'));
        expect(runner.executables, ['/configured/ffmpeg']);
      },
    );

    test('preserves start time, duration and caller-selected volume', () async {
      await service.exportMix(
        fixture.session,
        voiceVolume: 1.25,
        backingVolume: 0.4,
      );
      final args = runner.argumentLists.single;
      final filter = args[args.indexOf('-filter_complex') + 1];
      expect(filter, contains('atrim=start=1.350000:duration=3.450000'));
      expect(filter, contains('atrim=duration=3.450000'));
      expect(filter, contains('volume=0.4000[b]'));
      expect(filter, contains('volume=1.2500[v]'));
      expect(filter, contains('amix=inputs=2:duration=shortest'));
      expect(args[args.indexOf('-c:a') + 1], 'pcm_s16le');
    });

    test('defaults backing volume from the recording session', () async {
      await service.exportMix(fixture.session);
      final args = runner.argumentLists.single;
      final filter = args[args.indexOf('-filter_complex') + 1];
      expect(filter, contains('volume=0.7000[b]'));
      expect(filter, contains('volume=1.0000[v]'));
    });

    test('clamps volume parameters to the supported range', () async {
      await service.exportMix(
        fixture.session,
        voiceVolume: 99,
        backingVolume: -1,
      );
      final args = runner.argumentLists.single;
      final filter = args[args.indexOf('-filter_complex') + 1];
      expect(filter, contains('volume=0.0000[b]'));
      expect(filter, contains('volume=2.0000[v]'));
    });

    test('reports a process launch failure and permits retry', () async {
      runner.failure = ProcessException('/configured/ffmpeg', [], 'not found');
      await expectLater(
        service.exportMix(fixture.session),
        throwsA(
          isA<KtvRecordingException>().having(
            (e) => e.message,
            'message',
            contains('无法启动 FFmpeg'),
          ),
        ),
      );
      expect(service.currentState.isExporting, isFalse);
      expect(service.currentState.error, contains('无法启动 FFmpeg'));
      expect((await fixture.readSession()).mixedOutputPath, isNull);
      runner.failure = null;
      await service.exportMix(fixture.session);
      expect(loads, 2);
      expect(service.currentState.error, isNull);
    });

    test(
      'non-zero exit preserves stderr and does not mark output as exported',
      () async {
        runner.exitCode = 9;
        runner.stderr = 'permission denied by test runner';
        await expectLater(
          service.exportMix(fixture.session),
          throwsA(
            isA<KtvRecordingException>().having(
              (e) => e.message,
              'message',
              contains('permission denied by test runner'),
            ),
          ),
        );
        expect((await fixture.readSession()).mixedOutputPath, isNull);
        expect(service.currentState.isExporting, isFalse);
        expect(loads, 1);
      },
    );

    test('exit zero without output remains a failure', () async {
      runner.createOutput = false;
      await expectLater(
        service.exportMix(fixture.session),
        throwsA(
          isA<KtvRecordingException>().having(
            (e) => e.message,
            'message',
            contains('FFmpeg 混音失败'),
          ),
        ),
      );
      expect((await fixture.readSession()).mixedOutputPath, isNull);
      expect(service.currentState.isExporting, isFalse);
    });

    test('rejects zero duration before asking for executable', () async {
      final invalid = fixture.session.copyWith(duration: Duration.zero);
      await expectLater(
        service.exportMix(invalid),
        throwsA(
          isA<KtvRecordingException>().having(
            (e) => e.message,
            'message',
            contains('录音内容为空'),
          ),
        ),
      );
      expect(loads, 0);
      expect(runner.executables, isEmpty);
    });

    test('settings callback failure leaves manifest untouched', () async {
      await service.dispose();
      final original = await fixture.manifest.readAsString();
      service = LocalKtvRecordingService(
        audioService: UnusedAudioPlayer(),
        microphoneService: UnusedMicrophone(),
        loadFfmpegExecutable: () async => throw StateError('read failed'),
        processRunner: runner.run,
      );
      await expectLater(service.exportMix(fixture.session), throwsStateError);
      expect(await fixture.manifest.readAsString(), original);
      expect(runner.executables, isEmpty);
      expect(service.currentState.error, contains('read failed'));
      expect(service.currentState.isExporting, isFalse);
    });

    test('preserves name and favorite changed while process runs', () async {
      await service.dispose();
      final started = Completer<List<String>>();
      final gate = Completer<ProcessResult>();
      service = LocalKtvRecordingService(
        audioService: UnusedAudioPlayer(),
        microphoneService: UnusedMicrophone(),
        loadFfmpegExecutable: () async => path,
        processRunner: (executable, args) {
          started.complete(args);
          return gate.future;
        },
      );
      final pending = service.exportMix(fixture.session);
      final args = await started.future;
      await fixture.writeSession(
        fixture.session.copyWith(displayName: '新名称', isFavorite: true),
      );
      await File(args.last).writeAsBytes([7]);
      gate.complete(ProcessResult(1, 0, '', ''));
      final result = await pending;
      expect(result.displayName, '新名称');
      expect(result.isFavorite, isTrue);
      expect((await fixture.readSession()).displayName, '新名称');
      expect((await fixture.readSession()).isFavorite, isTrue);
    });

    test('does not overwrite a changed manifest identity', () async {
      await service.dispose();
      final started = Completer<List<String>>();
      final gate = Completer<ProcessResult>();
      service = LocalKtvRecordingService(
        audioService: UnusedAudioPlayer(),
        microphoneService: UnusedMicrophone(),
        loadFfmpegExecutable: () async => path,
        processRunner: (executable, args) {
          started.complete(args);
          return gate.future;
        },
      );
      final pending = service.exportMix(fixture.session);
      final args = await started.future;
      final changed = fixture.session.toJson()..['id'] = 'other-take';
      await fixture.manifest.writeAsString(jsonEncode(changed));
      await File(args.last).writeAsBytes([7]);
      gate.complete(ProcessResult(1, 0, '', ''));
      await expectLater(
        pending,
        throwsA(
          isA<KtvRecordingException>().having(
            (e) => e.message,
            'message',
            contains('身份变化'),
          ),
        ),
      );
      expect(
        (jsonDecode(await fixture.manifest.readAsString()) as Map)['id'],
        'other-take',
      );
      expect(service.currentState.isExporting, isFalse);
    });

    test('does not recreate a manifest deleted during export', () async {
      await service.dispose();
      final started = Completer<List<String>>();
      final gate = Completer<ProcessResult>();
      service = LocalKtvRecordingService(
        audioService: UnusedAudioPlayer(),
        microphoneService: UnusedMicrophone(),
        loadFfmpegExecutable: () async => path,
        processRunner: (executable, args) {
          started.complete(args);
          return gate.future;
        },
      );
      final pending = service.exportMix(fixture.session);
      final args = await started.future;
      await fixture.manifest.delete();
      await File(args.last).writeAsBytes([7]);
      gate.complete(ProcessResult(1, 0, '', ''));
      await expectLater(
        pending,
        throwsA(
          isA<KtvRecordingException>().having(
            (e) => e.message,
            'message',
            contains('移动或删除'),
          ),
        ),
      );
      expect(await fixture.manifest.exists(), isFalse);
      expect(service.currentState.isExporting, isFalse);
    });

    test('emits exporting and completed states in order', () async {
      final states = <KtvRecordingState>[];
      final subscription = service.stateStream.listen(states.add);
      await service.exportMix(fixture.session);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(states.map((state) => state.isExporting), [true, false]);
      expect(states.last.lastCompletedSession?.mixedOutputPath, isNotNull);
      expect(states.last.error, isNull);
    });
  });
}
