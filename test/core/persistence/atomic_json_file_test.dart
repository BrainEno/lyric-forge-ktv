import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/persistence/atomic_json_file.dart';

bool _isCounterDocument(Object? value) =>
    value is Map && value['counter'] is int;

String _document(int counter) => jsonEncode({'counter': counter});

void main() {
  group('AtomicJsonFile', () {
    late Directory root;
    late File destination;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('atomic-json-file-');
      destination = File('${root.path}${Platform.pathSeparator}state.json');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('keeps the previous valid document when replacement fails', () async {
      await destination.writeAsString(_document(1), flush: true);

      await expectLater(
        AtomicJsonFile.write(
          destination,
          _document(2),
          validate: _isCounterDocument,
          onStage: (stage) async {
            final failureStage = Platform.isWindows
                ? AtomicJsonWriteStage.canonicalRemoved
                : AtomicJsonWriteStage.backupPrepared;
            if (stage == failureStage) {
              throw StateError('injected replacement failure');
            }
          },
        ),
        throwsA(isA<StateError>()),
      );

      expect(jsonDecode(await destination.readAsString()), {'counter': 1});
      expect(
        jsonDecode(await AtomicJsonFile.backupFor(destination).readAsString()),
        {'counter': 1},
      );
      expect(await destination.exists(), isTrue);
    });

    test('failure after the temp flush keeps the previous document', () async {
      await destination.writeAsString(_document(1), flush: true);

      await expectLater(
        AtomicJsonFile.write(
          destination,
          _document(2),
          validate: _isCounterDocument,
          onStage: (stage) async {
            if (stage == AtomicJsonWriteStage.temporaryFlushed) {
              throw StateError('injected failure after temporary flush');
            }
          },
        ),
        throwsA(isA<StateError>()),
      );

      expect(jsonDecode(await destination.readAsString()), {'counter': 1});
      expect(await AtomicJsonFile.temporaryFor(destination).exists(), isFalse);
    });

    test(
      'failure after replacement leaves the new document and valid backup',
      () async {
        await destination.writeAsString(_document(1), flush: true);

        await expectLater(
          AtomicJsonFile.write(
            destination,
            _document(2),
            validate: _isCounterDocument,
            onStage: (stage) async {
              if (stage == AtomicJsonWriteStage.canonicalReplaced) {
                throw StateError(
                  'injected failure after canonical replacement',
                );
              }
            },
          ),
          throwsA(isA<StateError>()),
        );

        expect(jsonDecode(await destination.readAsString()), {'counter': 2});
        expect(
          jsonDecode(
            await AtomicJsonFile.backupFor(destination).readAsString(),
          ),
          {'counter': 1},
        );
        expect(
          await AtomicJsonFile.isValidJsonFile(
            destination,
            validate: _isCounterDocument,
          ),
          isTrue,
        );
      },
    );

    test(
      'restores a flushed temporary document when canonical is missing',
      () async {
        await AtomicJsonFile.temporaryFor(
          destination,
        ).writeAsString(_document(3), flush: true);

        final result = await AtomicJsonFile.recoverIfNeeded(
          destination,
          validate: _isCounterDocument,
        );

        expect(result, AtomicJsonRecoveryResult.restoredFromTemporary);
        expect(jsonDecode(await destination.readAsString()), {'counter': 3});
      },
    );

    test(
      'restores the last valid backup when canonical and temp are invalid',
      () async {
        await destination.writeAsString('{broken');
        await AtomicJsonFile.temporaryFor(
          destination,
        ).writeAsString('{also broken');
        await AtomicJsonFile.backupFor(
          destination,
        ).writeAsString(_document(4), flush: true);

        final result = await AtomicJsonFile.recoverIfNeeded(
          destination,
          validate: _isCounterDocument,
        );

        expect(result, AtomicJsonRecoveryResult.restoredFromBackup);
        expect(jsonDecode(await destination.readAsString()), {'counter': 4});
      },
    );

    test(
      'does not overwrite an invalid store without a valid recovery copy',
      () async {
        await destination.writeAsString('{manual recovery may be needed');

        await expectLater(
          AtomicJsonFile.write(
            destination,
            _document(5),
            validate: _isCounterDocument,
          ),
          throwsA(isA<FileSystemException>()),
        );

        expect(
          await destination.readAsString(),
          '{manual recovery may be needed',
        );
      },
    );

    test(
      'keeps the previous document as a backup after a successful update',
      () async {
        await AtomicJsonFile.write(
          destination,
          _document(1),
          validate: _isCounterDocument,
        );
        await AtomicJsonFile.write(
          destination,
          _document(2),
          validate: _isCounterDocument,
        );

        expect(jsonDecode(await destination.readAsString()), {'counter': 2});
        expect(
          jsonDecode(
            await AtomicJsonFile.backupFor(destination).readAsString(),
          ),
          {'counter': 1},
        );
      },
    );
    group('schema versioning', () {
      final validator = AtomicJsonFile.versioned(
        currentVersion: 2,
        validate: _isCounterDocument,
      );

      test('schemaVersionOf reads stamps, rejects malformed ones', () {
        expect(AtomicJsonFile.schemaVersionOf({'counter': 1}), 0);
        expect(AtomicJsonFile.schemaVersionOf({'version': 2}), 2);
        expect(AtomicJsonFile.schemaVersionOf({'version': 2.0}), 2);
        expect(AtomicJsonFile.schemaVersionOf({'version': -1}), -1);
        expect(AtomicJsonFile.schemaVersionOf({'version': 1.5}), -1);
        expect(AtomicJsonFile.schemaVersionOf({'version': '2'}), -1);
        expect(AtomicJsonFile.schemaVersionOf(<Object?>[]), -1);
        expect(AtomicJsonFile.schemaVersionOf(null), -1);
      });

      test('stampSchemaVersion copies without mutating its input', () {
        final payload = <String, dynamic>{'counter': 1, 'version': 7};
        final stamped = AtomicJsonFile.stampSchemaVersion(payload, 2);
        expect(stamped, {'counter': 1, 'version': 2});
        expect(payload, {'counter': 1, 'version': 7});
      });

      test('versioned validator gates newer schema versions', () {
        expect(validator({'counter': 1}), isTrue);
        expect(validator({'counter': 1, 'version': 1}), isTrue);
        expect(validator({'counter': 1, 'version': 2}), isTrue);
        expect(validator({'counter': 1, 'version': 3}), isFalse);
        expect(validator({'counter': 1, 'version': -1}), isFalse);
        expect(validator({'version': 1}), isFalse);
      });

      test('write refuses to overwrite a newer-schema document', () async {
        final future = jsonEncode({'counter': 9, 'version': 99});
        await destination.writeAsString(future, flush: true);

        await expectLater(
          AtomicJsonFile.write(
            destination,
            jsonEncode({'counter': 1, 'version': 2}),
            validate: validator,
          ),
          throwsA(isA<FileSystemException>()),
        );

        expect(await destination.readAsString(), future);
      });

      test('recovery falls back to a readable backup on downgrade', () async {
        await destination.writeAsString(
          jsonEncode({'counter': 9, 'version': 99}),
          flush: true,
        );
        await AtomicJsonFile.backupFor(
          destination,
        ).writeAsString(jsonEncode({'counter': 4, 'version': 1}), flush: true);

        final result = await AtomicJsonFile.recoverIfNeeded(
          destination,
          validate: validator,
        );

        expect(result, AtomicJsonRecoveryResult.restoredFromBackup);
        expect(jsonDecode(await destination.readAsString()), {
          'counter': 4,
          'version': 1,
        });
      });

      test('legacy unstamped documents stay writable and readable', () async {
        await destination.writeAsString(_document(1), flush: true);

        await AtomicJsonFile.write(
          destination,
          jsonEncode({'counter': 2, 'version': 2}),
          validate: validator,
        );

        expect(jsonDecode(await destination.readAsString()), {
          'counter': 2,
          'version': 2,
        });
        expect(
          jsonDecode(
            await AtomicJsonFile.backupFor(destination).readAsString(),
          ),
          {'counter': 1},
        );
      });
    });
  });
}
