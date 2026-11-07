import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:just_audio_media_kit/src/audio_player_setup.dart';

void main() {
  test('configuration keeps audio-only OSC workaround and forwards options',
      () {
    final originalPitch = JustAudioMediaKit.pitch;
    final originalTitle = JustAudioMediaKit.title;
    final originalBufferSize = JustAudioMediaKit.bufferSize;
    final originalProtocols = JustAudioMediaKit.protocolWhitelist;
    addTearDown(() {
      JustAudioMediaKit.pitch = originalPitch;
      JustAudioMediaKit.title = originalTitle;
      JustAudioMediaKit.bufferSize = originalBufferSize;
      JustAudioMediaKit.protocolWhitelist = originalProtocols;
    });
    JustAudioMediaKit.pitch = false;
    JustAudioMediaKit.title = 'test player';
    JustAudioMediaKit.bufferSize = 123456;
    JustAudioMediaKit.protocolWhitelist = ['file', 'https'];
    var readyCalls = 0;

    final configuration = audioPlayerConfiguration(() => readyCalls++);
    expect(configuration.osc, isTrue);
    expect(configuration.pitch, isFalse);
    expect(configuration.title, 'test player');
    expect(configuration.bufferSize, 123456);
    expect(configuration.protocolWhitelist, ['file', 'https']);
    expect(configuration.logLevel, JustAudioMediaKit.mpvLogLevel);
    configuration.ready!();
    expect(readyCalls, 1);
  });

  test('readiness precedes ordered MPV options and awaits each write',
      () async {
    final ready = Completer<void>();
    final firstWrite = Completer<void>();
    final writes = <String>[];
    var completed = false;
    final operation = prepareAudioPlayer(ready.future, (name, value) async {
      writes.add('$name=$value');
      if (name == 'cache-on-disk') await firstWrite.future;
    }).then((_) => completed = true);

    await Future<void>.delayed(Duration.zero);
    expect(writes, isEmpty);
    expect(completed, isFalse);
    ready.complete();
    await Future<void>.delayed(Duration.zero);
    expect(writes, ['cache-on-disk=no']);
    expect(completed, isFalse);
    firstWrite.complete();
    await operation;
    expect(writes, ['cache-on-disk=no', 'sub-auto=no']);
    expect(completed, isTrue);
  });

  test('failed property write propagates without applying later options',
      () async {
    final writes = <String>[];
    final operation =
        prepareAudioPlayer(Future<void>.value(), (name, value) async {
      writes.add(name);
      throw StateError('MPV option failed');
    });
    await expectLater(operation, throwsStateError);
    expect(writes, ['cache-on-disk']);
  });

  test('failed readiness never attempts MPV options', () async {
    final writes = <String>[];
    await expectLater(
      prepareAudioPlayer(Future<void>.error(StateError('not ready')),
          (name, value) async {
        writes.add(name);
      }),
      throwsStateError,
    );
    expect(writes, isEmpty);
  });
}
