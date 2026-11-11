import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/project/domain/models/lyric_document.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/asr_process_supervisor.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/resumable_chunked_transcription_service.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/transcription_models.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/models/fusion_timing_evidence.dart';
import 'package:lyric_forge_ktv/features/transcription/domain/services/transcription_service.dart';

void main() {
  group('ResumableChunkedTranscriptionService', () {
    test(
      'short audio delegates without chunking after a bounded probe',
      () async {
        final directory = await Directory.systemTemp.createTemp('chunk-short-');
        addTearDown(() => directory.delete(recursive: true));
        final input = File(
          '${directory.path}${Platform.pathSeparator}song.wav',
        );
        await input.writeAsBytes(List<int>.filled(128, 0));
        final delegate = _FakeService();
        final process = _FakeProcess();
        final service = ResumableChunkedTranscriptionService(
          delegate: delegate,
          processSupervisor: AsrProcessSupervisor(
            startProcess: (_, arguments) async {
              expect(arguments, contains('-t'));
              Timer(const Duration(milliseconds: 1), () {
                process.emitStderr(
                  'Duration: 00:01:00.000, start: 0.000000, bitrate: 1 kb/s',
                );
                process.finish(0);
              });
              return process;
            },
          ),
        );

        final events = <TranscriptionProgress>[];
        final subscription = service.progressStream.listen(events.add);
        final result = await service.transcribe(
          _request(input.path, directory.path),
        );
        await Future<void>.delayed(Duration.zero);

        expect(result.detectedLanguage, 'en');
        expect(delegate.calls, 1);
        expect(
          events.where((e) => e.stage == TranscriptionStage.completed),
          hasLength(1),
        );
        expect(events.last.stage, TranscriptionStage.completed);
        await subscription.cancel();
        await service.dispose();
      },
    );

    for (final shortAudio in [true, false]) {
      test('only wrapper reports completion (short: $shortAudio)', () async {
        final directory = await Directory.systemTemp.createTemp(
          'chunk-terminal-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final input = File('${directory.path}/song.wav');
        await input.writeAsBytes(List<int>.filled(128, 1));
        final started = Completer<void>();
        final release = Completer<void>();
        final delegate = _AsyncService((request, service) async {
          service.emit(
            const TranscriptionProgress(
              stage: TranscriptionStage.completed,
              progress: 1,
              message: 'child completed',
            ),
          );
          await Future<void>.delayed(Duration.zero);
          if (shortAudio || service.calls == 2) {
            started.complete();
            await release.future;
          }
          return _emptyResult(request);
        });
        final service = ResumableChunkedTranscriptionService(
          delegate: delegate,
          chunkDuration: const Duration(seconds: 3),
          overlap: const Duration(seconds: 1),
          processSupervisor: _FfmpegStub(
            durationLabel: shortAudio ? '00:00:02.000' : '00:00:04.000',
          ).supervisor,
        );
        addTearDown(service.dispose);
        final events = <TranscriptionProgress>[];
        final subscription = service.progressStream.listen(events.add);
        addTearDown(subscription.cancel);
        final run = service.transcribe(_request(input.path, directory.path));
        await started.future.timeout(const Duration(seconds: 2));
        expect(
          events.where((e) => e.stage == TranscriptionStage.completed),
          isEmpty,
        );
        release.complete();
        await run;
        await Future<void>.delayed(Duration.zero);
        expect(
          events.where((e) => e.stage == TranscriptionStage.completed),
          hasLength(1),
        );
        expect(events.last.stage, TranscriptionStage.completed);
        expect(events.last.progress, 1);
      });
    }

    test(
      'a failed chunk attempt cannot report final failure when retry succeeds',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'chunk-retry-terminal-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final input = File('${directory.path}/song.wav');
        await input.writeAsBytes(List<int>.filled(128, 1));
        final delegate = _AsyncService((request, service) async {
          if (service.calls == 1) {
            service.emit(
              const TranscriptionProgress(
                stage: TranscriptionStage.failed,
                progress: 0,
                message: 'attempt failed',
              ),
            );
            await Future<void>.delayed(Duration.zero);
            throw const TranscriptionException('transient');
          }
          return _emptyResult(request);
        });
        final service = ResumableChunkedTranscriptionService(
          delegate: delegate,
          chunkDuration: const Duration(seconds: 3),
          overlap: const Duration(seconds: 1),
          processSupervisor: _FfmpegStub(
            durationLabel: '00:00:04.000',
          ).supervisor,
        );
        addTearDown(service.dispose);
        final events = <TranscriptionProgress>[];
        final subscription = service.progressStream.listen(events.add);
        addTearDown(subscription.cancel);
        await service.transcribe(_request(input.path, directory.path));
        await Future<void>.delayed(Duration.zero);
        expect(delegate.calls, 3);
        expect(
          events.where((e) => e.stage == TranscriptionStage.failed),
          isEmpty,
        );
        expect(
          events.where((e) => e.stage == TranscriptionStage.completed),
          hasLength(1),
        );
        expect(events.last.stage, TranscriptionStage.completed);
      },
    );

    for (final shortAudio in [true, false]) {
      test(
        'final child failure is emitted once (short: $shortAudio)',
        () async {
          final directory = await Directory.systemTemp.createTemp(
            'chunk-failure-terminal-',
          );
          addTearDown(() => directory.delete(recursive: true));
          final input = File('${directory.path}/song.wav');
          await input.writeAsBytes(List<int>.filled(128, 1));
          const failure = TranscriptionException.environment('engine broken');
          final delegate = _AsyncService((request, service) async {
            service.emit(
              const TranscriptionProgress(
                stage: TranscriptionStage.failed,
                progress: 0,
                message: 'child failed',
              ),
            );
            await Future<void>.delayed(Duration.zero);
            throw failure;
          });
          final service = ResumableChunkedTranscriptionService(
            delegate: delegate,
            chunkDuration: const Duration(seconds: 3),
            overlap: const Duration(seconds: 1),
            processSupervisor: _FfmpegStub(
              durationLabel: shortAudio ? '00:00:02.000' : '00:00:04.000',
            ).supervisor,
          );
          addTearDown(service.dispose);
          final events = <TranscriptionProgress>[];
          final subscription = service.progressStream.listen(events.add);
          addTearDown(subscription.cancel);
          await expectLater(
            service.transcribe(_request(input.path, directory.path)),
            throwsA(same(failure)),
          );
          await Future<void>.delayed(Duration.zero);
          expect(
            events.where((e) => e.stage == TranscriptionStage.failed),
            hasLength(1),
          );
          expect(
            events.where((e) => e.stage == TranscriptionStage.completed),
            isEmpty,
          );
          expect(events.last.stage, TranscriptionStage.failed);
        },
      );
    }

    test('checkpoint write failure reports failure, not completion', () async {
      final directory = await Directory.systemTemp.createTemp(
        'chunk-checkpoint-error-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final input = File('${directory.path}/song.wav');
      await input.writeAsBytes(List<int>.filled(128, 1));
      final delegate = _AsyncService((request, service) async {
        final blocked = Directory(
          '${directory.path}/chunk_session/chunks/chunk_0000.json',
        );
        await blocked.create();
        return _emptyResult(request);
      });
      final service = ResumableChunkedTranscriptionService(
        delegate: delegate,
        chunkDuration: const Duration(seconds: 3),
        overlap: const Duration(seconds: 1),
        processSupervisor: _FfmpegStub(
          durationLabel: '00:00:04.000',
        ).supervisor,
      );
      addTearDown(service.dispose);
      final events = <TranscriptionProgress>[];
      final subscription = service.progressStream.listen(events.add);
      addTearDown(subscription.cancel);
      await expectLater(
        service.transcribe(_request(input.path, directory.path)),
        throwsA(isA<FileSystemException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events.last.stage, TranscriptionStage.failed);
      expect(
        events.where(
          (e) =>
              e.stage == TranscriptionStage.completed ||
              e.stage == TranscriptionStage.cancelled,
        ),
        isEmpty,
      );
    });

    test(
      'delegate cancellation preserves checkpoint and resumes without retry',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'chunk-delegate-cancel-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final input = File(
          '${directory.path}${Platform.pathSeparator}song.wav',
        );
        await input.writeAsBytes(List<int>.filled(256, 7));
        var cancel = true;
        final delegate = _ScriptedService((index) {
          if (index == 1 && cancel) {
            throw const TranscriptionException.cancelled('stopped by caller');
          }
          return LyricDocument(language: 'en', lines: []);
        });
        final ffmpeg = _FfmpegStub(durationLabel: '00:00:04.000');
        final service = ResumableChunkedTranscriptionService(
          delegate: delegate,
          chunkDuration: const Duration(seconds: 3),
          overlap: const Duration(seconds: 1),
          maxAttempts: 3,
          processSupervisor: ffmpeg.supervisor,
        );
        addTearDown(service.dispose);
        final request = _request(input.path, directory.path);
        await expectLater(
          service.transcribe(request),
          throwsA(
            isA<TranscriptionException>()
                .having(
                  (e) => e.kind,
                  'kind',
                  TranscriptionFailureKind.cancelled,
                )
                .having(
                  (e) => e.message,
                  'original message',
                  'stopped by caller',
                ),
          ),
        );
        expect(delegate.outputDirectories, hasLength(2));
        final session = Directory(
          '${directory.path}${Platform.pathSeparator}chunk_session',
        );
        final checkpoint = File(
          '${session.path}${Platform.pathSeparator}chunks${Platform.pathSeparator}chunk_0000.json',
        );
        final before = await checkpoint.readAsString();
        final manifest =
            jsonDecode(
                  await File(
                    '${session.path}${Platform.pathSeparator}session.json',
                  ).readAsString(),
                )
                as Map<String, dynamic>;
        expect(manifest['completed'], ['chunk_0000']);
        cancel = false;
        await service.transcribe(request);
        expect(delegate.outputDirectories, hasLength(3));
        expect(await checkpoint.readAsString(), before);
      },
    );

    for (final shortAudio in [true, false]) {
      for (final childEmitsCancellation in [true, false]) {
        test(
          'delegate cancellation emits one wrapper event '
          '(short: $shortAudio, child event: $childEmitsCancellation)',
          () async {
            final directory = await Directory.systemTemp.createTemp(
              'chunk-events-',
            );
            addTearDown(() => directory.delete(recursive: true));
            final input = File(
              '${directory.path}${Platform.pathSeparator}song.wav',
            );
            await input.writeAsBytes(List<int>.filled(128, 0));
            const cancellation = TranscriptionException.cancelled(
              'delegate stopped',
              details: 'original detail',
            );
            final delegate = _AsyncService((_, service) async {
              if (childEmitsCancellation) {
                service.emit(
                  const TranscriptionProgress(
                    stage: TranscriptionStage.cancelled,
                    progress: 0,
                    message: 'child cancelled',
                  ),
                );
                // Allow the wrapper to receive the child event before the throw.
                await Future<void>.delayed(Duration.zero);
              }
              throw cancellation;
            });
            final service = ResumableChunkedTranscriptionService(
              delegate: delegate,
              chunkDuration: const Duration(seconds: 3),
              overlap: const Duration(seconds: 1),
              processSupervisor: _FfmpegStub(
                durationLabel: shortAudio ? '00:00:02.000' : '00:00:04.000',
              ).supervisor,
            );
            addTearDown(service.dispose);
            final events = <TranscriptionProgress>[];
            final subscription = service.progressStream.listen(events.add);
            addTearDown(subscription.cancel);

            await expectLater(
              service.transcribe(_request(input.path, directory.path)),
              throwsA(same(cancellation)),
            );
            await Future<void>.delayed(Duration.zero);
            expect(delegate.calls, 1);
            final cancelled = events
                .where((e) => e.stage == TranscriptionStage.cancelled)
                .toList();
            expect(cancelled, hasLength(1));
            expect(events.last, same(cancelled.single));
            expect(
              cancelled.single.message,
              shortAudio ? '歌词识别已取消' : '分片识别已取消，已完成进度已保存',
            );
          },
        );
      }
    }

    for (final shortAudio in [true, false]) {
      for (final failAfterCancel in [true, false]) {
        test(
          'child terminal then cancellation wins (short: $shortAudio, fail: $failAfterCancel)',
          () async {
            final directory = await Directory.systemTemp.createTemp(
              'chunk-cancel-terminal-',
            );
            addTearDown(() => directory.delete(recursive: true));
            final input = File('${directory.path}/song.wav');
            await input.writeAsBytes(List<int>.filled(128, 1));
            final started = Completer<void>();
            final release = Completer<void>();
            final delegate = _AsyncService((request, service) async {
              service.emit(
                const TranscriptionProgress(
                  stage: TranscriptionStage.completed,
                  progress: 1,
                  message: 'child completed',
                ),
              );
              await Future<void>.delayed(Duration.zero);
              started.complete();
              await release.future;
              if (failAfterCancel)
                throw const TranscriptionException.environment('late failure');
              return _emptyResult(request);
            });
            final service = ResumableChunkedTranscriptionService(
              delegate: delegate,
              chunkDuration: const Duration(seconds: 3),
              overlap: const Duration(seconds: 1),
              processSupervisor: _FfmpegStub(
                durationLabel: shortAudio ? '00:00:02.000' : '00:00:04.000',
              ).supervisor,
            );
            addTearDown(service.dispose);
            final events = <TranscriptionProgress>[];
            final subscription = service.progressStream.listen(events.add);
            addTearDown(subscription.cancel);
            final run = service.transcribe(
              _request(input.path, directory.path),
            );
            final assertion = expectLater(
              run,
              throwsA(
                isA<TranscriptionException>().having(
                  (e) => e.kind,
                  'kind',
                  TranscriptionFailureKind.cancelled,
                ),
              ),
            );
            await started.future.timeout(const Duration(seconds: 2));
            await service.cancel();
            release.complete();
            await assertion;
            await Future<void>.delayed(Duration.zero);
            expect(
              events.where((e) => e.stage == TranscriptionStage.cancelled),
              hasLength(1),
            );
            expect(
              events.where(
                (e) =>
                    e.stage == TranscriptionStage.completed ||
                    e.stage == TranscriptionStage.failed,
              ),
              isEmpty,
            );
            expect(events.last.stage, TranscriptionStage.cancelled);
          },
        );
      }
    }

    test(
      'cancelling during merge reports cancellation instead of completion',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'chunk-cancel-merge-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final input = File('${directory.path}/song.wav');
        await input.writeAsBytes(List<int>.filled(128, 1));
        final service = ResumableChunkedTranscriptionService(
          delegate: _FakeService(),
          chunkDuration: const Duration(seconds: 3),
          overlap: const Duration(seconds: 1),
          processSupervisor: _FfmpegStub(
            durationLabel: '00:00:04.000',
          ).supervisor,
        );
        addTearDown(service.dispose);
        final events = <TranscriptionProgress>[];
        final subscription = service.progressStream.listen((event) {
          events.add(event);
          if (event.stage == TranscriptionStage.parsing &&
              event.message.contains('合并'))
            unawaited(service.cancel());
        });
        addTearDown(subscription.cancel);
        await expectLater(
          service.transcribe(_request(input.path, directory.path)),
          throwsA(
            isA<TranscriptionException>().having(
              (e) => e.kind,
              'kind',
              TranscriptionFailureKind.cancelled,
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          events.where((e) => e.stage == TranscriptionStage.completed),
          isEmpty,
        );
        expect(events.last.stage, TranscriptionStage.cancelled);
      },
    );

    test(
      'cancel before delegate returns does not checkpoint its late result',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'chunk-late-result-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final input = File(
          '${directory.path}${Platform.pathSeparator}song.wav',
        );
        await input.writeAsBytes(List<int>.filled(128, 0));
        final secondStarted = Completer<void>();
        final releaseSecond = Completer<void>();
        final delegate = _AsyncService((request, service) async {
          if (service.calls == 2) {
            secondStarted.complete();
            await releaseSecond.future;
          }
          return _emptyResult(request);
        });
        final service = ResumableChunkedTranscriptionService(
          delegate: delegate,
          chunkDuration: const Duration(seconds: 3),
          overlap: const Duration(seconds: 1),
          processSupervisor: _FfmpegStub(
            durationLabel: '00:00:04.000',
          ).supervisor,
        );
        addTearDown(service.dispose);
        final events = <TranscriptionProgress>[];
        final subscription = service.progressStream.listen(events.add);
        addTearDown(subscription.cancel);
        final request = _request(input.path, directory.path);
        final run = service.transcribe(request);
        // Attach an error listener before cancellation can complete the future.
        final cancelled = expectLater(
          run,
          throwsA(
            isA<TranscriptionException>().having(
              (e) => e.kind,
              'kind',
              TranscriptionFailureKind.cancelled,
            ),
          ),
        );
        await secondStarted.future.timeout(const Duration(seconds: 2));
        await service.cancel();
        releaseSecond.complete();
        await cancelled;
        await Future<void>.delayed(Duration.zero);

        final session = Directory(
          '${directory.path}${Platform.pathSeparator}chunk_session',
        );
        final first = File(
          '${session.path}${Platform.pathSeparator}chunks${Platform.pathSeparator}chunk_0000.json',
        );
        final second = File(
          '${session.path}${Platform.pathSeparator}chunks${Platform.pathSeparator}chunk_0001.json',
        );
        final before = await first.readAsString();
        expect(await second.exists(), isFalse);
        final manifest =
            jsonDecode(
                  await File(
                    '${session.path}${Platform.pathSeparator}session.json',
                  ).readAsString(),
                )
                as Map<String, dynamic>;
        expect(manifest['completed'], ['chunk_0000']);
        expect(
          events.where((e) => e.stage == TranscriptionStage.cancelled),
          hasLength(1),
        );
        expect(events.last.stage, TranscriptionStage.cancelled);

        await service.transcribe(request);
        expect(delegate.calls, 3);
        expect(await first.readAsString(), before);
        expect(await second.exists(), isTrue);
      },
    );

    test('constructor accepts retry and overlap policy', () async {
      final delegate = _FakeService();
      final service = ResumableChunkedTranscriptionService(
        delegate: delegate,
        chunkDuration: const Duration(minutes: 2),
        overlap: const Duration(seconds: 6),
        maxAttempts: 2,
      );
      expect(service.isRunning, isFalse);
      await service.dispose();
    });

    test('duration probe timeout is a blocking environment failure', () async {
      final directory = await Directory.systemTemp.createTemp('chunk-timeout-');
      addTearDown(() => directory.delete(recursive: true));
      final input = File('${directory.path}${Platform.pathSeparator}song.wav');
      await input.writeAsBytes(List<int>.filled(128, 0));
      final process = _FakeProcess();
      final service = ResumableChunkedTranscriptionService(
        delegate: _FakeService(),
        durationProbeTimeout: const Duration(milliseconds: 20),
        processSupervisor: AsrProcessSupervisor(
          startProcess: (_, __) async => process,
          terminationGrace: const Duration(milliseconds: 5),
          streamDrainGrace: const Duration(milliseconds: 5),
        ),
      );

      await expectLater(
        service.transcribe(_request(input.path, directory.path)),
        throwsA(
          isA<TranscriptionException>()
              .having(
                (error) => error.kind,
                'failure kind',
                TranscriptionFailureKind.environment,
              )
              .having((error) => error.message, 'message', contains('超时')),
        ),
      );

      expect(process.killSignals, contains(ProcessSignal.sigterm));
      await service.dispose();
    });

    test(
      'cancelling a stuck duration probe escalates and stays typed',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'chunk-cancel-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final input = File(
          '${directory.path}${Platform.pathSeparator}song.wav',
        );
        await input.writeAsBytes(List<int>.filled(128, 0));
        final process = _FakeProcess(killOnSigterm: false, killOnSigkill: true);
        final started = Completer<void>();
        final service = ResumableChunkedTranscriptionService(
          delegate: _FakeService(),
          durationProbeTimeout: const Duration(minutes: 1),
          processSupervisor: AsrProcessSupervisor(
            startProcess: (_, __) async {
              if (!started.isCompleted) started.complete();
              return process;
            },
            terminationGrace: const Duration(milliseconds: 10),
            streamDrainGrace: const Duration(milliseconds: 10),
          ),
        );
        final running = service.transcribe(
          _request(input.path, directory.path),
        );
        await started.future.timeout(const Duration(seconds: 1));
        await Future<void>.delayed(const Duration(milliseconds: 5));

        await service.cancel();

        await expectLater(
          running,
          throwsA(
            isA<TranscriptionException>().having(
              (error) => error.kind,
              'failure kind',
              TranscriptionFailureKind.cancelled,
            ),
          ),
        );
        expect(process.killSignals, contains(ProcessSignal.sigterm));
        expect(process.killSignals, contains(ProcessSignal.sigkill));
        await service.dispose();
      },
    );

    test(
      'failed chunk extraction removes partial WAV but preserves completed checkpoints',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'chunk-checkpoint-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final input = File(
          '${directory.path}${Platform.pathSeparator}song.wav',
        );
        await input.writeAsBytes(List<int>.filled(256, 7));
        final stat = await input.stat();
        final fingerprint =
            '${stat.size}:${stat.modified.toUtc().millisecondsSinceEpoch}:${input.absolute.path}';
        final chunksDir = Directory(
          '${directory.path}${Platform.pathSeparator}chunk_session'
          '${Platform.pathSeparator}chunks',
        );
        await chunksDir.create(recursive: true);
        final manifestFile = File(
          '${directory.path}${Platform.pathSeparator}chunk_session'
          '${Platform.pathSeparator}session.json',
        );
        await manifestFile.writeAsString(
          jsonEncode({
            'version':
                ResumableChunkedTranscriptionService.checkpointManifestVersion,
            'fallbackEvidenceVersion': 1,
            'sourceFingerprint': fingerprint,
            'configFingerprint':
                ResumableChunkedTranscriptionService.checkpointConfigFingerprint(
                  _config(),
                ),
            'chunkMs': const Duration(minutes: 3).inMilliseconds,
            'overlapMs': const Duration(seconds: 8).inMilliseconds,
            'durationMs': const Duration(minutes: 4).inMilliseconds,
            'completed': ['chunk_0000'],
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          }),
        );
        final completedCheckpoint = File(
          '${chunksDir.path}${Platform.pathSeparator}chunk_0000.json',
        );
        await completedCheckpoint.writeAsString('{}');

        final supervisor = AsrProcessSupervisor(
          startProcess: (_, arguments) async {
            final process = _FakeProcess();
            if (arguments.contains('-ss')) {
              await File(arguments.last).writeAsBytes(List<int>.filled(128, 0));
              Timer(const Duration(milliseconds: 1), () => process.finish(23));
            } else {
              Timer(const Duration(milliseconds: 1), () {
                process.emitStderr(
                  'Duration: 00:04:00.000, start: 0.000000, bitrate: 1 kb/s',
                );
                process.finish(0);
              });
            }
            return process;
          },
          streamDrainGrace: const Duration(milliseconds: 10),
        );
        final service = ResumableChunkedTranscriptionService(
          delegate: _FakeService(),
          chunkDuration: const Duration(minutes: 3),
          processSupervisor: supervisor,
        );

        await expectLater(
          service.transcribe(_request(input.path, directory.path)),
          throwsA(
            isA<TranscriptionException>().having(
              (error) => error.kind,
              'failure kind',
              TranscriptionFailureKind.input,
            ),
          ),
        );

        expect(await completedCheckpoint.exists(), isTrue);
        expect(jsonDecode(await manifestFile.readAsString())['completed'], [
          'chunk_0000',
        ]);
        expect(
          await File(
            '${chunksDir.path}${Platform.pathSeparator}chunk_0001.wav',
          ).exists(),
          isFalse,
        );
        await service.dispose();
      },
    );

    test('a five-minute song is recognised in one pass', () async {
      expect(
        ResumableChunkedTranscriptionService.defaultChunkDuration,
        const Duration(minutes: 20),
      );
      final directory = await Directory.systemTemp.createTemp('chunk-song-');
      addTearDown(() => directory.delete(recursive: true));
      final input = File('${directory.path}${Platform.pathSeparator}song.wav');
      await input.writeAsBytes(List<int>.filled(128, 0));
      final delegate = _FakeService();
      final ffmpeg = _FfmpegStub(durationLabel: '00:05:00.000');
      final service = ResumableChunkedTranscriptionService(
        delegate: delegate,
        processSupervisor: ffmpeg.supervisor,
      );

      final result = await service.transcribe(
        _request(input.path, directory.path),
      );

      expect(delegate.calls, 1);
      expect(ffmpeg.chunkStartRequests, 0);
      expect(
        Directory(
          '${directory.path}${Platform.pathSeparator}chunk_session',
        ).existsSync(),
        isFalse,
      );
      expect(result.lyrics.metadata['chunked'], isNull);
      await service.dispose();
    });

    test(
      'chunk merge retains more than the highlight limit of candidates',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'chunk-many-candidates-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final input = File(
          '${directory.path}${Platform.pathSeparator}song.wav',
        );
        await input.writeAsBytes(List<int>.filled(128, 0));
        final ffmpeg = _FfmpegStub(durationLabel: '00:04:00.000');
        final delegate = _ScriptedService(
          (chunk) => LyricDocument(
            language: 'en',
            lines: [
              for (var i = 0; i < 15; i++)
                LyricLine(
                  text: 'chunk $chunk lyric $i',
                  startTime: Duration(seconds: i * 3),
                  endTime: Duration(seconds: i * 3 + 2),
                ),
            ],
            metadata: {
              if (chunk > 0) 'fallbackHighlightLimit': 8,
              'fallbackCandidates': [
                for (var i = 0; i < 15; i++)
                  {
                    'lineIndex': i,
                    'primaryText': 'chunk $chunk lyric $i',
                    'alternativeText': 'other $chunk $i',
                  },
              ],
              'fallbackAppliedCount': 0,
            },
          ),
        );
        final service = ResumableChunkedTranscriptionService(
          delegate: delegate,
          chunkDuration: const Duration(minutes: 3),
          processSupervisor: ffmpeg.supervisor,
        );
        addTearDown(service.dispose);
        final result = await service.transcribe(
          _request(input.path, directory.path),
        );
        final metadata = result.lyrics.metadata;
        expect(metadata['fallbackHighlightLimit'], 8);
        expect(metadata['fallbackCandidateCount'], 30);
        final candidates = metadata['fallbackCandidates'] as List;
        expect(
          candidates.map((c) => (c as Map)['lineIndex']).toSet(),
          Set<int>.from(List.generate(30, (i) => i)),
        );
      },
    );

    test(
      'chunk evidence follows the winning row and restored checkpoints; legacy rows remain unknown',
      () async {
        for (final legacyWinner in [false, true]) {
          final directory = await Directory.systemTemp.createTemp(
            'chunk-timing-evidence-',
          );
          addTearDown(() => directory.delete(recursive: true));
          final input = File('${directory.path}/song.wav');
          await input.writeAsBytes(List<int>.filled(128, 1));
          final delegate = _ScriptedService((chunk) {
            final line = chunk == 0
                ? const LyricLine(
                    text: 'hold on!',
                    startTime: Duration(milliseconds: 2100),
                    endTime: Duration(milliseconds: 2500),
                    confidence: 60,
                  )
                : const LyricLine(
                    text: 'hold on',
                    startTime: Duration(milliseconds: 100),
                    endTime: Duration(milliseconds: 500),
                    confidence: 90,
                  );
            return LyricDocument(
              language: 'en',
              lines: [line],
              metadata: {
                if (chunk == 0 || !legacyWinner)
                  FusionTimingEvidence.metadataKey: FusionTimingEvidence.wrap([
                    FusionTimingEvidence.entry(
                      lineIndex: 0,
                      result: line,
                      timedText: chunk == 0 ? line.text : 'different original',
                      secondaryOnly: false,
                    ),
                  ]),
              },
            );
          });
          final service = ResumableChunkedTranscriptionService(
            delegate: delegate,
            chunkDuration: const Duration(seconds: 3),
            overlap: const Duration(seconds: 1),
            processSupervisor: _FfmpegStub(
              durationLabel: '00:00:04.000',
            ).supervisor,
          );
          addTearDown(service.dispose);
          final request = _request(input.path, directory.path);
          final result = await service.transcribe(request);
          expect(result.lyrics.lines.single.text, 'hold on');
          expect(
            result.lyrics.lines.single.startTime,
            const Duration(milliseconds: 2100),
          );
          final evidence = FusionTimingEvidence.forLine(result.lyrics, 0);
          if (legacyWinner) {
            expect(evidence, isNull);
            expect(
              result.lyrics.metadata.containsKey(
                FusionTimingEvidence.metadataKey,
              ),
              isFalse,
            );
          } else {
            expect(
              evidence!['timedTextHash'],
              FusionTimingEvidence.textHash('different original'),
            );
            expect(evidence['needsRealignment'], isTrue);
            expect(evidence['startMs'], 2100);
            expect(evidence['endMs'], 2500);
          }
          final resumed = await service.transcribe(request);
          expect(FusionTimingEvidence.forLine(resumed.lyrics, 0), evidence);
          expect(delegate.outputDirectories, hasLength(2));
        }
      },
    );

    test(
      'chunk overlap preserves the complete shared-segment review candidate',
      () async {
        for (final firstShared in [false, true]) {
          for (final secondShared in [false, true]) {
            final directory = await Directory.systemTemp.createTemp(
              'chunk-shared-review-',
            );
            addTearDown(() => directory.delete(recursive: true));
            final input = File('${directory.path}/song.wav');
            await input.writeAsBytes(List<int>.filled(128, 1));
            final originalSegments = <List<dynamic>>[];
            final delegate = _ScriptedService((chunk) {
              final shared = chunk == 0 ? firstShared : secondShared;
              final segments = <dynamic>[
                {
                  'sourceIndex': 7,
                  'text': chunk == 0 ? 'first evidence' : 'second evidence',
                  'startMs': chunk == 0 ? 2100 : 100,
                  'endMs': chunk == 0 ? 2900 : 900,
                },
                'unrecognized legacy entry',
              ];
              originalSegments.add(segments);
              return LyricDocument(
                language: 'en',
                lines: chunk == 0
                    ? const [
                        LyricLine(
                          text: 'before',
                          startTime: Duration.zero,
                          endTime: Duration(milliseconds: 400),
                        ),
                        LyricLine(
                          text: 'hold on',
                          startTime: Duration(milliseconds: 2100),
                          endTime: Duration(milliseconds: 2500),
                          confidence: 60,
                        ),
                      ]
                    : const [
                        LyricLine(
                          text: 'hold on',
                          startTime: Duration(milliseconds: 100),
                          endTime: Duration(milliseconds: 500),
                          confidence: 90,
                        ),
                        LyricLine(
                          text: 'later',
                          startTime: Duration(milliseconds: 1100),
                          endTime: Duration(milliseconds: 1500),
                        ),
                      ],
                metadata: {
                  'fallbackCandidates': [
                    {
                      'lineIndex': chunk == 0 ? 1 : 0,
                      'primaryText': 'hold on',
                      'alternativeText': chunk == 0
                          ? 'first evidence'
                          : 'second evidence',
                      'startMs': chunk == 0 ? 2100 : 100,
                      'endMs': chunk == 0 ? 2500 : 500,
                      'secondarySegments': segments,
                      if (shared) 'sharedSecondaryAcrossPrimaryLines': true,
                      'reason': shared
                          ? 'shared_secondary_spans_multiple_primary_lines'
                          : 'engine_disagreement_review',
                    },
                    if (chunk == 1)
                      {'lineIndex': 1, 'alternativeText': 'independent'},
                  ],
                },
              );
            });
            final service = ResumableChunkedTranscriptionService(
              delegate: delegate,
              chunkDuration: const Duration(seconds: 3),
              overlap: const Duration(seconds: 1),
              processSupervisor: _FfmpegStub(
                durationLabel: '00:00:04.000',
              ).supervisor,
            );
            addTearDown(service.dispose);
            final request = _request(input.path, directory.path);
            final result = await service.transcribe(request);
            expect(result.lyrics.lines.map((line) => line.text), [
              'before',
              'hold on',
              'later',
            ]);
            expect(result.lyrics.lines[1].confidence, 90);
            expect(result.lyrics.metadata['fallbackCandidateCount'], 2);
            final candidates =
                result.lyrics.metadata['fallbackCandidates'] as List;
            final overlap =
                candidates.singleWhere((entry) => entry['lineIndex'] == 1)
                    as Map;
            final expectedSecond = !firstShared && secondShared;
            expect(
              overlap['alternativeText'],
              expectedSecond ? 'second evidence' : 'first evidence',
            );
            expect(
              overlap['sharedSecondaryAcrossPrimaryLines'] == true,
              firstShared || secondShared,
            );
            expect(
              overlap['reason'],
              firstShared || secondShared
                  ? 'shared_secondary_spans_multiple_primary_lines'
                  : 'engine_disagreement_review',
            );
            expect(overlap['startMs'], 2100);
            expect(overlap['endMs'], 2500);
            expect(
              overlap['secondarySegmentChunkIndex'],
              expectedSecond ? 1 : 0,
            );
            expect(overlap['secondarySegments'], [
              {
                'sourceIndex': 7,
                'text': expectedSecond ? 'second evidence' : 'first evidence',
                'startMs': 2100,
                'endMs': 2900,
              },
              'unrecognized legacy entry',
            ]);
            expect((originalSegments[1].first as Map)['startMs'], 100);
            final legacyCandidate =
                candidates.singleWhere((entry) => entry['lineIndex'] == 2)
                    as Map;
            expect(legacyCandidate['alternativeText'], 'independent');
            expect(legacyCandidate.containsKey('secondarySegments'), isFalse);
            expect(
              legacyCandidate.containsKey('secondarySegmentChunkIndex'),
              isFalse,
            );
            final resumed = await service.transcribe(request);
            final resumedCandidates =
                resumed.lyrics.metadata['fallbackCandidates'] as List;
            expect(
              resumedCandidates.singleWhere((entry) => entry['lineIndex'] == 1),
              overlap,
            );
            expect(delegate.outputDirectories, hasLength(2));
          }
        }
      },
    );

    test('chunk merge keeps engine identity and remaps indices', () async {
      final directory = await Directory.systemTemp.createTemp('chunk-merge-');
      addTearDown(() => directory.delete(recursive: true));
      final input = File('${directory.path}${Platform.pathSeparator}song.wav');
      await input.writeAsBytes(List<int>.filled(128, 0));
      final ffmpeg = _FfmpegStub(durationLabel: '00:04:00.000');
      final delegate = _ScriptedService(
        (chunk) => chunk == 0
            ? const LyricDocument(
                language: 'en',
                lines: [
                  LyricLine(
                    text: 'first line',
                    startTime: Duration.zero,
                    endTime: Duration(seconds: 5),
                  ),
                  LyricLine(
                    text: 'second line',
                    startTime: Duration(milliseconds: 175000),
                    endTime: Duration(milliseconds: 179000),
                    confidence: 80,
                  ),
                ],
                metadata: {
                  'qualityMode': 'highestQuality',
                  'primaryEngine': 'qwen3-asr-1.7b',
                  'fallbackCandidates': [
                    {'lineIndex': 1, 'primaryText': 'second line'},
                  ],
                  'secondaryOnlyLineIndices': [1],
                  'suspiciousLineIndexes': [0],
                  'fallbackAppliedCount': 1,
                  'qwenRawJsonPath': '/tmp/chunk_0000/qwen.json',
                  'independentAsrEvidence': {
                    'scope': 'singleInput',
                    'chunkLocal': true,
                  },
                },
              )
            : const LyricDocument(
                language: 'en',
                lines: [
                  LyricLine(
                    text: 'second line',
                    startTime: Duration(seconds: 3),
                    endTime: Duration(seconds: 7),
                    confidence: 90,
                  ),
                  LyricLine(
                    text: 'third line',
                    startTime: Duration(seconds: 60),
                    endTime: Duration(seconds: 64),
                  ),
                ],
                metadata: {
                  'qualityMode': 'highestQuality',
                  'primaryEngine': 'qwen3-asr-1.7b',
                  'fallbackCandidates': [
                    {
                      'lineIndex': 1,
                      'primaryText': 'third line',
                      'startMs': 60000,
                      'endMs': 64000,
                    },
                  ],
                  'secondaryOnlyLineIndices': [1],
                  'suspiciousLineIndexes': [1],
                  'fallbackAppliedCount': 0,
                },
              ),
      );
      final service = ResumableChunkedTranscriptionService(
        delegate: delegate,
        chunkDuration: const Duration(minutes: 3),
        processSupervisor: ffmpeg.supervisor,
      );

      final result = await service.transcribe(
        _request(input.path, directory.path),
      );

      final metadata = result.lyrics.metadata;
      expect(result.lyrics.lines.map((line) => line.text).toList(), [
        'first line',
        'second line',
        'third line',
      ]);
      // The overlap duplicate keeps the more confident copy.
      expect(result.lyrics.lines[1].confidence, 90);
      // Engine identity and quality mode survive the merge (they used to be
      // replaced by a lone mergeStrategy key, which also broke model tracing).
      expect(metadata['primaryEngine'], 'qwen3-asr-1.7b');
      expect(metadata['qualityMode'], 'highestQuality');
      expect(metadata['mergeStrategy'], 'overlapTextAndTimeDedup');
      // Indices follow the merged line list: the second chunk's line 1 became
      // merged line 2 after its first line deduplicated into merged line 1.
      expect(metadata['secondaryOnlyLineIndices'], [1, 2]);
      expect(metadata['secondaryOnlyLineCount'], 2);
      expect(metadata['suspiciousLineIndexes'], [0, 2]);
      expect(metadata['fallbackAppliedCount'], 1);
      expect(metadata['fallbackCandidateCount'], 2);
      expect(
        (metadata['fallbackCandidates'] as List)
            .map((candidate) => (candidate as Map)['lineIndex'])
            .toList(),
        [1, 2],
      );
      // Candidate timestamps must describe the song, not the chunk's local time.
      expect(
        (metadata['fallbackCandidates'] as List).last,
        containsPair('startMs', 232000),
      );
      // A single chunk's artifact path would be a lie about the merged result.
      expect(metadata.containsKey('qwenRawJsonPath'), isFalse);
      expect(metadata.containsKey('independentAsrEvidence'), isFalse);
      expect(metadata['chunked'], isTrue);
      expect(metadata['chunkCount'], 2);
      await service.dispose();
    });

    test(
      'chunk merge deduplicates matching Korean overlap text only',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'chunk-korean-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final input = File(
          '${directory.path}${Platform.pathSeparator}song.wav',
        );
        await input.writeAsBytes(List<int>.filled(128, 0));
        final ffmpeg = _FfmpegStub(durationLabel: '00:04:00.000');
        final delegate = _ScriptedService(
          (chunk) => chunk == 0
              ? const LyricDocument(
                  language: 'ko',
                  lines: [
                    LyricLine(
                      text: '오늘도 너를 기다려',
                      startTime: Duration(seconds: 175),
                      endTime: Duration(seconds: 179),
                      confidence: 80,
                    ),
                  ],
                )
              : const LyricDocument(
                  language: 'ko',
                  lines: [
                    LyricLine(
                      text: '오늘도 너를 기다려',
                      startTime: Duration(seconds: 3),
                      endTime: Duration(seconds: 7),
                      confidence: 90,
                    ),
                    LyricLine(
                      text: '다른 노래 한 줄',
                      startTime: Duration(seconds: 3),
                      endTime: Duration(seconds: 7),
                      confidence: 95,
                    ),
                  ],
                ),
        );
        final service = ResumableChunkedTranscriptionService(
          delegate: delegate,
          chunkDuration: const Duration(minutes: 3),
          processSupervisor: ffmpeg.supervisor,
        );

        final result = await service.transcribe(
          _request(input.path, directory.path),
        );

        expect(result.lyrics.lines.map((line) => line.text).toList(), [
          '오늘도 너를 기다려',
          '다른 노래 한 줄',
        ]);
        // Equal Korean overlap text is still merged and keeps the better copy.
        expect(result.lyrics.lines.first.confidence, 90);
        await service.dispose();
      },
    );

    test(
      'chunk merge preserves real repeats and remaps review evidence',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'chunk-repeats-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final input = File('${directory.path}/song.wav');
        await input.writeAsBytes(List<int>.filled(128, 1));
        final delegate = _ScriptedService((chunk) {
          LyricLine line(
            String text,
            int start,
            int end, [
            int confidence = 50,
          ]) => LyricLine(
            text: text,
            startTime: Duration(milliseconds: start),
            endTime: Duration(milliseconds: end),
            confidence: confidence,
          );
          final lines = chunk == 0
              ? [
                  line('again', 0, 400),
                  line('again', 500, 900),
                  line('echo', 1600, 1900),
                  line('echo', 2100, 2400),
                  line('echo', 2500, 2800),
                ]
              : [
                  line('echo', 100, 400, 90),
                  line('echo', 500, 800, 90),
                  line('echo', 550, 750),
                  line('echo', 1050, 1200),
                ];
          return LyricDocument(
            language: 'en',
            lines: lines,
            metadata: {
              'suspiciousLineIndexes': [
                for (var i = 0; i < lines.length; i++) i,
              ],
              'fallbackCandidates': [
                for (var i = 0; i < lines.length; i++)
                  {'lineIndex': i, 'primaryText': lines[i].text},
              ],
            },
          );
        });
        final service = ResumableChunkedTranscriptionService(
          delegate: delegate,
          chunkDuration: const Duration(seconds: 3),
          overlap: const Duration(seconds: 1),
          processSupervisor: _FfmpegStub(
            durationLabel: '00:00:04.000',
          ).supervisor,
        );
        addTearDown(service.dispose);
        final request = _request(input.path, directory.path);
        final result = await service.transcribe(request);
        expect(result.lyrics.lines.map((line) => line.text), [
          'again',
          'again',
          'echo',
          'echo',
          'echo',
          'echo',
          'echo',
        ]);
        expect(
          result.lyrics.lines.map((line) => line.startTime.inMilliseconds),
          [0, 500, 1600, 2100, 2500, 2550, 3050],
        );
        expect(result.lyrics.lines[3].confidence, 90);
        expect(result.lyrics.lines[4].confidence, 90);
        expect(result.lyrics.metadata['suspiciousLineIndexes'], [
          0,
          1,
          2,
          3,
          4,
          5,
          6,
        ]);
        final candidates = result.lyrics.metadata['fallbackCandidates'] as List;
        expect(candidates.map((c) => (c as Map)['lineIndex']).toSet(), {
          0,
          1,
          2,
          3,
          4,
          5,
          6,
        });
        final resumed = await service.transcribe(request);
        expect(delegate.outputDirectories, hasLength(2));
        expect(
          resumed.lyrics.lines.map((line) => line.startTime.inMilliseconds),
          [0, 500, 1600, 2100, 2500, 2550, 3050],
        );
      },
    );

    test(
      'large overlap deduplicates one occurrence across three chunks',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'chunk-wide-overlap-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final input = File('${directory.path}/song.wav');
        await input.writeAsBytes(List<int>.filled(128, 1));
        final delegate = _ScriptedService(
          (chunk) => LyricDocument(
            language: 'en',
            lines: [
              LyricLine(
                text: 'repeat',
                startTime: Duration(milliseconds: 2100 - chunk * 1000),
                endTime: Duration(milliseconds: 2400 - chunk * 1000),
                confidence: 50 + chunk * 10,
              ),
            ],
            metadata: {
              'suspiciousLineIndexes': [0],
            },
          ),
        );
        final service = ResumableChunkedTranscriptionService(
          delegate: delegate,
          chunkDuration: const Duration(seconds: 3),
          overlap: const Duration(seconds: 2),
          processSupervisor: _FfmpegStub(
            durationLabel: '00:00:05.000',
          ).supervisor,
        );
        addTearDown(service.dispose);
        final result = await service.transcribe(
          _request(input.path, directory.path),
        );
        expect(delegate.outputDirectories, hasLength(3));
        expect(result.lyrics.lines, hasLength(1));
        expect(result.lyrics.lines.single.confidence, 70);
        expect(result.lyrics.metadata['suspiciousLineIndexes'], [0]);
      },
    );

    test('only old dual-engine checkpoints are invalidated', () async {
      final directory = await Directory.systemTemp.createTemp(
        'chunk-old-version-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final input = File('${directory.path}${Platform.pathSeparator}song.wav');
      await input.writeAsBytes(List<int>.filled(128, 0));
      final delegate = _FakeService();
      final ffmpeg = _FfmpegStub(durationLabel: '00:04:00.000');
      final service = ResumableChunkedTranscriptionService(
        delegate: delegate,
        chunkDuration: const Duration(minutes: 3),
        processSupervisor: ffmpeg.supervisor,
      );
      addTearDown(service.dispose);
      final single = _request(
        input.path,
        directory.path,
        config: _config().copyWith(mode: TranscriptionMode.whisperOnly),
      );
      await service.transcribe(single);
      await service.transcribe(single);
      expect(delegate.calls, 2);

      final dual = _request(
        input.path,
        directory.path,
        config: _config().copyWith(mode: TranscriptionMode.highestQuality),
      );
      await service.transcribe(dual);
      expect(delegate.calls, 4);
      final manifest = File(
        '${directory.path}${Platform.pathSeparator}chunk_session${Platform.pathSeparator}session.json',
      );
      final data =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
      data.remove('fallbackEvidenceVersion');
      await manifest.writeAsString(jsonEncode(data));
      await service.transcribe(dual);
      expect(delegate.calls, 6);
      await service.transcribe(dual);
      expect(delegate.calls, 6);
    });

    test('changing recognition settings invalidates checkpoints', () async {
      final directory = await Directory.systemTemp.createTemp('chunk-config-');
      addTearDown(() => directory.delete(recursive: true));
      final input = File('${directory.path}${Platform.pathSeparator}song.wav');
      await input.writeAsBytes(List<int>.filled(128, 0));
      final delegate = _FakeService();
      final ffmpeg = _FfmpegStub(durationLabel: '00:04:00.000');
      final service = ResumableChunkedTranscriptionService(
        delegate: delegate,
        chunkDuration: const Duration(minutes: 3),
        processSupervisor: ffmpeg.supervisor,
      );

      await service.transcribe(
        _request(input.path, directory.path, config: _config()),
      );
      expect(delegate.calls, 2);

      // Identical settings resume instead of rerunning inference.
      await service.transcribe(
        _request(input.path, directory.path, config: _config()),
      );
      expect(delegate.calls, 2);

      // A different model must not replay the previous run's lyrics.
      await service.transcribe(
        _request(
          input.path,
          directory.path,
          config: _config(modelPath: 'large-v3.bin'),
        ),
      );
      expect(delegate.calls, 4);
      await service.dispose();
    });
  });
}

