import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/persistence/serial_write_queue.dart';

void main() {
  test('runs writes one after another in the order queued', () async {
    final queue = SerialWriteQueue();
    final first = Completer<void>();
    final log = <String>[];

    final a = queue.run(() async {
      log.add('a start');
      await first.future;
      log.add('a end');
    });
    final b = queue.run(() async => log.add('b'));
    await pumpEventQueue();

    expect(log, ['a start']);
    expect(queue.pending, 2);

    first.complete();
    await Future.wait([a, b]);
    expect(log, ['a start', 'a end', 'b']);
    expect(queue.pending, 0);
  });

  test('a failed write fails only its own caller', () async {
    final queue = SerialWriteQueue();

    final failing = queue.run<void>(() async => throw StateError('disk full'));
    final next = queue.run(() async => 'saved');

    await expectLater(failing, throwsStateError);
    expect(await next, 'saved');
  });

  test(
    'a write that throws synchronously still fails only its caller',
    () async {
      final queue = SerialWriteQueue();

      final failing = queue.run<void>(() => throw ArgumentError('bad payload'));
      final next = queue.run(() async => 1);

      await expectLater(failing, throwsArgumentError);
      expect(await next, 1);
      expect(queue.pending, 0);
    },
  );

  test('idle waits for queued writes and never throws', () async {
    final queue = SerialWriteQueue();
    final gate = Completer<void>();
    var finished = false;

    final failing = queue.run<void>(() async {
      await gate.future;
      finished = true;
      throw StateError('write failed');
    });
    unawaited(failing.catchError((Object _) {}));

    var idle = false;
    unawaited(queue.idle.then((_) => idle = true));
    await pumpEventQueue();
    expect(idle, isFalse);

    gate.complete();
    await queue.idle;
    expect(finished, isTrue);
    expect(idle, isTrue);
  });

  test('idle on an empty queue completes immediately', () async {
    await expectLater(SerialWriteQueue().idle, completes);
  });
}
