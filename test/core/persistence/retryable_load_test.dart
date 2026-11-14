import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/persistence/retryable_load.dart';

void main() {
  test('concurrent callers share a single attempt', () async {
    var calls = 0;
    final gate = Completer<void>();
    final load = RetryableLoad(() async {
      calls++;
      await gate.future;
    });

    final first = load.ensureLoaded();
    final second = load.ensureLoaded();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(load.isLoaded, isFalse);

    gate.complete();
    await Future.wait([first, second]);
    expect(load.isLoaded, isTrue);

    await load.ensureLoaded();
    expect(calls, 1);
  });

  test('a failed attempt is not cached and the next call retries', () async {
    var calls = 0;
    final load = RetryableLoad(() async {
      calls++;
      if (calls == 1) throw StateError('temporary permission problem');
    });

    await expectLater(load.ensureLoaded(), throwsStateError);
    expect(load.isLoaded, isFalse);

    await load.ensureLoaded();
    expect(calls, 2);
    expect(load.isLoaded, isTrue);
  });

  test('callers waiting on a failing attempt all see that failure', () async {
    var calls = 0;
    final gate = Completer<void>();
    final load = RetryableLoad(() async {
      calls++;
      await gate.future;
      if (calls == 1) throw const FormatException('changed while loading');
    });

    final first = load.ensureLoaded();
    final second = load.ensureLoaded();
    gate.complete();
    await expectLater(first, throwsFormatException);
    await expectLater(second, throwsFormatException);
    expect(calls, 1);

    await load.ensureLoaded();
    expect(calls, 2);
  });

  test('a loader that throws synchronously is still retried', () async {
    var calls = 0;
    Future<void> loader() {
      calls++;
      if (calls == 1) throw StateError('synchronous failure');
      return Future<void>.value();
    }

    final load = RetryableLoad(loader);
    await expectLater(load.ensureLoaded(), throwsStateError);
    await load.ensureLoaded();
    expect(calls, 2);
    expect(load.isLoaded, isTrue);
  });
}
