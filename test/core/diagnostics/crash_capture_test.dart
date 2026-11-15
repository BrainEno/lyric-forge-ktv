import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/diagnostics/app_logger.dart';
import 'package:lyric_forge_ktv/core/diagnostics/crash_capture.dart';
import 'package:lyric_forge_ktv/core/diagnostics/log_record.dart';
import 'package:lyric_forge_ktv/core/diagnostics/log_redactor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('crash_capture_test');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  CrashRecordStore store({int capacity = 10}) => CrashRecordStore(
    directory: () async => Directory('${root.path}/diagnostics'),
    capacity: capacity,
  );

  CrashRecord crash(int index) => CrashRecord(
    time: DateTime.utc(2026, 11, 15, 0, index),
    source: CrashSource.platform,
    error: 'StateError: $index',
    appVersion: '1.0.0+1',
  );

  group('CrashRecordStore', () {
    test('keeps the most recent records up to capacity', () async {
      final crashes = store(capacity: 3);
      for (var i = 0; i < 5; i++) {
        await crashes.add(crash(i));
      }
      final loaded = await crashes.load();
      expect(loaded.map((item) => item.error), [
        'StateError: 2',
        'StateError: 3',
        'StateError: 4',
      ]);
    });

    test('round-trips every field', () async {
      final crashes = store();
      final record = CrashRecord(
        time: DateTime.utc(2026, 11, 15, 1),
        source: CrashSource.flutter,
        error: 'FlutterError: overflow',
        context: 'during layout',
        stackTrace: '#0 a',
        appVersion: '1.0.0+1',
      );
      await crashes.add(record);
      expect((await crashes.load()).single.toJson(), record.toJson());
    });

    test('a damaged file loads as empty and is replaced on add', () async {
      final directory = Directory('${root.path}/diagnostics');
      await directory.create(recursive: true);
      await File(
        '${directory.path}/${CrashRecordStore.fileName}',
      ).writeAsString('{not json');
      final crashes = store();
      expect(await crashes.load(), isEmpty);
      await crashes.add(crash(1));
      expect(await crashes.load(), hasLength(1));
    });

    test('clear deletes the records', () async {
      final crashes = store();
      await crashes.add(crash(1));
      await crashes.clear();
      expect(await crashes.load(), isEmpty);
    });

    test('tryParse rejects incomplete records', () {
      expect(CrashRecord.tryParse({'time': 'x'}), isNull);
      expect(
        CrashRecord.tryParse({
          'time': '2026-11-15T00:00:00Z',
          'source': 'nuclear',
          'error': 'x',
        }),
        isNull,
      );
      expect(
        CrashRecord.tryParse({
          'time': '2026-11-15T00:00:00Z',
          'source': 'flutter',
          'error': 'x',
        })!.appVersion,
        'unknown',
      );
    });
  });

  group('installCrashCapture', () {
    late AppLogger logger;
    late CrashRecordStore crashes;
    late List<FlutterErrorDetails> forwarded;
    late FlutterExceptionHandler? originalFlutterHandler;
    late VoidCallback uninstall;

    setUp(() {
      logger = AppLogger(
        sinks: [MemoryLogSink()],
        redactor: LogRedactor(homeDirectories: ['/Users/alice']),
      );
      crashes = store();
      forwarded = [];
      originalFlutterHandler = FlutterError.onError;
      FlutterError.onError = forwarded.add;
    });

    tearDown(() {
      FlutterError.onError = originalFlutterHandler;
    });

    test('logs and stores Flutter errors, then forwards them', () async {
      final before = FlutterError.onError;
      uninstall = installCrashCapture(
        logger: logger,
        store: crashes,
        appVersion: '9.9.9',
      );
      final details = FlutterErrorDetails(
        exception: StateError('render failed at /Users/alice/x'),
        stack: StackTrace.fromString('#0 build'),
        context: ErrorDescription('while building Foo'),
      );
      FlutterError.onError!(details);
      uninstall();

      expect(forwarded, [details]);
      final record = logger.memory!.records.single;
      expect(record.level, LogLevel.error);
      expect(record.tag, 'crash');
      expect(record.message, 'Uncaught flutter error (while building Foo)');
      expect(record.error, contains('~/x'));

      final stored = (await crashes.load()).single;
      expect(stored.source, CrashSource.flutter);
      expect(stored.appVersion, '9.9.9');
      expect(stored.context, 'while building Foo');
      expect(stored.error, isNot(contains('alice')));
      expect(stored.stackTrace, '#0 build');
      expect(FlutterError.onError, same(before));
    });

    test('handles platform errors and restores previous handlers', () async {
      final dispatcher = PlatformDispatcher.instance;
      final previous = dispatcher.onError;
      uninstall = installCrashCapture(
        logger: logger,
        store: crashes,
        appVersion: '9.9.9',
      );
      final handled = dispatcher.onError!(
        StateError('async boom'),
        StackTrace.fromString('#0 tick'),
      );
      uninstall();

      expect(handled, isTrue);
      expect(dispatcher.onError, previous);
      expect(logger.memory!.records.single.message, 'Uncaught platform error');
      expect((await crashes.load()).single.source, CrashSource.platform);
    });

    test('shouldStore=false still logs but keeps no record', () async {
      uninstall = installCrashCapture(
        logger: logger,
        store: crashes,
        appVersion: '9.9.9',
        shouldStore: () => false,
      );
      FlutterError.onError!(FlutterErrorDetails(exception: StateError('x')));
      uninstall();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(logger.memory!.records, hasLength(1));
      expect(await crashes.load(), isEmpty);
    });
  });
}