TranscriptionConfig _config({String modelPath = 'model.bin'}) =>
    TranscriptionConfig(whisperExecutable: 'whisper', modelPath: modelPath);

TranscriptionRequest _request(
  String inputPath,
  String outputDirectory, {
  TranscriptionConfig? config,
}) => TranscriptionRequest(
  inputAudioPath: inputPath,
  outputDirectory: outputDirectory,
  config: config ?? _config(),
);

/// Reports a fixed duration for whichever file FFmpeg is asked about and
/// materialises chunk WAVs like the real extractor.
class _FfmpegStub {
  _FfmpegStub({required this.durationLabel});

  final String durationLabel;
  int chunkStartRequests = 0;

  AsrProcessSupervisor get supervisor => AsrProcessSupervisor(
    startProcess: (_, arguments) async {
      final process = _FakeProcess();
      if (arguments.contains('-ss')) {
        chunkStartRequests++;
        await File(arguments.last).writeAsBytes(List<int>.filled(128, 0));
        Timer(const Duration(milliseconds: 1), () => process.finish(0));
      } else {
        Timer(const Duration(milliseconds: 1), () {
          process.emitStderr(
            'Duration: $durationLabel, start: 0.000000, bitrate: 1 kb/s',
          );
          process.finish(0);
        });
      }
      return process;
    },
    streamDrainGrace: const Duration(milliseconds: 10),
  );
}

