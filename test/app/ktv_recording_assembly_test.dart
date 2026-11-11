import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/app/ktv_recording_assembly.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/ktv_recording_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';

import '../support/ktv_export_fixture.dart';

void main() {
  late KtvExportFixture fixture;
  late MutableSettingsStore settings;
  late CapturingProcessRunner runner;
  late KtvRecordingService service;

  setUp(() async {
    fixture = await KtvExportFixture.create();
    settings = MutableSettingsStore();
    runner = CapturingProcessRunner();
    service = assembleKtvRecordingService(
      audioService: UnusedAudioPlayer(),
      microphoneService: UnusedMicrophone(),
      settingsStore: settings,
      processRunner: runner.run,
    );
  });

  tearDown(() async {
    await service.dispose();
    await fixture.dispose();
  });

  group('app assembly routes shared FFmpeg settings to KTV export', () {
    test('production service registry uses this assembly and shared settings', () {
      final source = File('lib/app/app_services.dart').readAsStringSync();
      expect(source, contains('ktvRecordingService = assembleKtvRecordingService('));
      expect(source, contains('settingsStore: transcriptionSettingsStore'));
      expect(source, isNot(contains('ktvRecordingService = LocalKtvRecordingService(')));
    });

    test('uses selected executable and writes a valid session result', () async {
      settings.value = configWithFfmpeg('  /tools/音频 tools/ffmpeg  ');
      final result = await service.exportMix(fixture.session);
      expect(settings.loads, 1);
      expect(runner.executables, ['/tools/音频 tools/ffmpeg']);
      expect(runner.argumentLists.single, containsAll([fixture.backing.path, fixture.voice.path]));
      expect(result.mixedOutputPath, runner.argumentLists.single.last);
      expect(await File(result.mixedOutputPath!).readAsBytes(), [9, 8, 7]);
      expect((await fixture.readSession()).mixedOutputPath, result.mixedOutputPath);
      expect(service.currentState.isExporting, isFalse);
      expect(service.currentState.lastCompletedSession?.mixedOutputPath, result.mixedOutputPath);
    });

    for (final sample in <String?>[null, '', ' \n\t ']) {
      test('falls back to PATH ffmpeg for ${sample == null ? "missing settings" : "blank [$sample]"}', () async {
        settings.value = sample == null ? null : configWithFfmpeg(sample);
        await service.exportMix(fixture.session);
        expect(runner.executables, ['ffmpeg']);
        expect(settings.loads, 1);
      });
    }

    test('resolves current settings on every export instead of caching them', () async {
      settings.value = configWithFfmpeg('/one/ffmpeg');
      await service.exportMix(fixture.session);
      await settings.save(configWithFfmpeg('/two/ffmpeg'));
      await service.exportMix(fixture.session);
      await settings.clear();
      await service.exportMix(fixture.session);
      expect(runner.executables, ['/one/ffmpeg', '/two/ffmpeg', 'ffmpeg']);
      expect(settings.loads, 3);
    });

    test('settings failure propagates, clears export lock, and allows retry', () async {
      settings.failure = StateError('settings read failed');
      await expectLater(service.exportMix(fixture.session), throwsA(isA<StateError>()));
      expect(runner.executables, isEmpty);
      expect(service.currentState.isExporting, isFalse);
      expect(service.currentState.error, contains('settings read failed'));
      expect((await fixture.readSession()).mixedOutputPath, isNull);
      settings.failure = null;
      settings.value = configWithFfmpeg('/fixed/ffmpeg');
      final retried = await service.exportMix(fixture.session);
      expect(runner.executables, ['/fixed/ffmpeg']);
      expect(retried.mixedOutputPath, isNotNull);
      expect(service.currentState.error, isNull);
    });

    test('export lock is held while settings read is pending', () async {
      final deferred = _DeferredSettingsStore();
      await service.dispose();
      service = assembleKtvRecordingService(
        audioService: UnusedAudioPlayer(), microphoneService: UnusedMicrophone(),
        settingsStore: deferred, processRunner: runner.run,
      );
      final pending = service.exportMix(fixture.session);
      await deferred.started.future;
      expect(service.currentState.isExporting, isTrue);
      await expectLater(service.exportMix(fixture.session), throwsA(isA<KtvRecordingException>()));
      expect(deferred.loads, 1);
      expect(runner.executables, isEmpty);
      deferred.result.complete(configWithFfmpeg('/delayed/ffmpeg'));
      await pending;
      expect(runner.executables, ['/delayed/ffmpeg']);
      expect(service.currentState.isExporting, isFalse);
    });

    test('does not read settings or invoke process for unreliable take', () async {
      final session = fixture.session.copyWith(alignmentReliable: false, alignmentIssue: 'timeline changed');
      await expectLater(service.exportMix(session), throwsA(isA<KtvRecordingException>().having((e) => e.message, 'message', 'timeline changed')));
      expect(settings.loads, 0);
      expect(runner.executables, isEmpty);
      expect(service.currentState.isExporting, isFalse);
    });

    test('does not load settings when voice file is missing', () async {
      await fixture.voice.delete();
      await expectLater(service.exportMix(fixture.session), throwsA(isA<KtvRecordingException>().having((e) => e.message, 'message', contains('人声录音文件不存在'))));
      expect(settings.loads, 0);
      expect(runner.executables, isEmpty);
    });

    test('does not load settings when backing file is missing', () async {
      await fixture.backing.delete();
      await expectLater(service.exportMix(fixture.session), throwsA(isA<KtvRecordingException>().having((e) => e.message, 'message', contains('伴唱音轨文件不存在'))));
      expect(settings.loads, 0);
      expect(runner.executables, isEmpty);
    });
  });
}

class _DeferredSettingsStore extends MutableSettingsStore {
  final started = Completer<void>();
  final result = Completer<TranscriptionConfig?>();

  @override
  Future<TranscriptionConfig?> load() async {
    loads++;
    if (!started.isCompleted) started.complete();
    return result.future;
  }
}