TranscriptionResult _emptyResult(TranscriptionRequest request) =>
    TranscriptionResult(
      lyrics: const LyricDocument(language: 'en', lines: []),
      normalizedAudioPath: request.inputAudioPath,
      rawJsonPath:
          '${request.outputDirectory}${Platform.pathSeparator}raw.json',
      detectedLanguage: 'en',
    );

class _AsyncService implements TranscriptionService {
  _AsyncService(this.run);

  final Future<TranscriptionResult> Function(
    TranscriptionRequest,
    _AsyncService,
  )
  run;
  final _controller = StreamController<TranscriptionProgress>.broadcast();
  int calls = 0;

  void emit(TranscriptionProgress event) => _controller.add(event);

  @override
  Stream<TranscriptionProgress> get progressStream => _controller.stream;
  @override
  bool get isRunning => false;
  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) {
    calls++;
    return run(request, this);
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() => _controller.close();
}

/// Returns a scripted document per chunk working directory.
class _ScriptedService implements TranscriptionService {
  _ScriptedService(this.documentsForChunk);

  final LyricDocument Function(int chunkIndex) documentsForChunk;
  final _controller = StreamController<TranscriptionProgress>.broadcast();
  final List<String> outputDirectories = <String>[];

  @override
  Stream<TranscriptionProgress> get progressStream => _controller.stream;

  @override
  bool get isRunning => false;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    final chunkIndex = outputDirectories.length;
    outputDirectories.add(request.outputDirectory);
    final document = documentsForChunk(chunkIndex);
    return TranscriptionResult(
      lyrics: document,
      normalizedAudioPath: request.inputAudioPath,
      rawJsonPath:
          '${request.outputDirectory}${Platform.pathSeparator}raw.json',
      detectedLanguage: document.language,
    );
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() => _controller.close();
}

class _FakeService implements TranscriptionService {
  final _controller = StreamController<TranscriptionProgress>.broadcast();
  int calls = 0;

  @override
  Stream<TranscriptionProgress> get progressStream => _controller.stream;

  @override
  bool get isRunning => false;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    calls++;
    return TranscriptionResult(
      lyrics: const LyricDocument(
        language: 'en',
        lines: [
          LyricLine(
            text: 'hello',
            startTime: Duration.zero,
            endTime: Duration(seconds: 1),
          ),
        ],
      ),
      normalizedAudioPath: request.inputAudioPath,
      rawJsonPath:
          '${request.outputDirectory}${Platform.pathSeparator}raw.json',
      detectedLanguage: 'en',
    );
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() => _controller.close();
}

class _FakeProcess implements Process {
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();
  final IOSink _stdin = IOSink(_DiscardingConsumer());
  final List<ProcessSignal> killSignals = <ProcessSignal>[];
  final bool killOnSigterm;
  final bool killOnSigkill;

  _FakeProcess({this.killOnSigterm = true, this.killOnSigkill = true});

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  int get pid => 12345;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killSignals.add(signal);
    if ((signal == ProcessSignal.sigterm && killOnSigterm) ||
        (signal == ProcessSignal.sigkill && killOnSigkill)) {
      finish(137);
    }
    return true;
  }

  void emitStderr(String text) => _stderr.add(utf8.encode(text));

  void finish(int code) {
    if (!_exitCode.isCompleted) _exitCode.complete(code);
    unawaited(_closeStreams());
  }

  Future<void> _closeStreams() async {
    if (!_stdout.isClosed) await _stdout.close();
    if (!_stderr.isClosed) await _stderr.close();
  }
}

class _DiscardingConsumer implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.drain<void>();
  }

  @override
  Future<void> close() async {}
}
